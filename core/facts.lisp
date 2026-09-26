;;;; core/facts.lisp — symbolic facts (Phase 1)
;;;;
;;;; Facts are ordinary Lisp lists, e.g. (POWER-STATE INTERFACE-01 OFF).
;;;; Pattern variables are symbols whose names begin with #\? (e.g. ?X).
;;;; Full pattern matching / unification / rules arrive in Phase 2.

(in-package #:automa-gp)

(defun variable-symbol-p (x)
  "True if X is a symbol whose name starts with '?'."
  (and (symbolp x)
       (let ((name (symbol-name x)))
         (and (plusp (length name))
              (char= (char name 0) #\?)))))

(defun fact-equal (a b)
  "Structural equality for facts (lists compared with EQUAL)."
  (equal a b))

(defun fact-matches-p (pattern fact &optional bindings)
  "Shallow match of PATTERN against FACT.
Returns (VALUES T BINDINGS) on success, (VALUES NIL NIL) on failure.
Variables (symbols named ?…) bind consistently within one match.
This is intentionally minimal — not Phase-2 unification."
  (labels ((match (p f binds)
             (cond
               ((variable-symbol-p p)
                (let ((existing (assoc p binds :test #'eq)))
                  (if existing
                      (if (equal (cdr existing) f)
                          (values t binds)
                          (values nil nil))
                      (values t (acons p f binds)))))
               ((and (null p) (null f))
                (values t binds))
               ((and (consp p) (consp f))
                (multiple-value-bind (ok binds2) (match (car p) (car f) binds)
                  (if ok
                      (match (cdr p) (cdr f) binds2)
                      (values nil nil))))
               ((equal p f)
                (values t binds))
               (t
                (values nil nil)))))
    (match pattern fact (or bindings nil))))

(defun fact-p (fact facts)
  "True if FACT occurs in FACTS (exact EQUAL)."
  (find fact facts :test #'fact-equal))

(defun find-facts (pattern facts)
  "Return all facts in FACTS that match PATTERN (see FACT-MATCHES-P).
Each result is (FACT . BINDINGS) where BINDINGS is an alist."
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
