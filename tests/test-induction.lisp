;;;; tests/test-induction.lisp — operator and rule induction from observed states

(in-package #:automa-gp/tests)

(def-suite induction-suite :in automa-gp-suite)
(in-suite induction-suite)

(test induce-operator-ignores-unrelated-facts
  (let ((op (induce-operator 'free-port
                             '((device interface-01) (port-bound 47391))
                             '((device interface-01) (port-free 47391)))))
    (is (equal '((port-bound 47391)) (operator-preconditions op)))
    (is (equal '((port-free 47391)) (operator-add-list op)))
    (is (equal '((port-bound 47391)) (operator-delete-list op)))
    (is (eq t (getf (operator-meta op) :induced)))))

(test induce-rule-lifts-the-shared-object
  (let ((op (induce-operator 'power-on
                             '((weather sunny)
                               (device interface-01)
                               (power-state interface-01 off))
                             '((weather sunny)
                               (device interface-01)
                               (power-state interface-01 on))
                             :generalize t)))
    (let ((x (find-symbol "?X0" :automa-gp)))
      (is (eq x (second (first (operator-preconditions op)))))
      (is (equal `((device ,x) (power-state ,x off))
                 (operator-preconditions op)))
      (is (equal `((power-state ,x on)) (operator-add-list op)))
      (is (equal `((power-state ,x off)) (operator-delete-list op)))
      (is (equal '(interface-01) (getf (operator-meta op) :generalized))))))

(test induce-rule-keeps-numbers-ground
  (let ((op (induce-operator 'free-port
                             '((device interface-01) (port-bound 47391))
                             '((device interface-01) (port-free 47391))
                             :generalize t)))
    (is (equal '((port-bound 47391)) (operator-preconditions op)))
    (is (equal '((port-free 47391)) (operator-add-list op)))
    (is (null (getf (operator-meta op) :generalized)))))

(test failed-plan-listens-and-the-learned-rule-replans
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (let ((failed (gp-plan :goals '((power-state interface-01 on)) :archive nil)))
    (is (not (plan-success failed)))
    (is (observation-active-p))
    (is (fact-p '(power-state interface-01 on) (getf (gp-observation) :missing))))
  (gp-remove-fact '(power-state interface-01 off))
  (gp-add-fact '(power-state interface-01 on))
  (gp-induce-rule 'power-on)
  (is (not (observation-active-p)))
  (gp-remove-fact '(power-state interface-01 on))
  (gp-remove-fact '(device interface-01))
  (gp-add-fact '(device interface-02))
  (gp-add-fact '(power-state interface-02 off))
  (let ((plan (gp-plan :goals '((power-state interface-02 on)) :archive nil)))
    (is (plan-success plan))
    (is (eq 'power-on (getf (first (plan-steps plan)) :operator)))
    (is (not (observation-active-p)))))

(test induce-operator-rejects-an-unchanged-state
  (signals error (induce-operator 'noop '((folder notes missing))
                                  '((folder notes missing)))))

(test learn-action-registers-the-induced-operator
  (gp-reset)
  (gp-add-fact '(folder notes missing))
  (gp-note-state)
  (gp-remove-fact '(folder notes missing))
  (gp-add-fact '(folder notes present))
  (let ((op (gp-learn-action 'create-folder)))
    (is (eq 'create-folder (operator-name op)))
    (is (equal '((folder notes missing)) (operator-preconditions op)))
    (is (equal '((folder notes present)) (operator-add-list op)))
    (is (operator-p (find-operator (gp-context) 'create-folder)))))

(test induce-rule-merges-a-second-example
  (gp-clear-memory)
  (gp-reset)
  (gp-induce-rule 'power-on
                  :before '((device interface-01) (power-state interface-01 off))
                  :after '((device interface-01) (power-state interface-01 on)))
  (let ((op (gp-induce-rule 'power-on
                            :before '((power-state interface-02 off) (device interface-02))
                            :after '((device interface-02) (power-state interface-02 on)))))
    (let ((x (find-symbol "?X0" :automa-gp)))
      (is (equal `((device ,x) (power-state ,x off))
                 (operator-preconditions op)))
      (is (equal `((power-state ,x on)) (operator-add-list op)))
      (is (= 2 (getf (operator-meta op) :examples)))
      (is (equal '(interface-01 interface-02)
                 (getf (operator-meta op) :generalized))))))

(test induce-rule-refuses-a-different-value-and-a-different-number
  (gp-clear-memory)
  (gp-reset)
  (gp-induce-rule 'power-on
                  :before '((device interface-01) (power-state interface-01 off))
                  :after '((device interface-01) (power-state interface-01 on)))
  (signals error
    (gp-induce-rule 'power-on
                    :before '((device interface-01) (power-state interface-01 off))
                    :after '((device interface-01) (power-state interface-01 ready))))
  (let ((op (find-operator (gp-context) 'power-on)))
    (is (= 1 (getf (operator-meta op) :examples)))
    (is (equal '(interface-01) (getf (operator-meta op) :generalized))))
  (gp-reset)
  (gp-induce-rule 'free-port
                  :before '((port-bound 47391))
                  :after '((port-free 47391)))
  (signals error
    (gp-induce-rule 'free-port
                    :before '((port-bound 47392))
                    :after '((port-free 47392))))
  (let ((op (find-operator (gp-context) 'free-port)))
    (is (equal '((port-bound 47391)) (operator-preconditions op)))
    (is (equal '((port-free 47391)) (operator-add-list op)))
    (is (= 1 (getf (operator-meta op) :examples)))))

(test learn-action-merges-a-second-ground-example
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(folder notes missing))
  (gp-note-state)
  (gp-learn-action 'create-folder
                   :before '((weather sunny) (folder notes missing))
                   :after '((folder notes present) (weather sunny)))
  (is (not (observation-active-p)))
  (let ((op (gp-learn-action 'create-folder
                             :before '((folder notes missing) (weather rainy))
                             :after '((weather rainy) (folder notes present)))))
    (is (equal '((folder notes missing)) (operator-preconditions op)))
    (is (equal '((folder notes present)) (operator-add-list op)))
    (is (equal '((folder notes missing)) (operator-delete-list op)))
    (is (= 2 (getf (operator-meta op) :examples)))
    (is (null (getf (operator-meta op) :generalized)))))

(test learn-action-refuses-a-different-constant
  (gp-clear-memory)
  (gp-reset)
  (gp-learn-action 'create-folder
                   :before '((folder notes missing))
                   :after '((folder notes present)))
  (gp-add-fact '(folder notes present))
  (gp-note-state)
  (signals error
    (gp-learn-action 'create-folder
                     :before '((folder photos missing))
                     :after '((folder photos present))))
  (is (observation-active-p))
  (let ((op (find-operator (gp-context) 'create-folder)))
    (is (equal '((folder notes missing)) (operator-preconditions op)))
    (is (= 1 (getf (operator-meta op) :examples))))
  (gp-reset)
  (gp-learn-action 'free-port
                   :before '((port-bound 47391))
                   :after '((port-free 47391)))
  (signals error
    (gp-learn-action 'free-port
                     :before '((port-bound 47392))
                     :after '((port-free 47392))))
  (let ((op (find-operator (gp-context) 'free-port)))
    (is (equal '((port-bound 47391)) (operator-preconditions op)))
    (is (equal '((port-free 47391)) (operator-add-list op)))
    (is (= 1 (getf (operator-meta op) :examples))))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'create-folder
                  :preconditions '((folder notes missing))
                  :add-list '((folder notes present))))
  (signals error
    (gp-learn-action 'create-folder
                     :before '((folder notes missing))
                     :after '((folder notes present))))
  (is (not (getf (operator-meta (find-operator (gp-context) 'create-folder))
                 :induced)))
  (gp-reset)
  (gp-induce-rule 'power-on
                  :before '((device interface-01) (power-state interface-01 off))
                  :after '((device interface-01) (power-state interface-01 on)))
  (signals error
    (gp-learn-action 'power-on
                     :before '((device interface-01) (power-state interface-01 off))
                     :after '((device interface-01) (power-state interface-01 on))))
  (let ((op (find-operator (gp-context) 'power-on)))
    (is (= 1 (getf (operator-meta op) :examples)))
    (is (equal '(interface-01) (getf (operator-meta op) :generalized)))))

(test induce-rule-lifts-a-repeated-symbol-from-two-examples
  (gp-clear-memory)
  (gp-reset)
  (gp-induce-rule 'paint
                  :before '()
                  :after '((left alpha) (right alpha)))
  (let ((op (gp-induce-rule 'paint
                            :before '()
                            :after '((right beta) (left beta)))))
    (let ((x (find-symbol "?X0" :automa-gp)))
      (is (equal `((left ,x) (right ,x)) (operator-add-list op)))
      (is (= 2 (getf (operator-meta op) :examples)))
      (is (member 'alpha (getf (operator-meta op) :generalized)))
      (is (member 'beta (getf (operator-meta op) :generalized))))))
