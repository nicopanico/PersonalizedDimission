classdef DoseApp < matlab.apps.AppBase
    
    %DOSEAPP  App per il calcolo dei tempi di restrizione post-terapia (DoseApp).
    %
    % DESCRIZIONE
    %  L'app calcola il periodo di restrizione ottimale T_res (in giorni) per uno
    %  o più scenari di esposizione (fase restrittiva + fase ordinaria), a partire da:
    %   - T_discharge (INSERITO in GUI in ORE, convertito internamente in GIORNI)
    %   - R_Tdis (uSv/h): per I-131 inserito a 2 m, convertito a equivalente a 1 m
    %   - radiofarmaco (cinetica da JSON o personalizzata via plugin)
    %   - scenari (configurati da getScenariosConfig + override utente via ScenarioEditor)
    %
    % OUTPUT PRINCIPALI
    %  - Lista scenari con T_res arrotondato a giorni interi (ceil, prudenziale)
    %  - Riepilogo: T_max e T_medio (giorni)
    %  - Modalita' "Isolamento totale": fase restrittiva a contatti zero, vincolo
    %    preso dagli scenari restrittivi selezionati (T_res = max dei vincoli)
    %  - PDF paziente (DReportBuilder)
    %
    % UNITA' (CONVENZIONI)
    %  - T_discharge: ore in input GUI -> giorni nei calcoli (T_days = T_hours/24)
    %  - distanze: metri (m)
    %  - tempi scenario: ore/giorno
    %  - dose constraint: mSv
    %  - ratei: uSv/h
    %
    % NOTE GUI
    %  - Il pannello scenari usa uigridlayout "scrollabile" per evitare tagli su laptop/DPI.
    %  - Evitare Position dentro uigridlayout: usare Layout.Row/Column o griglie annidate.
    %
    % Autore: Nicola Panico - 19/12/2025

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
        IsolamentoCheckBox matlab.ui.control.CheckBox

        EditWhichDrop matlab.ui.control.DropDown
        EditPhaseDrop matlab.ui.control.DropDown
        EditScenarioBtn matlab.ui.control.Button

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
        WorkReturnDropIso matlab.ui.control.DropDown
        I131_RATEO_2M_TO_1M = 2.75; % I131 fattore di conversione da 2m a 1m
        I131_DIST_EXP         = 1.5;  % esponente di legge di distanza usato nel documento AIFM-AIMN
        I131_TRAVEL_LIMIT_MSV = 0.3; % Limite di dose durante il viaggio per la popolazione
        customOverrides struct = struct('restr', struct(), 'ord', struct());

    end
    properties (Access = private, Constant)
        % Tabella 6 AIFM-AIMN per 177Lu DOTATATE / PSMA
        travelLU = struct( ...          % rateo max (µSv/h)  →  ore consentite
            'th',   [ 5  10  15  20  25 ], ...   % soglie (superiore non incluso)
            'hMax', [ 9.5  5  3.5  2.5  2 ]);
        travelI131 = struct( ...
            'th',   [5 10 15 20],  ...          % soglie superiori non incluse
            'hMax', [4 2 1 0.5] );           % 4 classi → 4 valori% ore di viaggio ammesse
    end
    methods (Access = private)
        function tf = rfHasMin5Days(app)
            % Rileva se il radiofarmaco corrente richiede soglia minima 5 gg
            v = lower(string(app.RadiofarmacoDropDown.Value));  % adatta se il nome del dropdown è diverso
            % match robusto (etichette diverse non fanno paura)
            tf = contains(v,'i-131') || contains(v,'iodio') || ...
                contains(v,'lu-177') || contains(v,'lutet') || contains(v,'dotatate') || contains(v,'psma');
        end

        function T = applyMin5DaysIfNeeded(app, T)
            % T può essere scalare o vettore; applico floor=5 se RF è I-131 o Lu-177
            if app.rfHasMin5Days()
                T = max(T, 5);  % element-wise
            end
        end
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

            rateo_meas = app.R_TdisField.Value;          % valore inserito in GUI (I-131 a 2 m)
            rateo_eff  = app.toReferenceRateo(rateo_meas, rf);  % equivalente a 1 m per i calcoli

            rep = DReportBuilder(paziente,clinico,rf,rateo_meas); % nel PDF mostriamo il misurato

            % ---- scenari selezionati --------------------------------------------
            names = app.getAllSelected();
            if isempty(names)
                uialert(app.UIFigure,'Seleziona almeno uno scenario','Nessuno scenario');
                return;
            end

            Tdis   = app.TDischargeField.Value;
            R_Tdis = rateo_eff;
            rph = app.getKinetics(rf);
            fk0  = Farmacocinetica(rph.fr,rph.lambda_eff).aggiornaFrazioni(Tdis);

            if isfield(app,'IsolamentoCheckBox') && app.IsolamentoCheckBox.Value
                Tiso = app.calcolaIsolamentoTotale(fk0, R_Tdis);
                rep.addScenario("Isolamento totale", Tiso, ...
                    "Nessun contatto con altre persone fino al termine del periodo indicato.");
            end

            for k = 1:numel(names)
                scenName = names{k};
                restr = app.getScenarioInstance(names{k}, 'restr');
                ord   = app.getScenarioInstance(names{k}, 'ord');
                dc    = DoseCalculator(restr, ord, fk0, R_Tdis);

                %— T_res nominale
                Tres = dc.trovaPeriodoRestrizione(restr.DoseConstraint);
                Tres = app.applyMin5DaysIfNeeded(Tres);

                %— descrizione base
                descr = app.restr2human(restr.nome);

                %— caso speciale Trasporto
                if strcmpi(scenName,'Trasporto')
                    if contains(rf, {'DOTATATE','PSMA'}, 'IgnoreCase',true)
                        oreMax = maxOreViaggio(app, R_Tdis, 'Lu');
                    else
                        oreMax = maxOreViaggio(app, R_Tdis, 'I131');
                    end
                    descr = sprintf(['Nei primi 2 gg viaggio max %.1f h totali su mezzi pubblici. ', ...
                        'Auto privata consentita (sedile posteriore ≥1 m).'], oreMax);
                    Tres = NaN;   % in tabella comparirà “–”
                end

                %— finalmente aggiungi lo scenario al report
                rep.addScenario(restr.nome,  Tres,  descr);
            end

            % ---- salvataggio -----------------------------------------------------
            [file,path] = uiputfile({'*.pdf','PDF file'},'Salva istruzioni come');
            if isequal(file,0), return; end

            pdfPath = rep.build(fullfile(path,file));
            winopen(pdfPath);
        end

        %% ---------- helper: descrizione “leggera” per la GUI ----------------------
        function txt = restr2human(~, nomeScen)
            % Uniforma il nome scenario per evitare problemi di mapping
            nomeScen = lower(strtrim(nomeScen));
            nomeScen = strrep(nomeScen, ' restr.', '');
            nomeScen = strrep(nomeScen, ' aa', '');
            nomeScen = strrep(nomeScen, '  ', ' ');

            % Mapping tra chiavi normalizzate e descrizioni pratiche
            switch nomeScen
                case {'partner'}
                    txt = "Letti separati; contatto ≤2 h/gg a ~1 m";
                case {'bambino <2'}
                    txt = "1.5 h a 1 m e 2 h a 2 m";
                case {'bambino 2–5', 'bambino 2-5'}
                    txt = "1.5 h a 1 m e 1.5 h a 2 m";
                case {'bambino 5–11', 'bambino 5-11'}
                    txt = "≤2 h/g a 1 m; gioco a 2 m";
                case {'colleghi', 'colleghi lavoro'}
                    txt = "Rientro con distanza ≥1 m (o ≥2 m)";
                case {'trasporto', 'trasporto pubblico'}
                    txt = "Limitazioni mezzi pubblici nei primi 2 gg";
                case {'incinta', 'donna incinta'}
                    txt = "≥1 m per 6 h/gg; niente contatto ravvicinato";
                otherwise
                    txt = " ";
            end
        end

        %% Plot
        function PlotDoseButtonPushed(app)
            % --- parametri clinici
            T_discharge = app.TDischargeField.Value;
            R_Tdis_meas = app.R_TdisField.Value;
            selectedRF  = app.RadiofarmacoDropDown.Value;
            % conversione 2 m -> 1 m per I-131
            R_Tdis_eff  = app.toReferenceRateo(R_Tdis_meas, selectedRF);

            % --- farmacocinetica (dipende solo da T_discharge)
            rph = app.getKinetics(selectedRF);
            fk  = Farmacocinetica(rph.fr, rph.lambda_eff).aggiornaFrazioni(T_discharge);

            % --- scenario scelto
            restrName = app.getScenarioSelected();
            if isempty(restrName)
                uialert(app.UIFigure,'Seleziona uno scenario.','Attenzione'); return;
            end
            restr = app.getScenarioInstance(names{k}, 'restr');
            ord   = app.getScenarioInstance(names{k}, 'ord');

            % --- calcolo e grafico (usa sempre il rateo equivalente a 1 m)
            dc = DoseCalculator(restr, ord, fk, R_Tdis_eff);
            dc.plotDoseCurve(fk, selectedRF);
        end

        %% CalcolaDose
        function CalcolaDoseButtonPushed(app, ~)
            names = app.getAllSelected();
            if isempty(names) && ~(isprop(app,'IsolamentoCheckBox') && app.IsolamentoCheckBox.Value)
                app.RisultatiTextArea.Value = "Seleziona almeno uno scenario.";
                return;
            end

            % --- input base
            T_dis  = app.TDischargeField.Value/24;   % <-- ore -> giorni
            R_Tdis = app.R_TdisField.Value;
            RF     = app.RadiofarmacoDropDown.Value;

            % --- conversione 2m -> 1m per I-131
            R_Tdis_eff = app.toReferenceRateo(R_Tdis, RF);
            fprintf('RF=%s | R_Tdis(meas)=%.1f µSv/h | equiv_1m=%.1f µSv/h | factor=%.3f\n', ...
                RF, R_Tdis, R_Tdis_eff, R_Tdis_eff/max(R_Tdis,eps));

            % --- header informativo per la GUI
            if contains(RF,'I-131','IgnoreCase',true)
                hdr = sprintf('R_{Tdis} misurato = %.1f µSv/h @2 m   →   equiv. 1 m = %.1f µSv/h (fattore fisso %.2f)', ...
                    R_Tdis, R_Tdis_eff, app.I131_RATEO_2M_TO_1M);
                hdr = string(hdr);
            else
                hdr = sprintf('R_{Tdis} (a 1 m) = %.1f µSv/h', R_Tdis);
                hdr = string(hdr);
            end

            % --- farmacocinetica (dipende solo da T_dis)
            rph = app.getKinetics(RF);
            fk0 = Farmacocinetica(rph.fr, rph.lambda_eff).aggiornaFrazioni(T_dis);

            % === ramo ISOLAMENTO TOTALE ===
            if isprop(app, 'IsolamentoCheckBox') && app.IsolamentoCheckBox.Value
                [keysIso, labelsIso, TresVals] = app.calcolaIsolamentoDettagli(fk0, R_Tdis_eff);

                app.RisultatiTextArea.FontName = 'Courier New';
                app.RisultatiTextArea.FontSize = 15;

                if isempty(TresVals)
                    app.RisultatiTextArea.Value = {hdr; ''; ...
                        'Isolamento totale: nessuno scenario selezionato (e lavoro: Non incluso).'; ...
                        'Seleziona almeno un vincolo oppure scegli il lavoro nel menu in basso.'};
                    return;
                end

                TresVals = ceil(TresVals);     % giorni interi
                [Tmax, imax] = max(TresVals);
                Tmean = round(mean(TresVals));
                Tmax = round(max(TresVals));

                % righe per-scenario + riepilogo evidenziato
                rows = strings(0,1);
                rows(end+1) = hdr;
                rows(end+1) = "";
                for i = 1:numel(TresVals)
                    rows(end+1) = sprintf('%-20s  T_res = %5.1f gg', labelsIso(i), TresVals(i));
                end
                rows(end+1) = "";
                rows(end+1) = "================ RIEPILOGO ================";
                rows(end+1) = sprintf('T_max = %4.1f gg  (scenario: %s)   |   T_medio = %4.1f gg', ...
                    Tmax, labelsIso(imax), Tmean);
                rows(end+1) = "===========================================";

                % --- Aggiungi sempre la sezione TRASPORTO anche in isolamento totale ---
                isI131 = contains(RF,'I-131','IgnoreCase',true);
                isLu   = contains(RF, {'DOTATATE','PSMA'}, 'IgnoreCase', true);

                rows(end+1) = "";
                rows(end+1) = "Trasporto (indicativo)";

                if isI131
                    % I-131: formula intersocietaria con esponente k = app.I131_DIST_EXP
                    t03 = app.calcI131TravelHours(R_Tdis_eff, 0.3);
                    t1  = app.calcI131TravelHours(R_Tdis_eff, 1.0);
                    rows(end+1) = sprintf('I-131 → tempo max viaggio: %.1f h @0.3 m   |   %.1f h @1 m', t03, t1);

                elseif isLu
                    % Lu-177: mantieni la logica tabellare AIFM-AIMN (prime 48 h, mezzi pubblici)
                    oreMax = app.maxOreViaggio(R_Tdis_eff, 'Lu');
                    rows(end+1) = sprintf('Lu-177 → mezzi pubblici (primi 2 gg): %.1f h totali consentite', oreMax);

                else
                    % Altri RF: se vuoi, mostra n.d. oppure replica la formula I-131 con k=1.5
                    rows(end+1) = 'Altri RF → n.d. (nessuna regola dedicata)';
                end

                app.RisultatiTextArea.Value = rows;
                return;
            end
            % === fine ramo isolamento ===

            % --- Flusso standard (se NON è selezionato isolamento totale)
            rows = {};                          % <--- cell array di righe (char)
            rows{end+1} = char(hdr);            % header (convertito da string a char)
            rows{end+1} = '';

            Tres_list  = [];
            for k = 1:numel(names)
                restr = app.getScenarioInstance(names{k}, 'restr');
                ord   = app.getScenarioInstance(names{k}, 'ord');
                dc    = DoseCalculator(restr, ord, fk0, R_Tdis_eff);

                isTrav = strcmp(names{k}, 'Trasporto');

                if isTrav
                    if contains(RF, {'DOTATATE','PSMA'}, 'IgnoreCase', true)
                        oreMax  = maxOreViaggio(app, R_Tdis_eff, 'Lu');
                        TresStr = '–';
                        extra   = sprintf(' | Viaggio max %.1f h (mezzi pubblici, primi 2 gg)', oreMax);
                    else
                        t03 = app.calcI131TravelHours(R_Tdis_eff, 0.3);
                        t1  = app.calcI131TravelHours(R_Tdis_eff, 1.0);
                        TresStr = '–';
                        extra   = sprintf(' | Viaggio max: %.1f h @0.3 m   |   %.1f h @1 m', t03, t1);
                    end
                else
                    Tres = dc.trovaPeriodoRestrizione(restr.DoseConstraint);
                    Tres = app.applyMin5DaysIfNeeded(Tres);

                    TresR = ceil(Tres);                 % <-- arrotondo per eccesso (giorni interi)
                    TresStr = sprintf('%d', TresR);
                    Tres_list(end+1) = Tres; %#ok<AGROW>
                end

                riga = sprintf('%-18s  T_res: %4s gg  (Dose7gg: %5.2f mSv)%s', ...
                    restr.nome, TresStr, dc.calcolaDoseTotale(7));
                rows{end+1} = riga;
                rows{end+1} = '';
            end

            % ---- Riepilogo sempre visibile anche in modalità normale ----
            if ~isempty(Tres_list)
                Tmax  = round(max(Tres_list));
                Tmean = round(mean(Tres_list));   % <-- medio arrotondato a giorni interi

                box = { ...
                    '================ RIEPILOGO ================'; ...
                    sprintf('  T_max = %.1f gg    |    T_medio = %.1f gg', Tmax, Tmean); ...
                    '==========================================='; ...
                    ''};
                % Metto il box in testa e poi tutte le righe scenario
                rows = [box; rows(:)];
            end

            app.RisultatiTextArea.FontName = 'Courier New';
            app.RisultatiTextArea.FontSize = 15;
            app.RisultatiTextArea.Value    = rows;
        end




    %% ---------- drelper per checkbox ----------
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
    function h = maxOreViaggio(app, rateo, isotope)
        switch isotope
            case 'Lu'
                tbl = app.travelLU;
            case 'I131'
                tbl = app.travelI131;
            otherwise          % fallback conservativo
                    h = 0;  return;
            end
    
            idx = find(rateo < tbl.th, 1, 'first');
            if isempty(idx)
                h = tbl.hMax(end);
            else
                h = tbl.hMax(idx);
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
    function label = prettyScenarioName(~, key)
        switch key
            case 'Partner',    label = 'Partner';
            case 'Bambino02',  label = 'Bambino <2 aa';
            case 'Bambino25',  label = 'Bambino 2–5 aa';
            case 'Bambino511', label = 'Bambino 5–11 aa';
            case 'Incinta',    label = 'Donna incinta';
            case 'Colleghi',   label = 'Colleghi (≥1 m)';
            case 'Colleghi2m', label = 'Colleghi (≥2 m)';
            otherwise,         label = key;
        end
    end

    function [keys, labels, TresVals] = calcolaIsolamentoDettagli(app, fk0, R_Tdis)
        % scenari da considerare: selezionati + scelta lavoro dalla tendina
        keys = app.getSelectedForIsolation();
        labels = strings(0,1);
        TresVals = [];

        if isempty(keys), return; end

        TresVals = zeros(1, numel(keys));
        labels   = strings(1, numel(keys));

        for k = 1:numel(keys)
            key = keys{k};

            % fase ordinaria (post-isolamento)
            ord = app.pairMapOrd.(key)(app.modello);

            % vincolo restrittivo dello scenario corrispondente
            baseKey   = regexprep(key,'2m$','');           % rimuove "2m" per pescare il restr
            restr_nom = app.pairMap.(baseKey)(app.modello);

            % fase di isolamento: contatti zero
            zeroScenario = ord;
            if ~isempty(zeroScenario.tempi)
                zeroScenario.tempi(:) = 0;
            end
            zeroScenario.nome = restr_nom.nome + " (isolamento)";

            dc = DoseCalculator(zeroScenario, ord, fk0, R_Tdis);
            TresVals(k) = dc.trovaPeriodoRestrizione(restr_nom.DoseConstraint);
            TresVals(k) = app.applyMin5DaysIfNeeded(TresVals(k));
            labels(k)   = app.prettyScenarioName(key);
        end
    end
    end
    



