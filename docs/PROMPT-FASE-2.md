# AUTOMA GP — Prompt di Fase 2: conoscenza, verità, apprendimento, riproduzione

Questo prompt continua `docs/PROMPT.md`. Non lo sostituisce. Tutto ciò che
lì è vincolante resta vincolante: contesto come unità fondamentale, Common
Lisp ANSI su SBCL, nessun chatbot, REPL come superficie primaria, policy a
tre autorità prima di qualunque effetto reale, sviluppo incrementale con
sistema caricabile e testato a ogni passo.

---

## 0. RUOLO E PRIMO PASSO

Agisci come Senior Software Engineer e AI Architect specializzato in IA
simbolica, Common Lisp, CLOS, rappresentazione della conoscenza (RDF,
knowledge graph, Wikidata), truth maintenance, logiche a più valori,
pianificazione gerarchica, programmazione a vincoli, apprendimento di operatori, grammatiche a
unificazione e linguaggi naturali controllati.

Prima di scrivere una riga:

1. Leggi `docs/PROMPT.md`, `ROADMAP.md`, `docs/architecture.md`.
2. Leggi per intero `core/facts.lisp`, `core/context.lisp`,
   `core/matcher.lisp`, `core/operators.lisp`, `core/mea.lisp`,
   `core/planner.lisp`, `core/executor.lisp`, `core/induction.lisp`,
   `memory/knowledge.lisp`, `memory/procedural.lisp`,
   `memory/persistence.lisp`, `interface/json.lisp`, `interface/ask.lisp`,
   `interface/narration.lisp`.
3. Lancia `./scripts/run-tests.sh` e riporta il numero di check. Da qui in
   avanti quel numero può solo crescere.
4. Scrivi in `docs/architecture.md` una sezione "Fase 2" con il piano che
   segue, adattato a ciò che hai trovato nel codice. Poi inizia.

---

## 1. OBIETTIVO FINALE DELLA FASE 2

AUTOMA GP diventa il sistema con cui una sola persona conserva la propria
conoscenza professionale, ne distingue il vero dal falso dal non-saputo,
la fa crescere osservando ciò che fa, e la usa per riprodurre risultati
già ottenuti su situazioni nuove.

"Conoscenza professionale" significa tre cose distinte, e il sistema le
tratta separatamente:

- **Sapere che**: affermazioni sul proprio lavoro, con provenienza, data
  e valore di verità esplicito.
- **Sapere come**: procedure che hanno prodotto un risultato, come
  decomposizioni gerarchiche e non come sequenze piatte.
- **Sapere quando**: vincoli che una soluzione deve rispettare perché sia
  accettabile in quel dominio.

"Riprodurre un risultato" significa: dato un contesto nuovo e un risultato
già ottenuto altrove, trovare la procedura che lo produsse, verificare che
le sue condizioni valgano ancora o possano essere ripristinate, adattarla
dove il contesto differisce, eseguirla sotto policy, e spiegare ogni scarto
rispetto all'originale.

Il sistema resta simbolico. Nessun modello statistico, nessuna rete
neurale. L'unica sorgente esterna ammessa è Wikidata, in sola lettura,
sotto policy, come riferimento pubblico con cui confrontare la conoscenza
privata (§2.5). Ogni cosa che il sistema sa, la sa perché qualcuno l'ha
osservata, asserita, dedotta da regole leggibili, o letta da una fonte
pubblica con citazione.

---

## 2. LE CAPACITÀ DA INNESTARE

Ordine obbligatorio. Ognuna è una fase con versione minore propria, test
propri, e una sezione in `CHANGELOG.md`. Non si passa alla successiva se
la precedente non è caricabile, testata e documentata.

### Fase 2.0 — Rappresentazione a triple con affermazioni (statement)

Il formato dei fatti cambia. Oggi un fatto è una lista ad arità libera:
`(device interface-01)`, `(power-state interface-01 off)`. Da ora la forma
canonica è la **tripla** soggetto–predicato–oggetto, e ogni tripla vive
dentro una **affermazione** che porta il resto.

