# DoseApp – Guida all'uso e documentazione tecnica

## Indice
- [Introduzione](#introduzione)
- [Requisiti software e installazione](#requisiti-software-e-installazione)
- [Modello di calcolo della dose](#modello-di-calcolo-della-dose)      
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

## Requisiti Software e Installazione

Questa sezione descrive i requisiti software e la procedura passo-passo per installare ed eseguire correttamente **DoseApp**.

---

### 🚩 Requisiti Software Minimi

Per utilizzare correttamente **DoseApp**, assicurarsi di disporre di:

- **MATLAB versione R2021b** (o successive)
  - Licenza valida per il MATLAB Report Generator toolbox, richiesto per la generazione automatica dei report in formato PDF.
- Sistema operativo supportato da MATLAB (Windows, macOS, Linux).
- Un editor di testo (opzionale, per la modifica dei file JSON di configurazione), ad esempio [Visual Studio Code](https://code.visualstudio.com/) o [Notepad++](https://notepad-plus-plus.org/).

---

### 📥 Procedura di Installazione

Seguire attentamente questi passaggi per installare e avviare **DoseApp**:

**1. Clonare o scaricare il repository**

Scaricare il repository completo (file `.zip`) oppure clonare direttamente da terminale tramite Git:

```bash
git clone https://github.com/nicopanico/PersonalizedDimission.git
```

**2. Aprire MATLAB e inizializzare il codice**

Avvia MATLAB e imposta la cartella contenente `PersonalizedDimission` come directory corrente.  
Dalla Command Window digita:

```matlab
addpath(genpath('PersonalizedDimission'));  % include tutte le sottocartelle
savepath;                                   % salva il percorso
```
In questo modo vengono aggiunte tutte le sottocartelle, è anche sufficiente aprire il codice direttamente da MATLAB dentro la cartella.

## Modello di calcolo della dose

DoseApp implementa un **modello di sorgente lineare** (altezza assiale $H \approx 1.70\,$m) con costante di normalizzazione $\Gamma$ scelta affinché  
$\dot D(1\text{ m}) = 1\\mu\text{Sv·h}^{-1}$ quando $A_{\text{tot}} = 1$.

La **dose-rate puntuale** a distanza $d$ vale


$$
\dot D(d)=
\Gamma\
\frac{A_{\text{tot}}}{Hd}\
\arctan\\left(\frac{H}{2d}\right)
$$


Il **fattore di correzione geometrico** usato negli scenari è il rapporto tra due dose-rate:

$$
F_{\text{corr}}(d) \=\
\frac{\dot D(d)}{\dot D(1\text{ m})}
$$

Il periodo di restrizione ottimale $T_{\text{res}}$ si ottiene risolvendo

$$
D_{\text{restr}}\bigl(T_{\text{res}}\bigr)
\+\
D_{\text{ord}}\bigl(T_{\text{res}}\bigr)
\=\
\text{DoseConstraint}
$$

dove $D_{\text{restr}}$ e $D_{\text{ord}}$ sono gli integrali dose-tempo sulle due fasi (restrittiva / ordinaria) secondo *Buonamici 2025*.  
Il metodo di bisezione implementato in `DoseCalculator.trovaPeriodoRestrizione` garantisce una tolleranza di 0.01 giorni.

> Per l’implementazione completa dei modelli, vedi anche la sezione [Note tecniche e modelli matematici utilizzati](#note-tecniche-e-modelli-matematici-utilizzati).

## Utilizzo della GUI

![Panoramica GUI](docs/img/gui_overview.png)

L’interfaccia di **DoseApp** è suddivisa in tre colonne:

| # | Pannello | Funzione principale |
|---|----------|--------------------|
| **①** | **Parametri clinici** | Inserisci nome paziente, *T*<sub>discharge</sub>, rateo di dimissione e radio-farmaco. <br> Contiene i pulsanti **Calcola Dose**, **Grafico Dose** e **Genera PDF**. |
| **②** | **Scenari di esposizione** | Spunta uno o più scenari restrittivi (partner, bambino, colleghi, ecc.). <br> Per **Colleghi** appare un menu a tendina per scegliere la distanza “Standard ≈ 1 m” o “Sempre ≥ 2 m”. |
| **③** | **Risultati** | Mostra, per ogni scenario selezionato, il periodo ottimale di restrizione **T**<sub>res</sub> (in giorni) e la dose cumulativa a 7 gg. <br> I valori sono in grassetto e separati da una riga vuota per facilitarne la lettura. |

---
> Consiglio rapido: dopo aver compilato i parametri e selezionato gli scenari, premi **Genera PDF** per ottenere il foglio istruzioni da consegnare al paziente.

### Passaggi rapidi

1. **Compila i parametri clinici**  
   - Nome paziente (facoltativo)  
   - *T*<sub>discharge</sub> (giorni)  
   - Rateo *R*<sub>T dis</sub> (µSv / h @ 1 m)  
   - Attività somministrata (MBq)  
   - Seleziona il radiofarmaco dal menu a tendina

2. **Seleziona gli scenari**  
   Spunta le caselle corrispondenti alle restrizioni da valutare.  
   È possibile selezionare più scenari contemporaneamente.

3. **Calcola o visualizza**  
   - **Calcola Dose**: popola il riquadro “Risultati” con **T**<sub>res</sub> e dose 7 gg.  
   - **Grafico Dose**: apre la curva -dose vs *T*<sub>res</sub> con evidenza del limite di dose.

4. **Genera il PDF**  
   - Clicca **Genera PDF** → scegli dove salvare il file.  
   - Il report include intestazione, tabella riassuntiva, calendario “semaforo” a 40 gg e spiegazioni discorsive per ogni scenario.

---

### Suggerimenti utili

| Esigenza | Operazione |
|----------|------------|
| Aggiornare parametri farmacocinetici | Modifica `radiopharmaceuticals.json`, poi riavvia l’app |
| Aggiungere un nuovo scenario | Implementa il metodo statico in `Scenario.m` **e** aggiorna `doseApp.pairMap` / `pairMapOrd` |
| Cambiare altezza sorgente lineare | Modifica il costruttore `ModelloLineare( H )` (riga 183 di `DoseApp.m`) |
| PDF non generato | Verifica licenza Report Generator:<br>`license('test','MATLAB_Report_Gen')` deve restituire `1` |

> Per dubbi o segnalazioni apri pure una *Issue* su GitHub o contatta il maintainer indicato in [Riferimenti e contatti](#riferimenti-e-contatti).
