;;;; interface/repl.lisp — SLIME/REPL API surface
;;;;
;;;; Phases 1–12 REPL. Optional web: (ql:quickload :automa-gp/web).

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

(defun gp-clear-memory (&key (working t) (knowledge t) (episodic t)
                          (procedural t))
  "Clear selected session memory stores."
  (when working (clear-working-memory))
  (when knowledge (clear-knowledge-memory))
  (when episodic (clear-episodic-memory))
  (when procedural (clear-procedural-memory))
  t)

(defun gp-reset ()
  "Reset the REPL session to a fresh empty context in READ mode.
Also clears working/episodic session memory, the deliberative trace buffer,
and the autonomy policy (back to the safe default on next use).
Knowledge and procedural memory are kept (use GP-CLEAR-MEMORY to drop them)."
  (setf *current-context* (create-context :name 'default :mode :read))
  (setf *current-plan* nil)
  (setf *last-execution* nil)
  (setf *deliberative-strategy* nil)
  (setf *last-reaction* nil)
  (setf *last-autonomy* nil)
  (setf *autonomy-policy* nil)
  (clear-trace-session)
  (clear-working-memory)
  (clear-episodic-memory)
  (setf *observed-before* nil)
  (setf *observation* nil)
  (when (fboundp '%stop-notice-watches)
    (funcall '%stop-notice-watches))
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
     (refresh-working-memory *current-context*)
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
    (refresh-working-memory ctx)
    fact))

(defun gp-remove-fact (fact)
  "Retract FACT from the current context (local facts only)."
  (let ((ctx (ensure-current-context)))
    (setf (context-facts ctx) (remove-fact! (context-facts ctx) fact))
    (refresh-working-memory ctx)
    (context-facts ctx)))

(defun gp-add-goal (goal)
  "Add GOAL to the current context."
  (let ((g (add-goal! (ensure-current-context) goal)))
    (refresh-working-memory)
    g))

(defun gp-remove-goal (goal)
  "Remove GOAL from the current context."
  (let ((g (remove-goal! (ensure-current-context) goal)))
    (refresh-working-memory)
    g))

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
          (setf (context-facts ctx) (add-fact! (context-facts ctx) f)))
        (refresh-working-memory ctx))
      (values all new))))

(defun gp-plan (&key goals operators (remember t) (archive t))
  "Build a symbolic plan. Does not mutate facts.
When ARCHIVE is true (default), a scored procedure is reused if its
stored steps still apply. An exact goal match comes first. A procedure
whose goals also include other facts is used after that, and those extra
goals are applied. Otherwise procedures that each achieve part of the
request are combined, those with no extra goals first. A procedure that
also achieves something else is used after that, and those extra goals
are applied. When those extra goals cannot be restored, the steps that
serve the request are kept and the others are left aside. If none apply,
the plan is built by Means-Ends Analysis.
When REMEMBER is true (default), records a plan episode in episodic memory."
  (let ((ctx (ensure-current-context)))
    (setf (context-mode ctx) :plan)
    (setf *current-plan*
          (plan-consulting-archive ctx :goals goals :operators operators
                                   :archive archive))
    (refresh-working-memory ctx)
    (when remember
      (record-plan-episode! *current-plan* :context-name (context-name ctx)))
    (cond
      ((plan-success *current-plan*)
       (when (eq (getf *observation* :reason) :plan-failed)
         (setf *observation* nil)))
      (*listen-on-plan-failure*
       (gp-listen :missing (plan-remaining *current-plan*)
                  :reason :plan-failed)))
    *current-plan*))

(defun gp-plan-open-goals ()
  "Plan the goals already in the context.
Does not change facts, does not simulate, and does not execute.
No fact-like goal is an error."
  (let ((goals (normalize-planning-goals (gp-goals))))
    (unless goals
      (error "There is no goal to plan."))
    (gp-plan :goals goals)))

(defun gp-last-plan ()
  "Return the last plan produced by GP-PLAN, or NIL."
  *current-plan*)

