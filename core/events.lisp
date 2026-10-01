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
  "Number of the newest event id issued or restored in this Lisp image.
Ids are symbols named EVT-n and n only grows, so an id is not issued twice.
MAKE-EVENT moves the counter past every EVT-n id it is handed, which keeps
the ids of a restored context distinct from the ones issued after it.")

(defvar *last-reaction* nil
  "Plist describing the last PROCESS-PENDING-EVENTS! / GP-REACT result.")

(defclass gp-event ()
  ((id
    :initarg :id
    :accessor event-id
    :documentation "Id of this event, unique within a context's event log.")
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
  "True if OBJECT is a GP-EVENT."
  (typep object 'gp-event))

(defun next-event-id ()
  "Issue the next event id: the symbol EVT-n for the next unused n."
  (intern (format nil "EVT-~D" (incf *event-counter*)) :automa-gp))

(defun %event-id-number (id)
  "The n of an id named EVT-n, or NIL for any other id."
  (when (symbolp id)
    (let ((name (symbol-name id)))
      (when (and (> (length name) 4)
                 (string= "EVT-" name :end2 4)
                 (every #'digit-char-p (subseq name 4)))
        (parse-integer name :start 4)))))

(defun parse-event-form (form)
  "Parse FORM into (VALUES TYPE DATA).
FORM is (TYPE . DATA), e.g. (FILE-CREATED \"doc.pdf\")."
  (unless (and (consp form) (symbolp (car form)))
    (error "Event form must be (TYPE . DATA), got ~S" form))
  (values (car form) (copy-list (cdr form))))

(defun make-event (&key type data (status :pending) meta id timestamp)
  "Construct a GP-EVENT. TYPE is required.
Without ID the event gets the next EVT-n id. An ID named EVT-n, as on an
event restored from a saved context, moves *EVENT-COUNTER* up to n so that
no later event is issued the same id."
  (unless type
    (error "MAKE-EVENT requires :TYPE"))
  (let ((n (%event-id-number id)))
    (when n
      (setf *event-counter* (max *event-counter* n))))
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
  "True if OBJECT is an EVENT-REACTION."
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
  "Events on CONTEXT, oldest first, as a fresh list.
With :STATUS (:PENDING …) only the events in that status; NIL lists all."
  (loop for event in (context-events context)
        when (or (null status) (eq (event-status event) status))
          collect event))

(defun pending-events (context)
  "Events on CONTEXT still waiting for PROCESS-PENDING-EVENTS!, oldest first."
  (events-of context :status :pending))

(defun clear-events! (context &key status)
  "Clear events on CONTEXT and return the events left.
With :STATUS, clear only the events in that status. NIL, the default,
clears them all, the same way EVENTS-OF with a NIL status lists them all."
  (setf (context-events context)
        (when status
          (remove status (context-events context)
                  :key #'event-status :test #'eq))))

(defun emit-event! (context form-or-event &key (assert-fact t)
                                            (meta nil meta-p))
  "Post an event onto CONTEXT. FORM-OR-EVENT is (TYPE . DATA) or a GP-EVENT.
A form makes a new event carrying META. A GP-EVENT is posted as it is: its
status becomes :PENDING and META, when supplied, replaces its meta.
An event whose id is already in CONTEXT's log is an error and changes
nothing: the same event posted twice would sit in the log twice, be
reacted to twice, and settle both entries at once.
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
    (when (find (event-id event) (context-events context)
                :key #'event-id :test #'equal)
      (error "Event ~S is already posted on context ~S."
             (event-id event) (context-name context)))
    (when (and meta-p (event-p form-or-event))
      (setf (event-meta event) (copy-tree meta)))
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
  "Instantiate REACTION's :ASSERT and :GOALS patterns under BINDINGS.
Returns (VALUES FACTS GOALS DROPPED). A pattern that still holds a variable,
one the reaction's :WHEN did not bind, is neither asserted nor added as a
goal; its instance is returned in DROPPED so the caller can report it."
  (let ((dropped nil))
    (flet ((instances (patterns)
             (loop for pattern in patterns
                   for instance = (substitute-bindings pattern bindings)
                   if (pattern-has-variable-p instance)
                     do (push instance dropped)
                   else
                     collect instance)))
      (let* ((facts (instances (event-reaction-assert reaction)))
             (goals (instances (event-reaction-goals reaction))))
        (values facts goals (nreverse dropped))))))

(defun react-to-event! (context event &key (reactions nil reactions-p))
  "Apply matching event reactions to EVENT on CONTEXT.
Asserts facts, adds goals, marks EVENT :PROCESSED (or :IGNORED if none matched).
Returns a plist (:EVENT :MATCHED :FACTS-ADDED :GOALS-ADDED :DROPPED).
:FACTS-ADDED and :GOALS-ADDED name only what this call added: a fact
CONTEXT already held and a goal it already listed are left out. :DROPPED
lists the :ASSERT and :GOALS instances that still held a variable and were
therefore neither asserted nor added."
  (let ((matched nil)
        (facts-added nil)
        (goals-added nil)
        (dropped nil))
    (dolist (reaction (if reactions-p
                          reactions
                          (context-all-event-reactions context)))
      (let ((bindings (match-event-reaction reaction event)))
        (unless (fail-p bindings)
          (push (event-reaction-name reaction) matched)
          (multiple-value-bind (facts goals non-ground)
              (%apply-reaction-bindings reaction bindings)
            (dolist (fact facts)
              (unless (fact-p fact (context-facts context))
                (setf (context-facts context)
                      (add-fact! (context-facts context) fact))
                (push fact facts-added)))
            (dolist (goal goals)
              (unless (goal-active-p context goal)
                (add-goal! context goal)
                (push goal goals-added)))
            (setf dropped (append dropped non-ground))))))
    (setf (event-status event) (if matched :processed :ignored))
    (setf matched (nreverse matched)
          facts-added (nreverse facts-added)
          goals-added (nreverse goals-added))
    (trace-record :event
                  :action :react
                  :type (event-type event)
                  :id (event-id event)
                  :matched (copy-list matched)
                  :facts (copy-list facts-added)
                  :goals (copy-list goals-added)
                  :dropped (copy-list dropped))
    (list :event event
          :matched matched
          :facts-added facts-added
          :goals-added goals-added
          :dropped dropped)))

(defun %assert-inferred-facts! (context)
  "Forward-chain CONTEXT's rules over its facts and assert what is new.
Returns the new facts, in the order they were derived."
  (let ((new (nth-value 1 (forward-chain (context-all-facts context)
                                         (context-all-rules context)))))
    (dolist (fact new)
      (setf (context-facts context)
            (add-fact! (context-facts context) fact)))
    new))

(defun process-pending-events! (context &key (plan nil) (infer nil))
  "Process all :PENDING events on CONTEXT (oldest first).
Optionally forward-chain (:INFER T) after reactions.
When :PLAN is true and a fact-like goal of the context is still open, build
a plan via MEA, store it in *CURRENT-PLAN* and set the mode to :PLAN. With
no open goal there is nothing to plan: the previous plan and the mode stay,
as with GP-PLAN.
Returns a summary plist (:PROCESSED :MATCHED :FACTS-ADDED :GOALS-ADDED
:DROPPED :PLAN :RESULTS), also kept in *LAST-REACTION*. :FACTS-ADDED lists
the facts the reactions added, then the inferred ones; :RESULTS holds the
REACT-TO-EVENT! plist of each event.
Does not record episodic memory — callers (e.g. GP-REACT) may do so."
  (let* ((pending (pending-events context))
         (results (mapcar (lambda (event) (react-to-event! context event))
                          pending))
         (inferred (when infer (%assert-inferred-facts! context)))
         (plan-obj nil))
    (when (and plan
               (differences (context-all-facts context)
                            (normalize-planning-goals (goals-of context))))
      (setf (context-mode context) :plan)
      (setf plan-obj (plan-from-context context))
      (setf *current-plan* plan-obj))
    (flet ((collect (key)
             (loop for result in results
                   append (copy-list (getf result key)))))
      (setf *last-reaction*
            (list :processed (length pending)
                  :matched (collect :matched)
                  :facts-added (append (collect :facts-added)
                                       (copy-list inferred))
                  :goals-added (collect :goals-added)
                  :dropped (collect :dropped)
                  :plan plan-obj
                  :results results)))))