Modello di riferimento: RDF 1.2 per la tripla e per le triple citate
(RDF-star), il modello delle dichiarazioni di Wikidata per qualificatori,
riferimenti e rango, PROV-O per la provenienza. Non implementare RDF per
intero. Implementa questo sottoinsieme, in CLOS:

```lisp
(defclass statement ()
  ((id)                 ; simbolo o intero, stabile nel tempo
   (subject)            ; simbolo (entità locale) o riferimento esterno
   (predicate)          ; simbolo con namespace locale, es. gp:cliente-di
   (object)             ; simbolo, numero, stringa, data, riferimento esterno
   (qualifiers)         ; alist: (gp:dal . 2024-01-10) (gp:unità . ore) ...
   (references)         ; lista di provenienze (§2.1)
   (rank)               ; :preferred :normal :deprecated
   (truth)))            ; (§2.1)
```

Regole:

- `(device interface-01)` diventa `(interface-01 rdf:type device)`.
  `(power-state interface-01 off)` diventa
  `(interface-01 gp:power-state off)`. Scrivi un normalizzatore: la vecchia
  forma resta accettata in `gp-add-fact` e nei domini esistenti, viene
  convertita all'ingresso, e i test esistenti passano senza modifica.
- Relazioni n-arie non si appiattiscono: la tripla porta il nucleo e i
  qualificatori portano il resto. "Ho fatturato 12 ore ad ACME il 10
  gennaio" è `(io gp:ha-fatturato acme)` con qualificatori
  `(gp:quantità . 12) (gp:unità . ore) (gp:data . 2024-01-10)`.
- Le entità hanno un identificatore locale stabile e un'etichetta
  leggibile separata. Le etichette non sono identificatori.
- Il vocabolario dei predicati è dell'utente, in namespace `gp:`. Un
  predicato può dichiarare dominio, codominio, se è funzionale (un solo
  valore per soggetto: sostituisce `retract-slot-conflicts`) e se è
  **chiuso** (§2.1).
- Il matcher e l'unificazione lavorano sulle triple come oggi lavorano
  sulle liste. Un pattern `(?d gp:power-state off)` unifica come prima.
- Esporta e importa in N-Triples e Turtle (`gp-export :turtle`,
  `gp-import`) per interoperabilità. La persistenza primaria resta `.agp`.

### Fase 2.1 — Verità, provenienza e Truth Maintenance

Ogni affermazione porta:

**Provenienza** (riferimenti, uno o più), con tipo, agente e istante:

- `:asserted` — l'utente l'ha detta.
- `:observed` — un adapter l'ha letta (quale, da cosa).
- `:derived` — una regola l'ha dedotta (quale regola, da quali affermazioni).
- `:effect` — un operatore eseguito l'ha prodotta (quale, in quale piano).
- `:external` — una fonte pubblica la sostiene (Wikidata: QID, PID, rango
  della dichiarazione, riferimenti citati lì, data di lettura).

**Valore di verità** su quattro valori alla Belnap:

- `:true` — evidenza a favore, nessuna contro.
- `:false` — evidenza contro, nessuna a favore. Il falso è esplicito: si
  può asserire che qualcosa non vale (`:value :false`), non si deduce
  dall'assenza.
- `:unknown` — nessuna evidenza. È il valore di default di ciò che non è
  stato detto. Il mondo è aperto: assenza non è negazione.
- `:both` — evidenza a favore e contro da fonti diverse. È uno stato
  legittimo e visibile, non un errore da nascondere.

Un predicato dichiarato **chiuso** (`:closed t`) fa eccezione: per esso
l'assenza vale `:false`. Serve per ciò che l'utente controlla per intero,
come "le mie fatture del 2024".

**Truth Maintenance** (JTMS alla Doyle, esteso ai quattro valori). Il
valore di verità di un'affermazione è calcolato dalle sue giustificazioni,
non memorizzato a mano. Quando una provenienza cade, tutto ciò che
dipendeva da essa viene ricalcolato, ricorsivamente. Un `:both` non si
risolve in silenzio: è una condizione con restart:

- `prefer-source` — fidati di una provenienza indicata (es. l'osservazione
  sul precedente asserito, o l'asserito sull'esterno).
