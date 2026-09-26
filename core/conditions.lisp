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
                     (precondition-failure-missing c)))))

(define-condition confirmation-required (gp-error)
  ((reason
    :initarg :reason :reader confirmation-required-reason :initform :unspecified))
  (:report (lambda (c stream)
             (format stream "Confirmation required to EXECUTE ~A (~A)"
                     (gp-operator-name (gp-condition-operator c))
                     (confirmation-required-reason c)))))

(define-condition unknown-operator (gp-error)
  ((name :initarg :name :reader unknown-operator-name))
  (:report (lambda (c stream)
             (format stream "Unknown operator ~S" (unknown-operator-name c)))))

(define-condition action-failed (gp-error)
  ((reason :initarg :reason :reader action-failed-reason :initform nil))
  (:report (lambda (c stream)
             (format stream "Action/operator failed~@[ (~A)~]~@[: ~A~]"
                     (gp-operator-name (gp-condition-operator c))
                     (action-failed-reason c)))))

(defun gp-operator-name (operator)
  (cond
    ((null operator) '?)
    ((operator-p operator) (operator-name operator))
    ((symbolp operator) operator)
    (t '?)))

;;; Compatibility readers used by Phase-4 code/tests
(defun precondition-failure-operator (c) (gp-condition-operator c))
(defun precondition-failure-bindings (c) (gp-condition-bindings c))
(defun confirmation-required-operator (c) (gp-condition-operator c))
(defun confirmation-required-bindings (c) (gp-condition-bindings c))

;;; ---------------------------------------------------------------------------
;;; Step result helper (shared by executor)
;;; ---------------------------------------------------------------------------

(defun make-step-result (operator bindings before after &key status missing)
  (list :operator (gp-operator-name operator)
        :bindings (if (eq bindings *no-bindings*) nil bindings)
        :status status
        :missing missing
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
    :initform 3)
   (retry-count
    :initform 0
    :accessor strategy-retry-count)
   (events
    :initform nil
    :accessor strategy-events
    :documentation "Newest-first log of failure/recovery events.")
   (skipped
    :initform nil
    :accessor strategy-skipped))
  (:documentation "Mutable deliberative failure policy for a session/plan run."))

(defun make-strategy (&key (policy :signal) (retry-limit 3))
  (make-instance 'deliberative-strategy
                 :policy policy
                 :retry-limit retry-limit))

(defvar *deliberative-strategy* nil
  "When non-NIL, a DELIBERATIVE-STRATEGY guiding automatic restart choice.")

(defvar *ask-user-fn* nil
  "Optional (CONDITION RESTART-NAMES) → restart name or (name . args).")

(defvar *plan-runner-default-abort* t
  "When true, plan runners abort via ABORT-EXECUTION if a GP-ERROR is not
handled by *DELIBERATIVE-STRATEGY*.")

(defvar *gp-alternative-operator* nil
  "Bound by USE-ALTERNATIVE while retrying a step.")

(defun record-strategy-event (kind &rest plist)
  "Push a failure/recovery event onto the current strategy (if any)."
  (when *deliberative-strategy*
    (push (list* :kind kind :time (get-universal-time) plist)
          (strategy-events *deliberative-strategy*))
    (when (eq kind :skip)
      (push (getf plist :operator) (strategy-skipped *deliberative-strategy*)))
    (when (eq kind :retry)
      (incf (strategy-retry-count *deliberative-strategy*))))
  kind)

(defun strategy-events-of (&optional (strategy *deliberative-strategy*))
  (when strategy (copy-list (strategy-events strategy))))

(defmacro with-failure-strategy ((policy &key (retry-limit 3)) &body body)
  "Bind *DELIBERATIVE-STRATEGY* for BODY."
  `(let ((*deliberative-strategy*
          (make-strategy :policy ,policy :retry-limit ,retry-limit)))
     ,@body))

(defun maybe-invoke-strategy (condition)
  "HANDLER-BIND helper: invoke a restart according to *DELIBERATIVE-STRATEGY*."
  (declare (ignore condition))
  (let ((s *deliberative-strategy*))
    (when s
      (case (strategy-policy s)
        (:skip
         (when (find-restart :skip)
           (invoke-restart :skip)))
        (:abort
         (when (find-restart :abort-execution)
           (invoke-restart :abort-execution)))
        (:retry
         (when (and (find-restart :retry)
                    (< (strategy-retry-count s) (strategy-retry-limit s)))
           (invoke-restart :retry)))
        (:ask
         (when (find-restart :ask-user)
           (invoke-restart :ask-user)))
        (otherwise nil)))))

(defun plan-runner-condition-handler (condition)
  "Default handler for plan runners: try strategy, else abort-execution."
  (maybe-invoke-strategy condition)
  (when (and *plan-runner-default-abort*
             (find-restart :abort-execution))
    (invoke-restart :abort-execution)))

;;; ---------------------------------------------------------------------------
;;; Interactive helpers
;;; ---------------------------------------------------------------------------

(defun default-ask-user (condition restart-names)
  "Minimal REPL prompt; override via *ASK-USER-FN*."
  (format *query-io* "~&GP failure: ~A~%Choose restart ~S: " condition restart-names)
  (finish-output *query-io*)
  (read *query-io*))

(defun ask-user-pick (condition restart-names)
  (funcall (or *ask-user-fn* #'default-ask-user) condition restart-names))

(defun read-form-prompt (prompt)
  (format *query-io* "~&~A: " prompt)
  (finish-output *query-io*)
  (list (read *query-io*)))

;;; ---------------------------------------------------------------------------
;;; Restart establishment
;;; ---------------------------------------------------------------------------

(defun call-with-gp-restarts (thunk &key operator bindings alternatives
                                      mode context step
                                      (facts-on-skip nil facts-on-skip-p))
  "Invoke THUNK with GP recovery restarts established.

THUNK returns values on success (typically NEW-FACTS STEP-RESULT) or signals
a GP-ERROR. Returns those values, optionally with a third value
:SKIP / :ABORT / :USE-VALUE describing recovery.

Restarts: RETRY, SKIP, ABORT-EXECUTION, USE-VALUE, USE-ALTERNATIVE, ASK-USER."
  (let ((alt-queue (copy-list alternatives)))
    (labels
        ((op-name ()
           (and operator (gp-operator-name operator)))
         (skip-result (status)
           (make-step-result operator
                             (or bindings *no-bindings*)
                             (if facts-on-skip-p facts-on-skip nil)
                             (if facts-on-skip-p facts-on-skip nil)
                             :status status))
         (run ()
           (restart-case
               (funcall thunk)
             (:retry ()
               :report (lambda (s)
                         (format s "Retry step~@[ ~A~]" (op-name)))
               (record-strategy-event :retry :operator (op-name) :mode mode)
               (run))
             (:skip ()
               :report (lambda (s)
                         (format s "Skip step~@[ ~A~] and continue the plan"
                                 (op-name)))
               (record-strategy-event :skip :operator (op-name) :mode mode)
               (values (if facts-on-skip-p facts-on-skip nil)
                       (skip-result :skipped)
                       :skip))
             (:abort-execution ()
               :report "Abort the plan / execution"
               (record-strategy-event :abort :operator (op-name) :mode mode)
               (values (if facts-on-skip-p facts-on-skip nil)
                       (skip-result :aborted)
                       :abort))
             (:use-value (value)
               :report "Use a supplied value as the step outcome (fact list)"
               :interactive (lambda () (read-form-prompt "USE-VALUE form"))
               (record-strategy-event :use-value :operator (op-name))
               ;; VALUE is a replacement fact list, or (facts step-result) when
               ;; the second element is a step-result plist containing :STATUS.
               (if (and (consp value)
                        (= (length value) 2)
                        (listp (first value))
                        (consp (second value))
                        (member :status (second value) :test #'eq))
                   (values (first value) (second value) :use-value)
                   (values value
                           (make-step-result operator
                                             (or bindings *no-bindings*)
                                             (if facts-on-skip-p facts-on-skip nil)
                                             (if (listp value) value nil)
                                             :status :use-value)
                           :use-value)))
             (:use-alternative (&optional alt-operator)
               :report "Retry using an alternative operator"
               :interactive (lambda ()
                              (list (or (first alt-queue)
                                        (error "No alternative operators available"))))
               (let ((alt (or alt-operator (pop alt-queue))))
                 (unless (operator-p alt)
                   (error 'action-failed
                          :operator operator
                          :bindings bindings
                          :mode mode
                          :context context
                          :step step
                          :reason "no alternative operator available"))
                 (record-strategy-event :use-alternative
                                        :operator (operator-name alt)
                                        :replaced (op-name))
                 (let ((*gp-alternative-operator* alt))
                   (run))))
             (:ask-user ()
               :report "Ask which recovery action to take"
               ;; Implement choices directly (sibling restarts are not reliably
               ;; invokable from inside another restart's body on all CLs).
               (let* ((names '(:retry :skip :abort-execution :use-value :use-alternative))
                      (c (make-condition 'action-failed
                                         :operator operator
                                         :bindings bindings
                                         :mode mode
                                         :context context
                                         :step step
                                         :reason "ask-user"))
                      (pick (ask-user-pick c names)))
                 (record-strategy-event :ask-user :choice pick)
                 (cond
                   ((eq pick :retry)
                    (record-strategy-event :retry :operator (op-name) :mode mode)
                    (run))
                   ((eq pick :skip)
                    (record-strategy-event :skip :operator (op-name) :mode mode)
                    (values (if facts-on-skip-p facts-on-skip nil)
                            (skip-result :skipped)
                            :skip))
                   ((eq pick :abort-execution)
                    (record-strategy-event :abort :operator (op-name) :mode mode)
                    (values (if facts-on-skip-p facts-on-skip nil)
                            (skip-result :aborted)
                            :abort))
                   ((or (eq pick :use-value)
                        (and (consp pick) (eq (car pick) :use-value)))
                    (let ((val (if (consp pick)
                                   (cdr pick)
                                   (first (read-form-prompt "USE-VALUE")))))
                      (record-strategy-event :use-value :operator (op-name))
                      (values val
                              (make-step-result operator
                                                (or bindings *no-bindings*)
                                                (if facts-on-skip-p facts-on-skip nil)
                                                (if (listp val) val nil)
                                                :status :use-value)
                              :use-value)))
                   ((or (eq pick :use-alternative)
                        (and (consp pick) (eq (car pick) :use-alternative)))
                    (let ((alt (if (and (consp pick) (cdr pick))
                                   (cdr pick)
                                   (pop alt-queue))))
                      (unless (operator-p alt)
                        (error 'action-failed
                               :operator operator
                               :reason "no alternative operator available"))
                      (record-strategy-event :use-alternative
                                             :operator (operator-name alt))
                      (let ((*gp-alternative-operator* alt))
                        (run))))
                   (t (error "ASK-USER: unknown choice ~S" pick))))))))
      (run))))
