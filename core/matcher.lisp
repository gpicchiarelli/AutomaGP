;;;; core/matcher.lisp — pattern matching & substitution (Phase 2)
;;;;
;;;; Variables: symbols whose names begin with #\? (e.g. ?X).
;;;; Anonymous variable: the symbol named "?" (matches anything, does not bind).
;;;; Segment/sequence variables (e.g. ?*X) are NOT supported in Phase 2.

(in-package #:automa-gp)

;;; Binding sentinels shared with UNIFY

(defvar *fail* (list 'fail)
  "Unique failure sentinel for MATCH / UNIFY.")

(defvar *no-bindings* (list (cons t t))
  "Sentinel meaning success with an empty binding set.")

(defun fail-p (x)
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

(defun lookup-binding (var bindings)
  "Return the binding pair (VAR . VALUE) for VAR in BINDINGS, or NIL."
  (when (and bindings (not (eq bindings *no-bindings*)))
    (assoc var bindings :test #'eq)))

(defun extend-bindings (var value bindings)
  "Return BINDINGS extended with VAR → VALUE."
  (cons (cons var value)
        (if (eq bindings *no-bindings*) nil bindings)))

(defun substitute-bindings (tree bindings)
  "Replace variables in TREE according to BINDINGS (recursive)."
  (cond
    ((eq bindings *fail*) *fail*)
    ((or (null bindings) (eq bindings *no-bindings*)) tree)
    ((variable-symbol-p tree)
     (let ((pair (lookup-binding tree bindings)))
       (if pair
           (substitute-bindings (cdr pair) bindings)
           tree)))
    ((atom tree) tree)
    (t (cons (substitute-bindings (car tree) bindings)
             (substitute-bindings (cdr tree) bindings)))))

(defun match-variable (var data bindings)
  "Bind VAR to DATA or check consistency with an existing binding."
  (let ((pair (lookup-binding var bindings)))
    (if pair
        (match (cdr pair) data bindings)
        (extend-bindings var data bindings))))

(defun match (pattern data &optional (bindings *no-bindings*))
  "Match PATTERN against DATA with BINDINGS.
Returns an extended bindings alist on success, or *FAIL* on failure.
Only PATTERN introduces bindings; DATA is treated as ground structure
(equal symbols still match)."
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
against FACTS (each pattern matches some fact; bindings accumulate)."
  (labels ((walk (pats binds)
             (if (null pats)
                 (list binds)
                 (mapcan (lambda (fact)
                           (let ((b (match (car pats) fact binds)))
                             (unless (eq b *fail*)
                               (walk (cdr pats) b))))
                         facts))))
    (walk patterns bindings)))
