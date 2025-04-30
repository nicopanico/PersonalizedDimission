classdef Scenario
    % Scenario di esposizione – versione “tuning” secondo Banci Buonamici 2025
    % Unità: distanze in metri  |  tempi in ore/giorno  |  DoseConstraint in mSv
    properties
        nome            string
        distanze        double
        tempi           double
        DoseConstraint  double
        modello        
    end

    methods
        function obj = Scenario(nome, distanze, tempi, modello, DoseConstraint)
            obj.nome           = nome;
            obj.distanze       = distanze;
            obj.tempi          = tempi;
            obj.modello        = modello;
            if nargin < 5, DoseConstraint = 0; end
            obj.DoseConstraint = DoseConstraint;
        end

        % -------- Fattore di correzione geometrico giornaliero ----------
        function Fcorr_scenario = calcolaFcorrScenario(obj, A_tot)
            if nargin < 2, A_tot = 1; end
            Fcorr_scenario = 0;
            for k = 1:numel(obj.distanze)
                Fcorr = obj.modello.calcolaFattoreCorrezione(obj.distanze(k),1,A_tot);
                Fcorr_scenario = Fcorr_scenario + (obj.tempi(k)/24)*Fcorr;
            end
        end
    end

    % ===================== FACTORY STATICHE ============================ %
    methods (Static)
        %% -------- Restrittivi --------
        function sc = Partner(m)
            sc = Scenario("Partner restr.", [0.3 1 4], [2 4 18], m, 3);
        end
        function sc = TrasportoPubblico(m)
            sc = Scenario("Trasporto restr.", [0.5 4], [0.5 23.5], m, 0.3);
        end
        function sc = Bambino_0_2(m)
            sc = Scenario("Bambino <2 restr.", [0.1 0.3 2], [1 3 20], m, 1);
        end
        function sc = Bambino_2_5(m)
            sc = Scenario("Bambino 2–5 restr.", [0.1 0.5 2], [1 3 20], m, 1);
        end
        function sc = Bambino_5_11(m)
            sc = Scenario("Bambino 5–11 restr.", [0.1 0.5 2], [0.5 2 21.5], m, 1);
        end
        function sc = DonnaIncinta(m)
            sc = Scenario("Incinta restr.", [1 2], [4 20], m, 1);
        end
        function sc = Colleghi(m)
            sc = Scenario("Colleghi restr.", [1 2], [2 22], m, 0.3);
        end

        %% -------- Ordinari --------
        function sc = Ordinario_Partner(m)
            sc = Scenario("Partner ord.", [1 2 4], [8 6 10], m, 0);
        end
        function sc = Ordinario_Trasporto(m)
            sc = Scenario("Trasporto ord.", [0.5 1 2], [0.5 3 20.5], m, 0);
        end
        function sc = Ordinario_Bambino(m)
            sc = Scenario("Bambino ord.", [0.3 1 2], [2 6 16], m, 0);
        end
        function sc = Ordinario_Incinta(m)
            sc = Scenario("Incinta ord.", [1 2], [6 18], m, 0);
        end
        function sc = Ordinario_Colleghi(m)
            sc = Scenario("Colleghi ord.", [2 4], [8 16], m, 0);
        end

        %% Ordinario generico
        function sc = OrdinarioBasico(m)
            sc = Scenario("Ordinario", 999, 24, m, 0);
        end
    end
end
