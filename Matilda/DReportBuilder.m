classdef DReportBuilder < handle
    % PDF istruzioni dimissione – A4 landscape, 40 giorni – MATLAB R2021b

    properties
        Patient       struct
        Clinician     struct
        RadioPharm    string
        DischargeRate double
        Scenarios     struct = struct('Name',{},'Tres',{},'Instr',{})
    end

    methods
        %% costruttore ----------------------------------------------
        function obj = DReportBuilder(pat,doc,rf,rate)
            obj.Patient       = pat;
            obj.Clinician     = doc;
            obj.RadioPharm    = rf;
            obj.DischargeRate = rate;
        end

        %% aggiunge uno scenario ------------------------------------
        function addScenario(obj,name,Tres,instr)
            obj.Scenarios(end+1) = struct("Name",string(name), ...
                "Tres",Tres,          ...
                "Instr",string(instr));
        end

        %% build PDF ------------------------------------------------
        function filePDF = build(obj,fileOut)
            import mlreportgen.dom.*
            borderThin = { Border('solid', '#888888', '0.3pt') };
            d = Document(fileOut,'pdf');

            % pagina A4 landscape
            pl = d.CurrentPageLayout;
            pl.PageSize    = 'A4';
            pl.Orientation = 'landscape';
            pl.PageMargins.Top    = '25mm';
            pl.PageMargins.Bottom = '25mm';
            pl.PageMargins.Left   = '15mm';
            pl.PageMargins.Right  = '15mm';

            %% intestazione
            h1 = Heading1('FOGLIO ISTRUZIONI AL PAZIENTE');
            h1.Style = {FontFamily('Arial')};
            append(d,h1);

            info = sprintf(['Paziente: %s    ID: %s\n'...
                'Radiofarmaco: %s\n' ...
                'Rateo alla dimissione: %.0f µSv/h a 1 m\n'...
                'Data: %s'], ...
                obj.Patient.Name,obj.Patient.ID, ...
                obj.RadioPharm,obj.DischargeRate, ...
                datestr(now,'dd-mmm-yyyy'));
            pInfo = Paragraph(info);
            pInfo.Style = {FontFamily('Arial'),FontSize('10pt')};
            append(d,pInfo);

            %% tabella restrizioni
            if ~isempty(obj.Scenarios)
                h3 = Heading3('Restrizioni raccomandate');
                h3.Style = {FontFamily('Arial')};
                append(d,h3);

                % -- tabella vuota, bordo esterno sottile --------------------------------
                tbl = Table();
                tbl.Border       = 'solid';
                tbl.BorderWidth  = '0.3pt';
                tbl.Style        = {FontFamily('Arial'), FontSize('10pt')};

                % ---------- header con bordi su ogni cella ------------------------------
                hdr = TableRow();

                e = TableEntry('Scenario');               e.Style = borderThin; append(hdr,e);
                e = TableEntry('Giorni');                 e.Style = [borderThin, {HAlign('center'), Width('13mm')}]; append(hdr,e);
                e = TableEntry('Indicazioni pratiche');   e.Style = borderThin; append(hdr,e);

                append(tbl,hdr);

                % ---------- righe dati ---------------------------------------------------
                for k = 1:numel(obj.Scenarios)
                    s = obj.Scenarios(k);
                    r = TableRow();
                    if mod(k,2)==0, r.Style = {BackgroundColor('#f7f7f7')}; end

                    e = TableEntry(s.Name);               e.Style = borderThin; append(r,e);

                    e = TableEntry(sprintf('%.0f',s.Tres));
                    e.Style = [borderThin, {HAlign('center')}];               append(r,e);

                    e = TableEntry(s.Instr);              e.Style = borderThin; append(r,e);

                    append(tbl,r);
                end

                append(d,tbl);
            end

            %% calendario 40 gg
            if ~isempty(obj.Scenarios)
                h3 = Heading3('Calendario restrizioni (40 giorni)');
                h3.Style = {FontFamily('Arial')};
                append(d,h3);

                mat = Table();
                mat.Border = 'solid'; mat.RowSep = 'solid'; mat.ColSep = 'solid';
                mat.BorderWidth = '0.3pt';

                hdr = TableRow();
                append(hdr,TableEntry(' '));
                for dd = 1:40
                    e = TableEntry(sprintf('%d',dd));
                    e.Style = {FontSize('7pt'),Width('5mm'),HAlign('center')};
                    append(hdr,e);
                end
                append(mat,hdr);

                for s = obj.Scenarios
                    r = TableRow();
                    eName = TableEntry(s.Name);
                    eName.Style = {Width('30mm'),FontSize('8pt')};
                    append(r,eName);

                    for dd = 1:40
                        c = TableEntry(Paragraph(char(160)));
                        c.Style = {Width('5mm'),Height('5mm')};
                        if dd <= s.Tres
                            c.Style{end+1} = BackgroundColor('#ff0000');
                        elseif dd <= s.Tres+2
                            c.Style{end+1} = BackgroundColor('#ffd700');
                        else
                            c.Style{end+1} = BackgroundColor('#32cd32');
                        end
                        append(r,c);
                    end
                    append(mat,r);
                end
                append(d,mat);

                % legenda
                leg = Table();
                leg.Style = {FontFamily('Arial'),FontSize('8pt'), ...
                             OuterMargin('4pt','0pt','0pt','0pt')};
                lr = TableRow();

                e = TableEntry(Paragraph('■ Fase restrittiva'));
                e.Style = {BackgroundColor('white'),Color('#ff0000')}; append(lr,e);
                e = TableEntry(Paragraph('■ Fase ordinaria'));
                e.Style = {BackgroundColor('white'),Color('#ffd700')}; append(lr,e);
                e = TableEntry(Paragraph('■ Nessuna restr.'));
                e.Style = {BackgroundColor('white'),Color('#32cd32')}; append(lr,e);

                append(leg,lr); append(d,leg);
            end

            %% firma
            append(d,Paragraph(' '));
            pSign = Paragraph(sprintf('Medico: %s  (%s)', ...
                          obj.Clinician.Name,obj.Clinician.Unit));
            pSign.Style = {FontFamily('Arial'),FontSize('10pt')};
            append(d,pSign);
            append(d,Paragraph('Firma: ______________________________'));

            close(d);
            filePDF = d.OutputPath;
        end
    end
end

