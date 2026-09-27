;;;; core/facts.lisp — symbolic facts
;;;;
;;;; Facts are ordinary Lisp lists, e.g. (POWER-STATE INTERFACE-01 OFF).
;;;; Pattern matching is provided by MATCHER (Phase 2); this file keeps
;;;; the fact-store helpers used since Phase 1.

(in-package #:automa-gp)

(defun fact-equal (a b)
  "Structural equality for facts (lists compared with EQUAL)."
  (equal a b))

(defun fact-matches-p (pattern fact &optional bindings)
  "Match PATTERN against FACT. Phase-2 engine (MATCH); same values protocol
as Phase 1: (VALUES T BINDINGS) or (VALUES NIL NIL)."
  (match-p pattern fact (or bindings *no-bindings*)))

(defun fact-p (fact facts)
  "True if FACT occurs in FACTS (exact EQUAL)."
  (find fact facts :test #'fact-equal))

(defun fact-same-names-p (a b)
  "True when two facts use the same names, whatever their packages."
  (and (consp a) (consp b)
       (= (length a) (length b))
       (every (lambda (x y)
                (cond
                  ((and (symbolp x) (symbolp y))
                   (string= (symbol-name x) (symbol-name y)))
                  (t (equal x y))))
              a b)))

(defun find-fact-by-names (fact facts)
  "The stored fact whose names match FACT, or NIL."
  (find-if (lambda (live) (fact-same-names-p live fact)) facts))

(defun find-facts (pattern facts)
  "Return all facts in FACTS that match PATTERN.
Each result is (FACT . BINDINGS) where BINDINGS is an alist (possibly NIL)."
  (loop for fact in facts
        for (ok binds) = (multiple-value-list (fact-matches-p pattern fact))
        when ok
          collect (cons fact binds)))

(defun add-fact! (facts fact)
  "Return a new fact list with FACT asserted (idempotent)."
  (if (fact-p fact facts)
      facts
      (append facts (list fact))))

(defun remove-fact! (facts fact)
  "Return a new fact list with FACT retracted."
  (remove fact facts :test #'fact-equal))
