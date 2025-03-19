function rph = loadRadiopharmaceutical(name, filename)
    % Se il filename non viene fornito, usa il default
    if nargin < 2
        filename = 'radiopharmaceuticals.json';
    end

    % Apri il file e leggi il contenuto
    fid = fopen(filename, 'r');
    if fid == -1
        error('Impossibile aprire il file %s', filename);
    end
    raw = fread(fid, inf, '*char')';
    fclose(fid);

    % Decodifica il JSON in una struttura MATLAB
    data = jsondecode(raw);

    % Trova il radiofarmaco con il nome corrispondente
    idx = find(strcmp({data.name}, name), 1);
    if isempty(idx)
        error('Radiofarmaco "%s" non trovato nel file %s', name, filename);
    end
    rph = data(idx);
end
