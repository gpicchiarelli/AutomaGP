;;;; tests/test-unification.lisp

(in-package #:automa-gp/tests)

(def-suite unification-suite :in automa-gp-suite)
(in-suite unification-suite)

(test unify-two-variables
  (let ((b (unify '(f ?x) '(f ?y))))
    (is (not (fail-p b)))
    (is (equal '?y (cdr (lookup-binding '?x b))))))

(test unify-ground
  (multiple-value-bind (ok binds) (unify-p '(a 1) '(a 1))
    (is-true ok)
    (is (null binds))))

(test unify-conflict
  (is (fail-p (unify '(f a) '(f b)))))

(test occurs-check-rejects-cycle
  (is (fail-p (unify '?x '(f ?x)))))

(test unify-nested
  (let ((b (unify '(power-state ?d on) '(power-state interface-01 ?s))))
    (is (not (fail-p b)))
    (is (equal 'interface-01 (cdr (lookup-binding '?d b))))
    (is (equal 'on (cdr (lookup-binding '?s b))))))

(test unify-table
  ;; Each case is (X Y COMMON-INSTANCE), or :FAIL. Unification is symmetric.
  (loop for (x y instance)
          in '(((f ?x ?x) (f a a) (f a a))
               ((f ?x ?x) (f a b) :fail)
               ((f ?x ?y) (f ?y a) (f a a))
               ((p ?x (q ?y)) (p (r ?y) (q b)) (p (r b) (q b)))
               ((f ?x ?y ?z) (f ?y ?z c) (f c c c))
               ((f "s" 1) (f "s" 1) (f "s" 1))
               ((f "s") (f "S") :fail)
               ((f a) (f a b) :fail)
               (?x (f ?x) :fail)
               ((f ?x ?y) (f ?y (g ?x)) :fail)
               ((f ?x ?y) (f (g ?y) (g ?x)) :fail))
        do (loop for (left right) in (list (list x y) (list y x))
                 do (let ((b (%bounded (unify left right))))
                      (if (eq instance :fail)
                          (is (fail-p b))
                          (progn
                            (is (equal instance (substitute-bindings left b)))
                            (is (equal instance
                                       (substitute-bindings right b)))))))))

(test the-anonymous-variable-never-binds
  (loop for (x y) in '(((f ? b) (f a ?))
                       (? (f ?))
                       (?x ?)
                       ((f ?) (f (g ?))))
        do (is (eq *no-bindings* (unify x y)))
           (is (eq *no-bindings* (unify y x)))))

(test unify-continues-from-bindings-it-is-given
  (let ((b (unify '?x 'a (unify '?x '?y))))
    (is (equal '(a a) (substitute-bindings '(?x ?y) b))))
  (is (fail-p (unify '?y 'b (unify '?x 'a (unify '?x '?y)))))
  (is (eq *fail* (unify 'a 'a *fail*)))
  (is (equal '(nil nil) (multiple-value-list (unify-p '(f a) '(f b)))))
  (is (equal '(t ((?x . a))) (multiple-value-list (unify-p '(f ?x) '(f a))))))

(test occurs-check-follows-bindings-and-ends-on-circular-ones
  ;; Each case is (VAR TREE BINDINGS OCCURS).
  (loop for (var tree bindings occurs)
          in '((?x ?x nil t)
               (?x (f (g ?x)) nil t)
               (?x (f ?y) nil nil)
               (?x (f ?y) ((?y . (g ?x))) t)
               (?x (f ?y) ((?y . ?z) (?z . a)) nil)
               (?x ?y ((?y . ?y)) nil)
               (?x (f ?y) ((?y . ?z) (?z . ?y)) nil)
               (?x (f ?y) ((?y . ?z) (?z . (g ?y ?x))) t))
        do (is (eq occurs (%bounded (occurs-check-p var tree bindings))))))
