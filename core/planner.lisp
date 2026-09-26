;;;; core/planner.lisp — plan construction API (Phase 3)
;;;;
;;;; Builds symbolic plans via MEA. Does not execute or simulate externally
;;;; (Phase 4). Mode :PLAN is advisory for the REPL session.

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

(defun plan-for (state goals operators &key meta)
  "Construct a PLAN to achieve GOALS from STATE using OPERATORS."
  (let* ((g (normalize-planning-goals goals))
         (ops (copy-list operators)))
    (multiple-value-bind (ok final steps left)
        (means-ends-analyze state g ops)
      (make-instance 'plan
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
                     :meta meta))))

(defun plan-from-context (context &key goals operators)
  "Plan inside CONTEXT. GOALS default to fact-like context goals.
OPERATORS default to CONTEXT-PLANNING-OPERATORS.
Stores operators in plan meta for later simulate/execute lookup."
  (let* ((state (context-all-facts context))
         (g (or goals (normalize-planning-goals (goals-of context))))
         (ops (or operators (context-planning-operators context))))
    (plan-for state g ops
              :meta (list :context (context-name context)
                          :operators ops))))

(defun plan-length (plan)
  (length (plan-steps plan)))

(defun plan-cost (plan)
  (loop for s in (plan-steps plan) sum (or (getf s :cost) 1)))

(defvar *current-plan* nil
  "Last plan produced by GP-PLAN in this session.")
