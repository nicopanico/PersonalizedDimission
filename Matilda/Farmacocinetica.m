classdef Farmacocinetica
%FARMACOCINETICA  Modello bi-esponenziale (2 compartimenti) per attività residua / rateo.
%
% DESCRIZIONE
%   Questa classe rappresenta una farmacocinetica bi-esponenziale con:
%     - fr          : frazioni relative (adimensionali), tipicamente 2 elementi e somma = 1
%     - lambda_eff  : costanti di decadimento effettive (d^-1), includono decadimento fisico + biologico
%
%   Il modello sottostante (attività o rateo normalizzato) è:
%
%     A(t) = A0 * [ fr1 * exp(-lambda1*t) + fr2 * exp(-lambda2*t) ]
%
%   con t in GIORNI e lambda in 1/GIORNO.
%
% METODI PRINCIPALI
%   - aggiornaFrazioni(T_dis, a) : aggiorna le frazioni "effective" al tempo di discharge
%   - stimaParametri(t, R, R0)   : stima parametri da misure (richiede Optimization Toolbox)
%   - calcolaSommaFarmacocinetica(T_dis, T_res, Fcorr_res, Fcorr_ord) :
%       utility storica per somma analitica a due fasi (attenzione alle convenzioni)
%
% NOTE SU T_dis
%   In DoseApp, T_dis viene inserito in ore ma poi convertito in giorni.
%   Qui i metodi assumono SEMPRE che T_dis sia in giorni.
%
% Nicola Panico - 19/12/2025

    properties
        fr          % Vettore frazioni relative fr_i (adimensionale)
        lambda_eff  % Vettore costanti effettive lambda_i [giorni^-1]
    end

    methods
        function obj = Farmacocinetica(varargin)
            % Costruttore.
            %
            % USO:
            %   fk = Farmacocinetica()                 -> default (I-131 carcinoma tiroideo)
            %   fk = Farmacocinetica(fr, lambda_eff)   -> parametri custom
            %
            % NOTA:
            %   I default sono impostati come lambda = ln(2)/T_eff (T_eff in giorni).

            if nargin == 0
                % Default: I-131 carcinoma tiroideo (valori di esempio/letteratura)
                obj.fr = [0.70, 0.30];
                obj.lambda_eff = [log(2)/0.32, log(2)/8.04];  % d^-1

            elseif nargin == 2
                obj.fr = varargin{1};
                obj.lambda_eff = varargin{2};

            else
                error('Numero di argomenti non valido per Farmacocinetica. Usa 0 oppure 2 argomenti.');
            end

            % Validazione minima (robusta per uso in app)
            obj = obj.validate();
        end

        function somma_fk = calcolaSommaFarmacocinetica(obj, T_dis, T_res, Fcorr_res, Fcorr_ord)
            %CALCOLASOMMAFARMACOCINETICA  Utility analitica (due fasi) con shift di T_dis.
            %
            % ATTENZIONE (convenzione):
            %   Questa funzione usa (T_res - T_dis) nei termini esponenziali:
            %     termine_res = Fcorr_res * (1 - exp(-lambda*(T_res - T_dis)))
            %     termine_ord = Fcorr_ord * exp(-lambda*(T_res - T_dis))
            %
            %   Questo è coerente SOLO se:
            %     - T_res e T_dis sono espressi nello stesso riferimento temporale,
            %     - l’origine temporale dei contatti/integrazione è posizionata a T_dis.
            %
            %   Se nel resto del codice l’integrazione è definita su [0, T_res] senza shift,
            %   allora questo metodo va usato con cautela (o evitato).
            %
            % INPUT:
            %   T_dis      : tempo di discharge (giorni)
            %   T_res      : tempo di restrizione (giorni)
            %   Fcorr_res  : fattore di correzione fase restrittiva (adimensionale)
            %   Fcorr_ord  : fattore di correzione fase ordinaria (adimensionale)

            if ~isfinite(T_dis) || ~isfinite(T_res)
                error('T_dis e T_res devono essere finiti (giorni).');
            end

            dt = (T_res - T_dis);
            somma_fk = 0;

            for i = 1:numel(obj.fr)
                lambda_i = obj.lambda_eff(i);
                fr_i     = obj.fr(i);

                termine_res = Fcorr_res * (1 - exp(-lambda_i * dt));
                termine_ord = Fcorr_ord * exp(-lambda_i * dt);

                somma_fk = somma_fk + (fr_i / lambda_i) * (termine_res + termine_ord);
            end
        end

        function obj = stimaParametri(obj, t, R, R0)
            %STIMAPARAMETRI  Stima fr e lambda_eff da misure di rateo (fit LSQ).
            %
            % MODELLO:
            %   R(t) = R0 * [ f1*exp(-lambda1*t) + (1-f1)*exp(-lambda2*t) ]
            %
            % INPUT:
            %   t  : tempi (giorni)
            %   R  : ratei misurati (µSv/h)
            %   R0 : rateo iniziale (µSv/h) alla somministrazione/tempo 0 (scalare)
            %
            % OUTPUT:
            %   aggiorna obj.fr e obj.lambda_eff
            %
            % NOTE:
            %   Richiede Optimization Toolbox (lsqcurvefit).

            if nargin < 4
                error('Uso: obj = stimaParametri(obj, t, R, R0)');
            end
            if isempty(t) || isempty(R) || numel(t) ~= numel(R)
                error('t e R devono avere stessa lunghezza e non essere vuoti.');
            end
            if ~isfinite(R0) || R0 <= 0
                error('R0 deve essere > 0 e finito.');
            end

            % Modello biexponenziale (parametri: [f1, lambda1, lambda2])
            modelFun = @(beta, tt) R0 .* ( beta(1) .* exp(-beta(2).*tt) + (1-beta(1)) .* exp(-beta(3).*tt) );

            % Inizializzazione (usa default come "prior")
            beta0 = [obj.fr(1), obj.lambda_eff(1), obj.lambda_eff(2)];

            % Limiti: f1 in [0,1], lambda > 0
            lb = [0, 0, 0];
            ub = [1, Inf, Inf];

            % Opzioni lsqcurvefit
            options = optimoptions('lsqcurvefit', ...
                'Display','off', ...
                'Algorithm','trust-region-reflective');

            % Fit
            beta_est = lsqcurvefit(modelFun, beta0, t, R, lb, ub, options);

            % Aggiorna
            obj.fr = [beta_est(1), 1 - beta_est(1)];
            obj.lambda_eff = [beta_est(2), beta_est(3)];

            % Validazione finale (e normalizzazione fr)
            obj = obj.validate();

            % Log utile in debug (lasciato, ma puoi commentarlo se vuoi “silenzio” totale)
            fprintf('Parametri stimati:\n');
            fprintf('  f1 = %.4f, f2 = %.4f\n', obj.fr(1), obj.fr(2));
            fprintf('  lambda_eff1 = %.4f 1/giorno, lambda_eff2 = %.4f 1/giorno\n', obj.lambda_eff(1), obj.lambda_eff(2));
        end

        function obj = aggiornaFrazioni(obj, T_dis, a, doPrint)
            %AGGIORNAFRAZIONI  Aggiorna le frazioni al tempo di discharge.
            %
            % IDEA:
            %   Se le frazioni "iniziali" a_i sono definite a t=0, dopo un tempo T_dis
            %   i compartimenti decadono in modo diverso e le frazioni relative diventano:
            %
            %     fr_i(T_dis) = a_i * exp(-lambda_i*T_dis) / sum_j (a_j * exp(-lambda_j*T_dis))
            %
            % INPUT:
            %   T_dis   : tempo di discharge (giorni)
            %   a       : frazioni iniziali a_i (opzionale; default = obj.fr)
            %   doPrint : (opzionale) true/false per stampare su Command Window
            %
            % OUTPUT:
            %   aggiorna obj.fr

            if nargin < 3 || isempty(a)
                a = obj.fr;
            end
            if nargin < 4
                doPrint = false; % in app meglio non “sporcare” la console
            end

            if ~isfinite(T_dis) || T_dis < 0
                error('T_dis deve essere finito e >= 0 (giorni).');
            end
            if numel(a) ~= numel(obj.lambda_eff)
                error('Il vettore a deve avere la stessa lunghezza di lambda_eff.');
            end

            a = a(:).'; % forza riga
            numeratori = a .* exp(-obj.lambda_eff .* T_dis);

            denom = sum(numeratori);
            if denom <= 0 || ~isfinite(denom)
                error('Aggiornamento frazioni fallito: denominatore non valido (controlla a e lambda_eff).');
            end

            obj.fr = numeratori ./ denom;

            % Normalizzazione e controlli finali
            obj = obj.validate();

            if doPrint
                fprintf('Frazioni aggiornate per T_dis = %.2f giorni:\n', T_dis);
                fprintf('  f1 = %.4f, f2 = %.4f\n', obj.fr(1), obj.fr(2));
            end
        end
    end

    methods (Access = private)
        function obj = validate(obj)
            %VALIDATE  Controlli minimi e normalizzazione frazioni.
            %
            % - fr non negative
            % - somma fr ~ 1 (normalizzo se serve)
            % - lambda_eff > 0
            %
            % Mantiene la classe stabile per uso in GUI/compilato.

            if isempty(obj.fr) || isempty(obj.lambda_eff)
                error('Farmacocinetica non valida: fr e lambda_eff non possono essere vuoti.');
            end

            obj.fr = obj.fr(:).';               % riga
            obj.lambda_eff = obj.lambda_eff(:).'; % riga

            if numel(obj.fr) ~= numel(obj.lambda_eff)
                error('Farmacocinetica non valida: fr e lambda_eff devono avere la stessa lunghezza.');
            end

            if any(~isfinite(obj.fr)) || any(~isfinite(obj.lambda_eff))
                error('Farmacocinetica non valida: fr e lambda_eff devono essere finiti.');
            end

            if any(obj.lambda_eff <= 0)
                error('Farmacocinetica non valida: lambda_eff deve essere > 0 (1/giorno).');
            end

            if any(obj.fr < 0)
                error('Farmacocinetica non valida: fr deve essere >= 0.');
            end

            s = sum(obj.fr);
            if s <= 0
                error('Farmacocinetica non valida: somma fr deve essere > 0.');
            end

            % Normalizza (tollerante a piccoli errori numerici o input non perfetto)
            obj.fr = obj.fr ./ s;

            % Clipping leggero per errori numerici tipo -1e-15
            obj.fr(obj.fr < 0) = 0;
            obj.fr = obj.fr ./ sum(obj.fr);
        end
    end
end
