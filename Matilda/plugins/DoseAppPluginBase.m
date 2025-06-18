%% DoseAppPluginBase.m
classdef (Abstract) DoseAppPluginBase < handle
    % Abstract base class per plugin di DoseApp.
    methods (Abstract)
        % Nome visualizzato di questo plugin
        name = pluginName(obj)
        % Inizializzazione UI all'avvio: parentPanel è un uipanel/tab
        init(obj, app, parentPanel)
    end
    methods
        % Hook opzionale: chiamato dopo il calcolo della dose
        function onCompute(app, data), end
        % Hook opzionale: chiamato prima di generare il PDF
        function onReport(app, reportBuilder), end
    end
end