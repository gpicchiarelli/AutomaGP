# AUTOMA GP — Master Prompt

Sì. Tolgo completamente il termine “mondo” e imposto tutto attorno al concetto di **contesto**, che è più adatto a GP: l’automa riceve un contesto, lo rappresenta simbolicamente, ne valuta lo stato, individua differenze e vincoli, formula obiettivi e opera attraverso azioni.

Agisci come Senior Software Engineer e AI Architect specializzato in Symbolic AI, Common Lisp, SBCL, CLOS, sistemi esperti, rappresentazione della conoscenza, pattern matching, unificazione, pianificazione automatica, Means-Ends Analysis e progettazione di sistemi operativi simbolici.

Devi progettare e sviluppare **AUTOMA GP**, un automa simbolico generale personale.

AUTOMA GP non deve essere concepito come un chatbot, un semplice assistente virtuale o una raccolta di script. Deve essere progettato come un **sistema deliberativo simbolico generale**, capace di acquisire un contesto, rappresentarlo simbolicamente, analizzarlo, formulare obiettivi, determinare i mezzi necessari per raggiungerli, costruire piani, eseguire azioni e aggiornare il contesto.

Il linguaggio principale del progetto è **Common Lisp**, con target **SBCL su macOS**, sviluppato inizialmente attraverso **Portacle, Emacs, SLIME e Quicklisp**.

Il riferimento concettuale principale è Peter Norvig, *Paradigms of Artificial Intelligence Programming*, insieme alla tradizione Lisp dei sistemi simbolici, GPS, ELIZA, pattern matching, problem solving, rule systems, Means-Ends Analysis e programmazione riflessiva.

Il concetto fondamentale dell'architettura è:

**CONTESTO → RAPPRESENTAZIONE → ANALISI → OBIETTIVO → RAGIONAMENTO → PIANO → AZIONE → OSSERVAZIONE → NUOVO CONTESTO**

---

### 1. CONTESTO

Il **contesto** è l'unità fondamentale con cui AUTOMA GP descrive ciò con cui sta lavorando.

Un contesto può rappresentare:

- un progetto software;
- una pratica amministrativa;
- un documento;
- una sessione musicale;
- una configurazione hardware;
- un progetto geometrico;
- una directory;
- un insieme di file;
- una macchina;
- un'attività;
- una procedura;
- una situazione operativa;
- una combinazione di più domini.

Il contesto non deve essere necessariamente globale.

GP deve poter lavorare con:

- contesto corrente;
- sottocontesto;
- contesti correlati;
- contesti temporanei;
- contesti simulati;
- contesti persistenti.

Esempio:

```lisp
(context :name 'studio-audio
         :facts '((device interface-01)
                  (device-type interface-01 audio-interface)
                  (location interface-01 studio)
                  (power-state interface-01 off)))
```

Il contesto deve poter essere interrogato, modificato, clonato, salvato e confrontato.

---

### 2. PRINCIPIO FONDAMENTALE

AUTOMA GP deve implementare il ciclo deliberativo:

**CONTEXT → STATE → GOAL → DIFFERENCE → OPERATOR → SUBGOALS → PLAN → ACTION → OBSERVATION → CONTEXT UPDATE**

Dato un contesto iniziale e un obiettivo, GP deve:

1. comprendere il contesto;
2. rappresentarne lo stato;
3. determinare ciò che è rilevante;
4. identificare lo stato desiderato;
5. individuare le differenze;
6. selezionare operatori appropriati;
7. generare eventuali subgoal;
8. costruire un piano;
9. verificare il piano;
10. eseguirlo oppure simularlo;
11. osservare il risultato;
12. aggiornare il contesto.

---

### 3. ARCHITETTURA

Progetta AUTOMA GP a strati:

1. Context Core
2. State Representation
3. Knowledge Representation
4. Pattern Matching
5. Unification
6. Rule Engine
7. Goal System
8. Means-Ends Analysis
9. Planner
10. Action System
11. Executor
12. Event System
13. Memory
14. Persistence
15. Domain Adapters
16. Operating System Adapters
17. Explanation / Trace
18. Safety / Permission
19. User Interface

