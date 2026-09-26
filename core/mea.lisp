;;;; core/mea.lisp — Means-Ends Analysis (Phase 3)
;;;;
;;;; GPS-style / Norvig: differences → operator → preconditions as subgoals
;;;; → recursive achievement. Symbolic state only; no external execution.

(in-package #:automa-gp)

(defparameter *plan-depth-limit* 32
  "Maximum MEA recursion depth (goal stack).")

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

(defun retract-slot-conflicts (facts add)
  "If ADD is a 3-element fact (PRED OBJ VAL), drop other (PRED OBJ *) facts.
Helps GPS-style state changes such as power-state on/off."
  (if (and (consp add) (null (cdddr add)) (car add) (cadr add))
      (remove-if (lambda (f)
                   (and (consp f)
                        (null (cdddr f))
                        (equal (first f) (first add))
                        (equal (second f) (second add))))
                 facts)
      facts))

(defun ground-pattern (pattern bindings)
  "Substitute BINDINGS into PATTERN; *FAIL* if substitution fails."
  (substitute-bindings pattern bindings))

(defun apply-operator (facts operator bindings &key (conflict-retract t))
  "Symbolically apply OPERATOR to FACTS under BINDINGS.
Returns a new fact list. Does not touch the live context or adapters."
  (let ((state (copy-list facts)))
    (dolist (del (operator-delete-list operator))
      (let ((g (ground-pattern del bindings)))
        (unless (fail-p g)
          (setf state (remove-fact! state g)))))
    (dolist (add (operator-add-list operator))
      (let ((g (ground-pattern add bindings)))
        (unless (fail-p g)
          (when conflict-retract
            (setf state (retract-slot-conflicts state g)))
          (setf state (add-fact! state g)))))
    state))

(defun extend-bindings-from-state (patterns bindings facts)
  "Extend BINDINGS by matching still-open variables in PATTERNS against FACTS.
Uses the first successful match per pattern (Phase-3 simplicity)."
  (let ((b bindings))
    (dolist (pat patterns b)
      (let ((partial (substitute-bindings pat b)))
        (when (and (not (fail-p partial)) (variables-in partial))
          (let ((sols (match-all (list partial) facts b)))
            (when sols
              (setf b (first sols)))))))))

(defun precondition-subgoals (operator bindings facts)
  "Preconditions of OPERATOR (grounded by BINDINGS) not yet holding in FACTS."
  (loop for pre in (operator-preconditions operator)
        for g = (ground-pattern pre bindings)
        unless (or (fail-p g) (goal-holds-p g facts))
          collect g))

(defun make-plan-step (operator bindings goal subgoals)
  "A single planned step (plist)."
  (list :operator (operator-name operator)
        :bindings (instantiate-bindings
                   (cons goal (append (operator-preconditions operator)
                                      (operator-add-list operator)))
                   bindings)
        :goal goal
        :subgoals subgoals
        :action (operator-action operator)
        :cost (operator-cost operator)))

;;; Core MEA

(defun achieve (goal state operators plan depth)
  "Achieve GOAL from STATE using OPERATORS.
Returns (VALUES NEW-STATE NEW-PLAN) or (VALUES NIL NIL) on failure.
PLAN is a list of plan-steps in application order."
  (cond
    ((goal-holds-p goal state)
     (values state plan))
    ((>= depth *plan-depth-limit*)
     (values nil nil))
    (t
     (dolist (pair (operators-for-goal goal operators) (values nil nil))
       (let* ((op (car pair))
              (b0 (cdr pair)))
         (multiple-value-bind (new-state new-plan)
             (try-operator op goal b0 state operators plan depth)
           (when new-state
             (return (values new-state new-plan)))))))))

(defun try-operator (operator goal bindings state operators plan depth)
  "Try OPERATOR to achieve GOAL: satisfy precondition subgoals, then apply."
  (let* ((b (extend-bindings-from-state
             (operator-preconditions operator) bindings state))
         (subs (precondition-subgoals operator b state)))
    (multiple-value-bind (state2 plan2)
        (achieve-all subs state operators plan (1+ depth))
      (when state2
        (let* ((b2 (extend-bindings-from-state
                    (operator-preconditions operator) b state2))
               (still-missing (precondition-subgoals operator b2 state2)))
          (if still-missing
              (values nil nil)
              (let* ((step (make-plan-step operator b2 goal subs))
                     (state3 (apply-operator state2 operator b2)))
                (if (goal-holds-p goal state3)
                    (values state3 (append plan2 (list step)))
                    (values nil nil)))))))))

(defun achieve-all (goals state operators plan depth)
  "Achieve every goal in GOALS. Recomputes differences after each success."
  (let ((pending (differences state goals)))
    (if (null pending)
        (values state plan)
        (multiple-value-bind (s2 p2)
            (achieve (first pending) state operators plan depth)
          (if s2
              (achieve-all goals s2 operators p2 depth)
              (values nil nil))))))

(defun means-ends-analyze (state goals operators)
  "Run MEA: return (VALUES SUCCESS FINAL-STATE PLAN DIFFERENCES-REMAINING)."
  (let ((initial-diffs (differences state goals)))
    (multiple-value-bind (final plan)
        (achieve-all goals state operators nil 0)
      (if final
          (let ((left (differences final goals)))
            (values (null left) final plan left))
          (values nil state nil initial-diffs)))))
