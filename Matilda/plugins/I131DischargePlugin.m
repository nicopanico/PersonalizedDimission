classdef I131DischargePlugin < DoseAppPluginBase
    properties (Access = private)
        App
        Parent
        DatePicker
        TimeField
        ActivityField
        LimitField
        MeasuresTable
        AddButton
        ComputeButton
        ResultLabel
        Axes
    end

    methods
        function name = pluginName(~)
            name = "Dimissione I-131";
        end

        function init(obj, app, parent)
            obj.App = app;
            obj.Parent = parent;

            gl = uigridlayout(parent, [8 2]);
            gl.RowHeight = {'fit','fit','fit','fit','fit','fit','fit','1x'};
            gl.ColumnWidth = {'fit','1x'};

            % Data somministrazione
            uilabel(gl, "Text", "Data somministrazione:");
            obj.DatePicker = uidatepicker(gl, ...
                'Value', datetime('today'), ...
                'DisplayFormat', 'dd/MM/yyyy');
            obj.DatePicker.Layout.Column = 2;

            % Ora somministrazione (es: 11:34)
            uilabel(gl, "Text", "Ora somministrazione (HH:MM):");
            obj.TimeField = uieditfield(gl, 'text', 'Value', '11:30');
            obj.TimeField.Layout.Column = 2;

            % Attività somministrata
            uilabel(gl, "Text", "Attività somministrata (MBq):");
            obj.ActivityField = uieditfield(gl, 'numeric', 'Value', 600);
            obj.ActivityField.Layout.Column = 2;

            % Limite dose rate (µSv/h) [default 12]
            uilabel(gl, "Text", "Limite rateo (µSv/h) a 2m:");
            obj.LimitField = uieditfield(gl, 'numeric', 'Value', 12);
            obj.LimitField.Layout.Column = 2;

            % Bottone "+" per aggiungere riga
            obj.AddButton = uibutton(gl, "Text", "+ Aggiungi misura", ...
                'ButtonPushedFcn', @(~,~) obj.addRow());
            obj.AddButton.Layout.Row = 5; obj.AddButton.Layout.Column = 2;

            % Tabella per misure [Tempo (h), Rateo (µSv/h) a 2m]
            uilabel(gl, "Text", "Misure [ore, µSv/h] a 2m:");
            obj.MeasuresTable = uitable(gl, ...
                'Data', obj.defaultMeasures(), ...
                'ColumnName', {'Tempo (h)', 'Rateo (µSv/h)'}, ...
                'ColumnEditable', [true true], ...
                'CellEditCallback', @(~,~) obj.updatePlot());
            obj.MeasuresTable.Layout.Row = 6; obj.MeasuresTable.Layout.Column = [1 2];

            % Bottone calcola
            obj.ComputeButton = uibutton(gl, "Text", "Stima dimissione", ...
                'ButtonPushedFcn', @(~,~) obj.computeDischarge());
            obj.ComputeButton.Layout.Row = 7; obj.ComputeButton.Layout.Column = 1;

            % Output risultato
            obj.ResultLabel = uilabel(gl, "Text", "");
            obj.ResultLabel.Layout.Row = 7; obj.ResultLabel.Layout.Column = 2;

            % Grafico
            obj.Axes = uiaxes(gl);
            obj.Axes.Layout.Row = 8; obj.Axes.Layout.Column = [1 2];
            title(obj.Axes, 'Curva decadimento rateo I-131 a 2m');
            xlabel(obj.Axes, 'Tempo (h) dalla somministrazione');
            ylabel(obj.Axes, 'Rateo (µSv/h)');

            % Quando cambi data o ora, aggiorna la tabella dei tempi!
            obj.DatePicker.ValueChangedFcn = @(~,~) obj.resetMeasures();
            obj.TimeField.ValueChangedFcn  = @(~,~) obj.resetMeasures();

            obj.resetMeasures(); % Chiamata iniziale
        end

        function resetMeasures(obj)
            obj.MeasuresTable.Data = obj.defaultMeasures();
            obj.updatePlot();
        end

        function data = defaultMeasures(obj)
            try
                t0 = obj.getSomministrazioneDateTime();
            catch
                t0 = datetime('today') + hours(11.5);
            end

            % Slot clinici: subito dopo somm (0h), dopo 2h, alle 8 e alle 16 dei giorni dopo
            slotHours = [0, 2];
            giorni = 1:2;   % Numero di giorni successivi

            for kDay = giorni
                % Orario misura alle 8:00
                t8 = dateshift(t0, 'start', 'day') + days(kDay) + hours(8);
                slot8 = hours(t8 - t0);
                % Orario misura alle 16:00
                t16 = dateshift(t0, 'start', 'day') + days(kDay) + hours(16);
                slot16 = hours(t16 - t0);
                slotHours = [slotHours, slot8, slot16];
            end

            data = [slotHours(:), nan(numel(slotHours),1)];
        end

        function addRow(obj)
            data = obj.MeasuresTable.Data;
            if isempty(data) || all(isnan(data(:,1)))
                nextHour = 0; % Prima misura: 0 ore
            else
                nextHour = max(data(:,1)) + 2; % Prossima misura: 2h dopo l'ultima
            end
            newRow = [nextHour, NaN];
            data = [data; newRow];
            obj.MeasuresTable.Data = data;
        end

        function h = hoursFromSomministrazioneToHour(obj, t0, targetHour, dayOffset)
            if nargin < 4, dayOffset = 0; end
            giornoBase = dateshift(t0, 'start', 'day') + days(dayOffset);
            tTarget = giornoBase + hours(targetHour);
            if tTarget < t0
                tTarget = tTarget + days(1);
            end
            h = hours(tTarget - t0);
        end

        function dt0 = getSomministrazioneDateTime(obj)
            d = obj.DatePicker.Value;
            t = obj.TimeField.Value;
            hhmm = sscanf(t, '%d:%d');
            if numel(hhmm) == 2
                hh = hhmm(1); mm = hhmm(2);
            else
                error('Formato orario non valido. Usa HH:MM');
            end
            dt0 = datetime(year(d), month(d), day(d), hh, mm, 0);
        end

        function updatePlot(obj)
            data = obj.MeasuresTable.Data;
            t = data(:,1); y = data(:,2);
            valid = ~isnan(t) & ~isnan(y) & y>0 & t>=0;
            t = t(valid); y = y(valid);

            cla(obj.Axes);

            if ~isempty(t)
                scatter(obj.Axes, t, y, 60, 'filled', 'DisplayName', 'Misure');
                hold(obj.Axes,'on');
            end

            % Fit mono-esponenziale
            if numel(t) >= 2
                try
                    ft = fittype('a*exp(-lambda*x)','independent','x');
                    opts = fitoptions('Method','NonlinearLeastSquares', 'StartPoint',[max(y), 0.1]);
                    [fitresult,~] = fit(t, y, ft, opts);
                    tt = linspace(0, max([t; 96]), 100);
                    plot(obj.Axes, tt, fitresult(tt), 'r-', 'DisplayName', 'Fit exp');
                catch
                    % Se fit fallisce non crashare
                end
            end

            % Soglia
            yline(obj.Axes, obj.LimitField.Value, '--k', sprintf('Soglia %.1f', obj.LimitField.Value));
            hold(obj.Axes,'off');
            legend(obj.Axes, 'show');
        end

        function computeDischarge(obj)
            data = obj.MeasuresTable.Data;
            t = data(:,1); y = data(:,2);
            valid = ~isnan(t) & ~isnan(y) & y>0 & t>=0;
            t = t(valid); y = y(valid);

            if numel(t)<2
                obj.ResultLabel.Text = "Inserire almeno 2 misure!";
                return;
            end

            % Fit mono-esponenziale
            try
                ft = fittype('a*exp(-lambda*x)','independent','x');
                opts = fitoptions('Method','NonlinearLeastSquares', 'StartPoint',[max(y), 0.1]);
                [fitresult,~] = fit(t, y, ft, opts);
            catch
                obj.ResultLabel.Text = "Fit non riuscito.";
                return;
            end

            soglia = obj.LimitField.Value;
            if fitresult.a <= soglia
                obj.ResultLabel.Text = "Già dimissibile!";
                return;
            end
            tstar = log(fitresult.a/soglia)/fitresult.lambda;
            if tstar < min(t)
                obj.ResultLabel.Text = "Già dimissibile!";
            else
                % Data prevista (rispetto a data/ora somministrazione)
                dataSom = obj.getSomministrazioneDateTime();
                tstarAbs = dataSom + hours(tstar);
                obj.ResultLabel.Text = sprintf('Dimissibile tra %.1f h\n(%s)', tstar, datestr(tstarAbs,'dd-mmm-yyyy HH:MM'));
            end

            % Aggiorna plot
            obj.updatePlot();
            hold(obj.Axes,'on');
            plot(obj.Axes, [tstar tstar], [0 soglia], 'g--', 'LineWidth',2, 'DisplayName','T* dimissibilità');
            scatter(obj.Axes, tstar, soglia, 80, 'g','filled');
            hold(obj.Axes,'off');
        end
    end
end
