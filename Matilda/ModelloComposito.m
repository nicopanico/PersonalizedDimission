classdef ModelloComposito < ModelloGeometrico
    % ModelloComposito
    % -----------------
    % Sorgente volumetrica composta da cilindri e sfere, ognuno con peso w_j.
    % Kernel base: exp(-mu * R) / (4*pi*R^2) (la costante si semplifica nei rapporti).
    %
    % Effetti inclusi:
    %  - Autoassorbimento interno medio per componente (A_int = exp(-mu * tau)).
    %  - Build-up interno per componente (B_int): 'linear' o 'saturating'.
    %  - Build-up lungo cammino nel kernel (B_path(R)) opzionale ('linear'/'saturating').
    %
    % Interfaccia pubblica (coerente con ModelloGeometrico):
    %   dose  = calcolaDose(d, A_tot)                      % normalizzata a d_ref
    %   Fcorr = calcolaFattoreCorrezione(d, d_ref)         % = F(d)/F(d_ref)
    %
    % Factory pronti:
    %   mdl = ModelloComposito.forI131(...opzioni...)
    %   mdl = ModelloComposito.forLu177(...opzioni...)

    % ==================== Parametri & opzioni ====================
    properties
        % Componenti: array di struct con campi
        %   kind  : 'sphere' | 'cyl'
        %   w     : peso (somma consigliata ≈ 1)
        %   a     : raggio [m]
        %   L     : lunghezza [m] (solo per 'cyl'; per sfere lasciare [])
        %   tau   : (opz.) spessore medio interno [m] (se assente, stima automatica)
        %   b1    : (opz.) ampiezza build-up interno (se assente, usa default globale)
        components

        % Fisica
        mu_t   double = 8.0     % [1/m] coeff. attenuazione tessuto/medium
        d_ref  double = 1.0     % [m] distanza di riferimento per normalizzare

        % Griglie numeriche per le quadrature
        Nz     double = 50
        Nr     double = 36
        Nphi   double = 32
        Ntheta double = 48

        % --- Autoassorbimento medio interno ---
        useAvgInternalPath (1,1) logical = true

        % --- Build-up interno (per componente) ---
        useInternalBuildUp (1,1) logical = true
        internalBuildUpMode       char   = 'saturating'   % 'saturating' | 'linear'
        b1_internal_default double = 0.7                 % ampiezza max addizionale

        % --- Build-up lungo cammino (dentro i kernel) ---
        usePathBuildUp   (1,1) logical = false           % OFF di default
        pathBuildUpMode         char   = 'saturating'    % 'saturating' | 'linear'
        b1_path           double = 0.2                   % ampiezza path
        mu_b_path         double = NaN                   % [1/m] (se NaN, = mu_t)
    end

    % ==================== Costruttore & API ====================
    methods
        function obj = ModelloComposito(components, mu_t, d_ref)
            if nargin >= 1 && ~isempty(components), obj.components = components; end
            if nargin >= 2 && ~isempty(mu_t),      obj.mu_t      = mu_t;      end
            if nargin >= 3 && ~isempty(d_ref),     obj.d_ref     = d_ref;     end
            if isnan(obj.mu_b_path)
                obj.mu_b_path = obj.mu_t; % default coerente con l’isotopo/medium
            end
        end

        % Dose normalizzata (dose a d_ref = 1 per A_tot = 1)
        function dose = calcolaDose(obj, d, A_tot, ~)
            if nargin < 3 || isempty(A_tot), A_tot = 1; end
            dose = A_tot * obj.rawF(d) / obj.rawF(obj.d_ref);
        end

        % Fattore di correzione (rapporto di geometria): F(d) / F(d_ref)
        function Fcorr = calcolaFattoreCorrezione(obj, d, d_ref, ~)
            if nargin < 3 || isempty(d_ref), d_ref = obj.d_ref; end
            Fcorr = obj.rawF(d) / obj.rawF(d_ref);
        end
    end

    % ==================== Motore numerico ====================
    methods (Access=private)
        function F = rawF(obj, d)
            mu = obj.mu_t;
            F  = 0.0;

            for j = 1:numel(obj.components)
                c = obj.components(j);

                % --- Kernel geometrico con (eventuale) build-up lungo cammino ---
                switch lower(c.kind)
                    case 'sphere'
                        Dobs = max(d, 1e-3);
                        Kj = ModelloComposito.G_sphere( ...
                                Dobs, c.a, mu, ...
                                obj.Nr, obj.Ntheta, obj.Nphi, ...
                                obj.usePathBuildUp, ...
                                obj.b1_path, ...
                                obj.mu_b_path );

                    case 'cyl'
                        Dobs = max(d, 1e-3);
                        Kj = ModelloComposito.G_cyl( ...
                                Dobs, c.a, c.L, mu, ...
                                obj.Nz, obj.Nr, obj.Nphi, ...
                                obj.usePathBuildUp, ...
                                obj.b1_path, ...
                                obj.mu_b_path );

                    otherwise
                        error('Componente non riconosciuta: %s', c.kind);
                end

                % --- Autoassorbimento interno medio ---
                tau = 0.0;
                if obj.useAvgInternalPath
                    tau = ModelloComposito.avgInternalPath(c);
                elseif isfield(c,'tau') && ~isempty(c.tau)
                    tau = c.tau;
                end
                Aint = exp(-mu * max(tau,0));

                % --- Build-up interno (per componente) ---
                Bint = 1.0;
                if obj.useInternalBuildUp
                    b1int = obj.b1_internal_default;
                    if isfield(c,'b1') && ~isempty(c.b1), b1int = c.b1; end

                    switch lower(obj.internalBuildUpMode)
                        case 'linear'
                            % valido per mu*tau piccoli
                            Bint = 1 + b1int * mu * max(tau,0);
                        case 'saturating'
                            % tende a (1 + b1) per spessori grandi
                            Bint = 1 + b1int * (1 - exp(-mu * max(tau,0)));
                        otherwise
                            error('internalBuildUpMode non riconosciuto: %s', obj.internalBuildUpMode);
                    end
                end

                % Accumulo contribuzione del componente j
                F = F + c.w * Kj * Aint * Bint;
            end
        end
    end

    % ==================== Utility statiche ====================
    methods (Static, Access=private)
        function tau = avgInternalPath(c)
            % Stima semplice della half-chord media:
            %  - sfera: 2a/3
            %  - cilindro: ~ a/2 (uscita radiale prevalente)
            if isfield(c,'tau') && ~isempty(c.tau)
                tau = c.tau;
                return;
            end
            switch lower(c.kind)
                case 'sphere', tau = 2*c.a/3;
                case 'cyl',    tau = 0.5*c.a;
                otherwise,     tau = 0.0;
            end
        end
    end

    % ==================== Primitive geometriche ====================
    methods (Static)
        function K = G_cyl(D, a, L, mu, Nz, Nr, Nphi, useBuildUp, b1, mu_b)
            % Integrale volumetrico per un cilindro (r<=a, z∈[-L/2,L/2]) osservato a (D,0,0).
            % Discretizzazione: phi ∈ [0,2π], r ∈ [0,a], z ∈ [-L/2,L/2].

            if nargin < 10 || isempty(mu_b),       mu_b      = mu;       end
            if nargin < 9  || isempty(b1),         b1        = 0.0;      end
            if nargin < 8  || isempty(useBuildUp), useBuildUp = false;    end

            % griglie
            phi = linspace(0, 2*pi, Nphi);
            r   = linspace(0, a,     Nr);
            z   = linspace(-L/2, L/2, Nz);

            % ndgrid: F dimensioni [Nphi x Nr x Nz]
            [Phi, Rho, Z] = ndgrid(phi, r, z);

            % distanza punto-sorgente
            % R = sqrt(D^2 + r^2 - 2 D r cos(phi) + z^2)
            R = sqrt(D.^2 + Rho.^2 - 2*D.*Rho.*cos(Phi) + Z.^2);

            % build-up lungo cammino (opzionale)
            if useBuildUp && (b1 > 0)
                % modalità 'saturating' (consigliata): 1 + b1*(1 - exp(-mu_b*R))
                B = 1 + b1 * (1 - exp(-mu_b .* R));
            else
                B = 1;
            end

            % integrando: kernel * Jacobiano cilindrico (r)
            F = (exp(-mu .* R) ./ max(R.^2, eps)) .* Rho .* B;

            % integrazione ordinata: φ -> r -> z
            I_phi = trapz(phi, F, 1);    % [1 x Nr x Nz]
            I_r   = trapz(r,   I_phi, 2);% [1 x 1 x Nz]
            I_z   = trapz(z,   I_r,   3);% [1 x 1 x 1]

            % la costante 1/(4π) si elimina nei rapporti → omessa
            K = I_z;
            K = K(:).'; % scalare/riga
        end

        function K = G_sphere(D, a, mu, Nr, Ntheta, Nphi, useBuildUp, b1, mu_b)
            % Integrale volumetrico per sfera di raggio a centrata in (0,0,0), osservatore in (D,0,0).
            % Coordinate sferiche: ρ∈[0,a], θ∈[0,π], φ∈[0,2π].
            % dV = ρ^2 sinθ dρ dθ dφ.

            if nargin < 9 || isempty(mu_b),       mu_b      = mu;    end
            if nargin < 8 || isempty(b1),         b1        = 0.0;   end
            if nargin < 7 || isempty(useBuildUp), useBuildUp = false; end

            phi   = linspace(0, 2*pi, Nphi);
            theta = linspace(0, pi,    Ntheta);
            rho   = linspace(0, a,     Nr);

            % ndgrid: [Nphi x Ntheta x Nr]
            [Phi, Theta, Rho] = ndgrid(phi, theta, rho);

            % coordinate elemento sorgente
            xs = Rho .* sin(Theta) .* cos(Phi);
            ys = Rho .* sin(Theta) .* sin(Phi);
            zs = Rho .* cos(Theta);

            % distanza al punto (D,0,0)
            R = sqrt( (D - xs).^2 + ys.^2 + zs.^2 );

            % build-up lungo cammino (opzionale)
            if useBuildUp && (b1 > 0)
                B = 1 + b1 * (1 - exp(-mu_b .* R));
            else
                B = 1;
            end

            % kernel * Jacobiano sferico
            F = (exp(-mu .* R) ./ max(R.^2, eps)) .* (Rho.^2 .* sin(Theta)) .* B;

            % integrazione: φ -> θ -> ρ
            I_phi   = trapz(phi,   F, 1);  % [1 x Ntheta x Nr]
            I_theta = trapz(theta, I_phi, 2); % [1 x 1 x Nr]
            I_rho   = trapz(rho,   I_theta, 3); % [1 x 1 x 1]

            K = I_rho;
            K = K(:).';
        end
    end

    % ==================== Factory isotopo-specifiche ====================
    methods (Static)
        function mdl = forI131(varargin)
            % mdl = ModelloComposito.forI131('mu_t',8.0,'d_ref',1.0,'b1_int',0.6,'b1_path',0.2)
            p = inputParser;
            addParameter(p,'mu_t',8.0);
            addParameter(p,'d_ref',1.0);
            addParameter(p,'b1_int',0.6);   % build-up interno max addizionale
            addParameter(p,'b1_path',0.2);  % build-up lungo cammino (moderato)
            parse(p,varargin{:});

            mu_t  = p.Results.mu_t;
            d_ref = p.Results.d_ref;

            comps = [ ...
               struct('kind','cyl','w',0.60,'a',0.045,'L',0.10,'b1',p.Results.b1_int), ... % tiroide/collo
               struct('kind','cyl','w',0.30,'a',0.200,'L',0.55,'b1',p.Results.b1_int), ... % tronco
               struct('kind','sphere','w',0.07,'a',0.09,'L',[]  ,'b1',p.Results.b1_int), ... % testa
               struct('kind','cyl','w',0.03,'a',0.090,'L',0.90,'b1',p.Results.b1_int)  ... % gambe
            ];

            mdl = ModelloComposito(comps, mu_t, d_ref);

            % interno
            mdl.useInternalBuildUp  = true;
            mdl.internalBuildUpMode = 'saturating';
            mdl.b1_internal_default = p.Results.b1_int;

            % path
            mdl.usePathBuildUp   = true;          % attiva path build-up
            mdl.pathBuildUpMode  = 'saturating';
            mdl.b1_path          = p.Results.b1_path;
            mdl.mu_b_path        = mu_t;          % coerente con energia
        end

        function mdl = forLu177(varargin)
            % mdl = ModelloComposito.forLu177('mu_t',12.0,'d_ref',1.0,'b1_int',0.9,'b1_path',0.3)
            p = inputParser;
            addParameter(p,'mu_t',12.0);
            addParameter(p,'d_ref',1.0);
            addParameter(p,'b1_int',0.9);   % più marcato per energie più basse
            addParameter(p,'b1_path',0.3);
            parse(p,varargin{:});

            mu_t  = p.Results.mu_t;
            d_ref = p.Results.d_ref;

            comps = [ ...
               struct('kind','cyl','w',0.85,'a',0.200,'L',0.55,'b1',p.Results.b1_int), ... % tronco dominante
               struct('kind','sphere','w',0.05,'a',0.09,'L',[]  ,'b1',p.Results.b1_int), ... % testa
               struct('kind','cyl','w',0.10,'a',0.090,'L',0.90,'b1',p.Results.b1_int)  ... % gambe
            ];

            mdl = ModelloComposito(comps, mu_t, d_ref);

            % interno
            mdl.useInternalBuildUp  = true;
            mdl.internalBuildUpMode = 'saturating';
            mdl.b1_internal_default = p.Results.b1_int;

            % path
            mdl.usePathBuildUp   = true;
            mdl.pathBuildUpMode  = 'saturating';
            mdl.b1_path          = p.Results.b1_path;
            mdl.mu_b_path        = mu_t;
        end
    end
end