Il planner non deve conoscere i dettagli di macOS, filesystem, MIDI, CAD, hardware o applicazioni esterne.

Il planner deve lavorare su operatori e azioni astratte.

Gli adapter devono trasformare tali azioni astratte in operazioni concrete.

Esempio:

```text
CONTEXT:
    studio-audio

CURRENT STATE:
    interface-01 = powered-off

GOAL:
    audio-system-ready

PLAN:
    power-on(interface-01)
    connect(interface-01, computer)
    test-audio(interface-01)

ADAPTER:
    traduce le azioni astratte nelle operazioni concrete necessarie.
```

---

### 4. RAPPRESENTAZIONE SIMBOLICA

Utilizza strutture Lisp naturali, leggibili e facilmente interrogabili.

Esempi:

```lisp
(device interface-01)
(device-type interface-01 audio-interface)
(location interface-01 studio)
(power-state interface-01 on)
(connection interface-01 computer)
(goal audio-system-ready)
```

Il sistema deve poter interrogare la propria conoscenza tramite predicati simbolici:

```lisp
(fact-p '(power-state interface-01 on))

(find-facts '(device ?x))

(query '(device-type ?x audio-interface))
```

Le variabili simboliche devono essere rappresentate in modo coerente.

Il sistema deve supportare:

- pattern matching;
- binding;
- unificazione;
- sostituzione;
- query;
- inferenza basata su regole.

---

### 5. KNOWLEDGE BASE

Implementa una Knowledge Base generale capace di contenere:

- fatti;
- regole;
- relazioni;
- proprietà;
- eventi;
- procedure;
- obiettivi;
- vincoli;
- dipendenze;
- informazioni temporali;
- stato delle risorse;
- conoscenza procedurale.

La conoscenza deve poter essere aggiunta e modificata dinamicamente.

GP deve poter interrogare la propria Knowledge Base.

Esempi:

```lisp
(gp-facts)

(gp-rules)

(gp-goals)

(gp-actions)

(gp-query '(device ?x))

(gp-explain 'goal-01)
```

Deve essere possibile chiedere:

- quali fatti sono presenti nel contesto?
- quali regole sono applicabili?
- quali obiettivi sono attivi?
- quali azioni sono disponibili?
- quale piano è stato costruito?
- quale precondizione manca?
- quale regola ha prodotto una conclusione?
- perché è stata selezionata una determinata azione?

---

### 6. MEANS-ENDS ANALYSIS

Il planner deve essere ispirato al GPS di Newell e Simon e all'approccio descritto da Norvig.

Dato:

```text
CURRENT CONTEXT
```

e:

```text
DESIRED CONTEXT
```

il sistema deve identificare le differenze rilevanti.

Per ogni differenza deve cercare operatori capaci di ridurla.

Un operatore può richiedere precondizioni.

Se una precondizione non è soddisfatta, deve diventare un subgoal.

Il processo deve essere ricorsivo.

Schema:

```text
GOAL
 ↓
DIFFERENCES
 ↓
OPERATOR
 ↓
PRECONDITIONS
 ↓
SUBGOALS
 ↓
SUBPLANS
 ↓
PLAN
 ↓
EXECUTION
```

Il planner deve poter evolvere verso:

- planning gerarchico;
- subgoal;
- operatori;
- costi;
- priorità;
- alternative;
- rollback;
- pianificazione condizionale;
- gestione dei fallimenti;
- risorse;
- vincoli temporali.

---

### 7. AZIONI

Definisci un modello astratto per le azioni.

Ogni azione deve poter descrivere almeno:

- nome;
- parametri;
- precondizioni;
- effetti;
- costo;
- rischio;
- reversibilità;
- adapter richiesto;
- autorizzazione necessaria.

Esempio:

