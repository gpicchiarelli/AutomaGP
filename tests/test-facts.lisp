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

(test add-and-remove-fact-leave-their-argument-alone
  (let* ((facts (list '(a 1) '(b 2)))
         (before (copy-list facts)))
    (is (eq facts (add-fact! facts '(a 1))))
    (is (equal '((a 1) (b 2) (c 3)) (add-fact! facts '(c 3))))
    (is (equal '((b 2)) (remove-fact! facts '(a 1))))
    (is (equal before facts))))

(defun %in-another-package (tree)
  "TREE with every symbol replaced by the keyword of the same name."
  (cond
    ((consp tree) (cons (%in-another-package (car tree))
                        (%in-another-package (cdr tree))))
    ((and tree (symbolp tree)) (intern (symbol-name tree) :keyword))
    (t tree)))

(test same-names-ignores-the-package-at-every-depth
  ;; A fact has the same names as itself read in another package.
  (dolist (fact '((device d1)
                  (wraps (inner d1) 2)
                  (deep (a (b (c d))) "text" 1.5)
                  (dotted . tail)))
    (is-true (fact-same-names-p fact (%in-another-package fact)))
    (is-true (fact-same-names-p (%in-another-package fact) fact))
    (is (equal fact (find-fact-by-names (%in-another-package fact)
                                        (list '(other fact) fact)))))
  ;; Each (A B) differs in a name, a value, or its shape.
  (loop for (a b) in '(((a b) (a c))
                       ((a (b c)) (a (b d)))
                       ((a b) (a b c))
                       ((a b c) (a b))
                       ((a (b)) (a b))
                       ((a 1) (a 2))
                       ((a "x") (a "X"))
                       ((a . b) (a b))
                       (a a)
                       ((a) nil))
        do (is-false (fact-same-names-p a b))
           (is-false (fact-same-names-p b a))))
