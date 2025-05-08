classdef DoseApp < matlab.apps.AppBase

    properties (Access = public)
        UIFigure          matlab.ui.Figure
        GridLayout        matlab.ui.container.GridLayout

        % --- Col. 1 : parametri clinici
        ParametriPanel    matlab.ui.container.Panel
        TDischargeLabel   matlab.ui.control.Label
        TDischargeField   matlab.ui.control.NumericEditField
        RTdisLabel        matlab.ui.control.Label
        R_TdisField       matlab.ui.control.NumericEditField
        AttivitaLabel     matlab.ui.control.Label
        AttivitaField     matlab.ui.control.NumericEditField
        RadiofarmacoPanel matlab.ui.container.Panel
        RadiofarmacoDropDown matlab.ui.control.DropDown
        CalcolaDoseButton matlab.ui.control.Button

        % --- Col. 2 : scenari
        ScenariPanel      matlab.ui.container.Panel
        PartnerCheckBox   matlab.ui.control.CheckBox
        TrasportoCheckBox matlab.ui.control.CheckBox
        Bambino02CheckBox matlab.ui.control.CheckBox
        Bambino25CheckBox matlab.ui.control.CheckBox
        Bambino511CheckBox matlab.ui.control.CheckBox
        IncintaCheckBox   matlab.ui.control.CheckBox
        ColleghiCheckBox  matlab.ui.control.CheckBox
        WorkDistGroup     matlab.ui.container.ButtonGroup   % nuovo
        StandardRadio     matlab.ui.control.RadioButton     % nuovo
        DueMetriRadio     matlab.ui.control.RadioButton     % nuovo

        % --- Col. 3 : risultati
        RisultatiPanel    matlab.ui.container.Panel
        RisultatiTextArea matlab.ui.control.TextArea
        PlotDoseButton    matlab.ui.control.Button
    end

    properties (Access = private)
        modello    % Oggetto ModelloLineare
        pairMap    % factory restrittivi
        pairMapOrd % factory ordinari
    end

    % ========================= CALLBACKS =========================
    methods (Access = private)
    
    function PlotDoseButtonPushed(app)
        % --- parametri clinici
        T_discharge = app.TDischargeField.Value;
        R_Tdis      = app.R_TdisField.Value;
        selectedRF  = app.RadiofarmacoDropDown.Value;

        % --- farmacocinetica
        rph = loadRadiopharmaceutical(selectedRF,'radiopharmaceuticals.json');
        fk  = Farmacocinetica(rph.fr,rph.lambda_eff).aggiornaFrazioni(T_discharge);

        % --- scenario scelto
        restrName = app.getScenarioSelected();
        if isempty(restrName)
            uialert(app.UIFigure,'Seleziona uno scenario.','Attenzione'); return;
        end
        restr = app.pairMap.(restrName)(app.modello);
        ord   = app.selectOrdScenario(restrName);       % <— logica nuova

        % --- calcolo e grafico
        dc = DoseCalculator(restr,ord,fk,R_Tdis);
        dc.plotDoseCurve(fk,selectedRF);   
    end

    function CalcolaDoseButtonPushed(app,~)
        names = app.getAllSelected();
        if isempty(names)
            app.RisultatiTextArea.Value = "Seleziona almeno uno scenario."; return;
        end

        T_dis  = app.TDischargeField.Value;
        R_Tdis = app.R_TdisField.Value;
        RF     = app.RadiofarmacoDropDown.Value;

        rph = loadRadiopharmaceutical(RF,'radiopharmaceuticals.json');
        fk0 = Farmacocinetica(rph.fr,rph.lambda_eff).aggiornaFrazioni(T_dis);

        out = strings(numel(names),1);
        for k = 1:numel(names)
            restr = app.pairMap.(names{k})(app.modello);
            ord   = app.selectOrdScenario(names{k});
            dc    = DoseCalculator(restr,ord,fk0,R_Tdis);
            Tres  = dc.trovaPeriodoRestrizione(restr.DoseConstraint);
            out(k)= sprintf('%s → T_res=%.1f gg, Dose7g=%.2f mSv',...
                restr.nome,Tres,dc.calcolaDoseTotale(7));
        end
        app.RisultatiTextArea.Value = out;
    end

    % ---------- helper per checkbox ----------
    function name = getScenarioSelected(app)
        if app.PartnerCheckBox.Value     , name='Partner';
        elseif app.TrasportoCheckBox.Value, name='Trasporto';
        elseif app.Bambino02CheckBox.Value, name='Bambino02';
        elseif app.Bambino25CheckBox.Value, name='Bambino25';
        elseif app.Bambino511CheckBox.Value, name='Bambino511';
        elseif app.IncintaCheckBox.Value  , name='Incinta';
        elseif app.ColleghiCheckBox.Value , name='Colleghi';
        else, name='';
        end
    end
    function list = getAllSelected(app)
        list = {};
        if app.PartnerCheckBox.Value,   list{end+1}='Partner';   end
        if app.TrasportoCheckBox.Value, list{end+1}='Trasporto'; end
        if app.Bambino02CheckBox.Value, list{end+1}='Bambino02'; end
        if app.Bambino25CheckBox.Value, list{end+1}='Bambino25'; end
        if app.Bambino511CheckBox.Value,list{end+1}='Bambino511';end
        if app.IncintaCheckBox.Value,   list{end+1}='Incinta';   end
        if app.ColleghiCheckBox.Value,  list{end+1}='Colleghi';  end
    end

    % ---------- scelta ordinario dinamica ----------
    function ord = selectOrdScenario(app,restrName)
        if strcmp(restrName,'Colleghi') && app.DueMetriRadio.Value
            ord = app.pairMapOrd.Colleghi2m(app.modello);
        else
            ord = app.pairMapOrd.(restrName)(app.modello);
        end
    end
