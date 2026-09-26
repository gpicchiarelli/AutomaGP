;;;; interface/repl.lisp — SLIME/REPL API surface
;;;;
;;;; Phase 1–2 commands are live. Later phases signal NOT-YET-IMPLEMENTED.

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

(defun gp-context (&key name parent facts mode rules)
  "With no args: return the current context.
With :NAME (and optional keys): create/select a new current context."
  (cond
    ((or name parent facts mode rules)
     (setf *current-context*
           (create-context :name (or name 'unnamed)
                           :parent parent
                           :facts facts
                           :rules rules
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

(defun gp-rules ()
  "Rules visible in the current context (including parent inheritance)."
  (context-all-rules (ensure-current-context)))

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

(defun gp-add-rule (rule)
  "Register RULE (a RULE object) on the current context."
  (register-rule! (ensure-current-context) rule))

(defun gp-remove-rule (name)
  "Remove the rule named NAME from the current context."
  (remove-rule! (ensure-current-context) name))

(defun gp-query (pattern &key (infer t))
  "Query PATTERN in the current context.
INFER (default T) enables backward chaining over rules.
Returns a list of plists (:BINDINGS :FACT :SOURCE)."
  (query pattern (ensure-current-context) :infer infer))

(defun gp-infer (&key (assert nil) (limit *forward-chain-limit*))
  "Forward-chain rules over current facts.
Returns (VALUES ALL-FACTS NEW-FACTS).
If ASSERT is true, newly derived facts are added to the current context."
  (let* ((ctx (ensure-current-context))
         (facts (context-all-facts ctx))
         (rules (context-all-rules ctx)))
    (multiple-value-bind (all new)
        (forward-chain facts rules :limit limit)
      (when assert
        (dolist (f new)
          (setf (context-facts ctx) (add-fact! (context-facts ctx) f))))
      (values all new))))

(defun gp-mode (&optional mode)
  "Get or set the current context mode (:READ :PLAN :SIMULATE :EXECUTE).
PLAN/SIMULATE/EXECUTE still have no attached planner/executor (Phases 3–4)."
  (let ((ctx (ensure-current-context)))
    (if mode
        (progn
          (setf (context-mode ctx) (ensure-mode mode))
          (context-mode ctx))
        (context-mode ctx))))

(defun gp-register-action (action)
  "Register an ACTION object on the current context."
  (register-action! (ensure-current-context) action))

;;; Deferred Phase 3+ — honest signals

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
