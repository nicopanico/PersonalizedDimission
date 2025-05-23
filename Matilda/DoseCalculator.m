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
            dose = obj.R_Tdis *24* dose_tot / 1000;
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
    methods
        function plotDoseCurve(obj, fk, selectedRF)
            % fk è la Farmacocinetica usata (già parte di obj, ma passo esplicito
            % se vuoi riutilizzarla altrove)

            Tres_opt = obj.trovaPeriodoRestrizione(obj.scenarioRestrizione.DoseConstraint);

            Tvec = linspace(0.1,60,300);
            dose_tot = zeros(size(Tvec));
            dose_r   = zeros(size(Tvec));
            dose_o   = zeros(size(Tvec));

            Fr = obj.scenarioRestrizione.calcolaFcorrScenario(1);
            Fo = obj.scenarioOrdinario  .calcolaFcorrScenario(1);

            for k = 1:numel(Tvec)
                T = Tvec(k);
                sr = 0; so = 0;
                for i = 1:numel(fk.fr)
                    fr_i = fk.fr(i); lam = fk.lambda_eff(i);
                    sr   = sr + fr_i/lam * Fr*(1-exp(-lam*T));
                    so   = so + fr_i/lam * Fo*exp(-lam*T);
                end
                dose_r(k) = obj.R_Tdis*24*sr/1000;
                dose_o(k) = obj.R_Tdis*24*so/1000;
                dose_tot(k)=dose_r(k)+dose_o(k);
            end

            figure('Name','Dose vs T_{res}');
            plot(Tvec,dose_tot,'b-',Tvec,dose_r,'g--',Tvec,dose_o,'m-.','LineWidth',1.5); hold on
            yline(obj.scenarioRestrizione.DoseConstraint,'r--','Limite dose');
            plot(Tres_opt,obj.calcolaDoseTotale(Tres_opt),'ko','MarkerFaceColor','k');
            title(['Dose per ',selectedRF,' – ',obj.scenarioRestrizione.nome]);
            xlabel('T_{res} [giorni]'); ylabel('Dose [mSv]'); grid on
            legend('Tot','Restr.','Ordin.','Limite','T_{res}^{opt}');
        end
    end
end

