classdef DoseApp < matlab.apps.AppBase

    % Proprietà UI
    properties (Access = public)
        UIFigure                 matlab.ui.Figure
        GridLayout               matlab.ui.container.GridLayout

        % --- Colonna 1: Parametri Clinici
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

        % --- Colonna 2: Scenari
        ScenariPanel             matlab.ui.container.Panel
        RestrittiviPanel         matlab.ui.container.Panel
        MadreCheckBox            matlab.ui.control.CheckBox
        PartnerCheckBox          matlab.ui.control.CheckBox
        CollegaCheckBox          matlab.ui.control.CheckBox
        FamiliareCheckBox        matlab.ui.control.CheckBox

        OrdinariPanel            matlab.ui.container.Panel
        MadreOrdCheckBox         matlab.ui.control.CheckBox
        PartnerOrdCheckBox       matlab.ui.control.CheckBox
        FamiliareOrdCheckBox     matlab.ui.control.CheckBox
        LavoratoreOrdCheckBox    matlab.ui.control.CheckBox

        % --- Colonna 3: Risultati
        RisultatiPanel           matlab.ui.container.Panel
        RisultatiTextArea        matlab.ui.control.TextArea
    end

    properties (Access = private)
        modello   % Oggetto ModelloLineare
        scenarioMap  % Mappa (restrittivo -> ordinario) per linkare scenari
    end

    methods (Access = private)
        
        function CalcolaDoseButtonPushed(app, event)
            % Legge i parametri clinici
            T_discharge = app.TDischargeField.Value;
            R_Tdis = app.R_TdisField.Value;
            attivita = app.AttivitaField.Value;
            selectedRF = app.RadiofarmacoDropDown.Value;
            
            % Crea un array di nomi scenari restrittivi
            restrNames = {};
            if app.MadreCheckBox.Value
                restrNames{end+1} = 'Madre';
            end
            if app.PartnerCheckBox.Value
                restrNames{end+1} = 'Partner';
            end
            if app.CollegaCheckBox.Value
                restrNames{end+1} = 'Collega';
            end
            if app.FamiliareCheckBox.Value
                restrNames{end+1} = 'Familiare';
            end
            
            % Crea un array di nomi scenari ordinari
            ordNames = {};
            if app.MadreOrdCheckBox.Value
                ordNames{end+1} = 'Ordinario_Madre';
            end
            if app.PartnerOrdCheckBox.Value
                ordNames{end+1} = 'Ordinario_Partner';
            end
            if app.FamiliareOrdCheckBox.Value
                ordNames{end+1} = 'Ordinario_Familiare';
            end
            if app.LavoratoreOrdCheckBox.Value
                ordNames{end+1} = 'Ordinario_Lavoratore';
            end
            
            % Se l'utente non ha selezionato nessuno scenario restrittivo, avvisa
            if isempty(restrNames)
                app.RisultatiTextArea.Value = "Seleziona almeno uno scenario restrittivo.";
                return;
            end

            resultsStr = {};
            idx = 1;
            for i = 1:length(restrNames)
                rName = restrNames{i};
                
                % Trova lo scenario ordinario corrispondente usando la mappa
                if isfield(app.scenarioMap, rName)
                    ordCandidate = app.scenarioMap.(rName); % es. "Ordinario_Madre"
                    if ismember(ordCandidate, ordNames)
                        results = calcolateTime(...
                            T_discharge, R_Tdis, selectedRF, ...
                            DoseApp.scenarioStr2Func(rName), DoseApp.scenarioStr2Func(ordCandidate), ...
                            app.modello, attivita);
                        resultsStr{idx} = sprintf("Restr: %s + Ord: %s --> Dose: %.3f mSv, T_res: %.2f gg", ...
                            rName, ordCandidate, results.dose_totale, results.Tres_ott);
                        idx = idx + 1;
                    else
                        results = calcolateTime(...
                            T_discharge, R_Tdis, selectedRF, ...
                            DoseApp.scenarioStr2Func(rName), [], ...
                            app.modello, attivita);
                        resultsStr{idx} = sprintf("Restr: %s (no Ord) --> Dose: %.3f mSv, T_res: %.2f gg", ...
                            rName, results.dose_totale, results.Tres_ott);
                        idx = idx + 1;
                    end
                else
                    results = calcolateTime(...
                        T_discharge, R_Tdis, selectedRF, ...
                        DoseApp.scenarioStr2Func(rName), [], ...
                        app.modello, attivita);
                    resultsStr{idx} = sprintf("Restr: %s (no Ord corrispondente) --> Dose: %.3f mSv, T_res: %.2f gg", ...
                        rName, results.dose_totale, results.Tres_ott);
                    idx = idx + 1;
                end
            end
            
            app.RisultatiTextArea.Value = resultsStr;
        end
    end

    methods (Access = public)
        function app = DoseApp
            createComponents(app);
            app.modello = ModelloLineare(1.70, 0.058);
            app.scenarioMap = struct( ...
                'Madre','Ordinario_Madre', ...
                'Partner','Ordinario_Partner', ...
                'Collega','Ordinario_Collega', ...
                'Familiare','Ordinario_Familiare' ...
            );
            registerApp(app, app.UIFigure);
            if nargout == 0, clear app; end
        end
        
        function delete(app)
            delete(app.UIFigure);
        end
    end

    methods (Static)
        function funcHandle = scenarioStr2Func(str)
            % Mappa la stringa in un function handle corrispondente alla classe Scenario
            switch str
                case 'Madre'
                    funcHandle = @Scenario.Madre;
                case 'Partner'
                    funcHandle = @Scenario.Partner;
                case 'Collega'
                    funcHandle = @Scenario.Collega;
                case 'Familiare'
                    funcHandle = @Scenario.Familiare;
                case 'Ordinario_Madre'
                    funcHandle = @Scenario.Ordinario_Madre;
                case 'Ordinario_Partner'
                    funcHandle = @Scenario.Ordinario_Partner;
                case 'Ordinario_Familiare'
                    funcHandle = @Scenario.Ordinario_Familiare;
                case 'Ordinario_Lavoratore'
                    funcHandle = @Scenario.Ordinario_Lavoratore;
                otherwise
                    error('Scenario function for %s not defined.', str);
            end
        end
    end

    methods (Access = private)
        function createComponents(app)
            % Creazione della UIFigure
            app.UIFigure = uifigure('Name','DoseApp','Position',[100 100 900 500]);

            % Creazione del GridLayout principale (1 riga, 3 colonne)
            app.GridLayout = uigridlayout(app.UIFigure,[1,3]);
            app.GridLayout.ColumnWidth = {'fit','1x','1.5x'};
            app.GridLayout.RowHeight   = {'1x'};

            %% Colonna 1: Parametri Clinici
            app.ParametriPanel = uipanel(app.GridLayout, 'Title','Parametri Clinici');
            app.ParametriPanel.Layout.Row = 1;
            app.ParametriPanel.Layout.Column = 1;

            gl1 = uigridlayout(app.ParametriPanel, [5,2]);
            gl1.RowHeight = repmat({'fit'},1,5);
            gl1.ColumnWidth = {'fit','1x'};

            % Label T_discharge
            app.TDischargeLabel = uilabel(gl1, 'Text','T_{discharge} (giorni)');
            app.TDischargeLabel.Layout.Row = 1;
            app.TDischargeLabel.Layout.Column = 1;
            app.TDischargeField = uieditfield(gl1, 'numeric', 'Value', 0.25);
            app.TDischargeField.Layout.Row = 1;
            app.TDischargeField.Layout.Column = 2;

            % Label R_Tdis
            app.RTdisLabel = uilabel(gl1, 'Text','R_{Tdis} (µSv/h)');
            app.RTdisLabel.Layout.Row = 2;
            app.RTdisLabel.Layout.Column = 1;
            app.R_TdisField = uieditfield(gl1, 'numeric', 'Value', 30);
            app.R_TdisField.Layout.Row = 2;
            app.R_TdisField.Layout.Column = 2;

            % Label Attività
            app.AttivitaLabel = uilabel(gl1, 'Text','Attività (MBq)');
            app.AttivitaLabel.Layout.Row = 3;
            app.AttivitaLabel.Layout.Column = 1;
            app.AttivitaField = uieditfield(gl1, 'numeric', 'Value', 600);
            app.AttivitaField.Layout.Row = 3;
            app.AttivitaField.Layout.Column = 2;

            % Pannello per Radiofarmaco e Pulsante
            app.RadiofarmacoPanel = uipanel(gl1, 'Title','Radiofarmaco');
            app.RadiofarmacoPanel.Layout.Row = [4 5];
            app.RadiofarmacoPanel.Layout.Column = [1 2];

            app.RadiofarmacoDropDown = uidropdown(app.RadiofarmacoPanel, ...
                'Items',{'I-131 Carcinoma Tiroideo','I-131 Ipotiroidismo','Lu-177-DOTATATE','Lu-177-PSMA'}, ...
                'Position',[10 40 200 22]);
            app.CalcolaDoseButton = uibutton(app.RadiofarmacoPanel, 'push', 'Text','Calcola Dose',...
                'Position',[10 10 100 30], ...
                'ButtonPushedFcn',@(btn,event) CalcolaDoseButtonPushed(app,event));

            %% Colonna 2: ScenariPanel
            app.ScenariPanel = uipanel(app.GridLayout, 'Title','Scenari');
            app.ScenariPanel.Layout.Row = 1;
            app.ScenariPanel.Layout.Column = 2;

            gl2 = uigridlayout(app.ScenariPanel, [2,1]);
            gl2.RowHeight = {'fit','fit'};
            gl2.ColumnWidth = {'1x'};

            % Pannello scenari restrittivi
            app.RestrittiviPanel = uipanel(gl2, 'Title','Scenari Restrittivi');
            app.RestrittiviPanel.Layout.Row = 1;
            app.RestrittiviPanel.Layout.Column = 1;
            gl2a = uigridlayout(app.RestrittiviPanel, [4,1]);
            gl2a.RowHeight = repmat({'fit'},1,4);
            gl2a.ColumnWidth = {'1x'};
            app.MadreCheckBox = uicheckbox(gl2a, 'Text','Madre');
            app.MadreCheckBox.Layout.Row = 1; app.MadreCheckBox.Layout.Column = 1;
            app.PartnerCheckBox = uicheckbox(gl2a, 'Text','Partner');
            app.PartnerCheckBox.Layout.Row = 2; app.PartnerCheckBox.Layout.Column = 1;
            app.CollegaCheckBox = uicheckbox(gl2a, 'Text','Collega');
            app.CollegaCheckBox.Layout.Row = 3; app.CollegaCheckBox.Layout.Column = 1;
            app.FamiliareCheckBox = uicheckbox(gl2a, 'Text','Familiare');
            app.FamiliareCheckBox.Layout.Row = 4; app.FamiliareCheckBox.Layout.Column = 1;

            % Pannello scenari ordinari
            app.OrdinariPanel = uipanel(gl2, 'Title','Scenari Ordinari');
            app.OrdinariPanel.Layout.Row = 2;
            app.OrdinariPanel.Layout.Column = 1;
            gl2b = uigridlayout(app.OrdinariPanel, [4,1]);
            gl2b.RowHeight = repmat({'fit'},1,4);
            gl2b.ColumnWidth = {'1x'};
            app.MadreOrdCheckBox = uicheckbox(gl2b, 'Text','Ordinario_Madre');
            app.MadreOrdCheckBox.Layout.Row = 1; app.MadreOrdCheckBox.Layout.Column = 1;
            app.PartnerOrdCheckBox = uicheckbox(gl2b, 'Text','Ordinario_Partner');
            app.PartnerOrdCheckBox.Layout.Row = 2; app.PartnerOrdCheckBox.Layout.Column = 1;
            app.FamiliareOrdCheckBox = uicheckbox(gl2b, 'Text','Ordinario_Familiare');
            app.FamiliareOrdCheckBox.Layout.Row = 3; app.FamiliareOrdCheckBox.Layout.Column = 1;
            app.LavoratoreOrdCheckBox = uicheckbox(gl2b, 'Text','Ordinario_Lavoratore');
            app.LavoratoreOrdCheckBox.Layout.Row = 4; app.LavoratoreOrdCheckBox.Layout.Column = 1;

            %% Colonna 3: RisultatiPanel
            app.RisultatiPanel = uipanel(app.GridLayout, 'Title','Risultati');
            app.RisultatiPanel.Layout.Row = 1;
            app.RisultatiPanel.Layout.Column = 3;
            gl3 = uigridlayout(app.RisultatiPanel, [1,1]);
            gl3.RowHeight = {'1x'};
            gl3.ColumnWidth = {'1x'};
            app.RisultatiTextArea = uitextarea(gl3);
            app.RisultatiTextArea.Layout.Row = 1;
            app.RisultatiTextArea.Layout.Column = 1;
            app.RisultatiTextArea.Value = "Risultati...";
        end
    end
end



