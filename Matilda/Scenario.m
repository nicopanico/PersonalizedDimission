classdef Scenario
    properties
        nome            % Nome scenario
        distanze        % vettore distanze (m)
        tempi           % ore al giorno
        DoseConstraint  % limite di dose scenario (mSv)
        modello         % Modello geometrico
    end

    methods
        % costruttore con DoseConstraint opzionale
        function obj = Scenario(nome, distanze, tempi, modello, DoseConstraint)
            obj.nome = nome;
            obj.distanze = distanze;
            obj.tempi = tempi;
            obj.modello = modello;
            if nargin == 5
                obj.DoseConstraint = DoseConstraint;
            else
                obj.DoseConstraint = NaN; % se non specificato
            end
        end
        
        % Metodo calcolo Fcorr scenario
        function Fcorr_scenario = calcolaFcorrScenario(obj, A_tot)
            Fcorr_scenario = 0;
            for k = 1:length(obj.distanze)
                Fcorr = obj.modello.calcolaFattoreCorrezione(obj.distanze(k), 1, A_tot);
                Fcorr_scenario = Fcorr_scenario + (obj.tempi(k)/24) * Fcorr;
            end
        end
    end
    
    methods(Static)

        % 🔹 SCENARI RISTRETTI (da Buonamici)

        % Scenario: Madre con bambino piccolo
        function sc = Madre(modello)
            nome = 'Madre con bambino piccolo';
            distanze = [0.3, 2];  % 0.3m durante l’accudimento, 2m per altre attività
            tempi = [1, 3];       % 1 ora a 0.3m, 3 ore a 2m
            DoseConstraint = 1;   % Limite Buonamici: 1 mSv
            sc = Scenario(nome, distanze, tempi, modello, DoseConstraint);
        end

        % Scenario: Partner
        function sc = Partner(modello)
            nome = 'Partner';
            distanze = [0.5, 1.5];  
            tempi = [8, 4];        % 8 ore a 0.5m, 4 ore a 1.5m
            DoseConstraint = 1;    % Limite Buonamici: 1 mSv
            sc = Scenario(nome, distanze, tempi, modello, DoseConstraint);
        end

        % Scenario: Collega di lavoro
        function sc = Collega(modello)
            nome = 'Collega';
            distanze = [1, 3];  
            tempi = [2, 6];        % 2 ore a 1m, 6 ore a 3m
            DoseConstraint = 0.3;  % Limite Buonamici: 0.3 mSv
            sc = Scenario(nome, distanze, tempi, modello, DoseConstraint);
        end

        % Scenario: Familiare adulto
        function sc = Familiare(modello)
            nome = 'Familiare Adulto';
            distanze = [1, 2];  
            tempi = [4, 8];        % 4 ore a 1m, 8 ore a 2m
            DoseConstraint = 0.3;  % Limite Buonamici: 0.3 mSv
            sc = Scenario(nome, distanze, tempi, modello, DoseConstraint);
        end

        % 🔹 SCENARI ORDINARI (da Buonamici)

        % Scenario ordinario: Vita in famiglia
        function sc = Ordinario_Familiare(modello)
            nome = 'Ordinario Familiare';
            distanze = [2, 4];  
            tempi = [6, 18];       % 6 ore a 2m, 18 ore a 4m
            sc = Scenario(nome, distanze, tempi, modello, 0);  % Nessun DoseConstraint
        end

        % Scenario ordinario: Lavoratore con interazioni
        function sc = Ordinario_Lavoratore(modello)
            nome = 'Ordinario Lavoratore';
            distanze = [1.5, 3];  
            tempi = [8, 16];       % 8 ore a 1.5m, 16 ore a 3m
            sc = Scenario(nome, distanze, tempi, modello, 0);
        end

        % Scenario ordinario: Persona sola
        function sc = Ordinario_Singolo(modello)
            nome = 'Ordinario Singolo';
            distanze = [3, 5];  
            tempi = [6, 18];       % 6 ore a 3m, 18 ore a 5m
            sc = Scenario(nome, distanze, tempi, modello, 0);
        end

    end
end
