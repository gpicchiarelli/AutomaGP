;;;; tests/test-induction.lisp — operator and rule induction from observed states

(in-package #:automa-gp/tests)

(def-suite induction-suite :in automa-gp-suite)
(in-suite induction-suite)

(test induce-operator-ignores-unrelated-facts
  (let ((op (induce-operator 'free-port
                             '((device interface-01) (port-bound 47391))
                             '((device interface-01) (port-free 47391)))))
    (is (equal '((port-bound 47391)) (operator-preconditions op)))
    (is (equal '((port-free 47391)) (operator-add-list op)))
    (is (equal '((port-bound 47391)) (operator-delete-list op)))
    (is (eq t (getf (operator-meta op) :induced)))))

(test induce-rule-lifts-the-shared-object
  (let ((op (induce-operator 'power-on
                             '((weather sunny)
                               (device interface-01)
                               (power-state interface-01 off))
                             '((weather sunny)
                               (device interface-01)
                               (power-state interface-01 on))
                             :generalize t)))
    (let ((x (find-symbol "?X0" :automa-gp)))
      (is (eq x (second (first (operator-preconditions op)))))
      (is (equal `((device ,x) (power-state ,x off))
                 (operator-preconditions op)))
      (is (equal `((power-state ,x on)) (operator-add-list op)))
      (is (equal `((power-state ,x off)) (operator-delete-list op)))
      (is (equal '(interface-01) (getf (operator-meta op) :generalized))))))

(test induce-rule-keeps-numbers-ground
  (let ((op (induce-operator 'free-port
                             '((device interface-01) (port-bound 47391))
                             '((device interface-01) (port-free 47391))
                             :generalize t)))
    (is (equal '((port-bound 47391)) (operator-preconditions op)))
    (is (equal '((port-free 47391)) (operator-add-list op)))
    (is (null (getf (operator-meta op) :generalized)))))

(test failed-plan-listens-and-the-learned-rule-replans
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (let ((failed (gp-plan :goals '((power-state interface-01 on)) :archive nil)))
    (is (not (plan-success failed)))
    (is (observation-active-p))
    (is (fact-p '(power-state interface-01 on) (getf (gp-observation) :missing))))
  (gp-remove-fact '(power-state interface-01 off))
  (gp-add-fact '(power-state interface-01 on))
  (gp-induce-rule 'power-on)
  (is (not (observation-active-p)))
  (gp-remove-fact '(power-state interface-01 on))
  (gp-remove-fact '(device interface-01))
  (gp-add-fact '(device interface-02))
  (gp-add-fact '(power-state interface-02 off))
  (let ((plan (gp-plan :goals '((power-state interface-02 on)) :archive nil)))
    (is (plan-success plan))
    (is (eq 'power-on (getf (first (plan-steps plan)) :operator)))
    (is (not (observation-active-p)))))

(test induce-operator-rejects-an-unchanged-state
  (signals induction-error (induce-operator 'noop '((folder notes missing))
                                            '((folder notes missing))))
  (loop for generalize in '(nil t)
        do (handler-case
               (progn
                 (induce-operator 'noop '((a 1) (b 2)) '((b 2) (a 1))
                                  :generalize generalize)
                 (fail "An unchanged state was induced."))
             (induction-error (c)
               (is (eq 'noop (induction-error-name c)))
               (is (eq :unchanged-state (induction-error-reason c)))
               (is (search "did not change" (princ-to-string c))))))
  (signals type-error (induce-operator nil '((a 1)) '((a 2)))))

(test learn-action-registers-the-induced-operator
  (gp-reset)
  (gp-add-fact '(folder notes missing))
  (gp-note-state)
  (gp-remove-fact '(folder notes missing))
  (gp-add-fact '(folder notes present))
  (let ((op (gp-learn-action 'create-folder)))
    (is (eq 'create-folder (operator-name op)))
    (is (equal '((folder notes missing)) (operator-preconditions op)))
    (is (equal '((folder notes present)) (operator-add-list op)))
    (is (operator-p (find-operator (gp-context) 'create-folder)))))

(test induce-rule-merges-a-second-example
  (gp-clear-memory)
  (gp-reset)
  (gp-induce-rule 'power-on
                  :before '((device interface-01) (power-state interface-01 off))
                  :after '((device interface-01) (power-state interface-01 on)))
  (let ((op (gp-induce-rule 'power-on
                            :before '((power-state interface-02 off) (device interface-02))
                            :after '((device interface-02) (power-state interface-02 on)))))
    (let ((x (find-symbol "?X0" :automa-gp)))
      (is (equal `((device ,x) (power-state ,x off))
                 (operator-preconditions op)))
      (is (equal `((power-state ,x on)) (operator-add-list op)))
      (is (= 2 (getf (operator-meta op) :examples)))
      (is (equal '(interface-01 interface-02)
                 (getf (operator-meta op) :generalized))))))

(test induce-rule-refuses-a-different-value-and-a-different-number
  (gp-clear-memory)
  (gp-reset)
  (gp-induce-rule 'power-on
                  :before '((device interface-01) (power-state interface-01 off))
                  :after '((device interface-01) (power-state interface-01 on)))
  (signals error
    (gp-induce-rule 'power-on
                    :before '((device interface-01) (power-state interface-01 off))
                    :after '((device interface-01) (power-state interface-01 ready))))
  (let ((op (find-operator (gp-context) 'power-on)))
    (is (= 1 (getf (operator-meta op) :examples)))
    (is (equal '(interface-01) (getf (operator-meta op) :generalized))))
  (gp-reset)
  (gp-induce-rule 'free-port
                  :before '((port-bound 47391))
                  :after '((port-free 47391)))
  (signals error
    (gp-induce-rule 'free-port
                    :before '((port-bound 47392))
                    :after '((port-free 47392))))
  (let ((op (find-operator (gp-context) 'free-port)))
    (is (equal '((port-bound 47391)) (operator-preconditions op)))
    (is (equal '((port-free 47391)) (operator-add-list op)))
    (is (= 1 (getf (operator-meta op) :examples)))))

(test learn-action-merges-a-second-ground-example
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(folder notes missing))
  (gp-note-state)
  (gp-learn-action 'create-folder
                   :before '((weather sunny) (folder notes missing))
                   :after '((folder notes present) (weather sunny)))
  (is (not (observation-active-p)))
  (let ((op (gp-learn-action 'create-folder
                             :before '((folder notes missing) (weather rainy))
                             :after '((weather rainy) (folder notes present)))))
    (is (equal '((folder notes missing)) (operator-preconditions op)))
    (is (equal '((folder notes present)) (operator-add-list op)))
    (is (equal '((folder notes missing)) (operator-delete-list op)))
    (is (= 2 (getf (operator-meta op) :examples)))
    (is (null (getf (operator-meta op) :generalized)))))

(test learn-action-refuses-a-different-constant
  (gp-clear-memory)
  (gp-reset)
  (gp-learn-action 'create-folder
                   :before '((folder notes missing))
                   :after '((folder notes present)))
  (gp-add-fact '(folder notes present))
  (gp-note-state)
  (signals error
    (gp-learn-action 'create-folder
                     :before '((folder photos missing))
                     :after '((folder photos present))))
  (is (observation-active-p))
  (let ((op (find-operator (gp-context) 'create-folder)))
    (is (equal '((folder notes missing)) (operator-preconditions op)))
    (is (= 1 (getf (operator-meta op) :examples))))
  (gp-reset)
  (gp-learn-action 'free-port
                   :before '((port-bound 47391))
                   :after '((port-free 47391)))
  (signals error
    (gp-learn-action 'free-port
                     :before '((port-bound 47392))
                     :after '((port-free 47392))))
  (let ((op (find-operator (gp-context) 'free-port)))
    (is (equal '((port-bound 47391)) (operator-preconditions op)))
    (is (equal '((port-free 47391)) (operator-add-list op)))
    (is (= 1 (getf (operator-meta op) :examples))))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'create-folder
                  :preconditions '((folder notes missing))
                  :add-list '((folder notes present))))
  (signals error
    (gp-learn-action 'create-folder
                     :before '((folder notes missing))
                     :after '((folder notes present))))
  (is (not (getf (operator-meta (find-operator (gp-context) 'create-folder))
                 :induced)))
  (gp-reset)
  (gp-induce-rule 'power-on
                  :before '((device interface-01) (power-state interface-01 off))
                  :after '((device interface-01) (power-state interface-01 on)))
  (signals error
    (gp-learn-action 'power-on
                     :before '((device interface-01) (power-state interface-01 off))
                     :after '((device interface-01) (power-state interface-01 on))))
  (let ((op (find-operator (gp-context) 'power-on)))
    (is (= 1 (getf (operator-meta op) :examples)))
    (is (equal '(interface-01) (getf (operator-meta op) :generalized)))))

(test induce-rule-lifts-a-repeated-symbol-from-two-examples
  (gp-clear-memory)
  (gp-reset)
  (gp-induce-rule 'paint
                  :before '()
                  :after '((left alpha) (right alpha)))
  (let ((op (gp-induce-rule 'paint
                            :before '()
                            :after '((right beta) (left beta)))))
    (let ((x (find-symbol "?X0" :automa-gp)))
      (is (equal `((left ,x) (right ,x)) (operator-add-list op)))
      (is (= 2 (getf (operator-meta op) :examples)))
      (is (member 'alpha (getf (operator-meta op) :generalized)))
      (is (member 'beta (getf (operator-meta op) :generalized))))))

;;; INDUCE-OPERATOR and MERGE-INDUCED-OPERATORS on their own

(defun %patterns (operator)
  "The preconditions, add-list and delete-list of OPERATOR."
  (list (operator-preconditions operator)
        (operator-add-list operator)
        (operator-delete-list operator)))

(defun %x (index)
  "The induction variable ?Xindex."
  (intern (format nil "?X~D" index) :automa-gp))

(defun %permutations (list)
  (if (null (rest list))
      (list list)
      (loop for item in list
            nconc (mapcar (lambda (tail) (cons item tail))
                          (%permutations (remove item list :count 1))))))

(test preconditions-are-the-facts-about-the-objects-of-the-change
  (loop for (before after preconditions)
          in '(;; MISSING is a value: the other missing folder is unrelated.
               (((folder notes missing) (folder photos missing) (disk notes ssd))
                ((folder notes present) (folder photos missing) (disk notes ssd))
                ((folder notes missing) (disk notes ssd)))
               ;; No term on both sides: only the removed fact is required.
               (((light off) (switch off) (weather sunny))
                ((light on) (switch off) (weather sunny))
                ((light off)))
               ;; Only additions: every term of them may be an object.
               (((disk d1) (color red) (disk d2))
                ((disk d1) (color red) (disk d2) (file f1 d1))
                ((disk d1)))
               ;; Only removals.
               (((disk d1) (file f1 d1) (file f2 d2))
                ((disk d1) (file f2 d2))
                ((disk d1) (file f1 d1)))
               ;; A number is an object like any other term.
               (((port-bound 47391) (owner 47391 daemon) (port-bound 47392))
                ((port-free 47391) (owner 47391 daemon) (port-bound 47392))
                ((port-bound 47391) (owner 47391 daemon))))
        do (let ((ground (induce-operator 'op before after))
                 (lifted (induce-operator 'op before after :generalize t)))
             (is (equal preconditions (operator-preconditions ground)))
             (is (null (getf (operator-meta ground) :generalized)))
             ;; Lifting renames terms; it selects the same facts.
             (is (equal (%patterns ground)
                        (sublis (loop for object in (getf (operator-meta lifted)
                                                          :generalized)
                                      for index from 0
                                      collect (cons (%x index) object))
                                (%patterns lifted)))))))

(test lifting-leaves-predicates-numbers-and-one-sided-values
  (loop for (before after patterns generalized)
          in `((((light light off)) ((light light on))
                (((light ,(%x 0) off)) ((light ,(%x 0) on)) ((light ,(%x 0) off)))
                (light))
               (((link b a closed)) ((link b a open))
                (((link ,(%x 1) ,(%x 0) closed)) ((link ,(%x 1) ,(%x 0) open))
                 ((link ,(%x 1) ,(%x 0) closed)))
                (a b))
               (((port 80 closed)) ((port 80 open))
                (((port 80 closed)) ((port 80 open)) ((port 80 closed)))
                ())
               (() ((left alpha) (right alpha))
                (() ((left alpha) (right alpha)) ())
                ())
               (((thing alpha)) ((thing alpha) (left alpha) (right alpha))
                (((thing ,(%x 0))) ((left ,(%x 0)) (right ,(%x 0))) ())
                (alpha)))
        do (let ((op (induce-operator 'op before after :generalize t)))
             (is (equal patterns (%patterns op)))
             (is (equal generalized (getf (operator-meta op) :generalized)))
             (is (eq t (getf (operator-meta op) :induced))))))

(test a-second-example-fits-whatever-its-objects-are-called
  (let ((first-example (induce-operator 'toggle
                                        '((link a b closed) (cable a))
                                        '((link a b open) (cable a))
                                        :generalize t)))
    (is (equal `(((link ,(%x 0) ,(%x 1) closed) (cable ,(%x 0)))
                 ((link ,(%x 0) ,(%x 1) open))
                 ((link ,(%x 0) ,(%x 1) closed)))
               (%patterns first-example)))
    (loop for (from to) in '((a b) (c d) (z y) (b a) (m m))
          do (loop for generalize in '(t nil)
                   do (let* ((second-example
                               (induce-operator
                                'toggle
                                `((cable ,from) (link ,from ,to closed))
                                `((link ,from ,to open) (cable ,from))
                                :generalize generalize))
                             (merged (merge-induced-operators first-example
                                                              second-example)))
                        (is (operator-p merged))
                        (when merged
                          (is (equal (%patterns first-example)
                                     (%patterns merged)))
                          (is (= 2 (getf (operator-meta merged) :examples)))
                          (is (subsetp (list 'a 'b from to)
                                       (getf (operator-meta merged)
                                             :generalized)))))))
    ;; The example is refused when one variable would stand for two objects.
    (is (null (merge-induced-operators
               first-example
               (induce-operator 'toggle
                                '((link c d closed) (cable d))
                                '((link c d open) (cable d))))))))

(test a-variable-stands-for-one-object-in-each-example
  (let* ((alpha (induce-operator 'paint '() '((left alpha) (right alpha))))
         (beta (induce-operator 'paint '() '((right beta) (left beta))))
         (merged (merge-induced-operators alpha beta)))
    (is (equal `(() ((left ,(%x 0)) (right ,(%x 0))) ())
               (%patterns merged)))
    (is (equal '(alpha beta) (getf (operator-meta merged) :generalized)))
    (is (= 2 (getf (operator-meta merged) :examples)))
    (loop for (left right fits) in '((gamma gamma t)
                                     (gamma delta nil)
                                     (alpha beta nil)
                                     (7 7 nil))
          for third = (merge-induced-operators
                       merged
                       (induce-operator 'paint '()
                                        `((right ,right) (left ,left))))
          do (if fits
                 (progn
                   (is (equal (%patterns merged) (%patterns third)))
                   (is (= 3 (getf (operator-meta third) :examples)))
                   (is (equal (list 'alpha 'beta left)
                              (getf (operator-meta third) :generalized))))
                 (is (null third))))
    ;; A refused example leaves the operator as it was.
    (is (= 2 (getf (operator-meta merged) :examples)))
    ;; Without lifting, only the same constants fit.
    (is (null (merge-induced-operators alpha beta :lift nil)))
    (let ((again (merge-induced-operators alpha alpha :lift nil)))
      (is (equal (%patterns alpha) (%patterns again)))
      (is (= 2 (getf (operator-meta again) :examples))))))

(test a-repeated-constant-becomes-the-next-variable
  (let* ((existing (make-operator
                    :name 'fetch
                    :preconditions '((holds ?x0 tool) (on tool bench))
                    :add-list '((at ?x0 bench))
                    :delete-list '((holds ?x0 tool))))
         (merged (merge-induced-operators
                  existing
                  (make-operator :name 'fetch
                                 :preconditions '((on saw table) (holds r2 saw))
                                 :add-list '((at r2 table))
                                 :delete-list '((holds r2 saw))))))
    (is (equal `(((holds ?x0 ,(%x 1)) (on ,(%x 1) ,(%x 2)))
                 ((at ?x0 ,(%x 2)))
                 ((holds ?x0 ,(%x 1))))
               (%patterns merged)))
    (is (equal '(r2 tool saw bench table)
               (getf (operator-meta merged) :generalized)))
    ;; EXISTING is not modified.
    (is (equal '(((holds ?x0 tool) (on tool bench))
                 ((at ?x0 bench))
                 ((holds ?x0 tool)))
               (%patterns existing)))
    (is (null (operator-meta existing)))
    (loop for (preconditions adds deletes)
            in '(;; BENCH would stand for TABLE and for SHELF.
                 (((on saw table) (holds r2 saw)) ((at r2 shelf)) ((holds r2 saw)))
                 ;; ?X0 would stand for R2 and for R3.
                 (((on saw table) (holds r2 saw)) ((at r3 table)) ((holds r2 saw)))
                 ;; A number is not an object symbol.
                 (((on saw 4) (holds r2 saw)) ((at r2 4)) ((holds r2 saw)))
                 (((on saw table) (holds 2 saw)) ((at 2 table)) ((holds 2 saw)))
                 ;; Another predicate, another length, another number of facts.
                 (((under saw table) (holds r2 saw)) ((at r2 table)) ((holds r2 saw)))
                 (((on saw table top) (holds r2 saw)) ((at r2 table)) ((holds r2 saw)))
                 (((on saw table)) ((at r2 table)) ((holds r2 saw)))
                 (((on saw table) (holds r2 saw) (clean saw)) ((at r2 table))
                  ((holds r2 saw)))
                 (((on saw table) (holds r2 saw)) ((at r2 table)) ()))
          do (is (null (merge-induced-operators
                        existing
                        (make-operator :name 'fetch
                                       :preconditions preconditions
                                       :add-list adds
                                       :delete-list deletes)))))))

(test a-symbol-that-occurs-once-is-not-lifted
  (let ((existing (induce-operator 'power-on
                                   '((device d1) (power-state d1 off))
                                   '((device d1) (power-state d1 on))
                                   :generalize t)))
    (loop for (value fits) in '((on t) (ready nil) (1 nil))
          do (is (eq fits
                     (and (merge-induced-operators
                           existing
                           (induce-operator 'power-on
                                            '((device d2) (power-state d2 off))
                                            `((device d2) (power-state d2 ,value))
                                            :generalize t))
                          t))))))

(test an-example-that-repeats-the-operator-lifts-nothing-in-any-order
  (let* ((before '((state a off) (state b off) (state c off)))
         (after '((state a on) (state b on) (state c on)))
         (existing (induce-operator 'all-on before after)))
    (loop for reordered-before in (%permutations before)
          do (loop for reordered-after in (%permutations after)
                   do (loop for lift in '(nil t)
                            for merged = (merge-induced-operators
                                          existing
                                          (induce-operator 'all-on
                                                           reordered-before
                                                           reordered-after)
                                          :lift lift)
                            do (is (operator-p merged))
                               (when merged
                                 (is (equal (%patterns existing)
                                            (%patterns merged)))))))
    ;; One object differs: refused as it stands, one variable when lifting.
    (loop for (lift patterns)
            in `((nil nil)
                 (t (((state a off) (state b off) (state ,(%x 0) off))
                     ((state a on) (state b on) (state ,(%x 0) on))
                     ((state a off) (state b off) (state ,(%x 0) off)))))
          for merged = (merge-induced-operators
                        existing
                        (induce-operator 'all-on
                                         '((state d off) (state b off) (state a off))
                                         '((state b on) (state d on) (state a on)))
                        :lift lift)
          do (is (equal patterns (and merged (%patterns merged)))))))

(test a-merge-keeps-everything-else-the-operator-carries
  (let* ((existing (induce-operator 'power-on
                                    '((device d1) (power-state d1 off))
                                    '((device d1) (power-state d1 on))
                                    :generalize t))
         (meta (list :ask '(:question "Which device?") :induced t
                     :external '(:program "true") :generalized '(d1))))
    (setf (operator-meta existing) meta
          (operator-risk existing) :high
          (operator-reversible existing) nil
          (operator-action existing) 'run-it
          (operator-parameters existing) '(?device)
          (operator-cost existing) 7)
    (let ((merged (merge-induced-operators
                   existing
                   (induce-operator 'power-on
                                    '((device d2) (power-state d2 off))
                                    '((device d2) (power-state d2 on))
                                    :generalize t))))
      (loop for (reader expected) in `((,#'operator-name power-on)
                                       (,#'operator-risk :high)
                                       (,#'operator-reversible nil)
                                       (,#'operator-action run-it)
                                       (,#'operator-parameters (?device))
                                       (,#'operator-cost 7))
            do (is (equal expected (funcall reader merged))))
      (loop for (key expected) in '((:ask (:question "Which device?"))
                                    (:external (:program "true"))
                                    (:induced t)
                                    (:examples 2)
                                    (:generalized (d1 d2)))
            do (is (equal expected (getf (operator-meta merged) key))))
      (is (not (eq merged existing)))
      (is (eq meta (operator-meta existing)))
      (is (null (getf meta :examples))))))

;;; The same through the REPL entry points

(test induce-rule-merges-by-role-and-refuses-what-does-not-fit
  (gp-clear-memory)
  (gp-reset)
  (gp-induce-rule 'toggle
                  :before '((link a b closed))
                  :after '((link a b open)))
  (let ((op (gp-induce-rule 'toggle
                            :before '((link z y closed))
                            :after '((link z y open)))))
    (is (equal `(((link ,(%x 0) ,(%x 1) closed))
                 ((link ,(%x 0) ,(%x 1) open))
                 ((link ,(%x 0) ,(%x 1) closed)))
               (%patterns op)))
    (is (= 2 (getf (operator-meta op) :examples)))
    (setf (getf (operator-meta op) :ask) '(:question "Which link?")
          (operator-risk op) :high))
  (signals error
    (gp-induce-rule 'toggle
                    :before '((link z y closed))
                    :after '((link z z open))))
  (let ((op (find-operator (gp-context) 'toggle)))
    (is (= 2 (getf (operator-meta op) :examples))))
  (let ((op (gp-induce-rule 'toggle
                            :before '((link p q closed))
                            :after '((link p q open)))))
    (is (= 3 (getf (operator-meta op) :examples)))
    (is (equal '(:question "Which link?") (getf (operator-meta op) :ask)))
    (is (eq :high (operator-risk op)))
    (is (eq op (find-operator (gp-context) 'toggle)))))

(test learn-action-merges-a-reordered-example-with-a-shared-predicate
  (gp-clear-memory)
  (gp-reset)
  (gp-learn-action 'both-on
                   :before '((state a off) (state b off) (folder notes missing)
                             (folder photos missing))
                   :after '((state a on) (state b on) (folder notes missing)
                            (folder photos missing)))
  (let ((op (gp-learn-action 'both-on
                             :before '((state b off) (state a off))
                             :after '((state b on) (state a on)))))
    (is (equal '(((state a off) (state b off))
                 ((state a on) (state b on))
                 ((state a off) (state b off)))
               (%patterns op)))
    (is (= 2 (getf (operator-meta op) :examples)))))
