classdef ModelloCilindrico < ModelloGeometrico
    properties
        H % altezza cilindro (m)
        R % raggio cilindro (m)
        Gamma % costante gamma
        nR % divisioni radiali
        nZ % divisioni verticali
    end
    
    methods
        % Costruttore esplicito con TUTTI gli input necessari
        function obj = ModelloCilindrico(H, R, Gamma, nR, nZ)
            obj.H = H;
            obj.R = R;
            obj.Gamma = Gamma;
            obj.nR = nR;
            obj.nZ = nZ;
        end
        
        % Implementazione OBBLIGATORIA metodo astratto calcolaDose
        function dose = calcolaDose(obj, distanza, A_tot)
            dr = obj.R / obj.nR;
            dz = obj.H / obj.nZ;
            V_tot = pi * obj.R^2 * obj.H;
            dose = 0;
            for ir = 1:obj.nR
                for iz = 1:obj.nZ
                    r = (ir - 0.5) * dr;
                    z = (iz - 0.5) * dz - obj.H / 2;
                    vol_el = 2 * pi * r * dr * dz;
                    f_n = vol_el / V_tot;
                    r_n = sqrt(distanza^2 + r^2 + z^2);
                    dose = dose + obj.Gamma * A_tot * f_n / r_n^2;
                end
            end
        end
        
        % Implementazione OBBLIGATORIA metodo astratto calcolaFattoreCorrezione
        function Fcorr = calcolaFattoreCorrezione(obj, d, d_ref, A_tot)
            dose_ref = obj.calcolaDose(d_ref, A_tot);
            dose_d = obj.calcolaDose(d, A_tot);
            Fcorr = dose_d / dose_ref;
        end
    end
end

