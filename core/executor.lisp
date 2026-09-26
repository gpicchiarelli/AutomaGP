;;;; core/executor.lisp — symbolic simulation & execution (Phases 4–5)
;;;;
;;;; Applies operator effects to fact states. SIMULATE never mutates the live
;;;; context. EXECUTE updates context facts only — no macOS/adapters (Phase 8).
;;;;
;;;; Phase 5: step failures signal GP-ERROR with restarts (RETRY SKIP
;;;; ABORT-EXECUTION USE-VALUE USE-ALTERNATIVE ASK-USER). Plan runners use
;;;; HANDLER-BIND + deliberative strategy — not bare catch-all handlers.

(in-package #:automa-gp)

(defvar *last-execution* nil
  "Last EXECUTION-RESULT from GP-SIMULATE or GP-RUN.")

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
    :initform nil)
   (steps
    :initarg :steps
    :accessor execution-steps
    :initform nil
    :documentation "Per-step result plists.")
   (current-state
    :initarg :current-state
    :accessor execution-current-state
    :initform nil
    :documentation "CURRENT state before the run.")
   (expected-state
    :initarg :expected-state
    :accessor execution-expected-state
    :initform nil
    :documentation "EXPECTED state from the plan, if any.")
   (final-state
    :initarg :final-state
    :accessor execution-final-state
    :initform nil
    :documentation "SIMULATED or OBSERVED final state.")
   (divergences
    :initarg :divergences
    :accessor execution-divergences
    :initform nil
    :documentation "Compare EXPECTED vs FINAL, if both present.")
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
  (typep object 'execution-result))

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

(defun resolve-operator (name &key context operators)
  "Find OPERATOR by NAME from CONTEXT or OPERATORS list."
  (or (when context (find-operator context name))
      (when operators
        (find name operators :key #'operator-name :test #'equal))
      (error 'unknown-operator :name name)))

(defun bindings-from-step (step)
  "Rebuild bindings from a plan step's :BINDINGS."
  (let ((b (getf step :bindings)))
    (cond
      ((null b) *no-bindings*)
      ((eq b *no-bindings*) *no-bindings*)
      (t b))))

;;; --- Single-step core (signals conditions; no plan-level catch) ---

(defun %apply-operator-checked (facts operator bindings &key mode context)
  "Check preconditions and apply OPERATOR. Signals PRECONDITION-FAILURE."
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
    (let ((new (transition-facts facts operator b)))
      (values new b))))

(defun simulate-operator (facts operator bindings &key mode context)
  "Apply OPERATOR symbolically to FACTS.
Returns (VALUES NEW-FACTS STEP-RESULT). Signals GP-ERROR on failure."
  (multiple-value-bind (new b)
      (%apply-operator-checked facts operator bindings
                               :mode (or mode :simulate)
                               :context context)
    (values new (make-step-result operator b facts new :status :ok))))

(defun execute-operator! (context operator bindings &key confirm)
  "EXECUTE OPERATOR against live CONTEXT facts (symbolic only).
Returns (VALUES NEW-FACTS STEP-RESULT). Signals GP-ERROR on failure.
Establishes CONFIRM restart for irreversible ops when confirmation needed."
  (ensure-confirmed operator bindings
                    :confirm confirm
                    :mode :execute
                    :context context)
  (let ((facts (context-all-facts context)))
    (multiple-value-bind (new b)
        (%apply-operator-checked facts operator bindings
                                 :mode :execute
                                 :context context)
      (commit-facts-to-context! context new)
      (values new (make-step-result operator b facts new :status :executed)))))

(defun commit-facts-to-context! (context facts)
  "Set CONTEXT local facts to FACTS (Phase-4: write full visible set locally)."
  (setf (context-facts context) (copy-list facts))
  context)

(defun alternatives-for-step (step operators)
  "Other operators that achieve the step's goal (excluding the planned one)."
  (let* ((goal (getf step :goal))
         (planned (getf step :operator)))
    (when (and goal operators)
      (loop for pair in (operators-for-goal goal operators)
            for op = (car pair)
            unless (equal (operator-name op) planned)
              collect op))))

(defun run-step-with-restarts (thunk &key operator bindings alternatives
                                       mode context step facts)
  "Wrap THUNK with GP restarts and return (VALUES FACTS RESULT FLAG)."
  (call-with-gp-restarts
   thunk
   :operator operator
   :bindings bindings
   :alternatives alternatives
   :mode mode
   :context context
   :step step
   :facts-on-skip facts))

;;; --- Plan runners ---

(defun simulate-plan (plan &key context operators
                             (initial-facts nil initial-p))
  "Simulate PLAN steps without mutating any context.
Records a deliberative execution trace. Step restarts as in Phase 5."
  (unless (plan-p plan)
    (error "SIMULATE-PLAN requires a PLAN, got ~S" plan))
  (with-trace (:simulate :context-name
                         (or (and context (context-name context))
                             (getf (plan-meta plan) :context)))
    (when context
      (trace-record :context :name (context-name context)))
    (trace-record :goals :goals (plan-goals plan))
    (trace-record :state :facts (copy-list (if initial-p
                                               initial-facts
                                               (plan-initial-state plan))))
    (let* ((ops (or operators
                    (when context (context-planning-operators context))
                    (getf (plan-meta plan) :operators)))
           (facts (copy-list (if initial-p
                                 initial-facts
                                 (plan-initial-state plan))))
           (current (make-state facts :kind :current :source :simulate))
           (expected (expected-state-from-plan plan))
           (step-results nil)
           (ok t)
           (aborted nil))
      (handler-bind ((gp-error #'plan-runner-condition-handler))
        (dolist (step (plan-steps plan))
          (let* ((op0 (resolve-operator (getf step :operator)
                                        :context context
                                        :operators ops))
                 (b0 (bindings-from-step step))
                 (alts (alternatives-for-step step ops)))
            (trace-record :selected-operator
                          :operator (operator-name op0)
                          :goal (getf step :goal)
                          :bindings (getf step :bindings))
            (multiple-value-bind (new result flag)
                (run-step-with-restarts
                 (lambda ()
                   (let ((op (or *gp-alternative-operator* op0)))
                     (simulate-operator facts op b0
                                        :mode :simulate
                                        :context context)))
                 :operator op0
                 :bindings b0
                 :alternatives alts
                 :mode :simulate
                 :context context
                 :step step
                 :facts facts)
              (setf facts (or new facts))
              (push result step-results)
              (trace-record :execution-step
                            :mode :simulate
                            :operator (getf result :operator)
                            :status (getf result :status)
                            :flag flag)
              (trace-record :result :status (getf result :status))
              (when (eq flag :abort)
                (setf ok nil aborted t)
                (return))
              (when (and (null flag)
                         (not (member (getf result :status)
                                      '(:ok :skipped :use-value :executed))))
                (setf ok nil)
                (return))
              (when (eq flag :skip) nil)))))
      (when aborted (setf ok nil))
      (when (and expected ok)
        (unless (null (differences facts (plan-goals plan)))
          (setf ok nil)))
      (let* ((final (make-state facts :kind :simulated :source :simulate))
             (div (when (and expected ok)
                    (compare-states expected final))))
        (trace-record :execution-complete :mode :simulate :success ok)
        (make-instance 'execution-result
                       :mode :simulate
                       :success ok
                       :steps (nreverse step-results)
                       :current-state current
                       :expected-state expected
                       :final-state final
                       :divergences div
                       :plan plan
                       :strategy-events (strategy-events-of)
                       :meta (list :note "symbolic simulation; restarts available; no adapters"
                                   :trace *current-trace*))))))

(defun execute-plan! (context plan &key confirm)
  "EXECUTE PLAN steps against live CONTEXT. Mutates context facts.
Records a deliberative execution trace."
  (unless (plan-p plan)
    (error "EXECUTE-PLAN! requires a PLAN, got ~S" plan))
  (with-trace (:execute :context-name (context-name context))
    (trace-record :context :name (context-name context))
    (trace-record :goals :goals (plan-goals plan))
    (trace-record :state :facts (copy-list (context-all-facts context)))
    (let* ((ops (context-planning-operators context))
           (current (state-from-context context :kind :current))
           (expected (expected-state-from-plan plan))
           (step-results nil)
           (ok t)
           (aborted nil)
           (facts (context-all-facts context)))
      (handler-bind ((gp-error #'plan-runner-condition-handler))
        (dolist (step (plan-steps plan))
          (let* ((op0 (resolve-operator (getf step :operator) :context context))
                 (b0 (bindings-from-step step))
                 (alts (alternatives-for-step step ops)))
            (trace-record :selected-operator
                          :operator (operator-name op0)
                          :goal (getf step :goal)
                          :bindings (getf step :bindings))
            (multiple-value-bind (new result flag)
                (run-step-with-restarts
                 (lambda ()
                   (let ((op (or *gp-alternative-operator* op0)))
                     (execute-operator! context op b0 :confirm confirm)))
                 :operator op0
                 :bindings b0
                 :alternatives alts
                 :mode :execute
                 :context context
                 :step step
                 :facts facts)
              (setf facts (or new (context-all-facts context)))
              (push result step-results)
              (trace-record :action
                            :operator (getf result :operator)
                            :bindings (getf result :bindings))
              (trace-record :execution-step
                            :mode :execute
                            :operator (getf result :operator)
                            :status (getf result :status)
                            :flag flag)
              (trace-record :result :status (getf result :status))
              (cond
                ((eq flag :abort)
                 (setf ok nil aborted t)
                 (return))
                ((eq flag :skip) nil)
                ((eq flag :use-value)
                 (commit-facts-to-context! context facts))
                (t nil))))))
      (when aborted (setf ok nil))
      (when (and expected ok)
        (unless (null (differences (context-all-facts context) (plan-goals plan)))
          (setf ok nil)))
      (let* ((observed (state-from-context context :kind :observed))
             (div (when (and expected ok)
                    (compare-states expected observed))))
        (trace-record :execution-complete :mode :execute :success ok)
        (make-instance 'execution-result
                       :mode :execute
                       :success ok
                       :steps (nreverse step-results)
                       :current-state current
                       :expected-state expected
                       :final-state observed
                       :divergences div
                       :plan plan
                       :strategy-events (strategy-events-of)
                       :meta (list :note "symbolic execute; restarts available; no adapters"
                                   :trace *current-trace*))))))
