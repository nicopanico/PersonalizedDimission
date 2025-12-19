classdef Scenario
%SCENARIO  Scenario di esposizione (fase restrittiva o ordinaria).
%
% DESCRIZIONE
%   Rappresenta un profilo di contatto giornaliero suddiviso in N "blocchi":
%     - distanze(k) : distanza media del blocco k [m]
%     - tempi(k)    : durata del blocco k [h/giorno]
%
%   Lo scenario è collegato a un modello geometrico (es. ModelloLineare) che
%   fornisce il fattore di correzione Fcorr(d) rispetto al rateo a 1 m.
%
% UNITA'
%   - distanze      : metri (m)
%   - tempi         : ore al giorno (h/d)
%   - DoseConstraint: mSv (vincolo di dose per lo scenario restrittivo)
%
% NOTE OPERATIVE
%   - I contatti "lontani" (es. 999 m) possono essere usati come placeholder
%     per rappresentare tempi trascurabili ai fini della dose.
%   - La funzione calcolaFcorrScenario() restituisce un Fcorr medio giornaliero:
%
%       Fcorr_scenario = Σ_k (tempi(k)/24) * Fcorr(distanze(k))
%
%   - Per scenari con distanze/tempi vuoti (es. Assenza lavoro in restrittivo),
%     Fcorr_scenario risulta 0, come atteso.
%
% Nicola Panico - 19/12/2025

    properties
        nome            string
        distanze        double
        tempi           double
        DoseConstraint  double
        modello         % modello geometrico (es. ModelloLineare)
    end

    methods
        function obj = Scenario(nome, distanze, tempi, modello, DoseConstraint)
            % Costruttore.
            %
            % USO:
            %   scen = Scenario(nome, distanze, tempi, modello)
            %   scen = Scenario(nome, distanze, tempi, modello, DoseConstraint)
            %
            % INPUT:
            %   nome          : string/char descrittiva (es. "Partner restr.")
            %   distanze      : vettore [m]
            %   tempi         : vettore [h/giorno], stessa lunghezza di distanze
            %   modello       : oggetto con metodo calcolaFattoreCorrezione(d,1,A)
            %   DoseConstraint: (opzionale) vincolo [mSv] - tipicamente >0 solo in fase restrittiva

            if nargin < 5, DoseConstraint = 0; end

            obj.nome           = string(nome);
            obj.distanze       = distanze;
            obj.tempi          = tempi;
            obj.modello        = modello;
            obj.DoseConstraint = DoseConstraint;

            % Validazioni minime (robuste per uso in GUI/compilato)
            obj = obj.validate();
        end

        function Fcorr_scenario = calcolaFcorrScenario(obj, A_tot)
            %CALCOLAFCORRSCENARIO  Fattore di correzione medio giornaliero dello scenario.
            %
            % INPUT:
            %   A_tot : (opzionale) attività totale (unità arbitrarie coerenti col modello).
            %          In DoseApp di norma si usa A_tot = 1 perché serve un fattore relativo.
            %
            % OUTPUT:
            %   Fcorr_scenario : fattore adimensionale medio su 24 h, pesato sui tempi.
            %
            % NOTE:
            %   La funzione del modello calcolaFattoreCorrezione(d,1,A_tot) deve restituire
            %   un rapporto relativo rispetto a 1 m (oppure un valore equivalente coerente).
            %   Qui si integra su 24 h tramite (tempi/24).

            if nargin < 2 || isempty(A_tot)
                A_tot = 1;
            end

            % Scenario vuoto => Fcorr = 0 (es. assenza lavoro in fase restrittiva)
            if isempty(obj.distanze) || isempty(obj.tempi)
                Fcorr_scenario = 0;
                return;
            end

            Fcorr_scenario = 0;

            for k = 1:numel(obj.distanze)
                % Fcorr(d) relativo a 1 m (o coerente col tuo modello)
                Fcorr_k = obj.modello.calcolaFattoreCorrezione(obj.distanze(k), 1, A_tot);

                % peso temporale sul giorno (tempi in ore/giorno)
                Fcorr_scenario = Fcorr_scenario + (obj.tempi(k) / 24) * Fcorr_k;
            end
        end
    end

    methods (Access = private)
        function obj = validate(obj)
            %VALIDATE  Controlli di coerenza su input scenario.
            %
            % - distanze e tempi devono avere stessa dimensione
            % - tempi >= 0
            % - distanze > 0 (o >=0 se vuoi ammettere 0; qui richiedo >0)
            % - DoseConstraint >= 0

            if isempty(obj.modello)
                error('Scenario non valido: "modello" non può essere vuoto.');
            end

            % Permetti scenario vuoto (usato per "nessun contatto"): distanze/tempi entrambi vuoti
            if isempty(obj.distanze) && isempty(obj.tempi)
                return;
            end

            if isempty(obj.distanze) || isempty(obj.tempi)
                error('Scenario non valido: "distanze" e "tempi" devono essere entrambi vuoti oppure entrambi valorizzati.');
            end

            if numel(obj.distanze) ~= numel(obj.tempi)
                error('Scenario non valido: "distanze" e "tempi" devono avere la stessa lunghezza.');
            end

            if any(~isfinite(obj.distanze)) || any(~isfinite(obj.tempi))
                error('Scenario non valido: "distanze" e "tempi" devono contenere solo valori finiti.');
            end

            if any(obj.tempi < 0)
                error('Scenario non valido: "tempi" deve essere >= 0 (ore/giorno).');
            end

            if any(obj.distanze <= 0)
                error('Scenario non valido: "distanze" deve essere > 0 (metri).');
            end

            if ~isfinite(obj.DoseConstraint) || obj.DoseConstraint < 0
                error('Scenario non valido: "DoseConstraint" deve essere finito e >= 0 (mSv).');
            end
        end
    end
end


