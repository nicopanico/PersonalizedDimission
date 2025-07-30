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
            nome = obj.Patient.Name;

            if isfield(obj.Patient,'ID') && ~isempty(obj.Patient.ID)
                idTxt = ['    ID: ', obj.Patient.ID];
            else
                idTxt = '';                   % nessun ID -> niente testo
            end

            info = sprintf(['Paziente: %s%s\n' ...      % <-- usa idTxt
                'Radiofarmaco: %s\n' ...
                'Rateo alla dimissione: %.0f µSv/h a 1 m\n' ...
                'Data: %s'], ...
                nome, idTxt, ...             % <—
                obj.RadioPharm, obj.DischargeRate, ...
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

                    % ───── rileva “Trasporto” + 177Lu ───────────────────────────
                    isTrav = contains(s.Name,'Trasporto','IgnoreCase',true);
                    isLu   = contains(obj.RadioPharm,'DOTATATE','IgnoreCase',true) || ...
                        contains(obj.RadioPharm,'PSMA','IgnoreCase',true);

                    r = TableRow();
                    if mod(k,2)==0, r.Style = {BackgroundColor('#f7f7f7')}; end

                    % colonna 1 : nome scenario
                    e = TableEntry(s.Name);   e.Style = borderThin;  append(r,e);

                    % ------- colonna 2-3 in base al caso -----------------------
                    if isLu && isTrav
                        % ---- 177Lu / Viaggio  ---------------------------------
                        oreMax = DReportBuilder.maxOreTravel(obj.DischargeRate);

                        % Giorni “–”
                        e = TableEntry('–');
                        e.Style = [borderThin, {HAlign('center')}];
                        append(r,e);

                        % Indicazioni pratiche con ore max
                        txt = sprintf('Può viaggiare massimo %.1f h totali su mezzi pubblici', oreMax);
                        e = TableEntry(txt);  e.Style = borderThin;  append(r,e);

                    else
                        % ---- casi normali (manteniamo T_res) ------------------
                        e = TableEntry(sprintf('%.0f', s.Tres));
                        e.Style = [borderThin, {HAlign('center')}];   append(r,e);

                        e = TableEntry(s.Instr);   e.Style = borderThin;   append(r,e);
                    end

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
                    isTrav = contains(s.Name,'Trasporto','IgnoreCase',true);
                    isLu   = contains(obj.RadioPharm,'DOTATATE','IgnoreCase',true) || ...
                        contains(obj.RadioPharm,'PSMA','IgnoreCase',true);

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
            %% --- Norme di comportamento (nuovo blocco) -----------------------------
            append(d, Heading3('Norme di comportamento'));

            for s = obj.Scenarios
                par = DReportBuilder.restr2para(s.Name);
                par = strrep(par, 'T_res', sprintf('%.0f', s.Tres));   % sostituisce il numero
                p   = Paragraph(char(par));
                p.Style = {FontFamily('Arial'), FontSize('10pt'), ...
                    OuterMargin('4pt','0pt','0pt','0pt')};
                append(d, p);
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
    methods (Static)
        function txt = restr2para(nomeScen)
            % Normalizza il nome per il mapping
            nomeScen = lower(strtrim(nomeScen));
            nomeScen = strrep(nomeScen, ' restr.', '');
            nomeScen = strrep(nomeScen, ' aa', '');
            nomeScen = strrep(nomeScen, '  ', ' ');

            switch nomeScen
                case 'partner'
                    txt = [
                        "Per i primi T_res giorni si raccomanda di non condividere ", ...
                        "il letto con il partner. Il contatto ravvicinato (ad es. ", ...
                        "a tavola) deve restare entro 2 h/gg; le attività a più di ", ...
                        "2 m, come guardare la TV su divani separati, sono sicure."];
                case 'bambino <2'
                    txt = [
                        "Nei primi T_res giorni limitare il contatto in braccio o ", ...
                        "allattamento a circa 15 min al giorno. Tenere il bambino ", ...
                        "nel lettino o carrozzina a ≥1 m; passeggino a ≥2 m è idoneo."];
                case {'bambino 2–5', 'bambino 2-5'}
                    txt = [
                        "Fino a T_res giorni evitare abbracci o gioco ravvicinato ", ...
                        "prolungato. Giocare fianco a fianco a 1 m per non più di ", ...
                        "1 h/g è consentito; mantenere ≥2 m quando possibile."];
                case {'bambino 5–11', 'bambino 5-11'}
                    txt = [
                        "Il contatto a 1 m (compiti, gioco da tavolo) non deve ", ...
                        "superare 2 h/g nei primi T_res giorni. Nessuna restrizione ", ...
                        "se il bambino resta a ≥2 m."];
                case {'colleghi', 'colleghi lavoro'}
                    txt = [
                        "Puoi riprendere il lavoro dopo T_res giorni. Mantieni ", ...
                        "permanentemente la distanza minima indicata (≥1 m o ≥2 m ", ...
                        "se selezionato) durante l’orario di lavoro."];
                case {'incinta', 'donna incinta'}
                    txt = [
                        "Per T_res giorni mantieni almeno 1 m da donne in gravidanza ", ...
                        "e riduci al minimo il contatto fisico diretto."];
                case {'trasporto', 'trasporto pubblico'}
                    txt = [
                        "Per i primi 2 giorni limita/evita i mezzi pubblici secondo le " ...
                        "indicazioni in tabella. In automobile privata siedi sul sedile " ...
                        "posteriore, lato passeggero, mantenendo ≥1 m dal guidatore." ];
                otherwise
                    txt = "";
            end
        end
    end
    methods (Static)
        function ore = maxOreTravel(rateo)
            % Tabella 6 AIFM-AIMN 2024
            lim = [5 10 15 20 30 40];     % µSv/h
            ore = [0  1   2  3  4  6 ];   % h di viaggio
            idx = find(rateo < lim, 1,'first');
            if isempty(idx), ore = ore(end);
            else,             ore = ore(idx);
            end
        end
    end
end

