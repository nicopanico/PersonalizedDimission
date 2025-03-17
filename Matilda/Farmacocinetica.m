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
    end
end


