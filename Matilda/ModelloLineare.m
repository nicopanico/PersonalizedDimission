classdef ModelloLineare < ModelloGeometrico
    properties
        H      % altezza effettiva del paziente (line source), in metri
        Gamma  % costante di normalizzazione
    end
    
    methods
        function obj = ModelloLineare(H, Gamma)
            % Se il costruttore riceve un valore di Gamma,
            % lo usa direttamente; altrimenti lo calcola
            % in modo che dose(1 m) = 1 con A_tot=1
            if nargin < 2 || isempty(Gamma)
                obj.H = H;
                % Calcolo automatico di Gamma:
                % dose(1) = Gamma * (1 / (H*1)) * atan(H/(2*1)) = 1
                % => Gamma = H / atan(H/2)
                obj.Gamma = H / atan(H/2);
            else
                obj.H = H;
                obj.Gamma = Gamma;
            end
        end
        
        function dose = calcolaDose(obj, distanza, A_tot)
            % Se l'utente non specifica A_tot, poniamolo = 1
            if nargin < 3
                A_tot = 1;
            end
            
            % dose(d) = Gamma * (A_tot / (H*d)) * atan(H/(2*d))
            dose = obj.Gamma * (A_tot / (obj.H * distanza)) * ...
                   atan( obj.H / (2 * distanza) );
        end
        
        function Fcorr = calcolaFattoreCorrezione(obj, d, d_ref, A_tot)
            if nargin < 4
                A_tot = 1;
            end
            
            dose_d   = obj.calcolaDose(d,     A_tot);
            dose_ref = obj.calcolaDose(d_ref, A_tot);
            Fcorr    = dose_d / dose_ref;  
        end
    end
end


