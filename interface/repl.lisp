;;;; interface/repl.lisp — the session commands (GP-*)
;;;;
;;;; Each command works on the session: the current context, the last plan
;;;; and execution, the listening session, the failure strategy and the
;;;; autonomy policy. A command checks its arguments and refuses before it
;;;; changes anything. One function installs a session context and one
;;;; installs a plan, so the plan, the execution, the listening session and
;;;; working memory change together whichever command is used.
;;;; Optional web console: (ql:quickload :automa-gp/web).

(in-package #:automa-gp)

;;; ---------------------------------------------------------------------------
;;; The session lock
;;; ---------------------------------------------------------------------------

(defvar *session-lock* (sb-thread:make-mutex :name "automa-gp-session")
  "The lock of the one session this image holds.
The commands of this file do not take it: a REPL has one thread. Whatever
runs other threads against the session takes it around each unit of work:
the web layer holds it while a request is answered and its response is
written, and every notice and every watch thread holds it while a noticed
form enters a context. A thread that holds it may take it again.")

(defmacro with-session-lock ((&key timeout) &body body)
  "Run BODY holding *SESSION-LOCK*, which the calling thread may already hold.
With TIMEOUT, in seconds, a turn that does not come in time skips BODY and
the form returns NIL: the caller looks at its stop flag and tries again."
  `(sb-thread:with-recursive-lock (*session-lock*
                                   ,@(when timeout `(:timeout ,timeout)))
     ,@body))

;;; ---------------------------------------------------------------------------
;;; Conditions
;;; ---------------------------------------------------------------------------

(define-condition not-yet-implemented-error (error)
  ((feature :initarg :feature :reader not-yet-implemented-feature)
   (phase :initarg :phase :reader not-yet-implemented-phase :initform nil))
  (:report (lambda (c stream)
             (format stream "AUTOMA GP: ~A is not yet implemented~@[ (Phase ~A)~]."
                     (not-yet-implemented-feature c)
                     (not-yet-implemented-phase c))))
  (:documentation "FEATURE belongs to a later PHASE and does not exist yet."))