end

    % ========================= COSTRUTTORE =========================
    methods (Access = public)
        function app = DoseApp
            createComponents(app);

            app.modello = ModelloLineare(1.70);

            % ---------- factory restrittivi ----------
            app.pairMap = struct( ...
                'Partner',    @Scenario.Partner, ...
                'Trasporto',  @Scenario.TrasportoPubblico, ...
                'Bambino02',  @Scenario.Bambino_0_2, ...
                'Bambino25',  @Scenario.Bambino_2_5, ...
                'Bambino511', @Scenario.Bambino_5_11, ...
                'Incinta',    @Scenario.DonnaIncinta, ...
                'Colleghi',   @Scenario.NessunaRestr );

            % ---------- factory ordinari ----------
            app.pairMapOrd = struct( ...
                'Partner',   @Scenario.Ordinario_Partner, ...
                'Trasporto', @Scenario.Ordinario_Trasporto, ...
                'Bambino02', @Scenario.Ordinario_Bambino_0_2, ...
                'Bambino25', @Scenario.Ordinario_Bambino_2_5, ...
                'Bambino511',@Scenario.Ordinario_Bambino, ...
                'Incinta',   @Scenario.Ordinario_Incinta, ...
                'Colleghi',  @Scenario.Ordinario_Colleghi );

            % nuova factory per variante ≥2 m
            app.pairMapOrd.Colleghi2m = @Scenario.Ordinario_Colleghi_2m;

            registerApp(app,app.UIFigure);
            if nargout==0, clear app, end
        end
        function delete(app), delete(app.UIFigure); end
    end

    % ========================= GUI BUILD =========================
    methods (Access = private)
        function createComponents(app)
            % === finestra e griglia principale ===
            app.UIFigure = uifigure('Name','DoseApp','Position',[100 100 1000 600]);
            app.GridLayout = uigridlayout(app.UIFigure,[1,3]);
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
            glSc = uigridlayout(app.ScenariPanel,[8,1]);  % +1 riga

            app.PartnerCheckBox    = uicheckbox(glSc,'Text','Partner');
            app.TrasportoCheckBox  = uicheckbox(glSc,'Text','Trasporto pubblico');
            app.Bambino02CheckBox  = uicheckbox(glSc,'Text','Bambino <2 aa');
            app.Bambino25CheckBox  = uicheckbox(glSc,'Text','Bambino 2–5 aa');
            app.Bambino511CheckBox = uicheckbox(glSc,'Text','Bambino 5–11 aa');
            app.IncintaCheckBox    = uicheckbox(glSc,'Text','Donna incinta');
            app.ColleghiCheckBox   = uicheckbox(glSc,'Text','Colleghi lavoro');

            % --- gruppo radio per distanza lavoro ---
            app.WorkDistGroup = uibuttongroup(glSc,'Title','Distanza al lavoro',...
                'Visible','off');
            app.StandardRadio = uiradiobutton(app.WorkDistGroup,...
                'Text','Standard (≈1 m)','Position',[10 5 140 22],'Value',true);
            app.DueMetriRadio = uiradiobutton(app.WorkDistGroup,...
                'Text','Sempre ≥2 m','Position',[10 30 140 22]);

            % callback visibilità
            app.ColleghiCheckBox.ValueChangedFcn = ...
                @(cb,~) set(app.WorkDistGroup,'Visible',cb.Value);


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



