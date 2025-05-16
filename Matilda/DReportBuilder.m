classdef DReportBuilder < handle
    % DReportBuilder – produce un PDF di istruzioni di dimissione
    %   usando il DOM API (integrato in MATLAB).
    %
    %  ▶ Esempio uso
    %     pat = struct('Name',"Mario Rossi",'ID',"RSSMRA80A01H501Z");
    %     doc = struct('Name',"Dr.ssa Bianchi",'Unit',"Medicina Nucleare");
    %     rep = DReportBuilder(pat,doc,"I-131 (740 MBq)",30);
    %
    %     rep.addScenario("Partner",15, ...
    %        "Letti separati, contatto <30 cm ≤1 h/giorno");
    %     rep.addScenario("Colleghi",6, ...
    %        "Rientro al lavoro dopo 6 gg, distanza ≥2 m");
    %
    %     pdfFile = rep.build("istruzioni_dimissione.pdf");
    %     open(pdfFile)
    %

    properties
        Patient        struct          % .Name  .ID   (string)
        Clinician      struct          % .Name  .Unit (string)
        RadioPharm     string
        DischargeRate  double          % µSv/h @1 m
        Scenarios      struct = struct('Name',{},'Tres',{},'Instr',{})
    end

    methods
        % ----------------------------------------------------------- %
        function obj = DReportBuilder(patient, clinician, radioPharm, rate)
            obj.Patient       = patient;
            obj.Clinician     = clinician;
            obj.RadioPharm    = radioPharm;
            obj.DischargeRate = rate;
        end

        % ----------------------------------------------------------- %
        function addScenario(obj,name,Tres,instr)
            s = struct('Name',string(name), ...
                       'Tres',Tres, ...
                       'Instr',string(instr));
            obj.Scenarios(end+1) = s;
        end

        % ----------------------------------------------------------- %
        function filePDF = build(obj, fileOut)
            import mlreportgen.dom.*          % se vuoi usare Paragraph, Table, ecc.

            d = mlreportgen.dom.Document(fileOut,'pdf');   % <-- nome qualificato
            pl = d.CurrentPageLayout;
            pl.PageSize = 'A4';     % oppure 'Letter', 'A5', ecc.

            %% --- TITOLI ------------------------------------------------
            append(d, Heading1('FOGLIO ISTRUZIONI AL PAZIENTE'));

            info = sprintf(['Paziente: %s    ID: %s\n' ...
                            'Radiofarmaco: %s\n' ...
                            'Rateo alla dimissione: %.0f µSv/h a 1 m\n' ...
                            'Data: %s'], ...
                            obj.Patient.Name, obj.Patient.ID, ...
                            obj.RadioPharm, obj.DischargeRate, ...
                            datestr(now,'dd-mmm-yyyy'));
            pInfo = Paragraph(info); pInfo.Style = {FontSize('10pt')};
            append(d,pInfo);

            %% --- TABELLA TESTUALE RESTRIZIONI -------------------------
            if ~isempty(obj.Scenarios)
                append(d, Heading3('Restrizioni raccomandate'));
                tbl = Table({'Scenario','Giorni','Indicazioni pratiche'});
                tbl.Border = 'solid'; tbl.ColSep = 'solid'; tbl.RowSep = 'solid';
                for s = obj.Scenarios
                    r = TableRow({s.Name, sprintf('%.0f',s.Tres), s.Instr});
                    append(tbl,r);
                end
                append(d,tbl);
            end

            %% --- MATRICE SEMAFORO (scenario × 30 giorni) -------------
            if ~isempty(obj.Scenarios)
                append(d, Heading3('Calendario restrizioni (30 giorni)'));

                mat = Table(); mat.Border = 'solid';
                header = TableRow();
                append(header, TableEntry(' '));              % angolo vuoto
                for dDay = 1:30
                    e = TableEntry(sprintf('%d',dDay));
                    e.Style = {HAlign('center'),Width('5mm')};
                    append(header,e);
                end
                append(mat,header);

                for s = obj.Scenarios
                    row = TableRow();
                    % prima colonna = nome scenario
                    append(row, TableEntry(s.Name));
                    for dDay = 1:30
                        cell = TableEntry();
                        cell.Style = {Width('5mm'),Height('5mm')};
                        if dDay <= s.Tres
                            col = 'red';
                        elseif dDay <= s.Tres+2
                            col = 'gold';
                        else
                            col = 'limegreen';
                        end
                        cell.Style{end+1} = BackgroundColor(col);
                        append(row,cell);
                    end
                    append(mat,row);
                end
                append(d,mat);

                % legenda mini
                leg = Table({'■ Fase restrittiva','■ Fase ordinaria','■ Nessuna restr.'});
                leg.Style = {FontSize('8pt'),OuterMargin('4pt','0pt','0pt','0pt')};
                leg.TableEntriesStyle = {BackgroundColor('white')};
                % colori legenda
                leg.TableEntries(1).Children(1).Style = {FontColor('red')};
                leg.TableEntries(2).Children(1).Style = {FontColor('gold')};
                leg.TableEntries(3).Children(1).Style = {FontColor('limegreen')};
                append(d,leg);
            end

            %% --- FIRMA -----------------------------------------------
            append(d, Paragraph(' '));
            pSign = Paragraph(sprintf('Medico: %s  (%s)', ...
                       obj.Clinician.Name, obj.Clinician.Unit));
            pSign.Style = {FontSize('10pt')};
            append(d,pSign);
            append(d, Paragraph('Firma: ______________________________'));

            %% --- GENERA PDF ------------------------------------------
            close(d);
            filePDF = d.OutputPath;
        end
    end
end
