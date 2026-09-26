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
