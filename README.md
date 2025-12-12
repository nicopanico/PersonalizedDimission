# DoseApp – Guida all'uso e documentazione tecnica

## Indice
- [Introduzione](#introduzione)
- [Requisiti software e installazione](#requisiti-software-e-installazione)
- [Modello di calcolo della dose](#modello-di-calcolo-della-dose)
- [Sistema a Plugin](#sistema-a-plugin)
- [Esempio di plugin – BiExpKineticsPlugin](#esempio-di-plugin-biexpkineticsplugin)
- [Utilizzo della GUI](#utilizzo-della-gui)
- [Parametri clinici e farmacocinetica](#parametri-clinici-e-farmacocinetica)
- [Scenari di esposizione](#scenari-di-esposizione)
- [Modalità “Isolamento totale”](#modalità-isolamento-totale)
- [Trasporto / viaggio](#trasporto--viaggio)
- [Personalizzazione scenari (Scenario Editor)](#personalizzazione-scenari-scenario-editor)
- [Report PDF di istruzioni per il paziente](#report-pdf-di-istruzioni-per-il-paziente)
- [Note tecniche e modelli matematici utilizzati](#note-tecniche-e-modelli-matematici-utilizzati)
- [Riferimenti e contatti](#riferimenti-e-contatti)

---

## Introduzione

**DoseApp** è uno strumento sviluppato per facilitare e migliorare la gestione delle dimissioni di pazienti sottoposti a trattamenti medico-nucleari (ad esempio, terapie con **I-131** e **Lu-177**). Questi trattamenti comportano infatti un periodo durante il quale il paziente emette radiazioni ionizzanti potenzialmente rischiose per chi vive o lavora nelle immediate vicinanze. Diventa quindi cruciale definire con precisione i periodi di restrizione (**T<sub>res</sub>**), ovvero i giorni nei quali è necessario adottare particolari accorgimenti di distanziamento e di comportamento per tutelare familiari, bambini, donne incinte e colleghi.

DoseApp implementa un approccio **personalizzato e scenariale** coerente con la letteratura recente sulle dimissioni post-terapia e, in particolare, con la logica “restrittivo + ordinario” proposta da **Banci Buonamici et al. (2025)** (vedi [Riferimenti fondativi](#riferimenti-fondativi)). Il calcolo è guidato dal **rateo di dose misurato alla dimissione** e da **scenari realistici** di contatto.

Tramite un’interfaccia grafica (GUI) intuitiva, **DoseApp** permette agli operatori sanitari (in particolare, fisici medici e medici nucleari) di:

- Inserire rapidamente parametri clinici rilevanti (attività somministrata, rateo di dose alla dimissione, tipologia di radiofarmaco utilizzato).
- Selezionare specifici scenari di esposizione personalizzabili e già predefiniti sulla base di linee guida consolidate e della letteratura scientifica.
- Stimare automaticamente i periodi di restrizione necessari, fornendo anche rappresentazioni grafiche dell’andamento dose-tempo.
- Generare un foglio informativo personalizzato (PDF) con istruzioni semplici e consegnabili al paziente.

Questa documentazione fornisce le informazioni per installazione, utilizzo, manutenzione e personalizzazione (scenari, farmacocinetiche via JSON, plugin).

---

## Requisiti Software e Installazione

### 🚩 Requisiti Software Minimi

Per utilizzare correttamente **DoseApp**, assicurarsi di disporre di:

- **MATLAB R2021b** (o successive).
- Toolbox consigliati / richiesti:
  - **MATLAB Report Generator** (necessario per la generazione automatica del PDF).
  - **Optimization Toolbox** (necessario solo per plugin/fit, es. `lsqcurvefit` nel plugin bi-esponenziale).
- Sistema operativo supportato da MATLAB (Windows, macOS, Linux).
- Editor di testo (opzionale) per modificare i file JSON (es. VS Code, Notepad++).

### 📥 Procedura di Installazione

**1. Clonare o scaricare il repository**

```bash
git clone https://github.com/nicopanico/PersonalizedDimission.git
```

**2. Aprire MATLAB e inizializzare il codice**

Impostare la cartella `PersonalizedDimission` come directory corrente e aggiungere al path:

```matlab
addpath(genpath('PersonalizedDimission'));  % include tutte le sottocartelle
savepath;                                   % salva il percorso
```

> In alternativa è spesso sufficiente aprire direttamente il progetto da MATLAB dentro la cartella (con path relativo).

---

## Modello di calcolo della dose

DoseApp implementa un **modello di sorgente lineare** (altezza assiale \(H \approx 1.70\) m) con costante di normalizzazione \(\Gamma\) scelta affinché  
\(\dot D(1\text{ m}) = 1\,\mu\text{Sv·h}^{-1}\) quando \(A_{\text{tot}} = 1\).

La **dose-rate puntuale** a distanza \(d\) vale:

\[
\dot D(d)=
\Gamma\,
\frac{A_{\text{tot}}}{H\,d}\,
\arctan\!\left(\frac{H}{2d}\right)
\]

Il **fattore di correzione geometrico** usato negli scenari è il rapporto tra due dose-rate:

\[
F_{\text{corr}}(d)=
\frac{\dot D(d)}{\dot D(1\text{ m})}
\]

Il periodo di restrizione ottimale \(T_{\text{res}}\) si ottiene risolvendo:

\[
D_{\text{restr}}\bigl(T_{\text{res}}\bigr)
+
D_{\text{ord}}\bigl(T_{\text{res}}\bigr)
=
\text{DoseConstraint}
\]

dove \(D_{\text{restr}}\) e \(D_{\text{ord}}\) sono gli integrali dose-tempo sulle due fasi (restrittiva / ordinaria), in coerenza con l’impostazione “two-phase” di **Banci Buonamici et al. (2025)**.  
Il metodo di bisezione implementato in `DoseCalculator.trovaPeriodoRestrizione` garantisce una tolleranza tipica di ~0.01 giorni.

### Vincolo clinico minimo sul periodo di restrizione (floor a 5 giorni)

Per radiofarmaci a lunga permanenza corporea, in particolare **¹³¹I** e **¹⁷⁷Lu** (DOTATATE, PSMA), DoseApp applica un **vincolo clinico minimo**:

\[
T_{\text{res}} \ge 5 \text{ giorni}
\]

Questo “floor” è applicato **post-calcolo** (non altera la forma del modello) ed è valido:
- nel flusso standard multi-scenario,
- nella modalità **Isolamento totale**,
- nella generazione del **PDF**.

Dal punto di vista implementativo, è gestito tramite la funzione `applyMin5DaysIfNeeded()`.

### Nota su I-131: input a 2 m e conversione a 1 m

Per **I-131**, l’interfaccia richiede il rateo \(R_{Tdis}\) misurato **a 2 m** e lo converte internamente all’equivalente a **1 m** (per uniformare il calcolo agli altri radiofarmaci).  
Per gli altri radiofarmaci, \(R_{Tdis}\) è assunto già **a 1 m**.

---

## Sistema a Plugin
<a name="sistema-a-plugin"></a>

**DoseApp** può essere esteso senza toccare il core grazie a un sistema di plugin caricati all’avvio.

| Cartella / File | Scopo |
|----------|-------|
| `plugins/` | contiene i file `.m` dei plugin |
| `DoseAppPluginBase.m` | interfaccia astratta che tutti i plugin devono derivare |

### Workflow

1. **Avvio app** → `DoseApp` scansiona `plugins/*.m`.  
2. Se la classe trovata eredita da `DoseAppPluginBase`, ne crea un’istanza.  
3. Aggiunge una voce nel menu **Plugins**:  
   ```matlab
   uimenu(app.MenuPlugins,'Text',obj.pluginName(), ...
          'MenuSelectedFcn',@(~,~)app.openPlugin(obj));
   ```
4. Alla selezione, `openPlugin` apre una nuova `uifigure` e invoca `obj.init(appHandle, parentFig)`.

### API essenziale

```matlab
classdef (Abstract) DoseAppPluginBase < handle
    methods (Abstract)
        name = pluginName(obj)                  % testo da mostrare nel menu
        init(obj, appHandle, parentContainer)   % costruisce la UI del plugin
    end
end
```

### Scheletro di un nuovo plugin

```matlab
classdef MyPlugin < DoseAppPluginBase
    properties (Access = private)
        App   % handle a DoseApp
    end

    function name = pluginName(~)
        name = "My-Plugin";
    end

    function init(obj, app, parent)
        obj.App = app;

        gl = uigridlayout(parent,[2 2]);
        uilabel(gl,"Text","Demo");

        uibutton(gl,"Text","Run", ...
            "ButtonPushedFcn",@(~,~)uialert(parent,"Done","My-Plugin"));
    end
end
```

---

## Esempio di plugin – **BiExpKineticsPlugin**
<a name="esempio-di-plugin-biexpkineticsplugin"></a>

Il plugin **BiExpKineticsPlugin** consente di stimare in pochi secondi i parametri di una cinetica bi-esponenziale a partire da **quattro misure di rateo** (µSv·h⁻¹) effettuate dopo la somministrazione del radiofarmaco.

### Obiettivo

Stimare:

\[
A(t)=A_{\text{tot}}\,[f_{1}e^{-\lambda_{1}t}+f_{2}e^{-\lambda_{2}t}],
\qquad
f_{1}+f_{2}=1
\]

ricavando le **frazioni** \((f_{1},f_{2})\) e le **costanti** di decadimento \((\lambda_{1},\lambda_{2})\) (in giorni⁻¹) tramite `lsqcurvefit`.

### Interfaccia rapida

| Campo | Descrizione |
|------|-------------|
| **Ora [h]** (×4) | tempo della misura (es. 0, 4, 24, 48 h) |
| **Rateo [µSv/h]** (×4) | valore corrispondente misurato a 1 m |
| **Stima cinetica** | avvia il fit non-lineare |
| **Risultati** | mostra \(f_{1},\lambda_{1},f_{2},\lambda_{2}\) in formato “DoseApp/JSON-ready” |

---

## Utilizzo della GUI

> Nota: le immagini sotto sono indicative. In alcune versioni la GUI può variare (es. editor scenari, modalità isolamento totale).

L’interfaccia di **DoseApp** è suddivisa in tre colonne:

| # | Pannello | Funzione principale |
|---|----------|--------------------|
| **①** | **Parametri clinici** | Inserisci nome paziente, \(T_{\text{discharge}}\), rateo di dimissione e radiofarmaco. Include i pulsanti **Calcola Dose**, **Grafico Dose**, **Genera PDF**. |
| **②** | **Scenari di esposizione** | Spunta uno o più scenari restrittivi (partner, bambino, colleghi, ecc.). Per **Colleghi** appare un menu a tendina per scegliere la distanza “Standard ≈ 1 m” o “Sempre ≥ 2 m”. |
| **③** | **Risultati** | Mostra, per ogni scenario selezionato, \(T_{\text{res}}\) (giorni) e dose cumulativa a 7 gg. In testa, un riepilogo con **T_max** e **T_medio**. |

### Passaggi rapidi

1. **Compila i parametri clinici**
   - Nome paziente
   - \(T_{\text{discharge}}\) (giorni)
   - Rateo \(R_{Tdis}\) (µSv/h)  
     - **I-131**: inserire il rateo a **2 m** (la GUI lo converte internamente a 1 m)
     - altri RF: inserire il rateo a **1 m**
   - Attività somministrata (MBq)
   - Seleziona il radiofarmaco dal menu a tendina

2. **Seleziona gli scenari**
   Spunta le caselle corrispondenti alle restrizioni da valutare.  
   È possibile selezionare più scenari contemporaneamente.

3. **Calcola o visualizza**
   - **Calcola Dose**: popola “Risultati” con \(T_{\text{res}}\), dose 7 gg e riepilogo (T_max / T_medio).
   - **Grafico Dose**: mostra la curva dose vs \(T_{\text{res}}\) per lo scenario selezionato.

4. **Genera il PDF**
   - Clicca **Genera PDF** → scegli dove salvare il file.
   - Il report include tabella riassuntiva e istruzioni discorsive per ogni scenario.

### Output “Risultati”: T_max e T_medio

Nel riquadro **Risultati**, oltre ai valori di \(T_{\text{res}}\) per ciascuno scenario, DoseApp riporta un riepilogo globale:

- **T_max**: il periodo di restrizione più lungo tra tutti gli scenari selezionati → valore clinicamente vincolante.
- **T_medio**: media aritmetica dei periodi di restrizione → indicatore sintetico del “carico restrittivo complessivo”.

Il riepilogo è mostrato sia:
- nel flusso standard multi-scenario,
- nella modalità **Isolamento totale**.

### Suggerimenti utili

| Esigenza | Operazione |
|----------|------------|
| Aggiornare parametri farmacocinetici | Modifica `radiopharmaceuticals.json`, poi riavvia l’app |
| Aggiungere un nuovo scenario | Aggiorna `getScenariosConfig()` e/o le factory `pairMap` / `pairMapOrd` in `DoseApp.m` |
| Cambiare altezza sorgente lineare | Modifica il costruttore `ModelloLineare(H)` in `DoseApp.m` |
| PDF non generato | Verifica licenza Report Generator:<br>`license('test','MATLAB_Report_Gen')` deve restituire `1` |

---

## Parametri clinici e farmacocinetica

La cinetica di eliminazione dei radiofarmaci è descritta in **DoseApp** da un modello bi-esponenziale:

\[
A(t)=A_{\text{tot}}
\Bigl[
f_{r_1}e^{-\lambda_{\text{eff,1}}t}
+f_{r_2}e^{-\lambda_{\text{eff,2}}t}
\Bigr],
\qquad
\sum_i f_{r_i}=1
\]

| Variabile | Significato | Unità |
|-----------|-------------|-------|
| \(f_{r_i}\) | frazione nel compartimento \(i\) | — |
| \(\lambda_{\text{eff},i}\) | decadimento **effettivo** (biologico + fisico) | d⁻¹ |
| \(A_{\text{tot}}\) | attività somministrata | MBq |

### 🔬 Dataset pre-caricato

I parametri sono memorizzati in `radiopharmaceuticals.json`:

```json
[
  {
    "name": "I-131 Carcinoma Tiroideo",
    "fr":         [0.70, 0.30],
    "lambda_eff": [2.16, 0.0866]
  },
  {
    "name": "I-131 Ipotiroidismo",
    "fr":         [0.20, 0.80],
    "lambda_eff": [0.693, 0.0866]
  },
  {
    "name": "Lu-177-DOTATATE",
    "fr":         [0.44, 0.56],
    "lambda_eff": [2.25, 0.175]
  },
  {
    "name": "Lu-177-PSMA",
    "fr":         [0.44, 0.56],
    "lambda_eff": [2.25, 0.175]
  }
]
```

### 🛠️ Come aggiornare `radiopharmaceuticals.json`

1. Apri il file con un editor (VS Code, Notepad++, ecc.).
2. Aggiungi/modifica un blocco:

```jsonc
{
  "name": "Nuovo-Radiofarmaco",
  "fr":         [f1, f2],        // due frazioni che sommano a 1
  "lambda_eff": [λ1, λ2]         // corrispondenti costanti (d⁻¹)
}
```

**Linee guida**
- Usa **punto decimale** (`0.175`, non `0,175`).
- Mantieni **esattamente 2** componenti in `fr` e `lambda_eff`.
- Controlla che `f1 + f2 = 1`.
- Metti la virgola `,` tra oggetti JSON (tranne dopo l’ultimo).

> Se la GUI non vede il nuovo radiofarmaco: verifica la sintassi e riavvia MATLAB (o esegui `clear all`).

---

## Scenari di esposizione

Gli scenari di esposizione implementati in **DoseApp** sono un adattamento operativo degli scenari clinici in letteratura (in particolare Buonamici/Banci Buonamici 2025), rivisitati con la pratica clinica del Centro.

Ogni scenario è rappresentato come oggetto `Scenario` con:
- `distanze` (m),
- `tempi` (ore/24h associate alle distanze),
- `DoseConstraint` (mSv) per l’esposto.

### 🔒 Fase restrittiva (esempi)

| Nome GUI | Distanza / Tempo (h·d⁻¹) | Vincolo (mSv) | Nota sintetica |
|----------|---------------------------|---------------|----------------|
| **Partner** | 1 m → 2 h | 3 | Letti separati, contatto ravvicinato ridotto |
| **Bambino <2 aa** | 1 m → 1.5 h · 2 m → 2 h | 1 | Contatto ravvicinato limitato |
| **Bambino 2–5** | 1 m → 1.5 h · 2 m → 1.5 h | 1 | Gioco vicino ma limitato |
| **Bambino 5–11** | 1 m → 2.5 h | 1 | Evita “abbracci lunghi” |
| **Donna incinta** | 1 m → 2 h | 1 | Evita contatto <1 m prolungato |
| **Colleghi lavoro** | (dipende) | (dipende) | Rientro al lavoro con distanza scelta (≈1 m o ≥2 m) |

> I valori esatti dipendono dalla configurazione locale (`getScenariosConfig()` / factory `pairMap`, `pairMapOrd`) e possono essere personalizzati con lo Scenario Editor.

### 👥 Fase ordinaria (post-restrizione)

Dopo \(T_{\text{res}}\) lo scenario ordinario rappresenta una giornata tipo con contatti più lunghi ma a distanze maggiori. È possibile scegliere, per il lavoro, **Standard (≈1 m)** o **Sempre ≥ 2 m**.

> Tutti i contatti oltre i 2 m sono tipicamente considerati trascurabili ai fini della dose.

---

## Modalità “Isolamento totale”

La modalità **Isolamento totale** calcola un unico tempo di isolamento “worst-case” assumendo:
- fase restrittiva con **contatti nulli** (tempi = 0) per i contatti domestici selezionati,
- fase ordinaria come rientro ai contatti ordinari dopo l’isolamento.

In questa modalità:
- vengono considerati gli scenari domestici selezionati,
- **Trasporto** è escluso dal calcolo del tempo di isolamento,
- il lavoro è gestito con una tendina dedicata `WorkReturnDropIso` (Non incluso / ≥1 m / ≥2 m),
- è applicato il **floor a 5 giorni** per ¹³¹I e ¹⁷⁷Lu.

Il riquadro Risultati mostra:
- elenco dei tempi richiesti per ciascun vincolo considerato,
- riepilogo con **T_max** e **T_medio**,
- una sezione informativa dedicata al trasporto (vedi sotto).

---

## Trasporto / viaggio

DoseApp gestisce il tema “trasporto” in modo dedicato:

- **Lu-177 (DOTATATE/PSMA)**: ore massime consigliate su mezzi pubblici (prime 48 h) tramite una tabella (AIFM-AIMN).
- **I-131**: stima ore massime via una formula con legge di distanza (esponente \(k\)) e limite di dose al pubblico (mSv), riportando tipicamente:
  - tempo max @0.3 m,
  - tempo max @1 m.

Nel flusso standard, lo scenario “Trasporto” compare come riga informativa con \(T_{\text{res}}\) indicato come “–” (poiché il vincolo è espresso in ore e finestre temporali brevi).

Nella modalità Isolamento totale, la sezione “Trasporto (indicativo)” è mostrata come promemoria.

---

## Personalizzazione scenari (Scenario Editor)

DoseApp include un editor per modificare **al volo** distanze/tempi (e, per la fase restrittiva, eventualmente il `DoseConstraint`) senza alterare il codice base.

- Seleziona lo scenario e la fase (Restrittivo / Ordinario).
- Premi **Personalizza…**
- Applica o rimuovi la personalizzazione.

Le personalizzazioni sono mantenute in memoria durante la sessione tramite `customOverrides`.

---

## Report PDF di istruzioni per il paziente

Il foglio di dimissione in formato **PDF** fornisce al paziente, in linguaggio semplice, le restrizioni post-terapia personalizzate calcolate da DoseApp.

### 📄 Contenuto del documento (tipico)

| Sezione | Descrizione |
|---------|-------------|
| Intestazione | Nome paziente, radiofarmaco, rateo alla dimissione, data |
| Tabella “Restrizioni raccomandate” | Elenco scenari selezionati con \(T_{\text{res}}\) e indicazioni pratiche |
| Istruzioni discorsive | Paragrafi per ogni scenario, con esempi pratici |
| Firma medico | Spazio per firma |

> Il layout è definito dalla classe `DReportBuilder` e può essere personalizzato via DOM API.

### 🖱️ Generazione

1. Compila nome paziente e parametri clinici.
2. Seleziona scenari (o isolamento totale).
3. Clicca **Genera PDF** → scegli percorso.
4. DoseApp crea e apre il file.

### ❓ Domande frequenti

- **Il PDF non si apre**: assicurati di avere un lettore PDF installato.
- **Errore license Report Generator**: verifica:
  ```matlab
  license('test','MATLAB_Report_Gen')
  ```
  deve restituire `1`.

---

## Note tecniche e modelli matematici utilizzati
<a name="note-tecniche-e-modelli-matematici-utilizzati"></a>

Questa sezione descrive – in forma sintetica – i modelli fisici e numerico-computazionali alla base di DoseApp.

### 1. Modello geometrico “line-source” assiale

| Simbolo | Valore predefinito | Significato |
|---------|-------------------|------------|
| \(H\) | 1.70 m | altezza sorgente lineare (paziente) |
| \(\Gamma\) | normalizzazione | tale che \(\dot D(1m)=1\,\mu Sv/h\) per \(A_{tot}=1\) |

\[
\dot D(d)=
\Gamma\,
\frac{A_{\text{tot}}}{H\,d}\;
\arctan\!\Bigl(\tfrac{H}{2d}\Bigr)
\]

\[
F_{\text{corr}}(d)=\frac{\dot D(d)}{\dot D(1\text{ m})}
\]

### 2. Modello farmacocinetico bi-esponenziale

\[
A(t)=A_{\text{tot}}\,
\Bigl[f_1e^{-\lambda_1 t}+f_2e^{-\lambda_2 t}\Bigr],
\quad
f_1+f_2=1
\]

Input da `radiopharmaceuticals.json` (λ in d⁻¹).

### 3. Integrazione dose su due fasi (schema)

Per ogni scenario si distinguono:

| Fase | Intervallo | Contatto | Dose parziale |
|------|------------|----------|---------------|
| Restrittiva | 0 → \(T_{res}\) | distanze/tempi “restr.” | \(D_{restr}(T)\) |
| Ordinaria | \(T_{res}\) → ∞ | distanze/tempi “ord.” | \(D_{ord}(T)\) |

Dose settimanale (in GUI) calcolata come dose cumulativa su 7 giorni, derivata dal rateo alla dimissione e dalla cinetica.

### 4. Calcolo ottimo di \(T_{\text{res}}\)

Si risolve:

\[
D_{\text{restr}}(T)+D_{\text{ord}}(T)=\text{DoseConstraint}
\]

con **bisezione** su un intervallo finito (tipicamente 0.1–60 giorni) fino a tolleranza desiderata.

### 5. Precisione numerica

| Quantità | Note |
|----------|------|
| Integrazione dose | analitica (errore macchina) |
| Bisezione \(T_{res}\) | tipicamente ≤ 0.01 d |
| Vincolo \(f_1+f_2\) | controllato |

---

## Riferimenti e contatti
<a name="riferimenti-e-contatti"></a>

## Riferimenti fondativi

| ID | Citazione |
|----|-----------|
| **[BB25]** | Banci Buonamici *et al.* “Discharge optimisation after radionuclide therapy: a personalised dosimetric approach.” **J Radiol Prot** 43 (2025) 021504. |

> Il lavoro **[BB25]** costituisce il riferimento metodologico principale per l’impostazione concettuale di DoseApp, in particolare per: separazione fase restrittiva/ordinaria, scenari realistici e approccio personalizzato basato sul rateo misurato alla dimissione.

## Bibliografia — dati farmacocinetici

| ID | Riferimento (DOI) | Radiofarmaco / Parametri estratti |
|---|-------------------|------------------------------------|
| **[H1]** | Hänscheid, H. *et al.* “Time–activity curves after therapeutic administration of **¹³¹I** in differentiated thyroid cancer patients.” *J Nucl Med* 47 (2006) 1481-1487. **doi:10.2967/jnumed.106.033860** | I-131 carcinoma tiroideo – \(f_r\), \(\lambda_{eff}\) |
| **[B1]** | Broggio, D. *et al.* “Discharge criteria after **¹³¹I** therapy: a dosimetric approach.” *Radiat Prot Dosimetry* 187 (2019) 135-142. **doi:10.1093/rpd/ncy236** | I-131 (iper/ipotiroidismo) – \(f_r\), \(\lambda_{eff}\) |
| **[G1]** | Garske, U. *et al.* “Individualised dosimetry for patients receiving therapy with **¹⁷⁷Lu-DOTATATE**.” *Eur J Nucl Med Mol Imaging* 39 (2012) 1688-1696. **doi:10.1007/s00259-012-2182-3** | Lu-177-DOTATATE – \(f_r\), \(\lambda_{eff}\) |
| **[V1]** | Violet, J. *et al.* “Prospective study of **¹⁷⁷Lu-PSMA-617** theranostics in men with metastatic prostate cancer.” *Lancet Oncol* 21 (2020) 140-152. **doi:10.1016/S1470-2045(19)30684-5** | Lu-177-PSMA – \(f_r\), \(\lambda_{eff}\) |

> I valori nel file `radiopharmaceuticals.json` sono stati digitalizzati o dedotti dalle curve tempo-attività presentate nei lavori sopra elencati.

## Contatti

Per domande / segnalazioni:

| Nome | Ruolo / Struttura | Email |
|------|-------------------|-------|
| Federica Fioroni | Fisica Sanitaria – AUSL Reggio Emilia | federica.fioroni@ausl.re.it |
| Nicola Panico   | Fisica Sanitaria – AUSL Reggio Emilia | nicola.panico@ausl.re.it |
| Elisa Grassi    | Fisica Sanitaria – AUSL Reggio Emilia | elisa.grassi@ausl.re.it |
