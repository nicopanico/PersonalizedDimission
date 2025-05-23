classdef DReportBuilder < handle
    % DReportBuilder – PDF istruzioni dimissione, 40 gg landscape (R2021b)

    properties
        Patient       struct
        Clinician     struct
        RadioPharm    string
        DischargeRate double
        Scenarios     struct = struct('Name',{},'Tres',{},'Instr',{})
    end

    methods
        %% -------- constructor --------------------------------------
        function obj = DReportBuilder(patient, clinician, radioPharm, rate)
            obj.Patient       = patient;
            obj.Clinician     = clinician;
            obj.RadioPharm    = radioPharm;
            obj.DischargeRate = rate;
        end

        %% -------- aggiunge scenario --------------------------------
        function addScenario(obj,name,Tres,instr)
            obj.Scenarios(end+1) = struct( ...
                "Name",string(name),"Tres",Tres,"Instr",string(instr));
        end

        %% -------- build PDF ----------------------------------------
        function filePDF = build(obj,fileOut)
            import mlreportgen.dom.*

            d  = mlreportgen.dom.Document(fileOut,"pdf");

            % — A4 landscape, margini --------------------------------
            pl = d.CurrentPageLayout;
            pl.PageSize    = "A4";
            pl.Orientation = "landscape";
            pl.PageMargins.Top    = "25mm";
            pl.PageMargins.Bottom = "25mm";
            pl.PageMargins.Left   = "15mm";
            pl.PageMargins.Right  = "15mm";

            %% ---- intestazione --------------------------------------
            h1 = Heading1("FOGLIO ISTRUZIONI AL PAZIENTE");
            h1.Style = {FontFamily("Arial")}; append(d,h1);

            info = sprintf(['Paziente: %s    ID: %s\n'     ...
                            'Radiofarmaco: %s\n'           ...
                            'Rateo alla dimissione: %.0f µSv/h a 1 m\n' ...
                            'Data: %s'], ...
                            obj.Patient.Name,obj.Patient.ID, ...
                            obj.RadioPharm,obj.DischargeRate, ...
                            datestr(now,"dd-mmm-yyyy"));
            pInfo = Paragraph(info);
            pInfo.Style = {FontFamily("Arial"),FontSize("10pt")};
            append(d,pInfo);

            %% ---- tabella restrizioni -------------------------------
            if ~isempty(obj.Scenarios)
                h3 = Heading3("Restrizioni raccomandate");
                h3.Style = {FontFamily("Arial")}; append(d,h3);

                tbl = Table({"Scenario","Giorni","Indicazioni pratiche"});
                tbl.Border = "solid"; tbl.RowSep="solid"; tbl.ColSep="solid";
                tbl.BorderWidth = "0.3pt";
                tbl.Style = {FontFamily("Arial"),FontSize("10pt")};

                for k = 1:numel(obj.Scenarios)
                    s = obj.Scenarios(k);
                    r = TableRow();
                    if mod(k,2)==0, r.Style = {BackgroundColor("#f7f7f7")}; end

                    % colonna 1
                    e = TableEntry(s.Name);
                    e.Style = {Border("solid"),BorderWidth("0.3pt")};
                    append(r,e);

                    % colonna 2 (giorni)
                    e = TableEntry(sprintf("%.0f",s.Tres));
                    e.Style = {HAlign("center"),Border("solid"),BorderWidth("0.3pt")};
                    append(r,e);

                    % colonna 3
                    e = TableEntry(s.Instr);
                    e.Style = {Border("solid"),BorderWidth("0.3pt")};
                    append(r,e);

                    append(tbl,r);
                end
                append(d,tbl);
            end

            %% ---- matrice semaforo 40 gg ----------------------------
            if ~isempty(obj.Scenarios)
                h3 = Heading3("Calendario restrizioni (40 giorni)");
                h3.Style = {FontFamily("Arial")}; append(d,h3);

                mat = Table();
                mat.Border = "solid";
                mat.RowSep = "solid";
                mat.ColSep = "solid";
                mat.BorderWidth = "0.3pt";
                mat.BorderColor = "#888888";
                mat.Style = {FontFamily("Arial")};

                % header 1–40
                hdr = TableRow();
                append(hdr,TableEntry(" "));
                for dd = 1:40
                    e = TableEntry(sprintf("%d",dd));
                    e.Style = {HAlign("center"),Width("5mm"),FontSize("7pt"), ...
                               Border("solid"),BorderWidth("0.3pt"),BorderColor("#888888")};
                    append(hdr,e);
                end
                append(mat,hdr);

                % righe scenario
                for s = obj.Scenarios
                    r = TableRow();

                    eName = TableEntry(s.Name);
                    eName.Style = {Width("30mm"),FontSize("8pt"), ...
                                   Border("solid"),BorderWidth("0.3pt")};
                    append(r,eName);

                    for dd = 1:40
                        cell = TableEntry(Paragraph(char(160))); % NB-space
                        cell.Style = {Width("5mm"),Height("5mm"), ...
                                      Border("solid"),BorderWidth("0.3pt"),BorderColor("#888888")};

                        if dd <= s.Tres
                            cell.Style{end+1} = BackgroundColor("#ff0000");   % rosso
                        elseif dd <= s.Tres+2
                            cell.Style{end+1} = BackgroundColor("#ffd700");   % oro
                        else
                            cell.Style{end+1} = BackgroundColor("#32cd32");   % verde
                        end
                        append(r,cell);
                    end
                    append(mat,r);
                end
                append(d,mat);

                %% ---- legenda ---------------------------------------
                leg = Table();
                leg.Style = {FontFamily("Arial"),FontSize("8pt"), ...
                             OuterMargin("4pt","0pt","0pt","0pt")};
                lr = TableRow();

                mk = @(txt,colHex) ...
                    ( e = TableEntry(Paragraph(txt)); ...
                      e.Style = {BackgroundColor("white"),Color(colHex)}; ...
                      lr.appendChild(e) );

                mk("■ Fase restrittiva","#ff0000");
                mk("■ Fase ordinaria","#ffd700");
                mk("■ Nessuna restr.","#32cd32");

                append(leg,lr); append(d,leg);
            end

            %% ---- firma --------------------------------------------
            append(d,Paragraph(" "));
            pSign = Paragraph(sprintf("Medico: %s  (%s)", ...
                            obj.Clinician.Name,obj.Clinician.Unit));
            pSign.Style = {FontFamily("Arial"),FontSize("10pt")};
            append(d,pSign);
            append(d,Paragraph("Firma: ______________________________"));

            %% ---- salva -------------------------------------------
            close(d);
            filePDF = d.OutputPath;
        end
    end
end

