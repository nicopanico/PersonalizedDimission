classdef ScenarioEditor < handle
% ScenarioEditor.edit(app, initialKey, initialPhase)
% - app: handle alla tua DoseApp (serve per leggere i factory scenario)
% - initialKey: es. 'Partner','Bambino02','Bambino25','Bambino511','Incinta','Colleghi','Colleghi2m','Trasporto'
% - initialPhase: 'restr' | 'ord'
%
% Ritorna una struct:
%   out.action   = 'apply' | 'clear' | 'cancel'
%   out.key      = <scenario scelto, p.es. 'Colleghi2m'>
%   out.phase    = 'restr' | 'ord'
%   out.dist     = [ ... ]    % solo se action='apply'
%   out.time     = [ ... ]    % solo se action='apply'
%   out.Dc       = <valore>   % solo se phase='restr' e action='apply'

methods (Static)
    function out = edit(app, initialKey, initialPhase)
        % ---------- setup ----------
        if nargin < 2 || isempty(initialKey),     initialKey   = 'Partner'; end
        if nargin < 3 || isempty(initialPhase),   initialPhase = 'restr';   end
        validKeys = {'Partner','Bambino02','Bambino25','Bambino511','Incinta','Colleghi','Colleghi2m','Trasporto'};
        if ~ismember(initialKey, validKeys), initialKey = 'Partner'; end
        if ~ismember(initialPhase, {'restr','ord'}), initialPhase = 'restr'; end

        out = struct('action','cancel','key',initialKey,'phase',initialPhase, ...
            'dist',[],'time',[],'Dc',[]);

        % ---------- setup finestra e griglia principale ----------
        fig = uifigure('Name','Personalizzazione scenario', ...
            'Position',[300 200 720 540], ...
            'AutoResizeChildren','on');
        fig.Scrollable = 'on';

        gl  = uigridlayout(fig,[6,1]);
        gl.RowHeight  = {52, 52, '1x', 'fit', 52, 'fit'};  % top bars, tabella, Dc, bottoni, help
        gl.RowSpacing = 8;
        gl.Padding    = [12 12 12 12];

        % ---------- riga 1: selezione scenario ----------
        pTop = uigridlayout(gl,[1,2]);
        pTop.Layout.Row = 1;
        pTop.ColumnWidth = {120, '1x'};
        pTop.ColumnSpacing = 8;
        pTop.Padding = [0 0 0 0];
        uilabel(pTop,'Text','Scenario', ...
            'HorizontalAlignment','right','FontWeight','bold');
        ddScenario = uidropdown(pTop, 'Items', validKeys, 'Value', initialKey);

        % ---------- riga 2: selezione fase ----------
        pPhase = uigridlayout(gl,[1,2]);
        pPhase.Layout.Row = 2;
        pPhase.ColumnWidth = {120, '1x'};
        pPhase.ColumnSpacing = 8;
        pPhase.Padding = [0 0 0 0];
        uilabel(pPhase,'Text','Fase', ...
            'HorizontalAlignment','right','FontWeight','bold');
        ddPhase = uidropdown(pPhase, 'Items', {'Restrittivo','Ordinario'}, ...
            'Value', iff(strcmp(initialPhase,'restr'),'Restrittivo','Ordinario'));

        % ---------- riga 3: tabella distanze/tempi ----------
        pTbl = uipanel(gl,'Title','Contatti (distanza [m] / tempo [h/g])');
        pTbl.Layout.Row = 3;
        pTbl.Scrollable = 'on';

        tblGL = uigridlayout(pTbl,[2,1]);
        tblGL.RowHeight = {'1x', 'fit'};
        tblGL.RowSpacing = 8;
        tblGL.Padding = [8 8 8 8];

        uit = uitable(tblGL, ...
            'ColumnName',{'Distanza (m)','Tempo (h/giorno)'}, ...
            'ColumnEditable',[true true], ...
            'RowName',{}, ...
            'ColumnWidth',{'auto','auto'}, ...
            'Data', zeros(0,2));

        btRowPanel = uigridlayout(tblGL,[1,3]);
        btRowPanel.ColumnWidth = {110,110,150};  % bottoni compatti
        btRowPanel.ColumnSpacing = 8;
        btRowPanel.Padding = [0 0 0 0];
        uibutton(btRowPanel,'Text','+ riga','ButtonPushedFcn',@(s,e) addRow());
        uibutton(btRowPanel,'Text','- riga','ButtonPushedFcn',@(s,e) delRow());
        uibutton(btRowPanel,'Text','Pulisci righe vuote', 'ButtonPushedFcn',@(s,e) cleanTable());

        % ---------- riga 4: Dose Constraint (solo restrittivo) ----------
        pDc = uipanel(gl,'Title','Dose Constraint (mSv)');
        pDc.Layout.Row = 4;
        dcGL = uigridlayout(pDc,[1,2]);
        dcGL.ColumnWidth = {120,'1x'};
        dcGL.ColumnSpacing = 8;
        dcGL.Padding = [0 0 0 0];
        uilabel(dcGL,'Text','Dc:','HorizontalAlignment','right');
        edDc = uieditfield(dcGL,'numeric','Value',0);

        % ---------- riga 5: bottoni ----------
        pBtns = uigridlayout(gl,[1,4]);
        pBtns.Layout.Row = 5;
        pBtns.ColumnWidth = {160, 200, 120, 120};  % larghezze stabili
        pBtns.ColumnSpacing = 8;
        pBtns.Padding = [0 0 0 0];
        uibutton(pBtns,'Text','Ripristina default', ...
            'ButtonPushedFcn',@(s,e) loadFactory());
        uibutton(pBtns,'Text','Rimuovi personalizzazione', ...
            'ButtonPushedFcn',@(s,e) onClear());
        uibutton(pBtns,'Text','Annulla', ...
            'ButtonPushedFcn',@(s,e) onCancel());
        uibutton(pBtns,'Text','Applica', ...
            'ButtonPushedFcn',@(s,e) onApply());

        % ---------- riga 6: help ----------
        uilabel(gl, ...
            'Text','Le modifiche valgono solo per questa sessione della App.', ...
            'HorizontalAlignment','center','WordWrap','on');

        % ---------- callback su cambio scenario/fase ----------
        ddScenario.ValueChangedFcn = @(s,e) onScenarioOrPhaseChanged();
    ddPhase.ValueChangedFcn    = @(s,e) onScenarioOrPhaseChanged();
    % carica i valori iniziali
    loadFactory();
    onScenarioOrPhaseChanged();  % aggiorna visibilità Dc

    % attesa modale
    uiwait(fig);
    if isvalid(fig), delete(fig); end

    % ===== nested helpers =====
    function onScenarioOrPhaseChanged()
        % ricarica i valori di default (o factory) per la coppia selezionata
        loadFactory();

        % mostra Dc solo se 'Restrittivo'
        isRestr = strcmpi(ddPhase.Value,'Restrittivo');
        if isRestr
            pDc.Visible = 'on';
        else
            pDc.Visible = 'off';
        end
    end

    function loadFactory()
        key   = ddScenario.Value;
        phase = iff(strcmpi(ddPhase.Value,'Restrittivo'),'restr','ord');
        scen  = app.getFactoryScenario(key, phase);   % DoseApp getter

        % popola tabella e Dc
        if isempty(scen.distanze), D = []; else, D = scen.distanze(:); end
        if isempty(scen.tempi),    T = []; else, T = scen.tempi(:);    end
        n = max(numel(D),numel(T));
        if n==0
            uit.Data = zeros(0,2);
        else
            if numel(D)<n, D(end+1:n,1) = NaN; end
            if numel(T)<n, T(end+1:n,1) = NaN; end
            uit.Data = [D, T];
        end
        edDc.Value = max(0, scen.DoseConstraint);
    end

    function addRow()
        d = uit.Data;
        if isempty(d), d = [NaN NaN]; else, d(end+1,:)= [NaN NaN]; end
        uit.Data = d;
    end

    function delRow()
        d = uit.Data;
        if ~isempty(d), d(end,:) = []; end
        uit.Data = d;
    end

    function cleanTable()
        d = uit.Data;
        if isempty(d), return; end
        % rimuovi righe totalmente vuote o non significative
        keep = ~(all(isnan(d),2) | all(d==0,2));
        d = d(keep,:);
        uit.Data = d;
    end

    function onApply()
        cleanTable();
        key   = ddScenario.Value;
        phase = iff(strcmpi(ddPhase.Value,'Restrittivo'),'restr','ord');

        d = uit.Data;
        if isempty(d)
            % consenti anche vuoto (interpretabile come "nessun contatto")
            dist = [];
            time = [];
        else
            dist = d(:,1)';  time = d(:,2)';
            % rimuovi NaN residui a coppie
            mask = ~(isnan(dist) | isnan(time));
            dist = dist(mask); time = time(mask);
        end

        out.action = 'apply';
        out.key    = key;
        out.phase  = phase;
        out.dist   = dist;
        out.time   = time;
        if strcmp(phase,'restr')
            out.Dc = edDc.Value;
        else
            out.Dc = [];
        end
        uiresume(fig);
    end

    function onCancel()
        out.action = 'cancel';
        uiresume(fig);
    end

    function onClear()
        out.action = 'clear';
        out.key    = ddScenario.Value;
        out.phase  = iff(strcmpi(ddPhase.Value,'Restrittivo'),'restr','ord');
        uiresume(fig);
    end
end
end
end
% ===== helpers esterni (file-scope) =====
function y = iff(c, a, b)
    if c
        y = a;
    else
        y = b;
    end
end

function scen = getFactoryScenario(app, key, phase)
    % app è l'istanza di DoseApp passata a ScenarioEditor.edit
    % normalizza eventualmente la fase
    if startsWith(lower(strtrim(phase)),'restr')
        phase = 'restr';
    else
        phase = 'ord';
    end
    scen = app.getFactoryScenario(key, phase);  % delega al getter pubblico
end


