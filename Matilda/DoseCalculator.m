classdef DoseCalculator
    properties
        scenarioRestrizione
        scenarioOrdinario
        farmacocinetica
        R_Tdis % µSv/h
    end

    methods
        function obj = DoseCalculator(scenarioRestrizione, scenarioOrdinario, farmacocinetica, R_Tdis)
            obj.scenarioRestrizione = scenarioRestrizione;
            obj.scenarioOrdinario   = scenarioOrdinario;
            obj.farmacocinetica     = farmacocinetica;
            obj.R_Tdis             = R_Tdis;
        end

        % Calcolo della dose totale come funzione di T_res (in giorni)
        function dose = calcolaDoseTotale(obj, T_res)
            % Se T_res=0 => dose solo scenario ordinario, ma tipicamente T_res>0
            F_r = obj.scenarioRestrizione.calcolaFcorrScenario(1);
            F_o = obj.scenarioOrdinario.calcolaFcorrScenario(1);

            dose_tot = 0;
            for i = 1:length(obj.farmacocinetica.fr)
                fr_i     = obj.farmacocinetica.fr(i);
                lambda_i = obj.farmacocinetica.lambda_eff(i);  % in 1/giorno

                % Fase restrittiva: [0 -> T_res] (nessun *24, T_res in giorni)
                dose_restr = (fr_i / lambda_i) * F_r * (1 - exp(-lambda_i * T_res));

                % Fase ordinaria: [T_res -> ∞]
                dose_ord  = (fr_i / lambda_i) * F_o * exp(-lambda_i * T_res);

                dose_tot = dose_tot + dose_restr + dose_ord;
            end

            % Moltiplico per R_Tdis (µSv/h)
            % => devo convertire "dose_tot" in "ore" ? In realtà no,
            %    la formula di Buonamici è costruita in modo che l'integrazione
            %    dia come "unità" => "frazione della dose" da moltiplicare
            %    per R_Tdis (µSv/h) * (un fattore?)
            %
            %    Nella derivazione "classica" se λ è in 1/h e T in h,
            %    appare un *24. Qui λ in 1/g, T in g => niente *24.
            %    R_Tdis -> µSv/h => per ottenere mSv, /1000.
            %    E' "coerente" con la formula che usi negli esponenziali
            %    in scenario restrittivo: (1 - e^-lambda * T_res) => T in giorni
            %
            % "Trick" per rimanere coerenti col paper:
            dose = obj.R_Tdis * dose_tot / 1000;
        end

        function Tres_ottimale = trovaPeriodoRestrizione(obj, Dcons)
            if Dcons <= 0
                Tres_ottimale = 0;
                return;
            end

            Tmin = 0.1;  % gg
            Tmax = 60;   % gg
            Tol  = 0.01;

            if obj.calcolaDoseTotale(Tmin) <= Dcons
                Tres_ottimale = Tmin;
                return;
            end

            if obj.calcolaDoseTotale(Tmax) > Dcons
                warning('Non si riesce a soddisfare Dcons anche con T_res=60 gg');
                Tres_ottimale = Tmax;
                return;
            end

            while (Tmax - Tmin) > Tol
                Tmed = (Tmin + Tmax)/2;
                dose_curr = obj.calcolaDoseTotale(Tmed);
                if dose_curr > Dcons
                    Tmin = Tmed;
                else
                    Tmax = Tmed;
                end
            end
            Tres_ottimale = (Tmin + Tmax)/2;
        end
    end
end

