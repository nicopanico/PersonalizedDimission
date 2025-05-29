# DoseApp – Guida all'uso e documentazione tecnica

## Indice
- [Introduzione](#introduzione)
- [Requisiti software e installazione](#requisiti-software-e-installazione)
- [Struttura del progetto](#struttura-del-progetto)
- [Utilizzo della GUI](#utilizzo-della-gui)
- [Parametri clinici e farmacocinetica](#parametri-clinici-e-farmacocinetica)
- [Scenari di esposizione](#scenari-di-esposizione)
- [Report PDF di istruzioni per il paziente](#report-pdf-di-istruzioni-per-il-paziente)
- [Modifica e aggiornamento dati (JSON)](#modifica-e-aggiornamento-dati-json)
- [Note tecniche e modelli matematici utilizzati](#note-tecniche-e-modelli-matematici-utilizzati)
- [Riferimenti e contatti](#riferimenti-e-contatti)

## Introduzione

**DoseApp** è uno strumento sviluppato per facilitare e migliorare la gestione delle dimissioni di pazienti sottoposti a trattamenti medico-nucleari (ad esempio, terapie con I-131 e Lu-177). Questi trattamenti comportano infatti un periodo durante il quale il paziente emette radiazioni ionizzanti potenzialmente rischiose per chi vive o lavora nelle immediate vicinanze. Diventa quindi cruciale definire con precisione i periodi di restrizione (**T<sub>res</sub>**), ovvero i giorni nei quali è necessario adottare particolari accorgimenti di distanziamento e di comportamento per tutelare familiari, bambini, donne incinte e colleghi.

Tramite un'interfaccia grafica (GUI) intuitiva, **DoseApp** permette agli operatori sanitari (in particolare, fisici medici e medici nucleari) di:

- Inserire rapidamente parametri clinici rilevanti (attività somministrata, rateo di dose alla dimissione, tipologia di radiofarmaco utilizzato).
- Selezionare specifici scenari di esposizione personalizzabili e già predefiniti sulla base di linee guida consolidate e della letteratura scientifica aggiornata.
- Stimare automaticamente i periodi di restrizione necessari, fornendo anche rappresentazioni grafiche chiare dell’andamento della dose da esposizione nel tempo.
- Generare velocemente un foglio informativo personalizzato (in formato PDF), pronto per essere consegnato direttamente al paziente, con istruzioni semplici, comprensibili e dettagliate sulle norme di comportamento da adottare.

In questo modo, **DoseApp** non solo rende più efficiente il lavoro del personale sanitario, ma contribuisce significativamente anche alla sicurezza del paziente e dei suoi conviventi, migliorando la comunicazione medico-paziente e garantendo la conformità alle normative vigenti in ambito di radioprotezione.

Questa documentazione fornisce tutte le informazioni necessarie per l'installazione, l'utilizzo quotidiano, la manutenzione e l'eventuale personalizzazione del software. Sono incluse inoltre indicazioni tecniche dettagliate per eventuali aggiornamenti, modifiche agli scenari espositivi, gestione dei dati clinici, e modelli matematici e computazionali utilizzati.
