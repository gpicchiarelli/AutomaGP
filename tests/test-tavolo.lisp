;;;; tests/test-tavolo.lisp — smoke test for examples/tavolo-di-lavoro.lisp

(in-package #:automa-gp/tests)

(def-suite tavolo-suite :in automa-gp-suite)
(in-suite tavolo-suite)

(test tavolo-di-lavoro-four-step-plan
  "Workbench operator chain yields the four steps in MEA order."
  (gp-reset)
  (gp-add-fact '(url-sorgente "https://esempio.com"))
  (gp-add-fact '(connessione-internet attiva))
  (gp-add-fact '(servizio-mail pronto))
  (gp-add-operator
   (make-operator
    :name 'naviga-ed-estrai-testo
    :preconditions '((url-sorgente ?url) (connessione-internet attiva))
    :add-list '((testo-estratto-disponibile vero))
    :delete-list '()))
  (gp-add-operator
   (make-operator
    :name 'genera-riassunto-ia
    :preconditions '((testo-estratto-disponibile vero))
    :add-list '((riassunto-pronto vero))
    :delete-list '()))
  (gp-add-operator
   (make-operator
    :name 'compila-file-pdf
    :preconditions '((riassunto-pronto vero))
    :add-list '((file-pdf-generato vero))
    :delete-list '()))
  (gp-add-operator
   (make-operator
    :name 'invia-report-email
    :preconditions '((file-pdf-generato vero) (servizio-mail pronto))
    :add-list '((email-inviata-con-successo vero))
    :delete-list '()))
  (let* ((plan (gp-plan :goals '((email-inviata-con-successo vero))))
         (names (mapcar (lambda (s) (getf s :operator)) (plan-steps plan))))
    (is-true (plan-success plan))
    (is (equal '(naviga-ed-estrai-testo
                 genera-riassunto-ia
                 compila-file-pdf
                 invia-report-email)
               names))
    (is (deliberative-trace-p (trace-of plan)))
    (let ((sim (gp-simulate)))
      (is-true (execution-success sim))
      (is (fact-p '(connessione-internet attiva) (gp-facts)))
      (is (not (fact-p '(email-inviata-con-successo vero) (gp-facts)))))
    (let ((run (gp-run)))
      (is-true (execution-success run))
      (is (fact-p '(email-inviata-con-successo vero) (gp-facts))))))
