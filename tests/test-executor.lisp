;;;; tests/test-executor.lisp

(in-package #:automa-gp/tests)

(def-suite executor-suite :in automa-gp-suite)
(in-suite executor-suite)

(defun studio-ops ()
  (list (make-operator :name 'power-on
                       :preconditions '((device ?d) (power-state ?d off))
                       :add-list '((power-state ?d on))
                       :delete-list '((power-state ?d off)))
        (make-operator :name 'connect
                       :preconditions '((device ?d) (power-state ?d on))
                       :add-list '((connection ?d computer)))))

(defun studio-context ()
  (let ((ctx (create-context
              :name 'studio
              :facts '((device interface-01)
                       (power-state interface-01 off)))))
    (dolist (op (studio-ops)) (register-operator! ctx op))
    ctx))

(test transition-state-a-to-b
  (let* ((op (first (studio-ops)))
         (a (make-state '((device interface-01)
                          (power-state interface-01 off))
                        :kind :current))
         (b (unify '(power-state interface-01 on) '(power-state ?d on)))
         (next (transition-state a op b :kind :simulated)))
    (is (eq :simulated (state-kind next)))
    (is (fact-p '(power-state interface-01 on) (state-facts next)))
    (is (not (fact-p '(power-state interface-01 off) (state-facts next))))))

(test simulate-plan-no-mutation
  (let* ((ctx (studio-context))
         (plan (plan-from-context
                ctx :goals '((connection interface-01 computer))))
         (before (copy-list (context-facts ctx)))
         (result (simulate-plan plan :context ctx)))
    (is (execution-result-p result))
    (is (eq :simulate (execution-mode result)))
    (is-true (execution-success result))
    (is (eq :simulated (state-kind (execution-final-state result))))
    (is (eq :expected (state-kind (execution-expected-state result))))
    (is (fact-p '(connection interface-01 computer)
                (state-facts (execution-final-state result))))
    (is (equal before (context-facts ctx)))
    (is (getf (execution-divergences result) :equal))))

(test execute-plan-mutates-context
  (let* ((ctx (studio-context))
         (plan (plan-from-context
                ctx :goals '((connection interface-01 computer))))
         (result (execute-plan! ctx plan)))
    (is (eq :execute (execution-mode result)))
    (is-true (execution-success result))
    (is (eq :observed (state-kind (execution-final-state result))))
    (is (fact-p '(connection interface-01 computer) (context-all-facts ctx)))
    (is (fact-p '(power-state interface-01 on) (context-all-facts ctx)))
    (is (getf (execution-divergences result) :equal))))

(test irreversible-requires-confirmation
  (let* ((ctx (create-context :facts '((device d1))))
         (op (make-operator :name 'wipe
                            :preconditions '((device ?d))
                            :add-list '((wiped ?d))
                            :reversible nil
                            :risk :high)))
    (register-operator! ctx op)
    (signals confirmation-required
      (execute-operator! ctx op '((?d . d1))))
    (multiple-value-bind (facts result)
        (execute-operator! ctx op '((?d . d1)) :confirm t)
      (is (fact-p '(wiped d1) facts))
      (is (eq :executed (getf result :status))))))

(test simulate-precondition-failure
  (let* ((op (make-operator :name 'connect
                            :preconditions '((power-state ?d on))
                            :add-list '((connection ?d computer))))
         (facts '((device interface-01) (power-state interface-01 off))))
    (signals precondition-failure
      (simulate-operator facts op
                         (unify '(connection interface-01 computer)
                                '(connection ?d computer))))))

;;; ---------------------------------------------------------------------------
;;; Fixtures for hand-built plans
;;; ---------------------------------------------------------------------------

(defparameter *run-modes* '(:simulate :execute)
  "Both plan runners; a property that holds for one usually has to hold
for the other.")

(defparameter *step-kinds*
  '(:ordinary :effects-only-live :effects-only-recorded :stored-apply)
  "Every way a plan step can reach the runners.")

(defun manual-plan (goals steps &key initial final)
  "A successful PLAN made of STEPS, as MEA or the archive would hand it over."
  (make-instance 'plan
                 :goals goals
                 :steps steps
                 :success t
                 :initial-state initial
                 :final-state final))

(defun run-plan-in (mode ctx plan &key confirm)
  (ecase mode
    (:simulate (simulate-plan plan :context ctx))
    (:execute (execute-plan! ctx plan :confirm confirm))))

(defun step-statuses (result)
  (mapcar (lambda (step) (getf step :status)) (execution-steps result)))

(defun same-facts-p (a b)
  (null (set-exclusive-or a b :test #'equal)))

(defun wipe-case (kind)
  "A context holding (DEVICE D1) and a one-step plan that asserts (WIPED D1)
through an irreversible step of KIND. Returns (VALUES CONTEXT PLAN)."
  (let ((ctx (create-context :name 'bench :facts '((device d1)))))
    (when (member kind '(:ordinary :effects-only-live))
      (register-operator! ctx (make-operator :name 'wipe
                                             :preconditions '((device ?d))
                                             :add-list '((wiped ?d))
                                             :reversible nil)))
    (values
     ctx
     (manual-plan
      '((wiped d1))
      (list (append
             (list :operator 'wipe :bindings '((?d . d1)) :goal '(wiped d1))
             (ecase kind
               (:ordinary nil)
               (:effects-only-live (list :effects-only t))
               (:effects-only-recorded
                (list :effects-only t :effects-stored t
                      :adds '((wiped d1)) :reversible nil))
               (:stored-apply
                (list :stored-apply t :effects-stored t
                      :preconditions-stored t
                      :preconditions '((device d1))
                      :adds '((wiped d1)) :reversible nil)))))
      :initial '((device d1))
      :final '((device d1) (wiped d1))))))

(defun child-of-powered-off-room ()
  "A child context that only inherits its facts. Returns (VALUES CHILD PARENT)."
  (let* ((parent (create-context
                  :name 'room
                  :facts '((device interface-01)
                           (power-state interface-01 off))))
         (child (create-context :name 'desk :parent parent)))
    (dolist (op (studio-ops)) (register-operator! child op))
    (values child parent)))

;;; ---------------------------------------------------------------------------
;;; SIMULATE never touches the live context
;;; ---------------------------------------------------------------------------

(test simulate-leaves-the-live-context-alone-for-every-step-kind
  (dolist (kind *step-kinds*)
    (multiple-value-bind (ctx plan) (wipe-case kind)
      (add-goal! ctx '(wiped d1))
      (let* ((facts (context-facts ctx))
             (copy (copy-tree facts))
             (operators (context-operators ctx))
             (*invoke-adapters* t)
             (result (simulate-plan plan :context ctx)))
        (is-true (execution-success result) "~A did not simulate" kind)
        (is (fact-p '(wiped d1) (state-facts (execution-final-state result))))
        (is (eq facts (context-facts ctx)))
        (is (equal copy (context-facts ctx)))
        (is (equal '((wiped d1)) (context-goals ctx)))
        (is (eq operators (context-operators ctx)))
        (is (eq :read (context-mode ctx)))
        (is (null (context-events ctx)))))))

(test simulate-restarts-do-not-reach-the-live-context
  (loop for (restart . arguments) in '((:skip)
                                       (:abort-execution)
                                       (:use-value ((made up)))
                                       (:use-value nil))
        do (let* ((ctx (create-context :facts '((device d1))))
                  (plan (manual-plan
                         '((connection d1 computer))
                         (list (list :operator 'connect
                                     :bindings '((?d . d1))
                                     :goal '(connection d1 computer)))))
                  (*plan-runner-default-abort* nil))
             (dolist (op (studio-ops)) (register-operator! ctx op))
             (let* ((facts (context-facts ctx))
                    (result (handler-bind
                                ((precondition-failure
                                   (lambda (c)
                                     (declare (ignore c))
                                     (apply #'invoke-restart restart arguments))))
                              (simulate-plan plan :context ctx))))
               (is (eq facts (context-facts ctx)))
               (is (equal '((device d1)) (context-facts ctx)))
               (is (equal (if (eq restart :use-value)
                              (first arguments)
                              '((device d1)))
                          (state-facts (execution-final-state result))))))))

(test simulate-starts-from-the-live-facts
  (gp-reset)
  (let* ((ctx (studio-context))
         (plan (plan-from-context
                ctx :goals '((connection interface-01 computer))))
         (changed '((device interface-01) (power-state interface-01 broken))))
    (setf (context-facts ctx) (copy-list changed))
    ;; The plan no longer applies; a simulation that replayed the planner's
    ;; snapshot would report success for it.
    (let ((live (simulate-plan plan :context ctx)))
      (is-false (execution-success live))
      (is (equal '(:aborted) (step-statuses live)))
      (is (equal changed (state-facts (execution-current-state live))))
      (is (eq 'studio (state-source (execution-current-state live))))
      (is (equal changed (context-facts ctx))))
    ;; Explicit initial facts replace the live ones.
    (let ((given (simulate-plan plan
                                :context ctx
                                :initial-facts (plan-initial-state plan))))
      (is-true (execution-success given))
      (is (equal changed (context-facts ctx))))
    ;; With no context there is nothing live: the recorded state is used.
    (let ((recorded (simulate-plan plan :operators (studio-ops))))
      (is-true (execution-success recorded))
      (is (equal (plan-initial-state plan)
                 (state-facts (execution-current-state recorded))))
      (is (eq :plan (state-source (execution-current-state recorded)))))))

;;; ---------------------------------------------------------------------------
;;; Confirmation
;;; ---------------------------------------------------------------------------

(test only-irreversible-or-high-risk-operators-need-confirmation
  (loop for (reversible risk needed) in '((t :low nil)
                                          (t :medium nil)
                                          (t :high t)
                                          (t :critical t)
                                          (nil :low t)
                                          (nil :critical t))
        do (is (eq needed
                   (and (operator-needs-confirmation-p
                         (make-operator :name 'op
                                        :reversible reversible
                                        :risk risk))
                        t))
               "reversible ~A, risk ~A" reversible risk)))

(test confirmation-cannot-be-bypassed-by-any-step-kind
  (dolist (kind *step-kinds*)
    ;; Unconfirmed, the step is aborted and nothing is written.
    (multiple-value-bind (ctx plan) (wipe-case kind)
      (let ((result (execute-plan! ctx plan)))
        (is-false (execution-success result) "~A ran unconfirmed" kind)
        (is (equal '(:aborted) (step-statuses result)))
        (is (equal '((device d1)) (context-all-facts ctx)))))
    ;; A confirm function that says no is honoured; the condition is typed.
    (multiple-value-bind (ctx plan) (wipe-case kind)
      (let ((*execution-confirm* (constantly nil))
            (*plan-runner-default-abort* nil))
        (signals confirmation-required (execute-plan! ctx plan))
        (is (equal '((device d1)) (context-all-facts ctx)))))
    ;; Each of the three ways to confirm lets the step through.
    (dolist (way '(:keyword :function :restart))
      (multiple-value-bind (ctx plan) (wipe-case kind)
        (let ((result
                (ecase way
                  (:keyword (execute-plan! ctx plan :confirm t))
                  (:function
                   (let ((*execution-confirm* (constantly t)))
                     (execute-plan! ctx plan)))
                  (:restart
                   (let ((*plan-runner-default-abort* nil))
                     (handler-bind ((confirmation-required
                                      (lambda (c)
                                        (invoke-restart
                                         (find-restart :confirm c)))))
                       (execute-plan! ctx plan)))))))
          (is-true (execution-success result) "~A, confirmed by ~A" kind way)
          (is (fact-p '(wiped d1) (context-all-facts ctx))))))))

(test confirmation-is-asked-only-for-a-step-that-can-run
  (let* ((ctx (create-context :facts '((device d1))))
         (asked nil)
         (*execution-confirm* (lambda (operator bindings)
                                (declare (ignore operator))
                                (push bindings asked)
                                t))
         (wipe (make-operator :name 'wipe
                              :preconditions '((device ?d) (armed ?d))
                              :add-list '((wiped ?d))
                              :reversible nil)))
    (signals precondition-failure
      (execute-operator! ctx wipe *no-bindings*))
    (is (null asked))
    (is (equal '((device d1)) (context-facts ctx)))
    (setf (context-facts ctx) (list '(device d1) '(armed d1)))
    (execute-operator! ctx wipe *no-bindings*)
    ;; Asked once, with the bindings the preconditions grounded.
    (is (equal '(((?d . d1))) asked))
    (is (fact-p '(wiped d1) (context-facts ctx)))))

(test an-alternative-operator-is-confirmed-like-a-planned-one
  (let* ((ctx (create-context :facts '((device d1))))
         (force (make-operator :name 'force-connect
                               :preconditions '((device ?d))
                               :add-list '((connection ?d computer))
                               :reversible nil))
         (plan (manual-plan '((connection d1 computer))
                            (list (list :operator 'connect
                                        :bindings '((?d . d1))
                                        :goal '(connection d1 computer)))))
         (*plan-runner-default-abort* nil))
    (dolist (op (studio-ops)) (register-operator! ctx op))
    (flet ((run (&key confirm)
             (handler-bind ((precondition-failure
                              (lambda (c)
                                (declare (ignore c))
                                (invoke-restart :use-alternative force))))
               (execute-plan! ctx plan :confirm confirm))))
      (signals confirmation-required (run))
      (is (equal '((device d1)) (context-facts ctx)))
      (is-true (execution-success (run :confirm t)))
      (is (fact-p '(connection d1 computer) (context-facts ctx))))))

(test a-recorded-step-carries-its-own-risk
  (loop for (step reversible risk) in '(((:operator x) t :low)
                                        ((:operator x :reversible t) t :low)
                                        ((:operator x :reversible nil) nil :low)
                                        ((:operator x :risk :high) t :high)
                                        ;; A value is not a key.
                                        ((:operator x :goal :reversible) t :low)
                                        ((:operator x :goal :reversible
                                          :reversible nil)
                                         nil :low))
        for operator = (automa-gp::%operator-for-stored-step step)
        do (is (eq reversible (operator-reversible operator)) "~S" step)
           (is (eq risk (operator-risk operator)) "~S" step)))

;;; ---------------------------------------------------------------------------
;;; Refusals before the first step
;;; ---------------------------------------------------------------------------

(test a-step-with-no-operator-and-no-record-refuses-the-whole-plan
  (dolist (mode *run-modes*)
    (let* ((ctx (studio-context))
           (plan (plan-from-context
                  ctx :goals '((connection interface-01 computer))))
           (before (copy-list (context-facts ctx))))
      (remove-operator! ctx 'connect)
      (setf (plan-steps plan)
            (mapcar (lambda (step)
                      (if (eq 'connect (getf step :operator))
                          (list :operator 'connect
                                :bindings (getf step :bindings)
                                :goal (getf step :goal))
                          step))
                    (plan-steps plan)))
      (let ((refusal (handler-case (run-plan-in mode ctx plan)
                       (unknown-operator (c) c))))
        (is (typep refusal 'unknown-operator) "~A ran the plan" mode)
        (when (typep refusal 'unknown-operator)
          (is (eq 'connect (unknown-operator-name refusal)))))
      ;; POWER-ON, the step before the unknown one, was not applied.
      (is (equal before (context-facts ctx))))))

(test execute-refuses-to-retract-an-inherited-fact
  (multiple-value-bind (child parent) (child-of-powered-off-room)
    (register-operator! child (make-operator :name 'label
                                             :preconditions '((device ?d))
                                             :add-list '((labelled ?d))))
    (let* ((inherited (copy-list (context-facts parent)))
           (plan (plan-from-context
                  child :goals '((labelled interface-01)
                                 (power-state interface-01 on))))
           (refusal (handler-case (execute-plan! child plan)
                      (plan-refused (c) c))))
      (is (equal '(label power-on)
                 (mapcar (lambda (step) (getf step :operator))
                         (plan-steps plan))))
      (is (typep refusal 'plan-refused))
      (when (typep refusal 'plan-refused)
        (is (eq :inherited-retraction (plan-refused-reason refusal)))
        (is (equal '((power-state interface-01 off))
                   (plan-refused-facts refusal)))
        (is (eq child (gp-condition-context refusal)))
        (is (search "inherits" (princ-to-string refusal))))
      ;; Refused before LABEL, the step that could have run.
      (is (null (context-facts child)))
      (is (equal inherited (context-facts parent)))
      (is (equal inherited (context-all-facts child)))
      ;; Simulation works on a copy, so it may still be asked.
      (is-true (execution-success (simulate-plan plan :context child)))
      (is (null (context-facts child))))))

(test a-recovered-run-still-cannot-retract-an-inherited-fact
  ;; The pre-flight walk ends at CALIBRATE, which fails. Once that step is
  ;; skipped, POWER-ON is refused at the step, under the step restarts.
  (multiple-value-bind (child parent) (child-of-powered-off-room)
    (register-operator! child (make-operator
                               :name 'calibrate
                               :preconditions '((device ?d) (warm ?d))
                               :add-list '((calibrated ?d))))
    (let ((plan (manual-plan
                 '((calibrated interface-01) (power-state interface-01 on))
                 (list (list :operator 'calibrate
                             :bindings '((?d . interface-01))
                             :goal '(calibrated interface-01))
                       (list :operator 'power-on
                             :bindings '((?d . interface-01))
                             :goal '(power-state interface-01 on))))))
      (with-failure-strategy (:skip)
        (let ((result (execute-plan! child plan)))
          (is-false (execution-success result))
          (is (equal '(:skipped :skipped) (step-statuses result)))))
      (is (null (context-facts child)))
      (is (fact-p '(power-state interface-01 off) (context-facts parent)))
      (is (not (fact-p '(power-state interface-01 on)
                       (context-all-facts child)))))))

(test execute-in-a-child-context-stores-only-what-is-local
  (let* ((parent (create-context
                  :name 'room
                  :facts '((device interface-01) (power-state interface-01 on))))
         (child (create-context :name 'desk
                                :parent parent
                                :facts '((device interface-01)))))
    (dolist (op (studio-ops)) (register-operator! child op))
    (let* ((plan (plan-from-context
                  child :goals '((connection interface-01 computer))))
           (result (execute-plan! child plan)))
      (is-true (execution-success result))
      (is-true (getf (execution-divergences result) :equal))
      ;; The fact that was already local stays local; the inherited one is
      ;; not copied down.
      (is (equal '((device interface-01) (connection interface-01 computer))
                 (context-facts child)))
      (is (same-facts-p '((device interface-01)
                          (power-state interface-01 on)
                          (connection interface-01 computer))
                        (context-all-facts child)))
      ;; So the child still follows its parent.
      (setf (context-facts parent) (list '(device interface-01)))
      (is (not (fact-p '(power-state interface-01 on)
                       (context-all-facts child)))))))

;;; ---------------------------------------------------------------------------
;;; Restarts and the context mode through the REPL runners
;;; ---------------------------------------------------------------------------

(defun open-unsupported-session-plan ()
  "A session whose last plan no longer applies: POWER-ON lost its precondition."
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device d1))
  (gp-add-fact '(power-state d1 off))
  (dolist (op (studio-ops)) (gp-add-operator op))
  (gp-plan :goals '((power-state d1 on)) :archive nil)
  (gp-remove-fact '(power-state d1 off)))

(test step-restarts-stay-reachable-through-the-repl-runners
  (loop for (name runner mode) in (list (list 'gp-simulate #'gp-simulate :simulate)
                                        (list 'gp-run #'gp-run :execute))
        do (dolist (restart '(:retry :skip :abort-execution :use-value
                              :use-alternative :ask-user))
             (open-unsupported-session-plan)
             (let* ((*plan-runner-default-abort* nil)
                    (offered nil)
                    (result (handler-bind
                                ((precondition-failure
                                   (lambda (c)
                                     (setf offered (find-restart restart c))
                                     (invoke-restart :skip))))
                              (funcall runner))))
               (is-true offered "~A hides ~A" name restart)
               (is (equal '(:skipped) (step-statuses result)))
               (is (eq mode (context-mode (gp-context))))))))

(test the-confirm-restart-is-reachable-through-gp-run
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device d1))
  (gp-add-operator (make-operator :name 'wipe
                                  :preconditions '((device ?d))
                                  :add-list '((wiped ?d))
                                  :reversible nil))
  (gp-plan :goals '((wiped d1)) :archive nil)
  (let* ((*plan-runner-default-abort* nil)
         (result (handler-bind ((confirmation-required
                                  (lambda (c)
                                    (declare (ignore c))
                                    (invoke-restart :confirm))))
                   (gp-run))))
    (is-true (execution-success result))
    (is (fact-p '(wiped d1) (gp-facts)))
    (is (eq :execute (context-mode (gp-context))))))

(test an-abandoned-run-restores-the-mode
  (let ((ctx (create-context :mode :plan)))
    (flet ((run (mode thunk)
             (automa-gp::call-with-execution-mode ctx mode thunk)))
      ;; A run that returns keeps the mode and its values.
      (is (equal '(1 2) (multiple-value-list
                         (run :execute (lambda () (values 1 2))))))
      (is (eq :execute (context-mode ctx)))
      (setf (context-mode ctx) :plan)
      ;; Any other way out restores it: a THROW, an error nobody handled.
      (dolist (mode *run-modes*)
        (catch 'abandon (run mode (lambda () (throw 'abandon nil))))
        (is (eq :plan (context-mode ctx)))
        (signals error (run mode (lambda () (error "boom"))))
        (is (eq :plan (context-mode ctx)))))))

(test an-unhandled-step-failure-restores-the-session-mode
  (dolist (runner (list #'gp-simulate #'gp-run))
    (open-unsupported-session-plan)
    (let ((*plan-runner-default-abort* nil))
      (signals precondition-failure (funcall runner)))
    (is (eq :plan (context-mode (gp-context))))
    (is (null (gp-last-execution)))))

;;; ---------------------------------------------------------------------------
;;; What a run reports
;;; ---------------------------------------------------------------------------

(test a-failed-run-still-reports-its-divergences
  (dolist (mode *run-modes*)
    (let* ((ctx (studio-context))
           (plan (plan-from-context
                  ctx :goals '((connection interface-01 computer)))))
      (setf (context-facts ctx) (list '(device interface-01)))
      (let* ((result (run-plan-in mode ctx plan))
             (divergences (execution-divergences result)))
        (is-false (execution-success result))
        (is (equal '(:aborted) (step-statuses result)))
        (is-false (getf divergences :equal) "~A hides the divergence" mode)
        (is (same-facts-p '((power-state interface-01 on)
                            (connection interface-01 computer))
                          (getf divergences :facts-only-in-a)))
        (is (null (getf divergences :facts-only-in-b)))))))

(test an-empty-fact-list-is-a-real-outcome
  (dolist (mode *run-modes*)
    ;; A step may retract the last fact.
    (let ((ctx (create-context :facts '((token))))
          (plan (manual-plan nil (list (list :operator 'consume))
                             :initial '((token)))))
      (register-operator! ctx (make-operator :name 'consume
                                             :preconditions '((token))
                                             :delete-list '((token))))
      (let ((result (run-plan-in mode ctx plan)))
        (is-true (execution-success result))
        (is (null (state-facts (execution-final-state result)))
            "~A kept the retracted fact" mode)
        (is-true (getf (execution-divergences result) :equal))))
    ;; USE-VALUE may supply the empty state.
    (let ((ctx (create-context :facts '((device d1))))
          (plan (manual-plan nil (list (list :operator 'connect
                                             :bindings '((?d . d1))))))
          (*plan-runner-default-abort* nil))
      (dolist (op (studio-ops)) (register-operator! ctx op))
      (let ((result (handler-bind ((precondition-failure
                                     (lambda (c)
                                       (declare (ignore c))
                                       (invoke-restart :use-value nil))))
                      (run-plan-in mode ctx plan))))
        (is (equal '(:use-value) (step-statuses result)))
        (is (null (state-facts (execution-final-state result)))
            "~A ignored the supplied state" mode)
        (is (equal (if (eq mode :execute) nil '((device d1)))
                   (context-facts ctx)))))))

(test a-projection-retracts-nothing-an-ordinary-application-keeps
  ;; ?X occurs only in the delete list. An ordinary application leaves it
  ;; open and retracts no lock; the effects-only projection must not pick one.
  (dolist (mode *run-modes*)
    (let* ((facts '((holder bob) (lock alpha) (lock beta)))
           (ctx (create-context :facts facts))
           (release (make-operator :name 'release
                                   :preconditions '((holder ?h) (armed ?h))
                                   :add-list '((released ?h))
                                   :delete-list '((lock ?x))))
           (plan (manual-plan '((released bob))
                              (list (list :operator 'release
                                          :bindings '((?h . bob))
                                          :goal '(released bob)
                                          :effects-only t)))))
      (register-operator! ctx release)
      (let ((result (run-plan-in mode ctx plan)))
        (is-true (execution-success result))
        (is (equal '(:projected) (step-statuses result)))
        (is (equal (apply-operator facts release '((?h . bob)))
                   (state-facts (execution-final-state result)))
            "~A retracted a fact the operator keeps" mode)))))

(test the-trace-names-an-action-only-for-a-step-that-ran
  (let* ((ctx (studio-context))
         (plan (plan-from-context
                ctx :goals '((connection interface-01 computer)))))
    ;; POWER-ON can no longer run; CONNECT can.
    (setf (context-facts ctx)
          (list '(device interface-01) '(power-state interface-01 on)))
    (let ((result (with-failure-strategy (:skip) (execute-plan! ctx plan))))
      (is (equal '(:skipped :executed) (step-statuses result)))
      (is-true (execution-success result))
      (is (equal '(connect)
                 (mapcar (lambda (entry) (getf entry :operator))
                         (find-trace-entries :action (trace-of result))))))))
