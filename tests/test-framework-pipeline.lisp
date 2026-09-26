;;;; tests/test-framework-pipeline.lisp — smoke for Dynamic Context Pipeline

(in-package #:automa-gp/tests)

(def-suite framework-pipeline-suite :in automa-gp-suite)
(in-suite framework-pipeline-suite)

(test framework-github-manager-four-operators
  "GitHub/manager instance yields the four generalized operators in order.
Variable bindings (?target ?tipo ?formato ?dest) unify across MEA steps."
  (gp-reset)
  (gp-add-fact '(modulo-navigazione pronto))
  (gp-add-fact '(motore-inferenza-llm pronto))
  (gp-add-fact '(compilatore-documenti pronto))
  (gp-add-fact '(canale-comunicazione pronto))
  (gp-add-operator
   (make-operator
    :name 'acquisici-sorgente-dati
    :preconditions '((modulo-navigazione pronto) (sorgente-specificata ?target))
    :add-list '((dati-grezzi-acquisiti ?target))))
  (gp-add-operator
   (make-operator
    :name 'elabora-contenuto-con-ia
    :preconditions '((motore-inferenza-llm pronto)
                     (dati-grezzi-acquisiti ?target)
                     (tipo-elaborazione ?tipo))
    :add-list '((contenuto-elaborato ?target ?tipo))))
  (gp-add-operator
   (make-operator
    :name 'genera-documento-output
    :preconditions '((compilatore-documenti pronto)
                     (contenuto-elaborato ?target ?tipo)
                     (formato-richiesto ?formato))
    :add-list '((file-pronto ?target ?formato))))
  (gp-add-operator
   (make-operator
    :name 'distribuisci-risultato-finale
    :preconditions '((canale-comunicazione pronto)
                     (file-pronto ?target ?formato)
                     (destinazione-specificata ?dest))
    :add-list '((flusso-completato-con-successo ?target ?dest))))
  (gp-add-fact '(sorgente-specificata "https://github.com"))
  (gp-add-fact '(tipo-elaborazione "riassunto-esecutivo"))
  (gp-add-fact '(formato-richiesto "pdf"))
  (gp-add-fact '(destinazione-specificata "manager@azienda.com"))
  (let* ((plan (gp-plan :goals '((flusso-completato-con-successo
                                  "https://github.com"
                                  "manager@azienda.com"))))
         (names (mapcar (lambda (s) (getf s :operator)) (plan-steps plan))))
    (is-true (plan-success plan))
    (is (equal '(acquisici-sorgente-dati
                 elabora-contenuto-con-ia
                 genera-documento-output
                 distribuisci-risultato-finale)
               names))
    (is (equal "https://github.com"
               (cdr (assoc '?target (getf (first (plan-steps plan)) :bindings)
                           :test #'eq))))
    (let ((sim (gp-simulate)))
      (is-true (execution-success sim)))
    (let ((run (gp-run)))
      (is-true (execution-success run))
      (is (fact-p '(flusso-completato-con-successo
                    "https://github.com"
                    "manager@azienda.com")
                  (gp-facts))))))
