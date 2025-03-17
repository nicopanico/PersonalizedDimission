Gamma = 0.058;
H = 1.70;
R_Tdis = 38.9; % µSv/h esempio reale

mod_lin = ModelloLineare(H, Gamma);

scen_res = Scenario.Madre(mod_lin);
scen_ord = Scenario('Ordinario',[2],[24],mod_lin);

fk = Farmacocinetica();

calc_dose = DoseCalculator(scen_res, scen_ord, fk, R_Tdis);

dose_totale = calc_dose.calcolaDoseTotale(7);
disp(['Dose totale (7 giorni restrizione): ', num2str(dose_totale), ' mSv']);

Dcons = scen_res.DoseConstraint;
Tres_ott = calc_dose.trovaPeriodoRestrizione(Dcons);
disp(['Periodo ottimale di restrizione: ', num2str(Tres_ott), ' giorni']);




