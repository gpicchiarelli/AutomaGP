;;;; tests/test-goals.lisp

(in-package #:automa-gp/tests)

(def-suite goals-suite :in automa-gp-suite)
(in-suite goals-suite)

(test add-remove-goals
  (let ((ctx (create-context :name 'g)))
    (add-goal! ctx 'audio-system-ready)
    (add-goal! ctx 'audio-system-ready)
    (is (= 1 (length (goals-of ctx))))
    (is-true (goal-active-p ctx 'audio-system-ready))
    (remove-goal! ctx 'audio-system-ready)
    (is (null (goals-of ctx)))))
