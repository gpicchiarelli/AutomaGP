;; =====================================================================
;; MASTER PROMPT: FRAMEWORK UNIVERSALE PER TAVOLO DI LAVORO AUTOMATICO
;; =====================================================================
;; Obiettivo: Fornire ad AutomaGP un'architettura astratta per orchestrare
;; qualsiasi flusso di lavoro basato su: Acquisizione -> Analisi -> Output -> Invio.
;;
;; Load after (ql:quickload :automa-gp), e.g.:
;;   (load "examples/framework-pipeline-contesto.lisp")
;; Companion doc: docs/framework-pipeline-contesto.md

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
