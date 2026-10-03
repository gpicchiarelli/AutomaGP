;;;; tests/test-repl.lisp — the session commands (GP-*)

(in-package #:automa-gp/tests)

(def-suite repl-suite :in automa-gp-suite)
(in-suite repl-suite)

(test repl-roundtrip
  (gp-reset)
  (is (context-p (gp-context)))
  (gp-context :name 'studio-audio)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (is (fact-p '(device interface-01) (gp-facts)))
  (gp-add-goal 'audio-system-ready)
  (is (equal '(audio-system-ready) (gp-goals)))
  (is (eq :read (gp-mode)))
  (is (eq :plan (gp-mode :plan)))
  (is (state-p (gp-state)))
  (gp-remove-fact '(power-state interface-01 off))
  (is (not (fact-p '(power-state interface-01 off) (gp-facts))))
  (gp-register-action (make-action :name 'noop :effects nil))
  (is (= 1 (length (gp-actions))))
  (gp-reset)
  (is (null (gp-facts))))

(test repl-phase2-rules-and-query
  (gp-reset)
  (gp-context :name 'studio-audio)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 on))
  (gp-add-rule (make-rule :name 'powered-when-on
                          :if '((device ?d) (power-state ?d on))
                          :then '(powered ?d)))
  (is (= 1 (length (gp-rules))))
  (let ((hits (gp-query '(device ?x) :infer nil)))
    (is (= 1 (length hits))))
  (let ((hits (gp-query '(powered ?x))))
    (is (plusp (length hits)))
    (is (equal '(powered interface-01) (getf (first hits) :fact))))
  (multiple-value-bind (all new) (gp-infer :assert t)
    (declare (ignore all))
    (is (fact-p '(powered interface-01) new))
    (is (fact-p '(powered interface-01) (gp-facts))))
  (gp-remove-rule 'powered-when-on)
  (is (null (gp-rules))))

(test repl-phase3-plan
  (gp-reset)
  (gp-context :name 'studio-audio)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (gp-add-operator
   (make-operator :name 'connect
                  :preconditions '((device ?d) (power-state ?d on))
                  :add-list '((connection ?d computer))))
  (is (= 2 (length (gp-operators))))
  (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
    (is (plan-p plan))
    (is-true (plan-success plan))
    (is (eq :plan (gp-mode)))
    (is (eq plan (gp-last-plan)))
    (is (>= (plan-length plan) 2))
    (is (fact-p '(power-state interface-01 off) (gp-facts)))
    (is (not (fact-p '(connection interface-01 computer) (gp-facts))))
    (gp-add-fact '(power-state interface-01 on))
    (gp-add-fact '(connection interface-01 computer))
    (signals error (gp-plan :goals '((connection interface-01 computer))))
    (is (eq plan (gp-last-plan)))))

(test repl-refuses-simulate-and-run-on-a-failed-plan
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (let ((failed (gp-plan :goals '((power-state interface-01 on)) :archive nil)))
    (is (not (plan-success failed)))
    (signals error (gp-simulate))
    (signals error (gp-run :confirm t))
    (is (null (gp-last-execution)))
    (is (eq failed (gp-last-plan)))))

(test repl-phase4-simulate-and-run
  (gp-reset)
  (gp-context :name 'studio-audio)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (gp-add-operator
   (make-operator :name 'connect
                  :preconditions '((device ?d) (power-state ?d on))
                  :add-list '((connection ?d computer))))
  (gp-plan :goals '((connection interface-01 computer)))
  (let ((sim (gp-simulate)))
    (is (execution-result-p sim))
    (is (eq :simulate (gp-mode)))
    (is-true (execution-success sim))
    (is (eq sim (gp-last-execution)))
    ;; Live facts unchanged after simulate
    (is (fact-p '(power-state interface-01 off) (gp-facts)))
    (is (not (fact-p '(connection interface-01 computer) (gp-facts)))))
  (let ((run (gp-run)))
    (is (eq :execute (gp-mode)))
    (is-true (execution-success run))
    (is (fact-p '(connection interface-01 computer) (gp-facts)))
    (is (fact-p '(power-state interface-01 on) (gp-facts)))
    (is (eq :observed (state-kind (execution-final-state run))))))

(test repl-phase6-explain
  (gp-reset)
  (gp-context :name 'studio-audio)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (gp-add-operator
   (make-operator :name 'connect
                  :preconditions '((device ?d) (power-state ?d on))
                  :add-list '((connection ?d computer))))
  (gp-plan :goals '((connection interface-01 computer)))
  (multiple-value-bind (text tr) (gp-explain :plan nil)
    (is (deliberative-trace-p tr))
    (is (search "Selected operator" text))
    (is (search "POWER-ON" text)))
  (gp-simulate)
  (multiple-value-bind (text tr) (gp-explain :last nil)
    (is (deliberative-trace-p tr))
    (is (search "Execution" text))))

;;; ---------------------------------------------------------------------------
;;; Fixtures
;;; ---------------------------------------------------------------------------

(defun %repl-door ()
  "A fresh session whose context can open a door, with the plan that does."
  (gp-reset)
  (gp-add-fact '(door closed))
  (gp-add-operator (make-operator :name 'open-door
                                  :preconditions '((door closed))
                                  :add-list '((door open))
                                  :delete-list '((door closed))))
  (gp-plan :goals '((door open)) :archive nil))

(defun %refusal-reason (thunk)
  "The reason THUNK was refused for. NIL when it returned; the type of any
other error it signalled."
  (handler-case (progn (funcall thunk) nil)
    (command-refused (c) (command-refused-reason c))
    (error (c) (type-of c))))

(defun %induction-reason (thunk)
  "The reason of the INDUCTION-ERROR THUNK signalled. NIL when it returned;
the type of any other error it signalled."
  (handler-case (progn (funcall thunk) nil)
    (induction-error (c) (induction-error-reason c))
    (error (c) (type-of c))))

;;; ---------------------------------------------------------------------------
;;; Arguments are checked at the boundary
;;; ---------------------------------------------------------------------------

(test repl-commands-check-their-arguments
  "A wrong argument is a TYPE-ERROR at the command, and changes nothing."
  (%repl-door)
  (let ((context (gp-context))
        (knowledge *knowledge-memory*)
        (facts (gp-facts))
        (operators (gp-operators))
        (plan (gp-last-plan)))
    (loop for (label thunk)
            in (list (list "a string fact" (lambda () (gp-add-fact "door open")))
                     (list "a symbol fact" (lambda () (gp-add-fact 'door-open)))
                     (list "a string goal" (lambda () (gp-add-goal "door open")))
                     (list "a number goal" (lambda () (gp-add-goal 42)))
                     (list "a NIL goal" (lambda () (gp-add-goal nil)))
                     (list "a rule name" (lambda () (gp-add-rule 'not-a-rule)))
                     (list "an operator name"
                           (lambda () (gp-add-operator 'not-an-operator)))
                     (list "an action name"
                           (lambda () (gp-register-action 'not-an-action)))
                     (list "a reaction name"
                           (lambda () (gp-add-reaction 'not-a-reaction)))
                     (list "a number for knowledge"
                           (lambda () (gp-knowledge-add 42)))
                     (list "a symbol among knowledge facts"
                           (lambda () (gp-knowledge :facts '((door open) shut))))
                     (list "a rule name among knowledge rules"
                           (lambda () (gp-knowledge :rules '(not-a-rule))))
                     (list "a symbol among the facts of a new context"
                           (lambda () (gp-context :name 'new :facts '(shut))))
                     (list "a rule name for a new context"
                           (lambda () (gp-context :name 'new
                                                  :rules '(not-a-rule))))
                     (list "an operator name for a new context"
                           (lambda () (gp-context :name 'new
                                                  :operators '(open-door))))
                     (list "a parent that is no context"
                           (lambda () (gp-context :name 'new :parent 'default)))
                     (list "a new context in a mode that is none"
                           (lambda () (gp-context :name 'new :mode :bogus)))
                     (list "operator names to plan with"
                           (lambda () (gp-plan :goals '((door open))
                                               :operators '(open-door))))
                     (list "an atom to plan with"
                           (lambda () (gp-plan :goals '((door open))
                                               :operators 'open-door)))
                     (list "a non-plan to simulate"
                           (lambda () (gp-simulate :plan 'not-a-plan)))
                     (list "a non-plan to run"
                           (lambda () (gp-run :plan 'not-a-plan)))
                     (list "a non-plan to remember"
                           (lambda () (gp-remember-procedure :plan 'not-a-plan)))
                     (list "an unknown listening reason"
                           (lambda () (gp-listen :reason :bogus)))
                     (list "an atom as missing goals"
                           (lambda () (gp-listen :missing 'door-open)))
                     (list "an atom as the before-state"
                           (lambda () (gp-learn-action 'shut :before 'door-open
                                                             :after '((door shut)))))
                     (list "a symbol among the before facts"
                           (lambda () (gp-induce-rule 'shut :before '(door-open)
                                                            :after '((door shut)))))
                     (list "a string among the after facts"
                           (lambda () (gp-learn-action 'shut
                                                       :before '((door open))
                                                       :after '("door shut"))))
                     (list "an atom as event meta"
                           (lambda () (gp-emit '(knock) :meta 'loud)))
                     (list "a mode that is none"
                           (lambda () (gp-mode :bogus))))
          do (is (typep (nth-value 1 (ignore-errors (funcall thunk)))
                        'type-error)
                 "~A was not refused with a TYPE-ERROR" label))
    (is (eq context (gp-context)))
    (is (eq knowledge *knowledge-memory*))
    (is (equal facts (gp-facts)))
    (is (null (gp-goals)))
    (is (null (gp-actions)))
    (is (null (gp-reactions)))
    (is (null (gp-events)))
    (is (null (gp-rules)))
    (is (equal operators (gp-operators)))
    (is (eq plan (gp-last-plan)))
    (is (null (gp-last-execution)))
    (is (eq :plan (gp-mode)))
    (is (not (observation-active-p)))))

(test repl-failure-strategy-sets-clears-and-validates
  (gp-reset)
  (is (null (gp-failure-strategy)))
  (dolist (policy '(:signal :skip :retry :abort :ask))
    (is (eq policy (strategy-policy (gp-failure-strategy policy))))
    (is (eq policy (strategy-policy (gp-failure-strategy)))))
  (let ((installed (gp-failure-strategy :skip)))
    (dolist (bad '(:skipp skip 3))
      (signals type-error (gp-failure-strategy bad))
      (is (eq installed (gp-failure-strategy))
          "the refused policy ~S replaced the strategy" bad))
    (signals type-error (gp-failure-strategy :retry -1))
    (is (eq installed (gp-failure-strategy)))
    ;; NIL is not a policy: it clears the strategy.
    (is (null (gp-failure-strategy nil)))
    (is (null (gp-failure-strategy)))))

;;; ---------------------------------------------------------------------------
;;; The session context
;;; ---------------------------------------------------------------------------

(test repl-context-is-created-only-with-a-name
  "A key without :NAME used to replace the session context with an empty
one named UNNAMED."
  (gp-reset)
  (gp-add-fact '(door closed))
  (let ((context (gp-context))
        (parent (create-context :name 'parent)))
    (dolist (keys (list '(:mode :plan)
                        '(:facts ((door open)))
                        (list :parent parent)
                        (list :rules (list (make-rule :name 'shut
                                                      :if '((door closed))
                                                      :then '(room quiet))))
                        (list :operators
                              (list (make-operator :name 'open-door)))))
      (is (eq :context-name-required
              (%refusal-reason (lambda () (apply #'gp-context keys))))
          "GP-CONTEXT ~S was not refused" (first keys))
      (is (eq context (gp-context)))
      (is (equal '((door closed)) (gp-facts)))
      (is (eq :read (gp-mode))))
    (let ((made (gp-context :name 'studio :mode :plan :facts '((door open)))))
      (is (eq made (gp-context)))
      (is (eq 'studio (context-name made)))
      (is (eq :plan (gp-mode)))
      (is (equal '((door open)) (gp-facts))))))

(test repl-a-new-session-context-drops-plan-execution-and-listening
  "The last plan, the last execution and the listening session belong to
the context they were made in, whichever command installs another one."
  (uiop:with-temporary-file (:pathname context-file :type "agp")
    (uiop:with-temporary-file (:pathname snapshot-file :type "agp")
      (%repl-door)
      (gp-save-context context-file)
      (gp-save snapshot-file :knowledge nil :episodic nil :procedural nil)
      (loop for (label switch)
              in (list (list "GP-CONTEXT" (lambda () (gp-context :name 'other)))
                       (list "GP-LOAD-CONTEXT"
                             (lambda () (gp-load-context context-file)))
                       (list "GP-LOAD" (lambda () (gp-load snapshot-file)))
                       (list "GP-RESET" #'gp-reset))
            do (%repl-door)
               (gp-simulate)
               (gp-note-state)
               (let ((before (gp-context)))
                 (funcall switch)
                 (is (not (eq before (gp-context)))
                     "~A kept the session context" label))
               (is (null (gp-last-plan)) "~A kept the plan" label)
               (is (null (gp-last-execution)) "~A kept the execution" label)
               (is (not (observation-active-p)) "~A kept listening" label)
               (is (null *observed-before*) "~A kept the before-state" label)
               (dolist (command (list #'gp-simulate #'gp-run))
                 (is (eq :no-plan (%refusal-reason command))
                     "after ~A a command still found a plan" label))
               ;; IS-TRUE: IS would evaluate both arguments of OR.
               (is-true (or (null *working-memory*)
                            (eq (context-name (gp-context))
                                (working-memory-context-name *working-memory*)))
                        "~A left working memory on the context before" label))
      ;; Loading without installing changes nothing in the session.
      (let ((plan (%repl-door))
            (context (gp-context)))
        (gp-load-context context-file :set-current nil)
        (gp-load snapshot-file :apply nil)
        (is (eq context (gp-context)))
        (is (eq plan (gp-last-plan)))))))

(test repl-save-writes-the-context-it-is-given
  "A context passed as :CONTEXT used to be replaced by the current one."
  (uiop:with-temporary-file (:pathname path :type "agp")
    (gp-reset)
    (gp-add-fact '(current context))
    (let ((other (create-context :name 'other :facts '((other context)))))
      (loop for (requested name fact)
              in (list (list other "OTHER" '(other context))
                       (list t "DEFAULT" '(current context)))
            do (gp-save path :context requested)
               (let ((saved (getf (gp-load path :apply nil) :context)))
                 (is (string= name (symbol-name (context-name saved))))
                 (is (= 1 (length (context-facts saved))))
                 (is-true (fact-same-names-p fact
                                             (first (context-facts saved))))))
      (gp-save path :context nil)
      (is (null (getf (gp-load path :apply nil) :context))))))

;;; ---------------------------------------------------------------------------
;;; Planning
;;; ---------------------------------------------------------------------------

(test repl-plan-refuses-a-request-with-nothing-to-plan
  "No goal, only labels, or goals that already hold: nothing changes."
  (loop for (label context-goals requested)
          in '(("no goal at all" () ())
               ("a label on the context" (audio-system-ready) ())
               ("labels requested" () (audio-system-ready tidy))
               ("a goal that already holds" () ((door closed)))
               ("a held goal and a label" () ((door closed) tidy)))
        do (let ((plan (%repl-door)))
             (gp-mode :read)
             (dolist (goal context-goals)
               (gp-add-goal goal))
             (let ((episodes (length (gp-episodes))))
               (is (eq :no-open-goal
                       (%refusal-reason (lambda () (gp-plan :goals requested))))
                   "~A was planned" label)
               (is (eq plan (gp-last-plan)) "~A replaced the plan" label)
               (is (eq :read (gp-mode)) "~A changed the mode" label)
               (is (not (observation-active-p)) "~A started listening" label)
               (is (= episodes (length (gp-episodes)))
                   "~A recorded an episode" label))))
  (gp-reset)
  (is (eq :no-open-goal (%refusal-reason #'gp-plan-open-goals)))
  (gp-add-fact '(door open))
  (is (eq :goal-holds
          (%refusal-reason (lambda () (gp-add-goal '(door open))))))
  (is (null (gp-goals))))

(test repl-plan-keeps-the-mode-when-the-planner-signals
  (let ((plan (%repl-door)))
    (gp-mode :read)
    (signals type-error
      (gp-plan :goals '((door open)) :operators '(:not-an-operator)))
    (is (eq :read (gp-mode)))
    (is (eq plan (gp-last-plan)))))

(test repl-simulate-refuses-what-run-would-refuse
  "A plan built with operators the context does not register simulated
successfully and was then refused by GP-RUN."
  (gp-reset)
  (gp-add-fact '(door closed))
  (let ((foreign (make-operator :name 'open-door
                                :preconditions '((door closed))
                                :add-list '((door open))
                                :delete-list '((door closed)))))
    (is-true (plan-success (gp-plan :goals '((door open))
                                    :operators (list foreign))))
    (dolist (command (list #'gp-simulate #'gp-run))
      (signals unknown-operator (funcall command))
      (is (eq :plan (gp-mode)))
      (is (null (gp-last-execution)))
      (is (equal '((door closed)) (gp-facts))))
    ;; Once the context registers the operator, both agree again.
    (gp-add-operator foreign)
    (is-true (execution-success (gp-simulate)))
    (is-true (execution-success (gp-run)))
    (is (equal '((door open)) (gp-facts)))))

(test repl-commands-that-need-a-plan-say-why-they-refuse
  (gp-reset)
  (gp-add-fact '(door closed))
  (flet ((refusals ()
           (mapcar #'%refusal-reason
                   (list #'gp-simulate #'gp-run #'gp-remember-procedure))))
    (is (equal '(:no-plan :no-plan :no-plan) (refusals)))
    (is (not (plan-success (gp-plan :goals '((door open)) :archive nil))))
    (is (equal '(:unsuccessful-plan :unsuccessful-plan :unsuccessful-plan)
               (refusals)))
    (is (eq :plan (gp-mode)))
    (is (null (gp-last-execution))))
  ;; The sentence names the command the same way from any package.
  (gp-reset)
  (let ((*package* (find-package :cl-user)))
    (is (string= "GP-SIMULATE requires a plan; call GP-PLAN first or pass :PLAN."
                 (princ-to-string (nth-value 1 (ignore-errors (gp-simulate))))))))

(test repl-simulate-and-run-leave-a-failed-step-to-the-caller
  "Under a :SIGNAL strategy the GP-ERROR of a failed step reaches a handler
bound around the command with the step restarts still active. The commands
used to signal it again from a HANDLER-CASE, after the restarts were gone."
  (loop for (command mode) in (list (list #'gp-simulate :simulate)
                                    (list #'gp-run :execute))
        do (flet ((failing-plan ()
                    ;; The only step of the plan needs (DOOR CLOSED).
                    (%repl-door)
                    (gp-remove-fact '(door closed))
                    (gp-failure-strategy :signal)))
             (dolist (restart '(:skip :abort-execution))
               (failing-plan)
               (let* ((offered nil)
                      (result
                        (handler-bind
                            ((gp-error
                               (lambda (condition)
                                 (setf offered
                                       (mapcar #'restart-name
                                               (compute-restarts condition)))
                                 (invoke-restart restart))))
                          (funcall command))))
                 (is (subsetp '(:retry :skip :abort-execution :use-value
                                :use-alternative :ask-user)
                              offered)
                     "~A offered only ~S" mode offered)
                 (is (not (execution-success result)))
                 (is (eq result (gp-last-execution)))
                 (is (eq mode (gp-mode)))))
             ;; A handler that leaves the command finds the mode as it was.
             (failing-plan)
             (signals precondition-failure (funcall command))
             (is (eq :plan (gp-mode)))
             (is (null (gp-last-execution)))
             ;; With no strategy the step is given up and the command returns.
             (failing-plan)
             (gp-failure-strategy nil)
             (is (not (execution-success (funcall command))))
             (is (eq mode (gp-mode))))))

;;; ---------------------------------------------------------------------------
;;; Listening and induction
;;; ---------------------------------------------------------------------------

(test repl-learns-from-an-empty-before-state
  "A session noted on a context with no fact is still a session."
  (dolist (learn (list #'gp-learn-action #'gp-induce-rule))
    (gp-reset)
    (gp-note-state)
    (is (observation-active-p))
    (gp-add-fact '(lamp on))
    (let ((operator (funcall learn 'switch-on)))
      (is (equal '((lamp on)) (operator-add-list operator)))
      (is (null (operator-preconditions operator)))
      (is (eq operator (find-operator (gp-context) 'switch-on)))
      (is (not (observation-active-p))))))

(test repl-listening-session-belongs-to-its-context
  "A before-state noted in one context used to be diffed against the facts
of another, which induced an operator that deletes facts it never saw."
  (dolist (learn (list #'gp-learn-action #'gp-induce-rule))
    (flet ((refusal ()
             (%refusal-reason (lambda () (funcall learn 'make-folder)))))
      ;; A context installed by a command ends the session.
      (gp-reset)
      (gp-add-fact '(device a1))
      (gp-note-state)
      (gp-context :name 'other)
      (gp-add-fact '(folder notes present))
      (is (eq :no-listening-session (refusal)))
      (is (null (gp-operators)))
      ;; A context bound around the command does not inherit it either.
      (gp-reset)
      (gp-add-fact '(device a1))
      (gp-note-state)
      (let ((*current-context* (create-context
                                :name 'elsewhere
                                :facts '((folder notes present)))))
        (is (eq :no-listening-session (refusal)))
        (is (null (gp-operators)))
        ;; An induction from explicit states succeeds there, and the
        ;; session of the other context is not its to end.
        (is (operator-p (funcall learn 'make-folder
                                 :before '((folder notes missing))
                                 :after '((folder notes present))))))
      ;; Back on its own context the session is still open.
      (is (observation-active-p))
      (is (null (gp-operators)))
      (gp-add-fact '(folder notes present))
      (let ((operator (funcall learn 'make-folder)))
        (is (null (operator-delete-list operator)))
        (is (= 1 (length (operator-add-list operator))))))))

(test repl-induction-refusals-are-typed-and-change-nothing
  (loop for (reason learn first-example second-example)
          in (list
              ;; An operator somebody wrote is not replaced by an example.
              (list :not-induced #'gp-learn-action nil
                    '(((folder notes missing)) ((folder notes present))))
              (list :not-induced #'gp-induce-rule nil
                    '(((folder notes missing)) ((folder notes present))))
              (list :uses-variables #'gp-learn-action
                    '(((power-state a1 off)) ((power-state a1 on)))
                    '(((power-state a1 off)) ((power-state a1 on))))
              (list :does-not-fit #'gp-learn-action
                    '(((folder notes missing)) ((folder notes present)))
                    '(((folder notes missing)) ((folder other present))))
              (list :does-not-fit #'gp-induce-rule
                    '(((port 80 busy)) ((port 80 free)))
                    '(((port 81 busy)) ((port 81 free))))
              (list :unchanged-state #'gp-learn-action nil
                    '(((folder notes present)) ((folder notes present)))))
        do (gp-reset)
           (cond
             ((eq reason :uses-variables)
              (gp-induce-rule 'target :before (first first-example)
                                      :after (second first-example)))
             (first-example
              (funcall learn 'target :before (first first-example)
                                     :after (second first-example)))
             ((eq reason :not-induced)
              (gp-add-operator (make-operator :name 'target
                                              :add-list '((written by hand))))))
           (gp-note-state)
           (let ((in-place (find-operator (gp-context) 'target))
                 (operators (gp-operators)))
             (is (eq reason
                     (%induction-reason
                      (lambda ()
                        (funcall learn 'target
                                 :before (first second-example)
                                 :after (second second-example)))))
                 "~A was not signalled" reason)
             (is (equal operators (gp-operators)))
             (is (eq in-place (find-operator (gp-context) 'target)))
             (is (observation-active-p)
                 "~A ended the listening session" reason))))

(test repl-an-action-of-the-same-name-is-not-an-induced-operator
  "With no operator in the context FIND-OPERATOR answers with a lifted
action, which is not an operator anybody registered."
  (dolist (learn (list #'gp-learn-action #'gp-induce-rule))
    (gp-reset)
    (gp-register-action (make-action :name 'make-folder :effects nil))
    (let ((operator (funcall learn 'make-folder
                             :before '((folder notes missing))
                             :after '((folder notes present)))))
      (is-true (getf (operator-meta operator) :induced))
      (is (eql 1 (getf (operator-meta operator) :examples)))
      (is (equal (list operator) (context-operators (gp-context)))))))

;;; ---------------------------------------------------------------------------
;;; The archive
;;; ---------------------------------------------------------------------------

(test repl-use-procedure-installs-the-plan-like-gp-plan
  (gp-clear-memory)
  (%repl-door)
  (gp-remember-procedure :name 'opener)
  (gp-add-goal '(door open))
  (gp-add-goal 'tidy)
  ;; A label among the goals is left out with or without the check.
  (dolist (unchecked '(nil t))
    (gp-mode :read)
    (setf *current-plan* nil)
    (let ((episodes (length (gp-episodes :kind :plan)))
          (plan (gp-use-procedure :unchecked unchecked)))
      (is-true (plan-success plan))
      (is (eq plan (gp-last-plan)))
      (is (equal '(opener) (plan-reused-procedure-names plan)))
      (is (eq :plan (gp-mode)))
      (is (eq :plan (working-memory-mode *working-memory*))
          "working memory still shows the mode before the plan")
      (is (= (1+ episodes) (length (gp-episodes :kind :plan))))))
  (let ((episodes (length (gp-episodes :kind :plan))))
    (gp-use-procedure :name 'opener :remember nil)
    (is (= episodes (length (gp-episodes :kind :plan)))))
  ;; A successful replay ends the session a failed plan opened, and no other.
  (dolist (reason '(:plan-failed :manual))
    (gp-listen :reason reason)
    (gp-use-procedure :name 'opener)
    (is (eq (eq reason :manual) (and (observation-active-p) t)))))

(test repl-use-procedure-says-why-no-plan-was-built
  (gp-clear-memory)
  (let ((plan (%repl-door)))
    (gp-remember-procedure :name 'opener)
    (signals unknown-procedure (gp-use-procedure :name 'no-such-procedure))
    (is (eq plan (gp-last-plan)))
    (is (equal '(opener)
               (plan-reused-procedure-names
                (handler-bind ((unknown-procedure
                                 (lambda (condition)
                                   (declare (ignore condition))
                                   (invoke-restart :use-value 'opener))))
                  (gp-use-procedure :name 'no-such-procedure)))))
    (setf *current-plan* plan)
    (loop for keys in '((:goals ((window open)))
                        (:goals ((window open)) :unchecked t)
                        (:goals (tidy))
                        (:goals (tidy) :unchecked t))
          do (is (eq :no-procedure
                     (%refusal-reason
                      (lambda () (apply #'gp-use-procedure keys))))
                 "GP-USE-PROCEDURE ~S found a procedure" keys))
    ;; The sentence repeats what was asked, the label included.
    (is (search "TIDY"
                (princ-to-string
                 (nth-value 1 (ignore-errors
                               (gp-use-procedure :goals '(tidy)))))))
    ;; The stored steps need (DOOR CLOSED).
    (gp-remove-fact '(door closed))
    (dolist (keys '((:name opener) (:goals ((door open)))))
      (is (eq :procedure-does-not-apply
              (%refusal-reason (lambda () (apply #'gp-use-procedure keys))))
          "GP-USE-PROCEDURE ~S replayed steps that do not apply" keys))
    (is (eq plan (gp-last-plan)))))

(test repl-use-procedure-combines-procedures-that-each-do-a-part
  "The combination its docstring promises was unreachable: the command gave
up as soon as no single procedure covered the request."
  (gp-clear-memory)
  (gp-reset)
  (loop for (operator goal procedure) in '((make-a (a done) part-a)
                                           (make-b (b done) part-b))
        do (gp-add-operator (make-operator :name operator
                                           :add-list (list goal)))
           (gp-plan :goals (list goal) :archive nil)
           (gp-remember-procedure :name procedure))
  (let ((plan (gp-use-procedure :goals '((a done) (b done)))))
    (is-true (plan-success plan))
    (is (null (set-exclusive-or '(part-a part-b)
                                (plan-reused-procedure-names plan))))
    (is (eq plan (gp-last-plan)))))

;;; ---------------------------------------------------------------------------
;;; Inference, explanation, events, autonomy
;;; ---------------------------------------------------------------------------

(test repl-infer-says-when-the-closure-was-cut
  (gp-reset)
  (gp-add-fact '(stage 0))
  (loop for (from to) on '(0 1 2 3)
        while to
        do (gp-add-rule (make-rule :if `((stage ,from))
                                   :then `(stage ,to))))
  (let ((warned nil))
    (multiple-value-bind (all new complete-p)
        (handler-bind ((forward-chain-incomplete
                         (lambda (warning)
                           (setf warned t)
                           (muffle-warning warning))))
          (gp-infer :limit 1 :assert t))
      (is-true warned)
      (is (null complete-p))
      (is (equal '((stage 1)) new))
      (is (equal '((stage 0) (stage 1)) all))
      ;; What was derived is sound and is asserted.
      (is (equal all (gp-facts)))))
  (multiple-value-bind (all new complete-p) (gp-infer :assert t)
    (is-true complete-p)
    (is (equal '((stage 2) (stage 3)) new))
    (is (equal all (gp-facts)))))

(test repl-explain-follows-the-format-stream-convention
  (%repl-door)
  (let* (text
         trace
         (printed (with-output-to-string (*standard-output*)
                    (setf (values text trace) (gp-explain :plan)))))
    (is (null text))
    (is (deliberative-trace-p trace))
    (is (search "OPEN-DOOR" printed))
    (multiple-value-bind (returned same-trace) (gp-explain :plan nil)
      (is (string= printed returned))
      (is (eq trace same-trace)))))

(test repl-emit-keeps-the-meta-of-an-event-posted-as-it-is
  (gp-reset)
  (let ((event (make-event :type 'knock :data '(front) :meta '(:source bell))))
    (is (eq event (gp-emit event)))
    (is (equal '(:source bell) (event-meta event))))
  (let ((event (make-event :type 'knock :data '(back) :meta '(:source bell))))
    (gp-emit event :meta '(:source hand))
    (is (equal '(:source hand) (event-meta event))))
  (is (equal '(:source form)
             (event-meta (gp-emit '(knock side) :meta '(:source form))))))

(test repl-react-plans-through-gp-plan
  "A plan asked of GP-REACT used to skip the archive and the listening
session a failed GP-PLAN opens."
  (flet ((knock (&rest keys)
           (apply #'gp-emit '(knock) :react t keys)
           (gp-last-reaction))
         (answer-knocks ()
           (gp-add-reaction (make-event-reaction :name 'answer
                                                 :when '(knock)
                                                 :goals '((door open))))))
    ;; An unreachable goal: the plan fails and the session listens.
    (gp-clear-memory)
    (gp-reset)
    (answer-knocks)
    (let ((summary (knock :plan t)))
      (is (plan-p (getf summary :plan)))
      (is (eq (getf summary :plan) (gp-last-plan)))
      (is (not (plan-success (gp-last-plan))))
      (is (eq :plan (gp-mode)))
      (is (eq :plan-failed (getf (gp-observation) :reason)))
      (is (equal '((door open)) (getf (gp-observation) :missing)))
      (is (= 1 (length (gp-episodes :kind :plan)))))
    ;; A remembered procedure is replayed, as GP-PLAN replays it.
    (%repl-door)
    (gp-remember-procedure :name 'opener)
    (answer-knocks)
    (let ((summary (knock :plan t)))
      (is-true (plan-success (getf summary :plan)))
      (is (equal '(opener) (plan-reused-procedure-names (gp-last-plan)))))
    ;; Without :PLAN, and with no open goal, the last plan stays.
    (let ((plan (gp-last-plan)))
      (is (null (getf (knock) :plan)))
      (is (eq plan (gp-last-plan)))
      (gp-run)
      (is (null (getf (knock :plan t) :plan)))
      (is (eq plan (gp-last-plan)))
      (is (eq :execute (gp-mode))))))

(test repl-autonomy-gate-follows-the-policy
  "A policy that does not react to events has no work in a pending event."
  (dolist (command (list #'gp-autonomous-step #'gp-autonomous-loop))
    (gp-reset)
    (is (eq :no-work (%refusal-reason command)))
    (gp-emit '(knock))
    (let ((deaf (make-autonomy-policy :react-events nil)))
      (is (eq :no-work
              (%refusal-reason (lambda () (funcall command :policy deaf)))))
      (is (null (gp-last-autonomy)))
      (is (= 1 (length (pending-events (gp-context)))))
      (signals type-error (funcall command :policy :not-a-policy))
      ;; The same event is work for a policy that reacts.
      (is (null (%refusal-reason command)))
      (is (null (pending-events (gp-context))))
      (is (not (null (gp-last-autonomy)))))))
