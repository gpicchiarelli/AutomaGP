;;;; interface/repl.lisp — SLIME/REPL API surface (Phase 1)
;;;;
;;;; First official interface. Commands that belong to later phases signal
;;;; NOT-YET-IMPLEMENTED rather than faking behavior.

(in-package #:automa-gp)

(defvar *current-context* nil
  "Session current context for REPL helpers.")

(define-condition not-yet-implemented-error (error)
  ((feature :initarg :feature :reader not-yet-implemented-feature)
   (phase :initarg :phase :reader not-yet-implemented-phase :initform nil))
  (:report (lambda (c stream)
             (format stream "AUTOMA GP: ~A is not yet implemented~@[ (Phase ~A)~]."
                     (not-yet-implemented-feature c)
                     (not-yet-implemented-phase c)))))

(defun not-yet-implemented (feature &optional phase)
  (error 'not-yet-implemented-error :feature feature :phase phase))

(defun ensure-current-context ()
  (unless (context-p *current-context*)
    (setf *current-context* (create-context :name 'default)))
  *current-context*)

(defun gp-reset ()
  "Reset the REPL session to a fresh empty context in READ mode."
  (setf *current-context* (create-context :name 'default :mode :read))
  *current-context*)

(defun gp-context (&key name parent facts mode)
  "With no args: return the current context.
With :NAME (and optional keys): create/select a new current context."
  (cond
    ((or name parent facts mode)
     (setf *current-context*
           (create-context :name (or name 'unnamed)
                           :parent parent
                           :facts facts
                           :mode (or mode :read)))
     *current-context*)
    (t
     (ensure-current-context))))

(defun gp-state ()
  "Return a STATE snapshot of the current context."
  (state-from-context (ensure-current-context)))

(defun gp-facts ()
  "Facts visible in the current context (including parent inheritance)."
  (context-all-facts (ensure-current-context)))

(defun gp-goals ()
  "Goals on the current context."
  (goals-of (ensure-current-context)))

(defun gp-actions ()
  "Actions registered on the current context."
  (actions-of (ensure-current-context)))

(defun gp-add-fact (fact)
  "Assert FACT in the current context."
  (let ((ctx (ensure-current-context)))
    (setf (context-facts ctx) (add-fact! (context-facts ctx) fact))
    fact))

(defun gp-remove-fact (fact)
  "Retract FACT from the current context (local facts only)."
  (let ((ctx (ensure-current-context)))
    (setf (context-facts ctx) (remove-fact! (context-facts ctx) fact))
    (context-facts ctx)))

(defun gp-add-goal (goal)
  "Add GOAL to the current context."
  (add-goal! (ensure-current-context) goal))

(defun gp-remove-goal (goal)
  "Remove GOAL from the current context."
  (remove-goal! (ensure-current-context) goal))

(defun gp-mode (&optional mode)
  "Get or set the current context mode (:READ :PLAN :SIMULATE :EXECUTE).
Phase 1 only stores the mode; PLAN/SIMULATE/EXECUTE have no attached engine."
  (let ((ctx (ensure-current-context)))
    (if mode
        (progn
          (setf (context-mode ctx) (ensure-mode mode))
          (context-mode ctx))
        (context-mode ctx))))

(defun gp-register-action (action)
  "Register an ACTION object on the current context."
  (register-action! (ensure-current-context) action))

;;; Deferred Phase 2+ — honest signals

(defun gp-rules ()
  "Not yet implemented (Phase 2)."
  (not-yet-implemented 'gp-rules 2))

(defun gp-query (&rest args)
  "Not yet implemented (Phase 2). Use CONTEXT-QUERY / FIND-FACTS for Phase-1 patterns."
  (declare (ignore args))
  (not-yet-implemented 'gp-query 2))

(defun gp-plan ()
  "Not yet implemented (Phase 3)."
  (not-yet-implemented 'gp-plan 3))

(defun gp-explain (&rest args)
  "Not yet implemented (Phase 6)."
  (declare (ignore args))
  (not-yet-implemented 'gp-explain 6))

(defun gp-run (&rest args)
  "Not yet implemented (Phase 4)."
  (declare (ignore args))
  (not-yet-implemented 'gp-run 4))

(defun gp-simulate (&rest args)
  "Not yet implemented (Phase 4). Mode :SIMULATE may be set via GP-MODE."
  (declare (ignore args))
  (not-yet-implemented 'gp-simulate 4))
