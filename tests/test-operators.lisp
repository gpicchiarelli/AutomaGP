;;;; tests/test-operators.lisp

(in-package #:automa-gp/tests)

(def-suite operators-suite :in automa-gp-suite)
(in-suite operators-suite)

(test make-operator-and-achieves
  (let ((op (make-operator :name 'power-on
                           :preconditions '((device ?d) (power-state ?d off))
                           :add-list '((power-state ?d on))
                           :delete-list '((power-state ?d off)))))
    (is (operator-p op))
    (is (not (fail-p (operator-achieves op '(power-state interface-01 on)))))
    (is (fail-p (operator-achieves op '(connection interface-01 computer))))))

(test action-lift
  (let* ((act (make-action :name 'power-on
                           :preconditions '((device ?d))
                           :effects '((power-state ?d on))
                           :cost 2))
         (op (action->operator act)))
    (is (eq 'power-on (operator-name op)))
    (is (equal '((power-state ?d on)) (operator-add-list op)))
    (is (= 2 (operator-cost op)))))

(test register-operators-on-context
  (let ((ctx (create-context :name 'o)))
    (register-operator! ctx (make-operator :name 'a :add-list '((f 1))))
    (is (= 1 (length (operators-of ctx))))
    (is (eq 'a (operator-name (first (context-planning-operators ctx)))))))
