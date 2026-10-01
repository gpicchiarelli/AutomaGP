;;;; core/explanation.lisp — deliberative trace & explanation (Phase 6)
;;;;
;;;; Records significant decisions as they happen in MEA / planning /
;;;; simulation / execution. gp-explain formats that record — it does not
;;;; invent a narrative after the fact.
;;;;
;;;; Threads: WITH-TRACE binds *CURRENT-TRACE*, so each thread records into
;;;; its own trace. *LAST-TRACE*, *TRACE-HISTORY* and the id counter are
;;;; session state shared by every thread and are not locked: the core has
;;;; no threading dependency. A front end that deliberates on several
;;;; threads must serialise those calls itself.

(in-package #:automa-gp)

(defparameter *trace-enabled* t
  "When false, WITH-TRACE opens no trace and TRACE-RECORD records nothing,
so nothing reaches *LAST-TRACE* or *TRACE-HISTORY*.")

(defvar *current-trace* nil
  "Active DELIBERATIVE-TRACE being recorded, or NIL.")

(defvar *last-trace* nil
  "Most recently finished deliberative trace.")

(defvar *trace-history* nil
  "Newest-first list of finished traces (session buffer, not persistence).")

(defparameter *trace-history-limit* 32
  "Max finished traces retained in *TRACE-HISTORY*: a non-negative integer.
Any other value retains none.")

(defvar *trace-counter* 0
  "How many traces this Lisp image has made; numbers the next TRACE-ID.")

(defun %next-trace-id ()
  "A fresh uninterned symbol named TRACE-<n>.
An interned id would leak one symbol per trace into whichever package
happened to be current."
  (make-symbol (format nil "TRACE-~D" (incf *trace-counter*))))

(defclass deliberative-trace ()
  ((id
    :initarg :id
    :accessor trace-id
    :initform (%next-trace-id)
    :documentation "Uninterned symbol naming the trace in explanations.")
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
    :documentation "Event plists: newest first while the trace is open,
oldest first once it is finalized.")
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
  "True when OBJECT is a DELIBERATIVE-TRACE."
  (typep object 'deliberative-trace))

(defun make-trace (&key phase context-name)
  "A fresh open DELIBERATIVE-TRACE for PHASE in CONTEXT-NAME, with no entries.
WITH-TRACE is the usual way to record into one."
  (make-instance 'deliberative-trace
                 :phase phase
                 :context-name context-name))

(defun trace-record (kind &rest plist)
  "Append a deliberative event to *CURRENT-TRACE*.
KIND is a keyword such as :GOAL :DIFFERENCE :SELECTED-OPERATOR :PRECONDITION
:ACTION :RESULT :SUBGOAL :CONTEXT :STATE :EXECUTION-STEP :EVENT.
Returns the entry plist, or NIL if tracing is off / no current trace."
  (when (and *trace-enabled* (deliberative-trace-p *current-trace*)
             (trace-open-p *current-trace*))
    (let ((entry (list* :kind kind
                        :time (get-universal-time)
                        plist)))
      (push entry (trace-entries *current-trace*))
      entry)))

(defun %publish-trace (trace)
  "Make TRACE the last trace and the newest entry of the bounded history.
Each variable is assigned once, and the history only ever with a list that
no one else holds, so a reader never sees a half-built history."
  (let ((limit (if (typep *trace-history-limit* '(integer 0))
                   *trace-history-limit*
                   0))
        (history (cons trace *trace-history*)))
    (setf *trace-history* (if (> (length history) limit)
                              (subseq history 0 limit)
                              history)
          *last-trace* trace)))

(defun finalize-trace (&optional (trace *current-trace*))
  "Close TRACE, put its entries in chronological order and publish it as
*LAST-TRACE* and the head of *TRACE-HISTORY*. A trace is published once:
finalizing a closed trace changes nothing.
Returns TRACE, or NIL when TRACE is not a trace."
  (when (deliberative-trace-p trace)
    (when (trace-open-p trace)
      ;; REVERSE, not NREVERSE: a caller may still hold the list it read from
      ;; TRACE-ENTRIES while the trace was open, or have supplied :ENTRIES.
      (setf (trace-entries trace) (reverse (trace-entries trace))
            (trace-open-p trace) nil
            (trace-finished-at trace) (get-universal-time))
      (%publish-trace trace))
    (when (eq trace *current-trace*)
      (setf *current-trace* nil))
    trace))

(defun call-with-trace (phase context-name thunk)
  "Call THUNK with a fresh trace for PHASE bound to *CURRENT-TRACE*.
The trace is finalized when THUNK exits, normally or not. When
*TRACE-ENABLED* is false there is no trace: *CURRENT-TRACE* is NIL inside
THUNK and nothing is published. Returns the values of THUNK."
  (if *trace-enabled*
      (let* ((trace (make-trace :phase phase :context-name context-name))
             (*current-trace* trace))
        (trace-record :begin :phase phase :context context-name)
        (unwind-protect
             (funcall thunk)
          (finalize-trace trace)))
      (let ((*current-trace* nil))
        (funcall thunk))))

(defmacro with-trace ((phase &key context-name) &body body)
  "Run BODY recording into a fresh *CURRENT-TRACE*, finalized afterward.
PHASE and CONTEXT-NAME are each evaluated once. See CALL-WITH-TRACE."
  `(call-with-trace ,phase ,context-name (lambda () ,@body)))

;;; ---------------------------------------------------------------------------
;;; Introspection
;;; ---------------------------------------------------------------------------

(defun last-trace ()
  "The most recently finished deliberative trace, or NIL."
  *last-trace*)

(defun trace-of (object)
  "The deliberative trace carried by a PLAN or an EXECUTION-RESULT, OBJECT
itself when it is a trace, otherwise NIL."
  (cond
    ((deliberative-trace-p object) object)
    ((plan-p object) (getf (plan-meta object) :trace))
    ((execution-result-p object) (getf (execution-meta object) :trace))))

(defun %chronological-entries (trace)
  "Entries of TRACE oldest first, whether or not it is still open."
  (if (trace-open-p trace)
      (reverse (trace-entries trace))
      (trace-entries trace)))

(defun find-trace-entries (kind &optional (trace *last-trace*))
  "Entries in TRACE whose :KIND is KIND, oldest first."
  (when (deliberative-trace-p trace)
    (remove-if-not (lambda (entry) (eq (getf entry :kind) kind))
                   (%chronological-entries trace))))

(defun clear-trace-session ()
  "Clear the in-session trace buffer (not durable persistence)."
  (setf *current-trace* nil
        *last-trace* nil
        *trace-history* nil)
  t)

(defun resolve-explain-topic (topic)
  "The deliberative trace TOPIC designates, or NIL.
TOPIC is a trace, a PLAN or an EXECUTION-RESULT (its own trace), or one of
  :LAST or NIL  the last finished trace
  :PLAN         the trace of *CURRENT-PLAN*
  :EXECUTION    the trace of *LAST-EXECUTION*
  :HISTORY      the newest trace in *TRACE-HISTORY*
With no current plan :PLAN means :LAST, and so does :EXECUTION with no last
execution. A plan or execution that carries no trace yields NIL: it is never
explained by the trace of something else."
  (case topic
    ((nil :last) *last-trace*)
    (:plan (if *current-plan* (trace-of *current-plan*) *last-trace*))
    (:execution (if *last-execution* (trace-of *last-execution*) *last-trace*))
    (:history (first *trace-history*))
    (t (trace-of topic))))

;;; ---------------------------------------------------------------------------
;;; Formatting (derived only from recorded entries)
;;; ---------------------------------------------------------------------------

(defmacro %with-standard-printing (&body body)
  "Run BODY under the standard printer settings, unreadable objects allowed.
Rendered text must not change with the caller's *PRINT-CASE*, *PRINT-BASE*
or *PRINT-LENGTH*: a truncated fact list would be a hidden omission."
  `(with-standard-io-syntax
     (let ((*print-readably* nil))
       ,@body)))

(defun %fmt-term (term)
  "TERM in Lisp notation with every symbol printed by its name alone.
A package prefix would make the text depend on the reader's *PACKAGE*.
Keywords keep their colon, strings their quotes, and a dotted tail its dot."
  (with-output-to-string (out)
    (labels ((walk (x)
               (cond
                 ((keywordp x)
                  (write-char #\: out)
                  (write-string (symbol-name x) out))
                 ((symbolp x)
                  (write-string (symbol-name x) out))
                 ((consp x)
                  (write-char #\( out)
                  (loop for cell = x then (cdr cell)
                        do (walk (car cell))
                           (cond
                             ((null (cdr cell)) (return))
                             ((consp (cdr cell)) (write-char #\Space out))
                             (t (write-string " . " out)
                                (walk (cdr cell))
                                (return))))
                  (write-char #\) out))
                 (t (prin1 x out)))))
      (walk term))))

(defun %fmt-term-lines (terms)
  "One indented line per term in TERMS; \"(none)\" when TERMS is empty."
  (format nil "~:[    (none)~%~;~:*~{    ~A~%~}~]" (mapcar #'%fmt-term terms)))

(defun %fmt-bindings (bindings)
  "BINDINGS as \" ?X=A ?Y=B\", or \"\" when nothing is bound.
The empty-success sentinel prints nothing, even as a copy of *NO-BINDINGS*."
  (format nil "~{ ~A~}"
          (loop for pair in (binding-alist bindings)
                unless (equal pair '(t . t))
                  collect (format nil "~A=~A"
                                  (%fmt-term (car pair))
                                  (%fmt-term (cdr pair))))))

(defun %entry-details (entry)
  "ENTRY without the :KIND and :TIME that TRACE-RECORD adds."
  (loop for (key value) on entry by #'cddr
        unless (member key '(:kind :time))
          collect key and collect value))

(defun %explain-event (entry out)
  "Write an :EVENT ENTRY to OUT. False when its :ACTION is not one recorded
by EMIT-EVENT! or REACT-TO-EVENT!, and then nothing is written."
  (let ((id (getf entry :id))
        (type (getf entry :type)))
    (case (getf entry :action)
      (:emit
       (format out "Event emitted:~%    ~@[~A ~]~A~%~%"
               id (%fmt-term (cons type (getf entry :data))))
       t)
      (:react
       (format out "Event reaction:~%    ~@[~A ~]~A~%" id type)
       (format out "~:[    no reaction matched~%~;~:*~{    matched ~A~%~}~]"
               (getf entry :matched))
       (format out "~{    asserted ~A~%~}~{    goal ~A~%~}~%"
               (mapcar #'%fmt-term (getf entry :facts))
               (mapcar #'%fmt-term (getf entry :goals)))
       t))))

(defun %explain-entry (entry trace out)
  "Write ENTRY of TRACE to OUT as one titled block."
  (flet ((term (key) (%fmt-term (getf entry key)))
         (terms (key) (%fmt-term-lines (getf entry key)))
         (as-recorded ()
           (format out "~A:~%    ~A~%~%"
                   (getf entry :kind) (%fmt-term (%entry-details entry)))))
    (case (getf entry :kind)
      (:begin
       (format out "Begin (~A)~%~%" (getf entry :phase)))
      (:context
       ;; The header already names the context of the trace: repeat it only
       ;; when an entry records a different one.
       (unless (equal (getf entry :name) (trace-context-name trace))
         (format out "Context:~%    ~A~%~%" (getf entry :name))))
      (:goal
       (format out "Goal:~%    ~A~%~%" (term :goal)))
      (:goals
       (format out "Goals:~%~A~%" (terms :goals)))
      (:state
       (format out "Current state:~%~A~%" (terms :facts)))
      (:difference
       (format out "Difference:~%    ~A~%~%" (term :goal)))
      (:differences
       (format out "Differences:~%~A~%" (terms :goals)))
      (:goal-already-satisfied
       (format out "Goal already satisfied:~%    ~A~@[~%    operator ~A~]~%~%"
               (term :goal) (getf entry :operator)))
      (:projected-effects
       (format out "Projected effects:~%    ~A~%    ~A~%~%"
               (getf entry :operator) (term :goal)))
      (:recorded-effects
       (format out "Recorded effects:~%    ~A~%    ~A~%~%"
               (getf entry :operator) (term :goal)))
      (:missing-precondition
       (format out "Missing precondition:~%~A    for ~A~
                    ~@[~%    reused procedure ~A~]~%~%"
               (terms :goals) (getf entry :operator) (getf entry :from-procedure)))
      (:repair-step
       (format out "Repair step:~%    ~A~%    ~A~%~%"
               (getf entry :operator) (term :goal)))
      (:step-set-aside
       (format out "Left aside:~%    ~A~%    ~A~%~%"
               (getf entry :operator) (term :goal)))
      (:selected-operator
       (format out "Selected operator:~%    ~A~A~%~%"
               (getf entry :operator) (%fmt-bindings (getf entry :bindings))))
      (:subgoal
       (format out "Required precondition (subgoal):~%    ~A~%~%" (term :goal)))
      (:precondition
       (format out "Precondition:~%    ~A — ~A~%~%"
               (getf entry :status) (term :goal)))
      (:action
       (format out "Action:~%    ~A~A~%~%"
               (getf entry :operator) (%fmt-bindings (getf entry :bindings))))
      (:result
       (format out "Result:~%    ~A~@[ for ~A~]~%~%"
               (getf entry :status) (and (getf entry :goal) (term :goal))))
      (:operator-failed
       (format out "Operator failed:~%    ~A~@[ (~A)~]~%~{    missing ~A~%~}~%"
               (getf entry :operator) (getf entry :reason)
               (mapcar #'%fmt-term (getf entry :missing))))
      (:execution-step
       (format out "Execution step (~A):~%    ~A → ~A~%~%"
               (getf entry :mode) (getf entry :operator) (getf entry :status)))
      (:reused-procedure
       (format out "Reused procedure:~%    ~A~@[ (score ~,3F)~]~%~%"
               (getf entry :name) (getf entry :score)))
      (:plan-complete
       (format out "Plan complete:~%    success=~A steps=~A~%~{    remaining ~A~%~}~%"
               (getf entry :success) (getf entry :steps)
               (mapcar #'%fmt-term (getf entry :remaining))))
      (:execution-complete
       (format out "Execution complete:~%    mode=~A success=~A~%~%"
               (getf entry :mode) (getf entry :success)))
      (:event
       (or (%explain-event entry out) (as-recorded)))
      (otherwise
       (as-recorded)))))

(defun format-explanation (trace &optional stream)
  "Render TRACE as text following the PROMPT §17 shape.
Only recorded entries are used: no decision is invented, and the text does
not depend on the caller's *PACKAGE* or printer settings.
STREAM is as for FORMAT: with NIL the text is returned; otherwise it is
written to STREAM (T means *STANDARD-OUTPUT*) and NIL is returned."
  (if (deliberative-trace-p trace)
      (format stream "~A"
              (%with-standard-printing
                (with-output-to-string (out)
                  (format out "Deliberative trace ~A (phase ~A)~%"
                          (trace-id trace) (or (trace-phase trace) '?))
                  (when (trace-context-name trace)
                    (format out "Context:~%    ~A~%~%" (trace-context-name trace)))
                  (dolist (entry (%chronological-entries trace))
                    (%explain-entry entry trace out)))))
      (format stream "No deliberative trace available.~%")))

(defun explain-trace (topic &key stream)
  "Explain TOPIC (see RESOLVE-EXPLAIN-TOPIC) from its recorded trace.
Returns (VALUES TEXT TRACE). STREAM is as for FORMAT: with NIL, TEXT is the
explanation; otherwise the explanation is written to STREAM and TEXT is NIL.
When TOPIC has no trace the text says so and TRACE is NIL.
Named EXPLAIN-TRACE (not EXPLAIN) to avoid clashing with FiveAM:EXPLAIN."
  (let ((trace (resolve-explain-topic topic)))
    (values (if trace
                (format-explanation trace stream)
                (format stream "No deliberative trace for ~S.~%" topic))
            trace)))
