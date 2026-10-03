# AutomaGP — Semantic Standard Implementation Platform

Specifica normativa del sottosistema semantico. Il testo che segue è quello
scritto dal proprietario del progetto, conservato alla lettera dal
2026-10-03 (come `docs/PROMPT.md`); sono stati tolti dai collegamenti i
parametri di tracciamento e aggiunti i livelli di intestazione. Non è
linted. Come questo prompt si integra con `docs/PROMPT.md` e
`docs/PROMPT-FASE-2.md`, cosa esiste già e cosa no, e le decisioni ancora
aperte stanno in [`piattaforma-semantica.md`](piattaforma-semantica.md).

---

Sì. A questo punto il prompt precedente è ancora troppo “compiler-oriented”. Il requisito centrale deve essere: lo standard entra nel sistema come specifica completa e ne esce una implementazione Common Lisp verificabile.

Non dobbiamo quindi dire “supporta OWL” intendendo “legge alcune classi OWL”. OWL 2 ha una specifica strutturale, Direct Semantics e RDF-Based Semantics distinte; il sistema deve trattarle come parte dello standard da implementare. [W3C](https://www.w3.org/TR/owl-overview/) Analogamente, Wikidata ha un proprio modello con statement, qualifier, reference e rank, quindi va implementato come modello semantico completo, non ridotto a triple. [Wikidata](https://www.wikidata.org/wiki/Help%3AStatements/en)

Questo sarebbe il prompt definitivo che userei:

## MASTER PROMPT

### AutomaGP Semantic Standard Implementation Platform

### Missione

Progettare e implementare un sistema Common Lisp/SBCL nel quale AutomaGP possa acquisire, comprendere, memorizzare, implementare e utilizzare standard semantici completi.

Il sistema deve essere contemporaneamente:

* Semantic Knowledge Platform
* Standard Implementation Engine
* Ontology/Knowledge Manager
* Reasoning Engine
* Behavior Model
* Planning substrate per AutomaGP
* Common Lisp Code Generator
* Conformance/Test Engine

L'obiettivo fondamentale è:

```
STANDARD COMPLETO
        ↓
ACQUISIZIONE
        ↓
RISOLUZIONE DIPENDENZE
        ↓
MODELLO CANONICO
        ↓
SEMANTICA FORMALE
        ↓
IMPLEMENTAZIONE COMMON LISP
        ↓
SBCL
        ↓
CONFORMANCE TESTS
        ↓
STANDARD IMPLEMENTATO
```

Non costruire un semplice ontology-to-code generator.

Costruire un sistema capace di implementare standard semantici in Common Lisp.

### 1. Principio fondamentale

Il sistema deve distinguere chiaramente quattro livelli:

```
SPECIFICATION
    ↓
SEMANTIC MODEL
    ↓
IMPLEMENTATION
    ↓
EXECUTION
```

Lo standard originale non deve essere sostituito da una IR semplificata.

Deve essere conservato.

La IR è una rappresentazione derivata utilizzata per implementazione, ottimizzazione e code generation.

### 2. Full Standard Implementation

Quando il sistema dichiara di supportare uno standard, deve implementare lo standard nella sua interezza prevista dal progetto, non soltanto un sottoinsieme implicito.

Non è accettabile:

```
unsupported feature → ignore
```

Deve invece produrre:

```
implemented
partially implemented
not implemented
invalid
```

con diagnostica esplicita.

Ogni costrutto dello standard deve essere catalogato.

Esempio:

```
OWL 2
├── syntax
├── structural specification
├── axioms
├── class expressions
├── property expressions
├── datatypes
├── restrictions
├── annotations
├── imports
├── Direct Semantics
├── RDF-Based Semantics
├── profiles
└── conformance
```

L'implementazione deve essere costruita sulla specifica normativa, non su una semplificazione arbitraria.

### 3. Standard Registry

Creare uno Standard Registry.

Ogni standard deve avere:

```
identifier
name
version
release
official specification
dependencies
normative documents
test suites
implementation status
conformance status
```

Esempio:

```
standard: OWL 2
version: ...
specification:
  structural
  direct-semantics
  rdf-based-semantics
```

Il registry deve permettere ad AutomaGP di sapere:

```
quali standard esistono
quali versioni sono disponibili
quali dipendenze richiedono
quali sono implementati
quali sono parzialmente implementati
quali test hanno superato
```

### 4. Standard Acquisition Engine

Il sistema deve essere capace di acquisire automaticamente gli standard.

Le sorgenti possono essere:

```
HTTP/HTTPS
local filesystem
Git repositories
package registries
official specification repositories
ontology registries
SPARQL endpoints
knowledge-base endpoints
```

L'acquisizione deve essere versionata e riproducibile.

Ogni artefatto deve avere:

```
source
IRI/URI
version
retrieval timestamp
checksum
content type
dependency information
provenance
```

### 5. Ontology Resolver

Implementare un resolver completo per le dipendenze semantiche.

Deve supportare:

```
IRI resolution
owl:imports
ontology version
version IRI
catalog mappings
local mirrors
remote resources
cache
dependency graph
cycle detection
checksum verification
```

Il sistema deve poter trasformare:

```
ontology A
   ↓ imports
ontology B
   ↓ imports
ontology C
   ↓ imports
ontology D
```

in una dependency graph completa.

Deve essere possibile eseguire:

```
resolve(A)
```

e ottenere l'intera closure delle dipendenze.

### 6. Immutable Semantic Archive

Conservare sempre il materiale originale.

Il sistema deve mantenere:

```
original source
parsed representation
canonical representation
derived representation
implementation
tests
```

Non distruggere l'informazione originale durante la compilazione.

Il sistema deve poter ricostruire:

```
standard → model → implementation
```

e verificare quale parte del codice deriva da quale elemento della specifica.

### 7. Canonical Semantic Model

Creare un modello semantico canonico indipendente dal backend Common Lisp.

Deve essere in grado di rappresentare:

```
IRI
RDF resources
literals
datatypes
graphs
named graphs
classes
individuals
properties
axioms
restrictions
annotations
rules
constraints
imports
metadata
provenance
versions
```

Il modello canonico deve essere sufficientemente espressivo da rappresentare gli standard senza perdita semantica.

### 8. OWL

OWL deve essere implementato come linguaggio semantico completo, non come schema generator.

Implementare progressivamente:

```
OWL ontology structure
classes
individuals
object properties
data properties
annotation properties
class expressions
property expressions
axioms
restrictions
cardinality
property characteristics
property chains
equivalence
disjointness
keys
datatypes
annotations
imports
ontology metadata
```

Implementare separatamente:

```
OWL 2 Direct Semantics
OWL 2 RDF-Based Semantics
```

Non trattare le due semantiche come equivalenti.

Supportare esplicitamente la distinzione:

```
OWL 2 DL
OWL 2 Full
OWL profiles
```

e implementare i relativi controlli di validità/conformità.

### 9. RDF

RDF deve essere un componente fondamentale del sistema.

Implementare:

```
IRI
blank nodes
literals
datatypes
triples
graphs
datasets
named graphs
RDF vocabulary
RDF serialization
RDF parsing
RDF serialization
```

Supportare almeno:

```
Turtle
RDF/XML
JSON-LD
N-Triples
N-Quads
```

La rappresentazione interna non deve dipendere da una singola serializzazione.

### 10. SHACL

SHACL deve essere implementato come sistema completo di constraints.

Rappresentare:

```
NodeShape
PropertyShape
targets
property paths
cardinality
datatype
class
node kind
patterns
enumerations
string constraints
comparison constraints
logical constraints
qualified constraints
severity
messages
custom constraints
```

Separare:

```
SHACL model
validation
constraint evaluation
SHACL rules
inference
```

Una SHACL constraint deve poter essere trasformata in una implementazione Common Lisp equivalente.

Esempio concettuale:

```
SHACL
   ↓
constraint semantics
   ↓
Common Lisp validator
```

### 11. SPARQL

Prevedere un SPARQL engine come componente separato.

Implementare progressivamente:

```
SELECT
ASK
CONSTRUCT
DESCRIBE
WHERE
FILTER
OPTIONAL
UNION
GRAPH
VALUES
aggregates
property paths
updates
```

Il query engine deve operare sul Semantic Knowledge Store.

In futuro deve poter operare anche su knowledge source remoti.

### 12. Wikidata

Wikidata deve essere trattata come knowledge model completo, non come semplice RDF endpoint.

Rappresentare:

```
Items
Properties
Statements
Claims
Snaks
Values
Qualifiers
References
Ranks
Labels
Descriptions
Aliases
Sitelinks
Unknown values
No-value values
```

Preservare la struttura delle statement e la loro provenienza.

Il sistema non deve trasformare semplicemente:

```
Q42 P31 Q5
```

in una tripla perdendo:

```
qualifiers
references
rank
value semantics
```

La rappresentazione interna deve poter mantenere l'informazione completa prevista dal modello Wikidata.

### 13. Knowledge Source Abstraction

Implementare una API comune per le fonti di conoscenza:

```
(search-knowledge ...)
(get-entity ...)
(get-statements ...)
(query-knowledge ...)
(resolve-entity ...)
```

Backend iniziali:

```
local RDF
SPARQL
Wikidata
ontology store
remote knowledge source
```

AutomaGP non deve conoscere i dettagli tecnici delle singole sorgenti.

### 14. Reasoning Engine

Implementare un reasoning layer.

Supportare progressivamente:

```
RDF entailment
RDFS entailment
OWL entailment
OWL Direct Semantics reasoning
OWL RDF-Based reasoning
SHACL inference
rule-based inference
```

Separare rigorosamente:

```
asserted fact
inferred fact
derived fact
hypothesis
observation
```

Ogni inferenza deve poter essere spiegata.

Esempio:

```
Fact A
+
Fact B
+
Rule R
=
Inferred Fact C
```

### 15. Constraint Engine

I vincoli devono essere oggetti di prima classe.

Il sistema deve poter rappresentare:

```
constraint
scope
condition
severity
message
source
provenance
```

e deve poter verificare:

```
model validity
data validity
state validity
action validity
plan validity
```

### 16. Semantic World Model

Costruire un modello persistente del mondo:

```
Semantic World Model
│
├── Standards
├── Ontologies
├── Classes
├── Properties
├── Datatypes
├── Individuals
├── Statements
├── Axioms
├── Constraints
├── Rules
├── Inferences
├── Observations
├── World State
├── Behaviors
├── Actions
├── Goals
├── Plans
└── Provenance
```

Questo è il modello utilizzato da AutomaGP.

### 17. Behavior Model

Oltre alla conoscenza descrittiva, il sistema deve rappresentare comportamenti.

Un comportamento deve poter descrivere:

```
action
parameters
preconditions
effects
state transitions
constraints
resources
cost
duration
capabilities
```

Esempio:

```
(action approve-order
  :parameters (...)
  :preconditions (...)
  :effects (...))
```

Il behavior model deve essere indipendente da Common Lisp.

### 18. AutomaGP

AutomaGP deve operare sopra il Semantic World Model.

Deve poter:

```
observe
query
reason
infer
evaluate constraints
select goals
plan
execute actions
observe effects
update world state
explain decisions
```

AutomaGP non deve avere conoscenza hard-coded di:

```
FIBO
Wikidata
Schema.org
OWL
specific business domains
```

Questa conoscenza deve provenire dal Semantic World Model e dagli standard implementati.

### 19. Planning

Il planner deve utilizzare:

```
current state
ontology
constraints
available actions
preconditions
effects
goals
resources
knowledge
```

per costruire piani validi.

Prima di eseguire un piano deve poter verificare:

```
semantic validity
constraint validity
preconditions
resource requirements
expected effects
```

### 20. Implementation Model

Creare una fase esplicita:

```
Canonical Semantic Model
        ↓
Implementation Model
```

L'Implementation Model descrive come implementare in Common Lisp i costrutti dello standard.

Non assumere automaticamente:

```
OWL Class = CLOS class
OWL Property = slot
SHACL constraint = simple predicate
Wikidata statement = RDF triple
```

Queste possono essere strategie di implementazione soltanto quando semanticamente corrette.

### 21. Common Lisp Implementation Backend

Common Lisp è il primo target ufficiale.

Target:

```
SBCL
```

Il backend deve generare:

```
packages
types
classes
generic functions
methods
conditions
validators
reasoners
query engines
rules
actions
state transitions
serialization
deserialization
runtime support
```

Il codice deve essere idiomatico Common Lisp.

Utilizzare S-expressions come rappresentazione del codice.

Non generare codice tramite concatenazione indiscriminata di stringhe.

### 22. Runtime

Il sistema deve possedere un runtime Common Lisp capace di fornire le primitive necessarie agli standard implementati.

Separare:

```
standard implementation
runtime
generated code
compiler
```

Il runtime può fornire:

```
semantic objects
graph operations
reasoning
validation
query execution
provenance
actions
world state
```

### 23. Conformance Engine

Questo è un componente fondamentale.

Ogni standard implementato deve avere:

```
Specification
Test Suite
Implementation
Conformance Runner
Report
```

Pipeline:

```
Official Standard
       ↓
Normative Requirements
       ↓
Conformance Tests
       ↓
Common Lisp Implementation
       ↓
SBCL
       ↓
Test Runner
       ↓
PASS / FAIL / PARTIAL
```

Non dichiarare uno standard “implementato” sulla sola base della compilazione del codice.

### 24. Specification-to-Test Pipeline

Quando possibile, derivare automaticamente test dalla specifica.

Il sistema deve poter mantenere:

```
requirement ID
specification section
semantic rule
test
implementation
source location
```

Esempio:

```
REQ-OWL-XXX
    ↓
OWL specification
    ↓
semantic requirement
    ↓
test
    ↓
Lisp implementation
```

### 25. Traceability

Ogni livello deve essere collegabile al precedente:

```
Standard
   ↓
Requirement
   ↓
Semantic construct
   ↓
Canonical Model
   ↓
Implementation Model
   ↓
Lisp definition
   ↓
Test
```

Deve essere possibile rispondere:

```
"Quale parte dello standard implementa questa funzione Lisp?"

"Quale codice implementa questo axiom?"

"Quale test verifica questa semantica?"

"Perché questa inferenza è stata prodotta?"
```

### 26. Versioning

Tutto deve essere versionato:

```
standard
ontology
knowledge source
schema
implementation
runtime
generated code
test suite
```

Una modifica a uno standard deve generare una nuova implementation target.

Supportare:

```
standard@version
ontology@version
implementation@version
```

### 27. Reproducible Builds

Una build deve essere riproducibile.

Utilizzare:

```
lock files
content hashes
fixed versions
dependency graph
deterministic generation
```

Input identico + lock identico deve produrre:

```
identical semantic model
identical implementation
identical generated Lisp
```

### 28. Error Handling

Nessuna perdita semantica silenziosa.

Errori distinti:

```
parse error
resolution error
dependency error
semantic error
unsupported construct
implementation error
conformance failure
runtime error
```

Ogni errore deve contenere, quando disponibile:

```
code
message
source
location
standard
version
semantic construct
suggestion
```

### 29. CLI

Prevedere una CLI:

```
modelc standard fetch OWL
modelc standard install OWL
modelc ontology fetch FIBO
modelc ontology resolve model.ttl
modelc ontology imports model.ttl
modelc knowledge query wikidata ...
modelc validate model.ttl
modelc reason model.ttl
modelc dump-model model.ttl
modelc dump-ir model.ttl
modelc generate model.ttl
modelc build model.ttl
modelc conform OWL
```

AutomaGP deve poter utilizzare le stesse capacità tramite API/tool interface.

### 30. API per AutomaGP

Fornire primitive semantiche ad alto livello:

```
(find-class ...)
(find-property ...)
(find-individual ...)
(find-statements ...)
(query ...)
(infer ...)
(validate ...)
(explain ...)
(find-actions ...)
(check-preconditions ...)
(apply-action ...)
(get-world-state ...)
(update-world-state ...)
(plan ...)
```

AutomaGP deve ragionare tramite queste primitive, non manipolare direttamente i file RDF/OWL.

### 31. Package Architecture

Organizzare il progetto in moduli indipendenti:

```
src/
├── rdf/
├── rdfs/
├── owl/
│   ├── syntax/
│   ├── model/
│   ├── direct-semantics/
│   ├── rdf-semantics/
│   └── reasoning/
├── shacl/
├── sparql/
├── wikidata/
├── standards/
├── ontology/
├── registry/
├── resolver/
├── cache/
├── provenance/
├── knowledge/
├── reasoning/
├── constraints/
├── world-model/
├── behavior/
├── planning/
├── implementation/
├── ir/
├── compiler/
├── backend/
│   └── common-lisp/
├── runtime/
├── conformance/
├── cli/
└── automagp/
```

### 32. Principio di estendibilità

L'architettura deve permettere di aggiungere nuovi standard senza modificare il core di AutomaGP.

Esempio:

```
OWL
SHACL
RDF
Wikidata
FIBO
Schema.org
BPMN
DMN
CMMN
...
```

Ogni standard deve essere un modulo implementabile attraverso un'interfaccia comune:

```
Standard Definition
Parser
Canonical Model
Semantics
Validator
Reasoner
Serializer
Implementation Backend
Conformance Suite
```

### 33. Nessun dominio applicativo hard-coded

Non costruire:

```
CRM
ERP
gestionale
e-commerce
banking application
```

come obiettivo del core.

Questi devono essere conseguenze dell'utilizzo di:

```
standard
ontologies
knowledge
behaviors
constraints
plans
```

Il sistema deve poter generare applicazioni diverse a partire da modelli diversi.

### 34. Prima implementazione reale

La prima implementazione deve essere piccola ma completa rispetto al sotto-standard scelto.

Non creare un OWL parser incompleto e dichiararlo “supporto OWL”.

Scegliere un primo target formalmente delimitato.

Implementare:

```
parser
canonical model
semantics
reasoning
validation
Common Lisp implementation
SBCL runtime
conformance tests
```

end-to-end.

Solo dopo estendere la copertura.

### 35. Roadmap

Phase 1 — Semantic foundation

```
RDF
RDFS
graph model
IRI
literals
datatypes
serialization
canonical store
```

Phase 2 — Ontology infrastructure

```
ontology resolver
owl:imports
registry
cache
versions
provenance
lock files
```

Phase 3 — OWL implementation

```
OWL structural model
OWL semantics
reasoning
conformance
Common Lisp implementation
```

Phase 4 — SHACL

```
constraints
validation
rules
inference
Common Lisp implementation
conformance
```

Phase 5 — SPARQL

```
query engine
updates
property paths
remote endpoints
```

Phase 6 — Wikidata

```
items
properties
statements
qualifiers
references
ranks
knowledge-source adapter
```

Phase 7 — Behavior

```
actions
preconditions
effects
state
resources
behavior semantics
```

Phase 8 — AutomaGP

```
world model
reasoning
planning
execution
explanation
state updates
```

Phase 9 — Full semantic compilation

```
standard
    ↓
semantic implementation
    ↓
Common Lisp
    ↓
SBCL
    ↓
conformance
    ↓
usable capability of AutomaGP
```

### 36. Definizione di "supporto"

Il sistema deve distinguere rigorosamente:

```
PARSED
```

Il formato può essere letto.

```
REPRESENTED
```

Il costrutto può essere conservato senza perdita.

```
VALIDATED
```

Il costrutto può essere verificato secondo le regole dello standard.

```
SEMANTICALLY IMPLEMENTED
```

Il sistema implementa la semantica prevista.

```
EXECUTABLE
```

La semantica è eseguibile in Common Lisp/SBCL.

```
CONFORMANT
```

L'implementazione supera i test di conformità disponibili.

Non confondere questi livelli.

### 37. Regola assoluta

Il progetto deve sempre preferire:

```
complete semantic representation
```

a:

```
convenient simplified representation
```

e:

```
formal semantics
```

a:

```
heuristic interpretation
```

e:

```
conformance
```

a:

```
"sembra funzionare"
```

### 38. Obiettivo finale

L'obiettivo finale del progetto è ottenere un sistema nel quale:

```
             STANDARD
                 │
                 ▼
        STANDARD ACQUISITION
                 │
                 ▼
       DEPENDENCY RESOLUTION
                 │
                 ▼
       COMPLETE SEMANTIC MODEL
                 │
          ┌──────┴──────┐
          │             │
          ▼             ▼
      REASONING      CONSTRAINTS
          │             │
          └──────┬──────┘
                 ▼
          WORLD MODEL
                 │
                 ▼
             AUTOMA GP
                 │
          ┌──────┴──────┐
          │             │
       PLANNING      BEHAVIOR
          │             │
          └──────┬──────┘
                 ▼
            IMPLEMENTATION
                 │
                 ▼
           COMMON LISP
                 │
                 ▼
                SBCL
                 │
                 ▼
          CONFORMANCE TESTS
```

Il risultato non deve essere semplicemente codice Lisp generato.

Il risultato deve essere una implementazione Common Lisp eseguibile e verificabile dello standard, utilizzabile da AutomaGP come capacità semantica del proprio modello del mondo.

Il principio guida dell'intero progetto è:

Acquisire lo standard. Preservarne la semantica. Implementarlo in Common Lisp. Verificarne la conformità. Renderlo utilizzabile da AutomaGP.

Non costruire scorciatoie che riducano lo standard a ciò che è conveniente per il code generator.

Questa volta il centro del progetto è molto più netto: Common Lisp non è il formato di output di un ontology importer; è il linguaggio nel quale implementiamo gli standard.

E la distinzione `PARSED → REPRESENTED → VALIDATED → SEMANTICALLY IMPLEMENTED → EXECUTABLE → CONFORMANT` la terrei assolutamente nel progetto: impedisce che tra qualche mese “supportiamo OWL” significhi in realtà “leggiamo `owl:Class` e generiamo `defclass`”. OWL 2 stesso distingue struttura e semantiche, quindi questa separazione non è solo organizzativa: riflette la struttura reale dello standard. [W3C](https://www.w3.org/TR/owl-overview/)
