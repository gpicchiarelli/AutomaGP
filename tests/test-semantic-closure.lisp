;;;; tests/test-semantic-closure.lisp — the closure of a dependency graph

(in-package #:automa-gp/tests)

(def-suite semantic-closure-suite :in automa-gp-suite)
(in-suite semantic-closure-suite)

(defun %closure-of (graph &optional (root (first (first graph))))
  "The closure of ROOT in GRAPH, an alist (NODE . DEPENDENCIES)."
  (sem:dependency-closure root (lambda (node) (rest (assoc node graph)))))

(test closure-is-dependencies-before-dependents-in-a-fixed-order
  "Each entry is (GRAPH ORDER): the order is a depth-first post-order that
follows the dependencies in the order they are listed."
  (loop for (graph order)
          in '((((a)) (a))
               (((a b) (b c) (c)) (c b a))
               (((a b c) (b d) (c d) (d)) (d b c a))
               (((a c b) (b) (c)) (c b a))
               (((a b c) (b) (c)) (b c a))
               (((a b c) (b c) (c)) (c b a))
               (((a b b) (b)) (b a)))
        do (is (equal order (%closure-of graph)) "graph ~S" graph)))

(test closure-lists-each-node-once-with-its-dependencies
  (multiple-value-bind (order edges)
      (%closure-of '((a b c) (b d) (c d) (d)))
    (is (equal '(d b c a) order))
    (is (equal '((d) (b d) (c d) (a b c)) edges))
    (is (= (length order) (length (remove-duplicates order))))))

(test closure-reports-a-cycle-as-the-path-that-closes-it
  "Each entry is (GRAPH ROOT PATH)."
  (loop for (graph root path)
          in '((((a b) (b a)) a (a b a))
               (((a a)) a (a a))
               (((a b) (b c) (c a)) a (a b c a))
               (((r a) (a b) (b a)) r (a b a))
               (((r a b) (a c) (b) (c b a)) r (a c a)))
        do (let ((condition (handler-case (%closure-of graph root)
                              (sem:dependency-cycle (c) c))))
             (is (typep condition 'sem:dependency-cycle) "graph ~S" graph)
             (is (equal path (sem:dependency-cycle-path condition))
                 "graph ~S" graph)
             (is (typep condition 'sem:standard-dependency-error))
             (is (typep condition 'sem:standards-error))
             (is (typep condition 'gp-error))
             (is (eq :dependency-cycle (sem:standards-error-code condition))))))

(test closure-keys-nodes-by-what-identifies-them
  "\"C\" and \"c\" are one node under a key that ignores case, and the
spelling that is kept is the one met first."
  (let ((graph '(("A" "b" "C") ("b" "c") ("C"))))
    (flet ((neighbours (node) (rest (assoc node graph :test #'string-equal))))
      (is (equal '("c" "b" "A")
                 (sem:dependency-closure "A" #'neighbours
                                         :key #'string-downcase)))
      (is (equal '("c" "b" "C" "A")
                 (sem:dependency-closure "A" #'neighbours))
          "without a key, EQUAL compares the strings as they are"))))

(test closure-survives-a-long-chain
  (let* ((n 2000)
         (graph (loop for i from 0 below n
                      collect (if (< (1+ i) n) (list i (1+ i)) (list i)))))
    (is (equal (loop for i from (1- n) downto 0 collect i)
               (%closure-of graph 0)))))
