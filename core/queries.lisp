;;;; core/queries.lisp — symbolic queries (Phase 2)
;;;;
;;;; Query a context's facts, and optionally its rules by backward chaining.
;;;; Not a full Prolog engine: no cuts, no negation, no tabling.
;;;;
;;;; Each rule application renames the rule's variables, so a rule may call
;;;; itself and may share variable names with the query. The search is
;;;; depth-first and bounded twice: by the length of a chain of rule
;;;; applications and by the number of goals resolved. A search cut by a
;;;; bound returns the answers it found and says that others may be missing.
;;;; A goal that comes back as its own subgoal is not proved again: that
;;;; proof would only repeat an answer the outer goal has without it.
;;;; Without tabling, a left-recursive rule always reaches the depth bound,
;;;; and a rule with two recursive antecedents can use up the steps before
;;;; it has every answer. FORWARD-CHAIN closes such rule sets.

(in-package #:automa-gp)

(defparameter *query-depth-limit* 32
  "Longest chain of rule applications QUERY / PROVE follow below one goal.
A proof that needs a longer chain is not found.")

(defparameter *query-step-limit* 100000
  "Most goals one QUERY / PROVE call resolves before it stops searching.
The depth limit bounds one chain, not the search: a rule with two recursive
antecedents grows it exponentially in the depth.")

(define-condition query-incomplete (warning)
  ((goal :initarg :goal :reader query-incomplete-goal)
   (limit :initarg :limit :reader query-incomplete-limit))
  (:report (lambda (c stream)
             (format stream "The search for ~S reached ~A; answers may be ~
                             missing."
                     (query-incomplete-goal c)
                     (ecase (query-incomplete-limit c)
                       (:depth '*query-depth-limit*)
                       (:steps '*query-step-limit*)))))
  (:documentation "A backward-chaining search was cut short. LIMIT is :DEPTH
or :STEPS. The answers returned are sound; more may exist."))

;;; Bindings

(defun binding-alist (bindings)
  "BINDINGS as a plain alist: the *NO-BINDINGS* sentinel becomes NIL.
BINDINGS is the value of a successful match, never *FAIL*."
  (if (eq bindings *no-bindings*) nil bindings))

(defun resolve-term (term bindings)
  "TERM with each bound variable replaced by its value, in depth.
A variable reached again while its own value is being resolved stays as it
is, so this returns even for the circular bindings MATCH can produce
against data that holds variables. SUBSTITUTE-BINDINGS does not."
  (labels ((resolve (term resolving)
             (cond
               ((variable-symbol-p term)
                (let ((pair (lookup-binding term bindings)))
                  (if (or (null pair) (member term resolving :test #'eq))
                      term
                      (resolve (cdr pair) (cons term resolving)))))
               ((consp term)
                (cons (resolve (car term) resolving)
                      (resolve (cdr term) resolving)))
               (t term))))
    (resolve term nil)))

(defun instantiate-bindings (pattern bindings)
  "Alist from each named variable of PATTERN to its value under BINDINGS.
Values are resolved in depth; an unbound variable maps to itself.
BINDINGS is the value of a successful match, never *FAIL*."
  (mapcar (lambda (variable)
            (cons variable (resolve-term variable bindings)))
          (remove-duplicates (variables-in pattern) :test #'eq)))

(defun query-facts (pattern facts)
  "Match PATTERN against FACTS only (no rules).
Each hit is a plist (:FACT f :BINDINGS alist)."
  (loop for fact in facts
        for b = (match pattern fact *no-bindings*)
        unless (eq b *fail*)
          collect (list :fact fact :bindings (binding-alist b))))

;;; Backward chaining

(defvar *proof-steps-left* 0
  "Goals the proof search in progress may still resolve.")

(defvar *proof-cut* nil
  "The limit that cut the proof search in progress: NIL, :DEPTH or :STEPS.")

(defun %cut-proof (limit)
  "Record that LIMIT stopped part of the search. The first limit is kept."
  (unless *proof-cut*
    (setf *proof-cut* limit)))

(defun rename-variables (tree)
  "A copy of TREE whose named variables are fresh uninterned symbols.
The same variable gets the same replacement throughout TREE. Renaming a
rule before each use keeps its variables apart from those of the goal
and of every other use of the same rule."
  (sublis (mapcar (lambda (variable)
                    (cons variable (gensym (symbol-name variable))))
                  (remove-duplicates (variables-in tree) :test #'eq))
          tree))

(defun %goal-on-path-p (goal bindings path)
  "True when GOAL is, under BINDINGS, one of the goals in PATH.
PATH holds the goals GOAL is a subgoal of. Proving such a goal again can
only repeat an answer the outer goal reaches without the detour."
  (let ((instance (substitute-bindings goal bindings)))
    (some (lambda (outer)
            (equal instance (substitute-bindings outer bindings)))
          path)))

(defun %prove (goal facts rules bindings depth path)
  "PROVE inside a running search; PATH holds the goals above GOAL."
  (cond
    ((%goal-on-path-p goal bindings path)
     nil)
    ((not (plusp *proof-steps-left*))
     (%cut-proof :steps)
     nil)
    (t
     (decf *proof-steps-left*)
     (let ((results nil))
       (dolist (fact facts)
         (let ((b (unify goal fact bindings)))
           (unless (fail-p b)
             (push b results))))
       (dolist (rule rules)
         (destructuring-bind (consequents . antecedents)
             (rename-variables (cons (rule-then rule) (rule-if rule)))
           (dolist (consequent consequents)
             (let ((b (unify goal consequent bindings)))
               (cond
                 ((fail-p b))
                 ((>= depth *query-depth-limit*)
                  (%cut-proof :depth))
                 (t
                  (dolist (solution (%prove-all antecedents facts rules b
                                                (1+ depth) (cons goal path)))
                    (push solution results))))))))
       (nreverse results)))))

(defun %prove-all (goals facts rules bindings depth path)
  "PROVE-ALL inside a running search; PATH holds the goals above GOALS."
  (if (null goals)
      (list bindings)
      (loop for b in (%prove (first goals) facts rules bindings depth path)
            nconc (%prove-all (rest goals) facts rules b depth path))))

(defun call-with-proof-limits (goal bindings search)
  "Call SEARCH, which proves GOAL from BINDINGS, under fresh search limits.
Returns (VALUES SOLUTIONS COMPLETE-P). When a limit cut the search and
solutions may be missing, COMPLETE-P is NIL and QUERY-INCOMPLETE is
signalled."
  (let* ((*proof-steps-left* *query-step-limit*)
         (*proof-cut* nil)
         (solutions (funcall search))
         (complete-p
           (or (null *proof-cut*)
               ;; With no variable left to bind, one proof is the whole answer.
               (and solutions
                    (null (variables-in (substitute-bindings goal bindings)))))))
    (unless complete-p
      (warn 'query-incomplete :goal goal :limit *proof-cut*))
    (values solutions complete-p)))

(defun prove (goal facts rules &optional (bindings *no-bindings*) (depth 0))
  "Backward-chain: every proof of GOAL from FACTS and RULES.
Returns (VALUES SOLUTIONS COMPLETE-P). Each solution is a binding set that
extends BINDINGS; read one with INSTANTIATE-BINDINGS or SUBSTITUTE-BINDINGS.
Facts are tried first, then every rule with a consequent that unifies with
GOAL, its variables renamed for this use. DEPTH counts the rule
applications already above GOAL; no rule is applied at *QUERY-DEPTH-LIMIT*.
The search also stops after *QUERY-STEP-LIMIT* goals. When either limit may
have hidden a solution, COMPLETE-P is NIL and the warning QUERY-INCOMPLETE
is signalled; the solutions returned are still sound."
  (call-with-proof-limits
   goal bindings
   (lambda () (%prove goal facts rules bindings depth nil))))

(defun prove-all (goals facts rules bindings depth)
  "Prove the conjunction GOALS; see PROVE for the arguments and the values."
  (call-with-proof-limits
   goals bindings
   (lambda () (%prove-all goals facts rules bindings depth nil))))

(defun %name-anonymous-variables (tree)
  "A copy of TREE in which each anonymous ? is a fresh variable of its own.
An anonymous variable takes no binding, so a proof leaves it in the goal;
a named one comes back as the term it stood for."
  (cond
    ((anonymous-variable-p tree) (gensym "?ANY"))
    ((consp tree)
     (cons (%name-anonymous-variables (car tree))
           (%name-anonymous-variables (cdr tree))))
    (t tree)))

(defun query (pattern context &key (infer t))
  "Query PATTERN in CONTEXT.
If INFER is true (default), use backward chaining over visible rules.
If INFER is NIL, match facts only (like FIND-FACTS / CONTEXT-QUERY).

Returns (VALUES HITS COMPLETE-P). HITS is a list of distinct plists
  (:BINDINGS alist :FACT instantiated-pattern :SOURCE :FACT|:RULE)
where :BINDINGS covers the named variables of PATTERN, :FACT also fills
in what each anonymous ? stood for, and :SOURCE is :FACT when that fact
is a visible fact. COMPLETE-P is NIL when the search limits of PROVE may
have hidden a hit; PROVE then also signals the warning QUERY-INCOMPLETE."
  (let ((facts (context-all-facts context)))
    (if infer
        (let ((goal (%name-anonymous-variables pattern)))
          (multiple-value-bind (solutions complete-p)
              (prove goal facts (context-all-rules context))
            (values (remove-duplicates
                     (loop for b in solutions
                           for fact = (substitute-bindings goal b)
                           collect (list :bindings (instantiate-bindings
                                                    pattern b)
                                         :fact fact
                                         :source (if (fact-p fact facts)
                                                     :fact
                                                     :rule)))
                     :test #'equal :from-end t)
                    complete-p)))
        (values (loop for hit in (query-facts pattern facts)
                      collect (list :bindings (instantiate-bindings
                                               pattern (getf hit :bindings))
                                    :fact (getf hit :fact)
                                    :source :fact))
                t))))

(defun query-bindings (pattern context &key (infer t))
  "Convenience: the binding alists of QUERY, and its COMPLETE-P."
  (multiple-value-bind (hits complete-p) (query pattern context :infer infer)
    (values (mapcar (lambda (hit) (getf hit :bindings)) hits)
            complete-p)))
