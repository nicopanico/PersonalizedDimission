classdef DoseCalculator
%DOSECALCULATOR  Calcolatore di dose cumulativa e T_res ottimale (bisezione).
%
% DESCRIZIONE
%   Questa classe implementa il calcolo della dose cumulativa attesa (mSv)
%   per un soggetto esposto a un paziente trattato con radiofarmaco, seguendo
%   un modello a due fasi:
%     1) fase restrittiva  : t = [0, T_res]
%     2) fase ordinaria    : t = [T_res, +inf)
%
%   La dipendenza temporale dell’attività è modellata con una cinetica
%   bi-esponenziale (Farmacocinetica) con parametri:
%     - fr(i)         frazione i-esima (somma ~ 1)
%     - lambda_eff(i) costante effettiva (1/giorno)
%
%   Il contributo geometrico/di contatto dello scenario è condensato nei
%   fattori F_corr (adimensionali) calcolati dagli scenari:
%     - F_r = scenarioRestrizione.calcolaFcorrScenario(1)
%     - F_o = scenarioOrdinario  .calcolaFcorrScenario(1)
%
% UNITA' (CONVENZIONI)
%   - T_res in GIORNI (d)
%   - lambda_eff in 1/GIORNO (d^-1)
%   - R_Tdis in µSv/h (rateo a T_discharge al riferimento usato dall’app)
%   - Dose restituita in mSv
%
% FORMULA (struttura)
%   Per ciascun compartimento i:
%     D_restr,i(T) = (fr_i / lambda_i) * F_r * (1 - exp(-lambda_i * T))
%     D_ord,i(T)   = (fr_i / lambda_i) * F_o * exp(-lambda_i * T)
%
%   La somma (in "giorni equivalenti") viene poi convertita in mSv con:
%     Dose[mSv] = R_Tdis[µSv/h] * 24[h/d] * (D_restr + D_ord) / 1000
%
% NOTA IMPORTANTE (bisezione)
%   trovaPeriodoRestrizione assume che Dose(T) sia monotona DECRESCENTE con T.
%   Questo è vero nel caso tipico Fo >= Fr (scenario ordinario più "espositivo"
%   del restrittivo). Se per qualche motivo Fo < Fr, l’andamento può invertirsi
%   e la bisezione non sarebbe corretta.
%
% Nicola Panico - 19/12/2025

    properties
        scenarioRestrizione
        scenarioOrdinario
        farmacocinetica
        R_Tdis % µSv/h
    end

    methods
        function obj = DoseCalculator(scenarioRestrizione, scenarioOrdinario, farmacocinetica, R_Tdis)
            % Costruttore: salva gli oggetti necessari al calcolo.
            obj.scenarioRestrizione = scenarioRestrizione;
            obj.scenarioOrdinario   = scenarioOrdinario;
            obj.farmacocinetica     = farmacocinetica;
            obj.R_Tdis              = R_Tdis;
        end

        function dose = calcolaDoseTotale(obj, T_res)
            %CALCOLADOSETOTALE  Dose totale (mSv) in funzione di T_res (giorni).
            %
            % INPUT:
            %   T_res : periodo restrittivo in giorni (d)
            %
            % OUTPUT:
            %   dose  : dose totale (mSv) = dose_restr + dose_ord

            % Controlli minimi (evita risultati “silenziosamente” strani)
            if isempty(T_res) || ~isfinite(T_res) || T_res < 0
                error('T_res deve essere un valore finito e >= 0 (giorni).');
            end

            fr = obj.farmacocinetica.fr;
            lam = obj.farmacocinetica.lambda_eff; % 1/giorno

            if numel(fr) ~= numel(lam)
                error('Farmacocinetica incoerente: fr e lambda_eff devono avere la stessa lunghezza.');
            end
            if any(lam <= 0)
                error('Farmacocinetica non valida: lambda_eff deve essere > 0 (1/giorno).');
            end

            % Fattori di correzione scenario (adimensionali)
            F_r = obj.scenarioRestrizione.calcolaFcorrScenario(1);
            F_o = obj.scenarioOrdinario  .calcolaFcorrScenario(1);

            dose_tot = 0; % somma in "giorni equivalenti"

            % Somma dei contributi dei compartimenti (bi-esponenziale)
            for i = 1:numel(fr)
                fr_i     = fr(i);
                lambda_i = lam(i);

                % Fase restrittiva: [0 -> T_res]
                dose_restr = (fr_i / lambda_i) * F_r * (1 - exp(-lambda_i * T_res));

                % Fase ordinaria: [T_res -> +inf)
                dose_ord   = (fr_i / lambda_i) * F_o * exp(-lambda_i * T_res);

                dose_tot = dose_tot + dose_restr + dose_ord;
            end

            % Conversione in mSv:
            %   - dose_tot è in "giorni equivalenti" (perché lam è in 1/giorno)
            %   - R_Tdis è in µSv/h -> moltiplico per 24 h/giorno
            %   - µSv -> mSv: /1000
            dose = obj.R_Tdis * 24 * dose_tot / 1000;
        end

        function Tres_ottimale = trovaPeriodoRestrizione(obj, Dcons)
            %TROVAPERIODORESTRIZIONE  Trova T_res (giorni) tale che Dose(T_res) <= Dcons.
            %
            % Metodo:
            %   Bisezione su intervallo [Tmin, Tmax] assumendo monotonicità decrescente.
            %
            % INPUT:
            %   Dcons : dose constraint (mSv)
            %
            % OUTPUT:
            %   Tres_ottimale : giorni (d)

            if isempty(Dcons) || ~isfinite(Dcons)
                error('Dcons deve essere un valore finito (mSv).');
            end
            if Dcons <= 0
                Tres_ottimale = 0;
                return;
            end

            Tmin = 0.1;  % gg (evito 0 solo per robustezza numerica)
            Tmax = 60;   % gg
            Tol  = 0.01; % gg

            % Se già a Tmin la dose è sotto al limite, “serve poco/niente”
            if obj.calcolaDoseTotale(Tmin) <= Dcons
                Tres_ottimale = Tmin;
                return;
            end

            % Se anche a Tmax la dose è sopra il limite, non riesco a rispettare Dcons
            if obj.calcolaDoseTotale(Tmax) > Dcons
                warning('Non si riesce a soddisfare Dcons anche con T_res = %.0f gg', Tmax);
                Tres_ottimale = Tmax;
                return;
            end

            % Bisezione
            while (Tmax - Tmin) > Tol
                Tmed = (Tmin + Tmax)/2;
                dose_curr = obj.calcolaDoseTotale(Tmed);

                % Dose(T) tipicamente decrescente:
                %   - se sono sopra al vincolo -> devo aumentare T (sposto Tmin in alto)
                %   - se sono sotto/uguale     -> posso ridurre T (sposto Tmax in basso)
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
            %PLOTDOSECURVE  Grafico dose vs T_res (totale + componenti).
            %
            % INPUT:
            %   fk         : oggetto Farmacocinetica (in pratica può coincidere con obj.farmacocinetica)
            %   selectedRF : stringa/nome radiofarmaco (solo per titolo grafico)

            % T_res ottimale rispetto al vincolo dello scenario restrittivo
            Tres_opt = obj.trovaPeriodoRestrizione(obj.scenarioRestrizione.DoseConstraint);

            % Vettore di T_res per il grafico
            Tvec = linspace(0.1, 60, 300);

            dose_tot = zeros(size(Tvec));
            dose_r   = zeros(size(Tvec));
            dose_o   = zeros(size(Tvec));

            % Fattori di scenario
            Fr = obj.scenarioRestrizione.calcolaFcorrScenario(1);
            Fo = obj.scenarioOrdinario  .calcolaFcorrScenario(1);

            % Calcolo esplicito componenti restr/ord (utile per debug e spiegazioni)
            for k = 1:numel(Tvec)
                T = Tvec(k);
                sr = 0; so = 0;

                for i = 1:numel(fk.fr)
                    fr_i = fk.fr(i);
                    lam  = fk.lambda_eff(i);

                    sr = sr + (fr_i/lam) * Fr * (1 - exp(-lam*T));
                    so = so + (fr_i/lam) * Fo * exp(-lam*T);
                end

                dose_r(k)   = obj.R_Tdis * 24 * sr / 1000;
                dose_o(k)   = obj.R_Tdis * 24 * so / 1000;
                dose_tot(k) = dose_r(k) + dose_o(k);
            end

            figure('Name','Dose vs T_{res}');
            plot(Tvec, dose_tot, 'b-', ...
                 Tvec, dose_r,   'g--', ...
                 Tvec, dose_o,   'm-.', ...
                 'LineWidth', 1.5);
            hold on

            yline(obj.scenarioRestrizione.DoseConstraint, 'r--', 'Limite dose');
            plot(Tres_opt, obj.calcolaDoseTotale(Tres_opt), 'ko', 'MarkerFaceColor', 'k');

            title(['Dose per ', char(selectedRF), ' – ', char(obj.scenarioRestrizione.nome)]);
            xlabel('T_{res} [giorni]');
            ylabel('Dose [mSv]');
            grid on
            legend('Tot','Restr.','Ordin.','Limite','T_{res}^{opt}', 'Location', 'best');
        end
    end
end