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

(test deferred-commands-signal
  (signals not-yet-implemented-error (gp-rules))
  (signals not-yet-implemented-error (gp-plan))
  (signals not-yet-implemented-error (gp-run))
  (signals not-yet-implemented-error (gp-simulate))
  (signals not-yet-implemented-error (gp-explain))
  (signals not-yet-implemented-error (gp-query '(device ?x))))