%% ========================= COSTRUTTORE ========================
% DoseApp constructor with plugin integration
methods (Access = public)
    function app = DoseApp
        % 1) Costruisci UI base (pannelli, grid, controlli)
        createComponents(app);
        app.UIFigure.WindowState = 'maximized';

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
        app.TDischargeLabel = uilabel(gl1,'Text','T_{discharge} (ore)');
        app.TDischargeField = uieditfield(gl1,'numeric','Value',24);
        app.TDischargeField.Tooltip = 'Inserisci in ore; il codice converte automaticamente in giorni.';
        app.TDischargeLabel.Layout.Row    = 2;
        app.TDischargeLabel.Layout.Column = 1;
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
        app.RadiofarmacoDropDown.ValueChangedFcn = @(dd,~) updateRateoLabel(app);
        % call once at startup
        updateRateoLabel(app);

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
        glSc = uigridlayout(app.ScenariPanel,[11,1]);
        glSc.RowHeight  = repmat({'fit'},1,11);

        % più compatto (il 45 era il “killer” sui laptop)
        glSc.RowSpacing = 8;
        glSc.Padding    = [10 8 10 8];

        % scroll quando lo spazio verticale non basta (robusto su laptop/DPI diversi)
        try
            glSc.Scrollable = 'on';
        catch
        end

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
        % Checkbox per isolamento totale
        app.IsolamentoCheckBox = uicheckbox(glSc, ...
            'Text', 'Isolamento totale (nessun contatto con altre persone)', ...
            'FontWeight', 'bold', ...
            'Tooltip', 'Seleziona per calcolare solo il tempo di isolamento totale, senza contatti.');
        app.IsolamentoCheckBox.Layout.Row = 9;
        app.IsolamentoCheckBox.Layout.Column = 1;

        % Esclude lavoro da isolamento totale (gia lo è!)
        app.WorkReturnDropIso = uidropdown(glSc, ...
            'Items', {'Non incluso','≥1 m','≥2 m'}, ...
            'Value', 'Non incluso', ...
            'Tooltip','In isolamento totale: includi (facoltativo) un vincolo di rientro al lavoro.');
        app.WorkReturnDropIso.Layout.Row = 10;  % mettilo sotto/accanto alla checkbox; se serve, aumenta le righe griglia
        app.WorkReturnDropIso.Layout.Column = 1;
        app.WorkReturnDropIso.Visible = 'off';   % visibile solo quando Isolamento è ON

        % --- riga 11: editor scenari “responsive” (niente Position)
        editGrid = uigridlayout(glSc,[1 3]);
        editGrid.Layout.Row = 11;
        editGrid.Layout.Column = 1;
        editGrid.ColumnWidth = {'1x','fit','fit'};
        editGrid.ColumnSpacing = 8;
        editGrid.Padding = [0 0 0 0];

        app.EditWhichDrop = uidropdown(editGrid, ...
            'Items', {'Partner','Trasporto','Bambino02','Bambino25','Bambino511','Incinta','Colleghi'}, ...
            'Value','Partner');
        app.EditWhichDrop.Layout.Row = 1; app.EditWhichDrop.Layout.Column = 1;

        app.EditPhaseDrop = uidropdown(editGrid, ...
            'Items', {'Restrittivo','Ordinario'}, ...
            'Value','Restrittivo');
        app.EditPhaseDrop.Layout.Row = 1; app.EditPhaseDrop.Layout.Column = 2;

        app.EditScenarioBtn = uibutton(editGrid,'Text','Personalizza…', ...
            'ButtonPushedFcn', @(~,~) app.openScenarioEditor());
        app.EditScenarioBtn.Layout.Row = 1; app.EditScenarioBtn.Layout.Column = 3;

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

        %% Toggle
        app.IsolamentoCheckBox.ValueChangedFcn = @(cb,~) toggleIsolamento(cb, app);

        function toggleIsolamento(cb, app)
            state = cb.Value;
            if state
                enableStr = 'off';
            else
                enableStr = 'on';
            end
            app.PartnerCheckBox.Enable    = enableStr;
            app.TrasportoCheckBox.Enable  = enableStr;
            app.Bambino02CheckBox.Enable  = enableStr;
            app.Bambino25CheckBox.Enable  = enableStr;
            app.Bambino511CheckBox.Enable = enableStr;
            app.IncintaCheckBox.Enable    = enableStr;
            app.ColleghiCheckBox.Enable   = enableStr;
            app.WorkDistGroup.Enable      = enableStr;

            % mostra/nascondi l’opzione lavoro per isolamento
            if isprop(app,'WorkReturnDropIso')
                app.WorkReturnDropIso.Visible = ternary(state,'on','off');
            end
        end

        function out = ternary(cond,a,b)
            if cond, out=a; else, out=b; end
        end

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

    function Tres_isolamento = calcolaIsolamentoTotale(app, fk0, R_Tdis)
        % --- Decidi se includere il lavoro e a che distanza
        includeWork = false; workKey = '';
        if isprop(app,'WorkReturnDropIso') && ~isempty(app.WorkReturnDropIso) && isvalid(app.WorkReturnDropIso)
            switch app.WorkReturnDropIso.Value
                case '≥1 m'
                    includeWork = true; workKey = 'Colleghi';
                case '≥2 m'
                    includeWork = true;
                    if isfield(app.pairMapOrd,'Colleghi2m')
                        workKey = 'Colleghi2m';
                    else
                        workKey = 'Colleghi';
                    end
                otherwise
                    includeWork = false; % 'Non incluso'
            end
        end

        % Scenari domestici sempre inclusi
        scenari = {'Partner','Bambino02','Bambino25','Bambino511','Incinta'};
        if includeWork
            scenari{end+1} = workKey;   % 'Colleghi' o 'Colleghi2m'
        end

        Tres_vals = zeros(1, numel(scenari));
        for k = 1:numel(scenari)
            key = scenari{k};

            % scenario ordinario (per la fase post-isolamento)
            ord = app.pairMapOrd.(key)(app.modello);

            % scenario “restrittivo nominale” solo per leggere il constraint corretto
            restr_nom = app.pairMap.(regexprep(key,'2m$',''))(app.modello);  % toglie l'eventuale '2m'

            % isolamento = nessun contatto nella fase restrittiva
            zeroScenario = ord;
            if ~isempty(zeroScenario.tempi)
                zeroScenario.tempi(:) = 0;
            end
            zeroScenario.nome = restr_nom.nome + " (isolamento)";

            % calcolo tempo: rispetta il vincolo RESTRITTIVO di quello scenario
            dc  = DoseCalculator(zeroScenario, ord, fk0, R_Tdis);
            Tres_vals(k) = dc.trovaPeriodoRestrizione(restr_nom.DoseConstraint);
            Tres_vals(k) = app.applyMin5DaysIfNeeded(Tres_vals(k));
        end

        % tempo di isolamento richiesto è il massimo tra i vincoli considerati
        Tres_isolamento = max(Tres_vals);
        Tres_isolamento = app.applyMin5DaysIfNeeded(Tres_isolamento);

        % opzionale: minimo clinico per 177Lu
        % if contains(app.RadiofarmacoDropDown.Value,'DOTATATE','IgnoreCase',true) && Tres_isolamento < 5
        %     Tres_isolamento = 5;
        % end
    end


    function R1m = toReferenceRateo(app, R_measured, selectedRF)
        % Se I-131, l'utente inserisce R_Tdis a 2 m: convertiamo all'equivalente a 1 m
        if contains(selectedRF, 'I-131', 'IgnoreCase', true)
            % fattore = dose(1 m)/dose(2 m) dal modello geometrico
            R1m = R_measured * app.I131_RATEO_2M_TO_1M;
        else
            % per gli altri RF si assume già R_Tdis a 1 m
            R1m = R_measured;
        end
    end
    function updateRateoLabel(app)
        rf = app.RadiofarmacoDropDown.Value;
        if contains(rf, 'I-131', 'IgnoreCase', true)
            app.RTdisLabel.Text = 'R_{Tdis} (µSv/h a 2 m)';
            app.R_TdisField.Tooltip = 'Per I-131 inserisci il rateo a 2 m; i calcoli lo normalizzano a 1 m.';
        else
            app.RTdisLabel.Text = 'R_{Tdis} (µSv/h a 1 m)';
            app.R_TdisField.Tooltip = 'Per questo radiofarmaco inserisci il rateo a 1 m.';
        end
    end
    function keys = getSelectedScenarios(app)
        % Legge i checkbox degli scenari così come appaiono in GUI
        keys = {};
        if app.PartnerCheckBox.Value    , keys{end+1} = 'Partner';    end
        if app.TrasportoCheckBox.Value  , keys{end+1} = 'Trasporto';  end
        if app.Bambino02CheckBox.Value  , keys{end+1} = 'Bambino02';  end
        if app.Bambino25CheckBox.Value  , keys{end+1} = 'Bambino25';  end
        if app.Bambino511CheckBox.Value , keys{end+1} = 'Bambino511'; end
        if app.IncintaCheckBox.Value    , keys{end+1} = 'Incinta';    end
        if app.ColleghiCheckBox.Value   , keys{end+1} = 'Colleghi';   end
    end

    function keys = getSelectedForIsolation(app)
        % Scenari da considerare in isolamento totale:
        % - tutti quelli selezionati dall'utente, tranne "Trasporto"
        % - il lavoro lo si gestisce SOLO via la tendina WorkReturnDropIso
        keys = app.getSelectedScenarios();

        % Escludi "Trasporto" (non ha senso in isolamento)
        keys(strcmpi(keys,'Trasporto')) = [];

        % Rimuovi l’eventuale "Colleghi" selezionato via checkbox:
        % la scelta del lavoro si fa con la tendina (≥1 m / ≥2 m / Non incluso)
        keys(strcmpi(keys,'Colleghi')) = [];

        % Aggiungi il lavoro secondo la tendina
        if isprop(app,'WorkReturnDropIso') && isvalid(app.WorkReturnDropIso)
            switch app.WorkReturnDropIso.Value
                case '≥1 m'
                    keys{end+1} = 'Colleghi';
                case '≥2 m'
                    if isfield(app.pairMapOrd,'Colleghi2m')
                        keys{end+1} = 'Colleghi2m';
                    else
                        keys{end+1} = 'Colleghi'; % fallback prudente
                    end
                otherwise
                    % 'Non incluso' → non aggiungere nulla
            end
        end
    end
    function h = calcI131TravelHours(app, R1m, d_m)
        % Formula: t(h) = D_lim / [ R(1m) * (1/d^k) ]   (con unità coerenti)
        %          t(h) = (D_lim [mSv]) / ( (R1m [mSv/h]) / d^k )
        %          t(h) = (D_lim * d^k) / (R1m/1000)
        % → usando µSv/h in input: t(h) = (D_lim * 1000) * d^k / R1m_uSv_h
        if R1m <= 0
            h = 0; return;
        end
        Dlim = app.I131_TRAVEL_LIMIT_MSV;   % 0.3 mSv
        k    = app.I131_DIST_EXP;           % 1.5
        h    = (Dlim * 1000) * (d_m^k) / R1m;   % ore
    end
    function scen = getScenarioInstance(app, key, phase)
        % phase: 'restr' oppure 'ord'
        switch lower(phase)
            case 'restr'
                scen = app.pairMap.(key)(app.modello);
                if isfield(app.customOverrides.restr, key)
                    ov = app.customOverrides.restr.(key);
                    if ~isempty(ov.dist), scen.distanze = ov.dist; end
                    if ~isempty(ov.time), scen.tempi     = ov.time; end
                    if isfield(ov,'Dc') && ~isempty(ov.Dc), scen.DoseConstraint = ov.Dc; end
                end

            case 'ord'
                % Gestione speciale Colleghi / Colleghi2m
                if strcmp(key,'Colleghi')
                    if strcmp(app.WorkDistDrop.Value,'Sempre ≥ 2 m')
                        ordKey = 'Colleghi2m';
                    else
                        ordKey = 'Colleghi';
                    end
                else
                    ordKey = key;
                end
                scen = app.pairMapOrd.(ordKey)(app.modello);
                if isfield(app.customOverrides.ord, ordKey)
                    ov = app.customOverrides.ord.(ordKey);
                    if ~isempty(ov.dist), scen.distanze = ov.dist; end
                    if ~isempty(ov.time), scen.tempi     = ov.time; end
                    % di solito Dc per 'ord' è 0 → non lo tocchiamo
                end

            otherwise
                error('phase deve essere "restr" o "ord".');
        end
    end
    function openScenarioEditor(app)
        % Prende selezioni correnti dai 2 menu a tendina della colonna 2
        keyUI   = app.EditWhichDrop.Value;           % es. 'Partner'
        phaseUI = app.EditPhaseDrop.Value;           % 'Restrittivo' | 'Ordinario'
        phase   = DoseApp.iff(strcmpi(phaseUI,'Restrittivo'),'restr','ord');

        % Apri editor (modale) con quelle selezioni
        out = ScenarioEditor.edit(app, keyUI, phase);
        if isempty(out) || ~isfield(out,'action'), return; end

        switch out.action
            case 'cancel'
                return;

            case 'clear'
                % Rimuovi eventuale override per la coppia (key,phase)
                switch out.phase
                    case 'restr'
                        if isfield(app.customOverrides,'restr') ...
                                && isfield(app.customOverrides.restr, out.key)
                            app.customOverrides.restr = rmfield(app.customOverrides.restr, out.key);
                        end
                    case 'ord'
                        if isfield(app.customOverrides,'ord') ...
                                && isfield(app.customOverrides.ord, out.key)
                            app.customOverrides.ord = rmfield(app.customOverrides.ord, out.key);
                        end
                end
                uialert(app.UIFigure,'Personalizzazione rimossa.','OK');
                return;

            case 'apply'
                % Salva (o aggiorna) l’override di sessione
                ov = struct('dist', out.dist, 'time', out.time);
                switch out.phase
                    case 'restr'
                        ov.Dc = DoseApp.iff(isempty(out.Dc), 0, out.Dc);
                        app.customOverrides.restr.(out.key) = ov;
                    case 'ord'
                        app.customOverrides.ord.(out.key) = ov;
                end
                uialert(app.UIFigure, sprintf('Applicata personalizzazione: %s – %s', ...
                    out.key, DoseApp.iff(strcmp(out.phase,'restr'),'Restrittivo','Ordinario')), 'OK');
        end
    end
end
methods (Static)
    function y = iff(c, a, b)
        if c
            y = a;
        else
            y = b;
        end
    end
end

%% Getter per finestra personalizzazione scenario
methods (Access = public)
    function scen = getFactoryScenario(app, key, phase)
        % Ritorna lo scenario "di fabbrica" (senza override utente)
        switch lower(phase)
            case 'restr'
                scen = app.pairMap.(key)(app.modello);
            case 'ord'
                ordKey = key;
                if strcmpi(key,'Colleghi') && isfield(app.pairMapOrd,'Colleghi2m') ...
                        && strcmp(app.WorkDistDrop.Value,'Sempre ≥ 2 m')
                    ordKey = 'Colleghi2m';
                end
                scen = app.pairMapOrd.(ordKey)(app.modello);
            otherwise
                error('phase deve essere "restr" o "ord".');
        end
    end
end

end



