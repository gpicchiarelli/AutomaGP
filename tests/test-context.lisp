;;;; tests/test-context.lisp

(in-package #:automa-gp/tests)

(def-suite context-suite :in automa-gp-suite)
(in-suite context-suite)

(test create-and-query-context
  (let ((ctx (create-context :name 'studio
                             :facts '((device interface-01)
                                      (power-state interface-01 off)))))
    (is (context-p ctx))
    (is (eq 'studio (context-name ctx)))
    (is (fact-p '(device interface-01) (facts-of ctx)))
    (let ((hits (context-query ctx '(power-state ?d off))))
      (is (= 1 (length hits))))))

(test hierarchical-inheritance
  (let* ((parent (create-context :name 'studio
                                 :facts '((location studio-room)
                                          (device mixer-01))))
         (child (create-context :name 'audio
                                :parent parent
                                :facts '((device interface-01)))))
    (is (eq parent (context-parent child)))
    (is (member child (context-children parent) :test #'eq))
    ;; Union: parent facts visible through child
    (is (fact-p '(location studio-room) (context-all-facts child)))
    (is (fact-p '(device mixer-01) (context-all-facts child)))
    (is (fact-p '(device interface-01) (context-all-facts child)))
    ;; Exact EQUAL override: local identical fact replaces ancestor copy
    (setf (context-facts child)
          (add-fact! (context-facts child) '(location studio-room)))
    (is (= 1 (count '(location studio-room) (context-all-facts child)
                    :test #'fact-equal)))))

(test clone-and-compare
  (let* ((a (create-context :name 'a :facts '((f 1)) :goals '(g1) :mode :read))
         (b (clone-context a :name 'b)))
    (is (context-p b))
    (is (equal '(f 1) (first (facts-of b))))
    (is (null (context-parent b)))
    (context-modify! b :facts '((f 1) (f 2)))
    (let ((diff (compare-contexts a b)))
      (is (equal '((f 2)) (getf diff :facts-only-in-b)))
      (is (null (getf diff :facts-only-in-a))))))
