;;;; tests/test-state.lisp

(in-package #:automa-gp/tests)

(def-suite state-suite :in automa-gp-suite)
(in-suite state-suite)

(test state-from-context-and-compare
  (let* ((ctx (create-context :name 's
                              :facts '((a 1) (b 2))))
         (st (state-from-context ctx))
         (st2 (make-instance 'state :facts '((b 2) (a 1)))))
    (is (state-p st))
    (is (state-equal st st2))
    (let ((diff (compare-states st (make-instance 'state :facts '((a 1))))))
      (is (equal '((b 2)) (getf diff :facts-only-in-a)))
      (is-false (getf diff :equal)))))

(test state-kind-is-normalized-or-refused
  (dolist (kind *valid-state-kinds*)
    (is (eq kind (state-kind (make-state nil :kind kind))))
    (is (eq kind (state-kind
                  (make-state nil :kind (make-symbol (symbol-name kind)))))))
  (dolist (bad (list :bogus 'bogus 42 "current" nil))
    (signals unknown-keyword (make-state nil :kind bad)))
  (handler-case (make-state nil :kind :bogus)
    (unknown-keyword (c)
      (is (equal "state kind" (unknown-keyword-what c)))
      (is (search "Unknown state kind :BOGUS" (princ-to-string c)))))
  (is (eq :observed
          (state-kind
           (handler-bind ((unknown-keyword
                            (lambda (c)
                              (declare (ignore c))
                              (use-value 'observed))))
             (make-state nil :kind :bogus))))))

(test make-state-copies-its-fact-list
  (let* ((facts (list '(a 1) '(b 2)))
         (st (make-state facts :source 'here)))
    (is (eq 'here (state-source st)))
    (is (eq :current (state-kind st)))
    (is (equal facts (state-facts st)))
    (is (not (eq facts (state-facts st))))))

(test compare-states-reports-both-directions
  ;; Each case is (A B ONLY-IN-A ONLY-IN-B).
  (loop for (a b only-a only-b) in '((((a 1) (b 2)) ((b 2) (a 1)) () ())
                                     (((a 1) (b 2)) ((a 1)) ((b 2)) ())
                                     (((a 1)) ((a 1) (b 2)) () ((b 2)))
                                     (((a 1)) ((b 2)) ((a 1)) ((b 2)))
                                     (() () () ()))
        do (let* ((sa (make-state a :kind :expected))
                  (sb (make-state b :kind :observed))
                  (diff (compare-states sa sb))
                  (same (and (null only-a) (null only-b))))
             (is (equal only-a (getf diff :facts-only-in-a)))
             (is (equal only-b (getf diff :facts-only-in-b)))
             (is (eq same (getf diff :equal)))
             (is (eq same (and (state-equal sa sb) t)))
             (is (eq :expected (getf diff :kind-a)))
             (is (eq :observed (getf diff :kind-b))))))

(test a-state-transition-takes-the-same-options-as-a-fact-transition
  (let ((op (make-operator :name 'power-on :add-list '((power-state d1 on))))
        (st (make-state '((power-state d1 off)) :source 'here)))
    ;; Each case is (CONFLICT-RETRACT FACTS-AFTER).
    (loop for (retract after)
            in '((t ((power-state d1 on)))
                 (nil ((power-state d1 off) (power-state d1 on))))
          do (is (equal after
                        (transition-facts (state-facts st) op *no-bindings*
                                          :conflict-retract retract)))
             (is (equal after
                        (state-facts
                         (transition-state st op *no-bindings*
                                           :conflict-retract retract)))))
    (let ((next (transition-state st op *no-bindings*)))
      (is (equal '((power-state d1 on)) (state-facts next)))
      (is (eq :simulated (state-kind next)))
      (is (eq 'here (state-source next)))
      (is (equal '((power-state d1 off)) (state-facts st))))))
