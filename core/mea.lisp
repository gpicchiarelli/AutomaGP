;;;; core/mea.lisp — Means-Ends Analysis (Phase 3+)
;;;;
;;;; GPS-style / Norvig: differences → operator → preconditions as subgoals
;;;; → recursive achievement. Records deliberative events into *CURRENT-TRACE*.
;;;;
;;;; The search is linear and depth-first. A plan it returns is correct for
;;;; the symbolic state; a failure means this search found no plan, not that
;;;; none exists. Three guards keep it finite: a goal already being pursued
;;;; is not pursued again beneath itself, goals that keep undoing one another
;;;; are given up, and *PLAN-DEPTH-LIMIT* bounds chains of distinct subgoals.

(in-package #:automa-gp)

(defparameter *plan-depth-limit* 32
  "Maximum depth of nested subgoals in Means-Ends Analysis.
A goal that is needed again beneath itself fails at once (see ACHIEVE), so
this limit only stops chains of distinct subgoals.")

(defun goal-holds-p (goal facts)
  "True if GOAL is already satisfied in FACTS.
Concrete goals use EQUAL; patterns with variables need ≥1 match."
  (cond
    ((null goal) t)
    ((pattern-has-variable-p goal)
     (not (null (find-facts goal facts))))
    (t (not (null (fact-p goal facts))))))

(defun differences (facts goals)
  "Goals not yet satisfied in FACTS (MEA differences)."
  (remove-if (lambda (g) (goal-holds-p g facts)) goals))

;;; Effects

(defun %slot-fact-p (fact)
  "True when FACT is a three-element list (PREDICATE OBJECT VALUE) with a
predicate and an object."
  (and (consp fact)
       (consp (cdr fact))
       (consp (cddr fact))
       (null (cdddr fact))
       (first fact)
       (second fact)
       t))

(defun retract-slot-conflicts (facts add)
  "FACTS without the facts that asserting ADD replaces.
This is a simplification applied to every predicate: a three-element fact
(PREDICATE OBJECT VALUE) is read as a slot with one value, as in
(POWER-STATE D1 ON), so asserting ADD drops every three-element fact with
the same PREDICATE and OBJECT. A relation that needs several values for one
object cannot be kept as three-element facts under this rule.
Facts of any other length are never dropped, and an ADD of any other length
drops nothing."
  (if (%slot-fact-p add)
      (remove-if (lambda (fact)
                   (and (%slot-fact-p fact)
                        (equal (first fact) (first add))
                        (equal (second fact) (second add))))
                 facts)
      facts))

(defun ground-pattern (pattern bindings)
  "PATTERN with BINDINGS substituted, or *FAIL*.
*FAIL* when BINDINGS is *FAIL* or a named variable is still unbound. The
anonymous variable ? stays in place, where it still matches anything."
  (let ((instance (substitute-bindings pattern bindings)))
    (if (or (fail-p instance) (variables-in instance))
        *fail*
        instance)))

(defun %effect-fact-p (object)
  "True when OBJECT can be asserted or retracted: a list with no variable in
it, the anonymous ? included."
  (and (consp object)
       (not (pattern-has-variable-p object))))

(defun %ground-effects (patterns bindings)
  "The facts PATTERNS stand for under BINDINGS.
A pattern that is not a fact under BINDINGS is left out."
  (loop for pattern in patterns
        for instance = (substitute-bindings pattern bindings)
        when (and (not (fail-p instance)) (%effect-fact-p instance))
          collect instance))

(defun ungrounded-adds (operator bindings)
  "Add-list patterns of OPERATOR that are not facts under BINDINGS.
Each still holds a variable, so APPLY-OPERATOR would leave it out. An
operator that is to be applied in full needs this to be NIL."
  (remove-if (lambda (pattern)
               (let ((instance (substitute-bindings pattern bindings)))
                 (and (not (fail-p instance))
                      (not (pattern-has-variable-p instance)))))
             (operator-add-list operator)))

(defun apply-stored-effects (facts adds deletes &key (conflict-retract t))
  "Apply already-ground ADDS and DELETES to FACTS; return a new fact list.
Deletes come first. With CONFLICT-RETRACT (the default) each add then drops
the facts it replaces (RETRACT-SLOT-CONFLICTS) before it is asserted.
An element that is not a fact, because it is an atom or still holds a
variable, is left out. No adapters and no precondition check."
  (let ((state (copy-list facts)))
    (dolist (del deletes)
      (when (%effect-fact-p del)
        (setf state (remove-fact! state del))))
    (dolist (add adds)
      (when (%effect-fact-p add)
        (when conflict-retract
          (setf state (retract-slot-conflicts state add)))
        (setf state (add-fact! state add))))
    state))

(defun apply-operator (facts operator bindings &key (conflict-retract t))
  "Symbolically apply OPERATOR to FACTS under BINDINGS.
Returns a new fact list. Does not touch the live context or adapters.
Effects are applied as by APPLY-STORED-EFFECTS: deletes, then adds, and
only the effects that are ground under BINDINGS. A delete pattern left with
a variable deletes nothing; an add pattern left with one is not asserted
(UNGROUNDED-ADDS names those)."
  (apply-stored-effects facts
                        (%ground-effects (operator-add-list operator) bindings)
                        (%ground-effects (operator-delete-list operator) bindings)
                        :conflict-retract conflict-retract))

;;; Preconditions and bindings

(defun %ground-all (patterns bindings)
  "Ground every PATTERN. Returns (VALUES GROUNDED COMPLETE-P).
A pattern that does not ground (GROUND-PATTERN) is left out and makes
COMPLETE-P false."
  (let ((out nil)
        (complete t))
    (dolist (pat patterns)
      (let ((g (ground-pattern pat bindings)))
        (if (fail-p g)
            (setf complete nil)
            (push g out))))
    (values (nreverse out) complete)))

(defun missing-stored-preconditions (step facts)
  "Recorded preconditions of STEP that do not hold in FACTS."
  (loop for pre in (getf step :preconditions)
        unless (and (consp pre) (goal-holds-p pre facts))
          collect pre))

(defun %joint-match (patterns facts bindings)
  "First bindings under which every pattern in PATTERNS matches some fact in
FACTS, or *FAIL*. Depth-first, in pattern order and fact order."
  (if (null patterns)
      bindings
      (dolist (fact facts *fail*)
        (let ((b (match (first patterns) fact bindings)))
          (unless (fail-p b)
            (let ((all (%joint-match (rest patterns) facts b)))
              (unless (fail-p all)
                (return all))))))))

(defun extend-bindings-from-state (patterns bindings facts)
  "Extend BINDINGS by matching the still-open variables of PATTERNS in FACTS.
When FACTS satisfy all the open patterns at once, the first such joint match
is returned, so the choice made for one pattern never rules out another.
Otherwise each open pattern takes its own first match in turn and a pattern
that matches nothing stays open, to become a subgoal. That second case does
not go back over its choices: another fact for an earlier pattern is not
tried."
  (let ((open (loop for pattern in patterns
                    for partial = (substitute-bindings pattern bindings)
                    when (and (not (fail-p partial)) (variables-in partial))
                      collect partial)))
    (let ((joint (if (every (lambda (pattern) (find-facts pattern facts)) open)
                     (%joint-match open facts bindings)
                     *fail*)))
      (if (fail-p joint)
          (let ((b bindings))
            (dolist (pattern open b)
              (let ((solutions (match-all (list (substitute-bindings pattern b))
                                          facts b)))
                (when solutions
                  (setf b (first solutions))))))
          joint))))

(defun precondition-subgoals (operator bindings facts)
  "Preconditions of OPERATOR, instantiated by BINDINGS, that do not hold in
FACTS. One that still has a variable holds when some fact matches it."
  (loop for pre in (operator-preconditions operator)
        for g = (substitute-bindings pre bindings)
        unless (or (fail-p g) (goal-holds-p g facts))
          collect g))

(defun %operator-bindings (operator bindings)
  "Alist from the variables of OPERATOR's preconditions and add list to
their values under BINDINGS.
A variable with no ground value yet is left out. The alist therefore never
binds a variable to itself, which SUBSTITUTE-BINDINGS would follow forever."
  (loop for var in (remove-duplicates
                    (variables-in (append (operator-preconditions operator)
                                          (operator-add-list operator)))
                    :test #'eq)
        for value = (substitute-bindings var bindings)
        unless (or (fail-p value) (pattern-has-variable-p value))
          collect (cons var value)))

(defun make-plan-step (operator bindings goal subgoals)
  "A single planned step (plist).
:BINDINGS gives OPERATOR's variables their ground values. :ADDS and
:DELETES are the effects grounded at plan time. :PRECONDITIONS are the
grounded preconditions, and :PRECONDITIONS-STORED is true only when
every precondition grounded. A later replay can apply that record when
OPERATOR is no longer registered."
  (multiple-value-bind (pres complete)
      (%ground-all (operator-preconditions operator) bindings)
    (list :operator (operator-name operator)
          :bindings (%operator-bindings operator bindings)
          :goal goal
          :subgoals subgoals
          :action (operator-action operator)
          :cost (operator-cost operator)
          :adds (%ground-effects (operator-add-list operator) bindings)
          :deletes (%ground-effects (operator-delete-list operator) bindings)
          :effects-stored t
          :preconditions pres
          :preconditions-stored complete
          :risk (operator-risk operator)
          :reversible (operator-reversible operator))))

;;; Core MEA (with deliberative recording)
;;;
;;; ACHIEVE, TRY-OPERATOR and ACHIEVE-ALL return (VALUES STATE PLAN T) on
;;; success and (VALUES NIL NIL NIL) on failure. The third value is the
;;; verdict: a state can be the empty list.

(defun %rename-variables (pattern)
  "PATTERN with each named variable replaced by a fresh uninterned variable
of the same name."
  (sublis (mapcar (lambda (var) (cons var (make-symbol (symbol-name var))))
                  (remove-duplicates (variables-in pattern) :test #'eq))
          pattern
          :test #'eq))

(defun %same-facts-p (a b)
  "True when fact lists A and B hold the same facts, in any order."
  (and (subsetp a b :test #'fact-equal)
       (subsetp b a :test #'fact-equal)))

(defun achieve (goal state operators plan depth &optional goal-stack)
  "Achieve GOAL from STATE using OPERATORS, extending PLAN.
GOAL-STACK lists the goals being pursued above this one. A GOAL that is on
it and does not hold fails at once: needing a goal in order to reach that
same goal is a cycle. GOAL's variables are kept apart from the variables of
the operators tried, whatever their names.
Returns (VALUES NEW-STATE NEW-PLAN T), or (VALUES NIL NIL NIL) on failure.
NEW-STATE can be the empty list, so test the third value."
  (cond
    ((goal-holds-p goal state)
     (trace-record :goal-already-satisfied :goal goal :depth depth)
     (values state plan t))
    ((member goal goal-stack :test #'equal)
     (trace-record :result :status :goal-cycle :goal goal)
     (values nil nil nil))
    ((>= depth *plan-depth-limit*)
     (trace-record :result :status :depth-limit :goal goal)
     (values nil nil nil))
    (t
     (trace-record :difference :goal goal :depth depth)
     (let ((candidates (operators-for-goal (%rename-variables goal) operators)))
       (unless candidates
         (trace-record :result :status :no-operator :goal goal))
       (loop for (operator . bindings) in candidates
             do (multiple-value-bind (new-state new-plan ok)
                    (try-operator operator goal bindings state operators plan
                                  depth goal-stack)
                  (when ok
                    (return (values new-state new-plan t))))
             finally (return (values nil nil nil)))))))

(defun try-operator (operator goal bindings state operators plan depth
                     &optional goal-stack)
  "Try OPERATOR to achieve GOAL: satisfy precondition subgoals, then apply.
Returns (VALUES NEW-STATE NEW-PLAN T). Returns (VALUES NIL NIL NIL) when a
subgoal cannot be achieved, a precondition is still missing afterwards, an
add pattern is left with a variable, or GOAL does not hold after the
effects."
  (let* ((name (operator-name operator))
         (preconditions (operator-preconditions operator))
         (b (extend-bindings-from-state preconditions bindings state))
         (subs (precondition-subgoals operator b state)))
    (trace-record :selected-operator
                  :operator name
                  :goal goal
                  :bindings (%operator-bindings operator b)
                  :depth depth)
    (dolist (sg subs)
      (trace-record :subgoal :goal sg :for-operator name))
    (multiple-value-bind (state2 plan2 ok)
        (achieve-all subs state operators plan (1+ depth)
                     (cons goal goal-stack))
      (if (not ok)
          (values nil nil nil)
          (let* ((b2 (extend-bindings-from-state preconditions b state2))
                 (still-missing (precondition-subgoals operator b2 state2))
                 (ungrounded (ungrounded-adds operator b2)))
            (dolist (pre preconditions)
              (let ((g (substitute-bindings pre b2)))
                (unless (fail-p g)
                  (trace-record :precondition
                                :goal g
                                :status (if (goal-holds-p g state2)
                                            :satisfied
                                            :missing)
                                :operator name))))
            (cond
              (still-missing
               (trace-record :operator-failed
                             :operator name
                             :reason :preconditions-unmet
                             :missing still-missing)
               (values nil nil nil))
              (ungrounded
               (trace-record :operator-failed
                             :operator name
                             :reason :ungrounded-effect
                             :patterns ungrounded)
               (values nil nil nil))
              (t
               (let* ((step (make-plan-step operator b2 goal subs))
                      (state3 (apply-operator state2 operator b2)))
                 (trace-record :action
                               :operator name
                               :bindings (getf step :bindings)
                               :goal goal)
                 (cond
                   ((goal-holds-p goal state3)
                    (trace-record :result :status :success
                                  :operator name
                                  :goal goal)
                    (values state3 (append plan2 (list step)) t))
                   (t
                    (trace-record :result :status :goal-not-achieved
                                  :operator name
                                  :goal goal)
                    (values nil nil nil)))))))))))

(defun achieve-all (goals state operators plan depth &optional goal-stack)
  "Achieve every goal in GOALS, one difference at a time.
Differences are recomputed after each success, so a goal undone while a
later one was achieved is achieved again. When that brings back a set of
facts already seen for these GOALS, the goals keep undoing one another:
the search records :GOAL-CLOBBERED and fails instead of going round forever.
GOAL-STACK is passed on to ACHIEVE.
Returns (VALUES NEW-STATE NEW-PLAN T), or (VALUES NIL NIL NIL) on failure.
NEW-STATE can be the empty list, so test the third value."
  (let ((seen nil))
    (loop
      (let ((pending (differences state goals)))
        (when (and pending (zerop depth))
          (trace-record :differences :goals pending))
        (cond
          ((null pending)
           (return (values state plan t)))
          ((member state seen :test #'%same-facts-p)
           (trace-record :result :status :goal-clobbered :goals pending)
           (return (values nil nil nil)))
          (t
           (push state seen)
           (multiple-value-bind (new-state new-plan ok)
               (achieve (first pending) state operators plan depth goal-stack)
             (unless ok
               (return (values nil nil nil)))
             (setf state new-state
                   plan new-plan))))))))

(defun means-ends-analyze (state goals operators)
  "Run MEA: return (VALUES SUCCESS FINAL-STATE PLAN DIFFERENCES-REMAINING).
On success FINAL-STATE satisfies every goal and nothing remains. On failure
FINAL-STATE is STATE, PLAN is NIL, and the goals that do not hold in STATE
remain."
  (trace-record :goals :goals goals)
  (trace-record :state :facts (copy-list state))
  (multiple-value-bind (final plan ok)
      (achieve-all goals state operators nil 0)
    (let ((left (if ok nil (differences state goals))))
      (trace-record :plan-complete
                    :success ok
                    :steps (length plan)
                    :remaining left)
      (values ok (if ok final state) plan left))))
