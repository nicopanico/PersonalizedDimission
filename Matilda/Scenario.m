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
            % =================================================================
            %  SCENARIO: PARTNER (fase restrittiva “light”)
            %
            %  • Destinatario: coniuge o convivente che condivide la casa
            %    ma NON il letto per i primi 15 giorni.
            %  • Motivazione: vincolo di dose 3 mSv (care‑giver, Tab. 2).
            %  • Questa fase copre il contatto ravvicinato che NON si può
            %    evitare del tutto: 1 ora al giorno a circa 1 m (pasti,
            %    divano, stesso ambiente).
            %  • In `DoseApp` compare quando l’utente spunta “Partner”.
            % =================================================================
            sc = Scenario("Partner", [1.0], [2.0], m, 3.0);  % 1 h @ 1 m
        end
        function sc = NessunaRestr(m)
            % =================================================================
            %  SCENARIO: ASSENZA DAL LAVORO (CONGEDO INPS)
            %
            %  • Destinatari: colleghi di lavoro o pubblico generico.
            %  • Durante il congedo il paziente NON è presente in ufficio,
            %    quindi non serve una fase restrittiva → distanze/tempi vuoti.
            %  • Vincolo di dose 0.3 mSv (pubblico).
            %  • `T_res` calcolato dallo scenario ordinario stabilisce
            %    la durata del certificato di assenza.
            % =================================================================
            sc = Scenario("GG Assenza Lavoro", [], [], m, 0.3);
        end
        function sc = NessunaRestr_2(m)
            % Nessuna fase restrittiva
            sc = Scenario("No restr.", [], [], m, 3);
        end

        function sc = TrasportoPubblico(m)
            % Travel in public transport
            %  0.5 h @ 0.1 m, constraint = 0.3 mSv
            sc = Scenario("Trasporto restr.",[0.5],[0.5],m,0.3);
        end

        function sc = Bambino_0_2(m)
            % =================================================================
            %  SCENARIO: BAMBINO < 2 ANNI (fase restrittiva)
            %
            %  • Periodo di riferimento: 39 giorni (Buonamici, Tab. 3).
            %  • Vincolo pediatrico: 1 mSv.
            %  • Contatto “in braccio / allattamento” limitato a 6 min al giorno
            %    a 10 cm (0.1 m).  Il resto della giornata è gestito dallo
            %    scenario ordinario (vedi sotto).
            % =================================================================
            sc = Scenario("Limite contatto bambino <2", [0.1], [0.10], m, 1.0);
        end

        function sc = Bambino_2_5(m)
            % =================================================================
            %  SCENARIO: BAMBINO 2–5 ANNI (fase restrittiva)
            %
            %  • T_res atteso: 32 giorni (Buonamici).
            %  • Vincolo: 1 mSv.
            %  • Si prevedono:
            %      – 10 min/gg a 0.3 m (bimbo in grembo o sulle ginocchia)
            %      – 1 h/gg a 1 m (gioco fianco a fianco)
            % =================================================================
            sc = Scenario("Limite contatto bambino 2-5", ...
                [0.3, 1.0], [0.16, 1.0], m, 1.0);
        end

        function sc = Bambino_5_11(m)
            % Primo mese: max 2 h/gg a 1 m (compiti, pasti)
            sc = Scenario("Bambino 5-11 restr.", [1.0], [2.5], m, 1.0);
        end

        function sc = DonnaIncinta(m)
            % Contact with pregnant woman
            %  6 h @ 1 m, constraint = 1 mSv
            sc = Scenario("Incinta restr.",[1.0],[2],m,1.0);
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
            % =================================================================
            %  ORDINARIO PARTNER (dopo i primi 15 gg)
            %  – 5.6 h/gg a 30 cm (divano, abbracci saltuari)
            %  – 4.2 h/gg a 1 m  (stessa stanza)
            %  – 7.0 h/gg a distanza ≫ 2 m (lontano / lavoro)
            % =================================================================
            sc = Scenario("Partner ord.", [0.3, 1.0, 2], [5, 3.5, 9.5] , m, 0);
        end

        function sc = Ordinario_Trasporto(m)
            % Ordinario trasporto: 0.5 h @ 0.1 m, 3 h @ 1 m, resto lontano
            sc = Scenario("Trasporto ord.",[0.3,1,999],[1,2,20.5],m,0);
        end
        function sc = Ordinario_Bambino_2_5(m)
            % =================================================================
            %  ORDINARIO BAMBINO 2–5 ANNI (dopo i 32 gg)
            %
            %  - 2 h @ 0.1 m  (abbracci brevi)
            %  - 6 h @ 2 m    (gioco in stanza)
            %  - 16 h lontano (>5 m)
            % =================================================================
            sc = Scenario("Bambino ord. 2-5", [0.1, 2.0, 999], [2, 6, 16], m, 0);
        end
        function sc = Ordinario_Bambino_0_2(m)
            % =================================================================
            %  ORDINARIO BAMBINO < 2 ANNI (dopo i 39 gg)
            %
            %  - 1.5 h @ 0.1 m  (abbracci / poppata)
            %  - 4.0 h @ 0.3 m  (accudimento ravvicinato)
            %  - 6.0 h @ 1 m    (gioco sul tappeto)
            %  - 12 h @ 2 m     (passeggino/culla a distanza)
            % =================================================================
            sc = Scenario("Bambino ord. <2", [0.1, 0.3, 1.0, 2.0], [1.5, 4, 6, 12], m, 0);
        end

        function sc = Ordinario_Bambino_5_11(m)
            distanze = [0.5, 1.0, 2.0, 999];
            tempi    = [2.5, 3.0, 6.0, 12.0];  % h/gg
            sc = Scenario("Bambino ord. 5-11", distanze, tempi, m, 0);
        end

        function sc = Ordinario_Incinta(m)
            % Ordinario donna incinta: 1 m contatto limitato
            sc = Scenario("Incinta ord.",[1.0,999],[6,18],m,0);
        end

        function sc = Ordinario_Colleghi(m)
            % =================================================================
            %  ORDINARIO COLLEGHI (dopo il congedo lavorativo)
            %
            %  Obiettivo clinico
            %  -----------------
            %  • Scenario di esposizione per i colleghi al rientro in ufficio.
            %  • Con R_Tdis = 30 µSv/h e fr/λ dell’ipertiroidismo, volevamo
            %    ottenere T_res ≈ 22 gg (assenza lavorativa) e vincolo 0.3 mSv.
            %
            %  Tempi/distanze quotidiani
            %  ------------------------
            %  • 7.27 h/gg   @ 1 m   (scrivania adiacente, riunioni)
            %  • 16.0 h/gg  @ 999 m  (fuori dall’ufficio / notte)
            %
            % =================================================================
            sc = Scenario("Colleghi ord.", [1.0, 999], [8, 16] * 0.9093, m, 0);
        end
        function sc = Ordinario_Colleghi_2m(m)
            % ================================================================
            %  ORDINARIO COLLEGHI – variante lavoro sempre ≥ 2 m
            %
            %  • Ipotesi: in ufficio il paziente può garantire > 2 m di distanza
            %    per TUTTA la giornata lavorativa (8 h).  Il resto del tempo
            %    è a distanza “lontano” (casa, notte).
            %  • Vincolo pubblico 0.3 mSv – con 2 m il F_geo è 0.26,
            %    quindi Fo = (8/24)*0.26 ≈ 0.087.
            % ================================================================
            sc = Scenario("Colleghi ord. ≥2 m", [2.0, 999], [8, 16], m, 0);
        end
    end
end

