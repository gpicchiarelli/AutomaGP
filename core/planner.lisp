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
    :documentation "True if all goals were achieved in the symbolic state.")
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
  (typep object 'plan))

(defun normalize-planning-goals (goals)
  "Keep only fact-like goals (lists). Symbol goals are ignored for MEA
(they are labels until given a desired-fact form)."
  (remove-if-not #'consp (copy-list goals)))

(defun plan-for (state goals operators &key meta context-name)
  "Construct a PLAN to achieve GOALS from STATE using OPERATORS.
Records deliberative decisions into a fresh trace attached to plan meta."
  (let* ((g (normalize-planning-goals goals))
         (ops (copy-list operators))
         (ctx-name context-name))
    (with-trace (:plan :context-name ctx-name)
      (when ctx-name
        (trace-record :context :name ctx-name))
      (multiple-value-bind (ok final steps left)
          (means-ends-analyze state g ops)
        (let ((plan (make-instance 'plan
                                   :goals g
                                   :steps steps
                                   :success ok
                                   :initial-state (copy-list state)
                                   :final-state (copy-list (or final state))
                                   :remaining left
                                   :operators-used
                                   (remove-duplicates
                                    (mapcar (lambda (s) (getf s :operator)) steps)
                                    :test #'equal)
                                   :meta (list* :trace *current-trace*
                                                meta))))
          plan)))))

(defun plan-from-context (context &key goals operators)
  "Plan inside CONTEXT. GOALS default to fact-like context goals.
OPERATORS default to CONTEXT-PLANNING-OPERATORS.
Stores operators and deliberative trace in plan meta."
  (let* ((state (context-all-facts context))
         (g (or goals (normalize-planning-goals (goals-of context))))
         (ops (or operators (context-planning-operators context))))
    (plan-for state g ops
              :context-name (context-name context)
              :meta (list :context (context-name context)
                          :operators ops))))

(defun plan-length (plan)
  (length (plan-steps plan)))

(defun plan-cost (plan)
  (loop for s in (plan-steps plan) sum (or (getf s :cost) 1)))

(defvar *current-plan* nil
  "Last plan produced by GP-PLAN in this session.")
