classdef Scenario
    % Scenario di esposizione – definizioni da Tabella 2 e 3 di Buonamici 2025
    % Unità: distanze in metri  |  tempi in ore/giorno  |  DoseConstraint in mSv

    properties
        nome            string
        distanze        double
        tempi           double
        DoseConstraint  double
        modello         % modello geometrico (e.g. ModelloLineare)
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

        function Fcorr_scenario = calcolaFcorrScenario(obj, A_tot)
            if nargin < 2, A_tot = 1; end
            Fcorr_scenario = 0;
            for k = 1:numel(obj.distanze)
                Fcorr = obj.modello.calcolaFattoreCorrezione(obj.distanze(k),1,A_tot);
                Fcorr_scenario = Fcorr_scenario + (obj.tempi(k)/24) * Fcorr;
            end
        end
    end

    methods (Static)
        %% -------- SCENARI RESTRITTIVI (Tabella 2) --------
        function sc = Partner(m)
            % Contact with partner (small apt. or same bed)
            %  8 h @ 0.3 m, 6 h @ 1 m, constraint = 3 mSv
            sc = Scenario("Partner restr.",[0.3, 1.0],[8, 6],m,3.0);
        end
        function sc = NessunaRestr(m)
            % Nessuna fase restrittiva
            sc = Scenario("No restr.", [], [], m, 0.3);
        end

        function sc = TrasportoPubblico(m)
            % Travel in public transport
            %  0.5 h @ 0.1 m, constraint = 0.3 mSv
            sc = Scenario("Trasporto restr.",[0.1],[0.5],m,0.3);
        end

        function sc = Bambino_0_2(m)
            % Contact with child <2 y
            %  9 h @ 0.1 m, constraint = 1 mSv
            sc = Scenario("Bambino <2 restr.",[0.1],[9],m,1.0);
        end

        function sc = Bambino_2_5(m)
            % Contact with child 2-5 y
            %  4 h @ 0.1 m, 8 h @ 1 m, constraint = 1 mSv
            sc = Scenario("Bambino 2-5 restr.",[0.1,1.0],[4,8],m,1.0);
        end

        function sc = Bambino_5_11(m)
            % Contact with child 5-11 y
            %  2 h @ 0.1 m, 4 h @ 1 m, constraint = 1 mSv
            sc = Scenario("Bambino 5-11 restr.",[0.1,1.0],[2,4],m,1.0);
        end

        function sc = DonnaIncinta(m)
            % Contact with pregnant woman
            %  6 h @ 1 m, constraint = 1 mSv
            sc = Scenario("Incinta restr.",[1.0],[6],m,1.0);
        end

        function sc = Colleghi(m)
            % Contact with co-workers
            %  8 h @ 1 m, constraint = 0.3 mSv
            sc = Scenario("Colleghi restr.",[1.0],[8],m,0.3);
        end

        function sc = Generico(m)
            % Generic scenario example
            %  8 h @ 0.3 m, constraint = 1 mSv
            sc = Scenario("Generico restr.",[0.3],[8],m,1.0);
        end

        %% -------- SCENARI ORDINARI (hipotesi semplici) --------
        function sc = Ordinario_Partner(m)
            % Ordinario partner: 8 h @ 0.3 m, 6 h @ 1 m, 10 h lontano
            sc = Scenario("Partner ord.",[0.3,1.0,999],[8,6,10],m,0);
        end

        function sc = Ordinario_Trasporto(m)
            % Ordinario trasporto: 0.5 h @ 0.1 m, 3 h @ 1 m, resto lontano
            sc = Scenario("Trasporto ord.",[0.1,1.0,999],[0.5,3,20.5],m,0);
        end

        function sc = Ordinario_Bambino(m)
            % Ordinario bambini: 0.1 m e 2 m small contact
            sc = Scenario("Bambino ord.",[0.1,2.0,999],[2,6,16],m,0);
        end

        function sc = Ordinario_Incinta(m)
            % Ordinario donna incinta: 1 m contatto limitato
            sc = Scenario("Incinta ord.",[1.0,999],[6,18],m,0);
        end

        function sc = Ordinario_Colleghi(m)
            % Ordinario colleghi: 1 m su poco tempo
            sc = Scenario("Colleghi ord.",[1.0,999],[8,16],m,0);
        end
    end
end

