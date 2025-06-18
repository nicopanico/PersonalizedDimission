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
        function Fcorr_scenario = calcolaFcorrScenario(obj, A_tot)
            if nargin < 2, A_tot = 1; end
            Fcorr_scenario = 0;
            for k = 1:numel(obj.distanze)
                Fcorr = obj.modello.calcolaFattoreCorrezione(obj.distanze(k),1,A_tot);
                Fcorr_scenario = Fcorr_scenario + (obj.tempi(k)/24) * Fcorr;
            end
        end

        function obj = Scenario(nome, distanze, tempi, modello, DoseConstraint)
            if nargin<5, DoseConstraint=0; end
            obj.nome           = nome;
            obj.distanze       = distanze;
            obj.tempi          = tempi;
            obj.modello        = modello;
            obj.DoseConstraint = DoseConstraint;
        end
    end
end

