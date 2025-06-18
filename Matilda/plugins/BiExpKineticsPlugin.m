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
            % Mostra risultati
            txt = sprintf([
                'A1 = %.3g\nA2 = %.3g\n', ...
                '\lambda1 = %.3f 1/h\n\lambda2 = %.3f 1/h'], p(1),p(2),p(3),p(4));
            obj.ResultText.Value = txt;
        end
    end
end