- `prefer-newer` / `prefer-older`.
- `keep-disputed` — lascia `:both`, escludi l'affermazione dalla
  pianificazione, segna il contesto come disputato.

Pesi di default tra fonti, sovrascrivibili per predicato: osservazione
sull'asserito, asserito sull'esterno per ciò che è privato, esterno
sull'asserito per ciò che è pubblico e datato (§2.5).

Superficie REPL minima:

```lisp
(gp-assert '(acme rdf:type gp:cliente) :by :asserted)
(gp-assert '(acme gp:sede milano) :by '(:external :wikidata "Q…"))
(gp-assert '(acme gp:attivo t) :value :false :by :asserted)   ; falso esplicito
(gp-truth '(acme gp:attivo t))          ; :false + evidenze pro e contro
(gp-why '(acme gp:sede milano))         ; catena di giustificazioni
(gp-retract-source :asserted '(acme gp:sede milano))
(gp-beliefs :truth :both)               ; cosa è in disputa e perché
```

Vincoli:

- La MEA pianifica solo su affermazioni `:true` con rango non
  `:deprecated`. `:unknown` e `:both` non esistono per lei, ma
  `gp-explain` sa dire "non ho usato X perché è in disputa".
- `gp-explain` estende la traccia: perché ha scelto un operatore e perché
  credeva alle affermazioni che l'hanno abilitato, fino alle provenienze.
- La persistenza `.agp` salva provenienze e valori. Un archivio vecchio si
  carica come `:asserted` con data del file.
- Gli adapter, quando abilitati, producono affermazioni `:observed` e sono
  l'unica fonte che può contraddire un `:asserted` senza chiedere.

### Fase 2.2 — Hierarchical Task Networks (metodi al posto di sequenze)

Introduci il concetto di **compito** distinto da operatore. Un operatore è
primitivo e ha effetti. Un compito ha **metodi**: ciascuno con
precondizioni e una rete di sottocompiti ordinati, parzialmente ordinati o
liberi. La pianificazione decompone alla SHOP2, dal compito radice fino
agli operatori primitivi, scegliendo tra metodi alternativi e tornando
indietro quando uno fallisce.

La MEA resta come fallback: quando nessun metodo copre un compito, o un
sottocompito è un semplice obiettivo simbolico, la MEA lo risolve.

