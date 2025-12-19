classdef GeoRestrictionPlots
% GeoRestrictionPlots
% Confronti di T_res dovuti SOLO alla geometria (lineare vs composita)
% a parità di farmacocinetica, scenari e R1m.
%
% Dipendenze: ModelloLineare, ModelloComposito, Scenario, DoseCalculator,
%   Farmacocinetica, getScenariosConfig, loadRadiopharmaceutical, JSON RF.

methods (Static)

%% ===================== 1) CONFRONTO SINGOLO ===================== %%
function T = compareTresOnce_byGeometry(RF, R1m_1m, Tdis_days, varargin)
% Confronta T_res (giorni) per TUTTI gli scenari (escluso Trasporto)
% Modello lineare vs Modello composito, a parità di fk e R1m.
%
% T = compareTresOnce_byGeometry('I-131', 25, 1.0);

opt = GeoRestrictionPlots.parseOpts(varargin{:});

% Modelli e fk
[ml, mc] = GeoRestrictionPlots.getModels(RF, opt);
fk = GeoRestrictionPlots.getFK(RF, Tdis_days);

% Scenari
cfg = getScenariosConfig();
cfg = cfg(~strcmp({cfg.key},'Trasporto'));  % niente T_res per Trasporto

rows = [];
for i = 1:numel(cfg)
    c = cfg(i);

    % Ordinario (rispetta opzione ≥2m per Colleghi)
    [ord_dist,ord_time,ord_dc,ord_lbl] = GeoRestrictionPlots.pickOrd(c, opt.UseWork2m);

    % Restrittivo
    restr_dist = c.restr.dist; restr_time = c.restr.time; restr_dc = c.restr.Dc;

    % Lineare
    S_restr_L = Scenario(c.label+" restr.", restr_dist, restr_time, ml, restr_dc);
    S_ord_L   = Scenario(ord_lbl,          ord_dist,   ord_time,   ml, ord_dc);
    dcL       = DoseCalculator(S_restr_L, S_ord_L, fk, R1m_1m);
    Tres_L    = dcL.trovaPeriodoRestrizione(restr_dc);
    Dose7_L   = dcL.calcolaDoseTotale(7);

    % Composito
    S_restr_C = Scenario(c.label+" restr.", restr_dist, restr_time, mc, restr_dc);
    S_ord_C   = Scenario(ord_lbl,          ord_dist,   ord_time,   mc, ord_dc);
    dcC       = DoseCalculator(S_restr_C, S_ord_C, fk, R1m_1m);
    Tres_C    = dcC.trovaPeriodoRestrizione(restr_dc);
    Dose7_C   = dcC.calcolaDoseTotale(7);

    rows = [rows; {c.key, c.label, Tres_L, Tres_C, (Tres_C-Tres_L), ...
                   100*((Tres_C-Tres_L)/max(Tres_L,eps)), Dose7_L, Dose7_C}];
end

T = cell2table(rows, 'VariableNames', ...
    {'key','Scenario','Tres_linear_d','Tres_comp_d','Delta_d','Delta_perc','Dose7_linear_mSv','Dose7_comp_mSv'});

% Bar plot Δ T_res
figure('Color','w','Name','ΔT_{res} (composito - lineare)');
bar(categorical(T.Scenario), T.Delta_d);
ylabel('\Delta T_{res} [giorni]'); grid on;
title(sprintf('%s | R_{1m}=%.1f µSv/h | T_{dis}=%.1f gg', RF, R1m_1m, Tdis_days));
end

%% ============== 2) SWEEP ΔT_res vs R1m (tutte le curve) ============== %%
function [R1m_vec, Delta, ScenLabels] = plotTresSweep_byR1m(RF, R1m_vec, Tdis_days, varargin)
% Traccia ΔT_res (composito-lineare) in funzione di R1m per ogni scenario.
%
% plotTresSweep_byR1m('Lu-177', 10:2:40, 1.0);

opt = GeoRestrictionPlots.parseOpts(varargin{:});

[ml, mc] = GeoRestrictionPlots.getModels(RF, opt);
fk       = GeoRestrictionPlots.getFK(RF, Tdis_days);

cfg = getScenariosConfig();
cfg = cfg(~strcmp({cfg.key},'Trasporto'));

ScenLabels = {cfg.label};
Delta = zeros(numel(R1m_vec), numel(cfg));

for s = 1:numel(cfg)
    c = cfg(s);

    [ord_dist,ord_time,ord_dc,ord_lbl] = GeoRestrictionPlots.pickOrd(c, opt.UseWork2m);
    restr_dist = c.restr.dist; restr_time = c.restr.time; restr_dc = c.restr.Dc;

    S_restr_L = Scenario(c.label+" restr.", restr_dist, restr_time, ml, restr_dc);
    S_ord_L   = Scenario(ord_lbl,          ord_dist,   ord_time,   ml, ord_dc);
    S_restr_C = Scenario(c.label+" restr.", restr_dist, restr_time, mc, restr_dc);
    S_ord_C   = Scenario(ord_lbl,          ord_dist,   ord_time,   mc, ord_dc);

    for k = 1:numel(R1m_vec)
        R1m = R1m_vec(k);
        Tres_L = DoseCalculator(S_restr_L, S_ord_L, fk, R1m).trovaPeriodoRestrizione(restr_dc);
        Tres_C = DoseCalculator(S_restr_C, S_ord_C, fk, R1m).trovaPeriodoRestrizione(restr_dc);
        Delta(k,s) = Tres_C - Tres_L;
    end
