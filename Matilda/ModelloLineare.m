classdef ModelloLineare < ModelloGeometrico
    properties
        H % altezza linea sorgente (m)
        Gamma % costante gamma
    end
    
    methods
        function obj = ModelloLineare(H, Gamma)
            obj.H = H;
            obj.Gamma = Gamma;
        end
        
        % Metodo obbligatorio astratto
        function dose = calcolaDose(obj, distanza, A_tot)
            dose = obj.Gamma * (A_tot / (obj.H * distanza)) * atan(obj.H / (2 * distanza));
        end
        
        % Metodo obbligatorio astratto
        function Fcorr = calcolaFattoreCorrezione(obj, d, d_ref, A_tot)
            dose_ref = obj.calcolaDose(d_ref, A_tot);
            dose_d = obj.calcolaDose(d, A_tot);
            Fcorr = dose_d / dose_ref;
        end
    end
end

