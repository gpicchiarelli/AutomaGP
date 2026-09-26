;;;; tests/test-rules.lisp

(in-package #:automa-gp/tests)

(def-suite rules-suite :in automa-gp-suite)
(in-suite rules-suite)

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