end

figure('Color','w','Name','ΔT_{res} vs R_{1m}');
hold on;
for s = 1:numel(cfg)
    plot(R1m_vec, Delta(:,s), 'LineWidth',1.6, 'DisplayName', ScenLabels{s});
end
grid on; xlabel('R_{1m} [\muSv/h]'); ylabel('\Delta T_{res} [giorni]');
title(sprintf('%s | T_{dis}=%.1f gg | geom: composito - lineare', RF, Tdis_days));
legend('Location','northwest');
end

%% ==================== 3) HEATMAP ΔT_res(R1m,Tdis) ==================== %%
function [M, R1m_vec, Tdis_vec] = plotTresHeatmap(RF, scenarioKeyOrLabel, R1m_vec, Tdis_vec, varargin)
% Heatmap di ΔT_res = T_res(composito) - T_res(lineare) su griglia (R1m, Tdis)
% per un singolo scenario.
%
% Esempi:
% plotTresHeatmap('I-131','Partner', 10:2:40, 0.5:0.5:5);
% plotTresHeatmap('Lu-177','Colleghi', 8:2:36, 0.5:0.5:7, 'UseWork2m',true);

opt = GeoRestrictionPlots.parseOpts(varargin{:});
[ml, mc] = GeoRestrictionPlots.getModels(RF, opt);

% recupera scenario dalla config (accetta key o label)
cfg = getScenariosConfig();
sel = [];
for i=1:numel(cfg)
    if strcmpi(cfg(i).key, scenarioKeyOrLabel) || strcmpi(cfg(i).label, scenarioKeyOrLabel)
        sel = cfg(i); break;
    end
end
if isempty(sel)
    error('Scenario "%s" non trovato in getScenariosConfig().', scenarioKeyOrLabel);
end
if strcmp(sel.key,'Trasporto')
    error('Lo scenario "Trasporto" non ha T_{res}. Scegli un altro scenario.');
end

[ord_dist,ord_time,ord_dc,ord_lbl] = GeoRestrictionPlots.pickOrd(sel, opt.UseWork2m);
restr_dist = sel.restr.dist; restr_time = sel.restr.time; restr_dc = sel.restr.Dc;

% prealloc matrice (rows = Tdis, cols = R1m)
M = zeros(numel(Tdis_vec), numel(R1m_vec));

for it = 1:numel(Tdis_vec)
    Tdis = Tdis_vec(it);
    fk   = GeoRestrictionPlots.getFK(RF, Tdis);

    S_restr_L = Scenario(sel.label+" restr.", restr_dist, restr_time, ml, restr_dc);
    S_ord_L   = Scenario(ord_lbl,            ord_dist,   ord_time,   ml, ord_dc);
    S_restr_C = Scenario(sel.label+" restr.", restr_dist, restr_time, mc, restr_dc);
    S_ord_C   = Scenario(ord_lbl,            ord_dist,   ord_time,   mc, ord_dc);

    for ir = 1:numel(R1m_vec)
        R1m = R1m_vec(ir);
        Tres_L = DoseCalculator(S_restr_L, S_ord_L, fk, R1m).trovaPeriodoRestrizione(restr_dc);
        Tres_C = DoseCalculator(S_restr_C, S_ord_C, fk, R1m).trovaPeriodoRestrizione(restr_dc);
        M(it, ir) = Tres_C - Tres_L;   % Δ giorni
    end
end

% --- plot heatmap ---
figure('Color','w','Name','Heatmap ΔT_{res}');
imagesc(R1m_vec, Tdis_vec, M);
set(gca,'YDir','normal');
colormap(parula); colorbar; grid on;
xlabel('R_{1m} [\muSv/h]'); ylabel('T_{dis} [giorni]');
title(sprintf('%s – %s | ΔT_{res} = comp - lin', RF, sel.label));

% linee guida rapide (0.3/1/2 m se utile per il tuo contesto? non qui)
% aggiungi livelli
hold on;
[cs,hc] = contour(R1m_vec, Tdis_vec, M, 'LineColor',[0 0 0], 'ShowText','on'); %#ok<ASGLU>
hc.LevelStep = 0.5;  % isolinee ogni 0.5 giorni (regola a piacere)
end

%% ======================== 4) WRAPPER “TUTTO” ======================== %%
function everythingDemo(RF, varargin)
% Comodo per provare rapidamente su impostazioni tipiche.
% Esempio:
% GeoRestrictionPlots.everythingDemo('I-131');

opt = GeoRestrictionPlots.parseOpts(varargin{:});

% set tipici
R1m0   = 25;             % µSv/h @1 m
Tdis0  = 1.0;            % giorni
Rvec   = 10:2:40;        % sweep R1m
Tvec   = 0.5:0.5:5.0;    % sweep Tdis
scen   = 'Partner';

