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

(test gp-add-goal-refuses-a-fact-that-already-holds
  (gp-clear-memory)
  (gp-reset)
  (gp-add-goal 'audio-system-ready)
  (is (equal '(audio-system-ready) (gp-goals)))
  (gp-add-fact '(power-state interface-01 on))
  (signals error (gp-add-goal '(power-state interface-01 on)))
  (is (equal '(audio-system-ready) (gp-goals)))
  (gp-add-goal '(power-state interface-01 off))
  (gp-add-goal '(power-state interface-01 off))
  (is (= 2 (length (gp-goals))))
  (web-api-handle :post "/api/add-fact"
                  (list :fact '("connection" "interface-01" "computer")))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/add-goal"
                      (list :goal '("connection" "interface-01" "computer")))
    (is (= 400 code))
    (is (search "already holds" (getf body :error))))
  (is (= 2 (length (gp-goals)))))
