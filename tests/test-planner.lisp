;;;; tests/test-planner.lisp

(in-package #:automa-gp/tests)

(def-suite planner-suite :in automa-gp-suite)
(in-suite planner-suite)

(test plan-from-context-success
  (let ((ctx (create-context
              :name 'studio
              :facts '((device interface-01)
                       (power-state interface-01 off))
              :goals '((power-state interface-01 on)
                       (connection interface-01 computer)))))
    (dolist (op (list
                 (make-operator :name 'power-on
                                :preconditions '((device ?d) (power-state ?d off))
                                :add-list '((power-state ?d on))
                                :delete-list '((power-state ?d off)))
                 (make-operator :name 'connect
                                :preconditions '((device ?d) (power-state ?d on))
                                :add-list '((connection ?d computer)))))
      (register-operator! ctx op))
    (let ((plan (plan-from-context ctx)))
      (is (plan-p plan))
      (is-true (plan-success plan))
      (is (= 2 (plan-length plan)))
      (is (fact-p '(connection interface-01 computer) (plan-final-state plan)))
      (is (null (plan-remaining plan))))))

(test plan-already-satisfied
  (let ((plan (plan-for '((a 1)) '((a 1)) nil)))
    (is-true (plan-success plan))
    (is (zerop (plan-length plan)))))

(test plan-failure-no-operators
  (let ((plan (plan-for '((a 1)) '((b 2)) nil)))
    (is-false (plan-success plan))
    (is (equal '((b 2)) (plan-remaining plan)))))

(test normalize-ignores-symbol-goals
  (is (equal '((f 1)) (normalize-planning-goals '(label (f 1) other)))))
