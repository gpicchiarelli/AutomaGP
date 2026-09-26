;;;; tests/test-executor.lisp

(in-package #:automa-gp/tests)

(def-suite executor-suite :in automa-gp-suite)
(in-suite executor-suite)

(defun studio-ops ()
  (list (make-operator :name 'power-on
                       :preconditions '((device ?d) (power-state ?d off))
                       :add-list '((power-state ?d on))
                       :delete-list '((power-state ?d off)))
        (make-operator :name 'connect
                       :preconditions '((device ?d) (power-state ?d on))
                       :add-list '((connection ?d computer)))))

(defun studio-context ()
  (let ((ctx (create-context
              :name 'studio
              :facts '((device interface-01)
                       (power-state interface-01 off)))))
    (dolist (op (studio-ops)) (register-operator! ctx op))
    ctx))

(test transition-state-a-to-b
  (let* ((op (first (studio-ops)))
         (a (make-state '((device interface-01)
                          (power-state interface-01 off))
                        :kind :current))
         (b (unify '(power-state interface-01 on) '(power-state ?d on)))
         (next (transition-state a op b :kind :simulated)))
    (is (eq :simulated (state-kind next)))
    (is (fact-p '(power-state interface-01 on) (state-facts next)))
    (is (not (fact-p '(power-state interface-01 off) (state-facts next))))))

(test simulate-plan-no-mutation
  (let* ((ctx (studio-context))
         (plan (plan-from-context
                ctx :goals '((connection interface-01 computer))))
         (before (copy-list (context-facts ctx)))
         (result (simulate-plan plan :context ctx)))
    (is (execution-result-p result))
    (is (eq :simulate (execution-mode result)))
    (is-true (execution-success result))
    (is (eq :simulated (state-kind (execution-final-state result))))
    (is (eq :expected (state-kind (execution-expected-state result))))
    (is (fact-p '(connection interface-01 computer)
                (state-facts (execution-final-state result))))
    (is (equal before (context-facts ctx)))
    (is (getf (execution-divergences result) :equal))))

(test execute-plan-mutates-context
  (let* ((ctx (studio-context))
         (plan (plan-from-context
                ctx :goals '((connection interface-01 computer))))
         (result (execute-plan! ctx plan)))
    (is (eq :execute (execution-mode result)))
    (is-true (execution-success result))
    (is (eq :observed (state-kind (execution-final-state result))))
    (is (fact-p '(connection interface-01 computer) (context-all-facts ctx)))
    (is (fact-p '(power-state interface-01 on) (context-all-facts ctx)))
    (is (getf (execution-divergences result) :equal))))

(test irreversible-requires-confirmation
  (let* ((ctx (create-context :facts '((device d1))))
         (op (make-operator :name 'wipe
                            :preconditions '((device ?d))
                            :add-list '((wiped ?d))
                            :reversible nil
                            :risk :high)))
    (register-operator! ctx op)
    (signals confirmation-required
      (execute-operator! ctx op '((?d . d1))))
    (multiple-value-bind (facts result)
        (execute-operator! ctx op '((?d . d1)) :confirm t)
      (is (fact-p '(wiped d1) facts))
      (is (eq :executed (getf result :status))))))

(test simulate-precondition-failure
  (let* ((op (make-operator :name 'connect
                            :preconditions '((power-state ?d on))
                            :add-list '((connection ?d computer))))
         (facts '((device interface-01) (power-state interface-01 off))))
    (signals precondition-failure
      (simulate-operator facts op
                         (unify '(connection interface-01 computer)
                                '(connection ?d computer))))))
