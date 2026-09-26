;;;; interface/repl.lisp — SLIME/REPL API surface
;;;;
;;;; Phases 1–6 commands are live. Memory/persistence remain deferred (Phase 7).

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
  (setf *current-plan* nil)
  (setf *last-execution* nil)
  (setf *deliberative-strategy* nil)
  (clear-trace-session)
  *current-context*)

(defun gp-context (&key name parent facts mode rules operators)
  "With no args: return the current context.
With :NAME (and optional keys): create/select a new current context."
  (cond
    ((or name parent facts mode rules operators)
     (setf *current-context*
           (create-context :name (or name 'unnamed)
                           :parent parent
                           :facts facts
                           :rules rules
                           :operators operators
                           :mode (or mode :read)))
     *current-context*)
    (t
     (ensure-current-context))))

(defun gp-state (&key (kind :current))
  "Return a STATE snapshot of the current context (default kind :CURRENT)."
  (state-from-context (ensure-current-context) :kind kind))

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

(defun gp-operators ()
  "Planning operators for the current context (explicit, else lifted actions)."
  (context-planning-operators (ensure-current-context)))

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

(defun gp-add-operator (operator)
  "Register OPERATOR on the current context."
  (register-operator! (ensure-current-context) operator))

(defun gp-remove-operator (name)
  "Remove operator named NAME from the current context."
  (remove-operator! (ensure-current-context) name))

(defun gp-query (pattern &key (infer t))
  "Query PATTERN in the current context."
  (query pattern (ensure-current-context) :infer infer))

(defun gp-infer (&key (assert nil) (limit *forward-chain-limit*))
  "Forward-chain rules over current facts."
  (let* ((ctx (ensure-current-context))
         (facts (context-all-facts ctx))
         (rules (context-all-rules ctx)))
    (multiple-value-bind (all new)
        (forward-chain facts rules :limit limit)
      (when assert
        (dolist (f new)
          (setf (context-facts ctx) (add-fact! (context-facts ctx) f))))
      (values all new))))

(defun gp-plan (&key goals operators)
  "Build a symbolic plan via Means-Ends Analysis. Does not mutate facts."
  (let ((ctx (ensure-current-context)))
    (setf (context-mode ctx) :plan)
    (setf *current-plan*
          (plan-from-context ctx :goals goals :operators operators))
    *current-plan*))

(defun gp-last-plan ()
  "Return the last plan produced by GP-PLAN, or NIL."
  *current-plan*)

(defun gp-simulate (&key plan)
  "Simulate PLAN (default: last plan) without mutating the live context.
Sets mode to :SIMULATE. Returns an EXECUTION-RESULT.
Step failures signal GP-ERROR with restarts; *DELIBERATIVE-STRATEGY* may
auto-invoke SKIP/RETRY/ABORT/ASK. Symbolic effects only — no adapters."
  (let* ((ctx (ensure-current-context))
         (p (or plan *current-plan*)))
    (unless (plan-p p)
      (error "GP-SIMULATE requires a plan; call GP-PLAN first or pass :PLAN."))
    (setf (context-mode ctx) :simulate)
    (setf *last-execution*
          (simulate-plan p :context ctx
                         :operators (context-planning-operators ctx)))
    *last-execution*))

(defun gp-run (&key plan (confirm nil confirm-p))
  "Execute PLAN (default: last plan) against live context facts.
Sets mode to :EXECUTE. Returns an EXECUTION-RESULT.
Step failures signal GP-ERROR with restarts (RETRY SKIP ABORT-EXECUTION
USE-VALUE USE-ALTERNATIVE ASK-USER). Irreversible ops also offer CONFIRM.
Mutates context facts symbolically only — no adapters."
  (let* ((ctx (ensure-current-context))
         (p (or plan *current-plan*)))
    (unless (plan-p p)
      (error "GP-RUN requires a plan; call GP-PLAN first or pass :PLAN."))
    (setf (context-mode ctx) :execute)
    (setf *last-execution*
          (execute-plan! ctx p :confirm (if confirm-p confirm nil)))
    *last-execution*))

(defun gp-last-execution ()
  "Return the last EXECUTION-RESULT from GP-SIMULATE or GP-RUN."
  *last-execution*)

(defun gp-failure-strategy (&optional policy &key (retry-limit 3))
  "Get or set the session *DELIBERATIVE-STRATEGY*.
With no args: return current strategy (or NIL).
With POLICY (:SIGNAL :SKIP :RETRY :ABORT :ASK): install a fresh strategy."
  (if policy
      (setf *deliberative-strategy*
            (make-strategy :policy policy :retry-limit retry-limit))
      *deliberative-strategy*))

(defun gp-mode (&optional mode)
  "Get or set the current context mode (:READ :PLAN :SIMULATE :EXECUTE)."
  (let ((ctx (ensure-current-context)))
    (if mode
        (progn
          (setf (context-mode ctx) (ensure-mode mode))
          (context-mode ctx))
        (context-mode ctx))))

(defun gp-register-action (action)
  "Register an ACTION object on the current context."
  (register-action! (ensure-current-context) action))

;;; Phase 6 — explanation from recorded deliberative traces

(defun gp-explain (&optional (topic :last) &key (stream t))
  "Print (and return) an explanation derived from a recorded deliberative trace.
TOPIC may be :LAST (default), :PLAN, :EXECUTION, :HISTORY, a PLAN,
an EXECUTION-RESULT, or a DELIBERATIVE-TRACE.
Does not invent decisions — only formats entries recorded during
plan / MEA / simulate / execute. Returns (VALUES TEXT TRACE)."
  (explain-trace topic :stream stream))

(defun gp-last-trace ()
  "Return the most recently finished deliberative trace, or NIL."
  (last-trace))

(defun gp-trace-history ()
  "Return newest-first session trace history (in-memory buffer only)."
  (copy-list *trace-history*))
