;;;; tests/test-queries.lisp

(in-package #:automa-gp/tests)

(def-suite queries-suite :in automa-gp-suite)
(in-suite queries-suite)

(defun %lineage (length &key left-recursive)
  "A context where K is the parent of K+1 for each K below LENGTH, with the
two rules that define ANCESTOR. The recursive rule calls itself last, or
first when LEFT-RECURSIVE."
  (let ((ctx (create-context
              :name 'lineage
              :facts (loop for k from 0 below length
                           collect `(parent ,k ,(1+ k))))))
    (register-rule! ctx (make-rule :name 'ancestor-step
                                   :if (if left-recursive
                                           '((ancestor ?x ?y) (parent ?y ?z))
                                           '((parent ?x ?y) (ancestor ?y ?z)))
                                   :then '(ancestor ?x ?z)))
    (register-rule! ctx (make-rule :name 'ancestor-base
                                   :if '((parent ?x ?y))
                                   :then '(ancestor ?x ?y)))
    ctx))

(defun %answers (variable hits)
  "What VARIABLE is bound to in each of HITS."
  (mapcar (lambda (hit) (cdr (assoc variable (getf hit :bindings)))) hits))

(defun %searching (thunk)
  "Call THUNK, a QUERY or PROVE call. Returns its answers, its COMPLETE-P,
and the limit named by each QUERY-INCOMPLETE warning it signalled."
  (multiple-value-bind (values warnings)
      (%collecting-warnings 'query-incomplete thunk)
    (values (first values)
            (second values)
            (mapcar #'query-incomplete-limit warnings))))

(defun %looping-context (facts &rest rules)
  "A context holding FACTS and one rule for each (CONSEQUENT . ANTECEDENTS)."
  (let ((ctx (create-context :name 'looping :facts facts)))
    (loop for (then . if) in rules
          do (register-rule! ctx (make-rule :if if :then then)))
    ctx))

(test query-facts-only
  (let ((ctx (create-context :name 'q
                             :facts '((device a) (device b)
                                      (power-state a on)))))
    (multiple-value-bind (hits complete-p) (query '(device ?x) ctx :infer nil)
      (is (= 2 (length hits)))
      (is (eq :fact (getf (first hits) :source)))
      (is (eq t complete-p)))))

(test query-with-backward-chain
  (let* ((ctx (create-context
               :name 'q
               :facts '((device interface-01)
                        (power-state interface-01 on)))))
    (register-rule! ctx
                    (make-rule :name 'powered-when-on
                               :if '((device ?d) (power-state ?d on))
                               :then '(powered ?d)))
    (let ((hits (query '(powered ?x) ctx :infer t)))
      (is (plusp (length hits)))
      (is (equal '(powered interface-01) (getf (first hits) :fact)))
      (is (equal 'interface-01
                 (cdr (assoc '?x (getf (first hits) :bindings) :test #'eq)))))
    (is (null (query '(powered ?x) ctx :infer nil)))))

(test query-bindings-helper
  (let ((ctx (create-context :facts '((device-type interface-01 audio-interface)))))
    (multiple-value-bind (binds complete-p)
        (query-bindings '(device-type ?x audio-interface) ctx :infer nil)
      (is (= 1 (length binds)))
      (is (equal 'interface-01 (cdr (assoc '?x (first binds) :test #'eq))))
      (is (eq t complete-p)))))

(test a-recursive-rule-answers-at-every-chain-length
  (loop for length in '(1 2 3 5 8 13)
        for ctx = (%lineage length)
        do (multiple-value-bind (hits complete-p limits)
               (%searching (lambda () (query '(ancestor 0 ?w) ctx)))
             (is (equal (loop for k from 1 to length collect k)
                        (sort (%answers '?w hits) #'<)))
             (is (every (lambda (hit) (eq :rule (getf hit :source))) hits))
             (is (eq t complete-p))
             (is (null limits)))
           (multiple-value-bind (hits complete-p limits)
               (%searching (lambda () (query '(ancestor ?a ?d) ctx)))
             (is (= (/ (* length (1+ length)) 2) (length hits)))
             (is (every (lambda (hit)
                          (destructuring-bind (ancestor a d) (getf hit :fact)
                            (declare (ignore ancestor))
                            (< a d)))
                        hits))
             (is (eq t complete-p))
             (is (null limits)))
           (is (loop for i from 0 to length
                     always (loop for j from 0 to length
                                  always (eq (< i j)
                                             (and (query `(ancestor ,i ,j) ctx)
                                                  t)))))))

