;; =====================================================================
;; TAVOLO DI LAVORO AUTOMATICO - CONFIGURAZIONE PER AUTOMA GP
;; =====================================================================
;;
;; Load after (ql:quickload :automa-gp), e.g.:
;;   (load "examples/tavolo-di-lavoro.lisp")
;; Companion doc: docs/tavolo-di-lavoro.md

(in-package :automa-gp)

;; 1. RESET DEL CONTESTO
;; Cancella la memoria da esecuzioni precedenti per iniziare da zero.
(gp-reset)

;; 2. DEFINIZIONE DEL CONTESTO INIZIALE (Stato Corrente)
;; Comunichiamo all'automa la situazione di partenza.
(gp-add-fact '(url-sorgente "https://esempio.com"))
(gp-add-fact '(connessione-internet attiva))
(gp-add-fact '(servizio-mail pronto))

;; 3. DEFINIZIONE DEGLI OPERATORI (Le leggi e le azioni del tavolo di lavoro)

;; Azione A: Navigazione e scaricamento del testo
(gp-add-operator
  (make-operator
    :name 'naviga-ed-estrai-testo
    :preconditions '((url-sorgente ?url) (connessione-internet attiva))
    :add-list '((testo-estratto-disponibile vero))
    :delete-list '()))

;; Azione B: Elaborazione del testo e creazione del riassunto (tramite LLM esterno)
(gp-add-operator
  (make-operator
    :name 'genera-riassunto-ia
    :preconditions '((testo-estratto-disponibile vero))
    :add-list '((riassunto-pronto vero))
    :delete-list '()))

;; Azione C: Compilazione e creazione del documento PDF
(gp-add-operator
  (make-operator
    :name 'compila-file-pdf
    :preconditions '((riassunto-pronto vero))
    :add-list '((file-pdf-generato vero))
    :delete-list '()))

;; Azione D: Invio del PDF tramite email al destinatario
(gp-add-operator
  (make-operator
    :name 'invia-report-email
    :preconditions '((file-pdf-generato vero) (servizio-mail pronto))
    :add-list '((email-inviata-con-successo vero))
    :delete-list '()))

;; =====================================================================
;; 4. AVVIO DELLA DELIBERAZIONE (PIANIFICAZIONE E SIMULAZIONE)
;; =====================================================================

;; Chiediamo ad AutomaGP di trovare la catena di azioni per raggiungere il traguardo
(gp-plan :goals '((email-inviata-con-successo vero)))

;; Eseguiamo la simulazione interna nella sandbox (senza alterare i fatti reali)
(format t "~%--- AVVIO SIMULAZIONE DI RAGIONAMENTO ---~%")
(gp-simulate)

;; Verifichiamo che i fatti nel contesto reale siano ancora intatti (fase deliberativa pura)
(format t "~%--- STATO DEI FATTI REALI (Invariati dopo simulazione) ---~%")
(gp-facts)

;; Eseguiamo il piano modificando lo stato del contesto
(format t "~%--- ESECUZIONE DEL PIANO DI LAVORO ---~%")
(gp-run)

;; Controlliamo il risultato finale: l'obiettivo deve essere presente tra i fatti
(format t "~%--- STATO DEI FATTI FINALE DOPO ESECUZIONE ---~%")
(gp-facts)
