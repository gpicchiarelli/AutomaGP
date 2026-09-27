;;;; core/rules.lisp — symbolic Horn-style rules (Phase 2)
;;;;
;;;; A rule is: IF conjunction of patterns THEN consequent fact pattern(s).
;;;; Supports forward chaining over a fact base. No negation-as-failure,
;;;; no certainty factors, no truth-maintenance (Phase 2 limits).

(in-package #:automa-gp)

(defparameter *forward-chain-limit* 64
  "Max forward-chaining iterations (fixpoint safety).")

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
  (typep object 'rule))

(defun normalize-pattern-list (x)
  "Normalize X to a list of patterns.
A single pattern like (POWERED ?D) becomes ((POWERED ?D)).
A list of patterns ((A) (B)) is returned as-is."
  (cond
    ((null x) nil)
    ((and (consp x) (consp (car x))) x)
    (t (list x))))

(defun make-rule (&key name if then meta)
  "Construct a RULE. :IF and :THEN accept a pattern or list of patterns."
  (make-instance 'rule
                 :name name
                 :if (normalize-pattern-list if)
                 :then (normalize-pattern-list then)
                 :meta meta))

(defun register-rule! (context rule)
  "Register RULE on CONTEXT (by name if present, else push)."
  (let* ((name (rule-name rule))
         (rules (context-rules context)))
    (setf (context-rules context)
          (if name
              (cons rule (remove name rules :key #'rule-name :test #'equal))
              (append rules (list rule))))
    rule))

(defun remove-rule! (context name)
  "Remove rule named NAME from CONTEXT."
  (setf (context-rules context)
        (remove name (context-rules context) :key #'rule-name :test #'equal))
  (context-rules context))

(defun rules-of (context)
  "Local rules on CONTEXT."
  (context-rules context))

(defun context-all-rules (context)
  "Rules visible along the parent chain (local first, then ancestors).
Same-name local rules replace ancestor rules."
  (let ((chain nil)
        (result nil)
        (seen-names nil))
    (loop for c = context then (context-parent c)
          while c
          do (push c chain))
    ;; chain is root→leaf; walk leaf→root so local names win
    (dolist (c (reverse chain))
      (dolist (r (context-rules c))
        (let ((n (rule-name r)))
          (cond
            ((and n (member n seen-names :test #'equal))
             nil)
            (t
             (when n (push n seen-names))
             (push r result))))))
    (nreverse result)))

(defun rule-conclusions (rule facts)
  "Ground consequent facts obtained by matching RULE antecedents against FACTS.
Does not recurse into other rules (one-shot application)."
  (let ((solutions (match-all (rule-if rule) facts *no-bindings*))
        (out nil))
    (dolist (binds solutions)
      (dolist (pat (rule-then rule))
        (let ((fact (substitute-bindings pat binds)))
          (unless (or (fail-p fact)
                      (fact-p fact out)
                      (fact-p fact facts))
            (push fact out)))))
    (nreverse out)))

(defun forward-chain (facts rules &key (limit *forward-chain-limit*))
  "Forward-chain RULES over FACTS until fixpoint or LIMIT iterations.
Returns (VALUES ALL-FACTS NEW-FACTS) where ALL-FACTS includes originals."
  (let ((all (copy-list facts))
        (new nil))
    (loop repeat limit
          for batch = (let ((out nil))
                        (dolist (rule rules)
                          (dolist (f (rule-conclusions rule all))
                            (unless (or (fact-p f all) (fact-p f out))
                              (push f out))))
                        (nreverse out))
          do (if (null batch)
                 (return (values all new))
                 (setf all (append all batch)
                       new (append new batch)))
          finally (return (values all new)))))