L'archivio di procedure esistente diventa la libreria dei metodi.
Ogni procedura salvata con `gp-remember-procedure` è un metodo con:
il compito che risolve, le precondizioni osservate al momento del salvataggio,
la decomposizione (all'inizio la sequenza piatta, raffinabile a mano o
dall'apprendimento della fase 2.4), il punteggio.

Superficie REPL minima:

```lisp
(gp-add-task 'configura-interfaccia '(?d))
(gp-add-method 'configura-interfaccia
  :preconditions '((?d rdf:type device))
  :subtasks '((alimenta ?d) (collega ?d) (imposta ?d)))
(gp-plan :task '(configura-interfaccia interface-01))
(gp-decomposition)                      ; albero, non lista
(gp-explain)                            ; quale metodo, perché non gli altri
```

Vincoli:

- La riparazione ricorsiva delle precondizioni fino a 61 livelli viene
  sostituita dalla decomposizione. Rimuovila quando i test dell'archivio
  passano sulla nuova via. Riscrivi quei test in forma parametrica: un
  ciclo o una macro, non un test per numerale.
- Un piano HTN porta la sua decomposizione nella traccia e nell'episodio
  salvato, così un risultato riprodotto conserva la struttura.

### Fase 2.3 — Vincoli (cosa è accettabile, separato da in che ordine)

Implementa un risolutore CSP minimo in Lisp puro: variabili con domini
finiti, vincoli come predicati o tabelle, propagazione di consistenza
d'arco, backtracking con scelta della variabile più vincolata. Niente
librerie esterne.

I vincoli vivono nel contesto come conoscenza di dominio, essi stessi
affermazioni con provenienza. Un compito HTN può avere un sottocompito
`(solve ?csp)` che lega variabili prima che gli operatori le usino: il
CSP dice quale interfaccia su quale porta, il planner dice in che ordine.

Riformula i domini `hardware`, `music` e `geometry` come vincoli più
operatori. Devono restare caricabili e i loro test devono passare.

Superficie REPL minima:

```lisp
(gp-add-variable 'porta-di-interface-01 :domain '(usb1 usb2 tb1))
(gp-add-constraint '(distinct porta-di-interface-01 porta-di-mixer))
(gp-solve)                              ; bindings o condizione unsat
(gp-explain)                            ; quale vincolo ha escluso cosa
```

Vincoli:

- Un CSP insoddisfacibile è una condizione con restart: rilassa un
  vincolo indicato, oppure rinuncia. Mai un piano che ignora un vincolo.
- Le soluzioni sono affermazioni `:derived` che citano i vincoli. Se un
  vincolo viene ritrattato, il TMS fa cadere la soluzione.

### Fase 2.4 — Apprendimento di operatori e metodi dalle osservazioni

Estendi `core/induction.lisp`. Oggi induce un operatore STRIPS da una
coppia prima/dopo. Deve diventare:

1. **Da osservazione continua.** Con adapter abilitati in modalità
   `:read`, `gp-observe` prende istantanee di affermazioni a intervalli o
   su evento. Ogni azione esterna che cambia le affermazioni tra due
   istantanee è un esempio di transizione.
2. **Generalizzazione per differenza su più esempi.** Costanti che variano
   tra esempi coerenti diventano variabili. Costanti che restano, restano.
   Precondizioni: intersezione delle affermazioni prima che condividono
   termini con il cambiamento. Confidenza: numero di esempi concordanti;
   esempi discordanti azzerano e chiedono.
3. **Da sequenze a metodi.** Se una sequenza di transizioni ricorre e
   termina in uno stato che soddisfa un compito dichiarato, proponi un
   metodo HTN. Non lo aggiungi da solo: lo proponi, con esempi a supporto,
   e l'utente conferma o corregge.
4. **Rifiuto onesto.** Con un solo esempio l'operatore è `:tentative` e la
   MEA lo usa solo in `:simulate`. Serve conferma o un secondo esempio per
   usarlo in `:execute`.

Superficie REPL minima:

```lisp
(gp-observe :start)
;; ... l'utente lavora ...
(gp-observe :stop)
(gp-transitions)                         ; coppie prima/dopo raccolte
(gp-learn)                               ; operatori e metodi proposti
(gp-confirm-operator 'nome)
(gp-why-operator 'nome)                  ; gli esempi che lo sostengono
```

### Fase 2.5 — Radicamento esterno: Wikidata come contesto pubblico

Wikidata entra come **adapter di lettura**, nel sistema opzionale
`automa-gp/wikidata` (come `automa-gp/web` è opzionale). Il core non
dipende da esso. L'adapter usa l'API `wbgetentities` e, dove serve, SPARQL;
può portare un client HTTP come dipendenza del solo sistema opzionale.
Riusa `interface/json.lisp`.

Cosa fa:

- **Allineamento.** `gp-align 'acme "Q…"` lega un'entità locale a un item
  Wikidata; `gp-align-predicate 'gp:sede "P159"` lega un predicato a una
  proprietà. L'allineamento è un'affermazione anch'essa
  (`(acme owl:sameAs wd:Q…)`), con provenienza `:asserted`, e si può
  ritrattare. Niente si allinea da solo: l'adapter propone candidati per
  etichetta, l'utente sceglie.
- **Lettura.** Per un'entità allineata, `gp-fetch 'acme` legge le
  dichiarazioni delle proprietà allineate e le inserisce come affermazioni
  con provenienza `:external`, conservando rango, qualificatori (date,
  unità) e riferimenti citati su Wikidata. Una dichiarazione con rango
  `deprecated` su Wikidata entra come evidenza contro, non a favore.
- **Verifica.** `gp-check 'acme` confronta le affermazioni locali con
  quelle esterne sulle proprietà allineate. Accordo: aggiunge una
  provenienza a favore. Disaccordo: la verità diventa `:both` e scatta la
  condizione della fase 2.1 con i suoi restart. Un predicato funzionale
  con valore diverso è disaccordo; un predicato non funzionale con valore
  in più non lo è.
- **Contesto.** `gp-context-from 'acme :depth 1` porta nel contesto le
  entità collegate, come `:unknown` finché non servono e con la sola
  provenienza esterna. È il modo per dare al planner conoscenza di sfondo
  senza che l'utente la scriva.

Cosa non fa, e va scritto nel codice e nella documentazione:

- Non scrive mai su Wikidata.
- Non è un oracolo. Wikidata è un insieme di dichiarazioni con rango e
  riferimenti, non la verità. Il sistema tratta le sue dichiarazioni come
  una fonte tra le altre, con un peso configurabile per predicato, e
  quando le cita cita anche i riferimenti che Wikidata stessa porta.
- Non riceve conoscenza privata. L'unica cosa che esce è l'etichetta o il
  QID cercato. Le affermazioni locali non lasciano mai la macchina.
  L'utente decide cosa allineare.
- Non gira senza policy: le letture avvengono solo se la policy dichiara
  `:external-read t`, e ogni lettura è registrata nel contesto con
  istante e cosa è stato chiesto.
- Ha una cache locale in `~/.automa-gp/wikidata-cache.agp`, con data di
  lettura; le affermazioni esterne portano quella data come qualificatore
  e `gp-check` avverte quando è più vecchia di una soglia.

### Fase 2.6 — Italiano ristretto, IA classica

L'automa accetta e produce un **italiano ristretto**: un sottoinsieme
della lingua con grammatica fissa, lessico dichiarato e traduzione
univoca in affermazioni, obiettivi, compiti, vincoli, regole e domande.
Nessun modello linguistico, nessuna statistica. La tradizione è quella
di ELIZA per il pattern matching, delle grammatiche a unificazione e dei
DCG di Pereira e Warren, dei capitoli di Norvig sulla sintassi e sulla
semantica composizionale, e dei linguaggi controllati come Attempto.

Sostituisce lo stemmer ad hoc di `interface/ask.lisp`, che va ritirato
quando i suoi test passano sulla via nuova.

**Architettura, in tre strati separati e testabili da soli:**

1. **Morfologia.** Un analizzatore per l'italiano regolare: le tre
   coniugazioni con i tempi che servono (presente, imperativo,
   participio, infinito), plurali e generi di nomi e aggettivi, articoli
   e preposizioni articolate, clitici più comuni. Le forme irregolari
   che servono (essere, avere, fare, andare, dare, dire, stare, potere,
   dovere, volere) sono in tabella. Restituisce lemma e tratti:
   `(accendi → accendere :modo imperativo :persona 2 :numero sg)`.
   Il lessico del dominio lo dichiara l'utente con `gp-lexicon`: un
   lemma, la categoria, i tratti fissi e il simbolo del grafo a cui
   corrisponde. Una parola non nel lessico non viene indovinata.

2. **Sintassi.** Un DCG o un chart parser in Lisp puro con unificazione
   di tratti (accordo genere e numero, reggenza dei verbi). La grammatica
   è chiusa e documentata in `docs/italiano-ristretto.md` con tutte le
   forme di frase ammesse e un esempio per ciascuna. Forme minime:

   - Affermazione: "ACME è un cliente", "la sede di ACME è Milano",
     "ACME non è attivo" (falso esplicito), "interface-01 è spenta".
   - Affermazione con qualificatori: "ho fatturato 12 ore ad ACME il
     10 gennaio 2024".
   - Obiettivo: "voglio che interface-01 sia configurata".
   - Compito: "configura interface-01", "esegui la chiusura mensile
     di ACME".
   - Vincolo: "ogni interfaccia ha una porta diversa", "la porta di
     interface-01 è usb1 oppure usb2".
   - Regola: "se un file è creato allora è da classificare".
   - Domanda: "perché interface-01 è configurata?", "ACME è attivo?",
     "quali clienti hanno sede a Milano?", "cosa manca per configurare
     interface-01?".
   - Meta: "dimentica che ACME è attivo", "chi lo dice?", "quanto è
     vecchio?".

   Ogni forma produce una e una sola struttura semantica. Una frase che
   ammette due analisi viene rifiutata con le due letture mostrate, non
   scelta a caso. Una frase fuori grammatica viene rifiutata indicando
   la prima parola in cui l'analisi si è fermata.

3. **Semantica.** Una funzione per forma di frase che costruisce
   l'oggetto del core: `statement` con provenienza `:asserted` e
   qualificatori, obiettivo per la MEA, compito per l'HTN, vincolo per
   il CSP, regola per il matcher, o interrogazione sul grafo e sul TMS.
   Le entità nominate vengono risolte contro le etichette del grafo e
   del lessico; un'entità mai vista è una condizione con restart
   (`declare-entity`, `abort`), non un simbolo creato in silenzio.

**Superficie REPL minima:**

```lisp
(gp-lexicon 'cliente :noun :gender :m :symbol 'gp:cliente)
(gp-lexicon 'configurare :verb :symbol 'configura-interfaccia :kind :task)
(gp-say "voglio che interface-01 sia configurata")
;; => Ho capito: obiettivo (interface-01 gp:configurata t). Confermi?
(gp-say "ACME non è attivo")
;; => Ho capito: (acme gp:attivo t) è FALSO, detto da te ora. Confermi?
(gp-say "perché interface-01 è configurata?")
;; => narrazione della catena di giustificazioni
(gp-parse "la sede di ACME è Milano")     ; solo l'albero e la semantica
(gp-grammar)                              ; le forme ammesse, con esempi
```

`gp-say` restituisce sempre ciò che ha capito prima di applicarlo, nella
stessa lingua, e applica solo dopo conferma, salvo `:confirm nil`
esplicito. Le domande non chiedono conferma.

**Generazione.** `interface/narration.lisp` si estende agli oggetti nuovi
con template: giustificazioni ("lo so perché l'adapter filesystem lo ha
letto il 3 marzo"), i quattro valori di verità ("non lo so", "è in
disputa tra ciò che hai detto e ciò che dice Wikidata"), decomposizioni
HTN ("per configurare ho scelto il metodo standard: prima alimento, poi
collego, poi imposto"), vincoli violati, operatori appresi con i loro
esempi. La generazione usa la stessa morfologia dello strato 1 per
accordare genere e numero. Nessuna frase dice più di quanto la traccia
o il grafo registrano.

**Vincoli:**

- La grammatica è finita e documentata. Estenderla è una modifica al
  codice con test, non un'inferenza.
- Il lessico generale (articoli, preposizioni, verbi ausiliari, parole
  delle forme di frase) è nel codice. Il lessico di dominio è
  dell'utente e si salva in `~/.automa-gp/lessico.agp`.
- Morfologia, sintassi e semantica sono tre file distinti con test
  distinti. La morfologia si testa su tabelle di forme; la sintassi su
  alberi attesi; la semantica su oggetti del core attesi.
- Le frasi che chiedono di eseguire, cancellare o lanciare comandi
  restano rifiutate come oggi. Una frase non esegue mai un piano: al più
  aggiunge un obiettivo o un compito, e il ciclo di autonomia con la sua
  policy decide il resto.

---

## 3. STRATO DI CONOSCENZA PROFESSIONALE

Sopra le capacità, un livello che le usa insieme. È qui che il sistema
serve davvero.

**Grafo privato.** La conoscenza professionale è un grafo di affermazioni
nel formato della fase 2.0, in un contesto radice `professionale` con
sottocontesti per cliente, progetto, periodo (i contesti gerarchici del
prompt maestro, §14). Le entità pubbliche del proprio lavoro (strumenti,
standard, aziende, luoghi, norme) si allineano a Wikidata; le entità
private (persone, progetti interni, importi) no.

**Casi.** Un caso è: contesto iniziale (affermazioni con provenienze),
compito richiesto, decomposizione usata, vincoli attivi, risultato
prodotto (affermazioni finali e riferimenti agli artefatti reali: file,
commit, documenti), esito, data. `gp-remember-case` lo salva. I casi sono
episodi con struttura, non log.

**Recupero.** `gp-similar-cases :task ... :context ...` ordina i casi per
somiglianza simbolica: stesso compito, sovrapposizione delle affermazioni
rilevanti, stessi vincoli, stesse entità allineate. La misura è leggibile
e spiegabile: il sistema dice quali affermazioni in comune hanno pesato.

**Riproduzione.** `gp-reproduce :case nome` fa, nell'ordine:

1. Confronta il contesto del caso con quello corrente; elenca le
   affermazioni mancanti, quelle in più, quelle con verità `:unknown` o
   `:both`, quelle con provenienza più debole.
2. Se ci sono entità allineate e la policy lo permette, `gp-check` sulle
   affermazioni pubbliche coinvolte; le disputate si risolvono prima di
   pianificare.
3. Tenta di ripristinare le mancanti con la pianificazione HTN e la MEA.
4. Risolve i vincoli del caso sul contesto nuovo.
5. Costruisce il piano dalla decomposizione del caso, adattata.
6. Simula. Mostra gli scarti rispetto al caso originale.
7. Esegue solo sotto `:execute` e con conferma sugli operatori esterni.
8. Salva l'esito come caso nuovo, collegato all'originale.

**Ingresso e uscita in italiano.** Ogni affermazione, caso, vincolo e
domanda dello strato professionale può entrare con `gp-say` nell'italiano
ristretto della fase 2.6 e ogni risposta può uscire per narrazione.
Il lessico di dominio nasce dalle tre risposte dell'utente qui sotto.

**Provenienza ovunque.** Qualunque risposta del sistema può essere
seguita da `gp-why`. Se non sa perché, dice `:unknown`, non inventa.

**Persistenza.** Tutto in `.agp` leggibili, nella cartella
`~/.automa-gp/`. Affermazioni, metodi, vincoli, operatori appresi, casi,
allineamenti, cache esterna. Un file per livello. `gp-save` e `gp-load`
restano l'unica via. `gp-export :turtle` produce il grafo privato in un
formato che qualunque strumento RDF legge.

Prima di implementare questo strato, chiedi all'utente tre cose e
inseriscile in `docs/dominio-professionale.md`:

- Il suo lavoro, in una frase.
- Tre risultati concreti che ha prodotto negli ultimi mesi e vorrebbe
  saper riprodurre.
- Per ciascuno: cosa c'era prima, cosa ha fatto, cosa doveva rispettare,
  cosa c'era dopo, e quali entità coinvolte sono pubbliche.

Da quelle risposte costruisci il dominio `domains/professionale`, i primi
tre casi, gli allineamenti iniziali, e i test che riproducono i casi in
`:simulate` con l'adapter Wikidata sostituito da una cache fissa nei test.

---

## 4. REGOLE DI SVILUPPO PER QUESTA FASE

- **Core prima, superfici dopo.** Nessuna modifica a `interface/web.lisp`,
  `interface/web-api.lisp` o al Workbench Swift finché le fasi 2.0–2.6 e
  lo strato di conoscenza non sono completi nel REPL. Le superfici si
  aggiornano una volta, alla fine, leggendo lo stato dal core invece di
  replicare i gate.
- **Una versione per capacità, non per pulsante.** La versione sale
  quando una delle fasi qui sopra è completa. Il `CHANGELOG.md` descrive
  la capacità, non la modifica.
- **Test parametrici.** Nessun file di test oltre le 1500 righe.
  Ripetizioni con numerali si scrivono come cicli. Se un test esistente
  viola questa regola e lo tocchi, lo riscrivi.
- **Test senza rete.** I test dell'adapter Wikidata usano risposte
  registrate su file. Nessun test apre una connessione.
- **Nessuna dipendenza nuova** per il core. UIOP resta l'unica. Il client
  HTTP vive solo in `automa-gp/wikidata`.
- **Ogni condizione ha restart.** Disputa nel TMS, metodo senza
  applicabilità, CSP insoddisfacibile, operatore discordante, disaccordo
  con la fonte esterna: tutte condizioni con almeno un restart che lascia
  il contesto coerente.
- **Spiegazione prima di velocità.** Se una struttura più veloce rende
  `gp-why` meno completo, non si adotta.
- **Il REPL è l'interfaccia.** Ogni funzione nuova è esportata da
  `packages.lisp`, documentata con docstring, e usabile senza il web.

---

## 5. CRITERI DI ACCETTAZIONE

La fase 2 è finita quando questi otto scenari passano come test in
`tests/` e funzionano a mano nel REPL:

1. **Tripla con qualificatori.** Un'affermazione n-aria entra nella forma
   nuova, viene esportata in Turtle, reimportata, e il contesto risultante
   è identico al precedente, provenienze comprese.
2. **Ritrattazione a cascata.** Un'affermazione osservata smentisce una
   premessa asserita; due affermazioni derivate e una soluzione CSP
   cadono; `gp-why` su una di esse spiega la catena; il piano corrente
   viene invalidato e `gp-plan` lo ricalcola senza l'affermazione caduta.
3. **Vero, falso, ignoto, disputato.** Quattro affermazioni con evidenze
   diverse restituiscono i quattro valori; un predicato chiuso restituisce
   `:false` per assenza mentre uno aperto restituisce `:unknown`; la MEA
   usa solo la `:true` e `gp-explain` lo dice.
4. **Disaccordo con Wikidata.** Un'entità allineata ha localmente un
   valore diverso da quello esterno su un predicato funzionale; `gp-check`
   porta la verità a `:both`, la condizione offre i restart, la scelta
   `prefer-source :asserted` riporta `:true` e registra che l'esterno è
   stato scartato e perché. Tutto con la cache fissa, senza rete.
5. **Decomposizione con alternativa.** Un compito con due metodi; il primo
   fallisce a metà; il planner torna indietro, sceglie il secondo, e
   `gp-explain` mostra entrambi i tentativi.
6. **Operatore appreso e usato.** Tre transizioni osservate producono un
   operatore generalizzato; un piano lo usa in `:simulate`; in `:execute`
   viene rifiutato finché non è confermato; dopo la conferma viene
   eseguito.
7. **Risultato riprodotto.** Un caso salvato da un contesto A viene
   riprodotto in un contesto B che differisce in due affermazioni, una
   delle quali pubblica e verificabile; il sistema elenca gli scarti,
   verifica la pubblica, ripristina ciò che manca, simula, esegue con
   conferma, e salva il caso nuovo collegato al primo.
8. **Italiano ristretto andata e ritorno.** Dieci frasi, una per forma
   ammessa, entrano con `gp-say`, producono gli oggetti del core attesi
   e vengono confermate; una frase ambigua viene rifiutata con le due
   letture; una frase con un'entità ignota apre il restart di
   dichiarazione; "perché" su un'affermazione derivata restituisce una
   narrazione che cita ogni provenienza e accorda genere e numero.

---

## 6. COSA NON FARE

- Nessun modello linguistico, nemmeno come "aiuto" alla traduzione delle
  affermazioni. Se in futuro servirà, entrerà come proponente esterno di
  affermazioni con provenienza `:llm` e verità iniziale `:unknown`, mai
  come decisore.
- Nessun parser statistico, nessun embedding, nessun dizionario esterno
  scaricato. L'italiano ristretto è una grammatica scritta a mano e un
  lessico dichiarato: ciò che non è dichiarato non è capito.
- Nessuna implementazione completa di RDF, OWL o SPARQL locale. Il
  sottoinsieme della fase 2.0 basta; l'interoperabilità passa per
  l'export.
- Nessun motore Rete. Il matcher attuale basta per il volume di regole
  previsto.
- Nessuna scrittura su Wikidata, nessun invio di affermazioni private,
  nessuna lettura senza policy.
- Nessun lavoro di parità tra REPL, HTML e Workbench finché il core non è
  completo. Quando lo sarà, le superfici leggono un solo stato.
- Nessuna riscrittura della MEA. Si estende, si affianca, non si
  sostituisce.

---

Priorità: correttezza, poi spiegabilità, poi chiarezza, poi testabilità,
poi performance.