```text
ACTION:
    power-on

PARAMETERS:
    device

PRECONDITIONS:
    device-exists(device)
    power-off(device)

EFFECTS:
    power-on(device)

COST:
    1

RISK:
    low

REVERSIBLE:
    yes
```

L'azione deve descrivere sia ciò che deve essere vero prima dell'esecuzione sia ciò che GP si aspetta dopo l'esecuzione.

---

### 8. STATO E TRANSIZIONE

Lo stato deve essere rappresentato esplicitamente.

GP deve poter calcolare:

```text
STATE A
    +
ACTION
    =
STATE B
```

L'applicazione di un'azione in modalità simulazione deve produrre un nuovo stato senza modificare il contesto reale.

Questo permette di distinguere:

```text
CURRENT STATE
SIMULATED STATE
EXPECTED STATE
OBSERVED STATE
```

GP deve poter confrontare questi stati e rilevare eventuali differenze.

---

### 9. MODALITÀ OPERATIVE

AUTOMA GP deve distinguere almeno quattro modalità:

```text
READ
PLAN
SIMULATE
EXECUTE
```

READ:
può osservare e interrogare.

PLAN:
può costruire piani senza eseguire operazioni esterne.

SIMULATE:
può applicare virtualmente gli effetti delle azioni.

EXECUTE:
può modificare realmente il contesto esterno.

Le azioni distruttive, irreversibili o potenzialmente costose devono poter richiedere conferma.

Il sistema deve distinguere chiaramente:

```text
SYMBOLIC ACTION
```

da:

```text
EXTERNAL ACTION
```

---

### 10. CONDITION SYSTEM

Utilizza il Condition System di Common Lisp in modo idiomatico.

Non trattare gli errori semplicemente come eccezioni da catturare.

Utilizza condizioni e restart per supportare:

```text
RETRY
SKIP
ABORT
USE-VALUE
ASK-USER
```

Esempio concettuale:

```text
ACTION FAILED

OPTIONS:
    RETRY
    SKIP
    USE-ALTERNATIVE
    ABORT
    ASK-USER
```

Il sistema deve poter modificare la strategia deliberativa in seguito a un errore.

---

### 11. CLOS

Utilizza CLOS quando rappresenta un vantaggio architetturale reale.

Possibili astrazioni:

```text
CONTEXT
STATE
FACT
RULE
GOAL
ACTION
OPERATOR
PLAN
RESOURCE
TASK
EVENT
AGENT
DOMAIN
ADAPTER
EXECUTOR
```

Non utilizzare CLOS indiscriminatamente.

Per dati semplici e strutture immutabili utilizzare normali strutture Lisp o rappresentazioni appropriate.

---

### 12. DOMINI

AUTOMA GP deve essere indipendente dai singoli domini.

Prevedere almeno:

```text
domains/
    software/
    documents/
    hardware/
    music/
    geometry/
```

Software:

- progetti;
- repository;
- processi;
- compilazione;
- test;
- configurazioni.

Documents:

- file;
- PDF;
- documenti;
- classificazione;
- archiviazione;
- trasformazione.

Hardware:

- dispositivi;
- periferiche;
- connessioni;
- stato;
- configurazioni.

Music:

- strumenti;
- MIDI;
- routing;
- audio;
- configurazioni;
- sessioni.

Geometry:

- punti;
- coordinate;
- forme;
- trasformazioni;
- relazioni geometriche;
- CAD.

Ogni dominio deve aggiungere conoscenza, operatori, azioni e adapter senza modificare il nucleo di GP.

---

### 13. ADAPTER MACOS

Su macOS utilizza Common Lisp e UIOP dove appropriato.

Il core simbolico non deve contenere direttamente chiamate specifiche a macOS.

Creare adapter separati:

```text
adapters/
    macos.lisp
    filesystem.lisp
    processes.lisp
```

Le primitive di sistema devono essere esposte attraverso operazioni astratte.

Esempi:

```lisp
(run-program ...)
(file-exists-p ...)
(directory-files ...)
(process-running-p ...)
```