(test a-query-may-share-variable-names-with-the-rules
  (let ((ctx (%lineage 3))
        (pairs '((0 . 1) (0 . 2) (0 . 3) (1 . 2) (1 . 3) (2 . 3))))
    (loop for (a d) in '((?x ?z) (?z ?x) (?x ?y) (?y ?x) (?y ?z) (?z ?y)
                         (?q ?r))
          do (is (equal pairs
                        (sort (mapcar (lambda (bindings)
                                        (cons (cdr (assoc a bindings))
                                              (cdr (assoc d bindings))))
                                      (query-bindings `(ancestor ,a ,d) ctx))
                              (lambda (p q)
                                (or (< (car p) (car q))
                                    (and (= (car p) (car q))
                                         (< (cdr p) (cdr q))))))))
             (is (equal '(0 1 2)
                        (sort (%answers a (query `(ancestor ,a 3) ctx)) #'<)))
             (is (equal '(1 2 3)
                        (sort (%answers d (query `(ancestor 0 ,d) ctx)) #'<)))
             (is (null (query `(ancestor ,a ,a) ctx))))))

(test a-rule-that-calls-its-own-goal-terminates
  (loop for (goal answers ctx)
          in (list
              (list '(p ?w) '(a)
                    (%looping-context '((p a)) '((p ?x) (p ?x))))
              (list '(p ?w) '(a)
                    (%looping-context '((p a)) '((p ?x) (p ?x) (p ?x))))
              (list '(q ?w) '(a)
                    (%looping-context '((p a))
                                      '((p ?x) (q ?x)) '((q ?x) (p ?x))))
              (list '(connected b ?w) '(a c)
                    (%looping-context '((connected a b) (connected b c))
                                      '((connected ?x ?y) (connected ?y ?x)))))
        do (multiple-value-bind (hits complete-p limits)
               (%searching (lambda () (query goal ctx)))
             (is (equal answers
                        (sort (%answers '?w hits) #'string<)))
             (is (eq t complete-p))
             (is (null limits)))
           (is (= (length answers)
                  (length (prove goal (context-all-facts ctx)
                                 (context-all-rules ctx)))))))

(test a-left-recursive-rule-answers-and-reports-the-depth-limit
  (let ((ctx (%lineage 4 :left-recursive t)))
    (multiple-value-bind (hits complete-p limits)
        (%searching (lambda () (query '(ancestor 0 ?w) ctx)))
      (is (equal '(1 2 3 4) (sort (%answers '?w hits) #'<)))
      (is (null complete-p))
      (is (equal '(:depth) limits)))
    (multiple-value-bind (hits complete-p limits)
        (%searching (lambda () (query '(ancestor 0 4) ctx)))
      (is (equal '(ancestor 0 4) (getf (first hits) :fact)))
      (is (= 1 (length hits)))
      (is (eq t complete-p))
      (is (null limits)))
    (multiple-value-bind (hits complete-p limits)
        (%searching (lambda () (query '(ancestor 4 0) ctx)))
      (is (null hits))
      (is (null complete-p))
      (is (equal '(:depth) limits)))
    (let ((warning (handler-case (query '(ancestor 0 ?w) ctx)
                     (query-incomplete (w) w))))
      (is (typep warning 'query-incomplete))
      (is (equal '(ancestor 0 ?w) (query-incomplete-goal warning)))
      (is (search "*QUERY-DEPTH-LIMIT*" (princ-to-string warning))))))

(test the-step-limit-stops-a-search-that-grows-exponentially
  (let ((ctx (%looping-context '((path a b) (path b c) (path c a) (path c d))
                               '((path ?x ?z) (path ?x ?y) (path ?y ?z)))))
    (loop for steps in '(1 2 4 8 16 500 4000)
          do (let ((*query-step-limit* steps))
               (multiple-value-bind (hits complete-p limits)
                   (%searching (lambda () (query '(path a ?w) ctx)))
                 (is (member 'b (%answers '?w hits)))
                 (is (subsetp (%answers '?w hits) '(a b c d)))
                 (is (null complete-p))
                 (is (= 1 (length limits)))
                 ;; The first dive needs more steps than the depth limit.
                 (when (< steps *query-depth-limit*)
                   (is (equal '(:steps) limits))))
               ;; One proof settles a goal without variables.
               (multiple-value-bind (hits complete-p limits)
                   (%searching (lambda () (query '(path a b) ctx)))
                 (is (= 1 (length hits)))
                 (is (eq :fact (getf (first hits) :source)))
                 (is (eq t complete-p))
                 (is (null limits)))))
    (let ((*query-step-limit* 0))
      (multiple-value-bind (hits complete-p limits)
          (%searching (lambda () (query '(path a ?w) ctx)))
        (is (null hits))
        (is (null complete-p))
        (is (equal '(:steps) limits))))))

(test the-depth-limit-counts-rule-applications
  (let ((facts '((stage 0)))
        (rules (%rule-chain 6)))
    (loop for limit from 0 to 6
          do (loop for needed from 0 to 6
                   do (let ((*query-depth-limit* limit))
                        (multiple-value-bind (solutions complete-p limits)
                            (%searching
                             (lambda () (prove `(stage ,needed) facts rules)))
                          (if (<= needed limit)
                              (progn
                                (is (= 1 (length solutions)))
                                (is (eq t complete-p))
                                (is (null limits)))
                              (progn
                                (is (null solutions))
                                (is (null complete-p))
                                (is (equal '(:depth) limits))))))))))

(test prove-extends-the-bindings-it-is-given
  (let ((facts '((parent a b) (parent b c) (parent a d))))
    (is (equal '(b d)
               (mapcar (lambda (b) (substitute-bindings '?y b))
                       (prove '(parent ?x ?y) facts nil '((?x . a))))))
    (is (null (prove '(parent ?x ?y) facts nil '((?x . c)))))
    (multiple-value-bind (solutions complete-p)
        (prove-all '((parent ?x ?y) (parent ?y ?z)) facts nil *no-bindings* 0)
      (is (equal '(((?x . a) (?y . b) (?z . c)))
                 (mapcar (lambda (b) (instantiate-bindings '(?x ?y ?z) b))
                         solutions)))
      (is (eq t complete-p)))
    (is (equal (list *no-bindings*)
               (prove-all nil facts nil *no-bindings* 0)))))

(test instantiate-bindings-resolves-values-in-depth
  (loop for (pattern bindings expected)
          in '(((holds ?x) ((?x . (pair ?y)) (?y . a)) ((?x . (pair a))))
               ((p ?x ?y) ((?x . ?y) (?y . 1)) ((?x . 1) (?y . 1)))
               ((p ?x ?z) ((?x . 1)) ((?x . 1) (?z . ?z)))
               ((p ?x (q ?x) ?) ((?x . a)) ((?x . a)))
               ((p ?x) () ((?x . ?x)))
               ((p a) ((?x . 1)) ()))
        do (is (equal expected (instantiate-bindings pattern bindings))))
  (is (equal '((?x . ?x))
             (instantiate-bindings '(p ?x) *no-bindings*)))
  ;; MATCH against data that holds variables can bind them in a circle.
  (is (equal '(?x ?y)
             (mapcar #'car (instantiate-bindings
                            '(p ?x ?y)
                            (match '(p ?x ?y) '(p ?y ?x)))))))

(test query-fills-in-what-an-anonymous-variable-stood-for
  (let ((ctx (create-context :name 'q
                             :facts '((device a) (device b)
                                      (power-state a on)))))
    (register-rule! ctx (make-rule :name 'powered-when-on
                                   :if '((device ?d) (power-state ?d ?))
                                   :then '(powered ?d)))
    (loop for (pattern . expected)
            in '(((device ?)
                  (:bindings nil :fact (device a) :source :fact)
                  (:bindings nil :fact (device b) :source :fact))
                 ((power-state ? ?)
                  (:bindings nil :fact (power-state a on) :source :fact))
                 ((power-state ?x ?)
                  (:bindings ((?x . a)) :fact (power-state a on) :source :fact))
                 ((powered ?)
                  (:bindings nil :fact (powered a) :source :rule)))
          do (is (equal expected (query pattern ctx)))
             (when (eq :fact (getf (first expected) :source))
               (is (equal expected (query pattern ctx :infer nil)))))))

(test query-hits-are-distinct-and-name-their-source
  (let ((ctx (create-context
              :name 'diamond
              :facts '((parent a b1) (parent a b2)
                       (parent b1 c) (parent b2 c)
                       (grandparent a z)))))
    (register-rule! ctx (make-rule :name 'grandparent
                                   :if '((parent ?x ?y) (parent ?y ?z))
                                   :then '(grandparent ?x ?z)))
    (register-rule! ctx (make-rule :name 'known
                                   :if '((parent ?x ?y))
                                   :then '(grandparent a z)))
    (is (= 2 (length (prove '(grandparent a c) (context-all-facts ctx)
                            (context-all-rules ctx)))))
    (is (equal '((:bindings ((?w . z)) :fact (grandparent a z) :source :fact)
                 (:bindings ((?w . c)) :fact (grandparent a c) :source :rule))
               (query '(grandparent a ?w) ctx)))))

(test backward-chaining-agrees-with-the-forward-closure
  ;; :COMPLETE programs must be answered in full and say so. :ANSWERED ones
  ;; lose no answer here although the search cannot rule one out. A :SOUND
  ;; one outgrows the step limit: whatever it answers must still be true.
  (loop for (expect steps facts rules patterns)
          in '((:complete nil
                ((edge a b) (edge b c) (edge c a) (edge c d))
                (((path ?x ?y) (edge ?x ?y))
                 ((path ?x ?z) (edge ?x ?y) (path ?y ?z)))
                ((path a ?w) (path ?v ?w) (path d ?w) (path ?v a)
                 (path a a) (path d a)))
               (:answered nil
                ((edge a b) (edge b c) (edge c a) (edge c d))
                (((path ?x ?y) (edge ?x ?y))
                 ((path ?x ?z) (path ?x ?y) (edge ?y ?z)))
                ((path a ?w) (path ?v ?w) (path d ?w) (path a a) (path d a)))
               (:complete nil
                ((married a b) (married c d))
                (((married ?x ?y) (married ?y ?x)))
                ((married ?v ?w) (married b ?w) (married b a) (married a c)))
               (:complete nil
                ((zero n0) (succ n0 n1) (succ n1 n2) (succ n2 n3) (succ n3 n4))
                (((even ?x) (zero ?x))
                 ((even ?y) (succ ?x ?y) (odd ?x))
                 ((odd ?y) (succ ?x ?y) (even ?x)))
                ((even ?w) (odd ?w) (even n4) (odd n4) (even ?) (odd n0)))
               (:complete nil
                ((parent r a) (parent r b) (parent a a1) (parent a a2)
                 (parent b b1) (parent a1 x) (parent b1 y))
                (((same-generation ?x ?y) (parent ?p ?x) (parent ?p ?y))
                 ((same-generation ?x ?y)
                  (parent ?px ?x) (same-generation ?px ?py) (parent ?py ?y)))
                ((same-generation ?v ?w) (same-generation x ?w)
                 (same-generation x y) (same-generation x a)))
               (:sound 2000
                ((link a b) (link b c) (link c d))
                (((connected ?x ?y) (link ?x ?y))
                 ((connected ?x ?y) (connected ?y ?x))
                 ((connected ?x ?z) (connected ?x ?y) (connected ?y ?z)))
                ((connected a ?w) (connected ?v ?w) (connected a d))))
        for ctx = (apply #'%looping-context facts rules)
        for closure = (forward-chain (context-all-facts ctx)
                                     (context-all-rules ctx))
        do (loop for pattern in patterns
                 for expected = (mapcar #'car (find-facts pattern closure))
                 do (multiple-value-bind (hits complete-p limits)
                        (let ((*query-step-limit* (or steps *query-step-limit*)))
                          (%searching (lambda () (query pattern ctx))))
                      (let ((answers (mapcar (lambda (hit) (getf hit :fact))
                                             hits)))
                        (is (subsetp answers expected :test #'equal))
                        (is (= (length answers)
                               (length (remove-duplicates answers
                                                          :test #'equal))))
                        (unless (eq expect :sound)
                          (is (subsetp expected answers :test #'equal)))
                        (is (eq (null limits) (and complete-p t)))
                        (when (eq expect :complete)
                          (is (eq t complete-p))))))))
