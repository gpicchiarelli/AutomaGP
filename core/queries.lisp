;;;; core/queries.lisp — symbolic queries (Phase 2)
;;;;
;;;; Query a context's facts (and optionally rules via backward chaining).
;;;; Not a full Prolog engine: no cuts, no negation, bounded depth.

(in-package #:automa-gp)

(defparameter *query-depth-limit* 32
  "Max backward-chaining depth for QUERY / PROVE.")

(defun binding-alist (bindings)
  "Normalize BINDINGS to a plain alist (NIL if empty success)."
  (cond
    ((or (null bindings) (eq bindings *no-bindings*)) nil)
    ((eq bindings *fail*) nil)
    (t bindings)))

(defun variables-in (tree)
  "Collect pattern variables in TREE (excluding anonymous ?)."
  (cond
    ((anonymous-variable-p tree) nil)
    ((variable-symbol-p tree) (list tree))
    ((consp tree)
     (append (variables-in (car tree)) (variables-in (cdr tree))))
    (t nil)))

(defun resolve-var (var bindings)
  "Follow VAR through BINDINGS to a ground value (or the last variable)."
  (let ((pair (lookup-binding var bindings)))
    (cond
      ((null pair) var)
      ((and (variable-symbol-p (cdr pair))
            (not (eq (cdr pair) var)))
       (resolve-var (cdr pair) bindings))
      (t (cdr pair)))))

(defun instantiate-bindings (pattern bindings)
  "Alist of variables occurring in PATTERN mapped to resolved values."
  (let ((b (binding-alist bindings)))
    (mapcar (lambda (v) (cons v (resolve-var v b)))
            (remove-duplicates (variables-in pattern) :test #'eq))))

(defun query-facts (pattern facts)
  "Match PATTERN against FACTS only (no rules).
Each hit is a plist (:FACT f :BINDINGS alist)."
  (loop for fact in facts
        for b = (match pattern fact *no-bindings*)
        unless (eq b *fail*)
          collect (list :fact fact :bindings (binding-alist b))))

(defun prove (goal facts rules &optional (bindings *no-bindings*) (depth 0))
  "Backward-chain: return list of successful binding alists for GOAL.
Tries facts first, then rules whose consequent unifies with GOAL."
  (when (> depth *query-depth-limit*)
    (return-from prove nil))
  (let ((results nil))
    ;; 1. Match against ground facts
    (dolist (fact facts)
      (let ((b (unify goal fact bindings)))
        (unless (eq b *fail*)
          (push b results))))
    ;; 2. Rules
    (dolist (rule rules)
      (dolist (consequent (rule-then rule))
        (let ((b (unify goal consequent bindings)))
          (unless (eq b *fail*)
            (dolist (solution (prove-all (rule-if rule) facts rules b (1+ depth)))
              (push solution results))))))
    (nreverse results)))

(defun prove-all (goals facts rules bindings depth)
  "Prove conjunction GOALS; return list of binding alists."
  (if (null goals)
      (list bindings)
      (mapcan (lambda (b)
                (prove-all (cdr goals) facts rules b depth))
              (prove (car goals) facts rules bindings depth))))

(defun query (pattern context &key (infer t))
  "Query PATTERN in CONTEXT.
If INFER is true (default), use backward chaining over visible rules.
If INFER is NIL, match facts only (like FIND-FACTS / CONTEXT-QUERY).

Returns a list of plists:
  (:BINDINGS alist :FACT grounded-or-nil :SOURCE :FACT|:RULE)"
  (let* ((facts (context-all-facts context))
         (rules (if infer (context-all-rules context) nil)))
    (if (not infer)
        (mapcar (lambda (hit)
                  (list :bindings (instantiate-bindings
                                   pattern
                                   (or (getf hit :bindings) *no-bindings*))
                        :fact (getf hit :fact)
                        :source :fact))
                (query-facts pattern facts))
        (let ((solutions (prove pattern facts rules *no-bindings* 0))
              (out nil))
          (dolist (b solutions)
            (let* ((alist (instantiate-bindings pattern b))
                   (grounded (substitute-bindings pattern b)))
              (push (list :bindings alist
                          :fact (if (fail-p grounded) nil grounded)
                          :source (if (find grounded facts :test #'fact-equal)
                                      :fact
                                      :rule))
                    out)))
          (remove-duplicates (nreverse out)
                             :test (lambda (a b)
                                     (and (equal (getf a :fact) (getf b :fact))
                                          (equal (getf a :bindings)
                                                 (getf b :bindings)))))))))

(defun query-bindings (pattern context &key (infer t))
  "Convenience: list of binding alists only."
  (mapcar (lambda (hit) (getf hit :bindings))
          (query pattern context :infer infer)))
