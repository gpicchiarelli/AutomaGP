;;;; core/goals.lisp — goal registry on a context (Phase 1)

(in-package #:automa-gp)

(defun add-goal! (context goal)
  "Assert GOAL on CONTEXT (idempotent). GOAL may be a symbol or list."
  (unless (find goal (context-goals context) :test #'equal)
    (setf (context-goals context)
          (append (context-goals context) (list goal))))
  (context-goals context))

(defun remove-goal! (context goal)
  "Retract GOAL from CONTEXT."
  (setf (context-goals context)
        (remove goal (context-goals context) :test #'equal))
  (context-goals context))

(defun goals-of (context)
  "Goals listed on CONTEXT."
  (context-goals context))

(defun goal-active-p (context goal)
  "True if GOAL is among CONTEXT's goals."
  (find goal (context-goals context) :test #'equal))
