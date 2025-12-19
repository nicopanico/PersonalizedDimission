classdef BiExpKineticsPlugin < DoseAppPluginBase
    % Cinetica biexponenziale da dati reali di rateo (tipicamente µSv/h)
    % - input: tempi in ORE (da iniezione o no, gestito con offset)
    % - output: fr = [f_fast, f_slow], lambda_eff = [lambda_fast, lambda_slow] in 1/GIORNO
    % - pensato per essere coerente con il JSON della DoseApp

    properties (Access = private)
        App
        Panel

        Tbl              matlab.ui.control.Table
        AddBtn           matlab.ui.control.Button
        DelBtn           matlab.ui.control.Button
        CleanBtn         matlab.ui.control.Button

        OffsetField      matlab.ui.control.NumericEditField
        NormalizeCheck   matlab.ui.control.CheckBox
        WeightDrop       matlab.ui.control.DropDown

        FitButton        matlab.ui.control.Button
        ExportButton     matlab.ui.control.Button

        Ax               matlab.graphics.axis.Axes
        ResultText       matlab.ui.control.TextArea
    end

    methods
        function name = pluginName(~)
            name = "Cinetica biexp (dati reali)";
        end

        function init(obj, app, parentPanel)
            obj.App   = app;
            obj.Panel = parentPanel;

            % layout generale
            gl = uigridlayout(parentPanel,[4,2]);
            gl.RowHeight   = {'1x', 38, 38, '1.3x'};
            gl.ColumnWidth = {'1x','1x'};
            gl.RowSpacing  = 6;
            gl.ColumnSpacing = 8;
            gl.Padding = [8 8 8 8];

            % ====== 1) tabella dati ======
            obj.Tbl = uitable(gl, ...
                'ColumnName', {'t [h]','R [µSv/h]'}, ...
                'ColumnEditable', [true true], ...
                'Data', [0 NaN; 2 NaN; 24 NaN; 48 NaN; 72 NaN]);
            obj.Tbl.Layout.Row    = 1;
            obj.Tbl.Layout.Column = [1 2];

            % ====== 2a) bottoni tabella ======
            pTab = uigridlayout(gl,[1,3]);
            pTab.Layout.Row    = 2;
            pTab.Layout.Column = 1;
            pTab.ColumnWidth   = {'1x','1x','1x'};
            obj.AddBtn = uibutton(pTab,'Text','+ Riga', ...
                'ButtonPushedFcn', @(~,~) obj.onAddRow());
            obj.DelBtn = uibutton(pTab,'Text','- Riga', ...
                'ButtonPushedFcn', @(~,~) obj.onDelRow());
            obj.CleanBtn = uibutton(pTab,'Text','Pulisci', ...
                'ButtonPushedFcn', @(~,~) obj.onClean());

            % ====== 2b) opzioni (offset, norm) ======
            pOpts = uigridlayout(gl,[1,3]);
            pOpts.Layout.Row    = 2;
            pOpts.Layout.Column = 2;
            pOpts.ColumnWidth   = {'fit','1x','1x'};

            uilabel(pOpts,'Text','Offset [h]:','HorizontalAlignment','right');
            obj.OffsetField = uieditfield(pOpts,'numeric','Value',0);
            obj.NormalizeCheck = uicheckbox(pOpts,'Text','Normalizza','Value',false);

            % ====== 3a) pesi ======
            pW = uigridlayout(gl,[1,2]);
            pW.Layout.Row    = 3;
            pW.Layout.Column = 1;
            pW.ColumnWidth   = {'fit','1x'};
            uilabel(pW,'Text','Pesi:','HorizontalAlignment','right');
            obj.WeightDrop = uidropdown(pW, ...
                'Items',{'Nessuno','Relativo (1/y)'}, ...
                'Value','Relativo (1/y)');

            % ====== 3b) azioni ======
            pAct = uigridlayout(gl,[1,2]);
            pAct.Layout.Row    = 3;
            pAct.Layout.Column = 2;
            pAct.ColumnWidth   = {'1x','1x'};

            obj.FitButton = uibutton(pAct,'Text','Stima cinetica', ...
                'ButtonPushedFcn', @(~,~) obj.runFit(false));
            obj.ExportButton = uibutton(pAct,'Text','Esporta in App', ...
                'ButtonPushedFcn', @(~,~) obj.runFit(true));

            % ====== 4a) grafico ======
            obj.Ax = uiaxes(gl);
            obj.Ax.Layout.Row    = 4;
            obj.Ax.Layout.Column = 1;
            title(obj.Ax,'Fit biexp');
            xlabel(obj.Ax,'Tempo [h]');
            ylabel(obj.Ax,'Rateo');
            grid(obj.Ax,'on');

            % ====== 4b) risultati ======
            obj.ResultText = uitextarea(gl,'Editable','off');
            obj.ResultText.Layout.Row    = 4;
            obj.ResultText.Layout.Column = 2;
            obj.ResultText.Value = { ...
                '1) Inserisci tempi (in ore) e ratei (>0)', ...
                '2) Offset se non sono da iniezione', ...
                '3) "Stima cinetica"', ...
                '4) "Esporta in App" per usarla nella DoseApp' ...
                };
        end
    end

    methods (Access = private)

        % ----------------------------- tabella
        function onAddRow(obj)
            d = obj.Tbl.Data;
            if isempty(d)
                d = [NaN NaN];
            else
                d(end+1,:) = [NaN NaN];
            end
            obj.Tbl.Data = d;
        end

        function onDelRow(obj)
            d = obj.Tbl.Data;
            if isempty(d), return; end
            d(end,:) = [];
            obj.Tbl.Data = d;
        end

        function onClean(obj)
            d = obj.Tbl.Data;
            if isempty(d), return; end
            keep = ~(all(isnan(d),2) | all(d==0,2));
            obj.Tbl.Data = d(keep,:);
        end

        % ----------------------------- core
        function runFit(obj, doExport)

            % === leggi dati dalla tabella
            d   = obj.Tbl.Data;
            t_h = d(:,1);
            y   = d(:,2);

            % filtra i validi
            m = ~isnan(t_h) & ~isnan(y) & (y > 0);
            t_h = t_h(m);
            y   = y(m);

            if numel(t_h) < 4
                uialert(obj.App.UIFigure, ...
                    'Servono almeno 4 misure valide (>0).', ...
                    'Dati insufficienti');
                return;
            end

            % ordina per tempo
            [t_h, idx] = sort(t_h);
            y = y(idx);

            % offset: porto il tempo alla somministrazione
            off_h = obj.OffsetField.Value;
            t_h = t_h - off_h;

            % normalizza (opzionale)
            A0 = 1.0;
            if obj.NormalizeCheck.Value
                A0 = y(1);
                if A0 <= 0
                    A0 = max(y);
                end
                y = y / A0;
            end

            % converto in giorni
            t_d = t_h / 24;

            % ========== modello CON VINCOLI via trasformazioni ==========
            % Parametri non vincolati q = [logS, s, logLamSlow, logDelta]
            %   S        = exp(logS)                 >= 0
            %   f_fast   = sigmoid(s)                in (0,1)
            %   f_slow   = 1 - f_fast
            %   lamSlow  = exp(logLamSlow)           > 0
            %   lamFast  = lamSlow + exp(logDelta)   > lamSlow
            sigm = @(x) 1./(1+exp(-x));

            modelFun_q = @(q, tt_d) ...
                exp(q(1)) .* ( ...
                    sigm(q(2)) .* exp(-(exp(q(3)) + exp(q(4))) .* tt_d) + ... % fast
                   (1 - sigm(q(2))) .* exp(-(exp(q(3))) .* tt_d) );            % slow

            % guess iniziale
            if obj.NormalizeCheck.Value
                S0 = 1.0;
            else
                S0 = y(1);
            end
            f0      = 0.6;
            s0      = log(f0/(1-f0));   % logit
            lamSlow0 = 0.10;            % 1/giorno (T1/2 ~ 6.9 d)
            dLam0    = 0.25;            % differenza fast-slow
            q0 = [log(S0), s0, log(lamSlow0), log(dLam0)];

            % pesi
            w = ones(size(y));
            if strcmp(obj.WeightDrop.Value,'Relativo (1/y)')
                epsw = 1e-6 * max(y);
                w = 1 ./ max(y, epsw);
            end

            % residui
            F = @(q) (modelFun_q(q, t_d) - y) .* w;

            % prova con lsqnonlin, fallback fminsearch
            useLSQ = exist('lsqnonlin','file') == 2;
            if useLSQ
                opts = optimoptions('lsqnonlin','Display','off','MaxIterations',400);
                try
                    q = lsqnonlin(F, q0, [], [], opts);
                catch
                    q = fminsearch(@(qq) sum(F(qq).^2), q0);
                end
            else
                q = fminsearch(@(qq) sum(F(qq).^2), q0);
            end

            % --- estraggo i parametri fisici
            S       = exp(q(1));
            f_fast  = sigm(q(2));
            f_slow  = 1 - f_fast;
            lamSlow = exp(q(3));
            lamFast = lamSlow + exp(q(4));

            % emivite
            T12_fast = log(2) / lamFast;
            T12_slow = log(2) / lamSlow;

            % ===== grafico =====
            cla(obj.Ax);
            hold(obj.Ax,'on');

            % dati (torno alla scala originale se normalizzato)
            if obj.NormalizeCheck.Value
                y_plot = y * A0;
            else
                y_plot = y;
            end
            scatter(obj.Ax, t_h, y_plot, 36, 'filled');

            % curva fitted (0 → max tempo*1.05)
            tmax_d = max(max(t_d,1)) * 1.05;
            tt_d   = linspace(0, tmax_d, 300);
            yy     = modelFun_q(q, tt_d);

            % componenti separate
            y_fast = S * f_fast * exp(-lamFast * tt_d);
            y_slow = S * f_slow * exp(-lamSlow * tt_d);

            % ri-scala se stai mostrando in scala originale
            if obj.NormalizeCheck.Value
                yy     = yy     * A0;
                y_fast = y_fast * A0;
                y_slow = y_slow * A0;
            end

            plot(obj.Ax, tt_d*24, yy, 'LineWidth', 1.5);
            plot(obj.Ax, tt_d*24, y_fast, '--');
            plot(obj.Ax, tt_d*24, y_slow, '--');

            legend(obj.Ax, {'Dati','Totale','Fast','Slow'}, 'Location','northeast');
            xlabel(obj.Ax,'Tempo [h]');
            if obj.NormalizeCheck.Value
                ylabel(obj.Ax,'Rateo (normalizzato)');
            else
                ylabel(obj.Ax,'Rateo [µSv/h]');
            end
            grid(obj.Ax,'on');

            % sistemi un po' gli assi
            ymax = max(y_plot);
            if ymax <= 0, ymax = 1; end
            ylim(obj.Ax, [0, ymax*1.15]);
            xlim(obj.Ax, [0, max(t_h)*1.05 + 1]);

            hold(obj.Ax,'off');

            % ===== testo risultato =====
            res = sprintf([ ...
                'f₁ (fast) = %.3f   f₂ (slow) = %.3f\n' ...
                'λ_fast = %.3f d⁻¹  (T½ = %.2f d)\n' ...
                'λ_slow = %.3f d⁻¹  (T½ = %.2f d)\n' ...
                'Offset applicato: %.2f h\n' ...
                'Pesi: %s | Normalizza: %s'], ...
                f_fast, f_slow, ...
                lamFast, T12_fast, ...
                lamSlow, T12_slow, ...
                off_h, ...
                obj.WeightDrop.Value, ...
                string(obj.NormalizeCheck.Value));

            if lamFast/lamSlow < 1.3
                res = sprintf('%s\nATTENZIONE: le due componenti sono molto simili.\nAggiungi un punto precoce (<4–6 h) e/o uno tardivo (48–72 h).', res);
            end

            obj.ResultText.Value = res;

            % ===== esporta nella App =====
            if doExport
                answer = inputdlg({'Nome cinetica da salvare:'}, ...
                                  'Esporta cinetica', [1 40], ...
                                  {datestr(now,'yyyy-mm-dd_HHMM')});
                if isempty(answer), return; end
                kinName = strtrim(answer{1});
                if isempty(kinName)
                    kinName = 'Cinetica custom';
                end

                newK = struct( ...
                    'name',       kinName, ...
                    'fr',         [f_fast, f_slow], ...
                    'lambda_eff', [lamFast, lamSlow] );

                % sovrascrivi se esiste
                idx = find(strcmp({obj.App.CustomKinetics.name}, kinName), 1);
                if isempty(idx)
                    obj.App.CustomKinetics(end+1) = newK;
                else
                    obj.App.CustomKinetics(idx) = newK;
                end

                % aggiungi al dropdown se manca
                items = obj.App.RadiofarmacoDropDown.Items;
                if ~any(strcmp(items, kinName))
                    items{end+1} = kinName;
                    obj.App.RadiofarmacoDropDown.Items = items;
                end
                obj.App.RadiofarmacoDropDown.Value = kinName;

                uialert(obj.App.UIFigure, ...
                    sprintf(['Cinetica salvata:\n%s\nfr = [%.3f, %.3f]\nλ = [%.3f, %.3f] 1/g\n'], ...
                        kinName, f_fast, f_slow, lamFast, lamSlow), ...
                    'OK');
            end
        end
    end
end
