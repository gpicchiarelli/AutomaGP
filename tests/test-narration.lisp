;;;; tests/test-narration.lisp — Italian narration reads only the recorded trace

(in-package #:automa-gp/tests)

(def-suite narration-suite :in automa-gp-suite)
(in-suite narration-suite)

(test narrate-trace-uses-recorded-operators-only
  (clear-trace-session)
  (let* ((facts '((device interface-01) (power-state interface-01 off)))
         (goals '((connection interface-01 computer)))
         (ops (list (make-operator :name 'power-on
                                   :preconditions '((device ?d) (power-state ?d off))
                                   :add-list '((power-state ?d on))
                                   :delete-list '((power-state ?d off)))
                    (make-operator :name 'connect
                                   :preconditions '((device ?d) (power-state ?d on))
                                   :add-list '((connection ?d computer)))))
         (plan (plan-for facts goals ops :context-name 'studio-audio)))
    (multiple-value-bind (text nodes) (narrate-trace (trace-of plan))
      (is (search "POWER-ON" text))
      (is (search "CONNECT" text))
      (is (search "Manca" text))
      (is (search "Scelgo" text))
      (is (not (search "QUICKLIME" text)))
      (is (find :missing nodes :key (lambda (n) (getf n :tone))))
      (is (find :action nodes :key (lambda (n) (getf n :tone)))))))

(test narrate-without-trace-does-not-invent
  (clear-trace-session)
  (multiple-value-bind (text nodes) (gp-narrate :last)
    (is (null nodes))
    (is (search "Non c'è ancora un ragionamento registrato" text))
    (is (not (search "POWER-ON" text)))))
