;;;; tests/test-autonomy.lisp — Phase 12 controlled autonomous operation

(in-package #:automa-gp/tests)

(def-suite autonomy-suite :in automa-gp-suite)
(in-suite autonomy-suite)

(defun %auto-studio ()
  (gp-clear-memory)
  (gp-reset)
  (gp-context :name 'studio-audio)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (gp-add-operator
   (make-operator :name 'connect
                  :preconditions '((device ?d) (power-state ?d on))
                  :add-list '((connection ?d computer))))
  (gp-add-goal '(connection interface-01 computer))
  (gp-context))

(test autonomy-read-observes-without-planning
  (%auto-studio)
  (let ((before (copy-tree (gp-facts)))
        (summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :read))))
    (is (eq :halted (getf summary :status)))
    (is (eq :authority-read (getf summary :halt)))
    (is (equal before (gp-facts)))
    (is (null (getf summary :plan)))
    (is (eq summary (gp-last-autonomy)))))

(test autonomy-simulate-achieves-without-mutating
  (%auto-studio)
  (let ((before (copy-tree (gp-facts)))
        (summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :simulate
                                                :learn t))))
    (is (eq :done (getf summary :status)))
    (is (eq :completed (getf summary :halt)))
    (is (eq :simulate (getf summary :authority)))
    (is (equal before (gp-facts)))
    (is-false (fact-p '(connection interface-01 computer) (gp-facts)))
    (is (getf (getf summary :plan) :success))
    (is (= 2 (getf (getf summary :plan) :length)))
    (is (getf (getf summary :execution) :success))
    (is (eq :simulate (getf (getf summary :execution) :mode)))
    (is-false (fact-p '(connection interface-01 computer)
                      (knowledge-memory-facts (ensure-knowledge-memory))))))

(test autonomy-execute-mutates-and-learns
  (%auto-studio)
  (let ((summary (gp-autonomous-loop
                  :policy (make-autonomy-policy :authority :execute
                                                :learn t
                                                :auto-confirm t))))
    (is (eq :done (getf summary :status)))
    (is (= 1 (getf summary :iterations)))
    (is-true (fact-p '(connection interface-01 computer) (gp-facts)))
    (is-true (fact-p '(power-state interface-01 on) (gp-facts)))
    (is-true (fact-p '(connection interface-01 computer)
                     (knowledge-memory-facts (ensure-knowledge-memory))))))

(test autonomy-execute-halts-without-confirmation
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(ready x))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((ready x))
                  :add-list '((sealed x))
                  :reversible nil
                  :risk :high))
  (gp-add-goal '(sealed x))
  (let ((summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :execute
                                                :auto-confirm nil))))
    (is (eq :halted (getf summary :status)))
    (is (eq :confirmation-required (getf summary :halt)))
    (is-false (fact-p '(sealed x) (gp-facts))))
  (let ((summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :execute
                                                :auto-confirm t
                                                :learn t))))
    (is (eq :done (getf summary :status)))
    (is-true (fact-p '(sealed x) (gp-facts)))))

(test autonomy-no-goals-and-impossible-plan-halt
  (gp-clear-memory)
  (gp-reset)
  (let ((summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :simulate))))
    (is (eq :halted (getf summary :status)))
    (is (eq :no-goals (getf summary :halt))))
  (gp-add-goal '(missing thing))
  (let ((summary (gp-autonomous-loop
                  :policy (make-autonomy-policy :authority :simulate
                                                :max-steps 4)
                  :max-steps 4)))
    (is (eq :halted (getf summary :status)))
    (is (eq :plan-failed (getf summary :halt)))
    (is (= 1 (getf summary :iterations)))))

(test autonomy-reacts-to-pending-document-event
  (gp-clear-memory)
  (gp-reset)
  (gp-load-domain :documents :seed-demo t)
  (gp-emit '(automa-gp::file-created "brief.pdf"))
  (is (= 1 (length (pending-events (gp-context)))))
  (let ((summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :simulate
                                                :react-events t))))
    (is (eq :done (getf summary :status)))
    (is (null (pending-events (gp-context))))
    (is-true (fact-p '(automa-gp::document-source "brief.pdf") (gp-facts)))
    (is-false (fact-p '(automa-gp::document-classified "brief.pdf"
                                                       automa-gp::report)
                      (gp-facts)))
    (is (getf (getf summary :plan) :success))))

(test web-api-autonomy-step
  (%auto-studio)
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/autonomy")
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (is (eq :simulate (getf (getf body :policy) :authority))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/autonomy/step"
                      '(:authority "simulate"))
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (is (eq :done (getf (getf body :autonomy) :status)))
    (is-false (fact-p '(connection interface-01 computer) (gp-facts)))))
