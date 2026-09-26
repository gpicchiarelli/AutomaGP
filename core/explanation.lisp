;;;; core/explanation.lisp — deliberative trace & explanation (Phase 6)
;;;;
;;;; Records significant decisions as they happen in MEA / planning /
;;;; simulation / execution. gp-explain formats that record — it does not
;;;; invent a narrative after the fact.

(in-package #:automa-gp)

(defparameter *trace-enabled* t
  "When true, TRACE-RECORD appends to *CURRENT-TRACE*.")

(defvar *current-trace* nil
  "Active DELIBERATIVE-TRACE being recorded, or NIL.")

(defvar *last-trace* nil
  "Most recently finished deliberative trace.")

(defvar *trace-history* nil
  "Newest-first list of finished traces (session buffer, not persistence).")

(defparameter *trace-history-limit* 32
  "Max finished traces retained in *TRACE-HISTORY*.")

(defclass deliberative-trace ()
  ((id
    :initarg :id
    :accessor trace-id
    :initform (gentemp "TRACE-"))
   (phase
    :initarg :phase
    :accessor trace-phase
    :initform nil
    :documentation ":PLAN :SIMULATE :EXECUTE or similar.")
   (context-name
    :initarg :context-name
    :accessor trace-context-name
    :initform nil)
   (entries
    :initarg :entries
    :accessor trace-entries
    :initform nil
    :documentation "Chronological list of event plists (oldest first when finalized).")
   (open-p
    :initarg :open-p
    :accessor trace-open-p
    :initform t)
   (started-at
    :initarg :started-at
    :accessor trace-started-at
    :initform (get-universal-time))
   (finished-at
    :initarg :finished-at
    :accessor trace-finished-at
    :initform nil))
  (:documentation "Record of deliberative steps actually performed."))

(defun deliberative-trace-p (object)
  (typep object 'deliberative-trace))

(defun make-trace (&key phase context-name)
  (make-instance 'deliberative-trace
                 :phase phase
                 :context-name context-name
                 :entries nil
                 :open-p t))

(defun trace-record (kind &rest plist)
  "Append a deliberative event to *CURRENT-TRACE*.
KIND is a keyword such as :GOAL :DIFFERENCE :SELECTED-OPERATOR :PRECONDITION
:ACTION :RESULT :SUBGOAL :CONTEXT :STATE :EXECUTION-STEP.
Returns the entry plist, or NIL if tracing is off / no current trace."
  (when (and *trace-enabled* (deliberative-trace-p *current-trace*)
             (trace-open-p *current-trace*))
    (let ((entry (list* :kind kind
                        :time (get-universal-time)
                        plist)))
      (push entry (trace-entries *current-trace*))
      entry)))

(defun finalize-trace (&optional (trace *current-trace*))
  "Close TRACE, reverse entries to chronological order, publish as last/history."
  (when (deliberative-trace-p trace)
    (when (trace-open-p trace)
      (setf (trace-entries trace) (nreverse (trace-entries trace)))
      (setf (trace-open-p trace) nil)
      (setf (trace-finished-at trace) (get-universal-time)))
    (setf *last-trace* trace)
    (push trace *trace-history*)
    (when (> (length *trace-history*) *trace-history-limit*)
      (setf *trace-history* (subseq *trace-history* 0 *trace-history-limit*)))
    (when (eq trace *current-trace*)
      (setf *current-trace* nil))
    trace))

(defmacro with-trace ((phase &key context-name) &body body)
  "Bind a fresh *CURRENT-TRACE* for BODY and finalize it afterward."
  (let ((trace-var (gensym "TRACE")))
    `(let* ((,trace-var (make-trace :phase ,phase
                                    :context-name ,context-name))
            (*current-trace* ,trace-var))
       (trace-record :begin :phase ,phase :context ,context-name)
       (unwind-protect
            (progn ,@body)
         (finalize-trace ,trace-var)))))

;;; ---------------------------------------------------------------------------
;;; Introspection
;;; ---------------------------------------------------------------------------

(defun last-trace ()
  *last-trace*)

(defun trace-of (object)
  "Extract a deliberative trace from a PLAN, EXECUTION-RESULT, or TRACE."
  (cond
    ((deliberative-trace-p object) object)
    ((and (fboundp 'plan-p) (plan-p object))
     (getf (plan-meta object) :trace))
    ((and (fboundp 'execution-result-p)
          (execution-result-p object))
     (getf (execution-meta object) :trace))
    (t nil)))

(defun find-trace-entries (kind &optional (trace *last-trace*))
  "Entries in TRACE whose :KIND is KIND."
  (when (deliberative-trace-p trace)
    (remove kind (trace-entries trace)
            :key (lambda (e) (getf e :kind))
            :test-not #'eq)))

(defun clear-trace-session ()
  "Clear the in-session trace buffer (not durable persistence)."
  (setf *current-trace* nil
        *last-trace* nil
        *trace-history* nil)
  t)

(defun resolve-explain-topic (topic)
  "Map TOPIC to a deliberative-trace or NIL."
  (cond
    ((deliberative-trace-p topic) topic)
    ((or (null topic) (eq topic :last)) *last-trace*)
    ((eq topic :plan)
     (or (and (boundp '*current-plan*)
              *current-plan*
              (trace-of *current-plan*))
         *last-trace*))
    ((eq topic :execution)
     (or (and (boundp '*last-execution*)
              *last-execution*
              (trace-of *last-execution*))
         *last-trace*))
    ((or (and (fboundp 'plan-p) (plan-p topic))
         (and (fboundp 'execution-result-p) (execution-result-p topic)))
     (trace-of topic))
    ((eq topic :history) (first *trace-history*))
    (t nil)))

;;; ---------------------------------------------------------------------------
;;; Formatting (derived only from recorded entries)
;;; ---------------------------------------------------------------------------

(defun %fmt-bindings (bindings)
  (cond
    ((or (null bindings) (eq bindings *no-bindings*)) "")
    (t (format nil " ~{~A~^ ~}"
               (mapcar (lambda (p) (format nil "~A=~A" (car p) (cdr p)))
                       bindings)))))

(defun format-explanation (trace &optional (stream nil))
  "Render TRACE as text following the PROMPT §17 shape.
Only uses recorded entries — never invents decisions."
  (unless (deliberative-trace-p trace)
    (return-from format-explanation
      (format stream "No deliberative trace available.~%")))
  (let ((out (or stream (make-string-output-stream))))
    (format out "Deliberative trace ~A (phase ~A)~%"
            (trace-id trace) (or (trace-phase trace) '?))
    (when (trace-context-name trace)
      (format out "Context:~%    ~A~%~%" (trace-context-name trace)))
    (dolist (e (trace-entries trace))
      (case (getf e :kind)
        (:begin
         (format out "Begin (~A)~%~%" (getf e :phase)))
        (:context
         (format out "Context:~%    ~A~%~%" (getf e :name)))
        (:goal
         (format out "Goal:~%    ~S~%~%" (getf e :goal)))
        (:goals
         (format out "Goals:~%")
         (dolist (g (getf e :goals))
           (format out "    ~S~%" g))
         (format out "~%"))
        (:state
         (format out "Current state:~%")
         (dolist (f (getf e :facts))
           (format out "    ~S~%" f))
         (format out "~%"))
        (:difference
         (format out "Difference:~%    ~S~%~%" (getf e :goal)))
        (:differences
         (format out "Differences:~%")
         (dolist (d (getf e :goals))
           (format out "    ~S~%" d))
         (format out "~%"))
        (:goal-already-satisfied
         (format out "Goal already satisfied:~%    ~S~%~%" (getf e :goal)))
        (:selected-operator
         (format out "Selected operator:~%    ~A~A~%~%"
                 (getf e :operator)
                 (%fmt-bindings (getf e :bindings))))
        (:subgoal
         (format out "Required precondition (subgoal):~%    ~S~%~%"
                 (getf e :goal)))
        (:precondition
         (format out "Precondition:~%    ~A — ~S~%~%"
                 (getf e :status) (getf e :goal)))
        (:action
         (format out "Action:~%    ~A~A~%~%"
                 (getf e :operator)
                 (%fmt-bindings (getf e :bindings))))
        (:result
         (format out "Result:~%    ~A~%~%" (getf e :status)))
        (:operator-failed
         (format out "Operator failed:~%    ~A~%~%" (getf e :operator)))
        (:execution-step
         (format out "Execution step (~A):~%    ~A → ~A~%~%"
                 (getf e :mode)
                 (getf e :operator)
                 (getf e :status)))
        (:plan-complete
         (format out "Plan complete:~%    success=~A steps=~A~%~%"
                 (getf e :success) (getf e :steps)))
        (:execution-complete
         (format out "Execution complete:~%    mode=~A success=~A~%~%"
                 (getf e :mode) (getf e :success)))
        (otherwise
         (format out "~A: ~S~%~%" (getf e :kind) e))))
    (if stream
        nil
        (get-output-stream-string out))))

(defun explain-trace (topic &key (stream nil))
  "Return (VALUES TEXT TRACE) for TOPIC (:LAST :PLAN :EXECUTION or object).
Named EXPLAIN-TRACE (not EXPLAIN) to avoid clashing with FiveAM:EXPLAIN."
  (let ((tr (resolve-explain-topic topic)))
    (if tr
        (values (format-explanation tr stream) tr)
        (values (format stream "No deliberative trace for ~S.~%" topic)
                nil))))
