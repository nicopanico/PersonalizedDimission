%% Test completo del modello per vari scenari
clear; clc;

% Parametri iniziali
Gamma = 0.058;       % costante gamma (µSv·m²/MBq·h)
H = 1.70;            % altezza (m)
R_Tdis = 30;         % rateo dose a Tdis (µSv/h) misurato al momento della dimissione

% Creazione del modello lineare
mod_lin = ModelloLineare(H, Gamma);

% Scenari ristretti predefiniti (secondo Buonamici)
scenari_restr = [Scenario.Madre(mod_lin), Scenario.Partner(mod_lin), ...
                 Scenario.Collega(mod_lin), Scenario.Familiare(mod_lin)];

% Scenari ordinari predefiniti: scegliamo lo scenario ordinario più appropriato, ad es. "Ordinario Familiare"
scenario_ordinario = Scenario.Ordinario_Familiare(mod_lin);

% Carica la farmacocinetica (di default per I-131, oppure sostituibile con dati personalizzati)
fk = Farmacocinetica();

fprintf('Test definitivo - Tutti gli scenari (R_Tdis = %g µSv/h)\n', R_Tdis);
disp('-------------------------------------------------------');

for k = 1:length(scenari_restr)
    % Creazione oggetto DoseCalculator per ogni scenario
    calc_dose = DoseCalculator(scenari_restr(k), scenario_ordinario, fk, R_Tdis);
    
    % Calcolo della dose totale per un periodo di restrizione di 7 giorni
    dose_totale = calc_dose.calcolaDoseTotale(7);
    
    % Calcolo della dose subito dopo T_res (per esempio a 0.1 giorni)
    dose_subito_dopo = calc_dose.calcolaDoseTotale(25);
    
    % Estrazione del Dose Constraint per lo scenario restrittivo
    Dcons = scenari_restr(k).DoseConstraint;
    
    % Calcolo del periodo ottimale di restrizione per soddisfare il constraint
    Tres_ott = calc_dose.trovaPeriodoRestrizione(Dcons);
    
    % Stampa dei risultati
    fprintf('Scenario: %s\n', scenari_restr(k).nome);
    fprintf('- Dose Constraint: %.2f mSv\n', Dcons);
    fprintf('- Dose totale (7 giorni restrizione): %.4f mSv\n', dose_totale);
    fprintf('- Dose subito dopo T_res (20 giorni): %.4f mSv\n', dose_subito_dopo);
    fprintf('- Periodo ottimale restrizione: %.2f giorni\n', Tres_ott);
    disp('-------------------------------------------------------');
end
% Parametri iniziali
Gamma = 0.058;
H = 1.70;
R_Tdis = 20; % µSv/h (misurato alla dimissione)

% Modello lineare
mod_lin = ModelloLineare(H, Gamma);

% Farmacocinetica
fk = Farmacocinetica();

% Scenario ordinario (tipico)
% scen_ord = Scenario('Ordinario', [3], [24], mod_lin, 0);

% Tutti scenari predefiniti
scenari = [Scenario.Madre(mod_lin),...
            Scenario.Partner(mod_lin),...
            Scenario.Collega(mod_lin),...
            Scenario.Familiare(mod_lin)];

% Loop per calcolare tutti gli scenari
fprintf('Test definitivo - Tutti gli scenari (R_Tdis = %g µSv/h)\n', R_Tdis);
disp('-------------------------------------------------------');

for k = 1:length(scenari)
    % Creazione DoseCalculator per ogni scenario
    calc_dose = DoseCalculator(scenari(k), scen_ord, fk, R_Tdis);

    % Calcolo dose totale con 7 giorni di restrizione
    dose_totale = calc_dose.calcolaDoseTotale(7);
    
    % Calcolo dose subito dopo T_res
    dose_subito_dopo = calc_dose.calcolaDoseTotale(0.1);  % Dose immediata

    % Calcolo periodo ottimale di restrizione
    Dcons = scenari(k).DoseConstraint;
    Tres_ott = calc_dose.trovaPeriodoRestrizione(Dcons);

    % Stampa risultati
    disp(['Scenario: ', scenari(k).nome]);
    disp(['- Dose Constraint: ', num2str(Dcons), ' mSv']);
    disp(['- Dose totale (7 giorni restrizione): ', num2str(dose_totale), ' mSv']);
    disp(['- Dose subito dopo T_res: ', num2str(dose_subito_dopo), ' mSv']);
    disp(['- Periodo ottimale restrizione: ', num2str(Tres_ott), ' giorni']);
    disp('-------------------------------------------------------');
end
