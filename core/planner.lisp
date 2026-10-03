;;;; core/planner.lisp — plan construction API (Phases 3+)
;;;;
;;;; Builds symbolic plans via MEA. Records a deliberative trace (Phase 6).

(in-package #:automa-gp)

(defclass plan ()
  ((goals
    :initarg :goals
    :accessor plan-goals
    :initform nil
    :documentation "Desired fact goals.")
   (steps
    :initarg :steps
    :accessor plan-steps
    :initform nil
    :documentation "Ordered plan steps (plists from MAKE-PLAN-STEP).")
   (success
    :initarg :success
    :accessor plan-success
    :initform nil
    :documentation "True if every fact goal holds in the symbolic final state.")
   (initial-state
    :initarg :initial-state
    :accessor plan-initial-state
    :initform nil)
   (final-state
    :initarg :final-state
    :accessor plan-final-state
    :initform nil
    :documentation "Symbolic fact list after applying plan steps.")
   (remaining
    :initarg :remaining
    :accessor plan-remaining
    :initform nil
    :documentation "Unachieved goals, if any.")
   (operators-used
    :initarg :operators-used
    :accessor plan-operators-used
    :initform nil)
   (meta
    :initarg :meta
    :accessor plan-meta
    :initform nil))
  (:documentation "Symbolic plan produced by MEA — not an execution record."))

(defun plan-p (object)
  "True when OBJECT is a PLAN."
  (typep object 'plan))

(defun normalize-planning-goals (goals)
  "Split GOALS into those Means-Ends Analysis can plan and the rest.
Returns (VALUES FACT-GOALS LABELS), each in the order of GOALS. A fact goal
is a list, a desired fact. Anything else, such as the symbol
AUDIO-SYSTEM-READY, is a label: it names a goal without saying which facts
make it true, so there is nothing to plan for it."
  (loop for goal in goals
        if (consp goal)
          collect goal into fact-goals
        else
          collect goal into labels
        finally (return (values fact-goals labels))))

(defun plan-for (state goals operators &key meta context-name)
  "Construct a PLAN to achieve GOALS from STATE using OPERATORS.
Records deliberative decisions into a fresh trace attached to plan meta.
Only the fact goals among GOALS are planned (NORMALIZE-PLANNING-GOALS),
and PLAN-SUCCESS speaks for those alone. The labels left out are recorded
under :IGNORED-GOALS in the plan meta and in the trace, so the plan itself
says which of the requested goals it did not consider."
  (multiple-value-bind (fact-goals labels) (normalize-planning-goals goals)
    (with-trace (:plan :context-name context-name)
      (when context-name
        (trace-record :context :name context-name))
      (when labels
        (trace-record :ignored-goals :goals labels))
      (multiple-value-bind (ok final steps left)
          (means-ends-analyze state fact-goals operators)
        (make-instance 'plan
                       :goals fact-goals
                       :steps steps
                       :success ok
                       :initial-state (copy-list state)
                       :final-state (copy-list final)
                       :remaining left
                       :operators-used
                       (remove-duplicates
                        (mapcar (lambda (s) (getf s :operator)) steps)
                        :test #'equal)
                       :meta (list* :trace *current-trace*
                                    :ignored-goals labels
                                    meta))))))

(defun plan-from-context (context &key goals operators)
  "Plan inside CONTEXT. GOALS default to the goals of CONTEXT; their labels
are recorded as PLAN-FOR records them.
OPERATORS default to CONTEXT-PLANNING-OPERATORS.
Stores operators and deliberative trace in plan meta."
  (let* ((ops (or operators (context-planning-operators context)))
         (plan (plan-for (context-all-facts context)
                         (or goals (goals-of context))
                         ops
                         :context-name (context-name context)
                         :meta (list :context (context-name context)
                                     :operators ops))))
    ;; Note on the plan the external actions it stands for; nothing is
    ;; invoked (core/external.lisp).
    (remember-plan-external-actions plan :context context :operators ops)))

(defun plan-length (plan)
  "Number of steps in PLAN."
  (length (plan-steps plan)))

(defun plan-cost (plan)
  "Sum of the step costs of PLAN. A step with no recorded cost counts 1."
  (loop for s in (plan-steps plan) sum (or (getf s :cost) 1)))
