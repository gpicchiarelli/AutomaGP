;;;; core/conditions.lisp — Condition System & restarts (Phase 5)
;;;;
;;;; Idiomatic CL conditions/restarts for GP failures. Not a catch-all
;;;; exception layer: step runners establish restarts; strategies may invoke them.
;;;;
;;;; Restarts: RETRY, SKIP, ABORT-EXECUTION, USE-VALUE, ASK-USER, USE-ALTERNATIVE.

(in-package #:automa-gp)

;;; ---------------------------------------------------------------------------
;;; Condition hierarchy
;;; ---------------------------------------------------------------------------

(defun gp-operator-name (operator)
  "Name to show for OPERATOR: an operator object, an operator name, or NIL.
? when there is none to show."
  (cond
    ((null operator) '?)
    ((operator-p operator) (operator-name operator))
    ((symbolp operator) operator)
    (t '?)))

(define-condition gp-condition (condition)
  ((operator
    :initarg :operator :reader gp-condition-operator :initform nil)
   (bindings
    :initarg :bindings :reader gp-condition-bindings :initform nil)
   (step
    :initarg :step :reader gp-condition-step :initform nil)
   (mode
    :initarg :mode :reader gp-condition-mode :initform nil)
   (context
    :initarg :context :reader gp-condition-context :initform nil))
  (:documentation "Base condition for AUTOMA GP deliberative failures."))

(define-condition gp-error (gp-condition error)
  ()
  (:documentation "Serious GP failure with recovery restarts at step boundaries."))

(define-condition precondition-failure (gp-error)
  ((missing
    :initarg :missing :reader precondition-failure-missing :initform nil))
  (:report (lambda (c stream)
             (format stream "Preconditions not satisfied for ~A; missing ~S"
                     (gp-operator-name (gp-condition-operator c))
                     (precondition-failure-missing c))))
  (:documentation "An operator was applied while a precondition did not hold."))

(define-condition confirmation-required (gp-error)
  ((reason
    :initarg :reason :reader confirmation-required-reason :initform :unspecified))
  (:report (lambda (c stream)
             (format stream "Confirmation required to EXECUTE ~A (~A)"
                     (gp-operator-name (gp-condition-operator c))
                     (confirmation-required-reason c))))
  (:documentation "An irreversible or high-risk operator was not confirmed."))

(define-condition unknown-operator (gp-error)
  ((name :initarg :name :reader unknown-operator-name))
  (:report (lambda (c stream)
             (format stream "Unknown operator ~S" (unknown-operator-name c))))
  (:documentation "A plan step names an operator that cannot be found."))

(define-condition action-failed (gp-error)
  ((reason :initarg :reason :reader action-failed-reason :initform nil))
  (:report (lambda (c stream)
             (format stream "Action/operator failed~@[ (~A)~]~@[: ~A~]"
                     (gp-operator-name (gp-condition-operator c))
                     (action-failed-reason c))))
  (:documentation "A step failed for the REASON given, or a recovery could not
be taken."))

;;; Readers named after the condition, kept for callers written before the
;;; slots moved to GP-CONDITION.

(defun precondition-failure-operator (c)
  "Operator of the PRECONDITION-FAILURE C. Same as GP-CONDITION-OPERATOR."
  (gp-condition-operator c))

(defun precondition-failure-bindings (c)
  "Bindings of the PRECONDITION-FAILURE C. Same as GP-CONDITION-BINDINGS."
  (gp-condition-bindings c))

(defun confirmation-required-operator (c)
  "Operator of the CONFIRMATION-REQUIRED C. Same as GP-CONDITION-OPERATOR."
  (gp-condition-operator c))

(defun confirmation-required-bindings (c)
  "Bindings of the CONFIRMATION-REQUIRED C. Same as GP-CONDITION-BINDINGS."
  (gp-condition-bindings c))

;;; ---------------------------------------------------------------------------
;;; Step result helper (shared by executor)
;;; ---------------------------------------------------------------------------

(defun make-step-result (operator bindings before after &key status missing
                                                         external)
  "The record of one step (plist): the name of OPERATOR, BINDINGS, STATUS,
MISSING preconditions, the EXTERNAL action, and copies of the fact lists
BEFORE and AFTER the step."
  (list :operator (gp-operator-name operator)
        :bindings (if (eq bindings *no-bindings*) nil bindings)
        :status status
        :missing missing
        :external external
        :before (copy-list before)
        :after (copy-list after)))

;;; ---------------------------------------------------------------------------
;;; Deliberative strategy (can change after failures)
;;; ---------------------------------------------------------------------------

(defclass deliberative-strategy ()
  ((policy
    :initarg :policy
    :accessor strategy-policy
    :initform :signal
    :documentation "One of :SIGNAL :SKIP :RETRY :ABORT :ASK.")
   (retry-limit
    :initarg :retry-limit
    :accessor strategy-retry-limit
    :initform 3
    :documentation "How many times a :RETRY policy retries one step.")
   (retry-count
    :initform 0
    :accessor strategy-retry-count
    :documentation "Retries recorded on this strategy, over all its steps.")
   (events
    :initform nil
    :accessor strategy-events
    :documentation "Newest-first log of failure/recovery events, over every
run this strategy guided. STRATEGY-EVENTS-OF gives those of one run.")
   (skipped
    :initform nil
    :accessor strategy-skipped
    :documentation "Names of the operators whose steps were skipped, newest
first."))
  (:documentation "Mutable deliberative failure policy for a session/plan run."))

(defun make-strategy (&key (policy :signal) (retry-limit 3))
  "A DELIBERATIVE-STRATEGY with POLICY and RETRY-LIMIT.
POLICY says what the plan runners do when a step fails: :SKIP the step,
:RETRY it up to RETRY-LIMIT times, :ABORT the plan, :ASK through
*ASK-USER-FN*, or :SIGNAL, which leaves the condition to the caller's
handlers. Any other POLICY is a TYPE-ERROR."
  (check-type policy (member :signal :skip :retry :abort :ask))
  (check-type retry-limit (integer 0))
  (make-instance 'deliberative-strategy
                 :policy policy
                 :retry-limit retry-limit))

(defvar *deliberative-strategy* nil
  "When non-NIL, a DELIBERATIVE-STRATEGY guiding automatic restart choice.")

(defvar *ask-user-fn* nil
  "Function of (CONDITION RESTART-NAMES) that chooses a recovery.
It returns one of RESTART-NAMES, or a cons (NAME . ARGUMENT) to pass the
fact list of :USE-VALUE or the operator of :USE-ALTERNATIVE. NIL means
DEFAULT-ASK-USER, which reads the answer from *QUERY-IO*.")

(defvar *plan-runner-default-abort* t
  "When true, plan runners abort via ABORT-EXECUTION if a GP-ERROR is not
handled by *DELIBERATIVE-STRATEGY*. A strategy whose policy is :SIGNAL
turns this off: the condition reaches the caller's handlers.")

(defvar *gp-alternative-operator* nil
  "Bound by USE-ALTERNATIVE while retrying a step.")

(defvar *running-step* nil
  "Inside CALL-WITH-GP-RESTARTS, a plist (:OPERATOR name :MODE mode
:RETRIES count) for the step it is running; NIL elsewhere.
MAYBE-INVOKE-STRATEGY reads it, so a retry limit counts the retries of one
step and not those of the whole session.")

(defun record-strategy-event (kind &rest plist)
  "Push a failure/recovery event onto the current strategy (if any).
The event is (:KIND KIND :TIME universal-time :TRACE-ID id . PLIST), where
the id is that of the deliberative trace open at the time, or NIL. A :SKIP
also adds its :OPERATOR to STRATEGY-SKIPPED and a :RETRY counts in
STRATEGY-RETRY-COUNT. Returns KIND."
  (let ((strategy *deliberative-strategy*))
    (when strategy
      (push (list* :kind kind
                   :time (get-universal-time)
                   :trace-id (and (deliberative-trace-p *current-trace*)
                                  (trace-id *current-trace*))
                   plist)
            (strategy-events strategy))
      (case kind
        (:skip (push (getf plist :operator) (strategy-skipped strategy)))
        (:retry (incf (strategy-retry-count strategy))))))
  kind)

(defun strategy-events-of (&optional (strategy *deliberative-strategy*))
  "Events recorded on STRATEGY, newest first, as a fresh list.
While a deliberative trace is open, as it is during a plan run, only the
events recorded under that trace: a strategy outlives the runs it guides,
and a run reports its own events. With no trace open, every event.
NIL when STRATEGY is NIL."
  (when strategy
    (if (deliberative-trace-p *current-trace*)
        (remove (trace-id *current-trace*) (strategy-events strategy)
                :key (lambda (event) (getf event :trace-id))
                :test-not #'eq)
        (copy-list (strategy-events strategy)))))

(defmacro with-failure-strategy ((policy &key (retry-limit 3)) &body body)
  "Bind *DELIBERATIVE-STRATEGY* for BODY."
  `(let ((*deliberative-strategy*
          (make-strategy :policy ,policy :retry-limit ,retry-limit)))
     ,@body))

(defun %invoke-if-active (name condition &rest arguments)
  "Invoke the restart NAME that applies to CONDITION, when there is one."
  (let ((restart (find-restart name condition)))
    (when restart
      (apply #'invoke-restart restart arguments))))

(defun maybe-invoke-strategy (condition)
  "HANDLER-BIND helper: invoke a restart according to *DELIBERATIVE-STRATEGY*.
Returns, declining CONDITION, when there is no strategy, when its policy is
:SIGNAL, when the restart it names is not active, and when a :RETRY policy
has already retried the running step RETRY-LIMIT times. That last case
records a :RETRY-EXHAUSTED event."
  (let ((strategy *deliberative-strategy*))
    (when strategy
      (case (strategy-policy strategy)
        (:skip (%invoke-if-active :skip condition))
        (:abort (%invoke-if-active :abort-execution condition))
        (:ask (%invoke-if-active :ask-user condition condition))
        (:retry
         (let ((step *running-step*)
               (limit (strategy-retry-limit strategy)))
           (cond
             ((null step) nil)
             ((< (getf step :retries) limit)
              (%invoke-if-active :retry condition))
             (t
              (record-strategy-event :retry-exhausted
                                     :operator (getf step :operator)
                                     :mode (getf step :mode)
                                     :limit limit)
              nil))))
        (otherwise nil)))))

(defun plan-runner-condition-handler (condition)
  "Handler the plan runners bind for GP-ERROR.
First the strategy chooses (MAYBE-INVOKE-STRATEGY). When it declines, a
:SIGNAL strategy leaves CONDITION to outer handlers and the debugger, with
every restart still active. Otherwise, while *PLAN-RUNNER-DEFAULT-ABORT* is
true, the step is given up through ABORT-EXECUTION."
  (maybe-invoke-strategy condition)
  (unless (and *deliberative-strategy*
               (eq :signal (strategy-policy *deliberative-strategy*)))
    (when *plan-runner-default-abort*
      (%invoke-if-active :abort-execution condition))))

;;; ---------------------------------------------------------------------------
;;; Interactive helpers
;;; ---------------------------------------------------------------------------

(defun %read-answer (control &rest arguments)
  "Print the prompt CONTROL and ARGUMENTS make on *QUERY-IO*, then read one
form from it. The form is data: *READ-EVAL* is off, so #. is a READER-ERROR."
  (format *query-io* "~&~?" control arguments)
  (finish-output *query-io*)
  (let ((*read-eval* nil))
    (read *query-io*)))

(defun default-ask-user (condition restart-names)
  "Ask on *QUERY-IO* which recovery to take for CONDITION.
Asks again until the answer is one of RESTART-NAMES, or a cons whose CAR
is. Override via *ASK-USER-FN*."
  (loop
    (let ((answer (%read-answer "GP failure: ~A~%Choose restart ~S: "
                                condition restart-names)))
      (when (member (if (consp answer) (car answer) answer) restart-names)
        (return answer))
      (format *query-io* "~&~S is not one of ~S.~%" answer restart-names))))

(defun ask-user-pick (condition restart-names)
  "What *ASK-USER-FN*, or DEFAULT-ASK-USER without one, answers for
CONDITION: one of RESTART-NAMES or a cons (NAME . ARGUMENT)."
  (funcall (or *ask-user-fn* #'default-ask-user) condition restart-names))

(defun read-form-prompt (prompt)
  "Print PROMPT on *QUERY-IO* and read one form, as data. Returns a list of
that form: the argument list of a restart."
  (list (%read-answer "~A: " prompt)))

;;; ---------------------------------------------------------------------------
;;; Restart establishment
;;; ---------------------------------------------------------------------------

(defun %proper-list-p (object)
  "True when OBJECT is a list that ends in NIL."
  (and (listp object)
       (handler-case (list-length object)
         (type-error () nil))
       t))

(defun %fact-list-p (object)
  "True when OBJECT is a proper list whose every element is a cons."
  (and (%proper-list-p object)
       (every #'consp object)))

(defun %supplied-outcome (value)
  "Read the VALUE handed to USE-VALUE.
Returns (VALUES FACTS STEP-RESULT VALID-P). VALUE is a fact list, and then
STEP-RESULT is NIL; or it is a list of a fact list and a step result, which
is a list with a :STATUS in it."
  (cond
    ((and (%proper-list-p value)
          (= 2 (length value))
          (%fact-list-p (first value))
          (%proper-list-p (second value))
          (member :status (second value) :test #'eq))
     (values (first value) (second value) t))
    ((%fact-list-p value)
     (values value nil t))
    (t
     (values nil nil nil))))

(defun call-with-gp-restarts (thunk &key operator bindings alternatives
                                      mode context step facts-on-skip)
  "Call THUNK, which runs one step, with the GP recovery restarts around it.

THUNK returns its values, usually NEW-FACTS and a step result, or signals a
GP-ERROR. Without a recovery those values are returned. A handler recovers
by invoking one of these restarts:

  :RETRY                         call THUNK again.
  :SKIP                          give the step up and go on. Returns
                                 FACTS-ON-SKIP, a :SKIPPED step result, :SKIP.
  :ABORT-EXECUTION               give the plan up. Returns FACTS-ON-SKIP, an
                                 :ABORTED step result, :ABORT.
  :USE-VALUE value               take VALUE as the outcome. VALUE is a fact
                                 list, or a list of a fact list and a step
                                 result. Returns the facts, a step result,
                                 :USE-VALUE.
  :USE-ALTERNATIVE [operator]    call THUNK again with
                                 *GP-ALTERNATIVE-OPERATOR* bound to OPERATOR,
                                 or to the next of ALTERNATIVES.
  :ASK-USER [condition]          let *ASK-USER-FN* choose one of the five
                                 above for CONDITION, the failure. It answers
                                 a name or a cons (NAME . ARGUMENT).

A recovery that cannot be taken signals ACTION-FAILED from this call, with
the restarts no longer active: no alternative left, a value that is not a
fact list, an answer that names no recovery.

Every recovery taken is recorded on *DELIBERATIVE-STRATEGY*. OPERATOR,
BINDINGS, MODE, CONTEXT and STEP describe the step in those records, in the
step results and in the ACTION-FAILED."
  (let* ((alt-queue (copy-list alternatives))
         (name (and operator (gp-operator-name operator)))
         (*running-step* (list :operator name :mode mode :retries 0)))
    (labels
        ((note (kind)
           (record-strategy-event kind :operator name :mode mode))
         (cannot (control &rest arguments)
           (error 'action-failed
                  :operator operator
                  :bindings bindings
                  :mode mode
                  :context context
                  :step step
                  :reason (apply #'format nil control arguments)))
         (outcome (status flag &optional (after facts-on-skip))
           (values after
                   (make-step-result operator bindings facts-on-skip after
                                     :status status)
                   flag))
         (retry ()
           (incf (getf *running-step* :retries))
           (note :retry)
           (run))
         (skip ()
           (note :skip)
           (outcome :skipped :skip))
         (abort-plan ()
           (note :abort)
           (outcome :aborted :abort))
         (take-value (value)
           (multiple-value-bind (facts result valid) (%supplied-outcome value)
             (unless valid
               (cannot "USE-VALUE takes a fact list, not ~S" value))
             (note :use-value)
             (if result
                 (values facts result :use-value)
                 (outcome :use-value :use-value facts))))
         (use-alternative (alternative)
           (let ((chosen (or alternative (first alt-queue))))
             (unless (operator-p chosen)
               (if alternative
                   (cannot "~S is not an operator" alternative)
                   (cannot "no alternative operator is left")))
             ;; An alternative that has been tried is not offered again.
             (setf alt-queue (remove chosen alt-queue))
             (record-strategy-event :use-alternative
                                    :operator (operator-name chosen)
                                    :replaced name
                                    :mode mode)
             (let ((*gp-alternative-operator* chosen))
               (run))))
         (ask (condition)
           ;; RESTART-CASE has unwound by now, so the sibling restarts are
           ;; no longer active: the answer selects the same local function
           ;; each of them calls.
           (let* ((choice (ask-user-pick
                           (or condition
                               (make-condition 'action-failed
                                               :operator operator
                                               :bindings bindings
                                               :mode mode
                                               :context context
                                               :step step
                                               :reason "ask-user"))
                           '(:retry :skip :abort-execution :use-value
                             :use-alternative)))
                  (argument (and (consp choice) (cdr choice))))
             (record-strategy-event :ask-user :choice choice)
             (case (if (consp choice) (car choice) choice)
               (:retry (retry))
               (:skip (skip))
               (:abort-execution (abort-plan))
               (:use-value
                (take-value (if (consp choice)
                                argument
                                (first (read-form-prompt "USE-VALUE")))))
               (:use-alternative (use-alternative argument))
               (t (cannot "ASK-USER answered ~S, which names no recovery"
                          choice)))))
         (run ()
           (restart-case (funcall thunk)
             (:retry ()
               :report (lambda (s) (format s "Retry step~@[ ~A~]" name))
               (retry))
             (:skip ()
               :report (lambda (s)
                         (format s "Skip step~@[ ~A~] and continue the plan"
                                 name))
               (skip))
             (:abort-execution ()
               :report "Abort the plan / execution"
               (abort-plan))
             (:use-value (value)
               :report "Use a supplied value as the step outcome (fact list)"
               :interactive (lambda () (read-form-prompt "USE-VALUE form"))
               (take-value value))
             (:use-alternative (&optional alternative)
               :report "Retry using an alternative operator"
               (use-alternative alternative))
             (:ask-user (&optional condition)
               :report "Ask which recovery action to take"
               (ask condition)))))
      (run))))
