classdef DoseCalculator
    properties
        scenarioRestrizione
        scenarioOrdinario
        farmacocinetica
        R_Tdis % (µSv/h)
    end

    methods
        % Costruttore (perfetto)
        function obj = DoseCalculator(scenarioRestrizione, scenarioOrdinario, farmacocinetica, R_Tdis)
            obj.scenarioRestrizione = scenarioRestrizione;
            obj.scenarioOrdinario = scenarioOrdinario;
            obj.farmacocinetica = farmacocinetica;
            obj.R_Tdis = R_Tdis;
        end

        % Metodo corretto definitivo dose totale
        function dose = calcolaDoseTotale(obj, T_res)
            Fcorr_res = obj.scenarioRestrizione.calcolaFcorrScenario(1);
            Fcorr_ord = obj.scenarioOrdinario.calcolaFcorrScenario(1);
            somma_fk = 0;
            for i=1:length(obj.farmacocinetica.fr)
                lambda_i = obj.farmacocinetica.lambda_eff(i);
                fr_i = obj.farmacocinetica.fr(i);
                termine_res = Fcorr_res*(1-exp(-lambda_i*T_res));
                termine_ord = Fcorr_ord*exp(-lambda_i*T_res);
                somma_fk = somma_fk + (fr_i/lambda_i)*(termine_res + termine_ord);
            end
            dose = obj.R_Tdis * somma_fk * 24 / 1000; % mSv
        end
        
        % Metodo corretto definitivo periodo restrizione ottimale
        function Tres_ottimale = trovaPeriodoRestrizione(obj, Dcons)
            % Definizione intervallo di ricerca
            Tmin = 0.1;  % Giorno minimo di restrizione
            Tmax = 30;   % Giorno massimo di restrizione
            Tol = 0.01;  % Tolleranza sulla dose per fermare la ricerca

            % Inizializzazione
            Tres = Tmin;
            dose_calcolata = obj.calcolaDoseTotale(Tres);

            % Se già inferiore al constraint, restituisci direttamente
            if dose_calcolata <= Dcons
                Tres_ottimale = Tres;
                return;
            end

            % Se già superiore anche a 30 giorni, restituisci warning
            dose_max = obj.calcolaDoseTotale(Tmax);
            if dose_max > Dcons
                warning('Periodo superiore a 30 giorni!');
                Tres_ottimale = Tmax;
                return;
            end

            % Ricerca iterativa ottimizzata (bisezione)
            while (Tmax - Tmin) > Tol
                Tres = (Tmin + Tmax) / 2; % Media dell'intervallo
                dose_calcolata = obj.calcolaDoseTotale(Tres);

                if dose_calcolata > Dcons
                    Tmin = Tres; % Aumenta il periodo minimo
                else
                    Tmax = Tres; % Diminuisci il massimo
                end
            end

            Tres_ottimale = Tres;
        end
    end
end
