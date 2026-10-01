;;;; core/matcher.lisp — pattern matching & substitution (Phase 2)
;;;;
;;;; Variables: symbols whose names begin with #\? (e.g. ?X).
;;;; Anonymous variable: the symbol named "?" (matches anything, does not bind).
;;;; Segment/sequence variables (e.g. ?*X) are NOT supported in Phase 2.
;;;;
;;;; Bindings are an alist of (VARIABLE . VALUE), shared with UNIFY. A value
;;;; may itself hold variables that are bound further down the alist. MATCH
;;;; and UNIFY never return bindings in which a variable contains itself.

(in-package #:automa-gp)

;;; Binding sentinels shared with UNIFY

(defvar *fail* (list 'fail)
  "Unique failure sentinel for MATCH / UNIFY.")

(defvar *no-bindings* (list (cons t t))
  "Sentinel meaning success with an empty binding set.")

(defun fail-p (x)
  "True if X is the failure sentinel *FAIL*."
  (eq x *fail*))

(defun variable-symbol-p (x)
  "True if X is a symbol whose name starts with '?' (including anonymous ?)."
  (and (symbolp x)
       (let ((name (symbol-name x)))
         (and (plusp (length name))
              (char= (char name 0) #\?)))))

(defun anonymous-variable-p (x)
  "True if X is the anonymous pattern variable (symbol named \"?\")."
  (and (symbolp x)
       (string= (symbol-name x) "?")))

(defun pattern-has-variable-p (pattern)
  "True if a variable symbol, named or anonymous, occurs anywhere in PATTERN."
  (cond
    ((variable-symbol-p pattern) t)
    ((consp pattern)
     (or (pattern-has-variable-p (car pattern))
         (pattern-has-variable-p (cdr pattern))))
    (t nil)))

;;; Bindings

(defun lookup-binding (var bindings)
  "Return the binding pair (VAR . VALUE) for VAR in BINDINGS, or NIL."
  (when (and bindings (not (eq bindings *no-bindings*)))
    (assoc var bindings :test #'eq)))

(defun extend-bindings (var value bindings)
  "Return BINDINGS extended with VAR → VALUE."
  (cons (cons var value)
        (if (eq bindings *no-bindings*) nil bindings)))

(defun dereference (term bindings)
  "Follow TERM through BINDINGS for as long as it is a bound variable.
Returns the first term that is not one: a value, or a variable that is still
open. A variable bound to itself, or a ring of variables bound to one
another, stands for nothing and counts as open, so the walk always ends.
INSTANTIATE-BINDINGS writes (?V . ?V) for a variable it could not resolve,
and such an alist comes back as the bindings of a plan step."
  (loop with seen = nil
        for pair = (and (variable-symbol-p term)
                        (not (member term seen :test #'eq))
                        (lookup-binding term bindings))
        while pair
        do (push term seen)
           (setf term (cdr pair))
        finally (return term)))

(defun occurs-check-p (var x bindings)
  "True if VAR occurs in X under BINDINGS (prevents infinite structures).
Each bound variable is expanded once, so the check ends even when BINDINGS
is itself circular."
  (let ((expanded nil))
    (labels ((occurs-p (x)
               (cond
                 ((eq var x) t)
                 ((variable-symbol-p x)
                  (let ((pair (lookup-binding x bindings)))
                    (when (and pair (not (member x expanded :test #'eq)))
                      (push x expanded)
                      (occurs-p (cdr pair)))))
                 ((consp x)
                  (or (occurs-p (car x))
                      (occurs-p (cdr x))))
                 (t nil))))
      (occurs-p x))))

(defun substitute-bindings (tree bindings)
  "Replace variables in TREE according to BINDINGS (recursive).
A value is itself substituted, so chains of bindings are followed to the
end. A variable met again inside its own value is left in place there, so a
circular BINDINGS alist yields a finite tree."
  (labels ((walk (tree expanding)
             (cond
               ((variable-symbol-p tree)
                (let ((pair (and (not (member tree expanding :test #'eq))
                                 (lookup-binding tree bindings))))
                  (if pair
                      (walk (cdr pair) (cons tree expanding))
                      tree)))
               ((atom tree) tree)
               (t (cons (walk (car tree) expanding)
                        (walk (cdr tree) expanding))))))
    (cond
      ((eq bindings *fail*) *fail*)
      ((or (null bindings) (eq bindings *no-bindings*)) tree)
      (t (walk tree nil)))))

;;; Matching

(defun match-variable (var data bindings)
  "Match the variable VAR against DATA under BINDINGS.
An open VAR is bound to DATA; a bound VAR must stand for something that
matches DATA. A variable symbol inside DATA is not renamed apart: it is the
same variable as in the pattern. So VAR matches itself, or a variable that
stands for it, without a new binding, and it does not match DATA that
contains it, which no finite value satisfies."
  (let ((term (dereference var bindings)))
    (cond
      ((not (eq term var)) (match term data bindings))
      ((eq var (dereference data bindings)) bindings)
      ((occurs-check-p var data bindings) *fail*)
      (t (extend-bindings var data bindings)))))

(defun match (pattern data &optional (bindings *no-bindings*))
  "Match PATTERN against DATA with BINDINGS.
Returns an extended bindings alist on success, or *FAIL* on failure.
Only PATTERN introduces bindings; DATA is treated as ground structure
(equal symbols still match). DATA that holds variable symbols all the same
never yields a circular binding: see MATCH-VARIABLE."
  (cond
    ((eq bindings *fail*) *fail*)
    ((anonymous-variable-p pattern) bindings)
    ((variable-symbol-p pattern)
     (match-variable pattern data bindings))
    ((and (consp pattern) (consp data))
     (match (cdr pattern) (cdr data)
            (match (car pattern) (car data) bindings)))
    ((equal pattern data) bindings)
    (t *fail*)))

(defun match-p (pattern data &optional (bindings *no-bindings*))
  "Boolean wrapper around MATCH. Returns (VALUES T BINDINGS) or (VALUES NIL NIL)."
  (let ((b (match pattern data bindings)))
    (if (eq b *fail*)
        (values nil nil)
        (values t (if (eq b *no-bindings*) nil b)))))

(defun match-all (patterns facts &optional (bindings *no-bindings*))
  "Return every bindings alist that satisfies the conjunction PATTERNS
against FACTS (each pattern matches some fact; bindings accumulate).
A solution that binds nothing is *NO-BINDINGS*, as returned by MATCH."
  (labels ((walk (pats binds)
             (if (null pats)
                 (list binds)
                 (mapcan (lambda (fact)
                           (let ((b (match (car pats) fact binds)))
                             (unless (eq b *fail*)
                               (walk (cdr pats) b))))
                         facts))))
    (walk patterns bindings)))
