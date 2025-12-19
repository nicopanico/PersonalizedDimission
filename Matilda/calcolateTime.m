function results = calcolateTime(T_discharge, R_Tdis, selectedRF, scenarioRestrFunc, scenarioOrdFunc, modello, attivita)
    % T_discharge: tempo di discharge (giorni)
    % R_Tdis: rateo dose (µSv/h)
    % selectedRF: radiofarmaco
    % scenarioRestrFunc: handle (es. @Scenario.Madre)
    % scenarioOrdFunc: handle (es. @Scenario.Ordinario_Madre) oppure []
    % modello: oggetto ModelloLineare
    % attivita: attività in MBq (se ti serve per calcoli aggiuntivi)
    
    if nargin < 7
        attivita = 0; % se non serve, ignora
    end

    % Carica parametri radiofarmaco
    rph = loadRadiopharmaceutical(selectedRF, 'radiopharmaceuticals.json');
    fk = Farmacocinetica(rph.fr, rph.lambda_eff);
    
    % Aggiorna frazioni in base a T_discharge
    fk = fk.aggiornaFrazioni(T_discharge);
    
    % Crea scenario restrittivo
    restrScenario = scenarioRestrFunc(modello);
    if isempty(scenarioOrdFunc)
        % Se non c'è scenarioOrdFunc, scenarioOrd = scenario "vuoto" o come preferisci
        ordScenario = Scenario('Nessun Ordinario',[],[],modello,0);
    else
        ordScenario = scenarioOrdFunc(modello);
    end
    
    if contains(selectedRF,'I-131','IgnoreCase',true)
        factor = modello.calcolaFattoreCorrezione(1, 2); % dose(1 m)/dose(2 m)
        R_Tdis_eff = R_Tdis * factor;
    else
        R_Tdis_eff = R_Tdis;
    end

    calc_dose = DoseCalculator(restrScenario, ordScenario, fk, R_Tdis);
    
    % Calcolo dose totale per 7 giorni
    dose_totale = calc_dose.calcolaDoseTotale(7);
    % Trova T_res ottimale
    Tres_ott = calc_dose.trovaPeriodoRestrizione(restrScenario.DoseConstraint);

    results = struct('dose_totale', dose_totale, 'Tres_ott', Tres_ott);
end