(defun not-yet-implemented (feature &optional phase)
  "Signal NOT-YET-IMPLEMENTED-ERROR for FEATURE, due in roadmap PHASE."
  (error 'not-yet-implemented-error :feature feature :phase phase))

(define-condition command-refused (simple-error)
  ((reason :initarg :reason :reader command-refused-reason))
  (:documentation "A session command was refused before it changed anything.
The report is the sentence shown to the user. REASON is a keyword:
:CONTEXT-NAME-REQUIRED  GP-CONTEXT was given keys but no :NAME
:GOAL-HOLDS             the goal to add already holds
:NO-OPEN-GOAL           there is no fact-like goal left to plan
:NO-PLAN                there is no plan to simulate, run or remember
:NO-LISTENING-SESSION   nothing was noted, on this context, to learn from
:UNSUCCESSFUL-PLAN      the plan did not succeed
:NO-PROCEDURE           no archived procedure answers the goals
:PROCEDURE-DOES-NOT-APPLY  the archived steps do not apply to the facts
:NO-WORK                an autonomy cycle would have nothing to do"))

(defun %refuse (reason control &rest arguments)
  "Signal COMMAND-REFUSED for REASON with the sentence CONTROL formats."
  (error 'command-refused :reason reason
                          :format-control control
                          :format-arguments arguments))

(defun %check-elements (items type)
  "ITEMS when it is a list whose elements are all of TYPE. Otherwise signal
a TYPE-ERROR for ITEMS itself or for the first element that is not."
  (check-type items list)
  (dolist (item items items)
    (unless (typep item type)
      (error 'type-error :datum item :expected-type type))))

;;; ---------------------------------------------------------------------------
;;; The session: context, listening, plan
;;; ---------------------------------------------------------------------------

(defun ensure-current-context ()
  "The session context. Creates an empty one named DEFAULT when there is none."
  (unless (context-p *current-context*)
    (setf *current-context* (create-context :name 'default)))
  *current-context*)

(defun %end-listening ()
  "Close the listening session: the observation and its before-state."
  (setf *observation* nil
        *observed-before* nil))

(defun %end-plan-failed-listening ()
  "Close a listening session opened after a failed plan.
The before-state goes with it, so induce cannot reuse a stale snapshot. A
manual session is left alone."
  (when (eq (getf *observation* :reason) :plan-failed)
    (%end-listening)))

(defun %install-session-context (context)
  "Make CONTEXT the session context and return it.
The last plan, the last execution and the listening session were made in
the context before it. They are dropped, so no later command runs a plan
or learns from a before-state that belongs to another context."
  (setf *current-context* context
        *current-plan* nil
        *last-execution* nil)
  (%end-listening)
  (refresh-working-memory context)
  context)

(defun %install-plan (context plan &key (remember t))
  "Make PLAN the session plan of CONTEXT and return it.
Sets the mode to :PLAN, refreshes working memory and, when REMEMBER is
true, records a plan episode. A successful plan ends a listening session
that a failed plan opened. A failed plan opens one on its remaining goals
while *LISTEN-ON-PLAN-FAILURE* is true."
  (setf (context-mode context) :plan
        *current-plan* plan)
  (refresh-working-memory context)
  (when remember
    (record-plan-episode! plan :context-name (context-name context)))
  (cond
    ((plan-success plan)
     (%end-plan-failed-listening))
    (*listen-on-plan-failure*
     (gp-listen :missing (plan-remaining plan) :reason :plan-failed)))
  plan)

(defun %successful-plan (plan command doing)
  "PLAN, or the last session plan when PLAN is NIL, when it succeeded.
Refuses when there is no plan or the plan failed. COMMAND, the name of the
command as a string, and DOING, e.g. \"simulating\", complete the sentence;
a symbol would print with its package prefix outside this package."
  (check-type plan (or null plan))
  (let ((p (or plan *current-plan*)))
    (unless (plan-p p)
      (%refuse :no-plan "~A requires a plan; call GP-PLAN first or pass :PLAN."
               command))
    (unless (plan-success p)
      (%refuse :unsuccessful-plan
               "The plan did not succeed; plan again before ~A." doing))
    p))

(defun gp-clear-memory (&key (working t) (knowledge t) (episodic t)
                          (procedural t))
  "Clear the selected session memory stores (all four by default). Returns T."
  (when working (clear-working-memory))
  (when knowledge (clear-knowledge-memory))
  (when episodic (clear-episodic-memory))
  (when procedural (clear-procedural-memory))
  ;; Defined later in this system, in interface/web-api.lisp.
  (%clear-applies-result-cache)
  t)

(defun gp-reset ()
  "Reset the REPL session to a fresh empty context in READ mode.
Also drops the last plan and execution, the listening session, working and
episodic session memory, the deliberative trace buffer, the failure
strategy and the autonomy policy (back to the safe default on next use),
and stops the notice watches.
Knowledge and procedural memory are kept (use GP-CLEAR-MEMORY to drop them),
and so is the adapters setting (GP-ADAPTERS).
Returns the new context."
  (%install-session-context (create-context :name 'default :mode :read))
  (setf *deliberative-strategy* nil
        *last-reaction* nil
        *last-autonomy* nil
        *autonomy-policy* nil)
  (clear-trace-session)
  (clear-working-memory)
  (clear-episodic-memory)
  ;; Both are defined later in this system: interface/web-api.lisp and
  ;; interface/notice.lisp.
  (%clear-applies-result-cache)
  (%stop-notice-watches)
  *current-context*)

(defun gp-context (&key name parent facts mode rules operators)
  "With no argument: return the current context.
With :NAME: create a context of that name from PARENT, FACTS, MODE (default
:READ), RULES and OPERATORS, make it the current context and return it.
The last plan, the last execution and the listening session belong to the
context they were made in and are dropped.
Another key without :NAME is refused and the current context stays: GP-MODE,
GP-ADD-FACT, GP-ADD-RULE and GP-ADD-OPERATOR change the current context.
A PARENT that is not a context, a fact that is not a list, a rule or an
operator that is not one, and a MODE that names none are TYPE-ERRORs, and
the current context stays."
  (cond
    (name
     (check-type parent (or null context))
     (%install-session-context
      (create-context :name name
                      :parent parent
                      :facts (%check-elements facts 'cons)
                      :rules (%check-elements rules 'rule)
                      :operators (%check-elements operators 'operator)
                      :mode (or mode :read))))
    ((or parent facts mode rules operators)
     (%refuse :context-name-required
              "GP-CONTEXT creates a context only with :NAME; GP-MODE, ~
               GP-ADD-FACT, GP-ADD-RULE and GP-ADD-OPERATOR change the ~
               current one."))
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
  "Assert FACT, a list such as (POWER-STATE INTERFACE-01 OFF), in the
current context. Returns FACT. Anything but a list is a TYPE-ERROR."
  (check-type fact cons "a fact, i.e. a non-empty list")
  (let ((ctx (ensure-current-context)))
    (context-add-fact! ctx fact)
    (refresh-working-memory ctx)
    fact))

(defun gp-remove-fact (fact)
  "Retract FACT from the current context (local facts only).
Returns the local facts that remain."
  (let ((ctx (ensure-current-context)))
    (context-remove-fact! ctx fact)
    (refresh-working-memory ctx)
    (context-facts ctx)))

(defun gp-add-goal (goal)
  "Add GOAL to the current context and return the goals of the context.
GOAL is a fact-like list or a symbol; anything else is a TYPE-ERROR.
When GOAL is fact-like and already holds in the current facts, the command
is refused and nothing is recorded. Names match across packages, so a goal
from JSON meets a fact recorded at the REPL. Symbol goals are labels
and are always accepted. Re-adding an already recorded open goal remains
idempotent."
  (check-type goal (or cons (and symbol (not null)))
              "a fact-like list or a symbol label")
  (let* ((ctx (ensure-current-context))
         (facts (context-all-facts ctx)))
    (when (and (consp goal)
               (or (goal-holds-p goal facts)
                   (find-fact-by-names goal facts)))
      (%refuse :goal-holds "That goal already holds."))
    (prog1 (add-goal! ctx goal)
      (refresh-working-memory ctx))))

(defun gp-remove-goal (goal)
  "Remove GOAL from the current context. Returns the goals that remain."
  (let ((ctx (ensure-current-context)))
    (prog1 (remove-goal! ctx goal)
      (refresh-working-memory ctx))))

(defun gp-add-rule (rule)
  "Register RULE (a RULE object) on the current context. Returns RULE."
  (check-type rule rule)
  (register-rule! (ensure-current-context) rule))

(defun gp-remove-rule (name)
  "Remove the rule named NAME from the current context.
Returns the local rules that remain."
  (remove-rule! (ensure-current-context) name))

(defun gp-add-operator (operator)
  "Register OPERATOR (an OPERATOR object) on the current context.
Returns OPERATOR."
  (check-type operator operator)
  (register-operator! (ensure-current-context) operator))

(defun gp-remove-operator (name)
  "Remove the operator named NAME from the current context.
Returns the local operators that remain."
  (remove-operator! (ensure-current-context) name))

(defun gp-query (pattern &key (infer t))
  "Query PATTERN in the current context.
Returns the hits and, as QUERY does, a second value that is false when
inference stopped before the closure was complete."
  (query pattern (ensure-current-context) :infer infer))

(defun gp-infer (&key (assert nil) (limit *forward-chain-limit*))
  "Forward-chain the rules visible in the current context over its facts.
Returns (VALUES ALL-FACTS NEW-FACTS COMPLETE-P), as FORWARD-CHAIN does.
COMPLETE-P is false when LIMIT rounds were not enough; FORWARD-CHAIN then
also signals the warning FORWARD-CHAIN-INCOMPLETE.
When ASSERT is true the new facts are asserted in the current context.
Each derived fact is sound, so those of a cut closure are asserted too:
COMPLETE-P says whether another GP-INFER could derive more."
  (let ((ctx (ensure-current-context)))
    (multiple-value-bind (all new complete-p)
        (forward-chain (context-all-facts ctx) (context-all-rules ctx)
                       :limit limit)
      (when assert
        (dolist (fact new)
          (context-add-fact! ctx fact))
        (refresh-working-memory ctx))
      (values all new complete-p))))

;;; ---------------------------------------------------------------------------
;;; Plan, simulate, run
;;; ---------------------------------------------------------------------------

(defun gp-plan (&key goals operators (remember t) (archive t))
  "Build a symbolic plan for GOALS (default: the goals of the current
context). Does not mutate facts. Only fact-like goals are planned; symbol
goals are labels.
OPERATORS, a list of OPERATOR objects, replaces the operators of the
context for this plan. GP-SIMULATE and GP-RUN run a step only through an
operator the context registers, so add such operators to the context
before running that plan.
When ARCHIVE is true (default), a scored procedure is reused if its
stored steps still apply. An exact goal match comes first. A procedure
whose goals also include other facts is used after that, and those extra
goals are applied. Otherwise procedures that each achieve part of the
request are combined, those with no extra goals first. A procedure that
also achieves something else is used after that, and those extra goals
are applied. When those extra goals cannot be restored, the steps that
serve the request are kept and the others are left aside. If none apply,
the plan is built by Means-Ends Analysis.
When there is no fact-like goal, or every fact-like goal already holds,
the command is refused instead of returning an empty successful plan: the
last plan, the mode and the listening session stay as they were. Core MEA
still treats an already-held goal as a zero-length success for internal
search.
The plan becomes the session plan and the mode becomes :PLAN. A plan that
fails opens a listening session on its remaining goals while
*LISTEN-ON-PLAN-FAILURE* is true; one that succeeds ends such a session.
When REMEMBER is true (default), records a plan episode in episodic memory."
  (%check-elements operators 'operator)
  (let* ((ctx (ensure-current-context))
         (requested (or goals (goals-of ctx))))
    (multiple-value-bind (fact-goals labels)
        (normalize-planning-goals requested)
      (cond
        ((and labels (null fact-goals))
         (%refuse :no-open-goal
                  "There is no open goal to plan: ~{~S~^, ~} ~
                   ~:[name goals~;names a goal~] without saying which ~
                   facts to reach."
                  labels (null (rest labels))))
        ((null (differences (context-all-facts ctx) fact-goals))
         (%refuse :no-open-goal "There is no open goal to plan."))))
    ;; The mode and the session plan change only once a plan exists: a
    ;; planner that signals leaves both as they were.
    (%install-plan ctx
                   (plan-consulting-archive ctx :goals requested
                                                :operators operators
                                                :archive archive)
                   :remember remember)))

(defun gp-plan-open-goals ()
  "Plan the unsatisfied fact-like goals already in the context.
Does not change facts, does not simulate, and does not execute.
No open goal (none recorded, or all already hold) is refused."
  (let ((open (autonomy-open-goals (ensure-current-context))))
    (unless open
      (%refuse :no-open-goal "There is no open goal to plan."))
    (gp-plan :goals open)))

(defun gp-last-plan ()
  "Return the session plan, set by GP-PLAN, GP-USE-PROCEDURE, GP-REACT or
an autonomy cycle, or NIL. A change of context drops it."
  *current-plan*)

(defun gp-simulate (&key plan (remember t))
  "Simulate PLAN (default: last plan) without mutating the live context.
Sets mode to :SIMULATE. Returns an EXECUTION-RESULT.
Symbolic effects only — no adapters.
A step that fails is given up and the run ends unsuccessful, unless
*DELIBERATIVE-STRATEGY* (GP-FAILURE-STRATEGY) says otherwise: :SKIP,
:RETRY, :ABORT and :ASK choose a restart themselves, and :SIGNAL lets the
GP-ERROR reach the caller's handlers with the restarts RETRY SKIP
ABORT-EXECUTION USE-VALUE USE-ALTERNATIVE ASK-USER active.
The plan is refused, before any simulated step and with the context mode
left as it was, for what GP-RUN would refuse it for as well: a step whose
operator the context does not register and that carries no record to run
from (UNKNOWN-OPERATOR), a recorded external action that no longer
matches, or facts that no longer support an action that would be handed
to an adapter (PLAN-REFUSED). No plan, or an unsuccessful one, is refused
the same way. When REMEMBER is true (default), records an episode."
  (let ((ctx (ensure-current-context))
        (p (%successful-plan plan "GP-SIMULATE" "simulating")))
    ;; EXECUTE-PLAN! finds a step's operator in the context alone, while
    ;; SIMULATE-PLAN falls back on the operators the plan was built with. A
    ;; simulation must not succeed on a plan the live run would refuse.
    (%resolve-plan-steps p :context ctx)
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

(defun gp-run (&key plan confirm (remember t) (adapters nil adapters-p))
  "Execute PLAN (default: last plan) against live context facts.
Sets mode to :EXECUTE. Returns an EXECUTION-RESULT.
CONFIRM true approves irreversible and high-risk operators beforehand;
otherwise such a step fails with CONFIRMATION-REQUIRED.
A step that fails is given up and the run ends unsuccessful, unless
*DELIBERATIVE-STRATEGY* (GP-FAILURE-STRATEGY) says otherwise: :SKIP,
:RETRY, :ABORT and :ASK choose a restart themselves, and :SIGNAL lets the
GP-ERROR reach the caller's handlers with the restarts RETRY SKIP
ABORT-EXECUTION USE-VALUE USE-ALTERNATIVE ASK-USER (and CONFIRM for a
step that needs confirmation) active.
Symbolic effects always apply. When ADAPTERS is true, operators with
:EXTERNAL meta may invoke OS adapters (Phase 8). Default: the session
setting (GP-ADAPTERS), normally off.
When REMEMBER is true (default), records an episode.
A plan reused from the archive (:FROM-PROCEDURE) updates that procedure's
score from this live result. GP-SIMULATE does not.
A refusal signals before any fact changes and leaves the context mode
as it was. No plan, or an unsuccessful one, is refused the same way."
  (let ((ctx (ensure-current-context))
        (p (%successful-plan plan "GP-RUN" "running")))
    (setf *last-execution*
          (call-with-execution-mode
           ctx :execute
           (lambda ()
             (execute-plan! ctx p
                            :confirm confirm
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
  "Return the last EXECUTION-RESULT from GP-SIMULATE or GP-RUN, or NIL.
A change of context drops it."
  *last-execution*)

(defun gp-failure-strategy (&optional (policy nil policy-p) (retry-limit 3))
  "Get, set or clear the session *DELIBERATIVE-STRATEGY*.
With no argument: return the current strategy, or NIL.
With POLICY :SIGNAL, :SKIP, :RETRY, :ABORT or :ASK: install and return a
fresh strategy; a :RETRY policy retries one step at most RETRY-LIMIT times.
With POLICY NIL: clear the strategy and return NIL, so a failed step is
given up again.
Any other POLICY, or a RETRY-LIMIT that is not a non-negative integer, is
a TYPE-ERROR and leaves the strategy in place."
  (cond
    ((not policy-p) *deliberative-strategy*)
    ((null policy) (setf *deliberative-strategy* nil))
    (t (setf *deliberative-strategy*
             (make-strategy :policy policy :retry-limit retry-limit)))))

(defun gp-mode (&optional mode)
  "Get or set the current context mode (:READ :PLAN :SIMULATE :EXECUTE).
With no argument, or NIL: return the mode. Anything that names no mode
signals UNKNOWN-KEYWORD and leaves the mode as it was."
  (let ((ctx (ensure-current-context)))
    (when mode
      (setf (context-mode ctx) (ensure-mode mode))
      (refresh-working-memory ctx))
    (context-mode ctx)))

(defun gp-register-action (action)
  "Register ACTION (an ACTION object) on the current context. Returns ACTION."
  (check-type action action)
  (register-action! (ensure-current-context) action))

;;; ---------------------------------------------------------------------------
;;; Listening and induction
;;; ---------------------------------------------------------------------------

(defun gp-listen (&key missing (reason :manual))
  "Open a listening session on the facts of the current context.
MISSING records the goals still open, usually PLAN-REMAINING after a
failed plan. REASON is :MANUAL (default) or :PLAN-FAILED.
The session belongs to the current context: a later GP-INDUCE-RULE or
GP-LEARN-ACTION consumes its before-state there, and a change of context
ends it. Returns a copy of the session plist, as GP-OBSERVATION does."
  (check-type missing list)
  (check-type reason (member :manual :plan-failed))
  (let* ((ctx (ensure-current-context))
         (before (copy-list (context-all-facts ctx))))
    (setf *observed-before* before
          *observation* (list :active t
                              :before before
                              :missing (copy-list missing)
                              :reason reason
                              :context ctx))
    (gp-observation)))

(defun gp-note-state ()
  "Remember the current facts as the before-state of a manual action.
The same as GP-LISTEN with no missing goal."
  (gp-listen :reason :manual))

(defun %listening-before (context)
  "The before-state of the listening session open on CONTEXT.
An empty before-state is a state like any other. Refuses when nobody is
listening, and when the session was opened on another context: its facts
say nothing about a change made in CONTEXT."
  (cond
    ((not (observation-active-p))
     (%refuse :no-listening-session
              "No listening session. Call GP-LISTEN or GP-NOTE-STATE ~
               before the manual change."))
    ((not (eq (getf *observation* :context) context))
     (%refuse :no-listening-session
              "The listening session was opened on another context. Call ~
               GP-LISTEN or GP-NOTE-STATE here before the manual change."))
    (t
     (getf *observation* :before))))

(defun %register-induced-operator (context fresh generalize)
  "Register the induced operator FRESH on CONTEXT and return what is now
registered under its name: FRESH as the first example, or the merge of
FRESH into the induced operator already visible there. With GENERALIZE the
merge may turn constants into variables; without it every constant must
match and an operator that already uses variables is refused.
Signals INDUCTION-ERROR, registering nothing: :NOT-INDUCED when the
operator in place was not induced, :USES-VARIABLES, or :DOES-NOT-FIT."
  (let* ((name (operator-name fresh))
         ;; Not FIND-OPERATOR: with no operator in CONTEXT it answers with a
         ;; lifted action, which is not an operator anyone registered.
         (existing (find name (context-all-operators context)
                         :key #'operator-name :test #'equal)))
    (flet ((refuse (reason)
             (error 'induction-error :name name :reason reason)))
      (register-operator!
       context
       (cond
         ((null existing)
          (setf (getf (operator-meta fresh) :examples) 1)
          fresh)
         ((not (getf (operator-meta existing) :induced))
          (refuse :not-induced))
         ((and (not generalize) (%operator-uses-variables-p existing))
          (refuse :uses-variables))
         (t
          (or (merge-induced-operators existing fresh :lift generalize)
              (refuse :does-not-fit))))))))

(defun %induce (name before before-p after after-p register generalize)
  "Induce operator NAME from one observation; see GP-LEARN-ACTION and
GP-INDUCE-RULE, which differ in GENERALIZE alone. A BEFORE or AFTER that
is supplied must be a list of facts. The listening session of the current
context ends only when the induction succeeded; one open on another
context is not this command's to end."
  (when before-p (%check-elements before 'cons))
  (when after-p (%check-elements after 'cons))
  (let* ((ctx (ensure-current-context))
         (before (if before-p before (%listening-before ctx)))
         (after (if after-p after (context-all-facts ctx)))
         (fresh (induce-operator name before after :generalize generalize))
         (operator (if register
                       (%register-induced-operator ctx fresh generalize)
                       fresh)))
    (when (eq (getf *observation* :context) ctx)
      (%end-listening))
    operator))

(defun gp-learn-action (name &key (before nil before-p) (after nil after-p)
                               (register t))
  "Induce a ground operator named NAME and, by default, register it.
BEFORE defaults to the before-state of the listening session (GP-NOTE-STATE
or GP-LISTEN), which may be empty. AFTER defaults to the current facts.
Either, when supplied, is a list of facts; anything else is a TYPE-ERROR.
Without an explicit BEFORE, a listening session must be active on the
current context — a stale before-state left after a successful plan, or
one noted in another context, is refused.
Patterns stay ground. A later call with the same name
merges when every constant is already the same; a different symbol or
number is refused and does not become a variable. An operator that
already uses variables is left unchanged.
Without a session the command is refused (COMMAND-REFUSED). An
observation that cannot become the operator signals INDUCTION-ERROR, whose
reason is :UNCHANGED-STATE, :NOT-INDUCED (an operator of that name exists
and was not induced), :USES-VARIABLES or :DOES-NOT-FIT. Either way the
operator in place and the listening session stay as they were.
With REGISTER false the operator is returned and nothing is registered.
Ends the session of the current context only after a successful induction."
  (%induce name before before-p after after-p register nil))

(defun gp-induce-rule (name &key (before nil before-p) (after nil after-p)
                             (register t))
  "Induce a generalized operator named NAME and, by default, register it.
The object symbol shared by one change becomes ?X0. Numbers stay ground.
BEFORE defaults to the before-state of the listening session, which may be
empty. AFTER defaults to the current facts. Either, when supplied, is a
list of facts; anything else is a TYPE-ERROR. Without an explicit BEFORE, a
listening session must be active on the current context — a stale
before-state left after a successful plan, or one noted in another
context, is refused.
A later call with the same name merges the new example when it fits: an
existing variable stays, a repeated symbol that is renamed becomes the
next variable, and a differing number or a one-off value is refused.
Without a session the command is refused (COMMAND-REFUSED). An
observation that cannot become the operator signals INDUCTION-ERROR, whose
reason is :UNCHANGED-STATE, :NOT-INDUCED (an operator of that name exists
and was not induced) or :DOES-NOT-FIT. Either way the operator in place
and the listening session stay as they were.
With REGISTER false the operator is returned and nothing is registered.
Ends the session of the current context only after a successful induction."
  (%induce name before before-p after after-p register t))

;;; ---------------------------------------------------------------------------
;;; Explanation from recorded deliberative traces
;;; ---------------------------------------------------------------------------

(defun gp-explain (&optional (topic :last) (stream t))
  "Explain TOPIC from its recorded deliberative trace.
TOPIC may be :LAST (default), :PLAN, :EXECUTION, :HISTORY, a PLAN,
an EXECUTION-RESULT, or a DELIBERATIVE-TRACE.
Does not invent decisions — only formats entries recorded during
plan / MEA / simulate / execute.
Returns (VALUES TEXT TRACE). STREAM is as for FORMAT: with the default T
the explanation is printed to standard output and TEXT is NIL; with NIL
nothing is printed and TEXT is the explanation."
  (explain-trace topic :stream stream))

(defun gp-last-trace ()
  "Return the most recently finished deliberative trace, or NIL."
  (last-trace))

(defun gp-trace-history ()
  "Return newest-first session trace history (in-memory buffer only)."
  (copy-list *trace-history*))

;;; ---------------------------------------------------------------------------
;;; Memory and persistence
;;; ---------------------------------------------------------------------------

(defun gp-working ()
  "Refresh and return the session working-memory snapshot."
  (refresh-working-memory (ensure-current-context)))

(defun gp-knowledge (&key name facts rules)
  "With no args: return (ensuring) session knowledge memory.
With keys: replace/create knowledge memory and return it. FACTS must be
lists and RULES rule objects; anything else is a TYPE-ERROR and the
knowledge memory in place stays."
  (if (or name facts rules)
      (setf *knowledge-memory*
            (make-knowledge-memory :name (or name 'default)
                                   :facts (%check-elements facts 'cons)
                                   :rules (%check-elements rules 'rule)))
      (ensure-knowledge-memory)))

(defun gp-knowledge-add (item)
  "Add ITEM, a fact (a list) or a RULE object, to session knowledge memory.
Returns ITEM. Anything else is a TYPE-ERROR."
  (check-type item (or cons rule) "a fact list or a RULE")
  (if (rule-p item)
      (knowledge-add-rule! item)
      (knowledge-add-fact! item)))

(defun gp-knowledge-query (pattern &key (infer nil))
  "Query PATTERN against session knowledge memory."
  (knowledge-query pattern :infer infer))

(defun gp-knowledge-merge ()
  "Merge session knowledge into the current context. Returns the context."
  (let ((ctx (ensure-current-context)))
    (knowledge-merge-into-context! ctx)
    (refresh-working-memory ctx)
    ctx))

(defun gp-episodes (&key kind success context-name)
  "Session episodes, newest first. KIND and CONTEXT-NAME select the
episodes that carry that value; SUCCESS T selects those that succeeded and
SUCCESS :FAILED those that did not. A filter left NIL selects everything."
  (find-episodes :kind kind :success success :context-name context-name))

(defun gp-last-episode ()
  "Most recent episode, or NIL."
  (when (episodic-memory-p *episodic-memory*)
    (last-episode *episodic-memory*)))

(defun gp-remember-procedure (&key plan name)
  "Store a reusable procedure from PLAN (default: the session plan).
Same name accumulates successes. Autosaves the procedure archive when
*PROCEDURE-ARCHIVE-AUTOSAVE* is true (default).
No plan, or an unsuccessful one, is refused before the archive is touched."
  (remember-procedure-from-plan!
   (%successful-plan plan "GP-REMEMBER-PROCEDURE" "remembering")
   :name name))

(defun gp-procedures (&optional goals)
  "List stored procedures, or those whose goal set equals GOALS when
supplied."
  (if goals
      (procedures-for-goals goals)
      (copy-list (procedural-memory-procedures (ensure-procedural-memory)))))

(defun gp-find-procedure (name)
  "Find a stored procedure by NAME, or NIL."
  (find-procedure name))

(defun gp-archive (&optional goals)
  "Archived procedures, highest score first. GOALS filters to an exact goal set."
  (rank-procedures (if goals
                       (procedures-for-goals goals)
                       (procedural-memory-procedures (ensure-procedural-memory)))))

(defun gp-archive-best (goals)
  "Highest-scoring archived procedure whose goal set equals GOALS, or NIL."
  (archive-best goals))

(defun gp-archive-save (&optional (path *procedure-archive-path*))
  "Write the procedure archive to PATH (default ~/.automa-gp/procedure-archive.agp)."
  (save-procedure-archive :path path))

(defun gp-archive-load (&optional (path *procedure-archive-path*))
  "Merge the procedure archive at PATH into session procedural memory, as
LOAD-PROCEDURE-ARCHIVE does. Returns the memory store."
  (load-procedure-archive path))

(defun gp-use-procedure (&key name goals (unchecked nil) (remember t))
  "Build a PLAN from the archive, without searching from scratch.
NAME selects one procedure; an unknown name signals UNKNOWN-PROCEDURE,
with the restart :USE-VALUE to name another one.
Without NAME, use an archived procedure for the fact-like goals among
GOALS (default: goals on the current context) whose steps still apply.
An exact goal match comes first; a procedure that also achieves other
goals is used after that. Otherwise procedures that each achieve part of
the request are combined, those with no extra goals first, and a search
restores only what they leave.
The plan is a replay on the current facts and carries a deliberative trace.
When the stored steps do not apply, or no procedure answers the goals, the
command is refused: no plan is built and the session plan stays.
UNCHECKED T rebuilds the procedure anyway, without that check: the one
named, or the best one whose goals are exactly the fact-like GOALS.
Records the external actions that replay would run. Does not invoke them.
The plan becomes the session plan and the mode becomes :PLAN, as with
GP-PLAN: a plan that succeeds ends a listening session that was opened
for a failed plan. When REMEMBER is true (default), records a plan episode
in episodic memory."
  (let* ((ctx (ensure-current-context))
         (requested (or goals (goals-of ctx)))
         (goal-set (normalize-planning-goals requested))
         (operators (context-planning-operators ctx))
         (plan
           (flet ((no-procedure ()
                    ;; REQUESTED, labels included: the sentence repeats
                    ;; what was asked, not what was left of it.
                    (%refuse :no-procedure
                             "No archived procedure matches goals ~:S."
                             requested)))
             (cond
               (name
                (let ((procedure (%procedure-named
                                  name (ensure-procedural-memory))))
                  (if unchecked
                      (procedure->plan procedure)
                      (or (plan-from-procedure procedure
                                               (context-all-facts ctx)
                                               operators
                                               :context-name (context-name ctx))
                          (%refuse :procedure-does-not-apply
                                   "Procedure ~A does not apply to the ~
                                    current state; no plan was built."
                                   (procedure-name procedure))))))
               (unchecked
                (procedure->plan (or (archive-best goal-set) (no-procedure))))
               ((plan-from-ranked-procedures ctx goal-set operators))
               ((%procedures-for-planning goal-set)
                (%refuse :procedure-does-not-apply
                         "No archived procedure for goals ~S applies to ~
                          the current state; no plan was built."
                         goal-set))
               (t
                (no-procedure))))))
    (remember-plan-external-actions plan :context ctx)
    (%install-plan ctx plan :remember remember)))

(defun gp-score-procedure (name &key (success t))
  "Score a replay of the archived procedure NAME. :SUCCESS NIL records a failure."
  (score-procedure! name :success success))

(defun gp-save (path &key (context t) (knowledge t) (episodic t)
                       (procedural t) meta)
  "Save a snapshot bundle to PATH. The keys select its sections.
CONTEXT is T (default) for the current context, a CONTEXT to save that
one, or NIL to leave the section out. KNOWLEDGE, EPISODIC and PROCEDURAL
are likewise T for the session memory, a memory object of that kind, or
NIL. A session memory that does not exist yet is left out."
  (flet ((section (requested object-p session)
           (cond
             ((funcall object-p requested) requested)
             (requested (and (funcall object-p session) session)))))
    (save-snapshot path
                   :context (cond
                              ((context-p context) context)
                              (context (ensure-current-context)))
                   :knowledge (section knowledge #'knowledge-memory-p
                                       *knowledge-memory*)
                   :episodic (section episodic #'episodic-memory-p
                                      *episodic-memory*)
                   :procedural (section procedural #'procedural-memory-p
                                        *procedural-memory*)
                   :meta meta)))

(defun gp-load (path &key (apply t))
  "Load a snapshot from PATH and return the bundle.
When APPLY is true (default), install it into the session: each memory
the bundle holds replaces the session's, and its context, when it has
one, becomes the current context. The last plan, the last execution and
the listening session belong to the context before it and are then
dropped. A bundle without a context leaves the current context and those
three as they were."
  (let ((bundle (load-snapshot path)))
    (when apply
      (apply-snapshot! bundle :set-current nil)
      (let ((context (getf bundle :context)))
        (when context
          (%install-session-context context))))
    bundle))

(defun gp-save-context (path)
  "Persist only the current context to PATH."
  (persist-context (ensure-current-context) path))

(defun gp-load-context (path &key (set-current t))
  "Restore a context from PATH and return it.
When SET-CURRENT is true (default), make it the session context: the last
plan, the last execution and the listening session belong to the context
before it and are dropped."
  (let ((ctx (restore-context path)))
    (when set-current
      (%install-session-context ctx))
    ctx))

;;; ---------------------------------------------------------------------------
;;; Context-bound events
;;; ---------------------------------------------------------------------------

(defun gp-emit (form &key (react nil) (plan nil) (infer nil)
                       (assert-fact t) (remember t) (meta nil meta-p))
  "Post event FORM ((TYPE . DATA), e.g. (FILE-CREATED \"doc.pdf\")) on the
current context. By default only records the event (and asserts it as a fact).
META, a plist, becomes the meta of the event when supplied; a GP-EVENT
posted without it keeps its own. A META that is not a list is a TYPE-ERROR
and nothing is posted.
When :REACT is true, process pending events as GP-REACT does (reactions →
facts/goals), with :PLAN, :INFER and :REMEMBER passed on.
Returns the GP-EVENT (and leaves *LAST-REACTION* when reacting)."
  (check-type meta list)
  (let* ((ctx (ensure-current-context))
         (event (if meta-p
                    (emit-event! ctx form :assert-fact assert-fact :meta meta)
                    (emit-event! ctx form :assert-fact assert-fact))))
    (when react
      (gp-react :plan plan :infer infer :remember remember))
    (refresh-working-memory ctx)
    event))

(defun gp-events (&key status)
  "List events on the current context (oldest first). Optional :STATUS filter."
  (events-of (ensure-current-context) :status status))

(defun gp-react (&key (plan nil) (infer nil) (remember t))
  "Process pending events: reactions assert facts and add goals; with
:INFER the rules are then forward-chained.
When :PLAN is true and a fact-like goal is then open, plan as GP-PLAN
does: the archive is consulted, the plan becomes the session plan, a
failed plan opens a listening session, and REMEMBER records the episode.
With no open goal there is nothing to plan and the last plan stays.
Returns the reaction summary plist (*LAST-REACTION*), whose :PLAN is the
plan built here or NIL. Goal-directed GP-PLAN still works independently
of events."
  (let* ((ctx (ensure-current-context))
         (summary (process-pending-events! ctx :infer infer)))
    (when (and plan (autonomy-open-goals ctx))
      (setf (getf summary :plan) (gp-plan :remember remember)
            *last-reaction* summary))
    (refresh-working-memory ctx)
    summary))

(defun gp-add-reaction (reaction)
  "Register REACTION (an EVENT-REACTION object) on the current context.
Returns REACTION."
  (check-type reaction event-reaction)
  (register-event-reaction! (ensure-current-context) reaction))

(defun gp-remove-reaction (name)
  "Remove event reaction named NAME from the current context.
Returns the local reactions that remain."
  (remove-event-reaction! (ensure-current-context) name))

(defun gp-reactions ()
  "Event reactions visible on the current context (incl. parents)."
  (context-all-event-reactions (ensure-current-context)))

(defun gp-last-reaction ()
  "Summary plist from the last GP-REACT / PROCESS-PENDING-EVENTS!, or NIL."
  *last-reaction*)

;;; ---------------------------------------------------------------------------
;;; Controlled autonomy
;;; ---------------------------------------------------------------------------

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
With keys: build a policy from the current one with those options changed;
when SET is true (default), install it. Returns the policy."
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

(defun %policy-with-work (policy)
  "POLICY, or the session policy when POLICY is NIL, for an autonomy cycle
that has something to do under it. Refuses an idle cycle, so the last
autonomy summary is not overwritten by an empty one."
  (let ((context (ensure-current-context))
        (policy (ensure-autonomy-policy policy)))
    (unless (autonomy-has-work-p context policy)
      (%refuse :no-work
               (if (pending-events context)
                   "There is no open goal, and the policy does not react ~
                    to pending events."
                   "There is no open goal and no pending event.")))
    policy))

(defun gp-autonomous-step (&key policy (remember t))
  "One controlled autonomy cycle (PROMPT §28). Respects policy authority
(:READ | :SIMULATE | :EXECUTE). Default policy authority is :SIMULATE.
POLICY defaults to the session policy (GP-POLICY).
Refused when there is no open goal and no pending event the policy
reacts to — the same gate as the workbench Passo button. Does not
overwrite the last autonomy summary in that case."
  (autonomous-step :policy (%policy-with-work policy)
                   :remember remember))

(defun gp-autonomous-loop (&key policy max-steps (remember t))
  "Repeat GP-AUTONOMOUS-STEP until done, halted, or MAX-STEPS steps
(default: the policy's limit).
Refused when there is no open goal and no pending event the policy
reacts to — the same gate as the workbench Ciclo button. Does not
overwrite the last autonomy summary in that case."
  (autonomous-loop :policy (%policy-with-work policy)
                   :max-steps max-steps
                   :remember remember))

(defun gp-last-autonomy ()
  "Summary plist from the last autonomous step/loop, or NIL."
  *last-autonomy*)
