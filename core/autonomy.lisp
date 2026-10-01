;;;; core/autonomy.lisp — controlled autonomous symbolic operation (Phase 12)
;;;;
;;;; PROMPT §28: autonomy ≠ indiscriminate execution. One step walks
;;;; observe → react → goals → plan → evaluate → authorize →
;;;; (simulate|execute) → observe result → discrepancy → knowledge update.
;;;; AUTONOMOUS-LOOP repeats the step up to a limit: after a live run that
;;;; failed part-way, the next step replans from the observed facts.
;;;;
;;;; Authority levels, in ascending order:
;;;;   :READ     — react to pending events (a reaction may assert facts and
;;;;               add goals, and a policy that infers adds derived facts)
;;;;               and report the open differences; never plans, simulates
;;;;               or executes
;;;;   :SIMULATE — plan, then simulate on a copy of the facts (default);
;;;;               no live fact changes except through reactions
;;;;   :EXECUTE  — plan, then change live facts, and only through
;;;;               %AUTHORIZE-EXECUTION: risky steps need confirmation and
;;;;               adapters stay off unless the policy enables them

(in-package #:automa-gp)

(defparameter *valid-authorities* '(:read :simulate :execute)
  "Maximum autonomy authority levels (ascending privilege).")

(defvar *autonomy-policy* nil
  "Session default AUTONOMY-POLICY, or NIL.")

(defvar *last-autonomy* nil
  "Summary plist of the last AUTONOMOUS-STEP or AUTONOMOUS-LOOP, or NIL.
A loop summary is the summary of its last step with :ITERATIONS,
:RESULTS and :FINAL added.")

;;; ---------------------------------------------------------------------------
;;; Policy
;;; ---------------------------------------------------------------------------

(defclass autonomy-policy ()
  ((authority
    :initarg :authority
    :accessor policy-authority
    :initform :simulate
    :documentation ":READ | :SIMULATE | :EXECUTE — ceiling for this run.")
   (max-steps
    :initarg :max-steps
    :accessor policy-max-steps
    :initform 8
    :documentation "Positive integer: how many steps AUTONOMOUS-LOOP may take.")
   (adapters
    :initarg :adapters
    :accessor policy-adapters
    :initform nil
    :documentation "When true and authority is :EXECUTE, allow OS adapters.")
   (auto-confirm
    :initarg :auto-confirm
    :accessor policy-auto-confirm
    :initform nil
    :documentation "When true, confirm high-risk/irreversible ops automatically.
A CONFIRM-FN, when present, is still asked and may deny.")
   (confirm-fn
    :initarg :confirm-fn
    :accessor policy-confirm-fn
    :initform nil
    :documentation "Optional (lambda (plan context) → boolean) gate, called once
for a plan with a high-risk or irreversible step before it is executed.")
   (react-events
    :initarg :react-events
    :accessor policy-react-events
    :initform t
    :documentation "When true, a step first processes the pending events.")
   (infer
    :initarg :infer
    :accessor policy-infer
    :initform nil
    :documentation "When true, forward-chain the rules after reacting to events.")
   (learn
    :initarg :learn
    :accessor policy-learn
    :initform t
    :documentation "After a live run that achieved its goals, record them in
knowledge memory. A simulation never does.")
   (replan-on-discrepancy
    :initarg :replan-on-discrepancy
    :accessor policy-replan-on-discrepancy
    :initform t
    :documentation "When true, a live run that failed after changing facts ends
the step :CONTINUE, so the loop replans from the observed facts. When
false that step halts with :EXECUTION-FAILED.")
   (remember-procedure
    :initarg :remember-procedure
    :accessor policy-remember-procedure
    :initform nil
    :documentation "When true, a fresh plan whose run achieved the goals, under
:EXECUTE or :SIMULATE, is stored as a procedure. A plan replayed from the
archive is never stored again, and a simulation never changes a score.")
   (prefer-archive
    :initarg :prefer-archive
    :accessor policy-prefer-archive
    :initform t
    :documentation "When true, reuse a scored procedure whose steps still apply before MEA."))
  (:documentation "Explicit gates for autonomous operation."))

(defun autonomy-policy-p (object)
  "True if OBJECT is an AUTONOMY-POLICY."
  (typep object 'autonomy-policy))

(defun ensure-authority (authority)
  "Return the member of *VALID-AUTHORITIES* that AUTHORITY designates, or
signal an error. AUTHORITY is a symbol of any package or a string; names
are compared without regard to case and nothing is interned."
  (or (and (typep authority '(or symbol string))
           (find authority *valid-authorities* :test #'string-equal))
      (error "Unknown autonomy authority ~S; expected one of ~S"
             authority *valid-authorities*)))

(defun make-autonomy-policy (&key (authority :simulate) (max-steps 8)
                               (adapters nil) (auto-confirm nil)
                               confirm-fn (react-events t) (infer nil)
                               (learn t) (replan-on-discrepancy t)
                               (remember-procedure nil)
                               (prefer-archive t))
  "Construct an AUTONOMY-POLICY. Default authority is :SIMULATE (safe).
MAX-STEPS is an integer: NIL means the default 8 and a value below 1
becomes 1. CONFIRM-FN is NIL or a function designator. Every other
option is a generalized boolean."
  (check-type max-steps (or null integer))
  (check-type confirm-fn (or symbol function))
  (make-instance 'autonomy-policy
                 :authority (ensure-authority authority)
                 :max-steps (max 1 (or max-steps 8))
                 :adapters (and adapters t)
                 :auto-confirm (and auto-confirm t)
                 :confirm-fn confirm-fn
                 :react-events (and react-events t)
                 :infer (and infer t)
                 :learn (and learn t)
                 :replan-on-discrepancy (and replan-on-discrepancy t)
                 :remember-procedure (and remember-procedure t)
                 :prefer-archive (and prefer-archive t)))

(defun ensure-autonomy-policy (&optional policy)
  "POLICY when given, else the session *AUTONOMY-POLICY*, else a fresh
default policy (:SIMULATE). Anything but an AUTONOMY-POLICY or NIL is a
TYPE-ERROR: a malformed policy must not silently turn into another one."
  (check-type policy (or null autonomy-policy))
  (cond
    (policy)
    ((autonomy-policy-p *autonomy-policy*) *autonomy-policy*)
    (t (make-autonomy-policy))))

(defun authority>= (have need)
  "True if HAVE authority is at least NEED (:READ < :SIMULATE < :EXECUTE)."
  (>= (position (ensure-authority have) *valid-authorities*)
      (position (ensure-authority need) *valid-authorities*)))

(defun %session-context (context)
  "CONTEXT, or the session *CURRENT-CONTEXT* when CONTEXT is NIL.
Anything but a CONTEXT or NIL is a TYPE-ERROR, so a wrong argument never
redirects a run to the session context."
  (check-type context (or null context))
  (cond
    (context)
    ((context-p *current-context*) *current-context*)
    (t (error "Autonomy needs a context: pass one, or call GP-RESET first."))))

;;; ---------------------------------------------------------------------------
;;; Risk
;;; ---------------------------------------------------------------------------

(defun %step-operator (step context)
  "The operator EXECUTE-PLAN! will ask confirmation for when it runs STEP:
the one registered in CONTEXT, or, when it is no longer registered, a
stand-in carrying the risk the plan recorded on STEP. A step that
recorded none counts as reversible and :LOW, as it does in the executor."
  (or (lookup-operator (getf step :operator) :context context)
      (make-operator :name (or (getf step :operator) 'stored-effects)
                     :risk (or (getf step :risk) :low)
                     :reversible (and (getf step :reversible t) t))))

(defun plan-risky-operators (plan context)
  "The steps of PLAN that need confirmation before a live run, in plan
order, each as (:NAME :RISK :REVERSIBLE). A step counts when its operator
is irreversible or :HIGH/:CRITICAL risk; for an operator that is no
longer registered in CONTEXT, the risk recorded on the step decides."
  (when (plan-p plan)
    (loop for step in (plan-steps plan)
          for operator = (%step-operator step context)
          when (operator-needs-confirmation-p operator)
            collect (list :name (operator-name operator)
                          :risk (operator-risk operator)
                          :reversible (operator-reversible operator)))))

(defun plan-requires-confirmation-p (plan context)
  "True if any step's operator is irreversible or high/critical risk.
See PLAN-RISKY-OPERATORS."
  (and (plan-risky-operators plan context) t))

;;; ---------------------------------------------------------------------------
;;; Open work
;;; ---------------------------------------------------------------------------

(defun goals-satisfied-p (context &optional goals)
  "True when every goal in GOALS (default: the fact-like goals of CONTEXT)
holds in the facts visible in CONTEXT. False when there is no goal."
  (let ((g (or goals (normalize-planning-goals (goals-of context))))
        (facts (context-all-facts context)))
    (and g (null (differences facts g)))))

(defun autonomy-open-goals (&optional context)
  "Fact-like goals of CONTEXT that do not yet hold."
  (let ((ctx (%session-context context)))
    (differences (context-all-facts ctx)
                 (normalize-planning-goals (goals-of ctx)))))

(defun autonomy-has-work-p (&optional context policy)
  "True when CONTEXT has unsatisfied fact-like goals or pending events.
Matches workbench Passo/Ciclo enablement. When POLICY is given and does
not react to events, pending events do not count: a step under that
policy would leave them pending."
  (check-type policy (or null autonomy-policy))
  (let ((ctx (%session-context context)))
    (or (autonomy-open-goals ctx)
        (and (or (null policy) (policy-react-events policy))
             (pending-events ctx)))))

;;; ---------------------------------------------------------------------------
;;; The authorization gate
;;; ---------------------------------------------------------------------------

(defun %external-refusal (policy plan context)
  "Why the external actions of PLAN forbid running it under POLICY, or NIL.
The same two refusals SIMULATE-PLAN and EXECUTE-PLAN! make before their
first step, decided here so that a refused plan halts the cycle:
:EXTERNAL-MISMATCH when the plan recorded its external actions and they
no longer ground the same way, or when adapters are requested for a
live run and the plan never recorded them; :EXTERNAL-UNSUPPORTED when
the facts no longer lead to an action that would be handed to an adapter."
  (let ((recorded (getf (plan-meta plan) :external-actions-recorded))
        (adapters (and (eq (policy-authority policy) :execute)
                       (policy-adapters policy))))
    (cond
      ((and (or recorded adapters)
            (not (plan-external-actions-match-p plan :context context)))
       :external-mismatch)
      ((not (plan-external-actions-supported-p plan :context context))
       :external-unsupported))))

(defun %confirm-live-run (policy plan context)
  "Decide the confirmation gate for a live run of PLAN.
Returns (VALUES OK REASON CONFIRMED). CONFIRMED is true only when the
policy confirms automatically or its CONFIRM-FN approved this plan; it is
the only confirmation the run may carry. A CONFIRM-FN is asked exactly
once, with (PLAN CONTEXT), when the plan has a step that needs
confirmation, and its refusal stands even under auto-confirm.
A CONFIRM-FN is the caller's code and runs after the external actions of
PLAN were checked, so they are checked again on the context it leaves
behind: an approval never authorizes a plan the runner would refuse."
  (let ((risky (plan-requires-confirmation-p plan context))
        (confirm-fn (policy-confirm-fn policy)))
    (cond
      (confirm-fn
       (cond
         ((not risky) (values t :execute-authorized nil))
         ((funcall confirm-fn plan context)
          (let ((refusal (%external-refusal policy plan context)))
            (if refusal
                (values nil refusal nil)
                (values t :execute-authorized t))))
         (t (values nil :confirmation-denied nil))))
      ((policy-auto-confirm policy) (values t :execute-authorized t))
      (risky (values nil :confirmation-required nil))
      (t (values t :execute-authorized nil)))))

(defun %authorize-execution (policy plan context)
  "Return (VALUES OK REASON CONFIRMED): whether POLICY allows running PLAN
in CONTEXT at its authority, the keyword that says why, and whether a
live run carries a confirmation (see %CONFIRM-LIVE-RUN).
:READ authorizes nothing. Only a successful plan is authorized. When the
plan recorded an external action that no longer matches, neither
simulation nor execution is authorized, with or without adapters. When
adapters are requested, a plan that never recorded its actions is not
authorized for execute either. An external action the facts no longer
support is not authorized for execute or simulate, with or without
adapters. Execution also needs every risky step confirmed."
  (let ((authority (policy-authority policy)))
    (cond
      ((eq authority :read) (values nil :authority-read nil))
      ((not (plan-p plan)) (values nil :no-plan nil))
      ((not (plan-success plan)) (values nil :plan-unsuccessful nil))
      (t
       (let ((refusal (%external-refusal policy plan context)))
         (cond
           (refusal (values nil refusal nil))
           (t
            (ecase authority
              (:simulate (values t :simulate-authorized nil))
              (:execute (%confirm-live-run policy plan context))))))))))

;;; ---------------------------------------------------------------------------
;;; Phases of one step
;;; ---------------------------------------------------------------------------

(defun %observe-context (context)
  "Snapshot plist of CONTEXT for the :OBSERVE phase: counts, not contents."
  (list :phase :observe
        :context (context-name context)
        :mode (context-mode context)
        :fact-count (length (context-all-facts context))
        :goal-count (length (goals-of context))
        :pending-events (length (pending-events context))
        :domains (copy-list (getf (context-meta context) :domains))))

(defun %react-to-pending-events (context policy)
  "Process the pending events of CONTEXT when POLICY reacts to events.
Returns the reaction summary of PROCESS-PENDING-EVENTS!, or NIL when the
policy does not react or nothing was pending."
  (when (and (policy-react-events policy)
             (pending-events context))
    (process-pending-events! context
                             :plan nil
                             :infer (policy-infer policy))))

(defun %plan-for-goals (context policy goals remember)
  "Plan GOALS in CONTEXT, consulting the archive when POLICY prefers it.
Sets the context mode to :PLAN and *CURRENT-PLAN*; records a plan episode
when REMEMBER is true. Returns the plan."
  (setf (context-mode context) :plan)
  (let ((plan (plan-consulting-archive context
                                       :goals goals
                                       :archive (policy-prefer-archive policy))))
    (setf *current-plan* plan)
    (when remember
      (record-plan-episode! plan :context-name (context-name context)))
    plan))

(defun %plan-summary (plan)
  "Plist describing PLAN in a step summary, or NIL when there is no plan."
  (when (plan-p plan)
    (list :success (plan-success plan)
          :length (plan-length plan)
          :operators (plan-operators-used plan)
          :remaining (plan-remaining plan)
          :from-procedure (getf (plan-meta plan) :from-procedure))))

(defun %execution-summary (execution)
  "Plist describing EXECUTION in a step summary, or NIL when nothing ran."
  (when (execution-result-p execution)
    (list :success (execution-success execution)
          :mode (execution-mode execution)
          :divergences (execution-divergences execution))))

(defun %run-authorized-plan (context policy plan confirmed remember)
  "Simulate or execute PLAN at the authority of POLICY; return the
EXECUTION-RESULT. Call it only for a plan %AUTHORIZE-EXECUTION allowed;
CONFIRMED is that gate's third value and is the only confirmation the
live run carries, so a risky step the gate did not see is still refused
by the executor. Simulation never changes live facts and never invokes
adapters. Execution invokes adapters only when the policy enables them,
whatever *INVOKE-ADAPTERS* is around the call.
A run that returns leaves the context in the mode it ran in, sets
*LAST-EXECUTION* and, when REMEMBER is true, records an execution
episode. No condition is handled here: what the runner signals reaches
the caller's handlers with the step restarts (RETRY, SKIP,
ABORT-EXECUTION, …) still available. If the run is left by a non-local
exit instead, the context mode is put back as it was. That includes the
runner's own refusal of a plan on the external-action checks the gate
made a moment before, which can only differ if the context changed in
between; no step ran in that case."
  (let ((authority (policy-authority policy))
        (previous (context-mode context))
        (execution nil))
    (unwind-protect
         (setf execution
               (ecase authority
                 (:simulate
                  (setf (context-mode context) :simulate)
                  (simulate-plan plan :context context))
                 (:execute
                  (setf (context-mode context) :execute)
                  (execute-plan! context plan
                                 :confirm confirmed
                                 :adapters (policy-adapters policy)))))
      (unless execution
        (setf (context-mode context) previous)))
    (setf *last-execution* execution)
    (when remember
      (record-execution-episode! execution))
    execution))

(defun %update-knowledge-from-success! (context plan)
  "Assert achieved goal facts into session knowledge memory."
  (let ((facts (context-all-facts context)))
    (dolist (goal (plan-goals plan))
      (when (fact-p goal facts)
        (knowledge-add-fact! goal)))))

(defun %step-signature (steps)
  "What identifies a sequence of plan STEPS: each operator with its bindings."
  (mapcar (lambda (step)
            (list (getf step :operator) (getf step :bindings)))
          steps))

(defun %remember-fresh-plan! (plan context live)
  "Archive the fresh successful PLAN. Return the procedure that was stored
or scored, or NIL when the archive is left as it was.
An archived procedure with the same goal set and the same steps is the
same procedure seen again: a LIVE run gives it one more success, and a
simulation leaves its score alone. Any other plan is stored under a name
no procedure uses, PROC-<context>-<n>, so one goal set never overwrites
another or inherits its successes."
  (let ((twin (find (%step-signature (plan-steps plan))
                    (procedures-for-goals (plan-goals plan))
                    :key (lambda (procedure)
                           (%step-signature (procedure-steps procedure)))
                    :test #'equal)))
    (cond
      ((null twin)
       (remember-procedure-from-plan!
        plan
        :name (loop for n from 1
                    for name = (intern (format nil "PROC-~A-~D"
                                               (or (context-name context)
                                                   'unnamed)
                                               n)
                                       :automa-gp)
                    unless (find-procedure name)
                      return name)))
      (live
       (score-procedure! (procedure-name twin) :success t)))))

(defun %conclude-run (context policy plan execution goals note)
  "Observe EXECUTION of PLAN against GOALS, update what POLICY allows and
return (VALUES STATUS HALT). NOTE is called as (NOTE PHASE &REST PLIST)
to record each phase.
A live run scores the archived procedures it replayed, once; a
simulation leaves the archive scores alone. When the goals hold in the
observed state the step is :DONE: a live run teaches them to knowledge
memory, and a fresh plan is archived when the policy remembers
procedures. Otherwise there is a discrepancy. A live run that changed
the facts before failing ends the step :CONTINUE when the policy
replans, since the next plan starts from a different state; any other
failed run halts with :EXECUTION-FAILED."
  (let* ((live (eq (execution-mode execution) :execute))
         (after (execution-final-state execution))
         (left (differences (state-facts after) goals))
         (achieved (and (execution-success execution) (null left) t))
         (divergences (execution-divergences execution)))
    (funcall note :observe-result
             :success (execution-success execution)
             :remaining left
             :divergences divergences)
    (when live
      (let ((scored (record-procedure-outcome! plan :success achieved)))
        (when scored
          (funcall note :update
                   :procedure-score (procedure-name scored)
                   :success achieved
                   :score (procedure-score scored)))))
    (cond
      (achieved
       ;; Learn only from live execution. Simulation must not write
       ;; durable knowledge for facts the context does not hold.
       (when (and live (policy-learn policy))
         (%update-knowledge-from-success! context plan)
         (funcall note :update :knowledge t :goals goals))
       (when (and (policy-remember-procedure policy)
                  (null (plan-reused-procedure-names plan)))
         (let ((procedure (%remember-fresh-plan! plan context live)))
           (when procedure
             (funcall note :update
                      :procedure t
                      :name (procedure-name procedure)))))
       (values :done :completed))
      (t
       (funcall note :discrepancy :remaining left :divergences divergences)
       (cond
         ((and live
               (policy-replan-on-discrepancy policy)
               (not (state-equal (execution-current-state execution) after)))
          (funcall note :correct :action :replan-next)
          (values :continue nil))
         (t
          (values :halted :execution-failed)))))))

;;; ---------------------------------------------------------------------------
;;; Step and loop
;;; ---------------------------------------------------------------------------

(defun autonomous-step (&key context policy (remember t))
  "Run one controlled autonomy cycle on CONTEXT (default: the session
context) under POLICY (default: the session policy). Returns a summary
plist (also stored in *LAST-AUTONOMY*):
  :STATUS            :DONE, :HALTED, or :CONTINUE when a live run failed
                     after changing facts and another step would replan
  :HALT              why the step ended; NIL under :CONTINUE
  :AUTHORITY         the policy authority
  :AUTHORIZED        whether the gate allowed the plan to run
  :AUTHORIZE-REASON  the gate's reason
  :PHASES            what each phase recorded, in order
  :PLAN :EXECUTION   plists, or NIL when the step got no further
  :GOALS :PENDING-EVENTS  the context after the step
When REMEMBER is true, the plan and the run are recorded as episodes.
Does not loop — see AUTONOMOUS-LOOP."
  (let* ((ctx (%session-context context))
         (pol (ensure-autonomy-policy policy))
         (authority (policy-authority pol))
         (phases nil)
         (plan nil)
         (execution nil)
         (authorized nil)
         (reason nil))
    (flet ((note (phase &rest plist)
             (push (list* :phase phase plist) phases)))
      (multiple-value-bind (status halt)
          (block cycle
            ;; 1. Understand / observe
            (note :observe :snapshot (%observe-context ctx))
            (refresh-working-memory ctx)
            ;; 2. Recognize state / react to events
            (let ((reaction (%react-to-pending-events ctx pol)))
              (when reaction
                (note :recognize
                      :processed (getf reaction :processed)
                      :goals-added (getf reaction :goals-added)
                      :facts-added (getf reaction :facts-added))))
            ;; 3. Determine goals
            (let ((goals (normalize-planning-goals (goals-of ctx))))
              (note :goals :goals goals)
              (when (null goals)
                (return-from cycle (values :halted :no-goals)))
              (when (goals-satisfied-p ctx goals)
                (note :goals-satisfied :goals goals)
                (return-from cycle (values :done :goals-already-satisfied)))
              (when (eq authority :read)
                ;; READ: may observe and report differences, not plan-execute
                (note :evaluate
                      :authority :read
                      :differences (differences (context-all-facts ctx) goals))
                (return-from cycle (values :halted :authority-read)))
              ;; 4. Build plan
              (setf plan (%plan-for-goals ctx pol goals remember))
              (apply #'note :plan (%plan-summary plan))
              ;; 5–6. Evaluate constraints / choose operators (from plan)
              (note :evaluate
                    :authority authority
                    :risky-operators (plan-risky-operators plan ctx)
                    :adapters-requested (policy-adapters pol))
              (note :choose :operators (plan-operators-used plan))
              (unless (plan-success plan)
                (return-from cycle (values :halted :plan-failed)))
              ;; 7. Execute when authorized
              (multiple-value-bind (ok why confirmed)
                  (%authorize-execution pol plan ctx)
                (setf authorized ok
                      reason why)
                (note :authorize :ok ok :reason why)
                (unless ok
                  (return-from cycle (values :halted why)))
                (setf execution
                      (%run-authorized-plan ctx pol plan confirmed remember)))
              (if (eq authority :execute)
                  (note :execute :mode :execute
                                 :success (execution-success execution)
                                 :adapters (policy-adapters pol))
                  (note :execute :mode :simulate
                                 :success (execution-success execution)))
              ;; 8–11. Observe result, detect discrepancies, correct, update
              (%conclude-run ctx pol plan execution goals #'note)))
        (refresh-working-memory ctx)
        (setf *last-autonomy*
              (list :status status
                    :halt halt
                    :authority authority
                    :authorized authorized
                    :authorize-reason reason
                    :phases (nreverse phases)
                    :plan (%plan-summary plan)
                    :execution (%execution-summary execution)
                    :goals (copy-list (goals-of ctx))
                    :pending-events (length (pending-events ctx))))))))

(defun autonomous-loop (&key context policy (max-steps nil) (remember t))
  "Repeat AUTONOMOUS-STEP on CONTEXT until a step ends :DONE or :HALTED,
or until MAX-STEPS steps ran (default: the policy's max-steps). A step
ends :CONTINUE only after a live run that failed part-way; the next step
then replans from the observed facts. The limit must be a positive
integer; anything else is a TYPE-ERROR and no step runs.
Returns the summary of the last step with three keys added (also stored
in *LAST-AUTONOMY*): :ITERATIONS, :RESULTS (every step summary, oldest
first) and :FINAL (the last one). When the limit ends a run that would
continue, :STATUS is :HALTED and :HALT is :MAX-STEPS."
  (let* ((ctx (%session-context context))
         (pol (ensure-autonomy-policy policy))
         (limit (or max-steps (policy-max-steps pol)))
         (results nil))
    (check-type limit (integer 1))
    (loop repeat limit
          do (push (autonomous-step :context ctx :policy pol :remember remember)
                   results)
          while (eq (getf (first results) :status) :continue))
    (let* ((final (first results))
           (summary (copy-list final)))
      (when (eq (getf final :status) :continue)
        (setf (getf summary :status) :halted
              (getf summary :halt) :max-steps))
      (setf *last-autonomy*
            (list* :iterations (length results)
                   :results (reverse results)
                   :final final
                   summary)))))
