;;;; tests/test-explanation.lisp — Phase 6 deliberative trace & gp-explain

(in-package #:automa-gp/tests)

(def-suite explanation-suite :in automa-gp-suite)
(in-suite explanation-suite)

(defun %studio-ops ()
  (list (make-operator :name 'power-on
                       :preconditions '((device ?d) (power-state ?d off))
                       :add-list '((power-state ?d on))
                       :delete-list '((power-state ?d off)))
        (make-operator :name 'connect
                       :preconditions '((device ?d) (power-state ?d on))
                       :add-list '((connection ?d computer)))))

(test plan-attaches-real-trace
  (clear-trace-session)
  (let* ((facts '((device interface-01) (power-state interface-01 off)))
         (goals '((connection interface-01 computer)))
         (plan (plan-for facts goals (%studio-ops) :context-name 'studio-audio))
         (tr (trace-of plan)))
    (is-true (plan-success plan))
    (is (deliberative-trace-p tr))
    (is (eq :plan (trace-phase tr)))
    (is (eq 'studio-audio (trace-context-name tr)))
    (is (null (find-trace-entries :goal tr))) ; goals recorded as :goals
    (is (plusp (length (find-trace-entries :goals tr))))
    (is (plusp (length (find-trace-entries :difference tr))))
    (is (plusp (length (find-trace-entries :selected-operator tr))))
    (is (plusp (length (find-trace-entries :action tr))))
    (is (plusp (length (find-trace-entries :result tr))))
    (is (plusp (length (find-trace-entries :plan-complete tr))))
    (let ((text (format-explanation tr)))
      (is (search "STUDIO-AUDIO" text))
      (is (search "Selected operator" text))
      (is (search "POWER-ON" text))
      (is (search "CONNECT" text))
      (is (search "Difference" text))
      (is (search "Result" text)))))

(test explain-does-not-invent-without-trace
  (clear-trace-session)
  (multiple-value-bind (text tr) (explain-trace :last)
    (is (null tr))
    (is (search "No deliberative trace" text))))

(test simulate-and-execute-record-traces
  (clear-trace-session)
  (let ((ctx (create-context
              :name 'studio-audio
              :facts '((device interface-01) (power-state interface-01 off)))))
    (dolist (op (%studio-ops)) (register-operator! ctx op))
    (let* ((plan (plan-from-context
                  ctx :goals '((connection interface-01 computer))))
           (sim (simulate-plan plan :context ctx))
           (sim-tr (trace-of sim))
           (run (execute-plan! ctx plan :confirm t))
           (run-tr (trace-of run)))
      (is (deliberative-trace-p sim-tr))
      (is (eq :simulate (trace-phase sim-tr)))
      (is (plusp (length (find-trace-entries :execution-step sim-tr))))
      (is (deliberative-trace-p run-tr))
      (is (eq :execute (trace-phase run-tr)))
      (is (plusp (length (find-trace-entries :action run-tr))))
      (is (eq run-tr (last-trace)))
      (is (>= (length *trace-history*) 2)))))

(test gp-explain-from-plan-and-last
  (gp-reset)
  (gp-context :name 'studio-audio)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (dolist (op (%studio-ops)) (gp-add-operator op))
  (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
    (is (deliberative-trace-p (trace-of plan)))
    (multiple-value-bind (text tr)
        (let ((*standard-output* (make-broadcast-stream)))
          (gp-explain :plan :stream nil))
      (declare (ignore text))
      (is (eq tr (trace-of plan))))
    (gp-simulate)
    (multiple-value-bind (text tr)
        (gp-explain :execution :stream nil)
      (is (deliberative-trace-p tr))
      (is (or (search "Execution" text)
              (search "execution" text)
              (search "SIMULATE" text)))
      (is (eq tr (trace-of (gp-last-execution)))))
    (is (deliberative-trace-p (gp-last-trace)))
    (is (consp (gp-trace-history)))))

(test with-trace-finalizes-chronological
  (clear-trace-session)
  (let ((tr
         (with-trace (:plan :context-name 'x)
           (trace-record :goal :goal '(a 1))
           (trace-record :result :status :ok)
           *current-trace*)))
    (is (not (trace-open-p tr)))
    (is (eq :begin (getf (first (trace-entries tr)) :kind)))
    (is (eq :goal (getf (second (trace-entries tr)) :kind)))
    (is (eq :result (getf (third (trace-entries tr)) :kind)))
    (is (eq tr (last-trace)))))
