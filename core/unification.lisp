;;;; core/unification.lisp — first-order unification (Phase 2)
;;;;
;;;; Classic Lisp unification with occur-check. Uses *FAIL* / *NO-BINDINGS*
;;;; from the matcher.

(in-package #:automa-gp)

(defun occurs-check-p (var x bindings)
  "True if VAR occurs in X under BINDINGS (prevents infinite structures)."
  (cond
    ((eq var x) t)
    ((and (variable-symbol-p x) (lookup-binding x bindings))
     (occurs-check-p var (cdr (lookup-binding x bindings)) bindings))
    ((consp x)
     (or (occurs-check-p var (car x) bindings)
         (occurs-check-p var (cdr x) bindings)))
    (t nil)))

(defun unify-variable (var x bindings)
  "Unify VAR with X under BINDINGS (with occur-check)."
  (cond
    ((lookup-binding var bindings)
     (unify (cdr (lookup-binding var bindings)) x bindings))
    ((and (variable-symbol-p x) (lookup-binding x bindings))
     (unify var (cdr (lookup-binding x bindings)) bindings))
    ((and (not (anonymous-variable-p var))
          (occurs-check-p var x bindings))
     *fail*)
    (t (extend-bindings var x bindings))))

(defun unify (x y &optional (bindings *no-bindings*))
  "Unify X and Y. Returns bindings alist, *NO-BINDINGS*, or *FAIL*.
Both sides may contain variables."
  (cond
    ((eq bindings *fail*) *fail*)
    ((eql x y) bindings)
    ((anonymous-variable-p x) bindings)
    ((anonymous-variable-p y) bindings)
    ((variable-symbol-p x) (unify-variable x y bindings))
    ((variable-symbol-p y) (unify-variable y x bindings))
    ((and (consp x) (consp y))
     (unify (cdr x) (cdr y)
            (unify (car x) (car y) bindings)))
    ((equal x y) bindings)
    (t *fail*)))

(defun unify-p (x y &optional (bindings *no-bindings*))
  "Boolean wrapper: (VALUES T BINDINGS) or (VALUES NIL NIL)."
  (let ((b (unify x y bindings)))
    (if (eq b *fail*)
        (values nil nil)
        (values t (if (eq b *no-bindings*) nil b)))))