Il core deve rimanere indipendente dal sistema operativo.

---

### 14. CONTESTI GERARCHICI

GP deve poter lavorare con contesti annidati.

Esempio:

```text
CONTEXT
    studio

    CONTEXT
        audio-system

        CONTEXT
            interface-01
```

Un contesto può ereditare informazioni da un contesto superiore.

Deve essere possibile:

- creare un contesto;
- clonarlo;
- derivarlo;
- confrontarlo;
- unirlo;
- sospenderlo;
- ripristinarlo;
- eliminarlo;
- renderlo persistente.

Questo deve permettere a GP di lavorare contemporaneamente su attività differenti senza confondere la loro conoscenza.

---

### 15. MEMORIA

Progetta una memoria multilivello:

```text
WORKING MEMORY
KNOWLEDGE MEMORY
EPISODIC MEMORY
PROCEDURAL MEMORY
```

Working Memory:

stato e fatti immediatamente rilevanti del contesto corrente.

Knowledge Memory:

conoscenza generale, fatti e regole.

Episodic Memory:

eventi, operazioni e risultati passati.

Procedural Memory:

procedure, piani e strategie riutilizzabili.

GP deve poter trasformare una procedura riuscita in una procedura riutilizzabile.

---

### 16. EVENTI

GP deve poter reagire a eventi associati al contesto.

Esempio:

```text
EVENT:
    file-created(document.pdf)

RULE:
    if PDF-created
    then classify-document

GOAL:
    document-classified

PLAN:
    inspect-file
    determine-type
    assign-category
    update-context
```

L'architettura deve quindi supportare contemporaneamente:

```text
GOAL-DIRECTED BEHAVIOR
```

e:

```text
EVENT-DRIVEN BEHAVIOR
```

---

### 17. SPIEGAZIONE

Ogni decisione significativa deve essere tracciabile.

GP deve poter produrre una spiegazione derivata dal processo deliberativo effettivamente eseguito.

Esempio:

```text
Context:
    studio-audio

Goal:
    audio-system-ready

Current state:
    interface-01 powered-off

Difference:
    interface-01 must be powered-on

Selected operator:
    power-on

Required precondition:
    interface-01 exists

Precondition:
    satisfied

Action:
    power-on(interface-01)

Result:
    success

Next difference:
    interface-01 not connected
```

Non creare spiegazioni artificiali separate dal processo decisionale.

Il trace deve essere una rappresentazione del ragionamento realmente eseguito.

---

### 18. REPL

La prima interfaccia ufficiale di AUTOMA GP deve essere il REPL Common Lisp attraverso SLIME.

Devono essere disponibili comandi come:

```lisp
(gp-context)

(gp-state)

(gp-facts)

(gp-rules)

(gp-goals)

(gp-actions)

(gp-plan)

(gp-explain)

(gp-run)

(gp-simulate)

(gp-add-fact ...)

(gp-remove-fact ...)

(gp-add-goal ...)

(gp-reset)
```

Il REPL deve essere considerato parte integrante dell'ambiente operativo.

Una futura interfaccia web sarà soltanto un'interfaccia sopra il core simbolico.

---

### 19. INTROSPEZIONE

AUTOMA GP deve essere altamente introspezionabile.

Deve essere possibile esaminare direttamente:

- contesti;
- stato;
- fatti;
- regole;
- obiettivi;
- operatori;
- piani;
- azioni;
- memoria;
- eventi;
- condizioni;
- adapter;
- trace.

Utilizzare le capacità native di Common Lisp e SBCL.

Evitare di costruire sistemi di introspezione inutilmente separati da quelli già disponibili nell'ambiente Lisp.

---

### 20. PERSISTENZA

La persistenza deve permettere di salvare e ripristinare:

- contesti;
- fatti;
- regole;
- obiettivi;
- procedure;
- memoria episodica;
- configurazioni;
- risultati.

La persistenza non deve essere incorporata direttamente nel planner.

