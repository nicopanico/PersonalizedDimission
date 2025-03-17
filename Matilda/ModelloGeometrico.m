classdef (Abstract) ModelloGeometrico
    % Classe astratta per modelli geometrici sorgenti
    
    methods (Abstract)
        dose = calcolaDose(obj, distanza, A_tot, Gamma)
        Fcorr = calcolaFattoreCorrezione(obj, d, d_ref, A_tot)
    end
end
