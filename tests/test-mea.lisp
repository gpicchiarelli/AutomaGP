;;;; tests/test-mea.lisp

(in-package #:automa-gp/tests)

(def-suite mea-suite :in automa-gp-suite)
(in-suite mea-suite)

(defun studio-operators ()
  (list (make-operator :name 'power-on
                       :preconditions '((device ?d) (power-state ?d off))
                       :add-list '((power-state ?d on))
                       :delete-list '((power-state ?d off)))
        (make-operator :name 'connect
                       :preconditions '((device ?d) (power-state ?d on))
                       :add-list '((connection ?d computer)))))

(test differences-detects-missing
  (let ((facts '((device interface-01) (power-state interface-01 off)))
        (goals '((power-state interface-01 on)
                 (connection interface-01 computer))))
    (is (= 2 (length (differences facts goals))))
    (is (goal-holds-p '(device interface-01) facts))))

(test apply-operator-updates-state
  (let* ((op (first (studio-operators)))
         (facts '((device interface-01) (power-state interface-01 off)))
         (b (unify '(power-state interface-01 on)
                   '(power-state ?d on)))
         (next (apply-operator facts op b)))
    (is (fact-p '(power-state interface-01 on) next))
    (is (not (fact-p '(power-state interface-01 off) next)))))

(test mea-with-subgoals
  (let ((facts '((device interface-01) (power-state interface-01 off)))
        (goals '((connection interface-01 computer)))
        (ops (studio-operators)))
    (multiple-value-bind (ok final plan left)
        (means-ends-analyze facts goals ops)
      (is-true ok)
      (is (null left))
      (is (fact-p '(connection interface-01 computer) final))
      (is (fact-p '(power-state interface-01 on) final))
      (is (>= (length plan) 2))
      (is (equal 'power-on (getf (first plan) :operator)))
      (is (equal 'connect (getf (second plan) :operator)))
      (is (equal '((power-state interface-01 on))
                 (getf (second plan) :subgoals))))))
