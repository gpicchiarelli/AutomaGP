;;;; core/autonomy.lisp — controlled autonomous symbolic operation (Phase 12)
;;;;
;;;; PROMPT §28: autonomy ≠ indiscriminate execution. One step walks
;;;; observe → react → goals → plan → evaluate → (simulate|execute) →
;;;; observe result → discrepancy → optional replan → knowledge update.
;;;;
;;;; Authority levels:
;;;;   :READ     — observe / react facts only; never plan-execute
;;;;   :SIMULATE — plan + symbolic simulation (default; safe)
;;;;   :EXECUTE  — live mutation only when policy authorizes (confirm gates)

(in-package #:automa-gp)

(defparameter *valid-authorities* '(:read :simulate :execute)
  "Maximum autonomy authority levels (ascending privilege).")

(defvar *autonomy-policy* nil
  "Session default AUTONOMY-POLICY, or NIL.")

(defvar *last-autonomy* nil
  "Plist summary of the last autonomous-step / autonomous-loop.")

(defclass autonomy-policy ()
  ((authority
    :initarg :authority
    :accessor policy-authority
    :initform :simulate
    :documentation ":READ | :SIMULATE | :EXECUTE — ceiling for this run.")
   (max-steps
    :initarg :max-steps
    :accessor policy-max-steps
    :initform 8)
   (adapters
    :initarg :adapters
    :accessor policy-adapters
    :initform nil
    :documentation "When true and authority is :EXECUTE, allow OS adapters.")
   (auto-confirm
    :initarg :auto-confirm
    :accessor policy-auto-confirm
    :initform nil
    :documentation "When true, confirm high-risk/irreversible ops automatically.")
   (confirm-fn
    :initarg :confirm-fn
    :accessor policy-confirm-fn
    :initform nil
    :documentation "Optional (lambda (operator plan) → boolean) gate.")
   (react-events
    :initarg :react-events
    :accessor policy-react-events
    :initform t)
   (infer
    :initarg :infer
    :accessor policy-infer
    :initform nil)
   (learn
    :initarg :learn
    :accessor policy-learn
    :initform t
    :documentation "On success, record achieved goals into knowledge memory.")
   (replan-on-discrepancy
    :initarg :replan-on-discrepancy
    :accessor policy-replan-on-discrepancy
    :initform t)
   (remember-procedure
    :initarg :remember-procedure
    :accessor policy-remember-procedure
    :initform nil
    :documentation "When true and plan succeeds under :EXECUTE/:SIMULATE, store procedure.")
   (prefer-archive
    :initarg :prefer-archive
    :accessor policy-prefer-archive
    :initform t
    :documentation "When true, reuse a scored procedure whose steps still apply before MEA."))
  (:documentation "Explicit gates for autonomous operation."))

(defun autonomy-policy-p (object)
  (typep object 'autonomy-policy))

(defun ensure-authority (authority)
  (let ((a (if (symbolp authority)
               (intern (symbol-name authority) :keyword)
               authority)))
    (unless (member a *valid-authorities* :test #'eq)
      (error "Unknown autonomy authority ~S; expected one of ~S"
             authority *valid-authorities*))
    a))

(defun make-autonomy-policy (&key (authority :simulate) (max-steps 8)
                               (adapters nil) (auto-confirm nil)
                               confirm-fn (react-events t) (infer nil)
                               (learn t) (replan-on-discrepancy t)
                               (remember-procedure nil)
                               (prefer-archive t))
  "Construct an AUTONOMY-POLICY. Default authority is :SIMULATE (safe)."
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
  (cond
    ((autonomy-policy-p policy) policy)
    ((autonomy-policy-p *autonomy-policy*) *autonomy-policy*)
    (t (make-autonomy-policy))))

(defun authority>= (have need)
  "True if HAVE authority is at least NEED (:READ < :SIMULATE < :EXECUTE)."
  (let* ((order '(:read :simulate :execute))
         (h (position (ensure-authority have) order))
         (n (position (ensure-authority need) order)))
    (and h n (>= h n))))

(defun plan-requires-confirmation-p (plan context)
  "True if any step's operator is irreversible or high/critical risk."
  (when (plan-p plan)
    (loop for step in (plan-steps plan)
          for op = (ignore-errors
                    (resolve-operator (getf step :operator) :context context))
          thereis (and (operator-p op)
                       (operator-needs-confirmation-p op)))))

(defun plan-risky-operators (plan context)
  (when (plan-p plan)
    (loop for step in (plan-steps plan)
          for op = (ignore-errors
                    (resolve-operator (getf step :operator) :context context))
          when (and (operator-p op) (operator-needs-confirmation-p op))
            collect (list :name (operator-name op)
                          :risk (operator-risk op)
                          :reversible (operator-reversible op)))))

(defun goals-satisfied-p (context &optional goals)
  (let ((g (or goals (normalize-planning-goals (goals-of context))))
        (facts (context-all-facts context)))
    (and g (null (differences facts g)))))

(defun autonomy-open-goals (&optional context)
  "Fact-like goals of CONTEXT that do not yet hold."
  (let ((ctx (%session-context context)))
    (differences (context-all-facts ctx)
                 (normalize-planning-goals (goals-of ctx)))))

(defun autonomy-has-work-p (&optional context)
  "True when CONTEXT has unsatisfied fact-like goals or pending events.
Matches workbench Passo/Ciclo enablement."
  (let ((ctx (%session-context context)))
    (or (autonomy-open-goals ctx)
        (pending-events ctx))))

(defun %authorize-execution (policy plan context)
  "Return (VALUES OK REASON). OK means policy allows running the plan
at the configured authority (simulate or execute).
When the plan recorded an external action that no longer matches,
execution is not authorized, with or without adapters, and simulation
is not authorized either. When adapters are requested, a plan that
never recorded its actions is not authorized for execute either. An
external action the facts no longer support is not authorized for
execute or simulate, with or without adapters."
  (let ((auth (policy-authority policy)))
    (cond
      ((eq auth :read)
       (values nil :authority-read))
      ((not (plan-p plan))
       (values nil :no-plan))
      ((not (plan-success plan))
       (values nil :plan-unsuccessful))
      ((eq auth :simulate)
       (cond
         ((and (getf (plan-meta plan) :external-actions-recorded)
               (not (plan-external-actions-match-p plan :context context)))
          (values nil :external-mismatch))
         ((not (plan-external-actions-supported-p plan :context context))
          (values nil :external-unsupported))
         (t (values t :simulate-authorized))))
      ((eq auth :execute)
       (cond
         ((and (not (plan-external-actions-match-p plan :context context))
               (or (policy-adapters policy)
                   (getf (plan-meta plan) :external-actions-recorded)))
          (values nil :external-mismatch))
         ((not (plan-external-actions-supported-p plan :context context))
          (values nil :external-unsupported))
         (t
          (let ((risky (plan-requires-confirmation-p plan context)))
            (cond
              ((and risky
                    (not (policy-auto-confirm policy))
                    (null (policy-confirm-fn policy)))
               (values nil :confirmation-required))
              ((and risky (policy-confirm-fn policy)
                    (not (funcall (policy-confirm-fn policy) plan context)))
               (values nil :confirmation-denied))
              (t (values t :execute-authorized)))))))
      (t (values nil :unknown-authority)))))

(defun %observe-context (context)
  (list :phase :observe
        :context (context-name context)
        :mode (context-mode context)
        :fact-count (length (context-all-facts context))
        :goal-count (length (goals-of context))
        :pending-events (length (pending-events context))
        :domains (copy-list (getf (context-meta context) :domains))))

(defun %update-knowledge-from-success! (context plan)
  "Assert achieved goal facts into session knowledge memory."
  (when (plan-p plan)
    (dolist (g (plan-goals plan))
      (when (and (consp g) (fact-p g (context-all-facts context)))
        (knowledge-add-fact! g)))
    t))

(defun %session-context (&optional context)
  "Resolve CONTEXT or the REPL *CURRENT-CONTEXT* (bound after interface load)."
  (cond
    ((context-p context) context)
    ((and (boundp '*current-context*) (context-p *current-context*))
     *current-context*)
    (t (error "AUTONOMOUS-STEP requires a context; call GP-RESET or pass :CONTEXT"))))

(defun autonomous-step (&key (context nil context-p) policy
                          (remember t))
  "Run one controlled autonomy cycle. Returns a summary plist (also
stored in *LAST-AUTONOMY*). Does not loop — see AUTONOMOUS-LOOP."
  (let* ((ctx (if context-p
                  (%session-context context)
                  (%session-context)))
         (pol (ensure-autonomy-policy policy))
         (auth (policy-authority pol))
         (phases nil)
         (plan nil)
         (execution nil)
         (halt nil)
         (status :ok)
         (authorized nil)
         (auth-reason nil))
    (unless (context-p ctx)
      (error "AUTONOMOUS-STEP requires a context"))
    (flet ((note (phase &rest plist)
             (let ((entry (list* :phase phase plist)))
               (push entry phases)
               entry)))
      ;; 1. Understand / observe
      (note :observe :snapshot (%observe-context ctx))
      (refresh-working-memory ctx)

      ;; 2. Recognize state / react to events
      (when (policy-react-events pol)
        (let ((pending (pending-events ctx)))
          (when pending
            (let ((reaction (process-pending-events!
                             ctx
                             :plan nil
                             :infer (policy-infer pol))))
              (note :recognize
                    :processed (getf reaction :processed)
                    :goals-added (getf reaction :goals-added)
                    :facts-added (getf reaction :facts-added))))))

      ;; 3. Determine goals
      (let ((goals (normalize-planning-goals (goals-of ctx))))
        (note :goals :goals goals)
        (cond
          ((null goals)
           (setf halt :no-goals status :halted))
          ((goals-satisfied-p ctx goals)
           (note :goals-satisfied :goals goals)
           (setf halt :goals-already-satisfied status :done))
          ((eq auth :read)
           ;; READ: may observe and report differences, not plan-execute
           (note :evaluate
                 :authority :read
                 :differences (differences (context-all-facts ctx) goals))
           (setf halt :authority-read status :halted))
          (t
           ;; 4. Build plan
           (setf (context-mode ctx) :plan)
           (setf plan (plan-consulting-archive
                       ctx :goals goals
                       :archive (policy-prefer-archive pol)))
           (setf *current-plan* plan)
           (when remember
             (record-plan-episode! plan :context-name (context-name ctx)))
           (note :plan
                 :success (plan-success plan)
                 :length (plan-length plan)
                 :operators (plan-operators-used plan)
                 :remaining (plan-remaining plan)
                 :from-procedure (getf (plan-meta plan) :from-procedure))

           ;; 5–6. Evaluate constraints / choose operators (from plan)
           (note :evaluate
                 :authority auth
                 :risky-operators (plan-risky-operators plan ctx)
                 :adapters-requested (policy-adapters pol))
           (note :choose :operators (plan-operators-used plan))

           (unless (plan-success plan)
             (setf halt :plan-failed status :halted))

           (when (eq status :ok)
             (multiple-value-bind (ok reason)
                 (%authorize-execution pol plan ctx)
               (setf authorized ok auth-reason reason)
               (note :authorize :ok ok :reason reason)
               (unless ok
                 (setf halt reason status :halted)))

             ;; 7. Execute when authorized
             (when (eq status :ok)
               (cond
                 ((eq auth :simulate)
                  (handler-case
                      (progn
                        (setf execution
                              (call-with-execution-mode
                               ctx :simulate
                               (lambda ()
                                 (simulate-plan plan :context ctx
                                                :operators
                                                (context-planning-operators ctx)))))
                        (setf *last-execution* execution)
                        (when remember
                          (record-execution-episode! execution))
                        (note :execute :mode :simulate
                              :success (execution-success execution)))
                    (error (condition)
                      (let ((text (princ-to-string condition)))
                        (cond
                          ((search "no longer matches" text)
                           (setf execution nil
                                 halt :external-mismatch
                                 status :halted)
                           (note :refuse :reason :external-mismatch))
                          ((search "no longer support" text)
                           (setf execution nil
                                 halt :external-unsupported
                                 status :halted)
                           (note :refuse :reason :external-unsupported))
                          (t (error condition)))))))
                 ((eq auth :execute)
                  (let ((confirm (or (policy-auto-confirm pol)
                                     (and (policy-confirm-fn pol) t))))
                    (handler-case
                        (progn
                          (setf execution
                                (call-with-execution-mode
                                 ctx :execute
                                 (lambda ()
                                   (execute-plan! ctx plan
                                                  :confirm confirm
                                                  :adapters (policy-adapters pol)))))
                          (setf *last-execution* execution)
                          (when remember
                            (record-execution-episode! execution))
                          (note :execute :mode :execute
                                :success (execution-success execution)
                                :adapters (policy-adapters pol)))
                      (error (condition)
                        (let ((text (princ-to-string condition)))
                          (cond
                            ((search "no longer matches" text)
                             (setf execution nil
                                   halt :external-mismatch
                                   status :halted)
                             (note :refuse :reason :external-mismatch))
                            ((search "no longer support" text)
                             (setf execution nil
                                   halt :external-unsupported
                                   status :halted)
                             (note :refuse :reason :external-unsupported))
                            (t (error condition))))))))
                 (t
                  (setf halt :authority-read status :halted))))

             ;; 8–9. Observe result / detect discrepancies
             (when (execution-result-p execution)
               (let* ((goals goals)
                      (facts-after (if (eq auth :execute)
                                       (context-all-facts ctx)
                                       (state-facts (execution-final-state execution))))
                      (left (differences facts-after goals))
                      (div (execution-divergences execution)))
                 (note :observe-result
                       :success (execution-success execution)
                       :remaining left
                       :divergences div)
                 ;; Score only a live run of a reused procedure. Simulation
                 ;; leaves the archive unchanged. One outcome, no second copy.
                 (when (and (eq auth :execute)
                            (plan-reused-procedure-names plan))
                   (let ((scored (record-procedure-outcome!
                                  plan
                                  :success (and (execution-success execution)
                                                (null left)))))
                     (when scored
                       (note :update
                             :procedure-score (procedure-name scored)
                             :success (and (execution-success execution)
                                           (null left))
                             :score (procedure-score scored)))))
                 (cond
                   ;; 11. Goals hold in the observed state.
                   ((and (execution-success execution) (null left))
                    ;; Learn only from live execution. Simulation must not
                    ;; write durable knowledge for facts the context does not hold.
                    (when (and (policy-learn pol) (eq auth :execute))
                      (%update-knowledge-from-success! ctx plan)
                      (note :update :knowledge t :goals goals))
                    (when (and (policy-remember-procedure pol)
                               (plan-success plan)
                               (not (and (getf (plan-meta plan) :from-procedure)
                                         (find-procedure
                                          (getf (plan-meta plan) :from-procedure)))))
                      (remember-procedure-from-plan! plan)
                      (note :update :procedure t))
                    (setf status :done halt :completed))
                   ;; 10. Correct: ask the loop to replan if the run
                   ;; succeeded symbolically but goals remain.
                   ((and (policy-replan-on-discrepancy pol)
                         (execution-success execution)
                         left)
                    (note :discrepancy :remaining left :divergences div)
                    (note :correct :action :replan-next)
                    (setf status :continue))
                   (t
                    (note :discrepancy :remaining left :divergences div)
                    (setf status :halted
                          halt (if (execution-success execution)
                                   :discrepancy
                                   :execution-failed)))))))))))

    (refresh-working-memory ctx)
    (setf *last-autonomy*
          (list :status status
                :halt halt
                :authority auth
                :authorized authorized
                :authorize-reason auth-reason
                :phases (nreverse phases)
                :plan (when (plan-p plan)
                        (list :success (plan-success plan)
                              :length (plan-length plan)
                              :operators (plan-operators-used plan)
                              :remaining (plan-remaining plan)
                              :from-procedure (getf (plan-meta plan) :from-procedure)))
                :execution (when (execution-result-p execution)
                             (list :success (execution-success execution)
                                   :mode (execution-mode execution)
                                   :divergences (execution-divergences execution)))
                :goals (goals-of ctx)
                :pending-events (length (pending-events ctx))))
    *last-autonomy*))

(defun autonomous-loop (&key (context nil context-p) policy
                          (max-steps nil) (remember t))
  "Repeat AUTONOMOUS-STEP until :DONE, :HALTED, or max steps.
Returns a plist (:iterations :results :final)."
  (let* ((ctx (if context-p
                  (%session-context context)
                  (%session-context)))
         (pol (ensure-autonomy-policy policy))
         (limit (or max-steps (policy-max-steps pol)))
         (results nil)
         (final nil))
    (loop for i from 1 to limit
          do (let ((r (autonomous-step :context ctx :policy pol
                                       :remember remember)))
               (push r results)
               (setf final r)
               (let ((st (getf r :status)))
                 (when (member st '(:done :halted) :test #'eq)
                   (return))))
          finally (when final
                    (setf (getf final :halt)
                          (or (getf final :halt) :max-steps))
                    (setf (getf final :status)
                          (if (eq (getf final :status) :continue)
                              :halted
                              (getf final :status)))))
    (setf *last-autonomy*
          (list :status (getf final :status)
                :halt (getf final :halt)
                :iterations (length results)
                :authority (policy-authority pol)
                :results (nreverse results)
                :final final))
    *last-autonomy*))