(defun gp-simulate (&key plan (remember t))
  "Simulate PLAN (default: last plan) without mutating the live context.
Sets mode to :SIMULATE. Returns an EXECUTION-RESULT.
Step failures signal GP-ERROR with restarts; *DELIBERATIVE-STRATEGY* may
auto-invoke SKIP/RETRY/ABORT/ASK. Symbolic effects only — no adapters.
When the plan recorded an external action that no longer matches, this
signals before any simulated step and leaves the context mode as it was.
When the facts no longer support an action that would be handed to an
adapter, this signals the same way. When REMEMBER is true (default),
records an episode."
  (let* ((ctx (ensure-current-context))
         (p (or plan *current-plan*)))
    (unless (plan-p p)
      (error "GP-SIMULATE requires a plan; call GP-PLAN first or pass :PLAN."))
    (setf *last-execution*
          (call-with-execution-mode
           ctx :simulate
           (lambda ()
             (simulate-plan p :context ctx
                            :operators (context-planning-operators ctx)))))
    (refresh-working-memory ctx)
    (when remember
      (record-execution-episode! *last-execution*))
    *last-execution*))

(defun gp-run (&key plan (confirm nil confirm-p) (remember t)
                 (adapters nil adapters-p))
  "Execute PLAN (default: last plan) against live context facts.
Sets mode to :EXECUTE. Returns an EXECUTION-RESULT.
Step failures signal GP-ERROR with restarts (RETRY SKIP ABORT-EXECUTION
USE-VALUE USE-ALTERNATIVE ASK-USER). Irreversible ops also offer CONFIRM.
Symbolic effects always apply. When ADAPTERS is true, operators with
:EXTERNAL meta may invoke OS adapters (Phase 8). Default: adapters off.
When REMEMBER is true (default), records an episode.
A plan reused from the archive (:FROM-PROCEDURE) updates that procedure's
score from this live result. GP-SIMULATE does not.
A refusal signals before any fact changes and leaves the context mode
as it was."
  (let* ((ctx (ensure-current-context))
         (p (or plan *current-plan*)))
    (unless (plan-p p)
      (error "GP-RUN requires a plan; call GP-PLAN first or pass :PLAN."))
    (setf *last-execution*
          (call-with-execution-mode
           ctx :execute
           (lambda ()
             (execute-plan! ctx p
                            :confirm (if confirm-p confirm nil)
                            :adapters (if adapters-p adapters *invoke-adapters*)))))
    (refresh-working-memory ctx)
    (when remember
      (record-execution-episode! *last-execution*))
    (record-procedure-outcome!
     p
     :success (and (execution-success *last-execution*)
                   (null (differences (context-all-facts ctx) (plan-goals p)))))
    *last-execution*))

(defun gp-adapters (&optional (enabled nil enabled-p))
  "Get or set session *INVOKE-ADAPTERS* (default NIL = symbolic EXECUTE)."
  (if enabled-p
      (setf *invoke-adapters* (and enabled t))
      *invoke-adapters*))

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
          (refresh-working-memory ctx)
          (context-mode ctx))
        (context-mode ctx))))

(defun gp-register-action (action)
  "Register an ACTION object on the current context."
  (register-action! (ensure-current-context) action))

;;; Phase 6 — explanation from recorded deliberative traces

(defun gp-listen (&key missing (reason :manual))
  "Open a listening session on the current facts.
MISSING records the goals still open, usually PLAN-REMAINING after a
failed plan. A later GP-INDUCE-RULE consumes this before-state."
  (setf *observed-before* (copy-list (gp-facts)))
  (setf *observation*
        (list :active t
              :before *observed-before*
              :missing (copy-list missing)
              :reason reason))
  *observation*)

(defun gp-note-state ()
  "Remember the current facts as the before-state of a manual action."
  (gp-listen :reason :manual))

(defun gp-learn-action (name &key (before nil before-p) (after nil after-p)
                               (register t))
  "Induce a ground operator named NAME and, by default, register it.
BEFORE defaults to the list from GP-NOTE-STATE. AFTER defaults to the
current facts. Patterns stay ground. A later call with the same name
merges when every constant is already the same; a different symbol or
number is refused and does not become a variable. An operator that
already uses variables is left unchanged. Clears the session only after
a successful induction."
  (let* ((before (if before-p
                     before
                     (or *observed-before*
                         (error "No state noted. Call gp-note-state before the manual change."))))
         (after (if after-p after (gp-facts)))
         (fresh (induce-operator name before after))
         (operator
           (if (not register)
               fresh
               (let ((existing (find-operator (ensure-current-context) name)))
                 (cond
                   ((null existing)
                    (gp-add-operator
                     (make-operator :name (operator-name fresh)
                                    :preconditions (operator-preconditions fresh)
                                    :add-list (operator-add-list fresh)
                                    :delete-list (operator-delete-list fresh)
                                    :cost (operator-cost fresh)
                                    :meta (list* :examples 1 (operator-meta fresh)))))
                   ((not (getf (operator-meta existing) :induced))
                    (error "Operator ~A already exists and was not induced." name))
                   ((%operator-uses-variables-p existing)
                    (error "Operator ~A already uses variables." name))
                   (t
                    (let ((merged (merge-induced-operators existing fresh :lift nil)))
                      (unless merged
                        (error "The new example does not fit operator ~A." name))
                      (gp-add-operator merged))))))))
    (setf *observed-before* nil)
    (setf *observation* nil)
    operator))

