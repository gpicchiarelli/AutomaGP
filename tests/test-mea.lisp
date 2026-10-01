;;;; tests/test-mea.lisp

(in-package #:automa-gp/tests)

(def-suite mea-suite :in automa-gp-suite)
(in-suite mea-suite)

(defun studio-operators ()
  (list (make-operator :name 'power-on
                       :preconditions '((device ?d) (power-state ?d off))
                       :add-list '((power-state ?d on))
                       :delete-list '((power-state ?d off)))
        (make-operator :name 'connect
                       :preconditions '((device ?d) (power-state ?d on))
                       :add-list '((connection ?d computer)))))

(defun %op (name &key pre add del)
  (make-operator :name name :preconditions pre :add-list add :delete-list del))

(defmacro within-seconds ((seconds) &body body)
  "Values of BODY. A BODY that has not returned after SECONDS fails the
test instead of hanging the suite."
  `(handler-case (sb-ext:with-timeout ,seconds ,@body)
     (sb-ext:timeout ()
       (fail "no result after ~D seconds" ,seconds)
       nil)))

(defun %trace-statuses (plan)
  "The :STATUS of every :RESULT entry in PLAN's trace, in order."
  (mapcar (lambda (entry) (getf entry :status))
          (find-trace-entries :result (trace-of plan))))

(defun %planned-operators (steps)
  (mapcar (lambda (step) (getf step :operator)) steps))

(defun %self-bound-p (bindings)
  "True when BINDINGS binds some variable to itself."
  (some (lambda (pair) (eq (car pair) (cdr pair))) bindings))

(test differences-detects-missing
  (let ((facts '((device interface-01) (power-state interface-01 off)))
        (goals '((power-state interface-01 on)
                 (connection interface-01 computer))))
    (is (= 2 (length (differences facts goals))))
    (is (goal-holds-p '(device interface-01) facts))))

(test apply-operator-updates-state
  (let* ((op (first (studio-operators)))
         (facts '((device interface-01) (power-state interface-01 off)))
         (b (unify '(power-state interface-01 on)
                   '(power-state ?d on)))
         (next (apply-operator facts op b)))
    (is (fact-p '(power-state interface-01 on) next))
    (is (not (fact-p '(power-state interface-01 off) next)))))

(test mea-with-subgoals
  (let ((facts '((device interface-01) (power-state interface-01 off)))
        (goals '((connection interface-01 computer)))
        (ops (studio-operators)))
    (multiple-value-bind (ok final plan left)
        (means-ends-analyze facts goals ops)
      (is-true ok)
      (is (null left))
      (is (fact-p '(connection interface-01 computer) final))
      (is (fact-p '(power-state interface-01 on) final))
      (is (>= (length plan) 2))
      (is (equal 'power-on (getf (first plan) :operator)))
      (is (equal 'connect (getf (second plan) :operator)))
      (is (equal '((power-state interface-01 on))
                 (getf (second plan) :subgoals))))))

;;; --- Slot retraction ---

(test slot-retraction-only-touches-three-element-facts
  ;; Each case is (FACTS ADD EXPECTED).
  (dolist (case '((((device d1 audio) (device d1) (other x))
                   (device d1)
                   ((device d1 audio) (device d1) (other x)))
                  (((power-state d1) (foo))
                   (power-state d1 on)
                   ((power-state d1) (foo)))
                  (((flag))
                   (flag)
                   ((flag)))
                  (((link d1 a b) (link d1 c))
                   (link d1 x y)
                   ((link d1 a b) (link d1 c)))
                  (((p a 1 2) (p a 1) (p a))
                   (p a 2)
                   ((p a 1 2) (p a)))
                  ;; A slot needs a predicate and an object.
                  (((nil d1 off) (p nil 1))
                   (nil d1 on)
                   ((nil d1 off) (p nil 1)))
                  (((nil d1 off) (p nil 1))
                   (p nil 2)
                   ((nil d1 off) (p nil 1)))
                  (((p a 1))
                   p
                   ((p a 1)))
                  (((power-state d1 off) (power-state d2 off) (device d1))
                   (power-state d1 on)
                   ((power-state d2 off) (device d1)))))
    (destructuring-bind (facts add expected) case
      (is (equal expected (retract-slot-conflicts facts add))
          "asserting ~S into ~S" add facts))))

(test stored-effects-can-keep-several-values
  (let ((facts '((device d1) (connection d1 computer))))
    (is (equal '((device d1) (connection d1 speaker))
               (apply-stored-effects facts '((connection d1 speaker)) nil)))
    (is (equal '((device d1) (connection d1 computer) (connection d1 speaker))
               (apply-stored-effects facts '((connection d1 speaker)) nil
                                     :conflict-retract nil)))))

;;; --- Grounding ---

(test grounding-fails-on-an-unbound-variable
  (is (equal '(mode d1 fast)
             (ground-pattern '(mode ?d ?m) '((?d . d1) (?m . fast)))))
  (is (fail-p (ground-pattern '(mode ?d ?m) '((?d . d1)))))
  (is (fail-p (ground-pattern '(mode ?d ?m) *no-bindings*)))
  (is (fail-p (ground-pattern '(mode ?d ?m) *fail*)))
  ;; The anonymous variable is a wildcard, not something left to bind.
  (is (equal '(mode d1 ?) (ground-pattern '(mode ?d ?) '((?d . d1))))))

(test effects-that-do-not-ground-are-not-asserted
  (let* ((op (%op 'ready
                  :pre '((device ?d))
                  :add '((ready ?d) (mode ?d ?m) (seen ?d ?))
                  :del '((idle ?d) (mode ?d ?old))))
         (facts '((device d1) (idle d1) (mode d1 slow)))
         (next (apply-operator facts op '((?d . d1)))))
    (is (equal '((mode ?d ?m) (seen ?d ?)) (ungrounded-adds op '((?d . d1)))))
    (is (null (ungrounded-adds (first (studio-operators)) '((?d . d1)))))
    (is (fact-p '(ready d1) next))
    (is (not (fact-p '(idle d1) next)))
    ;; The delete that did not ground removed nothing.
    (is (fact-p '(mode d1 slow) next))
    (is (notany #'automa-gp::pattern-has-variable-p next))
    ;; A recorded effect that still holds a variable is not asserted either,
    ;; and one that is not a fact at all changes nothing.
    (is (equal facts (apply-stored-effects facts '((mode d1 ?m)) nil)))
    (is (equal facts (apply-stored-effects facts '(ready (seen d1 ?))
                                           '(idle (mode d1 ?old) (mode ? slow)))))
    ;; Failed bindings ground nothing.
    (is (equal facts (apply-operator facts op *fail*)))
    (is (equal (operator-add-list op) (ungrounded-adds op *fail*)))
    (is (fail-p (extend-bindings-from-state (operator-preconditions op)
                                            *fail* facts)))))

(test recorded-preconditions-are-checked-against-the-facts
  (let ((facts '((a 1) (b 2))))
    ;; Each case is (RECORDED-PRECONDITIONS MISSING).
    (dolist (case '((nil nil)
                    (((a 1) (b 2)) nil)
                    (((a 1) (c 3)) ((c 3)))
                    ;; The anonymous variable is recorded as it is.
                    (((b ?) (c ?)) ((c ?)))
                    ;; Something that is not a fact cannot hold.
                    ((a (a 1)) (a))))
      (destructuring-bind (recorded missing) case
        (is (equal missing
                   (missing-stored-preconditions (list :preconditions recorded)
                                                 facts)))))))

(test operator-with-an-ungrounded-add-is-refused
  (let* ((op (%op 'ready
                  :pre '((device ?d))
                  :add '((ready ?d) (mode ?d ?m))))
         (facts '((device d1)))
         (plan (plan-for facts '((ready d1)) (list op)))
         (trace (trace-of plan)))
    (is-false (plan-success plan))
    (is (null (plan-steps plan)))
    (is (equal facts (plan-final-state plan)))
    (is (equal '((ready d1)) (plan-remaining plan)))
    (let ((failed (find-trace-entries :operator-failed trace)))
      (is (= 1 (length failed)))
      (is (eq :ungrounded-effect (getf (first failed) :reason)))
      (is (equal '((mode ?d ?m)) (getf (first failed) :patterns))))
    ;; No recorded binding maps a variable to itself: substituting such a
    ;; pair would never return.
    (dolist (kind '(:selected-operator :action))
      (dolist (entry (find-trace-entries kind trace))
        (is (not (%self-bound-p (getf entry :bindings))))))))

(test plan-step-bindings-are-ground
  (let* ((op (%op 'use-tool
                  :pre '((available ?t) (device ?d))
                  :add '((done ?d))
                  :del '((scratch ?d ?old))))
         (step (make-plan-step op '((?d . d1)) '(done d1) nil)))
    ;; ?T has no value yet and ?OLD is never bound: neither is recorded.
    (is (equal '((?d . d1)) (getf step :bindings)))
    (is (null (getf step :preconditions-stored)))
    (is (equal '((device d1)) (getf step :preconditions)))
    (is (equal '((done d1)) (getf step :adds)))
    (is (null (getf step :deletes))))
  (multiple-value-bind (ok final steps)
      (means-ends-analyze '((device interface-01) (power-state interface-01 off))
                          '((connection interface-01 computer))
                          (studio-operators))
    (declare (ignore final))
    (is-true ok)
    (dolist (step steps)
      (is (getf step :preconditions-stored))
      (is (not (%self-bound-p (getf step :bindings))))
      (is (notany #'automa-gp::pattern-has-variable-p
                  (mapcar #'cdr (getf step :bindings)))))))

;;; --- Search from an empty state ---

(test mea-starts-from-an-empty-state
  (multiple-value-bind (ok final steps left)
      (means-ends-analyze nil '((a 1)) (list (%op 'make-a :add '((a 1)))))
    (is-true ok)
    (is (equal '((a 1)) final))
    (is (equal '(make-a) (%planned-operators steps)))
    (is (null left)))
  (multiple-value-bind (ok final steps left)
      (means-ends-analyze nil nil nil)
    (is-true ok)
    (is (null final))
    (is (null steps))
    (is (null left)))
  ;; The third value tells an empty state from a failure.
  (is (equal '(nil nil t) (multiple-value-list (achieve-all nil nil nil nil 0))))
  (is (equal '(nil nil nil)
             (multiple-value-list (achieve '(a 1) nil nil nil 0)))))

;;; --- Goal interactions ---

(test sibling-goals-that-undo-each-other-fail
  ;; Each case is (FACTS GOALS OPERATORS). Before goals were protected the
  ;; search achieved one goal, undid it with the next, and never returned.
  (dolist (case (list
                 (list '((x 0))
                       '((a 1) (b 1))
                       (list (%op 'make-a :add '((a 1)) :del '((b 1)))
                             (%op 'make-b :add '((b 1)) :del '((a 1)))))
                 ;; Two values for one (PREDICATE OBJECT) slot.
                 (list '((device d1))
                       '((connection d1 computer) (connection d1 speaker))
                       (list (%op 'connect-computer
                                  :pre '((device ?d))
                                  :add '((connection ?d computer)))
                             (%op 'connect-speaker
                                  :pre '((device ?d))
                                  :add '((connection ?d speaker)))))))
    (destructuring-bind (facts goals operators) case
      (let ((plan (within-seconds (10) (plan-for facts goals operators))))
        (is (plan-p plan))
        (when (plan-p plan)
          (is-false (plan-success plan))
          (is (null (plan-steps plan)))
          (is (equal facts (plan-final-state plan)))
          (is (equal goals (plan-remaining plan)))
          (is (member :goal-clobbered (%trace-statuses plan))))))))

(test goal-undone-by-a-later-one-is-achieved-again
  ;; Each case is (OPERATORS GOALS EXPECTED-OPERATORS).
  (dolist (case (list
                 (list (list (%op 'make-a :add '((a 1)))
                             (%op 'make-b :add '((b 1)) :del '((a 1))))
                       '((a 1) (b 1))
                       '(make-a make-b make-a))
                 ;; MAKE-B undoes A and MAKE-A undoes C.
                 (list (list (%op 'make-a :add '((a 1)) :del '((c 1)))
                             (%op 'make-b :add '((b 1)) :del '((a 1)))
                             (%op 'make-c :add '((c 1))))
                       '((a 1) (b 1) (c 1))
                       '(make-a make-b make-a make-c))))
    (destructuring-bind (operators goals expected) case
      (multiple-value-bind (ok final steps left)
          (within-seconds (10) (means-ends-analyze '((x 0)) goals operators))
        (is-true ok)
        (is (null left))
        (is (null (differences final goals)))
        (is (equal expected (%planned-operators steps)))))))

(test subgoal-undone-by-a-sibling-subgoal-fails-the-operator
  ;; BUILD needs both A and B, and achieving either one removes the other.
  (let* ((operators (list (%op 'build :pre '((a 1) (b 1)) :add '((built 1)))
                          (%op 'make-a :add '((a 1)) :del '((b 1)))
                          (%op 'make-b :add '((b 1)) :del '((a 1)))))
         (plan (within-seconds (10)
                 (plan-for '((x 0)) '((built 1)) operators))))
    (is (plan-p plan))
    (when (plan-p plan)
      (is-false (plan-success plan))
      (is (member :goal-clobbered (%trace-statuses plan))))))

(test precondition-undone-by-a-subgoal-is-achieved-again
  ;; BUILD needs A and B. A holds at the start and MAKE-B removes it.
  (let ((operators (list (%op 'build :pre '((a 1) (b 1)) :add '((built 1)))
                         (%op 'make-b :add '((b 1)) :del '((a 1)))
                         (%op 'make-a :add '((a 1))))))
    (multiple-value-bind (ok final steps left)
        (within-seconds (10)
          (means-ends-analyze '((a 1)) '((built 1)) operators))
      (is-true ok)
      (is (null left))
      (is (equal '(make-b make-a build) (%planned-operators steps)))
      (is (null (differences final '((a 1) (b 1) (built 1)))))
      ;; The step still names the subgoals that were missing when BUILD was
      ;; chosen.
      (is (equal '((b 1)) (getf (third steps) :subgoals))))))

(test operator-is-refused-when-its-preconditions-do-not-hold-together
  ;; CUT needs one thing that is both held and sharp. The two subgoals
  ;; share a variable but are achieved one at a time, and here they are
  ;; answered with different things: CUT must not be applied.
  (let* ((operators (list (%op 'cut
                               :pre '((holding ?p) (sharp ?p))
                               :add '((cut 1)))
                          (%op 'grab :pre '((tool ?q)) :add '((holding ?q)))
                          (%op 'sharpen :pre '((blade ?q)) :add '((sharp ?q)))))
         (plan (plan-for '((tool hammer) (blade knife)) '((cut 1)) operators))
         (failed (find-trace-entries :operator-failed (trace-of plan))))
    (is-false (plan-success plan))
    (is (null (plan-steps plan)))
    (is (= 1 (length failed)))
    (is (eq :preconditions-unmet (getf (first failed) :reason)))
    (is (equal '((sharp hammer)) (getf (first failed) :missing)))
    (is (member :missing
                (mapcar (lambda (entry) (getf entry :status))
                        (find-trace-entries :precondition (trace-of plan)))))))

(test operator-whose-effects-undo-the-goal-is-refused
  ;; The second add takes the slot the first one filled.
  (let* ((operators (list (%op 'switch
                               :pre '((device ?d))
                               :add '((state ?d on) (state ?d ready)))))
         (plan (plan-for '((device d1)) '((state d1 on)) operators)))
    (is-false (plan-success plan))
    (is (null (plan-steps plan)))
    (is (equal '((state d1 on)) (plan-remaining plan)))
    (is (member :goal-not-achieved (%trace-statuses plan)))))

(test achieve-returns-the-state-when-the-goal-already-holds
  (let ((state '((a 1)))
        (plan '(:earlier-step)))
    (is (equal (list state plan t)
               (multiple-value-list (achieve '(a 1) state nil plan 0))))
    ;; A goal that holds is not a cycle, even when it is being pursued.
    (is (equal (list state plan t)
               (multiple-value-list
                (achieve '(a 1) state nil plan 0 '((a 1))))))
    (is-true (goal-holds-p nil state))
    (is-true (goal-holds-p '(a ?x) state))
    (is-false (goal-holds-p '(b ?x) state))))

(defun %cycle-operators (&rest more)
  "Two ways to G that need P and two ways to P that need G, then MORE."
  (append (list (%op 'g-first :pre '((p 1)) :add '((g 1)))
                (%op 'g-second :pre '((p 1)) :add '((g 1)))
                (%op 'p-first :pre '((g 1)) :add '((p 1)))
                (%op 'p-second :pre '((g 1)) :add '((p 1))))
          more))

(test goal-needed-for-itself-fails-at-once
  ;; The work must not depend on the depth limit. With only the limit to
  ;; stop it, each level doubled the search.
  (let ((selections nil))
    (dolist (limit '(4 8 16 32 64))
      (let* ((*plan-depth-limit* limit)
             (plan (within-seconds (10)
                     (plan-for '((x 0)) '((g 1)) (%cycle-operators)))))
        (is (plan-p plan))
        (when (plan-p plan)
          (is-false (plan-success plan))
          (is (member :goal-cycle (%trace-statuses plan)))
          (is (not (member :depth-limit (%trace-statuses plan))))
          (push (length (find-trace-entries :selected-operator (trace-of plan)))
                selections))))
    (is (= 5 (length selections)))
    (is (= 1 (length (remove-duplicates selections))))))

(test goal-cycle-leaves-the-direct-operator-reachable
  (multiple-value-bind (ok final steps)
      (within-seconds (10)
        (means-ends-analyze '((x 0)) '((g 1))
                            (%cycle-operators (%op 'p-direct :add '((p 1))))))
    (is-true ok)
    (is (fact-p '(g 1) final))
    (is (equal '(p-direct g-first) (%planned-operators steps)))))

(test depth-limit-stops-a-chain-of-distinct-subgoals
  (let* ((operators (loop for k from 1 to 6
                          collect (%op (intern (format nil "STEP-~D" k))
                                       :pre (list (list 'level (1- k)))
                                       :add (list (list 'level k)))))
         (facts '((level 0))))
    (let ((*plan-depth-limit* 6))
      (is-true (means-ends-analyze facts '((level 6)) operators)))
    (let* ((*plan-depth-limit* 5)
           (plan (plan-for facts '((level 6)) operators)))
      (is-false (plan-success plan))
      (is (member :depth-limit (%trace-statuses plan))))))

;;; --- Variables ---

(test goal-variables-are-kept-apart-from-operator-variables
  (let ((operators (list (%op 'make-pair
                              :pre '((first ?b) (second ?a))
                              :add '((pair ?b ?a)))))
        (facts '((first x) (second c))))
    ;; The goal asks for any pair ending in C. Its variable is not the
    ;; operator's, whatever it is called.
    (dolist (variable '(?a ?b ?z ?))
      (multiple-value-bind (ok final steps)
          (means-ends-analyze facts (list (list 'pair variable 'c)) operators)
        (is-true ok "goal (PAIR ~A C)" variable)
        (is (fact-p '(pair x c) final))
        (is (equal '((?b . x) (?a . c))
                   (getf (first steps) :bindings))))))
  ;; The subgoal (FITS ?T D1) carries USE's variable into ADAPT, which
  ;; gives the same names the opposite roles.
  (let ((operators (list (%op 'use
                              :pre '((fits ?t ?d))
                              :add '((done ?d)))
                         (%op 'adapt
                              :pre '((tool ?d) (device ?t))
                              :add '((fits ?d ?t)))))
        (facts '((tool t1) (device d1))))
    (multiple-value-bind (ok final steps)
        (means-ends-analyze facts '((done d1)) operators)
      (is-true ok)
      (is (fact-p '(fits t1 d1) final))
      (is (equal '(adapt use) (%planned-operators steps))))))

(test free-precondition-variables-are-bound-together
  (let ((op (%op 'use-tool
                 :pre '((available ?t) (compatible ?t ?d))
                 :add '((done ?d))))
        (facts '((available t1) (available t2) (compatible t2 d1))))
    ;; T1 is available but only T2 is also compatible.
    (is (equal 't2 (cdr (assoc '?t (extend-bindings-from-state
                                    (operator-preconditions op)
                                    '((?d . d1))
                                    facts)))))
    (multiple-value-bind (ok final steps)
        (means-ends-analyze facts '((done d1)) (list op))
      (is-true ok)
      (is (fact-p '(done d1) final))
      (is (equal 't2 (cdr (assoc '?t (getf (first steps) :bindings))))))
    ;; No fact satisfies both: each pattern takes its own first match and
    ;; the unmatched one becomes the subgoal.
    (let ((b (extend-bindings-from-state (operator-preconditions op)
                                         '((?d . d1))
                                         '((available t1) (available t2)))))
      (is (equal 't1 (cdr (assoc '?t b))))
      (is (equal '((compatible t1 d1))
                 (precondition-subgoals op b '((available t1) (available t2))))))))

;;; --- Trace ---

(test top-level-differences-are-recorded-once-per-state
  (flet ((recorded (goals)
           (mapcar (lambda (entry) (getf entry :goals))
                   (find-trace-entries
                    :differences
                    (trace-of (plan-for '((x 0)) goals
                                        (list (%op 'make-a :add '((a 1)))
                                              (%op 'make-b :add '((b 1))))))))))
    (is (equal '(((a 1))) (recorded '((a 1)))))
    (is (equal '(((a 1) (b 1)) ((b 1))) (recorded '((a 1) (b 1)))))
    (is (null (recorded '((x 0)))))))

(test exported-mea-functions-are-documented
  (dolist (name '(goal-holds-p differences apply-operator apply-stored-effects
                  retract-slot-conflicts ground-pattern ungrounded-adds
                  extend-bindings-from-state precondition-subgoals
                  missing-stored-preconditions make-plan-step achieve
                  achieve-all means-ends-analyze))
    (is (eq :external
            (nth-value 1 (find-symbol (symbol-name name) :automa-gp))))
    (is (fboundp name))
    (is (documentation name 'function)))
  (is (documentation '*plan-depth-limit* 'variable)))
