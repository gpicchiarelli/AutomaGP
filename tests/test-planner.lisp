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

(test normalize-returns-the-labels-too
  (multiple-value-bind (fact-goals labels)
      (normalize-planning-goals '(label (f 1) other))
    (is (equal '((f 1)) fact-goals))
    (is (equal '(label other) labels))))

(test plan-records-the-goals-it-does-not-plan
  ;; Each case is (GOALS PLANNED IGNORED).
  (dolist (case '(((audio-system-ready) nil (audio-system-ready))
                  ((audio-system-ready (a 1) later) ((a 1)) (audio-system-ready later))
                  (((a 1)) ((a 1)) nil)))
    (destructuring-bind (goals planned ignored) case
      (let* ((plan (plan-for '((a 1)) goals nil))
             (entries (find-trace-entries :ignored-goals (trace-of plan))))
        (is (equal planned (plan-goals plan)))
        (is (equal ignored (getf (plan-meta plan) :ignored-goals)))
        (is (equal ignored (getf (first entries) :goals)))
        (is (= (if ignored 1 0) (length entries)))))))

(test plan-from-context-records-context-labels
  (let* ((ctx (create-context :name 'studio
                              :facts '((a 1))
                              :goals '(audio-system-ready (a 1))))
         (plan (plan-from-context ctx)))
    (is (equal '((a 1)) (plan-goals plan)))
    (is (equal '(audio-system-ready) (getf (plan-meta plan) :ignored-goals)))
    (is (eq 'studio (getf (plan-meta plan) :context)))))

(test plan-from-an-empty-state
  (let ((plan (plan-for nil nil nil)))
    (is-true (plan-success plan))
    (is (null (plan-final-state plan))))
  (let ((plan (plan-for nil '((a 1))
                        (list (make-operator :name 'make-a :add-list '((a 1)))))))
    (is-true (plan-success plan))
    (is (= 1 (plan-length plan)))
    (is (= 1 (plan-cost plan)))
    (is (equal '(make-a) (plan-operators-used plan)))
    (is (equal '((a 1)) (plan-final-state plan)))))

(test plan-cost-sums-step-costs
  (let ((plan (plan-for '((x 0)) '((a 1) (b 1))
                        (list (make-operator :name 'make-a :add-list '((a 1))
                                             :cost 3)
                              (make-operator :name 'make-b :add-list '((b 1))
                                             :cost 4)))))
    (is (= 2 (plan-length plan)))
    (is (= 7 (plan-cost plan)))))

(test exported-planner-functions-are-documented
  (dolist (name '(plan-p plan-for plan-from-context plan-length plan-cost
                  normalize-planning-goals))
    (is (eq :external
            (nth-value 1 (find-symbol (symbol-name name) :automa-gp))))
    (is (documentation name 'function)))
  (is (documentation 'plan 'type)))
