;;;; tests/test-matcher.lisp

(in-package #:automa-gp/tests)

(def-suite matcher-suite :in automa-gp-suite)
(in-suite matcher-suite)

(test match-binds-variable
  (let ((b (match '(device ?x) '(device interface-01))))
    (is (not (fail-p b)))
    (is (equal 'interface-01 (cdr (lookup-binding '?x b))))))

(test match-anonymous
  (let ((b (match '(device ?) '(device interface-01))))
    (is (not (fail-p b)))
    (is (null (lookup-binding '? b)))))

(test match-inconsistent-fails
  (is (fail-p (match '(rel ?x ?x) '(rel a b)))))

(test substitute-bindings-nested
  (let* ((b (match '(power-state ?d ?s) '(power-state interface-01 on)))
         (out (substitute-bindings '(ready ?d ?s) b)))
    (is (equal '(ready interface-01 on) out))))

(test match-all-conjunction
  (let* ((facts '((device d1) (power-state d1 on) (device d2)))
         (sols (match-all '((device ?x) (power-state ?x on)) facts)))
    (is (= 1 (length sols)))
    (is (equal 'd1 (cdr (lookup-binding '?x (first sols)))))))

(test match-table
  ;; Each case is (PATTERN DATA MATCHES). DATA is ground and no pattern here
  ;; is anonymous, so a match substituted into its pattern gives DATA back.
  (loop for (pattern data matches)
          in '(((device ?x) (device d1) t)
               ((?x (?y ?x)) (1 (2 1)) t)
               ((?x (?y ?x)) (1 (2 3)) nil)
               ((a . ?rest) (a b c) t)
               ((a ?x) (a) nil)
               ((a) (a b) nil)
               ((a ?x) (b 1) nil)
               ((a "s" 1.5 ?x) (a "s" 1.5 (nested list)) t)
               ((a "s") (a "S") nil)
               (?x nil t)
               (nil nil t)
               (a a t)
               (a (a) nil))
        do (let ((b (match pattern data)))
             (is (eq matches (not (fail-p b))))
             (is (eq matches (nth-value 0 (match-p pattern data))))
             (when matches
               (is (equal data (substitute-bindings pattern b)))))))

(test match-returns-the-sentinels
  (is (eq *no-bindings* (match '(a b) '(a b))))
  (is (eq *no-bindings* (match '(? ?) '(1 2))))
  (is (eq *fail* (match '(a b) '(a c))))
  (is (eq *fail* (match '?x 'a *fail*)))
  (is (eq *fail* (substitute-bindings '(a ?x) *fail*)))
  (is (equal '(nil nil) (multiple-value-list (match-p '(a) '(b)))))
  (is (equal '(t nil) (multiple-value-list (match-p '(a) '(a)))))
  (is (equal '(t ((?x . 1))) (multiple-value-list (match-p '(a ?x) '(a 1)))))
  (is (equal (list *no-bindings*) (match-all '((a b)) '((a b)))))
  (is (null (match-all '((a b)) '((a c))))))

(test match-all-enumerates-every-consistent-solution
  (let ((facts '((device d1) (device d2) (power-state d1 on)
                 (power-state d2 off))))
    ;; Each case is (PATTERNS VALUES-OF-?X-PER-SOLUTION).
    (loop for (patterns xs) in '((((device ?x)) (d1 d2))
                                 (((device ?x) (power-state ?x ?)) (d1 d2))
                                 (((device ?x) (power-state ?x off)) (d2))
                                 (((device ?x) (power-state ?x broken)) ())
                                 (((power-state ?x on) (power-state ?y off)) (d1)))
          do (is (equal xs (mapcar (lambda (b) (cdr (lookup-binding '?x b)))
                                   (match-all patterns facts)))))))

(test a-bound-variable-is-matched-through-its-value
  ;; UNIFY leaves ?X standing for the open ?Y; matching ?X then settles ?Y.
  (let ((b (match '(p ?x) '(p a) (unify '?x '?y))))
    (is (equal '(a a) (substitute-bindings '(?x ?y) b))))
  (let ((b (unify '?x '(f ?z))))
    (is (equal '(f 1) (substitute-bindings '?x (match '(p ?x) '(p (f 1)) b))))
    (is (fail-p (match '(p ?x) '(p (g 1)) b)))))

(test data-holding-variables-never-yields-circular-bindings
  ;; Each case is (PATTERN DATA PATTERN-AFTER-SUBSTITUTION), or :FAIL where
  ;; only an infinite value would do.
  (loop for (pattern data result)
          in '((?x ?x ?x)
               ((?x ?x) (?y ?y) (?y ?y))
               ((?x ?y) (?y ?x) (?y ?y))
               ((?x ?y) (?y 1) (1 1))
               ((b ?x ?y) (b 1 ?y) (b 1 ?y))
               (?x (a ?x) :fail)
               ((?x ?x) (?y (a ?y)) :fail)
               ((?x ?y) (?y (a ?x)) :fail))
        do (let ((b (%bounded (match pattern data))))
             (if (eq result :fail)
                 (is (fail-p b))
                 (is (equal result
                            (%bounded (substitute-bindings pattern b))))))))

(test circular-bindings-given-from-outside-do-not-hang
  ;; INSTANTIATE-BINDINGS writes (?M . ?M) for a variable left open, and a
  ;; plan step hands that alist back as bindings. Each case is
  ;; (BINDINGS TREE TREE-AFTER-SUBSTITUTION).
  (loop for (bindings tree result)
          in '((((?m . ?m) (?d . d1)) (mode ?d ?m) (mode d1 ?m))
               (((?x . ?y) (?y . ?x)) (p ?x ?y) (p ?x ?y))
               (((?x a ?x)) (p ?x) (p (a ?x)))
               (((?x a ?y) (?y b ?x)) (p ?x) (p (a (b ?x)))))
        do (is (equal result (%bounded (substitute-bindings tree bindings))))
           (is-false (%bounded (occurs-check-p '?unrelated tree bindings)))
           (is (not (member (%bounded (match tree '(no match at all) bindings))
                            '(:timed-out :exhausted))))
           (is (not (member (%bounded (unify tree '?other bindings))
                            '(:timed-out :exhausted)))))
  ;; A variable bound to itself, or caught in a ring, is open: it can be bound.
  (dolist (bindings '(((?m . ?m) (?d . d1))
                      ((?m . ?n) (?n . ?m) (?d . d1))))
    (dolist (settle (list #'match #'unify))
      (is (equal '(mode d1 fast)
                 (%bounded
                   (substitute-bindings
                    '(mode ?d ?m)
                    (funcall settle '(mode ?d ?m) '(mode d1 fast) bindings)))))
      (is (fail-p (%bounded (funcall settle '(mode ?d ?m) '(mode d2 fast)
                                     bindings)))))))

(test callers-end-on-facts-that-hold-variables
  ;; A rule or operator that leaves a variable open asserts a fact holding
  ;; it; the next rule to reuse that name used to bind the variable to itself.
  (is (listp (%bounded
               (forward-chain
                '((a 1))
                (list (make-rule :name 'r1 :if '((a ?x)) :then '((b ?x ?y)))
                      (make-rule :name 'r2 :if '((b ?x ?y)) :then '((c ?y))))))))
  (is (plan-p (%bounded
                (plan-from-context
                 (make-context
                  :facts '((b 1 ?y))
                  :operators (list (make-operator :name 'op
                                                  :preconditions '((b ?x ?y))
                                                  :add-list '((done ?x)))))
                 :goals '((done 1))))))
  ;; The plan step below records (?M . ?M); simulating it reads that back.
  (let* ((ctx (make-context
               :facts '((device d1))
               :operators (list (make-operator
                                 :name 'set-mode
                                 :preconditions '((device ?d))
                                 :add-list '((mode ?d ?m) (ready ?d))))))
         (plan (%bounded (plan-from-context ctx :goals '((ready d1))))))
    (is (plan-p plan))
    (is (execution-result-p (%bounded (simulate-plan plan :context ctx))))))

(test pattern-has-variable-p-looks-at-every-depth
  ;; Each case is (PATTERN HAS-VARIABLE).
  (loop for (pattern has-variable) in '(((a b) nil)
                                        ((a ?x) t)
                                        ((a (b (c ?x))) t)
                                        ((a . ?x) t)
                                        ((a ?) t)
                                        (?x t)
                                        (a nil)
                                        (nil nil)
                                        ((a "?x" 42) nil))
        do (is (eq has-variable
                   (automa-gp::pattern-has-variable-p pattern)))))
