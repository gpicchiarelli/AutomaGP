;;;; tests/test-rules.lisp

(in-package #:automa-gp/tests)

(def-suite rules-suite :in automa-gp-suite)
(in-suite rules-suite)

(defun %collecting-warnings (type thunk)
  "Call THUNK with every warning of TYPE muffled.
Returns the values of THUNK as a list, then the warnings in the order they
were signalled. Also used by tests/test-queries.lisp."
  (let ((seen nil))
    (values (handler-bind ((warning (lambda (w)
                                      (when (typep w type)
                                        (push w seen)
                                        (muffle-warning w)))))
              (multiple-value-list (funcall thunk)))
            (nreverse seen))))

(defun %rule-chain (length)
  "LENGTH rules where (STAGE k) derives (STAGE k+1). A round sees only the
facts of the rounds before it, so closing the chain takes LENGTH rounds."
  (loop for k from 0 below length
        collect (make-rule :name (list 'link k)
                           :if `((stage ,k))
                           :then `(stage ,(1+ k)))))

(test make-and-register-rule
  (let* ((ctx (create-context :name 'r))
         (rule (make-rule :name 'powered-when-on
                          :if '((device ?d) (power-state ?d on))
                          :then '(powered ?d))))
    (register-rule! ctx rule)
    (is (rule-p (first (rules-of ctx))))
    (is (equal '((device ?d) (power-state ?d on)) (rule-if rule)))
    (is (equal '((powered ?d)) (rule-then rule)))))

(test forward-chain-derives-fact
  (let* ((facts '((device interface-01)
                  (power-state interface-01 on)))
         (rules (list (make-rule :name 'r1
                                 :if '((device ?d) (power-state ?d on))
                                 :then '(powered ?d)))))
    (multiple-value-bind (all new) (forward-chain facts rules)
      (is (fact-p '(powered interface-01) all))
      (is (fact-p '(powered interface-01) new))
      (is (fact-p '(device interface-01) all)))))

(test rule-inheritance
  (let* ((parent (create-context :name 'p))
         (child (create-context :name 'c :parent parent)))
    (register-rule! parent (make-rule :name 'from-parent
                                      :if '((device ?d))
                                      :then '(known-device ?d)))
    (is (= 1 (length (context-all-rules child))))
    (is (eq 'from-parent (rule-name (first (context-all-rules child)))))))

(test variables-in-lists-named-variables-in-order
  (loop for (tree expected)
          in '(((powered ?d) (?d))
               (((link ?a ?b) (link ?b ?a)) (?a ?b ?b ?a))
               ((holds (pair ?x (?y))) (?x ?y))
               ((device ?) ())
               ((device interface-01) ())
               (?x (?x))
               (nil ()))
        do (is (equal expected (variables-in tree)))))

(test make-rule-refuses-a-consequent-variable-no-antecedent-binds
  (loop for (if then unbound)
          in '((((device ?d)) ((powered ?other)) (?other))
               (((device ?d)) ((link ?d ?other) (seen ?d)) (?other))
               (((device ?d)) ((link ?d ?)) (?))
               (((device ?)) ((powered ?d)) (?d))
               (() ((p ?x) (q ?y ?x)) (?x ?y)))
        do (handler-case
               (progn
                 (make-rule :name 'unsafe :if if :then then)
                 (fail "~S => ~S was built without UNSAFE-RULE." if then))
             (unsafe-rule (c)
               (is (eq 'unsafe (unsafe-rule-name c)))
               (is (equal unbound (unsafe-rule-variables c)))
               (is (search "is unsafe" (princ-to-string c))))))
  (loop for (if then)
          in '((((device ?d) (power-state ?d on)) ((powered ?d)))
               (((link ?a ?b)) ((link ?b ?a) (linked ?a)))
               (((device ?)) ((some-device)))
               (() ((axiom))))
        do (finishes (make-rule :if if :then then))))

(test an-unsafe-rule-built-on-request-concludes-ground-facts-only
  (let ((rule (handler-bind ((unsafe-rule #'continue))
                (make-rule :name 'unsafe
                           :if '((device ?d))
                           :then '((powered ?other) (seen ?d))))))
    (is (rule-p rule))
    (is (equal '((seen d1)) (rule-conclusions rule '((device d1)))))
    (multiple-value-bind (all new complete-p)
        (forward-chain '((device d1)) (list rule))
      (is (equal '((device d1) (seen d1)) all))
      (is (equal '((seen d1)) new))
      (is (eq t complete-p)))))

(test rule-conclusions-are-new-and-distinct
  (let ((rule (make-rule :if '((edge ?a ?b))
                         :then '((node ?a) (node ?b)))))
    (is (equal '((node a) (node b) (node c))
               (rule-conclusions rule '((edge a b) (edge b c)))))
    (is (equal '((node c))
               (rule-conclusions rule '((edge a b) (edge b c)
                                        (node a) (node b)))))
    (is (null (rule-conclusions rule '((node a)))))))

(test forward-chain-says-whether-it-reached-the-fixpoint
  (let* ((length 5)
         (rules (%rule-chain length))
         (facts (list '(stage 0))))
    (loop for limit from 0 to (+ length 2)
          for reached = (min limit length)
          do (multiple-value-bind (values warnings)
                 (%collecting-warnings
                  'forward-chain-incomplete
                  (lambda () (forward-chain facts rules :limit limit)))
               (destructuring-bind (all new complete-p) values
                 (is (equal (loop for k from 1 to reached collect `(stage ,k))
                            new))
                 (is (equal (cons '(stage 0) new) all))
                 (if (< limit length)
                     (progn
                       (is (null complete-p))
                       (is (= 1 (length warnings)))
                       (is (eql limit (forward-chain-incomplete-limit
                                       (first warnings)))))
                     (progn
                       (is (eq t complete-p))
                       (is (null warnings)))))))
    (is (equal '((stage 0)) facts))
    (let ((*forward-chain-limit* 2))
      (is (= 2 (length (nth-value
                        1 (handler-bind ((warning #'muffle-warning))
                            (forward-chain facts rules)))))))))

(test forward-chain-closes-a-recursive-rule
  (let ((rules (list (make-rule :name 'base
                                :if '((parent ?x ?y))
                                :then '(ancestor ?x ?y))
                     (make-rule :name 'step
                                :if '((parent ?x ?y) (ancestor ?y ?z))
                                :then '(ancestor ?x ?z)))))
    (loop for length from 1 to 6
          for facts = (loop for k from 0 below length
                            collect `(parent ,k ,(1+ k)))
          do (multiple-value-bind (all new complete-p)
                 (forward-chain facts rules)
               (is (eq t complete-p))
               (is (= (/ (* length (1+ length)) 2) (length new)))
               (is (loop for i from 0 to length
                         always (loop for j from 0 to length
                                      always (eq (< i j)
                                                 (and (fact-p `(ancestor ,i ,j)
                                                              all)
                                                      t)))))))))

(test register-rule-puts-the-newest-rule-first
  (let ((ctx (create-context :name 'order)))
    (flet ((conclusions ()
             (mapcar (lambda (rule) (first (rule-then rule))) (rules-of ctx))))
      (register-rule! ctx (make-rule :name 'r1 :if '(a) :then '(one)))
      (register-rule! ctx (make-rule :if '(a) :then '(two)))
      (register-rule! ctx (make-rule :name 'r3 :if '(a) :then '(three)))
      (register-rule! ctx (make-rule :if '(a) :then '(four)))
      (is (equal '((four) (three) (two) (one)) (conclusions)))
      (register-rule! ctx (make-rule :name 'r1 :if '(a) :then '(one-again)))
      (is (equal '((one-again) (four) (three) (two)) (conclusions)))
      (remove-rule! ctx 'r3)
      (is (equal '((one-again) (four) (two)) (conclusions))))))

(test a-local-rule-shadows-the-ancestor-rule-of-the-same-name
  (let* ((root (create-context :name 'root))
         (middle (create-context :name 'middle :parent root))
         (leaf (create-context :name 'leaf :parent middle)))
    (register-rule! root (make-rule :name 'shared :if '(a) :then '(from-root)))
    (register-rule! root (make-rule :if '(a) :then '(root-unnamed)))
    (register-rule! middle (make-rule :name 'shared :if '(a) :then '(from-middle)))
    (register-rule! middle (make-rule :name 'middle-only :if '(a) :then '(middle)))
    (register-rule! leaf (make-rule :if '(a) :then '(leaf-unnamed)))
    (loop for (context expected)
            in `((,leaf ((leaf-unnamed) (middle) (from-middle) (root-unnamed)))
                 (,middle ((middle) (from-middle) (root-unnamed)))
                 (,root ((root-unnamed) (from-root))))
          do (is (equal expected
                        (mapcar (lambda (rule) (first (rule-then rule)))
                                (context-all-rules context)))))))
