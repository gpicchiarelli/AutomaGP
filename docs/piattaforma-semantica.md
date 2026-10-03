# Piattaforma semantica: integrazione col resto del progetto

Questo documento dice come [`PROMPT-SEMANTICA.md`](PROMPT-SEMANTICA.md)
entra nel repository: cosa prevale su cosa, cosa cambia rispetto a
[`PROMPT-FASE-2.md`](PROMPT-FASE-2.md), dove vive ciascuna delle 38
sezioni, in quale ordine si costruisce, cosa esiste già e cosa no. Non
sostituisce nessuno dei due prompt. Ogni frase sullo stato corrisponde a
codice caricabile e a un test, come nel resto della documentazione; quello
che è ancora da fare è scritto come da fare.

Le affermazioni sugli standard sono state lette dalle pagine ufficiali dei
loro editori il 2026-10-03 e il registro (`semantic/catalog.lisp`) le
conserva. Dove una specifica non è stata ancora letta fino ai suoi
riferimenti normativi, qui e nel registro è scritto "non letto", non
indovinato.

## 1. Stato in una riga

La fondazione esiste e funziona; nessuno standard è implementato.

| Cosa | Stato |
| --- | --- |
| Registro degli standard, con versioni, documenti normativi, suite di test, dipendenze (`semantic/registry.lisp`, `catalog.lisp`) | fatto: 16 standard registrati |
| Livelli di supporto e prove richieste per ciascuno (`semantic/support.lisp`) | fatto |
| Requisiti e tracciabilità requisito, costrutto, codice, test (`semantic/requirement.lisp`) | fatto |
| Diagnostica tipizzata, nessuna perdita silenziosa (`semantic/diagnostics.lisp`) | fatto |
| Chiusura delle dipendenze con rilevamento dei cicli (`semantic/closure.lisp`) | fatto |
| Riga di comando `modelc`: `standard list`, `show`, `closure`, `requirements` (`scripts/modelc`) | fatto; gli altri comandi dichiarano la fase che li porta e rifiutano con stato 3 |
| Acquisizione, archivio, resolver, RDF, OWL, SHACL, SPARQL, Wikidata, comportamento, compilatore | da fare (§7) |

Il comando `scripts/modelc standard list` stampa oggi, tra l'altro:
`16 standards registered, 0 with some support, 0 with a claimable level.`
Quella riga è il confine tra ciò che si può dire e ciò che no.

## 2. Gerarchia dei documenti e precedenza

1. [`PROMPT.md`](PROMPT.md): il sistema deliberativo. Contesto, stato,
   obiettivo, differenza, operatore, piano, azione, osservazione. Resta
   vincolante in tutto ciò che i documenti seguenti non modificano
   esplicitamente. Le sue regole di sicurezza (le tre autorità `:read`,
   `:simulate`, `:execute`, la conferma per ciò che è irreversibile, gli
   adapter spenti finché la policy non li accende) non si indeboliscono
   mai.
2. [`PROMPT-SEMANTICA.md`](PROMPT-SEMANTICA.md): la piattaforma che
   implementa standard semantici. Vincolante per il sottosistema
   `semantic/` e per ciò che lo usa. Prevale su `PROMPT-FASE-2.md` dove
   sono in conflitto, e i conflitti sono elencati nel §3.
3. [`PROMPT-FASE-2.md`](PROMPT-FASE-2.md): conoscenza, verità, HTN,
   vincoli, apprendimento, italiano ristretto, strato professionale. È
   conservato; le parti assorbite dalla piattaforma sono marcate lì.
4. Questo documento: la mappa e la regola di precedenza.

Regola: se due documenti si contraddicono, vale il più recente per il suo
ambito, e la contraddizione si annota qui, in una riga, invece di
risolversi in silenzio nel codice.

## 3. Cosa cambia rispetto al prompt di Fase 2

