;;;; core/events.lisp — context-bound events & event-driven reaction (Phase 10)
;;;;
;;;; Flow: EVENT → reaction (assert facts / add goals) → optional PLAN → UPDATE.
;;;; Coexists with goal-directed planning: emit/react may add goals; gp-plan
;;;; still works without any events.
;;;;
;;;; Looks at files, processes, and open terminals live in interface/notice.lisp.
;;;; GP-NOTICE-PATH posts one existing file only when a reaction already
;;;; matches FILE-CREATED. Other events are still posted by the REPL/API.
;;;; Reactions are pattern matches over event type+data, not a separate MEA.

(in-package #:automa-gp)

(defvar *event-counter* 0
  "Monotonic counter for event ids within a Lisp image.")

(defvar *last-reaction* nil
  "Plist describing the last PROCESS-PENDING-EVENTS! / GP-REACT result.")

(defclass gp-event ()
  ((id
    :initarg :id
    :accessor event-id
    :documentation "Unique id for this event instance.")
   (type
    :initarg :type
    :accessor event-type
    :documentation "Event type symbol, e.g. FILE-CREATED.")
   (data
    :initarg :data
    :accessor event-data
    :initform nil
    :documentation "Ground argument list for the event.")
   (timestamp
    :initarg :timestamp
    :accessor event-timestamp
    :initform (get-universal-time))
   (status
    :initarg :status
    :accessor event-status
    :initform :pending
    :documentation ":PENDING, :PROCESSED, or :IGNORED.")
   (meta
    :initarg :meta
    :accessor event-meta
    :initform nil))
  (:documentation "A symbolic event bound to a context."))

(defun event-p (object)
  (typep object 'gp-event))

(defun next-event-id ()
  (incf *event-counter*)
  (intern (format nil "EVT-~D" *event-counter*) :automa-gp))

(defun parse-event-form (form)
  "Parse FORM into (VALUES TYPE DATA).
FORM is (TYPE . DATA), e.g. (FILE-CREATED \"doc.pdf\")."
  (unless (and (consp form) (symbolp (car form)))
    (error "Event form must be (TYPE . DATA), got ~S" form))
  (values (car form) (copy-list (cdr form))))

(defun make-event (&key type data (status :pending) meta id timestamp)
  "Construct a GP-EVENT. TYPE is required."
  (unless type
    (error "MAKE-EVENT requires :TYPE"))
  (make-instance 'gp-event
                 :id (or id (next-event-id))
                 :type type
                 :data (copy-list data)
                 :status status
                 :meta (copy-tree meta)
                 :timestamp (or timestamp (get-universal-time))))

(defun event-form (event)
  "Return the (TYPE . DATA) list form of EVENT."
  (cons (event-type event) (copy-list (event-data event))))

(defclass event-reaction ()
  ((name
    :initarg :name
    :accessor event-reaction-name
    :initform nil)
   (when
    :initarg :when
    :accessor event-reaction-when
    :initform nil
    :documentation "Pattern (TYPE . DATA-PATTERNS), e.g. (FILE-CREATED ?PATH).")
   (assert
    :initarg :assert
    :accessor event-reaction-assert
    :initform nil
    :documentation "Fact patterns to assert (bindings substituted).")
   (goals
    :initarg :goals
    :accessor event-reaction-goals
    :initform nil
    :documentation "Goal patterns to add (bindings substituted).")
   (meta
    :initarg :meta
    :accessor event-reaction-meta
    :initform nil))
  (:documentation "Reaction: match event → assert facts and/or add goals."))

(defun event-reaction-p (object)
  (typep object 'event-reaction))

(defun make-event-reaction (&key name when assert goals meta)
  "Construct an EVENT-REACTION. :WHEN is (TYPE . DATA-PATTERNS)."
  (make-instance 'event-reaction
                 :name name
                 :when when
                 :assert (normalize-pattern-list assert)
                 :goals (normalize-pattern-list goals)
                 :meta meta))

(defun register-event-reaction! (context reaction)
  "Register REACTION on CONTEXT (by name if present)."
  (unless (context-p context)
    (error "REGISTER-EVENT-REACTION! requires a context"))
  (unless (event-reaction-p reaction)
    (error "REGISTER-EVENT-REACTION! requires an EVENT-REACTION"))
  (let* ((name (event-reaction-name reaction))
         (rs (context-event-reactions context)))
    (setf (context-event-reactions context)
          (if name
              (cons reaction
                    (remove name rs :key #'event-reaction-name :test #'equal))
              (append rs (list reaction))))
    reaction))

(defun remove-event-reaction! (context name)
  "Remove event reaction named NAME from CONTEXT."
  (setf (context-event-reactions context)
        (remove name (context-event-reactions context)
                :key #'event-reaction-name :test #'equal))
  (context-event-reactions context))

(defun event-reactions-of (context)
  "Local event reactions on CONTEXT."
  (context-event-reactions context))

(defun context-all-event-reactions (context)
  "Event reactions along the parent chain (local names win)."
  (let ((chain nil)
        (result nil)
        (seen nil))
    (loop for c = context then (context-parent c)
          while c
          do (push c chain))
    (dolist (c (reverse chain))
      (dolist (r (context-event-reactions c))
        (let ((n (event-reaction-name r)))
          (cond
            ((and n (member n seen :test #'equal)) nil)
            (t
             (when n (push n seen))
             (push r result))))))
    (nreverse result)))

(defun match-event-reaction (reaction event)
  "Match REACTION :WHEN against EVENT. Returns bindings or *FAIL*."
  (let ((pat (event-reaction-when reaction)))
    (if (null pat)
        *fail*
        (match pat (event-form event)))))

(defun events-of (context &key status)
  "Events on CONTEXT, oldest first. Optional :STATUS filter (:PENDING …)."
  (let ((evs (copy-list (context-events context))))
    (if status
        (remove status evs :key #'event-status :test-not #'eq)
        evs)))

(defun pending-events (context)
  (events-of context :status :pending))

(defun clear-events! (context &key (status nil status-p))
  "Clear events on CONTEXT. With :STATUS, only clear matching status."
  (setf (context-events context)
        (if status-p
            (remove status (context-events context)
                    :key #'event-status :test #'eq)
            nil))
  (context-events context))

(defun emit-event! (context form-or-event &key (assert-fact t) meta)
  "Post an event onto CONTEXT. FORM-OR-EVENT is (TYPE . DATA) or a GP-EVENT.
When ASSERT-FACT (default T), also assert (TYPE . DATA) as a context fact
so ordinary forward-chain rules can see it.
Returns the GP-EVENT (status :PENDING)."
  (unless (context-p context)
    (error "EMIT-EVENT! requires a context"))
  (let ((event (if (event-p form-or-event)
                   form-or-event
                   (multiple-value-bind (type data)
                       (parse-event-form form-or-event)
                     (make-event :type type :data data :meta meta)))))
    (setf (event-status event) :pending)
    (setf (context-events context)
          (append (context-events context) (list event)))
    (when assert-fact
      (let ((fact (event-form event)))
        (setf (context-facts context)
              (add-fact! (context-facts context) fact))))
    (trace-record :event
                  :action :emit
                  :type (event-type event)
                  :data (copy-list (event-data event))
                  :id (event-id event))
    event))

(defun %apply-reaction-bindings (reaction bindings)
  "Return (VALUES FACTS GOALS) ground from REACTION under BINDINGS."
  (let ((facts nil)
        (goals nil))
    (dolist (pat (event-reaction-assert reaction))
      (let ((f (substitute-bindings pat bindings)))
        (unless (or (eq f *fail*) (pattern-has-variable-p f))
          (push f facts))))
    (dolist (pat (event-reaction-goals reaction))
      (let ((g (substitute-bindings pat bindings)))
        (unless (or (eq g *fail*) (pattern-has-variable-p g))
          (push g goals))))
    (values (nreverse facts) (nreverse goals))))

(defun react-to-event! (context event &key (reactions nil reactions-p))
  "Apply matching event reactions to EVENT on CONTEXT.
Asserts facts, adds goals, marks EVENT :PROCESSED (or :IGNORED if none matched).
Returns a plist (:EVENT :MATCHED :FACTS-ADDED :GOALS-ADDED)."
  (let* ((rs (if reactions-p
                 reactions
                 (context-all-event-reactions context)))
         (matched nil)
         (facts-added nil)
         (goals-added nil))
    (dolist (r rs)
      (let ((b (match-event-reaction r event)))
        (unless (fail-p b)
          (push (event-reaction-name r) matched)
          (multiple-value-bind (facts goals)
              (%apply-reaction-bindings r b)
            (dolist (f facts)
              (setf (context-facts context)
                    (add-fact! (context-facts context) f))
              (push f facts-added))
            (dolist (g goals)
              (add-goal! context g)
              (push g goals-added))))))
    (setf (event-status event) (if matched :processed :ignored))
    (trace-record :event
                  :action :react
                  :type (event-type event)
                  :id (event-id event)
                  :matched (reverse matched)
                  :facts (reverse facts-added)
                  :goals (reverse goals-added))
    (list :event event
          :matched (nreverse matched)
          :facts-added (nreverse facts-added)
          :goals-added (nreverse goals-added))))

(defun process-pending-events! (context &key (plan nil) (infer nil))
  "Process all :PENDING events on CONTEXT (oldest first).
Optionally forward-chain (:INFER T) after reactions.
When :PLAN is true and the context has goals, build a plan via MEA and
store it in *CURRENT-PLAN*. Returns a summary plist (also in *LAST-REACTION*).
Does not record episodic memory — callers (e.g. GP-REACT) may do so."
  (let* ((pending (pending-events context))
         (all-matched nil)
         (all-facts nil)
         (all-goals nil)
         (results nil)
         (plan-obj nil))
    (dolist (ev pending)
      (let ((r (react-to-event! context ev)))
        (push r results)
        (setf all-matched (append all-matched (getf r :matched)))
        (setf all-facts (append all-facts (getf r :facts-added)))
        (setf all-goals (append all-goals (getf r :goals-added)))))
    (when infer
      (multiple-value-bind (all new)
          (forward-chain (context-all-facts context)
                         (context-all-rules context))
        (declare (ignore all))
        (dolist (f new)
          (setf (context-facts context)
                (add-fact! (context-facts context) f))
          (push f all-facts))))
    (when (and plan (goals-of context))
      (setf (context-mode context) :plan)
      (setf plan-obj (plan-from-context context))
      (setf *current-plan* plan-obj))
    (setf *last-reaction*
          (list :processed (length pending)
                :matched all-matched
                :facts-added all-facts
                :goals-added all-goals
                :plan plan-obj
                :results (nreverse results)))
    *last-reaction*))
