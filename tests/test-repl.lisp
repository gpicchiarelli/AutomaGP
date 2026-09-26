;;;; tests/test-repl.lisp

(in-package #:automa-gp/tests)

(def-suite repl-suite :in automa-gp-suite)
(in-suite repl-suite)

(test repl-roundtrip
  (gp-reset)
  (is (context-p (gp-context)))
  (gp-context :name 'studio-audio)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (is (fact-p '(device interface-01) (gp-facts)))
  (gp-add-goal 'audio-system-ready)
  (is (equal '(audio-system-ready) (gp-goals)))
  (is (eq :read (gp-mode)))
  (is (eq :plan (gp-mode :plan)))
  (is (state-p (gp-state)))
  (gp-remove-fact '(power-state interface-01 off))
  (is (not (fact-p '(power-state interface-01 off) (gp-facts))))
  (gp-register-action (make-action :name 'noop :effects nil))
  (is (= 1 (length (gp-actions))))
  (gp-reset)
  (is (null (gp-facts))))

(test repl-phase2-rules-and-query
  (gp-reset)
  (gp-context :name 'studio-audio)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 on))
  (gp-add-rule (make-rule :name 'powered-when-on
                          :if '((device ?d) (power-state ?d on))
                          :then '(powered ?d)))
  (is (= 1 (length (gp-rules))))
  (let ((hits (gp-query '(device ?x) :infer nil)))
    (is (= 1 (length hits))))
  (let ((hits (gp-query '(powered ?x))))
    (is (plusp (length hits)))
    (is (equal '(powered interface-01) (getf (first hits) :fact))))
  (multiple-value-bind (all new) (gp-infer :assert t)
    (declare (ignore all))
    (is (fact-p '(powered interface-01) new))
    (is (fact-p '(powered interface-01) (gp-facts))))
  (gp-remove-rule 'powered-when-on)
  (is (null (gp-rules))))

(test deferred-commands-signal
  (signals not-yet-implemented-error (gp-plan))
  (signals not-yet-implemented-error (gp-run))
  (signals not-yet-implemented-error (gp-simulate))
  (signals not-yet-implemented-error (gp-explain)))
