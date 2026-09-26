;;;; core/executor.lisp — symbolic simulation & execution (Phase 4)
;;;;
;;;; Applies operator effects to fact states. SIMULATE never mutates the live
;;;; context. EXECUTE updates context facts only — no macOS/adapters (Phase 8).
;;;;
;;;; State kinds: CURRENT (live) → SIMULATED / EXPECTED / OBSERVED.

(in-package #:automa-gp)

(defvar *last-execution* nil
  "Last EXECUTION-RESULT from GP-SIMULATE or GP-RUN.")

(defvar *execution-confirm* nil
  "Optional function (OPERATOR BINDINGS) → true to allow irreversible EXECUTE.
If NIL, irreversible/high-risk steps require :CONFIRM T on GP-RUN.")

(define-condition precondition-failure (error)
  ((operator :initarg :operator :reader precondition-failure-operator)
   (missing :initarg :missing :reader precondition-failure-missing)
   (bindings :initarg :bindings :reader precondition-failure-bindings))
  (:report (lambda (c stream)
             (format stream "Preconditions not satisfied for ~A; missing ~S"
                     (operator-name (precondition-failure-operator c))
                     (precondition-failure-missing c)))))

(define-condition confirmation-required (error)
  ((operator :initarg :operator :reader confirmation-required-operator)
   (bindings :initarg :bindings :reader confirmation-required-bindings)
   (reason :initarg :reason :reader confirmation-required-reason))
  (:report (lambda (c stream)
             (format stream "Confirmation required to EXECUTE ~A (~A)"
                     (operator-name (confirmation-required-operator c))
                     (confirmation-required-reason c)))))

(define-condition unknown-operator (error)
  ((name :initarg :name :reader unknown-operator-name))
  (:report (lambda (c stream)
             (format stream "Unknown operator ~S" (unknown-operator-name c)))))

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

(defun ensure-confirmed (operator bindings &key confirm)
  "Signal CONFIRMATION-REQUIRED unless CONFIRM or *EXECUTION-CONFIRM* allows."
  (when (operator-needs-confirmation-p operator)
    (let ((ok (or confirm
                  (and *execution-confirm*
                       (funcall *execution-confirm* operator bindings)))))
      (unless ok
        (error 'confirmation-required
               :operator operator
               :bindings bindings
               :reason (if (not (operator-reversible operator))
                           :irreversible
                           :high-risk))))))

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

(defun make-step-result (operator bindings before after &key status missing)
  (list :operator (operator-name operator)
        :bindings (if (eq bindings *no-bindings*) nil bindings)
        :status status
        :missing missing
        :before (copy-list before)
        :after (copy-list after)))

;;; --- Simulation (no live mutation) ---

(defun simulate-operator (facts operator bindings)
  "Apply OPERATOR symbolically to FACTS.
Returns (VALUES NEW-FACTS STEP-RESULT). Signals PRECONDITION-FAILURE."
  (let* ((b (extend-bindings-from-state
             (operator-preconditions operator) bindings facts))
         (missing (check-operator-preconditions facts operator b)))
    (when missing
      (error 'precondition-failure
             :operator operator :missing missing :bindings b))
    (let ((new (transition-facts facts operator b)))
      (values new (make-step-result operator b facts new :status :ok)))))

(defun simulate-plan (plan &key context operators
                             (initial-facts nil initial-p))
  "Simulate PLAN steps without mutating any context.
Returns an EXECUTION-RESULT with mode :SIMULATE.
Operator lookup uses CONTEXT and/or OPERATORS."
  (unless (plan-p plan)
    (error "SIMULATE-PLAN requires a PLAN, got ~S" plan))
  (let* ((ops (or operators
                  (when context (context-planning-operators context))
                  (getf (plan-meta plan) :operators)))
         (facts (copy-list (if initial-p
                               initial-facts
                               (plan-initial-state plan))))
         (current (make-state facts :kind :current :source :simulate))
         (expected (expected-state-from-plan plan))
         (step-results nil)
         (ok t))
    (dolist (step (plan-steps plan))
      (handler-case
          (let* ((op (resolve-operator (getf step :operator)
                                       :context context
                                       :operators ops))
                 (b (bindings-from-step step)))
            (multiple-value-bind (new result)
                (simulate-operator facts op b)
              (setf facts new)
              (push result step-results)))
        (precondition-failure (c)
          (setf ok nil)
          (push (make-step-result
                 (precondition-failure-operator c)
                 (precondition-failure-bindings c)
                 facts facts
                 :status :precondition-failure
                 :missing (precondition-failure-missing c))
                step-results)
          (return))))
    (let* ((final (make-state facts :kind :simulated :source :simulate))
           (div (when (and expected ok)
                  (compare-states expected final))))
      (make-instance 'execution-result
                     :mode :simulate
                     :success ok
                     :steps (nreverse step-results)
                     :current-state current
                     :expected-state expected
                     :final-state final
                     :divergences div
                     :plan plan
                     :meta '(:note "symbolic simulation; no adapters")))))

;;; --- Execution (mutates live context facts) ---

(defun commit-facts-to-context! (context facts)
  "Set CONTEXT local facts to FACTS (Phase-4: write full visible set locally)."
  (setf (context-facts context) (copy-list facts))
  context)

(defun execute-operator! (context operator bindings &key confirm)
  "EXECUTE OPERATOR against live CONTEXT facts (symbolic only).
Returns (VALUES NEW-FACTS STEP-RESULT)."
  (ensure-confirmed operator bindings :confirm confirm)
  (let* ((facts (context-all-facts context))
         (b (extend-bindings-from-state
             (operator-preconditions operator) bindings facts))
         (missing (check-operator-preconditions facts operator b)))
    (when missing
      (error 'precondition-failure
             :operator operator :missing missing :bindings b))
    (let ((new (transition-facts facts operator b)))
      (commit-facts-to-context! context new)
      (values new (make-step-result operator b facts new :status :executed)))))

(defun execute-plan! (context plan &key confirm)
  "EXECUTE PLAN steps against live CONTEXT. Mutates context facts.
Returns an EXECUTION-RESULT with mode :EXECUTE and OBSERVED final state."
  (unless (plan-p plan)
    (error "EXECUTE-PLAN! requires a PLAN, got ~S" plan))
  (let* ((current (state-from-context context :kind :current))
         (expected (expected-state-from-plan plan))
         (step-results nil)
         (ok t)
         (facts (context-all-facts context)))
    (dolist (step (plan-steps plan))
      (let* ((op (resolve-operator (getf step :operator) :context context))
             (b (bindings-from-step step)))
        (handler-case
            (multiple-value-bind (new result)
                (execute-operator! context op b :confirm confirm)
              (setf facts new)
              (push result step-results))
          (precondition-failure (c)
            (setf ok nil)
            (push (make-step-result
                   (precondition-failure-operator c)
                   (precondition-failure-bindings c)
                   facts facts
                   :status :precondition-failure
                   :missing (precondition-failure-missing c))
                  step-results)
            (return)))))
    (let* ((observed (state-from-context context :kind :observed))
           (div (when (and expected ok)
                  (compare-states expected observed))))
      (make-instance 'execution-result
                     :mode :execute
                     :success ok
                     :steps (nreverse step-results)
                     :current-state current
                     :expected-state expected
                     :final-state observed
                     :divergences div
                     :plan plan
                     :meta '(:note "symbolic execute; context facts updated; no adapters")))))
