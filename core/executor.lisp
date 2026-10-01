;;;; core/executor.lisp — symbolic simulation & execution (Phases 4–5)
;;;;
;;;; Applies operator effects to fact states. SIMULATE works on a copy of the
;;;; facts: it never mutates a context and never reaches an OS adapter.
;;;; EXECUTE updates the live context; when *INVOKE-ADAPTERS* is true, an
;;;; operator's :EXTERNAL spec is handed to adapters/ (Phase 8). MEA and the
;;;; planner still make no OS calls.
;;;;
;;;; Both runners refuse a plan before its first step when they can tell it
;;;; cannot run as recorded (UNKNOWN-OPERATOR, PLAN-REFUSED). After that a
;;;; step failure signals a GP-ERROR inside the Phase-5 restarts (RETRY SKIP
;;;; ABORT-EXECUTION USE-VALUE USE-ALTERNATIVE ASK-USER, plus CONFIRM for a
;;;; step that needs confirmation). The runners use HANDLER-BIND and the
;;;; deliberative strategy — never a catch-all handler.

(in-package #:automa-gp)

(defvar *invoke-adapters* nil
  "When true, EXECUTE may run operator :EXTERNAL adapter specs (Phase 8).
Defined here so the executor can bind it; adapters implement the dispatch.
Default NIL keeps EXECUTE symbolic-only. SIMULATE never invokes adapters.")

(defvar *execution-confirm* nil
  "Optional function (OPERATOR BINDINGS) → true to allow irreversible EXECUTE.
If NIL, irreversible/high-risk steps require :CONFIRM T on GP-RUN.")

(defclass execution-result ()
  ((mode
    :initarg :mode
    :accessor execution-mode
    :documentation ":SIMULATE or :EXECUTE")
   (success
    :initarg :success
    :accessor execution-success
    :initform nil
    :documentation "True when the run was not aborted and the plan's goals
hold in the final state.")
   (steps
    :initarg :steps
    :accessor execution-steps
    :initform nil
    :documentation "Per-step result plists.")
   (current-state
    :initarg :current-state
    :accessor execution-current-state
    :initform nil
    :documentation "CURRENT state the run started from.")
   (expected-state
    :initarg :expected-state
    :accessor execution-expected-state
    :initform nil
    :documentation "EXPECTED state: the plan's symbolic final facts.")
   (final-state
    :initarg :final-state
    :accessor execution-final-state
    :initform nil
    :documentation "SIMULATED or OBSERVED final state.")
   (divergences
    :initarg :divergences
    :accessor execution-divergences
    :initform nil
    :documentation "COMPARE-STATES of EXPECTED and FINAL, for a failed run too.")
   (plan
    :initarg :plan
    :accessor execution-plan
    :initform nil)
   (strategy-events
    :initarg :strategy-events
    :accessor execution-strategy-events
    :initform nil
    :documentation "Copy of deliberative strategy events from the run.")
   (meta
    :initarg :meta
    :accessor execution-meta
    :initform nil))
  (:documentation "Record of a symbolic simulate/execute pass."))

(defun execution-result-p (object)
  "True if OBJECT is an EXECUTION-RESULT."
  (typep object 'execution-result))

(define-condition plan-refused (gp-error)
  ((reason
    :initarg :reason
    :reader plan-refused-reason
    :documentation ":EXTERNAL-MISMATCH, :EXTERNAL-UNSUPPORTED or
:INHERITED-RETRACTION.")
   (facts
    :initarg :facts
    :reader plan-refused-facts
    :initform nil
    :documentation "For :INHERITED-RETRACTION, the inherited facts the
refused work would retract."))
  (:report (lambda (c stream)
             (case (plan-refused-reason c)
               (:external-mismatch
                (write-string
                 "The external action no longer matches the plan." stream))
               (:external-unsupported
                (write-string
                 "The facts no longer support the external action." stream))
               (:inherited-retraction
                (format stream
                        "Context ~A cannot retract ~{~S~^, ~}: it only ~
                         inherits ~:[that fact~;those facts~]."
                        (let ((context (gp-condition-context c)))
                          (if context (context-name context) '?))
                        (plan-refused-facts c)
                        (rest (plan-refused-facts c))))
               (otherwise
                (format stream "The plan is refused (~S)."
                        (plan-refused-reason c))))))
  (:documentation "A plan runner will not do what the plan asks.
Signalled before the refused work changes a fact or reaches an adapter:
for the whole plan before its first step, or for one step under the step
restarts when recovery from an earlier failure led somewhere the pre-flight
checks could not foresee. PLAN-REFUSED-REASON says why."))

(defun expected-state-from-plan (plan)
  "EXPECTED state = plan's symbolic final fact list."
  (when (plan-p plan)
    (make-state (plan-final-state plan) :source :plan :kind :expected)))

(defun operator-needs-confirmation-p (operator)
  "True if OPERATOR is irreversible or high-risk."
  (or (not (operator-reversible operator))
      (member (operator-risk operator) '(:high :critical) :test #'eq)))

(defun ensure-confirmed (operator bindings &key confirm mode context)
  "Signal CONFIRMATION-REQUIRED with a CONFIRM restart unless already allowed."
  (when (operator-needs-confirmation-p operator)
    (let ((ok (or confirm
                  (and *execution-confirm*
                       (funcall *execution-confirm* operator bindings)))))
      (unless ok
        (restart-case
            (error 'confirmation-required
                   :operator operator
                   :bindings bindings
                   :mode mode
                   :context context
                   :reason (if (not (operator-reversible operator))
                               :irreversible
                               :high-risk))
          (:confirm ()
            :report "Confirm and proceed with this operator"
            (record-strategy-event :confirm
                                   :operator (operator-name operator))
            t))))))

(defun check-operator-preconditions (facts operator bindings)
  "Return missing precondition facts, or NIL if all hold."
  (precondition-subgoals operator bindings facts))

(defun lookup-operator (name &key context operators)
  "Find OPERATOR by NAME from CONTEXT or OPERATORS, or NIL."
  (or (when context (find-operator context name))
      (when operators
        (find name operators :key #'operator-name :test #'equal))))

(defun resolve-operator (name &key context operators)
  "Find OPERATOR by NAME from CONTEXT or OPERATORS list.
Signals UNKNOWN-OPERATOR when there is none."
  (or (lookup-operator name :context context :operators operators)
      (error 'unknown-operator :name name :context context)))

(defun bindings-from-step (step)
  "The :BINDINGS recorded on plan STEP, or *NO-BINDINGS* when it has none."
  (or (getf step :bindings) *no-bindings*))

;;; --- Single-step core (signals conditions; no plan-level catch) ---

(defun %apply-operator-checked (facts operator bindings &key mode context)
  "Check preconditions and apply OPERATOR to FACTS.
Returns (VALUES NEW-FACTS EXTENDED-BINDINGS). Signals PRECONDITION-FAILURE."
  (let* ((b (extend-bindings-from-state
             (operator-preconditions operator) bindings facts))
         (missing (check-operator-preconditions facts operator b)))
    (when missing
      (error 'precondition-failure
             :operator operator
             :missing missing
             :bindings b
             :mode mode
             :context context))
    (values (transition-facts facts operator b) b)))

(defun project-stored-effects (facts step &key (status :projected))
  "Apply the :ADDS and :DELETES recorded on STEP. No adapters.
Returns (VALUES NEW-FACTS STEP-RESULT)."
  (let ((new (apply-stored-effects facts (getf step :adds) (getf step :deletes))))
    (values new
            (make-step-result (getf step :operator)
                              (bindings-from-step step)
                              facts new
                              :status status))))

(defun apply-recorded-step (facts step &key mode context)
  "Apply STEP's recorded effects after its recorded preconditions hold.
Signals PRECONDITION-FAILURE when one is missing. Does not invoke adapters.
Returns (VALUES NEW-FACTS STEP-RESULT) with status :RECORDED."
  (let ((missing (missing-stored-preconditions step facts)))
    (when missing
      (error 'precondition-failure
             :operator (getf step :operator)
             :missing missing
             :bindings (bindings-from-step step)
             :step step
             :mode mode
             :context context))
    (project-stored-effects facts step :status :recorded)))

(defun %recorded-step-p (step)
  "True when STEP carries enough of a record to run without its operator."
  (and (getf step :effects-stored)
       (or (getf step :effects-only)
           (and (getf step :stored-apply)
                (getf step :preconditions-stored)))))

(defun %operator-for-stored-step (step)
  "Stand-in operator carrying the risk recorded on STEP, for confirmation.
A step recorded before :REVERSIBLE was stored counts as reversible."
  (make-operator :name (or (getf step :operator) 'stored-effects)
                 :risk (or (getf step :risk) :low)
                 :reversible (and (getf step :reversible t) t)))

(defun %external-action-withheld (result operator)
  "Mark RESULT when a requested adapter action is not run.
An effects-only step no longer has its preconditions, so the symbolic
leftovers apply and the adapter is not invoked. When adapters are off,
RESULT is unchanged."
  (if (and *invoke-adapters*
           (operator-p operator)
           (operator-external-spec operator))
      (let ((copy (copy-list result)))
        (setf (getf copy :external) :withheld)
        copy)
      result))

(defun project-operator-effects (facts operator bindings)
  "Apply OPERATOR's symbolic add and delete lists without checking
preconditions and without invoking adapters.
Returns (VALUES NEW-FACTS STEP-RESULT) with status :PROJECTED.
Used when a stored step's goal already holds but its effects are not yet
in the state. Variables still open are bound from FACTS through the
preconditions and the add list, as an ordinary application binds them. A
variable that occurs only in the delete list stays open and retracts
nothing, exactly as in APPLY-OPERATOR: a projection never retracts a fact
an ordinary application of OPERATOR would keep."
  (let* ((patterns (append (operator-preconditions operator)
                           (operator-add-list operator)))
         (b (extend-bindings-from-state patterns bindings facts))
         (new (apply-operator facts operator b)))
    (values new (make-step-result operator b facts new :status :projected))))

(defun simulate-operator (facts operator bindings &key mode context)
  "Apply OPERATOR symbolically to FACTS.
Returns (VALUES NEW-FACTS STEP-RESULT). Signals GP-ERROR on failure."
  (multiple-value-bind (new b)
      (%apply-operator-checked facts operator bindings
                               :mode (or mode :simulate)
                               :context context)
    (values new (make-step-result operator b facts new :status :ok))))

;;; --- Committing to a live context ---

(defun %inherited-facts (context)
  "Facts CONTEXT sees only because an ancestor holds them."
  (let ((parent (context-parent context)))
    (when parent
      (context-all-facts parent))))

(defun %ensure-facts-committable (context facts &key operator bindings step)
  "Signal PLAN-REFUSED when FACTS drops a fact CONTEXT inherits.
A context stores its own facts and sees its ancestors' on top; it has no
way to record that an inherited fact stopped holding. Writing FACTS anyway
would leave the retracted fact visible beside whatever replaced it."
  (let ((lost (remove-if (lambda (fact) (fact-p fact facts))
                         (%inherited-facts context))))
    (when lost
      (error 'plan-refused
             :reason :inherited-retraction
             :facts lost
             :operator operator
             :bindings bindings
             :step step
             :mode :execute
             :context context))))

(defun commit-facts-to-context! (context facts)
  "Make FACTS the facts visible in CONTEXT by rewriting its local facts.
A fact CONTEXT inherits stays inherited: it is stored locally only when it
already was. FACTS that drops an inherited fact signals PLAN-REFUSED before
anything is written."
  (check-type facts list "a fact list")
  (%ensure-facts-committable context facts)
  (let ((inherited (%inherited-facts context))
        (local (context-facts context)))
    (setf (context-facts context)
          (loop for fact in facts
                unless (and (fact-p fact inherited)
                            (not (fact-p fact local)))
                  collect fact)))
  context)

(defun execute-operator! (context operator bindings &key confirm)
  "EXECUTE OPERATOR against live CONTEXT facts.
The outcome is computed first: a missing precondition signals
PRECONDITION-FAILURE, and an outcome CONTEXT cannot hold signals
PLAN-REFUSED, before anyone is asked to confirm. An operator that needs
confirmation then signals CONFIRMATION-REQUIRED with a CONFIRM restart
unless CONFIRM or *EXECUTION-CONFIRM* allows it. Only then, when
*INVOKE-ADAPTERS* is true and OPERATOR has :EXTERNAL meta, the OS adapter
runs (Phase 8); the symbolic effects are committed after it succeeds.
Returns (VALUES NEW-FACTS STEP-RESULT). Signals GP-ERROR on failure."
  (let ((facts (context-all-facts context)))
    (multiple-value-bind (new b)
        (%apply-operator-checked facts operator bindings
                                 :mode :execute
                                 :context context)
      (%ensure-facts-committable context new :operator operator :bindings b)
      (ensure-confirmed operator b
                        :confirm confirm
                        :mode :execute
                        :context context)
      (let ((external (maybe-invoke-external! operator b)))
        (commit-facts-to-context! context new)
        (values new (make-step-result operator b facts new
                                      :status :executed
                                      :external external))))))

;;; --- Plan steps ---

(defun alternatives-for-step (step operators)
  "Other operators that achieve the step's goal (excluding the planned one)."
  (let* ((goal (getf step :goal))
         (planned (getf step :operator)))
    (when (and goal operators)
      (loop for pair in (operators-for-goal goal operators)
            for op = (car pair)
            unless (equal (operator-name op) planned)
              collect op))))

(defun %resolve-plan-steps (plan &key context operators)
  "Pair each step of PLAN with the operator that runs it: (STEP . OPERATOR).
OPERATOR is NIL for a step that runs from its recorded effects because its
operator is gone. A step with neither signals UNKNOWN-OPERATOR here, so a
runner refuses the plan before its first step instead of failing midway
with the earlier steps already applied."
  (loop for step in (plan-steps plan)
        for name = (getf step :operator)
        for operator = (lookup-operator name
                                        :context context
                                        :operators operators)
        unless (or (operator-p operator) (%recorded-step-p step))
          do (error 'unknown-operator :name name :step step :context context)
        collect (cons step operator)))

(defun %apply-plan-step (facts step operator &key (mode :simulate) context)
  "Symbolic outcome of plan STEP on FACTS. Commits nothing, runs no adapter.
OPERATOR is the live operator for STEP, or NIL when STEP runs from its
record. An :EFFECTS-ONLY step applies its add and delete lists without
checking preconditions; any other step checks them first and signals
PRECONDITION-FAILURE. Returns (VALUES NEW-FACTS STEP-RESULT)."
  (cond
    ((operator-p operator)
     (if (getf step :effects-only)
         (project-operator-effects facts operator (bindings-from-step step))
         (simulate-operator facts operator (bindings-from-step step)
                            :mode mode
                            :context context)))
    ((getf step :stored-apply)
     (apply-recorded-step facts step :mode mode :context context))
    (t
     (project-stored-effects facts step))))

(defun %execute-plan-step! (context step operator &key confirm)
  "EXECUTE plan STEP against live CONTEXT, in the order EXECUTE-OPERATOR!
documents: outcome, confirmation, adapter, commit. Only an ordinary step
reaches an adapter. An :EFFECTS-ONLY step and a step that runs from its
record apply symbolic effects only, and are confirmed against the risk of
the operator, or the risk recorded on the step when the operator is gone.
Returns (VALUES NEW-FACTS STEP-RESULT)."
  (if (and (operator-p operator) (not (getf step :effects-only)))
      (execute-operator! context operator (bindings-from-step step)
                         :confirm confirm)
      (let ((bindings (bindings-from-step step)))
        (multiple-value-bind (new result)
            (%apply-plan-step (context-all-facts context) step operator
                              :mode :execute
                              :context context)
          (%ensure-facts-committable context new
                                     :operator (or operator
                                                   (getf step :operator))
                                     :bindings bindings
                                     :step step)
          (ensure-confirmed (if (operator-p operator)
                                operator
                                (%operator-for-stored-step step))
                            bindings
                            :confirm confirm
                            :mode :execute
                            :context context)
          (commit-facts-to-context! context new)
          (values new (%external-action-withheld result operator))))))

;;; --- Pre-flight refusals ---

(defun %refuse-unrunnable-external-actions (plan &key context operators adapters)
  "Signal PLAN-REFUSED unless PLAN's external actions can run as recorded.
:EXTERNAL-MISMATCH when the recorded actions no longer ground the same way,
and also, when ADAPTERS are requested, for a plan that never recorded them.
:EXTERNAL-UNSUPPORTED when the facts, counting the effects of earlier
steps, no longer reach an action that would be handed to an adapter.
The two checks belong to the adapter layer and invoke nothing."
  (when (and (or adapters
                 (getf (plan-meta plan) :external-actions-recorded))
             (not (plan-external-actions-match-p plan
                                                 :context context
                                                 :operators operators)))
    (error 'plan-refused :reason :external-mismatch :context context))
  (unless (plan-external-actions-supported-p plan
                                             :context context
                                             :operators operators)
    (error 'plan-refused :reason :external-unsupported :context context)))

(defun %refuse-inherited-retractions (context steps)
  "Signal PLAN-REFUSED when a step of STEPS would retract a fact CONTEXT
inherits. STEPS comes from %RESOLVE-PLAN-STEPS. The steps are applied to a
copy of the live facts, so nothing changes. The walk ends at the first
step that fails: what follows depends on the restart chosen there, and
%EXECUTE-PLAN-STEP! checks each step again before it commits."
  (when (context-parent context)
    (let ((facts (context-all-facts context)))
      (loop for (step . operator) in steps
            do (setf facts
                     (handler-case
                         (values (%apply-plan-step facts step operator
                                                   :mode :execute
                                                   :context context))
                       (gp-error () (return))))
               (%ensure-facts-committable context facts
                                          :operator (or operator
                                                        (getf step :operator))
                                          :bindings (bindings-from-step step)
                                          :step step)))))

;;; --- Plan runners ---

(defun %run-plan-steps (steps facts run-step &key mode context operators)
  "Run STEPS in order, each under the Phase-5 step restarts.
STEPS comes from %RESOLVE-PLAN-STEPS. RUN-STEP is called with (FACTS STEP
OPERATOR) and returns (VALUES NEW-FACTS STEP-RESULT); OPERATOR is the
alternative chosen through USE-ALTERNATIVE while one is bound. A GP-ERROR
goes to the deliberative strategy and then, by default, aborts the run.
In :EXECUTE mode a USE-VALUE fact list is committed to CONTEXT, and the
trace records an :ACTION only for a step that actually ran.
Returns (VALUES FINAL-FACTS STEP-RESULTS ABORTED-P)."
  (let ((results nil)
        (aborted nil))
    (handler-bind ((gp-error #'plan-runner-condition-handler))
      (loop for (step . operator) in steps
            do (trace-record :selected-operator
                             :operator (getf step :operator)
                             :goal (getf step :goal)
                             :bindings (getf step :bindings))
               (multiple-value-bind (new result flag)
                   (call-with-gp-restarts
                    (lambda ()
                      (funcall run-step facts step
                               (or *gp-alternative-operator* operator)))
                    :operator (or operator (getf step :operator))
                    :bindings (bindings-from-step step)
                    :alternatives (alternatives-for-step step operators)
                    :mode mode
                    :context context
                    :step step
                    :facts-on-skip facts)
                 (check-type new list "a fact list")
                 (when (eq mode :execute)
                   (case flag
                     ((nil)
                      (trace-record :action
                                    :operator (getf result :operator)
                                    :bindings (getf result :bindings)))
                     (:use-value
                      (commit-facts-to-context! context new))))
                 (setf facts new)
                 (push result results)
                 (trace-record :execution-step
                               :mode mode
                               :operator (getf result :operator)
                               :status (getf result :status)
                               :flag flag)
                 (trace-record :result :status (getf result :status))
                 (when (eq flag :abort)
                   (setf aborted t)
                   (return)))))
    (values facts (nreverse results) aborted)))

(defun %execution-result (mode plan current final step-results aborted meta)
  "Close the trace of a run and build its EXECUTION-RESULT.
CURRENT and FINAL are the states the run started from and ended in. The
run succeeded when it was not aborted and the plan's goals hold in FINAL.
Divergences compare the plan's expected state with FINAL either way."
  (let ((expected (expected-state-from-plan plan))
        (success (and (not aborted)
                      (null (differences (state-facts final)
                                         (plan-goals plan))))))
    (trace-record :execution-complete :mode mode :success success)
    (make-instance 'execution-result
                   :mode mode
                   :success success
                   :steps step-results
                   :current-state current
                   :expected-state expected
                   :final-state final
                   :divergences (compare-states expected final)
                   :plan plan
                   :strategy-events (strategy-events-of)
                   :meta (append meta (list :trace *current-trace*)))))

(defun simulate-plan (plan &key context operators
                             (initial-facts nil initial-p))
  "Simulate PLAN steps without mutating any context or invoking an adapter.
Records a deliberative execution trace. Step restarts as in Phase 5.
The simulation starts from the facts visible in CONTEXT now, the state an
execute would start from, so a plan the live facts no longer support fails
here too. Without CONTEXT it starts from the plan's recorded initial
state. INITIAL-FACTS, when supplied, replaces either.
A plan that cannot run as recorded is refused before any simulated step:
PLAN-REFUSED when a recorded external action no longer matches, or when
the facts of CONTEXT no longer support an action that would be handed to
an adapter, including through earlier steps; UNKNOWN-OPERATOR when a step
names an operator that is gone and carries no record to run from."
  (unless (plan-p plan)
    (error "SIMULATE-PLAN requires a PLAN, got ~S" plan))
  (%refuse-unrunnable-external-actions plan
                                       :context context
                                       :operators operators)
  (let* ((ops (or operators
                  (when context (context-planning-operators context))
                  (getf (plan-meta plan) :operators)))
         (steps (%resolve-plan-steps plan :context context :operators ops)))
    (multiple-value-bind (start source)
        (cond
          (initial-p (values initial-facts :initial-facts))
          (context (values (context-all-facts context) (context-name context)))
          (t (values (plan-initial-state plan) :plan)))
      (with-trace (:simulate :context-name
                             (or (and context (context-name context))
                                 (getf (plan-meta plan) :context)))
        (when context
          (trace-record :context :name (context-name context)))
        (trace-record :goals :goals (plan-goals plan))
        (trace-record :state :facts (copy-list start))
        (multiple-value-bind (facts step-results aborted)
            (%run-plan-steps steps (copy-list start)
                             (lambda (facts step operator)
                               (%apply-plan-step facts step operator
                                                 :mode :simulate
                                                 :context context))
                             :mode :simulate
                             :context context
                             :operators ops)
          (%execution-result
           :simulate plan
           (make-state start :kind :current :source source)
           (make-state facts :kind :simulated :source :simulate)
           step-results aborted
           (list :note "symbolic simulation; restarts available; no adapters")))))))

(defun call-with-execution-mode (context mode thunk)
  "Set CONTEXT's mode to MODE and call THUNK, returning its values.
The mode stays MODE when THUNK returns. When THUNK is left any other way
(an error nobody handled, a restart taken further out, a THROW), the mode
from before this call is restored, so a refused or abandoned run leaves the
mode unchanged. Nothing is caught and nothing unwinds before the handlers
have run: the restarts the plan runners establish stay available to a
handler bound around this call."
  (let ((previous (context-mode context))
        (returned nil))
    (setf (context-mode context) mode)
    (unwind-protect
         (multiple-value-prog1 (funcall thunk)
           (setf returned t))
      (unless returned
        (setf (context-mode context) previous)))))

(defun execute-plan! (context plan &key confirm (adapters nil adapters-p))
  "EXECUTE PLAN steps against live CONTEXT. Mutates context facts.
Records a deliberative execution trace.
When ADAPTERS is true, bind *INVOKE-ADAPTERS* for this run so operators with
:EXTERNAL meta may perform OS side effects (Phase 8). Default is the
current *INVOKE-ADAPTERS* value (normally NIL → symbolic only).
A plan that cannot run as recorded is refused before any fact changes, so
no step is applied and no adapter runs. PLAN-REFUSED is signalled when a
recorded external action no longer matches, whether or not adapters were
requested (a plan that never recorded its actions is refused only when
they were); when the facts no longer support an action that would be
handed to an adapter, including through earlier steps; and when a step
would retract a fact CONTEXT only inherits from an ancestor, which a
context cannot record. UNKNOWN-OPERATOR is signalled when a step names an
operator that is gone and carries no record to run from.
An effects-only step, whose preconditions no longer hold, applies the
symbolic leftovers and does not invoke the adapter. That step is marked
:EXTERNAL :WITHHELD when adapters were requested."
  (unless (plan-p plan)
    (error "EXECUTE-PLAN! requires a PLAN, got ~S" plan))
  (let* ((*invoke-adapters* (if adapters-p adapters *invoke-adapters*))
         (ops (context-planning-operators context)))
    (%refuse-unrunnable-external-actions plan
                                         :context context
                                         :adapters *invoke-adapters*)
    (let ((steps (%resolve-plan-steps plan :context context)))
      (%refuse-inherited-retractions context steps)
      (with-trace (:execute :context-name (context-name context))
        (trace-record :context :name (context-name context))
        (trace-record :goals :goals (plan-goals plan))
        (trace-record :state :facts (context-all-facts context))
        (let ((current (state-from-context context :kind :current)))
          (multiple-value-bind (facts step-results aborted)
              (%run-plan-steps steps (context-all-facts context)
                               (lambda (facts step operator)
                                 (declare (ignore facts))
                                 (%execute-plan-step! context step operator
                                                      :confirm confirm))
                               :mode :execute
                               :context context
                               :operators ops)
            (declare (ignore facts))
            (%execution-result
             :execute plan
             current
             (state-from-context context :kind :observed)
             step-results aborted
             (list :note (if *invoke-adapters*
                             "execute with adapters enabled"
                             "symbolic execute; adapters off")
                   :adapters *invoke-adapters*))))))))
