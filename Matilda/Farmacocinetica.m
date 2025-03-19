classdef Farmacocinetica
    properties
        fr          % Vettore frazioni relative fr_i
        lambda_eff  % Vettore costanti decadimento effettive lambda_i [giorni^-1]
    end
    
    methods
        % Costruttore predefinito (valori standard per I-131 Carcinoma Tiroideo)
        function obj = Farmacocinetica(varargin)
            if nargin == 0
                % Valori di default per I-131 Carcinoma Tiroideo
                obj.fr = [0.70, 0.30];
                obj.lambda_eff = [log(2)/0.32, log(2)/8.04];
            elseif nargin == 2
                % Costruttore alternativo: Farmacocinetica(fr, lambda_eff)
                obj.fr = varargin{1};
                obj.lambda_eff = varargin{2};
            else
                error('Numero di argomenti non valido per Farmacocinetica');
            end
        end
        
        % Metodo per calcolare la sommatoria farmacocinetica
        function somma_fk = calcolaSommaFarmacocinetica(obj, T_dis, T_res, Fcorr_res, Fcorr_ord)
            somma_fk = 0;
            for i = 1:length(obj.fr)
                lambda_i = obj.lambda_eff(i);
                fr_i = obj.fr(i);
                termine_res = Fcorr_res * (1 - exp(-lambda_i*(T_res - T_dis)));
                termine_ord = Fcorr_ord * exp(-lambda_i*(T_res - T_dis));
                somma_fk = somma_fk + (fr_i/lambda_i)*(termine_res + termine_ord);
            end
        end

        % Metodo opzionale per stimare i parametri (fr e lambda_eff)
        % a partire da più misure di dose rate
        % t: vettore dei tempi (in giorni) delle misurazioni
        % R: vettore dei ratei di dose misurati (in µSv/h)
        % R0: rateo di dose iniziale alla somministrazione (in µSv/h)
        function obj = stimaParametri(obj, t, R, R0)
            % Definizione del modello biexponenziale:
            % R(t) = R0 * ( f1 * exp(-lambda1*t) + (1-f1) * exp(-lambda2*t) )
            modelFun = @(beta, t) R0 * ( beta(1) * exp(-beta(2)*t) + (1-beta(1)) * exp(-beta(3)*t) );

            % Valori iniziali per [f1, lambda1, lambda2]
            beta0 = [0.70, log(2)/0.32, log(2)/8.04];

            % Definisci i limiti: f1 in [0,1], lambda1 e lambda2 > 0
            lb = [0, 0, 0];
            ub = [1, Inf, Inf];

            % Imposta le opzioni per lsqcurvefit
            options = optimoptions('lsqcurvefit','Display','off','Algorithm','trust-region-reflective');

            % Esegui lsqcurvefit
            beta_est = lsqcurvefit(modelFun, beta0, t, R, lb, ub, options);

            % Aggiorna i parametri dell'oggetto
            obj.fr = [beta_est(1), 1 - beta_est(1)];
            obj.lambda_eff = [beta_est(2), beta_est(3)];

            fprintf('Parametri stimati:\n');
            fprintf('  f1 = %.4f, f2 = %.4f\n', obj.fr(1), obj.fr(2));
            fprintf('  lambda_eff1 = %.4f 1/giorno, lambda_eff2 = %.4f 1/giorno\n', obj.lambda_eff(1), obj.lambda_eff(2));
        end
        
        % Nuovo metodo per aggiornare le frazioni in base al tempo di discharge T_dis
        function obj = aggiornaFrazioni(obj, T_dis, a)
            % T_dis: tempo di discharge in giorni
            % a: vettore delle frazioni iniziali (a_i); se non fornito, usa obj.fr come a_i
            if nargin < 3
                a = obj.fr;
            end
            % Calcola numeratori: a_i * exp(-lambda_eff_i * T_dis)
            numeratori = a .* exp(-obj.lambda_eff * T_dis);
            denominator = sum(numeratori);
            new_fr = numeratori / denominator;
            obj.fr = new_fr;
            fprintf('Frazioni aggiornate per T_dis = %.2f giorni:\n', T_dis);
            fprintf('  f1 = %.4f, f2 = %.4f\n', obj.fr(1), obj.fr(2));
        end

    end
end


