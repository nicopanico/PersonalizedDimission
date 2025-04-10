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

        % Colonna 2: Scenari
        ScenariPanel             matlab.ui.container.Panel
        RestrittiviPanel         matlab.ui.container.Panel
        PartnerCheckBox          matlab.ui.control.CheckBox
        IncintaCheckBox          matlab.ui.control.CheckBox
        MadreCheckBox            matlab.ui.control.CheckBox
        CollegaCheckBox          matlab.ui.control.CheckBox
        CaregiverCheckBox        matlab.ui.control.CheckBox

        OrdinariPanel            matlab.ui.container.Panel
        PartnerOrdCheckBox       matlab.ui.control.CheckBox
        IncintaOrdCheckBox       matlab.ui.control.CheckBox
        MadreOrdCheckBox         matlab.ui.control.CheckBox
        CollegaOrdCheckBox       matlab.ui.control.CheckBox
        CaregiverOrdCheckBox     matlab.ui.control.CheckBox

        % Colonna 3: Risultati
        RisultatiPanel           matlab.ui.container.Panel
        RisultatiTextArea        matlab.ui.control.TextArea
        PlotDoseButton           matlab.ui.control.Button
    end

    properties (Access = private)
        modello       % Oggetto ModelloLineare
        scenarioMap   % Mappa (restrittivo -> ordinario) per linkare scenari
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
            if app.PartnerCheckBox.Value
                restrName = 'Partner';
            elseif app.IncintaCheckBox.Value
                restrName = 'Incinta';
            elseif app.MadreCheckBox.Value
                restrName = 'Madre';
            elseif app.CollegaCheckBox.Value
                restrName = 'Collega';
            elseif app.CaregiverCheckBox.Value
                restrName = 'Caregiver';
            end
            if isempty(restrName)
                uialert(app.UIFigure, 'Seleziona uno scenario restrittivo.', 'Attenzione');
                return;
            end

            restrFunc = DoseApp.scenarioStr2Func(restrName);
            restr = restrFunc(app.modello);

            % Ordinario corrispondente
            if isfield(app.scenarioMap, restrName)
                ordName = app.scenarioMap.(restrName);
                ordFunc = DoseApp.scenarioStr2Func(ordName);
                ord = ordFunc(app.modello);
            else
                ord = Scenario('Nessun Ordinario',[],[],app.modello,0);
            end

            % Calcola e plotta
            dc = DoseCalculator(restr, ord, fk, R_Tdis);
            app.plotDoseCurve(dc, restr, ord, fk, R_Tdis, selectedRF);
        end

        function CalcolaDoseButtonPushed(app, ~)
            T_discharge = app.TDischargeField.Value;  % giorni
            R_Tdis      = app.R_TdisField.Value;       % µSv/h a 1 m
            attivita    = app.AttivitaField.Value;
            selectedRF  = app.RadiofarmacoDropDown.Value;

            restrNames = {};
            if app.PartnerCheckBox.Value
                restrNames{end+1} = 'Partner'; end
            if app.IncintaCheckBox.Value
                restrNames{end+1} = 'Incinta'; end
            if app.MadreCheckBox.Value
                restrNames{end+1} = 'Madre'; end
            if app.CollegaCheckBox.Value
                restrNames{end+1} = 'Collega'; end
            if app.CaregiverCheckBox.Value
                restrNames{end+1} = 'Caregiver'; end

            ordNames = {};
            if app.PartnerOrdCheckBox.Value
                ordNames{end+1} = 'Ordinario_Partner'; end
            if app.IncintaOrdCheckBox.Value
                ordNames{end+1} = 'Ordinario_Incinta'; end
            if app.MadreOrdCheckBox.Value
                ordNames{end+1} = 'Ordinario_Madre'; end
            if app.CollegaOrdCheckBox.Value
                ordNames{end+1} = 'Ordinario_Collega'; end
            if app.CaregiverOrdCheckBox.Value
                ordNames{end+1} = 'Ordinario_Caregiver'; end

            if isempty(restrNames)
                app.RisultatiTextArea.Value = "Seleziona almeno uno scenario restrittivo.";
                return;
            end

            resultsStr = {};
            idx = 1;
            for i = 1:length(restrNames)
                rName = restrNames{i};
                if isfield(app.scenarioMap, rName)
                    ordCandidate = app.scenarioMap.(rName);
                    if ismember(ordCandidate, ordNames)
                        res = calcolateTime(T_discharge, R_Tdis, selectedRF, ...
                                            DoseApp.scenarioStr2Func(rName), ...
                                            DoseApp.scenarioStr2Func(ordCandidate), ...
                                            app.modello, attivita);
                        resultsStr{idx} = sprintf("Restr: %s + Ord: %s --> Dose: %.3f mSv, T_res: %.2f gg", ...
                            rName, ordCandidate, res.dose_totale, res.Tres_ott);
                    else
                        res = calcolateTime(T_discharge, R_Tdis, selectedRF, ...
                                            DoseApp.scenarioStr2Func(rName), [], ...
                                            app.modello, attivita);
                        resultsStr{idx} = sprintf("Restr: %s (no Ord) --> Dose: %.3f mSv, T_res: %.2f gg", ...
                            rName, res.dose_totale, res.Tres_ott);
                    end
                else
                    % non esiste la chiave
                    res = calcolateTime(T_discharge, R_Tdis, selectedRF, ...
                                        DoseApp.scenarioStr2Func(rName), [], ...
                                        app.modello, attivita);
                    resultsStr{idx} = sprintf("Restr: %s (no Ord corrispondente) --> Dose: %.3f mSv, T_res: %.2f gg", ...
                        rName, res.dose_totale, res.Tres_ott);
                end
                idx = idx + 1;
            end
            app.RisultatiTextArea.Value = resultsStr(:);
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
                dose_restr(j) = R_Tdis * sum_r / 1000;
                dose_ordin(j) = R_Tdis * sum_o / 1000;
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
            % QUI USO Il MODELLO con H=1.70, gamma calcolata
            app.modello = ModelloLineare(1.70);

            app.scenarioMap = struct( ...
                'Partner',   'Ordinario_Partner', ...
                'Incinta',   'Ordinario_Incinta', ...
                'Madre',     'Ordinario_Madre', ...
                'Collega',   'Ordinario_Collega', ...
                'Caregiver', 'Ordinario_Caregiver');

            registerApp(app, app.UIFigure);
            if nargout == 0
                clear app;
            end
        end

        function delete(app)
            delete(app.UIFigure);
        end
    end

    methods (Static)
        function funcHandle = scenarioStr2Func(str)
            switch str
                case 'Partner'
                    funcHandle = @Scenario.Partner;
                case 'Incinta'
                    funcHandle = @Scenario.Incinta;
                case 'Madre'
                    funcHandle = @Scenario.Madre;
                case 'Collega'
                    funcHandle = @Scenario.Collega;
                case 'Caregiver'
                    funcHandle = @Scenario.Caregiver;
                case 'Ordinario_Partner'
                    funcHandle = @Scenario.Ordinario_Partner;
                case 'Ordinario_Incinta'
                    funcHandle = @Scenario.Ordinario_Incinta;
                case 'Ordinario_Madre'
                    funcHandle = @Scenario.Ordinario_Madre;
                case 'Ordinario_Collega'
                    funcHandle = @Scenario.Ordinario_Collega;
                case 'Ordinario_Caregiver'
                    funcHandle = @Scenario.Ordinario_Caregiver;
                otherwise
                    error('Scenario non riconosciuto: %s', str);
            end
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

            %% Colonna 2 - Scenari
            app.ScenariPanel = uipanel(app.GridLayout, 'Title','Scenari');
            app.ScenariPanel.Layout.Column = 2;

            gl2 = uigridlayout(app.ScenariPanel, [2,1]);
            gl2.RowHeight = {'fit','fit'};

            % SCENARI RISTRETTIVI
            app.RestrittiviPanel = uipanel(gl2, 'Title','Scenari Restrittivi');
            gl2a = uigridlayout(app.RestrittiviPanel, [5,1]);
            app.PartnerCheckBox    = uicheckbox(gl2a, 'Text','Partner in piccolo appartamento');
            app.IncintaCheckBox    = uicheckbox(gl2a, 'Text','Donna incinta convivente');
            app.MadreCheckBox      = uicheckbox(gl2a, 'Text','Madre con bambino');
            app.CollegaCheckBox    = uicheckbox(gl2a, 'Text','Collega di lavoro');
            app.CaregiverCheckBox  = uicheckbox(gl2a, 'Text','Caregiver a domicilio');

            % SCENARI ORDINARI
            app.OrdinariPanel = uipanel(gl2, 'Title','Scenari Ordinari');
            gl2b = uigridlayout(app.OrdinariPanel, [5,1]);
            app.PartnerOrdCheckBox     = uicheckbox(gl2b, 'Text','Ord. Partner');
            app.IncintaOrdCheckBox     = uicheckbox(gl2b, 'Text','Ord. Donna incinta');
            app.MadreOrdCheckBox       = uicheckbox(gl2b, 'Text','Ord. Madre con figlio');
            app.CollegaOrdCheckBox     = uicheckbox(gl2b, 'Text','Ord. Collega');
            app.CaregiverOrdCheckBox   = uicheckbox(gl2b, 'Text','Ord. Caregiver');

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



