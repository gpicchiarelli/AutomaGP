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

;;; --- Strategy scope: one run, one step ---

(defun force-connect-op ()
  (make-operator :name 'force-connect
                 :preconditions '((device ?d))
                 :add-list '((connection ?d computer))))

(defun %failing-connect-plan ()
  "A one-step plan whose step lacks its precondition in the context.
Returns (VALUES PLAN CONTEXT)."
  (let ((ctx (create-context :facts '((device d1) (power-state d1 off))))
        (op (failing-connect-op)))
    (register-operator! ctx op)
    (values (make-instance 'plan
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
                           :meta (list :operators (list op)))
            ctx)))

(defun %event-kinds (events)
  "Kinds of EVENTS, oldest first."
  (reverse (mapcar (lambda (event) (getf event :kind)) events)))

(defun %step-statuses (result)
  (mapcar (lambda (step) (getf step :status)) (execution-steps result)))

(test strategy-events-belong-to-one-run
  (multiple-value-bind (plan ctx) (%failing-connect-plan)
    (with-failure-strategy (:skip)
      (dotimes (run 3)
        (let* ((result (simulate-plan plan :context ctx))
               (events (execution-strategy-events result)))
          (is (equal '(:skip) (%event-kinds events)))
          (is (eq (trace-id (trace-of result))
                  (getf (first events) :trace-id)))))
      ;; Outside a run the strategy still shows the whole session.
      (is (= 3 (length (strategy-events-of))))
      (is (= 3 (length (strategy-skipped *deliberative-strategy*)))))))

(test retry-limit-applies-to-each-step
  (with-failure-strategy (:retry :retry-limit 2)
    (dotimes (step 3)
      (let ((attempts 0))
        (multiple-value-bind (facts result flag)
            (handler-bind ((gp-error #'plan-runner-condition-handler))
              (call-with-gp-restarts
               (lambda ()
                 (incf attempts)
                 (if (< attempts 3)
                     (error 'action-failed :reason "transient")
                     (values '((a 1)) :done)))
               :facts-on-skip '((x 0))))
          (is (= 3 attempts))
          (is (equal '((a 1)) facts))
          (is (eq :done result))
          (is (null flag)))))
    ;; The strategy still counts every retry it recorded.
    (is (= 6 (strategy-retry-count *deliberative-strategy*)))))

(test exhausted-retry-limit-is-recorded
  (with-failure-strategy (:retry :retry-limit 2)
    (let ((attempts 0))
      (multiple-value-bind (facts result flag)
          (handler-bind ((gp-error #'plan-runner-condition-handler))
            (call-with-gp-restarts
             (lambda ()
               (incf attempts)
               (error 'action-failed :reason "permanent"))
             :operator (power-on-op)
             :facts-on-skip '((x 0))))
        (is (= 3 attempts))
        (is (eq :abort flag))
        (is (eq :aborted (getf result :status)))
        (is (equal '((x 0)) facts))
        (is (equal '(:retry :retry :retry-exhausted :abort)
                   (%event-kinds (strategy-events-of))))
        (let ((exhausted (find :retry-exhausted (strategy-events-of)
                               :key (lambda (event) (getf event :kind)))))
          (is (eq 'power-on (getf exhausted :operator)))
          (is (eql 2 (getf exhausted :limit))))))))

(test signal-policy-leaves-the-choice-to-outer-handlers
  ;; Each case is (POLICY DEFAULT-ABORT OUTER-HANDLER-RUNS STEP-STATUS).
  ;; Without a strategy the runner aborts the step by default. A :SIGNAL
  ;; strategy asks for the condition itself.
  (dolist (case '((nil t nil :aborted)
                  (nil nil t :skipped)
                  (:signal t t :skipped)
                  (:signal nil t :skipped)
                  (:abort nil nil :aborted)
                  (:skip t nil :skipped)))
    (destructuring-bind (policy default-abort outer-runs status) case
      (multiple-value-bind (plan ctx) (%failing-connect-plan)
        (let* ((ran nil)
               (*plan-runner-default-abort* default-abort)
               (*deliberative-strategy* (and policy (make-strategy :policy policy)))
               (result (handler-bind ((precondition-failure
                                       (lambda (c)
                                         (declare (ignore c))
                                         (setf ran t)
                                         (invoke-restart :skip))))
                         (simulate-plan plan :context ctx))))
          (is (eq outer-runs ran) "policy ~S, default abort ~S" policy default-abort)
          (is (equal (list status) (%step-statuses result))
              "policy ~S, default abort ~S" policy default-abort))))))

(test strategy-policy-is-checked
  (signals type-error (make-strategy :policy :bogus))
  (signals type-error (make-strategy :policy nil))
  (dolist (limit '(-1 1.5 :many nil))
    (signals type-error (make-strategy :policy :retry :retry-limit limit)))
  (dolist (policy '(:signal :skip :retry :abort :ask))
    (is (eq policy (strategy-policy (make-strategy :policy policy)))))
  (is (zerop (strategy-retry-limit (make-strategy :policy :retry
                                                  :retry-limit 0)))))

(test exhausted-retry-limit-without-default-abort-reaches-the-caller
  ;; Each case is (RETRY-LIMIT ATTEMPTS).
  (dolist (case '((0 1) (1 2) (3 4)))
    (destructuring-bind (limit expected) case
      (with-failure-strategy (:retry :retry-limit limit)
        (let* ((attempts 0)
               (*plan-runner-default-abort* nil)
               (failure
                 (handler-case
                     (handler-bind ((gp-error #'plan-runner-condition-handler))
                       (call-with-gp-restarts
                        (lambda ()
                          (incf attempts)
                          (error 'action-failed :reason "permanent"))))
                   (action-failed (c) c))))
          (is (typep failure 'action-failed))
          (is (= expected attempts))
          (is (eq :retry-exhausted
                  (getf (first (strategy-events-of)) :kind))))))))

(test strategy-declines-outside-a-step
  ;; No restart is active here, so every policy leaves the condition alone.
  (let ((failure (make-condition 'action-failed :reason "nowhere")))
    (is (null (let ((*deliberative-strategy* nil))
                (maybe-invoke-strategy failure))))
    (dolist (policy '(:signal :skip :retry :abort :ask))
      (with-failure-strategy (policy)
        (is (null (maybe-invoke-strategy failure)))
        (is (null (plan-runner-condition-handler failure)))
        (is (null (strategy-events-of)))))))

(test strategy-events-are-recorded-only-on-a-strategy
  (let ((*deliberative-strategy* nil))
    (is (eq :skip (record-strategy-event :skip :operator 'connect)))
    (is (null (strategy-events-of))))
  (let ((strategy (make-strategy :policy :skip)))
    (let ((*deliberative-strategy* strategy))
      (is (eq :skip (record-strategy-event :skip :operator 'connect)))
      (is (eq :retry (record-strategy-event :retry :operator 'connect))))
    ;; The strategy can be read when it is no longer the current one.
    (is (equal '(:skip :retry) (%event-kinds (strategy-events-of strategy))))
    (is (not (eq (strategy-events strategy) (strategy-events-of strategy))))
    (is (equal '(connect) (strategy-skipped strategy)))
    (is (= 1 (strategy-retry-count strategy)))
    (is (null (getf (first (strategy-events strategy)) :trace-id)))))

;;; --- Recoveries ---

(defun %recover (alternative invoke &optional answer)
  "Fail a CONNECT step once and recover by invoking the restart INVOKE,
a list of a restart name and its arguments. ANSWER is what *ASK-USER-FN*
returns. The second attempt succeeds, through ALTERNATIVE.
Returns what the step returned and the events recorded, :ASK-USER aside."
  (let* ((bad (failing-connect-op))
         (facts '((device d1) (power-state d1 off)))
         (b '((?d . d1)))
         (attempts 0)
         (*ask-user-fn* (lambda (c names)
                          (declare (ignore c names))
                          answer)))
    (with-failure-strategy (:signal)
      (multiple-value-bind (new result flag)
          (handler-bind ((precondition-failure
                          (lambda (c)
                            (declare (ignore c))
                            (apply #'invoke-restart invoke))))
            (call-with-gp-restarts
             (lambda ()
               (incf attempts)
               (simulate-operator facts
                                  (or *gp-alternative-operator*
                                      (if (> attempts 1) alternative bad))
                                  b))
             :operator bad :bindings b :alternatives (list alternative)
             :facts-on-skip facts :mode :simulate))
        (list new (getf result :status) flag attempts
              (loop for event in (reverse (strategy-events-of))
                    unless (eq :ask-user (getf event :kind))
                      collect (list (getf event :kind)
                                    (getf event :operator)
                                    (getf event :replaced)
                                    (getf event :mode))))))))

(test ask-user-takes-the-same-recoveries-as-the-restarts
  (let ((good (force-connect-op))
        (supplied '((device d1) (connection d1 computer))))
    ;; Each case is (RESTART-AND-ARGUMENTS ANSWER-TO-ASK-USER).
    (dolist (case `(((:retry) :retry)
                    ((:skip) :skip)
                    ((:abort-execution) :abort-execution)
                    ((:use-value ,supplied) (:use-value . ,supplied))
                    ((:use-alternative ,good) (:use-alternative . ,good))
                    ((:use-alternative) :use-alternative)))
      (destructuring-bind (restart answer) case
        (let ((direct (%recover good restart))
              (asked (%recover good '(:ask-user) answer)))
          (is (equal direct asked) "~S gave ~S, asked gave ~S"
              (first restart) direct asked)
          (is (= 1 (length (fifth direct)))))))))

(test ask-policy-shows-the-failure-itself
  (multiple-value-bind (plan ctx) (%failing-connect-plan)
    (let* ((seen nil)
           (*ask-user-fn* (lambda (c names)
                            (setf seen (list c names))
                            :skip)))
      (with-failure-strategy (:ask)
        (let ((result (simulate-plan plan :context ctx)))
          (is (typep (first seen) 'precondition-failure))
          (is (equal '(:retry :skip :abort-execution :use-value :use-alternative)
                     (second seen)))
          (is (equal '(:skipped) (%step-statuses result)))
          (is (equal '(:ask-user :skip)
                     (%event-kinds (execution-strategy-events result)))))))))

(test ask-user-event-records-the-name-chosen
  ;; Each case is (ANSWER CHOICE-RECORDED). The argument of the answer, a
  ;; fact list or an operator, is not copied into the :ASK-USER event.
  (dolist (case `((:skip :skip)
                  ((:use-value (a 1)) :use-value)
                  ((:use-alternative . ,(force-connect-op)) :use-alternative)))
    (destructuring-bind (answer recorded) case
      (let ((*ask-user-fn* (lambda (c names)
                             (declare (ignore c names))
                             answer)))
        (with-failure-strategy (:ask)
          (handler-bind ((gp-error #'plan-runner-condition-handler))
            (call-with-gp-restarts
             (lambda ()
               (if *gp-alternative-operator*
                   (values '((done 1)) :alternative)
                   (error 'action-failed :reason "transient")))
             :operator (failing-connect-op)))
          (is (eq recorded
                  (getf (find :ask-user (strategy-events-of)
                              :key (lambda (event) (getf event :kind)))
                        :choice))))))))

(test recovery-that-cannot-be-taken-is-a-gp-error
  ;; Each case is (RESTART-AND-ARGUMENTS ANSWER-TO-ASK-USER).
  (let ((op (failing-connect-op))
        (step '(:operator connect)))
    (dolist (case '(((:use-alternative) nil)
                    ((:use-alternative 42) nil)
                    ((:use-value 42) nil)
                    ((:ask-user) :use-alternative)
                    ((:ask-user) (:use-alternative . 42))
                    ((:ask-user) (:use-value . 42))
                    ((:ask-user) :bogus)
                    ((:ask-user) (:bogus . 1))
                    ((:ask-user) 42)))
      (destructuring-bind (restart answer) case
        (let* ((*ask-user-fn* (lambda (c names)
                                (declare (ignore c names))
                                answer))
               (failure
                 (handler-case
                     (handler-bind ((precondition-failure
                                     (lambda (c)
                                       (declare (ignore c))
                                       (apply #'invoke-restart restart))))
                       (call-with-gp-restarts
                        (lambda ()
                          (simulate-operator '((device d1)) op '((?d . d1))))
                        :operator op :bindings '((?d . d1)) :step step
                        :mode :simulate :facts-on-skip '((device d1))))
                   (action-failed (c) c)
                   (error () nil))))
          (is (typep failure 'action-failed) "~S answered ~S" restart answer)
          (when (typep failure 'action-failed)
            (is (eq op (gp-condition-operator failure)))
            (is (equal '((?d . d1)) (gp-condition-bindings failure)))
            (is (eq step (gp-condition-step failure)))
            (is (eq :simulate (gp-condition-mode failure)))))))))

(test use-value-takes-only-a-fact-list
  (let ((op (failing-connect-op))
        (facts '((device d1))))
    (flet ((supply (value)
             (handler-bind ((precondition-failure
                             (lambda (c)
                               (declare (ignore c))
                               (invoke-restart :use-value value))))
               (call-with-gp-restarts
                (lambda () (simulate-operator facts op *no-bindings*))
                :operator op :facts-on-skip facts))))
      (dolist (value (list 42 "facts" 'fact '(a . b) '(1 2) '((a 1) . b)))
        (signals action-failed (supply value)))
      (dolist (value '(nil ((a 1)) ((a 1) (b 2 3))))
        (multiple-value-bind (new result flag) (supply value)
          (is (equal value new))
          (is (eq :use-value flag))
          (is (eq :use-value (getf result :status)))
          (is (equal facts (getf result :before)))
          (is (equal value (getf result :after)))))
      ;; A fact list with its own step result.
      (let ((own (list :operator 'connect :status :forced)))
        (multiple-value-bind (new result flag)
            (supply (list '((a 1)) own))
          (is (equal '((a 1)) new))
          (is (eq own result))
          (is (eq :use-value flag)))))))

(test prompts-read-data-and-ask-again
  (flet ((typed (text function &rest arguments)
           (let ((*query-io* (make-two-way-stream
                              (make-string-input-stream text)
                              (make-broadcast-stream))))
             (apply function arguments))))
    (let ((failure (make-condition 'action-failed :reason "transient"))
          (names '(:retry :skip)))
      (is (eq :skip (typed ":skip" #'automa-gp::default-ask-user failure names)))
      (is (eq :skip (typed ":bogus 42 :skip"
                           #'automa-gp::default-ask-user failure names)))
      (is (equal '(:retry) (typed "(:retry)"
                                  #'automa-gp::default-ask-user failure names)))
      ;; What is typed is data: #. is not evaluated.
      (signals reader-error
        (typed "#.(+ 1 2) :skip" #'automa-gp::default-ask-user failure names))
      (signals reader-error
        (typed "#.(list 1)" #'automa-gp::read-form-prompt "USE-VALUE"))
      (is (equal '(((a 1)))
                 (typed "((a 1))" #'automa-gp::read-form-prompt "USE-VALUE"))))))

(test alternatives-are-tried-once-each-in-order
  (let* ((bad (failing-connect-op))
         (first-alternative (make-operator :name 'first-alternative))
         (second-alternative (make-operator :name 'second-alternative))
         (tried nil))
    (with-failure-strategy (:signal)
      (signals action-failed
        (handler-bind ((precondition-failure
                         (lambda (c)
                           (declare (ignore c))
                           (invoke-restart :use-alternative))))
          (call-with-gp-restarts
           (lambda ()
             (push (and *gp-alternative-operator*
                        (operator-name *gp-alternative-operator*))
                   tried)
             (error 'precondition-failure :operator bad))
           :operator bad
           :alternatives (list first-alternative second-alternative))))
      (is (equal '(nil first-alternative second-alternative) (reverse tried)))
      (is (equal '((first-alternative connect) (second-alternative connect))
                 (loop for event in (reverse (strategy-events-of))
                       collect (list (getf event :operator)
                                     (getf event :replaced))))))
    ;; The alternative is bound only while the step runs.
    (is (null *gp-alternative-operator*))))

(defun %fail-then-recover-interactively (restart-name typed alternatives)
  "Fail a CONNECT step and take RESTART-NAME the way the debugger does,
with TYPED as what is read from *QUERY-IO*. The step succeeds once an
alternative is bound. Returns the values of the step in a list."
  (let* ((bad (failing-connect-op))
         (facts '((device d1)))
         (*ask-user-fn* nil)
         (*query-io* (make-two-way-stream (make-string-input-stream typed)
                                          (make-broadcast-stream))))
    (multiple-value-list
     (handler-bind ((precondition-failure
                      (lambda (c)
                        (invoke-restart-interactively
                         (find-restart restart-name c)))))
       (call-with-gp-restarts
        (lambda ()
          (if *gp-alternative-operator*
              (values '((done 1)) :alternative)
              (simulate-operator facts bad '((?d . d1)))))
        :operator bad :alternatives alternatives :facts-on-skip facts)))))

(test restarts-can-be-taken-interactively
  ;; Each case is (RESTART TYPED EXPECTED-FACTS EXPECTED-FLAG).
  (dolist (case '((:use-value "((a 1))" ((a 1)) :use-value)
                  (:skip "" ((device d1)) :skip)
                  (:abort-execution "" ((device d1)) :abort)
                  ;; ASK-USER reads the choice, and for a bare :USE-VALUE
                  ;; the value after it.
                  (:ask-user ":skip" ((device d1)) :skip)
                  (:ask-user ":nonsense :abort-execution" ((device d1)) :abort)
                  (:ask-user ":use-value ((b 2))" ((b 2)) :use-value)
                  (:ask-user "(:use-value (c 3))" ((c 3)) :use-value)))
    (destructuring-bind (restart typed facts flag) case
      (let ((values (%fail-then-recover-interactively restart typed nil)))
        (is (equal facts (first values)) "~S typed ~S" restart typed)
        (is (eq flag (third values)) "~S typed ~S" restart typed))))
  ;; USE-ALTERNATIVE asks nothing: it takes the next alternative.
  (dolist (case '((:use-alternative "") (:ask-user ":use-alternative")))
    (destructuring-bind (restart typed) case
      (is (equal '(((done 1)) :alternative)
                 (%fail-then-recover-interactively
                  restart typed (list (force-connect-op))))))))

(test restart-reports-name-the-step
  (let ((reports nil))
    (handler-bind ((action-failed
                     (lambda (c)
                       (setf reports
                             (loop for name in '(:retry :skip :abort-execution
                                                 :use-value :use-alternative
                                                 :ask-user)
                                   collect (princ-to-string
                                            (find-restart name c))))
                       (invoke-restart :skip))))
      (call-with-gp-restarts
       (lambda () (error 'action-failed :reason "transient"))
       :operator (power-on-op)))
    (is (= 6 (length reports)))
    (is (every (lambda (report) (plusp (length report))) reports))
    (is (search "POWER-ON" (first reports)))
    (is (search "POWER-ON" (second reports)))))

(test step-result-records-the-step
  (let* ((before (list '(a 1)))
         (after (list '(a 1) '(b 2)))
         (result (make-step-result (power-on-op) *no-bindings* before after
                                   :status :ok :missing '((c 3))
                                   :external :none)))
    (is (eq 'power-on (getf result :operator)))
    (is (null (getf result :bindings)))
    (is (eq :ok (getf result :status)))
    (is (equal '((c 3)) (getf result :missing)))
    (is (eq :none (getf result :external)))
    (is (equal before (getf result :before)))
    (is (not (eq before (getf result :before))))
    (is (equal after (getf result :after)))
    (is (not (eq after (getf result :after)))))
  ;; Each case is (OPERATOR NAME-SHOWN).
  (dolist (case (list (list (power-on-op) "POWER-ON")
                      (list 'connect "CONNECT")
                      (list nil "?")
                      (list 42 "?")))
    (destructuring-bind (operator name) case
      (is (string= name (getf (make-step-result operator '((?d . d1)) nil nil)
                              :operator)))
      (is (equal '((?d . d1))
                 (getf (make-step-result operator '((?d . d1)) nil nil)
                       :bindings))))))

;;; --- Conditions ---

(test condition-readers-and-reports
  (let ((op (power-on-op))
        (b '((?d . d1))))
    ;; Each case is (CONDITION-TYPE OPERATOR-READER BINDINGS-READER).
    (dolist (case (list (list 'precondition-failure
                              #'precondition-failure-operator
                              #'precondition-failure-bindings)
                        (list 'confirmation-required
                              #'confirmation-required-operator
                              #'confirmation-required-bindings)
                        (list 'action-failed
                              #'gp-condition-operator
                              #'gp-condition-bindings)))
      (destructuring-bind (type operator-of bindings-of) case
        (let ((c (make-condition type :operator op :bindings b)))
          (is (typep c 'gp-error))
          (is (eq op (funcall operator-of c)))
          (is (equal b (funcall bindings-of c)))
          (is (search "POWER-ON" (princ-to-string c))))))
    (is (search "NO-SUCH" (princ-to-string
                           (make-condition 'unknown-operator :name 'no-such))))
    (is (search "transient"
                (princ-to-string
                 (make-condition 'action-failed :reason "transient"))))
    (is (search "(P 1)"
                (princ-to-string
                 (make-condition 'precondition-failure
                                 :operator op :missing '((p 1))))))
    (is (search "IRREVERSIBLE"
                (princ-to-string
                 (make-condition 'confirmation-required
                                 :operator op :reason :irreversible))))))

(test exported-condition-functions-are-documented
  (dolist (name '(make-strategy record-strategy-event strategy-events-of
                  maybe-invoke-strategy plan-runner-condition-handler
                  call-with-gp-restarts make-step-result with-failure-strategy
                  precondition-failure-operator precondition-failure-bindings
                  confirmation-required-operator confirmation-required-bindings))
    (is (eq :external
            (nth-value 1 (find-symbol (symbol-name name) :automa-gp))))
    (is (documentation name 'function)))
  (dolist (name '(*deliberative-strategy* *ask-user-fn*
                  *plan-runner-default-abort* *gp-alternative-operator*))
    (is (documentation name 'variable))))
