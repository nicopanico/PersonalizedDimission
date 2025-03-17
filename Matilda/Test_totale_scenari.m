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