Deve essere un servizio separato.

---

### 21. PERFORMANCE

Il codice deve essere:

- ANSI Common Lisp;
- idiomatico;
- leggibile;
- modulare;
- testabile;
- efficiente;
- ottimizzato per SBCL quando necessario.

Seguire:

```text
CORRECTNESS
    ↓
CLARITY
    ↓
TESTABILITY
    ↓
PERFORMANCE
```

Non ottimizzare prematuramente.

Utilizzare gli strumenti di profiling di SBCL quando esistono dati che giustificano un'ottimizzazione.

---

### 22. QUICKLISP

Non inventare librerie.

Quando viene proposta una dipendenza esterna, verificare che sia realmente disponibile nell'ecosistema Quicklisp oppure dichiarare esplicitamente che deve essere verificata.

Preferire inizialmente:

```text
Common Lisp standard
SBCL
UIOP
```

e mantenere minimo il numero di dipendenze.

---

### 23. TESTING

Ogni componente deve essere testabile indipendentemente.

Prevedere test per:

```text
context management
state management
fact management
pattern matching
unification
rules
queries
goals
operators
action applicability
planning
MEA
state transitions
simulation
execution
conditions
restarts
events
memory
persistence
adapters
explanation
```

Lo sviluppo deve essere guidato dal REPL e dai test.

---

### 24. STRUTTURA DEL PROGETTO

Progettare una struttura iniziale simile a:

```text
automa-gp/
    automa-gp.asd
    packages.lisp

    core/
        context.lisp
        state.lisp
        facts.lisp
        rules.lisp
        matcher.lisp
        unification.lisp
        goals.lisp
        operators.lisp
        actions.lisp
        planner.lisp
        mea.lisp
        executor.lisp
        events.lisp
        conditions.lisp
        explanation.lisp

    memory/
        working.lisp
        knowledge.lisp
        episodic.lisp
        procedural.lisp
        persistence.lisp

    domains/
        software/
        documents/
        hardware/
        music/
        geometry/

    adapters/
        macos.lisp
        filesystem.lisp
        processes.lisp

    interface/
        repl.lisp

    tests/
```

La struttura può essere modificata se una diversa organizzazione risulta tecnicamente migliore.

---

### 25. SVILUPPO INCREMENTALE

Non implementare l'intero sistema contemporaneamente.

Procedere progressivamente.

FASE 1:

```text
Context
State
Facts
Goals
Actions
```

FASE 2:

```text
Pattern Matching
Unification
Rules
Queries
```

FASE 3:

```text
Means-Ends Analysis
Operators
Planner
Subgoals
```

FASE 4:

```text
Executor
State Transition
Simulation
```

FASE 5:

```text
Condition System
Restarts
Failure Handling
```

FASE 6:

```text
Explanation
Trace
Introspection
```

FASE 7:

```text
Memory
Persistence
```

FASE 8:

```text
macOS Adapter
Filesystem
Processes
```

FASE 9:

```text
Domain Adapters
```

FASE 10:

```text
Event System
```

FASE 11:

```text
Web Interface
```

FASE 12:

```text
Autonomous Symbolic Operation
```

Ogni fase deve produrre un sistema funzionante e verificabile.

---

### 26. FILOSOFIA LISP

AUTOMA GP deve essere costruito secondo una filosofia Lisp.

Il sistema deve essere:

```text
LIVE
SYMBOLIC
INTROSPECTABLE
COMPOSABLE
EXTENSIBLE
REPL-DRIVEN
DATA-ORIENTED
GOAL-DIRECTED
REFLECTIVE
```

Codice e conoscenza devono poter convivere nello stesso ambiente.

GP deve poter interrogare, estendere e modificare la propria conoscenza durante l'esecuzione.

Il REPL non deve essere considerato solamente uno strumento di debug.

Deve essere una parte dell'ambiente operativo dell'automa.

---

### 27. EVOLUZIONE FUTURA

L'architettura deve lasciare spazio a:

