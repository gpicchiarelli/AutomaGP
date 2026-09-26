;;;; tests/test-conditions.lisp — Phase 5 conditions & restarts

(in-package #:automa-gp/tests)

(def-suite conditions-suite :in automa-gp-suite)
(in-suite conditions-suite)

(defun failing-connect-op ()
  (make-operator :name 'connect
                 :preconditions '((power-state ?d on))
                 :add-list '((connection ?d computer))))

(defun power-on-op ()
  (make-operator :name 'power-on
                 :preconditions '((device ?d) (power-state ?d off))
                 :add-list '((power-state ?d on))
                 :delete-list '((power-state ?d off))))

(test retry-restart-succeeds
  (let* ((op (power-on-op))
         (facts '((device d1) (power-state d1 off)))
         (attempts 0)
         (b (unify '(power-state d1 on) '(power-state ?d on))))
    (multiple-value-bind (new result flag)
        (handler-bind ((action-failed
                        (lambda (c)
                          (declare (ignore c))
                          (invoke-restart :retry))))
          (call-with-gp-restarts
           (lambda ()
             (incf attempts)
             (if (= attempts 1)
                 (error 'action-failed :operator op :reason "transient")
                 (simulate-operator facts op b)))
           :operator op :bindings b :facts-on-skip facts
           :mode :simulate))
      (declare (ignore flag))
      (is (= 2 attempts))
      (is (fact-p '(power-state d1 on) new))
      (is (eq :ok (getf result :status))))))

(test skip-restart-continues
  (let* ((op (failing-connect-op))
         (facts '((device d1) (power-state d1 off)))
         (b (unify '(connection d1 computer) '(connection ?d computer))))
    (multiple-value-bind (new result flag)
        (handler-bind ((precondition-failure
                        (lambda (c)
                          (declare (ignore c))
                          (invoke-restart :skip))))
          (call-with-gp-restarts
           (lambda () (simulate-operator facts op b))
           :operator op :bindings b :facts-on-skip facts))
      (is (eq :skip flag))
      (is (eq :skipped (getf result :status)))
      (is (equal facts new)))))

(test abort-execution-restart
  (let* ((op (failing-connect-op))
         (facts '((power-state d1 off)))
         (b *no-bindings*))
    (multiple-value-bind (new result flag)
        (handler-bind ((precondition-failure
                        (lambda (c)
                          (declare (ignore c))
                          (invoke-restart :abort-execution))))
          (call-with-gp-restarts
           (lambda () (simulate-operator facts op b))
           :operator op :bindings b :facts-on-skip facts))
      (is (eq :abort flag))
      (is (eq :aborted (getf result :status)))
      (is (equal facts new)))))

(test use-value-restart
  (let* ((op (failing-connect-op))
         (facts '((device d1)))
         (supplied '((device d1) (connection d1 computer))))
    (multiple-value-bind (new result flag)
        (handler-bind ((precondition-failure
                        (lambda (c)
                          (declare (ignore c))
                          (invoke-restart :use-value supplied))))
          (call-with-gp-restarts
           (lambda () (simulate-operator facts op *no-bindings*))
           :operator op :facts-on-skip facts))
      (is (eq :use-value flag))
      (is (equal supplied new))
      (is (eq :use-value (getf result :status))))))

(test use-alternative-restart
  (let* ((bad (failing-connect-op))
         (good (make-operator :name 'force-connect
                              :preconditions '((device ?d))
                              :add-list '((connection ?d computer))))
         (facts '((device d1) (power-state d1 off)))
         (b (unify '(connection d1 computer) '(connection ?d computer))))
    (multiple-value-bind (new result flag)
        (handler-bind ((precondition-failure
                        (lambda (c)
                          (declare (ignore c))
                          (invoke-restart :use-alternative good))))
          (call-with-gp-restarts
           (lambda ()
             (simulate-operator facts
                                (or *gp-alternative-operator* bad)
                                b))
           :operator bad :bindings b :alternatives (list good)
           :facts-on-skip facts))
      (declare (ignore flag))
      (is (fact-p '(connection d1 computer) new))
      (is (eq :ok (getf result :status))))))

(test ask-user-restart
  (let* ((op (failing-connect-op))
         (facts '((device d1)))
         (*ask-user-fn* (lambda (c names)
                          (declare (ignore c names))
                          :skip)))
    (multiple-value-bind (new result flag)
        (handler-bind ((precondition-failure
                        (lambda (c)
                          (declare (ignore c))
                          (invoke-restart :ask-user))))
          (call-with-gp-restarts
           (lambda () (simulate-operator facts op *no-bindings*))
           :operator op :facts-on-skip facts))
      (is (eq :skip flag))
      (is (eq :skipped (getf result :status)))
      (is (equal facts new)))))

(test failure-strategy-skip-on-simulate-plan
  (let* ((ctx (create-context
               :facts '((device d1) (power-state d1 off))))
         (op (failing-connect-op)))
    (register-operator! ctx op)
    (let* ((plan (make-instance 'plan
                                :goals '((connection d1 computer))
                                :steps (list (list :operator 'connect
                                                   :bindings '((?d . d1))
                                                   :goal '(connection d1 computer)
                                                   :subgoals nil
                                                   :action nil
                                                   :cost 1))
                                :success t
                                :initial-state (context-all-facts ctx)
                                :final-state '((connection d1 computer))
                                :meta (list :operators (list op)))))
      (with-failure-strategy (:skip)
        (let ((result (simulate-plan plan :context ctx)))
          (is (execution-result-p result))
          (is (find :skip (execution-strategy-events result)
                    :key (lambda (e) (getf e :kind))))
          (is (member :skipped
                      (mapcar (lambda (s) (getf s :status))
                              (execution-steps result)))))))))

(test failure-strategy-alters-policy
  (with-failure-strategy (:abort)
    (is (eq :abort (strategy-policy *deliberative-strategy*)))
    (setf (strategy-policy *deliberative-strategy*) :retry)
    (is (eq :retry (strategy-policy *deliberative-strategy*)))))

(test confirm-restart-on-irreversible
  (let* ((ctx (create-context :facts '((device d1))))
         (op (make-operator :name 'wipe
                            :preconditions '((device ?d))
                            :add-list '((wiped ?d))
                            :reversible nil)))
    (multiple-value-bind (facts result)
        (handler-bind ((confirmation-required
                        (lambda (c)
                          (declare (ignore c))
                          (invoke-restart :confirm))))
          (execute-operator! ctx op '((?d . d1))))
      (is (fact-p '(wiped d1) facts))
      (is (eq :executed (getf result :status))))))
