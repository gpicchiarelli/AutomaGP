;;;; tests/test-facts.lisp

(in-package #:automa-gp/tests)

(def-suite facts-suite :in automa-gp-suite)
(in-suite facts-suite)

(test fact-p-exact
  (let ((facts '((device interface-01)
                 (power-state interface-01 off))))
    (is (fact-p '(device interface-01) facts))
    (is (not (fact-p '(device interface-02) facts)))))

(test find-facts-with-variable
  (let* ((facts '((device interface-01)
                  (device interface-02)
                  (power-state interface-01 off)))
         (hits (find-facts '(device ?x) facts)))
    (is (= 2 (length hits)))
    (is (equal 'interface-01 (cdr (assoc '?x (cdr (first hits)) :test #'eq))))
    (is (equal 'interface-02 (cdr (assoc '?x (cdr (second hits)) :test #'eq))))))

(test fact-matches-consistent-binding
  (multiple-value-bind (ok binds)
      (fact-matches-p '(rel ?x ?x) '(rel a a))
    (is-true ok)
    (is (equal 'a (cdr (assoc '?x binds :test #'eq)))))
  (multiple-value-bind (ok2 binds2)
      (fact-matches-p '(rel ?x ?x) '(rel a b))
    (declare (ignore binds2))
    (is-false ok2)))

(test add-and-remove-fact
  (let* ((f1 (add-fact! nil '(device d1)))
         (f2 (add-fact! f1 '(device d1)))
         (f3 (remove-fact! f2 '(device d1))))
    (is (= 1 (length f1)))
    (is (= 1 (length f2)))
    (is (null f3))))
