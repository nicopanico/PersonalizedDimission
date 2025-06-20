%% BiExpKineticsPlugin.m
classdef BiExpKineticsPlugin < DoseAppPluginBase
    % Plugin per stima cinetica biesponenziale da 4 misure
    properties (Access=private)
        App        % reference a DoseApp
        Panel      % pannello UI del plugin
        TimeFields % campi di inserimento tempo
        RateFields % campi di inserimento rateo dose
        FitButton  % bottone per avviare la stima
        ResultText % area di testo per mostrare parametri stimati
    end

    methods
        function name = pluginName(~)
            name = "Stima Kinetica Biexponenziale";
        end

        function init(obj, app, parentPanel)
            % Salva referenze
            obj.App   = app;
            obj.Panel = parentPanel;

            % Layout: 6 righe, 2 colonne
            gl = uigridlayout(parentPanel, [6,2]);
            gl.RowHeight    = repmat({'fit'},1,6);
            gl.ColumnWidth  = {'fit','1x'};

            % --- Intestazioni ---
            lbl1 = uilabel(gl, 'Text', 'Ora [h]');
            lbl1.Layout.Row    = 1;
            lbl1.Layout.Column = 1;

            lbl2 = uilabel(gl, 'Text', 'Rateo [µSv/h]');
            lbl2.Layout.Row    = 1;
            lbl2.Layout.Column = 2;

            % --- campi input per 4 misure ---
            obj.TimeFields = gobjects(1,4);
            obj.RateFields = gobjects(1,4);
            for i = 1:4
                tf = uieditfield(gl,'numeric');
                tf.Layout.Row    = i+1;
                tf.Layout.Column = 1;

                rf = uieditfield(gl,'numeric');
                rf.Layout.Row    = i+1;
                rf.Layout.Column = 2;

                obj.TimeFields(i) = tf;
                obj.RateFields(i)= rf;
            end

            % --- bottone di fit ---
            obj.FitButton = uibutton(gl,'push', 'Text','Stima cinetica');
            obj.FitButton.Layout.Row    = 6;
            obj.FitButton.Layout.Column = 1;
            obj.FitButton.ButtonPushedFcn = @(~,~) obj.runFit();

            % --- area risultati ---
            obj.ResultText = uitextarea(gl, 'Editable','off');
            obj.ResultText.Layout.Row    = 6;
            obj.ResultText.Layout.Column = 2;
        end
    end
    methods (Access=private)
        function runFit(obj)
            % Leggi dati
            t = arrayfun(@(f) f.Value, obj.TimeFields);
            y = arrayfun(@(f) f.Value, obj.RateFields);
            % Rimuovi eventuali NaN
            mask = ~isnan(t) & ~isnan(y);
            t = t(mask); y = y(mask);
            if numel(t)<4
                uialert(obj.App.UIFigure, 'Inserisci 4 misure valide','Errore Fit');
                return;
            end
            % Modello biesponenziale: y = A1*exp(-lambda1*t) + A2*exp(-lambda2*t)
            % Parametri: p = [A1,A2,lambda1,lambda2]
            fun = @(p,tt) p(1)*exp(-p(3)*tt) + p(2)*exp(-p(4)*tt);
            p0  = [max(y), max(y)/2, 0.1, 0.01]; % iniziali
            opts = optimoptions('lsqcurvefit','Display','off');
            try
                lb = [0,0,0,0]; ub = [Inf,Inf,Inf,Inf];
                p = lsqcurvefit(fun, p0, t, y, lb, ub, opts);
            catch ME
                uialert(obj.App.UIFigure, 'Fit biesponenziale fallito','Errore Fit');
                return;
            end
            A1 = p(1);  A2 = p(2);
            lam1_h = p(3); lam2_h = p(4);

            % 1) Fractions f1,f2
            A_tot = A1 + A2;
            f1 = A1 / A_tot;
            f2 = A2 / A_tot;

            % 2) Converti lambda da [1/h] a [1/giorno]
            lam1_d = lam1_h * 24;
            lam2_d = lam2_h * 24;

            
            name = inputdlg('Nome per questa cinetica:','Esporta cinetica');
            if isempty(name), return; end
            name = name{1};

            % — preparo la struct custom —
            newK = struct( ...
                'name',name, ...
                'fr',[f1,f2], ...
                'lambda_eff',[lam1_d,lam2_d] );

            % — la salvo in app.CustomKinetics —
            obj.App.CustomKinetics(end+1) = newK;

            % — aggiorno il dropdown nella GUI principale —
            items = obj.App.RadiofarmacoDropDown.Items;
            items{end+1} = name;
            obj.App.RadiofarmacoDropDown.Items = items;

            % Mostra risultati nel formato Buonamici
            txt = sprintf([
                'f₁ = %.3f   λ₁ = %.3f  1/d\n' ...
                'f₂ = %.3f   λ₂ = %.3f  1/d'], ...
                f1, lam1_d, f2, lam2_d);
            obj.ResultText.Value = txt;
        end
    end
end
