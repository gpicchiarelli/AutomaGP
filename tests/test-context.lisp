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

(test visible-facts-are-a-union-with-one-copy-of-each
  ;; Three levels; each case is (ROOT MIDDLE LEAF VISIBLE-FROM-LEAF).
  (loop for (root middle leaf visible)
          in '((((a 1)) ((b 2)) ((c 3))
                ((a 1) (b 2) (c 3)))
               ;; a repeated fact keeps its most local position
               (((a 1) (b 2)) ((c 3)) ((a 1))
                ((b 2) (c 3) (a 1)))
               (((a 1) (a 1)) () ((b 2) (b 2))
                ((a 1) (b 2)))
               ;; a local fact does not hide a different inherited one
               (((power d off)) () ((power d on))
                ((power d off) (power d on)))
               (() () () ()))
        do (let* ((top (create-context :facts root))
                  (mid (create-context :parent top :facts middle))
                  (low (create-context :parent mid :facts leaf)))
             (is (equal visible (context-all-facts low)))
             (is (equal (remove-duplicates root :test #'equal)
                        (context-all-facts top))))))

(test visible-facts-are-a-new-list
  (let* ((ctx (create-context :facts '((a 1) (b 2))))
         (visible (context-all-facts ctx)))
    (fill visible nil)
    (is (equal '((a 1) (b 2)) (context-facts ctx)))))

(test a-parent-link-never-closes-a-loop
  (let* ((root (create-context :name 'root :facts '((r 1))))
         (mid (create-context :name 'mid :parent root))
         (leaf (create-context :name 'leaf :parent mid)))
    ;; Each (PARENT CHILD) would make CHILD its own ancestor.
    (loop for (parent child) in (list (list root root)
                                      (list mid root)
                                      (list leaf root)
                                      (list leaf mid))
          do (signals context-cycle (context-add-child! parent child))
             (signals context-cycle (setf (context-parent child) parent)))
    (handler-case (context-add-child! leaf root)
      (context-cycle (c)
        (is (eq root (context-cycle-context c)))
        (is (eq leaf (context-cycle-parent c)))
        (is (search "ROOT" (princ-to-string c)))))
    ;; Refused before anything was written.
    (is (null (context-parent root)))
    (is (eq root (context-parent mid)))
    (is (eq mid (context-parent leaf)))
    (is (equal (list mid) (context-children root)))
    (is (equal (list leaf) (context-children mid)))
    (is (null (context-children leaf)))
    (is (equal (list leaf mid root) (%bounded (context-lineage leaf))))
    (is (equal '((r 1)) (%bounded (context-all-facts leaf))))))

(test a-loop-made-behind-the-accessors-is-reported
  (let* ((a (create-context :name 'a))
         (b (create-context :name 'b :parent a)))
    (setf (slot-value a 'automa-gp::parent) b)
    (dolist (walk (list #'context-lineage #'context-all-facts
                        #'context-all-rules #'context-all-operators
                        #'context-all-event-reactions))
      (is (eq :loop (%bounded (handler-case (funcall walk b)
                                (context-cycle (c)
                                  (and (eq b (context-cycle-context c))
                                       (null (context-cycle-parent c))
                                       :loop)))))))
    (signals context-cycle (context-add-child! b (create-context :name 'c)))))

(test add-child-moves-a-child-between-parents
  (let ((p (create-context :name 'p :facts '((under p))))
        (q (create-context :name 'q :facts '((under q))))
        (c (create-context :name 'c)))
    (is (eq c (context-add-child! p c)))
    (context-add-child! p c)
    (is (equal (list c) (context-children p)))
    (is (equal '((under p)) (context-all-facts c)))
    (context-add-child! q c)
    (is (null (context-children p)))
    (is (equal (list c) (context-children q)))
    (is (eq q (context-parent c)))
    (is (equal '((under q)) (context-all-facts c)))))

(test make-context-links-the-children-it-is-given
  (let* ((k1 (make-context :name 'k1))
         (k2 (make-context :name 'k2))
         (top (make-context :name 'top :facts '((f 1)) :children (list k1 k2))))
    (is (equal (list k1 k2) (context-children top)))
    (dolist (k (list k1 k2))
      (is (eq top (context-parent k)))
      (is (equal '((f 1)) (context-all-facts k))))
    ;; TOP is an ancestor of K1. The refusal comes before K2, listed with it
    ;; in either order, has been moved.
    (dolist (children (list (list top) (list k2 top) (list top k2)))
      (signals context-cycle (make-context :parent k1 :children children))
      (is (null (context-parent top)))
      (is (eq top (context-parent k2)))
      (is (equal (list k1 k2) (context-children top))))))

(test context-facts-are-asserted-and-retracted-in-place
  (let* ((parent (create-context :facts '((shared 1) (inherited 2))))
         (child (create-context :parent parent :facts '((own 3)))))
    ;; Each case is (OPERATION FACT LOCAL-FACTS-AFTER), applied in turn.
    (loop for (operation fact local)
            in '((:add (new 4) ((own 3) (new 4)))
                 (:add (new 4) ((own 3) (new 4)))
                 (:add (shared 1) ((own 3) (new 4) (shared 1)))
                 (:remove (own 3) ((new 4) (shared 1)))
                 (:remove (absent 0) ((new 4) (shared 1)))
                 (:remove (inherited 2) ((new 4) (shared 1)))
                 (:remove (shared 1) ((new 4)))
                 (:remove (new 4) ()))
          do (is (equal local
                        (ecase operation
                          (:add (context-add-fact! child fact))
                          (:remove (context-remove-fact! child fact)))))
             (is (equal local (facts-of child))))
    ;; The parent was never touched, and what it holds is still inherited.
    (is (equal '((shared 1) (inherited 2)) (facts-of parent)))
    (is (equal '((shared 1) (inherited 2)) (context-all-facts child)))))

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

(test a-clone-shares-no-list-with-its-original
  (let* ((a (create-context :name 'a :facts '((f 1)) :goals '(g1) :mode :plan
                            :meta (list :k (list 1 2))))
         (b (clone-context a :as-child t)))
    (is (eq 'a (context-name b)))
    (is (eq :plan (context-mode b)))
    (is (eq a (context-parent b)))
    (is (equal (list b) (context-children a)))
    (is (null (context-children b)))
    (dolist (slot (list #'context-facts #'context-goals #'context-meta))
      (is (equal (funcall slot a) (funcall slot b)))
      (is (not (eq (funcall slot a) (funcall slot b)))))
    (is (not (eq (getf (context-meta a) :k) (getf (context-meta b) :k))))))

(test modify-clears-a-slot-given-nil-and-copies-what-it-stores
  (let* ((meta (list :a (list 1 2)))
         (ctx (make-context :name 'n :meta '(:old t) :mode :plan
                            :facts '((f 1)))))
    (context-modify! ctx :meta meta)
    (is (equal meta (context-meta ctx)))
    (is (not (eq meta (context-meta ctx))))
    (is (not (eq (second meta) (second (context-meta ctx)))))
    ;; A supplied NIL clears the slot. A NIL mode and an absent key do not.
    (context-modify! ctx :name nil :meta nil :mode nil)
    (is (null (context-name ctx)))
    (is (null (context-meta ctx)))
    (is (eq :plan (context-mode ctx)))
    (is (equal '((f 1)) (context-facts ctx)))
    (context-modify! ctx :facts nil :mode 'execute)
    (is (null (context-facts ctx)))
    (is (eq :execute (context-mode ctx)))))