GeoRestrictionPlots.compareTresOnce_byGeometry(RF, R1m0, Tdis0, varargin{:});
GeoRestrictionPlots.plotTresSweep_byR1m(RF, Rvec, Tdis0, varargin{:});
GeoRestrictionPlots.plotTresHeatmap(RF, scen, Rvec, Tvec, varargin{:});
end

end % static methods

%% ======================== HELPERS PRIVATI ======================== %%
methods (Static, Access=private)

function opt = parseOpts(varargin)
p = inputParser;
addParameter(p,'Hline',1.70);
addParameter(p,'mu_I',8.0);
addParameter(p,'mu_Lu',12.0);
addParameter(p,'b1_int',[]);     % build-up interno (max addizionale)
addParameter(p,'b1_path',[]);    % build-up lungo cammino
addParameter(p,'UseWork2m',false);
parse(p, varargin{:});
opt = p.Results;
end

function [ml, mc] = getModels(RF, opt)
% Crea il modello lineare e il composito con le opzioni richieste
ml = ModelloLineare(opt.Hline);

if contains(RF,'I-131','IgnoreCase',true)
    if isempty(opt.b1_int) && isempty(opt.b1_path)
        mc = ModelloComposito.forI131('mu_t',opt.mu_I,'d_ref',1.0);
    else
        mc = ModelloComposito.forI131('mu_t',opt.mu_I,'d_ref',1.0, ...
                                      'b1_int',opt.b1_int,'b1_path',opt.b1_path);
    end
else
    % Lu-177, DOTATATE, PSMA, ecc.
    if isempty(opt.b1_int) && isempty(opt.b1_path)
        mc = ModelloComposito.forLu177('mu_t',opt.mu_Lu,'d_ref',1.0);
    else
        mc = ModelloComposito.forLu177('mu_t',opt.mu_Lu,'d_ref',1.0, ...
                                       'b1_int',opt.b1_int,'b1_path',opt.b1_path);
    end
end
end

function fk = getFK(RF, Tdis_days, varargin)
    % RF può essere:
    %  - stringa (nome “umano”: es. 'I-131', 'Lu-177', 'DOTATATE', 'PSMA', o il name esatto dal JSON)
    %  - struct con campi .fr e .lambda_eff
    %  - oppure puoi passare fr/lambda via varargin: 'fr',[...], 'lambda',[...]

    % --- override diretto via varargin?
    p = inputParser;
    addParameter(p,'json','radiopharmaceuticals.json');
    addParameter(p,'fr',[]);
    addParameter(p,'lambda',[]);
    parse(p,varargin{:});
    jsonPath = p.Results.json;
    fr_override = p.Results.fr;
    lam_override = p.Results.lambda;

    % --- caso RF già come struct fr/lambda
    if isstruct(RF) && isfield(RF,'fr') && isfield(RF,'lambda_eff')
        fr = RF.fr; lam = RF.lambda_eff;

        % --- override via varargin
    elseif ~isempty(fr_override) && ~isempty(lam_override)
        fr = fr_override; lam = lam_override;

        % --- altrimenti leggo dal JSON con fuzzy-match
    else
        key = lower(string(RF));
        data = jsondecode(fileread(jsonPath));
        names = string({data.name});
        namesL = lower(names);

        % 1) match esatto
        idx = find(namesL == key, 1);

        % 2) fuzzy: contiene la chiave
        if isempty(idx)
            cand = contains(namesL, key);
            % heuristics per I-131 / Lu-177 / DOTATATE / PSMA
            if ~any(cand)
                if contains(key, {'i-131','i131','iodio'})
                    cand = contains(namesL,'i-131') | contains(namesL,'iodio');
                elseif contains(key, {'lu-177','lu177','lutet'}) || contains(key, {'dotatate','psma'})
                    cand = contains(namesL,'lu-177') | contains(namesL,'lutet') | contains(namesL,'dotatate') | contains(namesL,'psma');
                end
            end
            idx = find(cand, 1, 'first');
        end

        if isempty(idx)
            error('RF "%s" non trovato in %s. Disponibili: %s', ...
                RF, jsonPath, strjoin(cellstr(names), ', '));
        end

        fr  = data(idx).fr;
        lam = data(idx).lambda_eff;

        fprintf('RF "%s" → uso entry JSON: "%s".\n', string(RF), data(idx).name);
    end

    fk = Farmacocinetica(fr, lam).aggiornaFrazioni(Tdis_days);
end

function [dist,time,dc,label] = pickOrd(c, use2m)
% Ord standard vs ≥2 m per Colleghi
if strcmp(c.key,'Colleghi') && use2m && ~isempty(c.ord2m.dist)
    dist = c.ord2m.dist; time = c.ord2m.time; dc = c.ord2m.Dc;
    label = c.label + " ord. ≥2 m";
else
    dist = c.ord.dist;   time = c.ord.time;   dc = c.ord.Dc;
    label = c.label + " ord.";
end
end

end % helpers

end