(defun gp-induce-rule (name &key (before nil before-p) (after nil after-p)
                             (register t))
  "Induce a generalized operator from the listening session and register it.
The object symbol shared by one change becomes ?X0. Numbers stay ground.
A later call with the same name merges the new example when it fits: an
existing variable stays, a repeated symbol that is renamed becomes the
next variable, and a differing number or a one-off value is refused.
The operator already registered is left unchanged when the example does
not fit. Clears the session only after a successful induction."
  (let* ((before (if before-p
                     before
                     (or *observed-before*
                         (error "No state noted. Call gp-listen before the manual change."))))
         (after (if after-p after (gp-facts)))
         (fresh (induce-operator name before after :generalize t))
         (operator
           (if (not register)
               fresh
               (let ((existing (find-operator (ensure-current-context) name)))
                 (cond
                   ((null existing)
                    (gp-add-operator
                     (make-operator :name (operator-name fresh)
                                    :preconditions (operator-preconditions fresh)
                                    :add-list (operator-add-list fresh)
                                    :delete-list (operator-delete-list fresh)
                                    :cost (operator-cost fresh)
                                    :meta (list* :examples 1 (operator-meta fresh)))))
                   ((not (getf (operator-meta existing) :induced))
                    (error "Operator ~A already exists and was not induced." name))
                   (t
                    (let ((merged (merge-induced-operators existing fresh)))
                      (unless merged
                        (error "The new example does not fit operator ~A." name))
                      (gp-add-operator merged))))))))
    (setf *observed-before* nil)
    (setf *observation* nil)
    operator))

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

;;; Phase 7 — memory & persistence

(defun gp-working ()
  "Refresh and return the session working-memory snapshot."
  (refresh-working-memory (ensure-current-context)))

