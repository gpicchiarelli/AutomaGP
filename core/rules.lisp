;;;; core/rules.lisp — symbolic Horn-style rules (Phase 2)
;;;;
;;;; A rule is: IF conjunction of patterns THEN consequent fact pattern(s).
;;;; Supports forward chaining over a fact base. No negation-as-failure,
;;;; no certainty factors, no truth-maintenance (Phase 2 limits).
;;;;
;;;; Rules are safe (range-restricted): every variable of a consequent occurs
;;;; in an antecedent, so a conclusion is always a ground fact.
;;;; Forward chaining is naive: every round matches every rule against every
;;;; fact. It stops at a fixpoint or after a bounded number of rounds, and
;;;; says which.

(in-package #:automa-gp)

(defparameter *forward-chain-limit* 64
  "Most rounds FORWARD-CHAIN runs before it gives up on reaching a fixpoint.")

(define-condition unsafe-rule (error)
  ((name :initarg :name :reader unsafe-rule-name :initform nil)
   (variables :initarg :variables :reader unsafe-rule-variables))
  (:report (lambda (c stream)
             (format stream "Rule ~:[without a name~;~:*~S~] is unsafe: no ~
                             antecedent binds ~{~S~^, ~} in its consequent."
                     (unsafe-rule-name c) (unsafe-rule-variables c))))
  (:documentation "MAKE-RULE was given a consequent variable that the
antecedents cannot bind, so the rule would conclude a non-ground fact."))

(define-condition forward-chain-incomplete (warning)
  ((limit :initarg :limit :reader forward-chain-incomplete-limit))
  (:report (lambda (c stream)
             (format stream "Forward chaining stopped after ~D round~:P ~
                             without reaching a fixpoint; derived facts may ~
                             be missing."
                     (forward-chain-incomplete-limit c))))
  (:documentation "FORWARD-CHAIN used up its rounds while rules could still
derive new facts. The facts it returns are sound but not the whole closure."))

(defclass rule ()
  ((name
    :initarg :name
    :accessor rule-name
    :initform nil
    :documentation "Optional symbolic rule name.")
   (if
    :initarg :if
    :accessor rule-if
    :initform nil
    :documentation "List of antecedent patterns (conjunction).")
   (then
    :initarg :then
    :accessor rule-then
    :initform nil
    :documentation "List of consequent fact patterns.")
   (meta
    :initarg :meta
    :accessor rule-meta
    :initform nil
    :documentation "Optional metadata."))
  (:documentation "Horn-style symbolic rule."))

(defun rule-p (object)
  "True if OBJECT is a RULE."
  (typep object 'rule))

(defun normalize-pattern-list (x)
  "Normalize X to a list of patterns.
A single pattern like (POWERED ?D) becomes ((POWERED ?D)).
A list of patterns ((A) (B)) is returned as-is."
  (cond
    ((null x) nil)
    ((and (consp x) (consp (car x))) x)
    (t (list x))))

(defun variables-in (tree)
  "The named pattern variables in TREE, in order, with repeats.
The anonymous ? is not one of them."
  (cond
    ((anonymous-variable-p tree) nil)
    ((variable-symbol-p tree) (list tree))
    ((consp tree)
     (append (variables-in (car tree)) (variables-in (cdr tree))))
    (t nil)))

(defun %unbound-consequent-variables (antecedents consequents)
  "Variables of CONSEQUENTS that matching ANTECEDENTS leaves unbound.
The anonymous ? never binds, so it counts wherever CONSEQUENTS use it."
  (let ((bound (variables-in antecedents))
        (unbound nil))
    (labels ((walk (tree)
               (cond
                 ((consp tree)
                  (walk (car tree))
                  (walk (cdr tree)))
                 ((and (variable-symbol-p tree) (not (member tree bound)))
                  (pushnew tree unbound)))))
      (walk consequents))
    (nreverse unbound)))

(defun make-rule (&key name if then meta)
  "Construct a RULE. :IF and :THEN accept a pattern or list of patterns.
Every variable of :THEN must occur in :IF, and :THEN may not use the
anonymous ?: a conclusion has to be a ground fact. Otherwise UNSAFE-RULE
is signalled. Its CONTINUE restart builds the rule anyway; forward
chaining then leaves out the conclusions that stay non-ground."
  (let* ((antecedents (normalize-pattern-list if))
         (consequents (normalize-pattern-list then))
         (unbound (%unbound-consequent-variables antecedents consequents)))
    (when unbound
      (cerror "Build the rule anyway."
              'unsafe-rule :name name :variables unbound))
    (make-instance 'rule
                   :name name
                   :if antecedents
                   :then consequents
                   :meta meta)))

(defun register-rule! (context rule)
  "Register RULE on CONTEXT, newest first.
A rule with a name replaces the local rule of that name."
  (let ((name (rule-name rule))
        (rules (context-rules context)))
    (setf (context-rules context)
          (cons rule
                (if name
                    (remove name rules :key #'rule-name :test #'equal)
                    rules)))
    rule))

(defun remove-rule! (context name)
  "Remove rule named NAME from CONTEXT."
  (setf (context-rules context)
        (remove name (context-rules context) :key #'rule-name :test #'equal))
  (context-rules context))

(defun rules-of (context)
  "Local rules on CONTEXT."
  (context-rules context))

(defun visible-by-name (context local name)
  "The objects (LOCAL c) of CONTEXT and of each ancestor, nearest first.
An object whose NAME a nearer context already used is shadowed and left
out. An object without a name is never shadowed."
  (let ((seen nil))
    (loop for c = context then (context-parent c)
          while c
          nconc (loop for object in (funcall local c)
                      for n = (funcall name object)
                      unless (and n (member n seen :test #'equal))
                        collect object
                        and do (when n (push n seen))))))

(defun context-all-rules (context)
  "Rules visible along the parent chain (local first, then ancestors).
Same-name local rules replace ancestor rules."
  (visible-by-name context #'context-rules #'rule-name))

(defun rule-conclusions (rule facts)
  "The facts one application of RULE adds to FACTS.
Each way of matching the antecedents against FACTS instantiates every
consequent; facts already in FACTS are left out. A conclusion that still
holds a variable is not a fact and is left out too: only a rule built
past UNSAFE-RULE, or a non-ground entry in FACTS, can produce one.
Does not recurse into other rules."
  (let ((out nil))
    (dolist (bindings (match-all (rule-if rule) facts))
      (dolist (pattern (rule-then rule))
        (let ((fact (substitute-bindings pattern bindings)))
          (unless (or (pattern-has-variable-p fact)
                      (fact-p fact out)
                      (fact-p fact facts))
            (push fact out)))))
    (nreverse out)))

(defun forward-chain (facts rules &key (limit *forward-chain-limit*))
  "Forward-chain RULES over FACTS to a fixpoint, in at most LIMIT rounds.
Returns (VALUES ALL-FACTS NEW-FACTS COMPLETE-P). ALL-FACTS starts with
FACTS; NEW-FACTS are the derived ones. COMPLETE-P is true when no rule
can derive anything more. When LIMIT rounds were not enough, COMPLETE-P
is NIL, the facts derived so far are returned, and the warning
FORWARD-CHAIN-INCOMPLETE is signalled."
  (let ((all (copy-list facts))
        (new nil))
    (flet ((next-batch ()
             (let ((batch nil))
               (dolist (rule rules (nreverse batch))
                 (dolist (fact (rule-conclusions rule all))
                   (unless (fact-p fact batch)
                     (push fact batch)))))))
      (loop for round from 0
            for batch = (next-batch)
            do (cond
                 ((null batch)
                  (return (values all new t)))
                 ((>= round limit)
                  (warn 'forward-chain-incomplete :limit limit)
                  (return (values all new nil)))
                 (t
                  (setf all (append all batch)
                        new (append new batch))))))))
