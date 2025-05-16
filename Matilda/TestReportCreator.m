% test_report.m  –  genera un PDF demo con DReportBuilder
% Assicurati che DReportBuilder.m sia sul path.

% === dati fittizi =======================================================
patient   = struct('Name',"Mario Rossi",'ID',"RSSMRA80A01H501Z");
clinician = struct('Name',"Dr.ssa Bianchi",'Unit',"Medicina Nucleare");
radio     = "I-131 (740 MBq)";
rate      = 30;                         % µSv/h @ 1 m alla dimissione

% === costruzione del report ============================================
rep = DReportBuilder(patient, clinician, radio, rate);

% Aggiungi alcuni scenari di prova
rep.addScenario("Partner", 15, ...
    "Letti separati, contatto <30 cm ≤1 h al giorno");
rep.addScenario("Bambino 2-5 aa", 32, ...
    "≤10 min/gg in braccio, distanza ≥1 m per il gioco");
rep.addScenario("Colleghi", 6, ...
    "Rientro dopo 6 gg, distanza ≥2 m durante l’orario di lavoro");

% === genera PDF in cartella temp =======================================
outFile = fullfile(tempdir, 'istruzioni_dimissione_demo.pdf');
pdfPath = rep.build(outFile);

fprintf('PDF creato: %s\n', pdfPath);
open(pdfPath)    % apre subito il PDF