| Tema | Fase 2 | Piattaforma semantica | Decisione |
| --- | --- | --- | --- |
| RDF, OWL, SPARQL | "Non implementare RDF per intero"; "nessuna implementazione completa di RDF, OWL o SPARQL locale" (§2.0, §6) | Implementarli per intero, per livelli, con prove (§2, §8, §9, §11, §36) | **Superato.** Il rigore resta: un livello si dichiara solo con la sua evidenza. |
| Forma dei fatti | Forma canonica = tripla in una classe `statement` (§2.0) | Il modello canonico è indipendente dal backend; RDF, OWL, SHACL e Wikibase sono modelli distinti e una conversione non è mai data per senza perdita (§7, §20) | La `statement` di 2.0 diventa lo statement del modello Wikibase (qualificatori, riferimenti, rango, verità) nel World Model. La tripla RDF è il modello del modulo RDF. Le liste-fatto del core restano e si normalizzano in ingresso, come in 2.0. |
| RDF 1.2 e triple citate | Riferimento per RDF-star (§2.0) | Non nomina una versione | RDF 1.2 è **Candidate Recommendation** (snapshot del 7 aprile 2026): registrato come tale, non è un target finché non diventa una Recommendation o il proprietario non decide altrimenti. Il primo riferimento è RDF 1.1. |
| Verità | Quattro valori alla Belnap e Truth Maintenance (§2.1) | Fatto asserito, inferito, derivato, ipotesi, osservazione, tenuti separati (§14); le semantiche dello standard sono formali (§37) | Le semantiche di RDFS e OWL sono a due valori e a mondo aperto. I quattro valori sono lo strato **epistemico** di AutomaGP (quanto fidarsi di un'affermazione) e non cambiano mai la relazione di conseguenza di uno standard. A un ragionatore di standard va una base di premesse: le affermazioni `:true`, e per `:both` quello che la policy decide. |
| Provenienza | `:asserted` `:observed` `:derived` `:effect` `:external` (§2.1) | asserted, inferred, derived, hypothesis, observation (§14) | Sette tipi, vedi §4. |
| Vincoli | Un risolutore CSP minimo, "cosa è accettabile" (§2.3) | Constraint Engine di prima classe; SHACL completo (§10, §15) | Due famiglie sotto un solo oggetto `constraint` (ambito, condizione, gravità, messaggio, fonte, provenienza): vincoli di **validità** (SHACL e predicati nativi su modello, dati, stato, azione, piano) e vincoli di **soddisfacimento** (il CSP di 2.3, che cerca assegnazioni). |
| Wikidata | Adapter di sola lettura in `automa-gp/wikidata` (§2.5) | Modello completo e astrazione `KnowledgeSource` (§12, §13) | Il modello diventa quello completo di Wikibase. Restano tutte le regole di 2.5: mai scrivere, mai inviare conoscenza privata, lettura solo con `:external-read t`, cache locale con data di lettura, allineamento deciso dall'utente, Wikidata non è un oracolo. |
| Dipendenze | "Nessuna dipendenza nuova per il core. UIOP resta l'unica. Il client HTTP vive solo in `automa-gp/wikidata`" (§4) | Acquisizione da HTTP, Git, endpoint SPARQL, con checksum (§4, §5) | Il **core** (`core/`, `memory/`, `adapters/`, `interface/`) resta ANSI CL più UIOP. La piattaforma può avere sistemi ASDF con dipendenze, ciascuno separato e opzionale, con la disponibilità su Quicklisp verificata (§9). Il client HTTP vive in un sistema di acquisizione, non in quello di Wikidata. |
| Test senza rete | Nessun test apre una connessione (§4) | Le suite di conformità sono ufficiali (§23) | Invariato. La suite unitaria non tocca la rete. Le suite del W3C si acquisiscono con un comando esplicito, si fissano per checksum e si leggono dalla cache locale. |
| Motore Rete | Non si fa (§6) | Non lo richiede | Invariato. Il ragionamento a regole (OWL 2 RL, regole SHACL) si fa con l'inferenza in avanti già esistente finché misure non dicono altro. |
| Core prima, superfici dopo | Sì (§4) | Non dice | Invariato. |
| Una versione per capacità | Sì (§4) | Fasi di roadmap | Invariato: ogni fase S1 e seguenti chiude con una versione minore. |
| HTN, apprendimento di operatori, italiano ristretto, strato professionale | 2.2, 2.4, 2.6, §3 | Non li nomina | Invariati. Si appoggiano al World Model (S8). |
| Struttura delle cartelle | Non dice | Albero `src/` (§31) | `semantic/`, un sistema ASDF per modulo (§6). |

## 4. Livelli di rappresentazione

Lo standard non viene sostituito da una IR semplificata: viene conservato,
e tutto il resto è derivato (§1 del prompt semantico). I livelli, dal più
vicino al core al più lontano:

```text
fatto di core        (power-state interface-01 off)            oggi
statement            soggetto, predicato, valore +             Fase 2.0, S6, S8
                     qualificatori, riferimenti, rango, verità
grafo/dataset RDF    triple e quadruple, termini RDF 1.1       S1
assiomi OWL          struttura OWL 2, due semantiche           S3
vincoli              SHACL e vincoli nativi                    S4
comportamenti        azioni, precondizioni, effetti            S7, e gli operatori di oggi
```

Nessun passaggio tra due livelli è senza perdita per ipotesi. Ogni
passaggio dichiara cosa conserva e cosa perde, e il suo andata e ritorno è
un test, prima che il costrutto possa salire a `:represented`.

Provenienza, sette tipi (i cinque di Fase 2 più i due che la piattaforma
aggiunge):

| Tipo | Significato | Origine |
| --- | --- | --- |
| `:asserted` | l'utente l'ha detta | Fase 2 |
| `:observed` | un adapter l'ha letta | Fase 2 |
| `:derived` | una regola l'ha dedotta, con le sue premesse | Fase 2 |
| `:effect` | un operatore eseguito l'ha prodotta | Fase 2 |
| `:external` | una fonte pubblica la sostiene, con i riferimenti che porta | Fase 2 |
| `:inferred` | conseguenza della semantica di uno standard: standard e versione, regola o assioma, premesse | piattaforma §14 |
| `:hypothesis` | proposta e non accettata: un operatore appreso `:tentative`, una proposta esterna con verità iniziale `:unknown` | piattaforma §14 |

"Inferito" e "derivato" restano distinti: il primo discende da uno
standard, il secondo da una regola di chi usa il sistema.

## 5. Livelli di supporto

"Supportiamo OWL" non è un'affermazione. Lo sono queste, in ordine, e
ciascuna richiede la propria prova e quella di tutte le precedenti
(`semantic/support.lisp`):

| Livello | Si può dire quando | Prova richiesta |
| --- | --- | --- |
| `:parsed` | il formato si legge | una esecuzione di test in cui qualcosa passa e niente fallisce |
| `:represented` | un costrutto si conserva senza perdita | un andata e ritorno: leggere, rappresentare, scrivere, rileggere dà lo stesso |
| `:validated` | un costrutto si verifica con le regole dello standard | test positivi e negativi delle regole di validità |
| `:semantically-implemented` | la semantica che lo standard definisce è implementata | test della semantica, legati ai requisiti |
| `:executable` | quella semantica gira in Common Lisp su SBCL | una build: caricata ed eseguita, senza fallimenti |
| `:conformant` | l'implementazione supera i test di conformità disponibili | un rapporto di conformità di una suite ufficiale, esito PASS |

Regole che il codice applica e i test fissano:

- Una prova con un fallimento non stabilisce il suo livello.
- Una prova per un livello alto senza quelle dei livelli sotto non vale
  nulla: `:executable` senza `:parsed` è nulla.
- Un rapporto di conformità in cui qualche test è stato lasciato fuori è
  PARTIAL, e PARTIAL non è conformità: il livello si ferma a
  `:executable`.
- Compilare non è una prova di niente.
- Uno standard è "supportato al livello L" solo quando il suo catalogo di
  costrutti è dichiarato completo (§2 del prompt: ogni costrutto va
  catalogato) e **ogni** costrutto ha almeno L. Finché il catalogo non è
  completo, l'enunciato onesto è "alcuni costrutti sono a questi livelli",
  e il rapporto dice quali.
- Il livello di uno standard è quello del suo costrutto più debole.

Le quattro risposte del §2 del prompt (implementato, parzialmente
implementato, non implementato, non valido) sono le **diagnostiche** su un
costrutto incontrato in un input. `construct-status` le ricava dal
livello: nessun livello è non implementato, fino a `:validated` è
parzialmente implementato, da `:semantically-implemented` in su è
implementato. "Non valido" lo produce la validazione di un input, mai il
catalogo.

Un limite da conoscere, riportato dalla specifica di OWL 2 stessa: i suoi
casi di test sono dichiarati *incompleti*. Superarli tutti non prova la
conformità; fallirne uno prova la non conformità. Quindi `:conformant`
significa "nessun fallimento noto sulla suite disponibile", che è quello
che il prompt chiede (§36), e le clausole di conformità del documento
Conformance di ogni standard diventano **requisiti** a parte, non
coperti dai soli test.

## 6. Dove vive ogni sezione del prompt semantico

| § | Tema | Dove | Stato |
| --- | --- | --- | --- |
| 1 | Specifica, modello, implementazione, esecuzione | `semantic/standard.lisp` conserva dove la specifica è pubblicata e non ne sostituisce il testo | fondazione |
| 2 | Implementazione completa, mai "ignora" | livelli di supporto; `report-unsupported` e `unsupported-construct` | fatto |
| 3 | Registro degli standard | `semantic/registry.lisp`, `catalog.lisp`, `modelc standard ...` | fatto |
| 4 | Acquisizione | sistema `automa-gp/acquire` | S2 |
| 5 | Resolver delle ontologie | `dependency-closure` (fatto) e il resolver | S2 |
| 6 | Archivio immutabile | archivio indirizzato per contenuto in `~/.automa-gp/archive/`, con manifest `.agp` | S2 |
| 7 | Modello semantico canonico | un modulo per modello (RDF, OWL, Wikibase, vincoli) | S1, S3, S4, S6 |
| 8 | OWL | `semantic/owl/` | S3 |
| 9 | RDF | `semantic/rdf/` | S1 |
| 10 | SHACL | `semantic/shacl/` | S4 |
| 11 | SPARQL | `semantic/sparql/` | S5 |
| 12 | Wikidata | `semantic/wikibase/` | S6 |
| 13 | Astrazione delle fonti | interfaccia `KnowledgeSource` | S6 |
| 14 | Ragionamento | RDFS in S1, OWL in S3, regole SHACL in S4; la spiegazione estende la traccia deliberativa esistente | S1, S3, S4 |
| 15 | Constraint Engine | S4 e il CSP di Fase 2.3 sotto un solo oggetto | S4 |
| 16 | World Model | il contesto resta l'unità centrale (`PROMPT.md`); il World Model è il contenuto dei contesti e delle memorie | S8 |
| 17 | Modello di comportamento | operatori, azioni, metodi HTN di oggi; il modello indipendente da Lisp | S7 |
| 18 | AutomaGP sopra il World Model | il ciclo deliberativo esiste; cambia ciò su cui lavora | S8 |
| 19 | Pianificazione | MEA e planner esistenti; HTN di Fase 2.2 | S7, S8 |
| 20 | Implementation Model | descrive come realizzare in Lisp i costrutti, senza equivalenze presunte | S9 |
| 21 | Backend Common Lisp | genera S-espressioni, mai stringhe concatenate | S9 |
| 22 | Runtime | cresce con ogni standard implementato | S1 e seguenti |
| 23 | Motore di conformità | il modello di evidenza (fatto) e il runner | evidenza fatta, runner da S1 |
| 24 | Dalla specifica ai test | `semantic/requirement.lisp` | fatto |
| 25 | Tracciabilità | `requirements-implemented-by`, `tests-for-requirement`, `traceability-gaps` | fatto |
| 26 | Versioni | `standard@version` (fatto); `implementation@version` | S9 |
| 27 | Build riproducibili | ordine deterministico della chiusura (fatto); lock file e hash | S2 |
| 28 | Errori | `semantic/diagnostics.lisp` | fatto |
| 29 | Riga di comando | `scripts/modelc` | quattro comandi fatti, tredici pianificati |
| 30 | API per AutomaGP | tabella dei nomi qui sotto | S8 |
| 31 | Architettura dei pacchetti | albero qui sotto | fondazione fatta |
| 32 | Estendibilità | interfaccia comune di un modulo di standard, definita con il primo modulo | S1 |
| 33 | Nessun dominio hard-coded | regola; i pacchetti di `domains/` migreranno a ontologia più comportamento | S8 |
| 34 | Prima implementazione | §8 | proposta |
| 35 | Roadmap | §7 | unificata |
| 36 | Definizione di supporto | §5 | fatto |
| 37, 38 | Regola assoluta, obiettivo | principi; li fanno rispettare i test di fitness | fatto dove misurabile |

### Nomi dell'API

Il prompt elenca primitive con nomi che il progetto non può usare così:
`find-class` è un simbolo di Common Lisp, e `query`, `plan`, `explain`
sono già esportati da `automa-gp` con un altro significato. Regola: i
comandi di REPL tengono il prefisso `gp-`; l'API interna del sottosistema
sta in pacchetti propri. Proposta, da confermare quando parte la fase che
li definisce:

| Prompt | Nome |
| --- | --- |
| `find-class`, `find-property`, `find-individual` | `gp-find-owl-class`, `gp-find-property`, `gp-find-individual` |
| `find-statements` | `gp-find-statements` |
| `query` | `gp-sparql` (`gp-query` esiste e interroga i fatti locali) |
| `infer` | `gp-reason` (`gp-infer` esiste ed è l'inferenza in avanti) |
| `validate` | `gp-validate` |
| `explain` | `gp-explain`, esteso alle giustificazioni semantiche |
| `find-actions`, `check-preconditions`, `apply-action` | `gp-find-actions`, `gp-check-preconditions`, `gp-apply-action` |
| `get-world-state`, `update-world-state` | `gp-world-state`, `gp-update-world-state` |
| `plan` | `gp-plan`, che esiste |
| `search-knowledge`, `get-entity`, `get-statements`, `query-knowledge`, `resolve-entity` | `gp-search-knowledge`, `gp-get-entity`, `gp-get-statements`, `gp-query-knowledge`, `gp-resolve-entity` |

### Albero dei moduli

Il prompt propone `src/`. Il repository ha già `core/`, `memory/`,
`adapters/`, `domains/`, `interface/`; un secondo albero sopra di essi
confonderebbe. La piattaforma sta in `semantic/`, e ciò che nel prompt
duplica il core (pianificazione, comportamento, World Model, AutomaGP) si
innesta nel core invece di essere riscritto.

```text
semantic/                 fatto: registro, catalogo, livelli, requisiti,
                          diagnostica, chiusura, rapporto, riga di comando
semantic/rdf/             S1   sistema automa-gp/rdf
semantic/acquire/         S2   sistema automa-gp/acquire (HTTP, hash)
semantic/owl/             S3   syntax, model, direct-semantics, rdf-semantics, reasoning
semantic/shacl/           S4
semantic/sparql/          S5
semantic/wikibase/        S6
semantic/compiler/        S9   implementation model, ir, backend/common-lisp
```

Ogni modulo di standard è un sistema ASDF proprio, che dipende da
`automa-gp/semantic` e non modifica il core (§32 del prompt).

## 7. Fasi

Le fasi del prompt semantico sono un ordine di dipendenza; Fase 2 non è più
un binario indipendente, ma si innesta su quelle. La sigla S distingue
queste fasi dalle 12 di `PROMPT.md` e dalle 2.x di Fase 2.

| Fase | Prompt semantico | Fase 2 | Contenuto | Si chiude quando |
| --- | --- | --- | --- | --- |
| **S0** | | | Fondazione: registro, livelli, requisiti, diagnostica, chiusura, `modelc` | **fatta (0.197.0)** |
| S1 | 1 | prepara 2.0 | IRI, termini RDF 1.1, grafi e dataset, N-Triples e N-Quads, poi Turtle, RDF/XML, JSON-LD; entailment RDFS | il primo target del §8 è `:conformant` su N-Triples; poi uno standard per volta |
| S2 | 2 | | Acquisizione, archivio immutabile, resolver, `owl:imports`, cache, lock file | `resolve(A)` dà la chiusura, due build uguali danno lo stesso risultato |
| S3 | 3 | | OWL 2 per gradini: struttura e sintassi funzionale, mappa verso RDF, controlli di profilo, ragionamento RL, Direct Semantics, RDF-Based Semantics | un livello alla volta secondo il §5, ciascuno con i requisiti del documento Conformance |
| S4 | 4 | 2.3 | SHACL e Constraint Engine; i CSP sotto lo stesso oggetto `constraint` | la suite SHACL ufficiale, esito PASS sul Core |
| S5 | 5 | | SPARQL 1.1: query, update, cammini, endpoint remoti | la suite SPARQL 1.1 |
| S6 | 6 | 2.5 | Modello Wikibase completo e `KnowledgeSource`; adapter di lettura di Wikidata | scenario 4 di Fase 2 con la cache fissa, senza rete |
| S7 | 7 | 2.2 | Modello di comportamento indipendente da Lisp; HTN | scenario 5 di Fase 2 |
| S8 | 8 | 2.0, 2.1, 2.4, 2.6, §3 | Statement con verità e TMS; AutomaGP sopra il World Model; apprendimento; italiano; strato professionale | gli otto scenari di Fase 2 |
| S9 | 9 | | Compilazione: standard, modello d'implementazione, S-espressioni Lisp, SBCL, conformità | un modulo di standard generato supera la stessa suite del modulo scritto a mano |

Fase 2.0 dipende da S1 per l'esportazione in Turtle e N-Triples: lo
statement si progetta in S8 sopra il modello RDF già fatto, non prima.

## 8. Primo target formalmente delimitato (proposta)

Il §34 del prompt chiede un primo standard piccolo e **completo**, da
parser a conformità, prima di ampliare. Proposta: **RDF 1.1 N-Triples**
(`ntriples@1.1`), insieme al sottoinsieme di RDF 1.1 che serve a
dargli senso.

Perché questo: è il più piccolo standard con una suite ufficiale
(`w3c.github.io/rdf-tests/rdf/rdf11/rdf-n-triples/`), e attraversa tutti i
livelli: acquisizione della suite fissata per checksum, modello canonico
dei termini e dei grafi, validazione, serializzatore canonico con andata e
ritorno, esecuzione su SBCL, rapporto di conformità.

Delimitazione:

- Costrutti catalogati: le produzioni della grammatica di N-Triples e i
  termini di RDF 1.1 Concepts che le servono (IRI, nodi vuoti, letterali
  con forma lessicale, IRI di tipo e lingua).
- `:represented`: un grafo si legge e si riscrive in N-Triples canonico, e
  riletto è lo stesso grafo; l'uguaglianza tra grafi è l'isomorfismo con
  nodi vuoti di RDF 1.1 Concepts, non l'uguaglianza di testo.
- `:validated`: la grammatica, la forma degli IRI assoluti (RFC 3987), le
  etichette di lingua.
- `:semantically-implemented`: per uno standard di sintassi la semantica è
  la corrispondenza tra testo e grafo astratto; la dimostrano i test di
  valutazione della suite, che confrontano il grafo letto con quello atteso.
- `:executable` e `:conformant`: build su SBCL e rapporto sulla suite
  ufficiale di N-Triples.
- Subito dopo, il primo ragionatore: l'entailment RDFS di RDF 1.1
  Semantics, che è ciò che AutomaGP usa per primo.

Alternative scartate per ora: OWL 2 RL (richiede prima il modello RDF e il
modulo di acquisizione), SHACL Core (richiede RDF e SPARQL).

## 9. Dipendenze esterne

Verificate sull'indice locale di Quicklisp (distribuzione del 2026-01-01)
il 2026-10-03, senza scaricare nulla. Il core non ne usa nessuna.

| Serve a | Libreria | Su Quicklisp |
| --- | --- | --- |
| Hash SHA-256 per checksum e lock file | `ironclad` | sì |
| Client HTTP | `dexador` o `drakma` | sì, entrambe |
| Parsing XML (RDF/XML, OWL/XML) | `cxml` o `xmls` | sì, entrambe |
| JSON (JSON-LD, risultati SPARQL) | `yason` o `cl-json`; il progetto ha già un codec proprio in `interface/json.lisp` | sì; **`jzon` no** |
| Espressioni regolari (SHACL `sh:pattern`, SPARQL `REGEX`) | `cl-ppcre` | sì |
| Gli altri usati altrove nel progetto | `fiveam`, `hunchentoot` | sì |

Regola proposta: ogni libreria sta nel sistema ASDF che ne ha bisogno e
solo lì (`automa-gp/acquire` per HTTP e hash, il modulo RDF/XML per XML), e
si decide caso per caso se un'implementazione propria, piccola e testata,
costa meno di una dipendenza.

## 10. Sicurezza e policy

Regole per la fase S2: non esiste ancora codice di acquisizione. Quando
c'è, scrive sulla macchina e legge dalla rete: è un effetto esterno, quindi
sta sotto la stessa policy delle altre.

- Un adapter di acquisizione gira solo se la policy dichiara
  `:external-read t`, come la lettura di Wikidata in Fase 2.5. Ogni lettura
  è registrata con istante e richiesta.
- Dalla macchina esce solo ciò che serve a chiedere: un IRI, un
  identificatore. Nessuna affermazione privata esce mai.
- SPARQL Update opera sull'archivio locale. Nessuna scrittura su Wikidata
  o su un endpoint remoto, mai.
- Un artefatto acquisito è immutabile: indirizzato per contenuto, con
  checksum, versione, istante, tipo di contenuto, provenienza. Una pagina
  viva (Wikibase) si fissa per revisione al momento dell'acquisizione.
- Le specifiche e le suite di test restano dove sono pubblicate: il
  repository ne conserva l'indirizzo e il checksum, non una copia, e non
  le ridistribuisce.
- Un'acquisizione che fallisce, o il cui checksum non torna, è una
  `standard-resolution-error` o una `standard-dependency-error`, non un
  file mancante in silenzio.

## 11. Rischi, e cosa si è verificato

- **Dimensione.** Implementare per intero OWL 2, SHACL, SPARQL, JSON-LD e
  il modello Wikibase è un lavoro lungo e grande, in contrasto con
  l'obiettivo di Fase 2 di un nucleo piccolo. La mitigazione è nella
  struttura: un livello alla volta, un solo standard fino a `:conformant`
  prima del successivo, e un registro che dice la verità sullo stato.
  Resta una scelta del proprietario se e quando passare da uno standard al
  successivo.
- **Cosa vuol dire "per intero" per OWL 2.** La specifica lo definisce.
  Il documento OWL 2 Conformance distingue la conformità dei documenti da
  quella degli strumenti, e per un entailment checker prescrive: risultato
  `True`, `False`, `Unknown` o `Error`; `True` solo se la conseguenza vale e
  `False` solo se non vale (obbligatorio); `Unknown` è "SHOULD NOT" ma
  ammesso; deve dichiarare i propri limiti sulle forme lessicali dei
  datatype e quale semantica usa. Cinque classi: Full, DL, EL, QL, RL. Ne
  seguono due cose di progetto: il risultato di un ragionatore è a quattro
  valori, e la correttezza non si negozia mentre la completezza è un
  obiettivo dichiarato, non un'omissione nascosta.
- **Complessità.** Il documento OWL 2 Profiles riporta che EL e RL
  ammettono algoritmi in tempo polinomiale e che QL risponde alle query
  congiuntive in LOGSPACE rispetto ai dati. Per questo il ragionamento
  parte dai profili. La complessità di OWL 2 DL e di Full non è nei testi
  letti: è risultato di letteratura e va citata dalla fonte quando si
  acquisiscono i documenti, non ripetuta a memoria.
- **Versioni.** OWL 2 (2012) precede RDF 1.1 (2014): quali versioni di RDF e
  XSD citi come riferimenti normativi lo deve estrarre l'acquisizione, e
  per questo il registro non dichiara dipendenze di OWL 2 e di SPARQL.
  Quelle di RDF 1.1, N-Triples e SHACL sono invece lette dai loro elenchi di
  riferimenti normativi.
- **Specifiche vive.** Il modello Wikibase è una pagina di wiki che cambia:
  nessuna implementazione può dirsi conforme a un testo che non ha versione
  finché la revisione non è fissata.
- **Casi di test.** Quelli di OWL 2 sono dichiarati incompleti dalla
  specifica (§5), e per altre suite l'URL ufficiale non è stato ancora
  localizzato: il registro lo dice invece di inventarlo.

## 12. Decisioni aperte

Ognuna ha una raccomandazione, e nessuna blocca il lavoro già fatto.

| # | Decisione | Raccomandazione |
| --- | --- | --- |
| D1 | Primo standard da portare a `:conformant` | N-Triples 1.1, poi RDFS (§8) |
| D2 | Dipendenze esterne ammesse e dove | §9: solo in sistemi separati; hash e HTTP in `automa-gp/acquire` |
| D3 | Un'implementazione propria di SHA-256, o `ironclad` | `ironclad`, finché la dimensione del sistema di acquisizione non dice altro |
| D4 | RDF 1.2 come target | non finché è Candidate Recommendation |
| D5 | Dopo il primo standard, l'ordine S1 (altre sintassi) o S2 (acquisizione) | S2, perché il primo standard già chiede una suite acquisita e fissata |
| D6 | Se Fase 2 aspetta S1 e S6 o procede in parallelo con una `statement` provvisoria | aspetta: uno statement provvisorio andrebbe riscritto |
| D7 | Nome della riga di comando e dell'API REPL | `modelc` come nel prompt; prefisso `gp-` per il REPL (§6) |

## 13. Criteri di accettazione della piattaforma

La piattaforma è "a regime" quando questi scenari passano come test e
funzionano a mano, in ordine di fase:

1. **Registro vero.** `modelc standard list` dice per ogni standard livello,
   catalogo, requisiti e verdetto; nessuno ha un livello senza evidenza.
   *(Oggi: sì, con nessuno standard a nessun livello.)*
2. **Nessuna perdita silenziosa.** Un costrutto non implementato in un
   input compare nel rapporto come `not-implemented`, o ferma l'elaborazione
   con una condizione che l'utente ha scelto di superare esplicitamente.
   *(Fatto per il meccanismo; i costrutti arrivano con S1.)*
3. **Chiusura.** `resolve(A)` restituisce l'intera chiusura di `owl:imports`
   in un ordine fisso, e segnala un ciclo con il suo percorso. *(Il motore è
   fatto, sugli standard; sugli IRI arriva con S2.)*
4. **Primo standard.** N-Triples: parser, modello, serializzatore,
   isomorfismo, esecuzione su SBCL, rapporto sulla suite ufficiale.
5. **Tracciabilità.** Da una funzione Lisp al requisito e al test, e dal
   requisito al codice. *(Il meccanismo è fatto.)*
6. **Build riproducibile.** Stesso input e stesso lock danno lo stesso
   modello e lo stesso Lisp generato.
7. **Spiegazione.** Ogni inferenza porta standard, versione, regola o
   assioma e premesse, e `gp-explain` le mostra.
8. **Standard senza toccare il core.** Un secondo standard si aggiunge come
   modulo, senza modificare `core/`.
