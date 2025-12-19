classdef ModelloLineare < ModelloGeometrico
%MODELLOLINEARE  Modello geometrico "line-source" assiale per il paziente.
%
% DESCRIZIONE
%   Implementa un modello semplificato in cui il paziente è rappresentato
%   come una sorgente lineare di altezza H (asse verticale). Il rateo di dose
%   (in forma normalizzata) a distanza d è modellato da:
%
%       dose(d) = Gamma * (A_tot / (H*d)) * atan( H / (2*d) )
%
%   dove Gamma è scelto (di default) per normalizzare la funzione in modo che:
%       dose(1 m) = 1   quando A_tot = 1
%
%   Questo consente di usare "dose(d)" come fattore relativo (adimensionale)
%   rispetto a 1 m, utile per calcolare:
%       Fcorr(d) = dose(d) / dose(d_ref)
%
% UNITA'
%   - H       : metri (m)
%   - d, d_ref: metri (m)
%   - A_tot   : adimensionale o attività in unità arbitrarie coerenti
%              (nella pratica DoseApp usa A_tot=1 per fattori relativi)
%   - dose(d) : valore relativo (adimensionale) se Gamma è normalizzata
%
% NOTE
%   - Questo modello è pensato per geometria e scaling relativo, non per
%     calcoli assoluti in Gy/h o simili.
%   - Se d o d_ref sono molto piccoli (→0), la formula diverge: qui imponiamo
%     un controllo per evitare risultati non fisici / divisioni per zero.
%
% Nicola Panico - 19/12/2025

    properties
        H      % Altezza effettiva del paziente (line source) [m]
        Gamma  % Costante di normalizzazione (adimensionale nel setting relativo)
    end

    methods
        function obj = ModelloLineare(H, Gamma)
            % Costruttore.
            %
            % USO:
            %   m = ModelloLineare(H)            -> Gamma calcolata automaticamente
            %   m = ModelloLineare(H, Gamma)     -> Gamma assegnata manualmente
            %
            % INPUT:
            %   H     : altezza paziente/sorgente lineare [m], tipicamente ~1.7
            %   Gamma : (opzionale) costante di normalizzazione
            %
            % DEFAULT:
            %   Se Gamma non è fornita, viene calcolata imponendo:
            %     dose(1 m) = 1 con A_tot=1
            %   cioè:
            %     1 = Gamma * (1/(H*1)) * atan(H/2)
            %     Gamma = H / atan(H/2)

            if nargin < 1 || isempty(H)
                error('ModelloLineare: H deve essere specificata (in metri).');
            end
            if ~isfinite(H) || H <= 0
                error('ModelloLineare: H deve essere un valore finito e > 0 (m).');
            end

            obj.H = H;

            if nargin < 2 || isempty(Gamma)
                obj.Gamma = H / atan(H/2);
            else
                if ~isfinite(Gamma) || Gamma <= 0
                    error('ModelloLineare: Gamma deve essere un valore finito e > 0.');
                end
                obj.Gamma = Gamma;
            end
        end

        function dose = calcolaDose(obj, distanza, A_tot)
            %CALCOLADOSE  Calcola la "dose" relativa a distanza d.
            %
            % INPUT:
            %   distanza : distanza dal paziente [m]
            %   A_tot    : (opzionale) attività totale (default = 1)
            %
            % OUTPUT:
            %   dose : valore relativo (adimensionale se Gamma normalizzata)
            %
            % FORMULA:
            %   dose(d) = Gamma * (A_tot / (H*d)) * atan(H/(2*d))

            if nargin < 3 || isempty(A_tot)
                A_tot = 1;
            end

            if ~isfinite(distanza) || distanza <= 0
                error('calcolaDose: "distanza" deve essere finita e > 0 (m).');
            end
            if ~isfinite(A_tot) || A_tot < 0
                error('calcolaDose: "A_tot" deve essere finita e >= 0.');
            end

            dose = obj.Gamma * (A_tot / (obj.H * distanza)) * atan(obj.H / (2 * distanza));
        end

        function Fcorr = calcolaFattoreCorrezione(obj, d, d_ref, A_tot)
            %CALCOLAFATTORECORREZIONE  Rapporto tra dose(d) e dose(d_ref).
            %
            % INPUT:
            %   d      : distanza di interesse [m]
            %   d_ref  : distanza di riferimento [m] (tipicamente 1 m)
            %   A_tot  : (opzionale) attività totale (default = 1)
            %
            % OUTPUT:
            %   Fcorr  : fattore di correzione geometrico (adimensionale)
            %
            % NOTE:
            %   Se A_tot è lo stesso in numeratore e denominatore, si semplifica.
            %   Lo lasciamo per completezza e coerenza con la firma.

            if nargin < 4 || isempty(A_tot)
                A_tot = 1;
            end

            if ~isfinite(d_ref) || d_ref <= 0
                error('calcolaFattoreCorrezione: "d_ref" deve essere finita e > 0 (m).');
            end

            dose_d   = obj.calcolaDose(d,     A_tot);
            dose_ref = obj.calcolaDose(d_ref, A_tot);

            if dose_ref <= 0
                error('calcolaFattoreCorrezione: dose_ref non valida (<=0). Controlla d_ref e parametri.');
            end

            Fcorr = dose_d / dose_ref;
        end
    end
end