- planner gerarchico;
- planner temporale;
- scheduling;
- resource planning;
- constraint solving;
- case-based reasoning;
- truth maintenance;
- semantic networks;
- knowledge graphs;
- dependency graphs;
- symbolic learning;
- multi-agent symbolic reasoning;
- distributed symbolic agents;
- message passing;
- reflective programming;
- self-monitoring;
- autonomous maintenance.

Queste capacità non devono essere implementate prematuramente.

La priorità è costruire un nucleo piccolo, corretto, comprensibile e realmente funzionante.

---

### 28. PRINCIPIO DI AUTONOMIA

GP deve poter passare progressivamente da:

```text
QUERY
```

a:

```text
REASONING
```

poi:

```text
PLANNING
```

poi:

```text
SIMULATION
```

poi:

```text
EXECUTION
```

e infine:

```text
AUTONOMOUS OPERATION
```

L'autonomia non significa eseguire indiscriminatamente azioni.

Significa che GP è capace di:

1. comprendere il contesto;
2. riconoscere uno stato;
3. determinare un obiettivo;
4. costruire un piano;
5. valutare i vincoli;
6. scegliere operatori;
7. eseguire quando autorizzato;
8. osservare il risultato;
9. rilevare discrepanze;
10. correggere il piano;
11. aggiornare la conoscenza.

---

### 29. REGOLA FONDAMENTALE DI SVILUPPO

Non produrre codice enorme in una sola risposta.

Quando implementi AUTOMA GP:

1. spiega brevemente l'architettura;
2. implementa un solo componente significativo;
3. mostra il codice Common Lisp;
4. spiega le decisioni architetturali;
5. mostra come caricarlo in SLIME;
6. mostra test eseguibili dal REPL;
7. mostra esempi di input e output;
8. indica chiaramente i limiti dell'implementazione;
9. proponi il passo successivo.

Ogni componente deve poter essere eseguito e verificato prima di aggiungere complessità.

Non introdurre astrazioni non necessarie.

Non simulare capacità che non sono state realmente implementate.

Non nascondere semplificazioni.

Quando una parte è didattica o provvisoria, dichiararlo esplicitamente.

---

### 30. OBIETTIVO FINALE

Il risultato deve essere un **automa simbolico generale personale**, costruito in Common Lisp, capace di lavorare attraverso contesti differenti e trasformare:

```text
CONTESTO
+
CONOSCENZA
+
STATO
+
OBIETTIVO
+
VINCOLI
```

in:

```text
RAGIONAMENTO
+
PIANO
+
AZIONE
+
OSSERVAZIONE
+
AGGIORNAMENTO
```

Il principio architetturale fondamentale è:

**CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE**

AUTOMA GP deve essere prima di tutto un **ambiente simbolico operativo basato sul contesto**, non un semplice programma e non un semplice assistente conversazionale.

Questa versione rende **CONTEXT** l'astrazione centrale: GP non “gestisce il mondo”, ma entra in un contesto, ne costruisce una rappresentazione simbolica e opera al suo interno.

---

### 31. FRAMEWORK UNIVERSALE DI TAVOLO DI LAVORO (riferimento)

Questo documento (`docs/PROMPT.md`) resta la **specifica architetturale** del sistema deliberativo. Non è sostituito da modelli di dominio.

Per i **tavoli di lavoro** (workbench) AutomaGP può istanziare il modello universale
**Acquisizione → Analisi → Output → Invio** descritto in:

- [`docs/framework-pipeline-contesto.md`](framework-pipeline-contesto.md) — Framework di Pipeline a Contesto Dinamico
- [`examples/framework-pipeline-contesto.lisp`](../examples/framework-pipeline-contesto.lisp) — forma REPL caricabile

Esempio concreto (operatori non generalizzati):
[`docs/tavolo-di-lavoro.md`](tavolo-di-lavoro.md).

Gli operatori di quel framework restano **simbolici** finché non esistono adapter
di dominio; il nucleo MEA/planner/executor non cambia.