(defun gp-knowledge (&key name facts rules)
  "With no args: return (ensuring) session knowledge memory.
With keys: replace/create knowledge memory and return it."
  (if (or name facts rules)
      (setf *knowledge-memory*
            (make-knowledge-memory :name (or name 'default)
                                   :facts facts
                                   :rules rules))
      (ensure-knowledge-memory)))

(defun gp-knowledge-add (item)
  "Add FACT (list) or RULE object to session knowledge memory."
  (cond
    ((rule-p item) (knowledge-add-rule! item))
    ((consp item) (knowledge-add-fact! item))
    (t (error "GP-KNOWLEDGE-ADD expects a fact list or RULE, got ~S" item))))

(defun gp-knowledge-query (pattern &key (infer nil))
  "Query PATTERN against session knowledge memory."
  (knowledge-query pattern :infer infer))

(defun gp-knowledge-merge ()
  "Merge session knowledge into the current context."
  (knowledge-merge-into-context! (ensure-current-context))
  (refresh-working-memory)
  (ensure-current-context))

(defun gp-episodes (&key kind success context-name)
  "List session episodes (optional filters)."
  (find-episodes :kind kind :success success :context-name context-name))

(defun gp-last-episode ()
  "Most recent episode, or NIL."
  (when (episodic-memory-p *episodic-memory*)
    (last-episode *episodic-memory*)))

(defun gp-remember-procedure (&key plan name)
  "Store a reusable procedure from PLAN (default: last successful plan).
Same name accumulates successes. Autosaves the procedure archive when
*PROCEDURE-ARCHIVE-AUTOSAVE* is true (default)."
  (let ((p (or plan *current-plan*)))
    (unless (plan-p p)
      (error "GP-REMEMBER-PROCEDURE requires a plan"))
    (remember-procedure-from-plan! p :name name)))

(defun gp-procedures (&optional goals)
  "List stored procedures, or those matching GOALS when supplied."
  (if goals
      (procedures-for-goals goals)
      (copy-list (procedural-memory-procedures (ensure-procedural-memory)))))

(defun gp-find-procedure (name)
  "Find a stored procedure by NAME."
  (find-procedure name))

(defun gp-archive (&optional goals)
  "Archived procedures, highest score first. GOALS filters to an exact goal set."
  (rank-procedures (if goals
                       (procedures-for-goals goals)
                       (procedural-memory-procedures (ensure-procedural-memory)))))

(defun gp-archive-best (goals)
  "Highest-scoring archived procedure for GOALS, or NIL."
  (archive-best goals))

(defun gp-archive-save (&optional (path *procedure-archive-path*))
  "Write the procedure archive to PATH (default ~/.automa-gp/procedure-archive.agp)."
  (save-procedure-archive path))

(defun gp-archive-load (&optional (path *procedure-archive-path*))
  "Load the procedure archive from PATH into session procedural memory."
  (load-procedure-archive path))

(defun gp-use-procedure (&key name goals (unchecked nil))
  "Build a PLAN from the archive without Means-Ends Analysis.
NAME selects one procedure. Without NAME, use an archived procedure for
GOALS (default: goals on the current context) whose steps still apply.
An exact goal match comes first; a procedure that also achieves other
goals is used after that. Otherwise procedures that each achieve part of
the request are combined, those with no extra goals first.
The plan is a replay on the current facts and carries a deliberative trace.
When the stored steps do not apply, no plan is built.
UNCHECKED T rebuilds the named procedure anyway, without that check.
Records the external actions that replay would run. Does not invoke them.
Sets *CURRENT-PLAN*."
  (let* ((ctx (ensure-current-context))
         (goal-set (or goals (goals-of ctx)))
         (proc (cond
                 (name (or (find-procedure name)
                           (error "No archived procedure named ~S." name)))
                 (unchecked (or (archive-best goal-set)
                                (error "No archived procedure matches goals ~S."
                                       goal-set)))
                 (t nil)))
         (plan (if unchecked
                   (procedure->plan proc)
                   (or (if name
                           (plan-from-procedure
                            proc
                            (context-all-facts ctx)
                            (context-planning-operators ctx)
                            :context-name (context-name ctx))
                           (progn
                             (unless (%procedures-for-planning
                                      (normalize-planning-goals goal-set))
                               (error "No archived procedure matches goals ~S."
                                      goal-set))
                             (plan-from-ranked-procedures
                              ctx
                              (normalize-planning-goals goal-set)
                              (context-planning-operators ctx))))
                       (error "Procedure ~A does not apply to the current state; no plan was built."
                              (if name (procedure-name proc) goal-set))))))
    (remember-plan-external-actions plan :context ctx)
    (setf (context-mode ctx) :plan)
    (setf *current-plan* plan)
    plan))

(defun gp-score-procedure (name &key (success t))
  "Score a replay of the archived procedure NAME. :SUCCESS NIL records a failure."
  (score-procedure! name :success success))

(defun gp-save (path &key (context t) (knowledge t) (episodic t)
                       (procedural t) meta)
  "Save a snapshot bundle to PATH. Boolean keys select sections.
CONTEXT T means the current context."
  (save-snapshot path
                 :context (when context (ensure-current-context))
                 :knowledge (when knowledge
                              (and (knowledge-memory-p *knowledge-memory*)
                                   *knowledge-memory*))
                 :episodic (when episodic
                             (and (episodic-memory-p *episodic-memory*)
                                  *episodic-memory*))
                 :procedural (when procedural
                               (and (procedural-memory-p *procedural-memory*)
                                    *procedural-memory*))
                 :meta meta))

(defun gp-load (path &key (apply t))
  "Load a snapshot from PATH. When APPLY is true (default), install into session."
  (let ((bundle (load-snapshot path)))
    (when apply
      (apply-snapshot! bundle))
    bundle))

(defun gp-save-context (path)
  "Persist only the current context to PATH."
  (persist-context (ensure-current-context) path))

(defun gp-load-context (path &key (set-current t))
  "Restore a context from PATH. When SET-CURRENT, make it the session context."
  (let ((ctx (restore-context path)))
    (when set-current
      (setf *current-context* ctx)
      (refresh-working-memory ctx))
    ctx))

;;; Phase 10 — context-bound events

(defun gp-emit (form &key (react nil) (plan nil) (infer nil)
                       (assert-fact t) (remember t) meta)
  "Post event FORM ((TYPE . DATA), e.g. (FILE-CREATED \"doc.pdf\")) on the
current context. By default only records the event (and asserts it as a fact).
When :REACT is true, process pending events (reactions → facts/goals).
When :PLAN is also true, build a plan for resulting goals.
Returns the GP-EVENT (and leaves *LAST-REACTION* when reacting)."
  (let* ((ctx (ensure-current-context))
         (event (emit-event! ctx form :assert-fact assert-fact :meta meta)))
    (when react
      (gp-react :plan plan :infer infer :remember remember))
    (refresh-working-memory ctx)
    event))

(defun gp-events (&key status)
  "List events on the current context (oldest first). Optional :STATUS filter."
  (events-of (ensure-current-context) :status status))

(defun gp-react (&key (plan nil) (infer nil) (remember t))
  "Process pending events: reactions assert facts / add goals, optional plan.
Returns the reaction summary plist (*LAST-REACTION*). Goal-directed
GP-PLAN still works independently of events."
  (let* ((ctx (ensure-current-context))
         (summary (process-pending-events! ctx :plan plan :infer infer))
         (plan-obj (getf summary :plan)))
    (when (and remember (plan-p plan-obj))
      (record-plan-episode! plan-obj :context-name (context-name ctx)))
    (refresh-working-memory ctx)
    summary))

(defun gp-add-reaction (reaction)
  "Register an EVENT-REACTION on the current context."
  (register-event-reaction! (ensure-current-context) reaction))

(defun gp-remove-reaction (name)
  "Remove event reaction named NAME from the current context."
  (remove-event-reaction! (ensure-current-context) name))

(defun gp-reactions ()
  "Event reactions visible on the current context (incl. parents)."
  (context-all-event-reactions (ensure-current-context)))

(defun gp-last-reaction ()
  "Summary plist from the last GP-REACT / PROCESS-PENDING-EVENTS!, or NIL."
  *last-reaction*)

;;; Phase 12 — controlled autonomy

(defun gp-policy (&key (authority nil authority-p)
                    (max-steps nil max-steps-p)
                    (adapters nil adapters-p)
                    (auto-confirm nil auto-confirm-p)
                    (confirm-fn nil confirm-fn-p)
                    (react-events t react-events-p)
                    (infer nil infer-p)
                    (learn t learn-p)
                    (replan-on-discrepancy t replan-p)
                    (remember-procedure nil remember-p)
                    (prefer-archive t prefer-archive-p)
                    (set t))
  "Get or install the session *AUTONOMY-POLICY*.
With no policy keys: return current policy (or a fresh default).
With keys: build a policy; when SET is true (default), install it."
  (if (or authority-p max-steps-p adapters-p auto-confirm-p confirm-fn-p
          react-events-p infer-p learn-p replan-p remember-p
          prefer-archive-p)
      (let* ((base (ensure-autonomy-policy))
             (p (make-autonomy-policy
                 :authority (if authority-p authority (policy-authority base))
                 :max-steps (if max-steps-p max-steps (policy-max-steps base))
                 :adapters (if adapters-p adapters (policy-adapters base))
                 :auto-confirm (if auto-confirm-p auto-confirm
                                   (policy-auto-confirm base))
                 :confirm-fn (if confirm-fn-p confirm-fn
                                 (policy-confirm-fn base))
                 :react-events (if react-events-p react-events
                                   (policy-react-events base))
                 :infer (if infer-p infer (policy-infer base))
                 :learn (if learn-p learn (policy-learn base))
                 :replan-on-discrepancy
                 (if replan-p replan-on-discrepancy
                     (policy-replan-on-discrepancy base))
                 :remember-procedure
                 (if remember-p remember-procedure
                     (policy-remember-procedure base))
                 :prefer-archive
                 (if prefer-archive-p prefer-archive
                     (policy-prefer-archive base)))))
        (when set (setf *autonomy-policy* p))
        p)
      (ensure-autonomy-policy)))

(defun gp-autonomous-step (&key policy (remember t))
  "One controlled autonomy cycle (PROMPT §28). Respects policy authority
(:READ | :SIMULATE | :EXECUTE). Default policy authority is :SIMULATE."
  (ensure-current-context)
  (autonomous-step :policy (or policy (ensure-autonomy-policy))
                   :remember remember))

(defun gp-autonomous-loop (&key policy max-steps (remember t))
  "Repeat GP-AUTONOMOUS-STEP until done, halted, or max steps."
  (ensure-current-context)
  (autonomous-loop :policy (or policy (ensure-autonomy-policy))
                   :max-steps max-steps
                   :remember remember))

(defun gp-last-autonomy ()
  "Summary plist from the last autonomous step/loop, or NIL."
  *last-autonomy*)
