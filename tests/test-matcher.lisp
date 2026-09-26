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
