;;;; core/context.lisp — context core (Phase 1)
;;;;
;;;; A context is the fundamental unit GP works inside. Hierarchical
;;;; parent/child contexts support inherited fact lookup: a context sees its
;;;; own facts together with those of every ancestor. That is a union. A
;;;; local (POWER D ON) does not hide an inherited (POWER D OFF); only an
;;;; EQUAL copy of the same fact is listed once.

(in-package #:automa-gp)

(defclass context ()
  ((name
    :initarg :name
    :accessor context-name
    :initform nil
    :documentation "Symbolic name of this context.")
   (parent
    :initarg :parent
    :accessor context-parent
    :initform nil
    :documentation "Optional parent context for hierarchical lookup.
Writing it never makes a context its own ancestor: see CONTEXT-CYCLE.
CONTEXT-ADD-CHILD! also keeps the children lists in step.")
   (children
    :initarg :children
    :accessor context-children
    :initform nil
    :documentation "List of direct child contexts.")
   (facts
    :initarg :facts
    :accessor context-facts
    :initform nil
    :documentation "Local symbolic facts (lists).")
   (goals
    :initarg :goals
    :accessor context-goals
    :initform nil
    :documentation "Goals associated with this context.")
   (actions
    :initarg :actions
    :accessor context-actions
    :initform nil
    :documentation "Action registry for this context (alist name → action).")
   (rules
    :initarg :rules
    :accessor context-rules
    :initform nil
    :documentation "Local symbolic rules (Phase 2).")
   (operators
    :initarg :operators
    :accessor context-operators
    :initform nil
    :documentation "Local planning operators (Phase 3).")
   (events
    :initarg :events
    :accessor context-events
    :initform nil
    :documentation "Context-bound event log (Phase 10), oldest first.")
   (event-reactions
    :initarg :event-reactions
    :accessor context-event-reactions
    :initform nil
    :documentation "Event reactions (match event → facts/goals), Phase 10.")
   (mode
    :initarg :mode
    :accessor context-mode
    :initform :read
    :documentation "Operational mode skeleton (:READ :PLAN :SIMULATE :EXECUTE).")
   (meta
    :initarg :meta
    :accessor context-meta
    :initform nil
    :documentation "Arbitrary metadata plist/alist."))
  (:documentation "AUTOMA GP context — symbolic work unit."))

(defun context-p (object)
  "True if OBJECT is a CONTEXT."
  (typep object 'context))

;;; Session specials used across core, memory, domains, and the REPL.
;;; Defined here (early in the ASDF order) so later files compile cleanly.
(defvar *current-context* nil
  "Session current context for REPL helpers and domain defaults.")

(defvar *current-plan* nil
  "Last plan produced by GP-PLAN in this session.")

(defvar *last-execution* nil
  "Last EXECUTION-RESULT from GP-SIMULATE or GP-RUN.")

(define-condition context-cycle (error)
  ((context
    :initarg :context
    :reader context-cycle-context
    :documentation "The context that is, or would become, its own ancestor.")
   (parent
    :initarg :parent
    :initform nil
    :reader context-cycle-parent
    :documentation "The refused parent; NIL when an existing loop was met."))
  (:report (lambda (condition stream)
             (let ((context (context-cycle-context condition))
                   (parent (context-cycle-parent condition)))
               (if parent
                   (format stream "Context ~S cannot have parent ~S: ~
                                   it would become its own ancestor"
                           (context-name context) (context-name parent))
                   (format stream "The parent links of context ~S form a loop"
                           (context-name context))))))
  (:documentation "A parent link would close, or has closed, a loop of contexts.
Not a GP-ERROR: that hierarchy is defined in core/conditions.lisp, which
loads after this file, and it describes a step that failed in a plan run."))

(defun context-lineage (context)
  "CONTEXT followed by its ancestors, nearest first.
Signals CONTEXT-CYCLE if the parent links loop back on themselves."
  (loop with lineage = nil
        for c = context then (context-parent c)
        while c
        do (when (member c lineage :test #'eq)
             (error 'context-cycle :context context))
           (push c lineage)
        finally (return (nreverse lineage))))

(defmethod (setf context-parent) :before (parent (child context))
  "Refuse, before anything is written, a PARENT that is CHILD or one of its
descendants."
  (when (and parent (member child (context-lineage parent) :test #'eq))
    (error 'context-cycle :context child :parent parent)))

(defun context-add-child! (parent child)
  "Make CHILD a child of PARENT (mutates both) and return CHILD.
CHILD leaves the children of the parent it had before. Signals CONTEXT-CYCLE,
leaving every context as it was, when PARENT is CHILD or one of its
descendants."
  (let ((previous (context-parent child)))
    (setf (context-parent child) parent)
    (when (and previous (not (eq previous parent)))
      (setf (context-children previous)
            (remove child (context-children previous) :test #'eq)))
    (pushnew child (context-children parent) :test #'eq)
    child))

(defun make-context (&key name parent facts goals actions rules operators
                       events event-reactions mode meta children)
  "Construct a CONTEXT. MODE defaults to :READ.
The new context inherits from PARENT but is not listed among PARENT's
children; CREATE-CONTEXT does both. Each context in CHILDREN becomes a child
of the new one, as by CONTEXT-ADD-CHILD!. Signals CONTEXT-CYCLE, moving no
child, when one of CHILDREN is PARENT or an ancestor of PARENT."
  (let ((context (make-instance 'context
                                :name name
                                :parent parent
                                :facts (copy-list facts)
                                :goals (copy-list goals)
                                :actions (copy-tree actions)
                                :rules (copy-list rules)
                                :operators (copy-list operators)
                                :events (copy-list events)
                                :event-reactions (copy-list event-reactions)
                                :mode (if mode (ensure-mode mode) :read)
                                :meta (copy-tree meta))))
    ;; Refuse every child before moving any, so that a refusal leaves all of
    ;; them under the parents they had.
    (let ((lineage (context-lineage context)))
      (dolist (child children)
        (when (member child lineage :test #'eq)
          (error 'context-cycle :context child :parent context))))
    ;; CONTEXT-ADD-CHILD! pushes, so add the last child first.
    (dolist (child (reverse children))
      (context-add-child! context child))
    context))

(defun create-context (&key name parent facts goals actions rules operators
                         events event-reactions mode meta)
  "Create a context and, if PARENT is given, register it as a child."
  (let ((ctx (make-context :name name
                           :parent parent
                           :facts facts
                           :goals goals
                           :actions actions
                           :rules rules
                           :operators operators
                           :events events
                           :event-reactions event-reactions
                           :mode mode
                           :meta meta)))
    (when parent
      (context-add-child! parent ctx))
    ctx))

(defun facts-of (context)
  "Local facts on CONTEXT (no inheritance)."
  (context-facts context))

(defun context-add-fact! (context fact)
  "Assert FACT among the local facts of CONTEXT (idempotent; mutates CONTEXT).
Returns the local facts. A copy of FACT held only by an ancestor does not
count: FACT is then stored locally as well."
  (setf (context-facts context) (add-fact! (context-facts context) fact)))

(defun context-remove-fact! (context fact)
  "Retract FACT from the local facts of CONTEXT (mutates CONTEXT).
Returns the local facts. A copy of FACT held by an ancestor stays where it
is, and stays visible through CONTEXT-ALL-FACTS."
  (setf (context-facts context) (remove-fact! (context-facts context) fact)))

(defun context-all-facts (context)
  "Facts visible in CONTEXT: its own and those of every ancestor, as a new list.
Ancestors contribute first. A fact that occurs more than once is listed
once, at its most local position. Nothing else is hidden: a local fact does
not override an inherited fact that merely differs from it."
  ;; EQUAL is FACT-EQUAL. Naming the standard predicate lets the
  ;; implementation hash a long list instead of comparing every pair.
  (remove-duplicates
   (mapcan (lambda (c) (copy-list (context-facts c)))
           (reverse (context-lineage context)))
   :test #'equal))

(defun context-query (context pattern)
  "Find facts visible in CONTEXT matching PATTERN (no rule inference).
For inference, see QUERY / GP-QUERY."
  (find-facts pattern (context-all-facts context)))

(defun context-modify! (context &key (name nil name-p)
                                 mode
                                 (meta nil meta-p)
                                 (facts nil facts-p)
                                 (goals nil goals-p)
                                 (actions nil actions-p)
                                 (rules nil rules-p)
                                 (operators nil operators-p)
                                 (events nil events-p)
                                 (event-reactions nil event-reactions-p))
  "Destructively modify CONTEXT slots when supplied.
A supplied NIL clears the slot, except for MODE: NIL is not a mode and
leaves the mode as it is. Lists are copied, as by MAKE-CONTEXT."
  (when name-p (setf (context-name context) name))
  (when mode (setf (context-mode context) (ensure-mode mode)))
  (when meta-p (setf (context-meta context) (copy-tree meta)))
  (when facts-p (setf (context-facts context) (copy-list facts)))
  (when goals-p (setf (context-goals context) (copy-list goals)))
  (when actions-p (setf (context-actions context) (copy-tree actions)))
  (when rules-p (setf (context-rules context) (copy-list rules)))
  (when operators-p (setf (context-operators context) (copy-list operators)))
  (when events-p (setf (context-events context) (copy-list events)))
  (when event-reactions-p
    (setf (context-event-reactions context) (copy-list event-reactions)))
  context)

(defun clone-context (context &key name as-child)
  "Deep-enough copy of CONTEXT (facts/goals/actions/rules/operators/events/meta).
Parent link is cleared unless AS-CHILD is true (then registered under original).
The copy has no children. Fact, rule, operator, action, event and reaction
objects are shared with CONTEXT; the lists that hold them are new."
  ;; MAKE-CONTEXT copies every list it is given.
  (let ((copy (make-context :name (or name (context-name context))
                            :facts (context-facts context)
                            :goals (context-goals context)
                            :actions (context-actions context)
                            :rules (context-rules context)
                            :operators (context-operators context)
                            :events (context-events context)
                            :event-reactions (context-event-reactions context)
                            :mode (context-mode context)
                            :meta (context-meta context))))
    (when as-child
      (context-add-child! context copy))
    copy))

(defun compare-contexts (a b)
  "Return a plist describing differences between contexts A and B.
Keys: :NAME-EQUAL :FACTS-ONLY-IN-A :FACTS-ONLY-IN-B :GOALS-ONLY-IN-A
:GOALS-ONLY-IN-B :MODE-EQUAL."
  (let* ((fa (context-all-facts a))
         (fb (context-all-facts b))
         (ga (context-goals a))
         (gb (context-goals b)))
    (list :name-equal (equal (context-name a) (context-name b))
          :mode-equal (eq (context-mode a) (context-mode b))
          :facts-only-in-a (set-difference fa fb :test #'fact-equal)
          :facts-only-in-b (set-difference fb fa :test #'fact-equal)
          :goals-only-in-a (set-difference ga gb :test #'equal)
          :goals-only-in-b (set-difference gb ga :test #'equal))))
