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

(test make-operator-requires-a-name
  (signals type-error (make-operator :add-list '((f 1))))
  (let ((op (handler-bind ((type-error (lambda (c) (store-value 'named c))))
              (make-operator :add-list '(f 1) :preconditions '((g 1) (h 1))))))
    (is (eq 'named (operator-name op)))
    (is (equal '((f 1)) (operator-add-list op)))
    (is (equal '((g 1) (h 1)) (operator-preconditions op)))
    (is (null (operator-delete-list op)))))

(test operators-for-goal-gives-every-add-pattern-that-fits
  (let ((several (make-operator :name 'several
                                :add-list '((status a ready) (status b ready)
                                            (status a ready) (color a red))))
        (general (make-operator :name 'general
                                :add-list '((status ?d ready))))
        (other (make-operator :name 'other :add-list '((color ?d red)))))
    (flet ((ways (goal)
             (loop for (operator . bindings)
                     in (operators-for-goal goal (list several general other))
                   collect (list (operator-name operator)
                                 (substitute-bindings goal bindings)))))
      (loop for (goal . expected)
              in '(((status ?x ready)
                    (several (status a ready)) (several (status b ready))
                    (general (status ?d ready)))
                   ((status b ready)
                    (several (status b ready)) (general (status b ready)))
                   ((status c ready)
                    (general (status c ready)))
                   ((color a ?c)
                    (several (color a red)) (other (color a red)))
                   ((status a waiting)))
            do (is (equal expected (ways goal)))))
    (is (equal '((?x . a))
               (operator-achieves several '(status ?x ready))))
    (is (eq *no-bindings* (operator-achieves several '(status b ready))))
    (is (fail-p (operator-achieves several '(status c ready))))))

(test register-operator-replaces-the-operator-of-the-same-name
  (let ((ctx (create-context :name 'o)))
    (register-operator! ctx (make-operator :name 'a :cost 1))
    (register-operator! ctx (make-operator :name 'b :cost 2))
    (register-operator! ctx (make-operator :name 'a :cost 3))
    (is (equal '((a . 3) (b . 2))
               (loop for op in (operators-of ctx)
                     collect (cons (operator-name op) (operator-cost op)))))
    (is (eq (first (operators-of ctx)) (find-operator ctx 'a)))
    (remove-operator! ctx 'a)
    (is (equal '(b) (mapcar #'operator-name (operators-of ctx))))
    (is (null (find-operator ctx 'a)))))

(test a-local-operator-shadows-the-ancestor-operator-of-the-same-name
  (let* ((root (create-context :name 'root))
         (middle (create-context :name 'middle :parent root))
         (leaf (create-context :name 'leaf :parent middle)))
    (register-operator! root (make-operator :name 'shared :cost 1))
    (register-operator! root (make-operator :name 'root-only :cost 2))
    (register-operator! middle (make-operator :name 'shared :cost 3))
    (register-operator! leaf (make-operator :name 'leaf-only :cost 4))
    (loop for (context expected)
            in `((,leaf ((leaf-only . 4) (shared . 3) (root-only . 2)))
                 (,middle ((shared . 3) (root-only . 2)))
                 (,root ((root-only . 2) (shared . 1))))
          do (is (equal expected
                        (loop for op in (context-all-operators context)
                              collect (cons (operator-name op)
                                            (operator-cost op)))))
             (is (= (cdr (assoc 'shared expected))
                    (operator-cost (find-operator context 'shared)))))))

(test planning-falls-back-to-lifted-actions-only-without-operators
  (let ((ctx (create-context :name 'o)))
    (register-action! ctx (make-action :name 'power-on
                                       :preconditions '((device ?d))
                                       :effects '((power-state ?d on))
                                       :risk :high
                                       :reversible nil))
    (is (null (context-all-operators ctx)))
    (let ((lifted (find-operator ctx 'power-on)))
      (is (operator-p lifted))
      (is (eq 'power-on (operator-action lifted)))
      (is (eq :high (operator-risk lifted)))
      (is (null (operator-reversible lifted)))
      (is (null (operator-delete-list lifted)))
      ;; Lifted on each call: the context holds the action, not an operator.
      (is (not (eq lifted (find-operator ctx 'power-on)))))
    (register-operator! ctx (make-operator :name 'explicit :add-list '((f 1))))
    (is (equal '(explicit)
               (mapcar #'operator-name (context-planning-operators ctx))))
    (is (null (find-operator ctx 'power-on)))))

(test the-planner-tries-every-way-an-operator-achieves-a-goal
  (let ((connect (make-operator :name 'connect
                                :preconditions '((port ?a out) (port ?b in))
                                :add-list '((linked ?a ?b) (linked ?b ?a))))
        (state '((port y out) (port x in))))
    ;; (LINKED X Y) fits the first add pattern only with the ports swapped;
    ;; the second pattern is the one the state allows.
    (loop for goal in '((linked y x) (linked x y))
          for plan = (plan-for state (list goal) (list connect))
          do (is (plan-success plan))
             (is (equal '(connect)
                        (mapcar (lambda (step) (getf step :operator))
                                (plan-steps plan))))
             (is (fact-p goal (plan-final-state plan))))))
