# Master Prompt — Framework universale per tavolo di lavoro automatico

Obiettivo: fornire ad AutomaGP un'architettura astratta per orchestrare qualsiasi flusso di lavoro basato su **Acquisizione → Analisi → Output → Invio**.

Questo modello generalizza il tavolo di lavoro come un **Framework di Pipeline a Contesto Dinamico**. Non si limita a un singolo compito: definisce le regole universali affinché l'automa possa combinare operazioni di Lettura, Elaborazione, Generazione Documenti e Distribuzione per obiettivi futuri.

Può essere usato insieme a `docs/PROMPT.md` (specifiche del sistema) e caricato in REPL dopo `(ql:quickload :automa-gp)`.

```lisp
;; =====================================================================
;; MASTER PROMPT: FRAMEWORK UNIVERSALE PER TAVOLO DI LAVORO AUTOMATICO
;; =====================================================================
;; Obiettivo: Fornire ad AutomaGP un'architettura astratta per orchestrare
;; qualsiasi flusso di lavoro basato su: Acquisizione -> Analisi -> Output -> Invio.

(in-package :automa-gp)
(gp-reset)

;; ---------------------------------------------------------------------
;; 1. ABILITATORI INFRASTRUTTURALI (Fatti di sistema sempre attivi)
;; ---------------------------------------------------------------------
(gp-add-fact '(modulo-navigazione pronto))    ; Browser/Scraper API
(gp-add-fact '(motore-inferenza-llm pronto))  ; Modello linguistico per riassunti/analisi
(gp-add-fact '(compilatore-documenti pronto)) ; Generatore PDF/Office
(gp-add-fact '(canale-comunicazione pronto))  ; Client Email/Slack/Telegram

;; ---------------------------------------------------------------------
;; 2. OPERATORI GENERALIZZATI (Le abilità modulari del tavolo di lavoro)
;; ---------------------------------------------------------------------

;; FASE 1: ACQUISIZIONE DATI (Sia da link Web che da documenti locali)
(gp-add-operator
  (make-operator
    :name 'acquisici-sorgente-dati
    :preconditions '((modulo-navigazione pronto) (sorgente-specificata ?target))
    :add-list '((dati-grezzi-acquisiti ?target))
    :delete-list '()))

;; FASE 2: ELABORAZIONE COGNITIVA (Riassunti, traduzioni, estrazione concetti, sentiment)
(gp-add-operator
  (make-operator
    :name 'elabora-contenuto-con-ia
    :preconditions '((motore-inferenza-llm pronto)
                     (dati-grezzi-acquisiti ?target)
                     (tipo-elaborazione ?tipo))
    :add-list '((contenuto-elaborato ?target ?tipo))
    :delete-list '()))

;; FASE 3: GENERAZIONE ARTIFATTI (Creazione di PDF, Markdown, CSV, o file di testo)
(gp-add-operator
  (make-operator
    :name 'genera-documento-output
    :preconditions '((compilatore-documenti pronto)
                     (contenuto-elaborato ?target ?tipo)
                     (formato-richiesto ?formato))
    :add-list '((file-pronto ?target ?formato))
    :delete-list '()))

;; FASE 4: DISTRIBUZIONE E NOTIFICA (Invio mail, salvataggio in cloud, invio su chat)
(gp-add-operator
  (make-operator
    :name 'distribuisci-risultato-finale
    :preconditions '((canale-comunicazione pronto)
                     (file-pronto ?target ?formato)
                     (destinazione-specificata ?dest))
    :add-list '((flusso-completato-con-successo ?target ?dest))
    :delete-list '()))

;; ---------------------------------------------------------------------
;; 3. ISTANZIAZIONE DI UN CASO REALE (Esempio d'uso del Framework)
;; ---------------------------------------------------------------------
;; Cambiando semplicemente queste poche righe, puoi cambiare radicalmente
;; il lavoro dell'automa.
(gp-add-fact '(sorgente-specificata "https://github.com"))
(gp-add-fact '(tipo-elaborazione "riassunto-esecutivo"))
(gp-add-fact '(formato-richiesto "pdf"))
(gp-add-fact '(destinazione-specificata "manager@azienda.com"))

;; ---------------------------------------------------------------------
;; 4. AVVIO DELLA DELIBERAZIONE
;; ---------------------------------------------------------------------
(gp-plan :goals '((flusso-completato-con-successo "https://github.com" "manager@azienda.com")))

(format t "~%--- PIANIFICAZIONE DELIBERATIVA IN CORSO ---~%")
(gp-simulate)
(gp-run)
```

## Perché questa struttura generalizza il tavolo di lavoro

1. **Polimorfismo dei passaggi:** la variabile `?target` può essere un sito web, un file locale o un database. L'operatore di acquisizione non cambia.
2. **Flessibilità dell'IA:** `?tipo` cambia l'istruzione cognitiva al volo (`"riassunto-esecutivo"`, `"traduzione-in-inglese"`, `"analisi-sentiment-commenti"`, …).
3. **Indipendenza dal formato e dal canale:** `?formato` (`"pdf"`, `"csv"`, …) e `?dest` (email, cartella cloud, …) restano fatti di contesto; il pianificatore MEA calcola l'incastro logico.

## Relazione con `docs/PROMPT.md`

- `docs/PROMPT.md` resta la specifica architetturale del sistema deliberativo.
- Questo documento è un **modello di dominio/tavolo di lavoro** caricabile nel REPL: operatori e fatti, non una modifica del nucleo.
- Gli operatori restano **simbolici** finché non esistono adapter concreti (navigazione, LLM, documenti, comunicazione).

## Scenario secondario (stesso framework)

Per riusare gli stessi operatori cambiando solo l'istanza, ad esempio monitoraggio prezzi → report Excel:

```lisp
(gp-reset)
;; ... ri-registrare abilitatori e operatori come sopra ...
(gp-add-fact '(sorgente-specificata "https://esempio.com/prezzi"))
(gp-add-fact '(tipo-elaborazione "monitoraggio-prezzi"))
(gp-add-fact '(formato-richiesto "xlsx"))
(gp-add-fact '(destinazione-specificata "report@azienda.com"))
(gp-plan :goals '((flusso-completato-con-successo
                   "https://esempio.com/prezzi"
                   "report@azienda.com")))
```
