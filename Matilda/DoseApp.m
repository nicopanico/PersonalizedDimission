classdef DoseApp < matlab.apps.AppBase

    properties (Access = public)
        UIFigure                 matlab.ui.Figure
        GridLayout               matlab.ui.container.GridLayout

        % Colonna 1: Parametri Clinici
        ParametriPanel           matlab.ui.container.Panel
        TDischargeLabel          matlab.ui.control.Label
        TDischargeField          matlab.ui.control.NumericEditField
        RTdisLabel               matlab.ui.control.Label
        R_TdisField              matlab.ui.control.NumericEditField
        AttivitaLabel            matlab.ui.control.Label
        AttivitaField            matlab.ui.control.NumericEditField

        RadiofarmacoPanel        matlab.ui.container.Panel
        RadiofarmacoDropDown     matlab.ui.control.DropDown
        CalcolaDoseButton        matlab.ui.control.Button

        % Colonna Scenari (unica)
        ScenariPanel         matlab.ui.container.Panel
        PartnerCheckBox      matlab.ui.control.CheckBox
        TrasportoCheckBox    matlab.ui.control.CheckBox
        Bambino02CheckBox    matlab.ui.control.CheckBox
        Bambino25CheckBox    matlab.ui.control.CheckBox
        Bambino511CheckBox   matlab.ui.control.CheckBox
        IncintaCheckBox      matlab.ui.control.CheckBox
        ColleghiCheckBox     matlab.ui.control.CheckBox

        % Colonna 3: Risultati
        RisultatiPanel           matlab.ui.container.Panel
        RisultatiTextArea        matlab.ui.control.TextArea
        PlotDoseButton           matlab.ui.control.Button
    end

    properties (Access = private)
        modello       % Oggetto ModelloLineare
        pairMap       % Mappa nome->factory restrittivo    
        pairMapOrd
    end
    methods (Access = private)

        function PlotDoseButtonPushed(app)
            % Prende parametri clinici e scenario selezionato
            T_discharge = app.TDischargeField.Value;   % in giorni
            R_Tdis = app.R_TdisField.Value;            % µSv/h @1m
            selectedRF = app.RadiofarmacoDropDown.Value;

            % Carica la farmacocinetica
            rph = loadRadiopharmaceutical(selectedRF, 'radiopharmaceuticals.json');
            fk = Farmacocinetica(rph.fr, rph.lambda_eff);

            % T_discharge in giorni e lambda_eff in 1/giorno => nessuna *24
            fk = fk.aggiornaFrazioni(T_discharge);

            % Trova un singolo scenario restrittivo
           restrName = '';
           if     app.PartnerCheckBox.Value,    restrName = 'Partner';
           elseif app.TrasportoCheckBox.Value,  restrName = 'Trasporto';
           elseif app.Bambino02CheckBox.Value,  restrName = 'Bambino02';
           elseif app.Bambino25CheckBox.Value,  restrName = 'Bambino25';
           elseif app.Bambino511CheckBox.Value, restrName = 'Bambino511';
           elseif app.IncintaCheckBox.Value,    restrName = 'Incinta';
           elseif app.ColleghiCheckBox.Value,   restrName = 'Colleghi';
           end

            if isempty(restrName)
                uialert(app.UIFigure, 'Seleziona uno scenario restrittivo.', 'Attenzione');
                return;
            end

            restr = app.pairMap.(restrName)(app.modello);
            ord   = app.pairMapOrd.(restrName)(app.modello);

            % Calcola e plotta
            dc = DoseCalculator(restr, ord, fk, R_Tdis);
            app.plotDoseCurve(dc, restr, ord, fk, R_Tdis, selectedRF);
        end

        function CalcolaDoseButtonPushed(app, ~)
            names = {};
            if app.PartnerCheckBox.Value,    names{end+1} = 'Partner';    end
            if app.TrasportoCheckBox.Value,  names{end+1} = 'Trasporto';  end
            if app.Bambino02CheckBox.Value,  names{end+1} = 'Bambino02';  end
            if app.Bambino25CheckBox.Value,  names{end+1} = 'Bambino25';  end
            if app.Bambino511CheckBox.Value, names{end+1} = 'Bambino511'; end
            if app.IncintaCheckBox.Value,    names{end+1} = 'Incinta';    end
            if app.ColleghiCheckBox.Value,   names{end+1} = 'Colleghi';   end

            if isempty(names)
                app.RisultatiTextArea.Value = "Seleziona almeno uno scenario.";
                return;
            end

            T_dis  = app.TDischargeField.Value;
            R_Tdis = app.R_TdisField.Value;
            RF     = app.RadiofarmacoDropDown.Value;

            results = {};
            for k = 1:numel(names)
                restr = app.pairMap.(names{k})(app.modello);
                ord   = app.pairMapOrd.(names{k})(app.modello);
                rph = loadRadiopharmaceutical(RF,'radiopharmaceuticals.json');
                fk  = Farmacocinetica(rph.fr,rph.lambda_eff).aggiornaFrazioni(T_dis);

                dc  = DoseCalculator(restr,ord,fk,R_Tdis);
                Tres = dc.trovaPeriodoRestrizione(restr.DoseConstraint);
                results{k} = sprintf('%s  →  T_res = %.1f gg, Dose7g = %.2f mSv', ...
                    restr.nome, Tres, dc.calcolaDoseTotale(7));
            end
            app.RisultatiTextArea.Value = results.';
        end
    end


    methods (Access = private)
        function plotDoseCurve(app, dc, restr, ord, fk, R_Tdis, selectedRF)
            % Trova T_res ottimale
            Tres_opt = dc.trovaPeriodoRestrizione(restr.DoseConstraint);

            % Vettr di T_res in giorni
            Tres_values = linspace(0.1, 60, 300);
            dose_tot   = zeros(size(Tres_values));
            dose_restr = zeros(size(Tres_values));
            dose_ordin = zeros(size(Tres_values));

            % calcola Fcorr per scenario restr e ordinario
            F_r = restr.calcolaFcorrScenario(1);
            F_o = ord.calcolaFcorrScenario(1);

            % Niente *24 negli esponenziali perché lambda_eff è in 1/giorno
            for j = 1:length(Tres_values)
                T = Tres_values(j);  % in giorni
                sum_r = 0; sum_o = 0;
                for i = 1:length(fk.fr)
                    fr_i = fk.fr(i);
                    lambda_i = fk.lambda_eff(i);
                    
                    % dose fase restrittiva (0 -> T)
                    d_r = (fr_i / lambda_i) * F_r * (1 - exp(-lambda_i * T));
                    % dose fase ordinaria (T -> inf)
                    d_o = (fr_i / lambda_i) * F_o * exp(-lambda_i * T);
                    
                    sum_r = sum_r + d_r;
                    sum_o = sum_o + d_o;
                end
                % Moltiplico per R_Tdis (µSv/h) e converto in mSv (/1000).
                % Attenzione: R_Tdis è un rate in µSv/h @ T_dis, 
                % ma qui la formula di Buonamici è normalizzata in 1/giorno. 
                % => usiamo la stessa identica formula di calcolaDoseTotale() 
                dose_restr(j) = R_Tdis *24* sum_r / 1000;
                dose_ordin(j) = R_Tdis *24* sum_o / 1000;
                dose_tot(j)   = dose_restr(j) + dose_ordin(j);
            end

            % Calcola la dose al T_res ottimale
            dose_opt = dc.calcolaDoseTotale(Tres_opt);

            figure('Name','Dose vs T_{res}');
            plot(Tres_values, dose_tot,'b-','LineWidth',2); hold on;
            plot(Tres_values, dose_restr,'g--','LineWidth',1.5);
            plot(Tres_values, dose_ordin,'m-.','LineWidth',1.5);

            yline(restr.DoseConstraint, 'r--', 'Limite di dose', 'LineWidth',1.2);
            plot(Tres_opt, dose_opt, 'ko', 'MarkerSize',8, 'MarkerFaceColor','k');
            text(Tres_opt, dose_opt, sprintf('  T_{res}^{opt} = %.2f gg', Tres_opt), ...
                'VerticalAlignment','bottom','FontSize',10,'FontWeight','bold');

            xlabel('Tempo di restrizione T_{res} [giorni]');
            ylabel('Dose [mSv]');
            legend('Dose totale','Fase restrittiva','Fase ordinaria','Limite','T_{res}^{opt}');
            title(['Dose stimata per ', selectedRF, ' - Scenario: ', restr.nome]);
            grid on;
        end
    end

    methods (Access = public)
        function app = DoseApp
            createComponents(app);

            % Modello lineare con altezza 1.70 m (Γ calcolata)
            app.modello = ModelloLineare(1.70);

            % Nuova mappa: nome checkbox → factory dello SCENARIO RESTRITTIVO
            % (l’ordinario è sempre Scenario.OrdinarioBasico)
            app.pairMap = struct( ...
                'Partner',    @Scenario.Partner, ...
                'Trasporto',  @Scenario.TrasportoPubblico, ...
                'Bambino02',  @Scenario.Bambino_0_2, ...
                'Bambino25',  @Scenario.Bambino_2_5, ...
                'Bambino511', @Scenario.Bambino_5_11, ...
                'Incinta',    @Scenario.DonnaIncinta, ...
                'Colleghi',   @Scenario.NessunaRestr );
            app.pairMapOrd = struct( ...
                'Partner',    @Scenario.Ordinario_Partner, ...
                'Trasporto',  @Scenario.Ordinario_Trasporto, ...
                'Bambino02',  @Scenario.Ordinario_Bambino, ...
                'Bambino25',  @Scenario.Ordinario_Bambino, ...
                'Bambino511', @Scenario.Ordinario_Bambino, ...
                'Incinta',    @Scenario.Ordinario_Incinta, ...
                'Colleghi',   @Scenario.Ordinario_Colleghi );

            registerApp(app, app.UIFigure);
            if nargout == 0, clear app; end
        end
        

        function delete(app)
            delete(app.UIFigure);
        end
    end


    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name','DoseApp','Position',[100 100 1000 600]);

            app.GridLayout = uigridlayout(app.UIFigure, [1,3]);
            app.GridLayout.ColumnWidth = {'fit','1x','1.5x'};

            %% Colonna 1 - Parametri Clinici
            app.ParametriPanel = uipanel(app.GridLayout, 'Title','Parametri Clinici');
            app.ParametriPanel.Layout.Column = 1;

            gl1 = uigridlayout(app.ParametriPanel, [5,2]);
            gl1.RowHeight = repmat({'fit'},1,5);
            gl1.ColumnWidth = {'fit','1x'};

            app.TDischargeLabel = uilabel(gl1, 'Text','T_{discharge} (giorni)');
            app.TDischargeLabel.Layout.Row = 1; app.TDischargeLabel.Layout.Column = 1;
            app.TDischargeField = uieditfield(gl1, 'numeric', 'Value', 1);
            app.TDischargeField.Layout.Row = 1; app.TDischargeField.Layout.Column = 2;

            app.RTdisLabel = uilabel(gl1, 'Text','R_{Tdis} (µSv/h)'); 
            app.RTdisLabel.Layout.Row = 2; app.RTdisLabel.Layout.Column = 1;
            app.R_TdisField = uieditfield(gl1, 'numeric', 'Value', 25);
            app.R_TdisField.Layout.Row = 2; app.R_TdisField.Layout.Column = 2;

            app.AttivitaLabel = uilabel(gl1, 'Text','Attività (MBq)');
            app.AttivitaLabel.Layout.Row = 3; app.AttivitaLabel.Layout.Column = 1;
            app.AttivitaField = uieditfield(gl1, 'numeric', 'Value', 740);
            app.AttivitaField.Layout.Row = 3; app.AttivitaField.Layout.Column = 2;

            app.RadiofarmacoPanel = uipanel(gl1, 'Title','Radiofarmaco');
            app.RadiofarmacoPanel.Layout.Row = [4 5]; app.RadiofarmacoPanel.Layout.Column = [1 2];

            app.RadiofarmacoDropDown = uidropdown(app.RadiofarmacoPanel, ...
                'Items', {'I-131 Carcinoma Tiroideo', 'I-131 Ipotiroidismo', ...
                'Lu-177-DOTATATE', 'Lu-177-PSMA'}, ...
                'Position', [10 35 200 22]);

            app.CalcolaDoseButton = uibutton(app.RadiofarmacoPanel, 'push', ...
                'Text','Calcola Dose', ...
                'Position',[10 5 120 28], ...
                'ButtonPushedFcn',@(btn,event) CalcolaDoseButtonPushed(app,event));

            app.PlotDoseButton = uibutton(app.RadiofarmacoPanel, 'push', ...
                'Text','Grafico Dose', ...
                'Position',[140 5 120 28], ...
                'ButtonPushedFcn', @(btn,event) PlotDoseButtonPushed(app));

            %% Colonna 2 – Scenari di esposizione
            app.ScenariPanel = uipanel(app.GridLayout,'Title','Scenari di esposizione');
            app.ScenariPanel.Layout.Column = 2;
            glSc = uigridlayout(app.ScenariPanel,[7,1]);

            app.PartnerCheckBox    = uicheckbox(glSc,'Text','Partner');
            app.TrasportoCheckBox  = uicheckbox(glSc,'Text','Trasporto pubblico');
            app.Bambino02CheckBox  = uicheckbox(glSc,'Text','Bambino <2 aa');
            app.Bambino25CheckBox  = uicheckbox(glSc,'Text','Bambino 2–5 aa');
            app.Bambino511CheckBox = uicheckbox(glSc,'Text','Bambino 5–11 aa');
            app.IncintaCheckBox    = uicheckbox(glSc,'Text','Donna incinta');
            app.ColleghiCheckBox   = uicheckbox(glSc,'Text','Colleghi lavoro');


            %% Colonna 3 - Risultati
            app.RisultatiPanel = uipanel(app.GridLayout, 'Title','Risultati');
            app.RisultatiPanel.Layout.Column = 3;
            gl3 = uigridlayout(app.RisultatiPanel, [1,1]);
            app.RisultatiTextArea = uitextarea(gl3);
            app.RisultatiTextArea.Layout.Row = 1;
            app.RisultatiTextArea.Layout.Column = 1;
            app.RisultatiTextArea.Value = "Risultati...";
            app.RisultatiTextArea.Value = {'Risultati...'};
        end
    end
end



