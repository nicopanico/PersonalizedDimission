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
        PatientLabel           matlab.ui.control.Label      % <– nuovo
        PatientNameField       matlab.ui.control.EditField  % <– nuovo
        ReportButton           matlab.ui.control.Button     % <– nuovo

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
        WorkDistDrop      matlab.ui.control.DropDown

        %  Menu per i plugin
        MenuPlugins         matlab.ui.container.Menu
        Plugins             cell
        CustomKinetics     struct = struct('name',{},'fr',{},'lambda_eff',{});
    end

    properties (Access = private)
        modello    % Oggetto ModelloLineare
        pairMap    % factory restrittivi
        pairMapOrd % factory ordinari 

    end
    properties (Access = private, Constant)
        % Tabella 6 AIFM-AIMN per 177Lu DOTATATE / PSMA
        travelLU = struct( ...          % rateo max (µSv/h)  →  ore consentite
            'th',   [ 5  10  15  20  25 ], ...   % soglie (superiore non incluso)
            'hMax', [ 9.5  5  3.5  2.5  2 ]);    % ore di viaggio ammesse
    end

    % ========================= CALLBACKS =========================
    methods (Access = private)
        % ---------- genera il foglio informativo PDF -----------------------------
        function generaPDF(app)
            import mlreportgen.dom.*

            % ---- dati base -------------------------------------------------------
            pazienteNome = strtrim(app.PatientNameField.Value);
            if isempty(pazienteNome)
                uialert(app.UIFigure,'Inserisci il nome del paziente','Nome mancante');
                return;
            end
            paziente  = struct('Name',pazienteNome);
            clinico   = struct('Name',"",'Unit',"");
            rf        = app.RadiofarmacoDropDown.Value;
            rateo     = app.R_TdisField.Value;

            rep = DReportBuilder(paziente,clinico,rf,rateo);

            % ---- scenari selezionati --------------------------------------------
            names = app.getAllSelected();
            if isempty(names)
                uialert(app.UIFigure,'Seleziona almeno uno scenario','Nessuno scenario');
                return;
            end

            Tdis   = app.TDischargeField.Value;
            R_Tdis = rateo;
            rph = app.getKinetics(rf);
            fk0  = Farmacocinetica(rph.fr,rph.lambda_eff).aggiornaFrazioni(Tdis);

            for k = 1:numel(names)
                restr = app.pairMap.(names{k})(app.modello);
                ord   = app.selectOrdScenario(names{k});
                dc    = DoseCalculator(restr,ord,fk0,R_Tdis);

                Tres  = dc.trovaPeriodoRestrizione(restr.DoseConstraint);
                if contains(rf,'DOTATATE','IgnoreCase',true) && Tres < 5
                    Tres = 5;                       % minimo clinico
                end

                % -------- descrizione pratica e gestione "Trasporto" --------------
                descr = app.restr2human(restr.nome);   % descrizione di base

                if strcmp(names{k},'Trasporto')
                    isLu = contains(rf,{'DOTATATE','PSMA'},'IgnoreCase',true);

                    if isLu            % ¹⁷⁷Lu: tabella ore di viaggio
                        oreMax = maxOreViaggio(app, R_Tdis);
                        descr  = sprintf(['Nei primi 2 gg evita mezzi pubblici oltre %.1f h totali. ', ...
                            'Auto privata consentita se siedi sul sedile posteriore ', ...
                            '(≥1 m dal guidatore).'], oreMax);
                        Tres   = NaN;   % → il PDF mostrerà “–”
                    else               % I-131: regola fissa 30 min
                        descr  = ['Nei primi 2 gg viaggio max 30 min totali su mezzi pubblici. ', ...
                            'Auto privata consentita (≥1 m).'];
                    end
                end

                rep.addScenario(restr.nome, Tres, descr);
            end

            % ---- salvataggio -----------------------------------------------------
            [file,path] = uiputfile({'*.pdf','PDF file'},'Salva istruzioni come');
            if isequal(file,0), return; end

            pdfPath = rep.build(fullfile(path,file));
            winopen(pdfPath);
        end

        %% ---------- helper: descrizione “leggera” per la GUI ----------------------
        function txt = restr2human(~,nomeScen)
            switch erase(lower(nomeScen)," restr.")
                case "partner"
                    txt = "Letti separati; contatto ≤2 h/gg a ~1 m";
                case "bambino <2"
                    txt = "1.5 h a 1 m e 2 h a 2 m";
                case "bambino 2-5"
                    txt = "1.5 h a 1 m e 1.5 h a 2 m";
                case "bambino 5-11"
                    txt = "≤2 h/g a 1 m; gioco a 2 m";
                case "colleghi"
                    txt = "Rientro con distanza ≥1 m (o ≥2 m)";
                case "trasporto"
                    txt = "Limitazioni mezzi pubblici nei primi 2 gg";
                case "incinta"
                    txt = "≥1 m per 6 h/gg; niente contatto ravvicinato";
                otherwise
                    txt = "";
            end
        end
        
    
    function PlotDoseButtonPushed(app)
        % --- parametri clinici
        T_discharge = app.TDischargeField.Value;
        R_Tdis      = app.R_TdisField.Value;
        selectedRF  = app.RadiofarmacoDropDown.Value;

        % --- farmacocinetica
        rph = app.getKinetics(selectedRF);
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

        rph = app.getKinetics(RF);
        fk0 = Farmacocinetica(rph.fr,rph.lambda_eff).aggiornaFrazioni(T_dis);

        out  = strings(numel(names)*2 ,1);   % *2 = riga vuota dopo ciascun risultato
        idx  = 1;

        for k = 1:numel(names)
            restr = app.pairMap.(names{k})(app.modello);
            ord   = app.selectOrdScenario(names{k});
            dc    = DoseCalculator(restr,ord,fk0,R_Tdis);

            isLu  = contains(RF,'DOTATATE','IgnoreCase',true) || ...
                contains(RF,'PSMA','IgnoreCase',true);
            isTrav = strcmp(names{k},'Trasporto');

            if isLu && isTrav
                % -------- 177Lu | Trasporto ---------------------------------
                oreMax  = maxOreViaggio(app, R_Tdis);     % tabella AIFM-AIMN
                TresStr = '–';                           % nessun T_res
                extra   = sprintf(' | Viaggio max %.1f h', oreMax);
            else
                Tres    = dc.trovaPeriodoRestrizione(restr.DoseConstraint);
                % Forza minimo 5 gg per DOTATATE, se vuoi mantenerlo:
                if isLu && Tres < 5, Tres = 5; end
                TresStr = sprintf('%.1f',Tres);
                extra   = '';
            end

            out(idx) = sprintf('%-18s  T_res: %4s gg  (Dose7gg: %5.2f mSv)%s', ...
                restr.nome, TresStr, dc.calcolaDoseTotale(7), extra);
            idx = idx + 2;   % riga vuota dopo ogni blocco
        end

        % — impostazioni di visualizzazione ————————————————
        app.RisultatiTextArea.FontName = 'Courier New';   % monospazio
        app.RisultatiTextArea.FontSize = 15;              % un po5 più grande
        app.RisultatiTextArea.Value    = out;

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
    % -----------helper per ore viaggio---------
    function h = maxOreViaggio(app, rateo)
        % Ritorna ore massimo viaggio secondo Tab. 6 (177Lu)
        th   = app.travelLU.th;
        hMax = app.travelLU.hMax;

        idx = find(rateo < th, 1, 'first');
        if isempty(idx)
            h = hMax(end);    % se supera la soglia più alta
        else
            h = hMax(idx);
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
    function ord = selectOrdScenario(app, restrName)
        if strcmp(restrName,'Colleghi')
            if strcmp(app.WorkDistDrop.Value,'Sempre ≥ 2 m')
                ord = app.pairMapOrd.Colleghi2m(app.modello);
            else
                ord = app.pairMapOrd.Colleghi(app.modello);
            end
        else
            ord = app.pairMapOrd.(restrName)(app.modello);
        end
    end
    end


    %% ========================= COSTRUTTORE ========================
    % DoseApp constructor with plugin integration
    methods (Access = public)
        function app = DoseApp
            % 1) Costruisci UI base (pannelli, grid, controlli)
            createComponents(app);

            % 2) Plugin: carica tutti i .m in plugins/, istanzia e riempi Menu
            app.Plugins = {};
            % Trova il file DoseApp.m e la dir dei plugin
            appFile    = which('DoseApp');
            pluginsDir = fullfile(fileparts(appFile),'plugins');
            if isfolder(pluginsDir)
                addpath(pluginsDir);
                files = dir(fullfile(pluginsDir,'*.m'));
                for k = 1:numel(files)
                    [~,name] = fileparts(files(k).name);
                    mc = meta.class.fromName(name);
                    if ~isempty(mc) && any(strcmp({mc.SuperclassList.Name},'DoseAppPluginBase'))
                        % Istanzia plugin e salva handle
                        pluginObj = feval(name);
                        app.Plugins{end+1} = pluginObj;
                        % Aggiungi voce di menu che apre il plugin
                        uimenu(app.MenuPlugins, ...
                            'Text', pluginObj.pluginName(), ...
                            'MenuSelectedFcn', @(~,~) app.openPlugin(pluginObj));
                    end
                end
            else
                warning('Directory plugin non trovata: %s', pluginsDir);
            end

            % 3) Inizializza modello e scenari
            app.modello = ModelloLineare(1.70);
            configs = getScenariosConfig();
            for i = 1:numel(configs)
                c = configs(i);
                app.pairMap.(c.key) = @(m) Scenario( ...
                    c.label+" restr.", c.restr.dist, c.restr.time, m, c.restr.Dc);
                app.pairMapOrd.(c.key) = @(m) Scenario( ...
                    c.label+" ord.",   c.ord.dist,   c.ord.time,   m, c.ord.Dc);
                if ~isempty(c.ord2m.dist)
                    app.pairMapOrd.([c.key '2m']) = @(m) Scenario( ...
                        c.label+" ord. ≥2 m", c.ord2m.dist, c.ord2m.time, m, c.ord2m.Dc);
                end
            end

            % === 4) registra e mostra ===
            registerApp(app, app.UIFigure);
            if nargout==0, clear app; end
        end
    end

    % ========================= GUI BUILD =========================
    methods (Access = private)
        function createComponents(app)
            % === finestra e griglia principale a 2 righe, 3 colonne ===
            app.UIFigure = uifigure('Name','DoseApp','Position',[100 100 1000 600]);
            app.GridLayout = uigridlayout(app.UIFigure,[1,3]);
            app.GridLayout.ColumnWidth = {'fit','1x','1.5x'}

            %% Colonna 1 – Parametri clinici (riga 1, colonna 1)
            app.ParametriPanel = uipanel(app.GridLayout,'Title','Parametri Clinici');
            app.ParametriPanel.Layout.Row    = 1;
            app.ParametriPanel.Layout.Column = 1;

            gl1 = uigridlayout(app.ParametriPanel,[6,2]);
            gl1.RowHeight   = repmat({'fit'},1,6);
            gl1.ColumnWidth = {'fit','1x'};

            % Paziente
            app.PatientLabel = uilabel(gl1,'Text','Paziente');
            app.PatientLabel.Layout.Row    = 1;
            app.PatientLabel.Layout.Column = 1;
            app.PatientNameField = uieditfield(gl1,'text','Placeholder','Mario Rossi');
            app.PatientNameField.Layout.Row    = 1;
            app.PatientNameField.Layout.Column = 2;

            % T_discharge
            app.TDischargeLabel = uilabel(gl1,'Text','T_{discharge} (giorni)');
            app.TDischargeLabel.Layout.Row    = 2;
            app.TDischargeLabel.Layout.Column = 1;
            app.TDischargeField = uieditfield(gl1,'numeric','Value',1);
            app.TDischargeField.Layout.Row    = 2;
            app.TDischargeField.Layout.Column = 2;

            % R_Tdis
            app.RTdisLabel = uilabel(gl1,'Text','R_{Tdis} (µSv/h)');
            app.RTdisLabel.Layout.Row    = 3;
            app.RTdisLabel.Layout.Column = 1;
            app.R_TdisField = uieditfield(gl1,'numeric','Value',25);
            app.R_TdisField.Layout.Row    = 3;
            app.R_TdisField.Layout.Column = 2;

            % Attività
            app.AttivitaLabel = uilabel(gl1,'Text','Attività (MBq)');
            app.AttivitaLabel.Layout.Row    = 4;
            app.AttivitaLabel.Layout.Column = 1;
            app.AttivitaField = uieditfield(gl1,'numeric','Value',740);
            app.AttivitaField.Layout.Row    = 4;
            app.AttivitaField.Layout.Column = 2;

            % Radiofarmaco + bottoni
            app.RadiofarmacoPanel = uipanel(gl1,'Title','Radiofarmaco');
            app.RadiofarmacoPanel.Layout.Row    = [5 6];
            app.RadiofarmacoPanel.Layout.Column = [1 2];
            % → Carico i nomi standard dal JSON
            raw  = fileread('radiopharmaceuticals.json');
            data = jsondecode(raw);
            stdNames = {data.name};

            % → Aggiungo l’opzione per la cinetica custom
            allNames = [stdNames, {'Cinetica personalizzata'}];

            app.RadiofarmacoDropDown = uidropdown(app.RadiofarmacoPanel, ...
                'Items', allNames, ...
                'Position',[10 35 200 22]);            
            app.CalcolaDoseButton = uibutton(app.RadiofarmacoPanel,'push', ...
                'Text','Calcola Dose', ...
                'Position',[10 5 120 28], ...
                'ButtonPushedFcn',@(btn,event) CalcolaDoseButtonPushed(app,event));
            app.PlotDoseButton = uibutton(app.RadiofarmacoPanel,'push', ...
                'Text','Grafico Dose', ...
                'Position',[140 5 120 28], ...
                'ButtonPushedFcn',@(btn,event) PlotDoseButtonPushed(app));
            app.ReportButton = uibutton(app.RadiofarmacoPanel,'push', ...
                'Text','Genera PDF', ...
                'Position',[10 -25 120 28], ...
                'ButtonPushedFcn',@(btn,event) generaPDF(app));

            %% Colonna 2 – Scenari di esposizione (riga 1, colonna 2)
            app.ScenariPanel = uipanel(app.GridLayout,'Title','Scenari di esposizione');
            app.ScenariPanel.Layout.Row    = 1;
            app.ScenariPanel.Layout.Column = 2;
            % (poi la generazione dinamica dei checkbox basata su configs, se la usi)
          
            % Layout interno: 8 righe (7 checkbox + 1 gruppo) × 1 colonna
            glSc = uigridlayout(app.ScenariPanel,[8,1]);
            glSc = uigridlayout(app.ScenariPanel,[8,1]);
            glSc.RowHeight  = repmat({'fit'},1,8);
            glSc.RowSpacing = 45;           % pixel tra una riga e l4altra
            glSc.Padding    = [10 5 10 5]; % [top right bottom left] margini interni

            % --- checkboxes per ogni scenario ---
            app.PartnerCheckBox    = uicheckbox(glSc,'Text','Partner');
            app.TrasportoCheckBox  = uicheckbox(glSc,'Text','Trasporto pubblico');
            app.Bambino02CheckBox  = uicheckbox(glSc,'Text','Bambino <2 aa');
            app.Bambino25CheckBox  = uicheckbox(glSc,'Text','Bambino 2–5 aa');
            app.Bambino511CheckBox = uicheckbox(glSc,'Text','Bambino 5–11 aa');
            app.IncintaCheckBox    = uicheckbox(glSc,'Text','Donna incinta');
            app.ColleghiCheckBox   = uicheckbox(glSc,'Text','Colleghi lavoro');

            % --- gruppo per distanza al lavoro (visibile solo se Colleghi) ---
            app.WorkDistGroup = uibuttongroup(glSc, ...
                'Title','Distanza al lavoro','Visible','off');
            % posiziona il gruppo nell’ottava riga
            app.WorkDistGroup.Layout.Row    = 8;
            app.WorkDistGroup.Layout.Column = 1;

            % dropdown dentro il gruppo
            app.WorkDistDrop = uidropdown(app.WorkDistGroup, ...
                'Items', {'Standard (≈1 m)', 'Sempre ≥ 2 m'}, ...
                'Value', 'Standard (≈1 m)');
            app.WorkDistDrop.Position = [10 10 160 22];

            % callback di visibilità
            app.ColleghiCheckBox.ValueChangedFcn = ...
                @(cb,~) set(app.WorkDistGroup,'Visible',cb.Value);

            %% Colonna 3 – Risultati (riga 1, colonna 3)
            app.RisultatiPanel = uipanel(app.GridLayout,'Title','Risultati');
            app.RisultatiPanel.Layout.Row    = 1;
            app.RisultatiPanel.Layout.Column = 3;
            gl3 = uigridlayout(app.RisultatiPanel,[1,1]);
            app.RisultatiTextArea = uitextarea(gl3,'Value',{'Risultati...'});
            app.RisultatiTextArea.Layout.Row    = 1;
            app.RisultatiTextArea.Layout.Column = 1;

            %% Finestra Plugin
            app.MenuPlugins = uimenu(app.UIFigure, 'Text', 'Plugins');

        end
    end
    %% ---------- HELPER ---------------------
    methods (Access = private)
        function openPlugin(app, pluginObj)
            % Apre una nuova finestra dedicata al plugin
            fig = uifigure('Name', pluginObj.pluginName(), 'Position',[200 200 400 300]);
            pluginObj.init(app, fig);
        end
        function rph = getKinetics(app, name)
            % Se è custom, lo prendo da CustomKinetics
            idx = find(strcmp({app.CustomKinetics.name}, name),1);
            if ~isempty(idx)
                rph = app.CustomKinetics(idx);
            elseif strcmp(name,'Cinetica personalizzata')
                error('Prima definisci una cinetica custom nel plugin.');
            else
                % Altrimenti carico dal JSON
                rph = loadRadiopharmaceutical(name,'radiopharmaceuticals.json');
            end
        end
        % … tutti i tuoi altri callback e helper (generaPDF, CalcolaDoseButtonPushed, ecc.) …
    end
end



