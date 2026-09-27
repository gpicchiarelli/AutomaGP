;;;; core/induction.lisp — one-shot operator induction
;;;;
;;;; A before/after observation becomes a STRIPS operator. Preconditions are
;;;; the before-facts that share a term with the change. With generalization,
;;;; an object symbol that the whole change shares becomes ?X0; numbers stay
;;;; ground. Unrelated facts stay out. A second example merges only when it
;;;; fits the operator already induced under the same name. A ground merge
;;;; keeps every constant: a different symbol or number does not fit and
;;;; does not become a variable.

(in-package #:automa-gp)

(defvar *observed-before* nil
  "Fact list noted by GP-NOTE-STATE or GP-LISTEN, consumed by learning.")

(defvar *observation* nil
  "Plist for the current listening session: :ACTIVE :BEFORE :MISSING :REASON.")

(defvar *listen-on-plan-failure* t
  "When true, a failed GP-PLAN starts a listening session.")

(defun observation-active-p ()
  "True while a listening session is open."
  (and (listp *observation*) (getf *observation* :active)))

(defun gp-observation ()
  "Copy of the listening session plist, or NIL."
  (copy-list *observation*))

(defun %fact-terms (fact)
  "A fresh list of the terms of FACT other than the predicate.
The copy matters: callers may nconc these lists."
  (if (consp fact) (copy-list (rest fact)) nil))

(defun %facts-about-terms (facts terms)
  "Facts in FACTS that mention at least one term in TERMS."
  (remove-if-not
   (lambda (fact)
     (some (lambda (term)
             (member term (%fact-terms fact) :test #'equal))
           terms))
   facts))

(defun %generalizable-term-p (term)
  "Symbols can be lifted. Numbers stay ground: a port is not a variable."
  (and (symbolp term)
       (not (variable-symbol-p term))
       (not (keywordp term))))

(defun %term-in-fact-p (term fact)
  (member term (%fact-terms fact) :test #'equal))

(defun %induction-variable (index)
  (intern (format nil "?X~D" index) :automa-gp))

(defun %substitute-term (term bindings)
  (or (cdr (assoc term bindings :test #'equal)) term))

(defun %substitute-fact (fact bindings)
  (mapcar (lambda (term) (%substitute-term term bindings)) fact))

(defun %object-terms (changed before after)
  "Symbols worth lifting from one before/after pair.
A symbol qualifies when it occurs in every changed fact and either the
action both adds and deletes, or the same symbol also occurs in a fact
that stayed true. One example never lifts a value that appears on only
one side, and never lifts a number."
  (let* ((adds (remove-if (lambda (fact) (fact-p fact before)) after))
         (deletes (remove-if (lambda (fact) (fact-p fact after)) before))
         (unchanged (remove-if-not (lambda (fact) (fact-p fact after)) before))
         (shared (remove-if-not
                  (lambda (term)
                    (and (%generalizable-term-p term)
                         (every (lambda (fact) (%term-in-fact-p term fact))
                                changed)))
                  (remove-duplicates (mapcan #'%fact-terms changed) :test #'equal))))
    (sort (copy-list
           (remove-if-not
            (lambda (term)
              (or (and adds deletes)
                  (some (lambda (fact) (%term-in-fact-p term fact)) unchanged)))
            shared))
          #'string< :key #'symbol-name)))

(defun induce-operator (name before after &key (generalize nil))
  "Build an OPERATOR named NAME from one observation.
ADDS are facts in AFTER missing from BEFORE. DELETES are the reverse.
PRECONDITIONS are BEFORE facts that mention a term of that change,
so an unrelated fact in the same state is not required.
When GENERALIZE is true, a repeated object symbol becomes ?X0, ?X1, …
Numbers stay as they are. Signals an error when the two states are equal,
or when NAME is missing. Does not register the operator."
  (unless name
    (error "induce-operator requires a name"))
  (let* ((adds (remove-if (lambda (fact) (fact-p fact before)) after))
         (deletes (remove-if (lambda (fact) (fact-p fact after)) before))
         (changed (append adds deletes)))
    (when (null changed)
      (error "The observation did not change the state."))
    (let* ((objects (if generalize
                        (%object-terms changed before after)
                        nil))
           (bindings (loop for term in objects
                           for i from 0
                           collect (cons term (%induction-variable i))))
           (terms (remove-duplicates
                   (append (mapcan #'%fact-terms adds)
                           (mapcan #'%fact-terms deletes))
                   :test #'equal))
           (focus (if objects objects terms)))
      (make-operator :name name
                     :preconditions (mapcar (lambda (fact)
                                              (%substitute-fact fact bindings))
                                            (%facts-about-terms before focus))
                     :add-list (mapcar (lambda (fact)
                                         (%substitute-fact fact bindings))
                                       adds)
                     :delete-list (mapcar (lambda (fact)
                                            (%substitute-fact fact bindings))
                                          deletes)
                     :meta (list :induced t
                                 :generalized (if objects objects nil))))))

(defun %same-term-p (a b)
  (cond
    ((and (symbolp a) (symbolp b))
     (string= (symbol-name a) (symbol-name b)))
    (t (equal a b))))

(defun %next-induction-index (facts)
  "The next ?Xn index after those already used in FACTS."
  (let ((max -1))
    (dolist (fact facts)
      (dolist (term fact)
        (when (variable-symbol-p term)
          (let ((name (symbol-name term)))
            (when (and (>= (length name) 3)
                       (char= (char name 0) #\?)
                       (char-equal (char name 1) #\X))
              (let ((rest (subseq name 2)))
                (when (every #'digit-char-p rest)
                  (let ((n (parse-integer rest)))
                    (when (> n max) (setf max n))))))))))
    (1+ max)))

(defun %term-counts (facts)
  "How often each generalizable symbol occurs across FACTS."
  (let ((counts (make-hash-table :test #'equal)))
    (dolist (fact facts counts)
      (dolist (term fact)
        (when (%generalizable-term-p term)
          (setf (gethash term counts) (1+ (gethash term counts 0))))))))

(defun %align-fact-lists (as bs)
  "Pair facts that share a predicate and a length. Returns (VALUES PAIRS OK)."
  (unless (= (length as) (length bs))
    (return-from %align-fact-lists (values nil nil)))
  (let ((used nil)
        (pairs nil)
        (ok t))
    (dolist (a as)
      (let ((b (find-if
                (lambda (candidate)
                  (and (not (member candidate used :test #'eq))
                       (consp a) (consp candidate)
                       (= (length a) (length candidate))
                       (symbolp (car a)) (symbolp (car candidate))
                       (string= (symbol-name (car a)) (symbol-name (car candidate)))))
                bs)))
        (if b
            (progn (push b used) (push (cons a b) pairs))
            (setf ok nil))))
    (if ok
        (values (nreverse pairs) t)
        (values nil nil))))

(defun %operator-uses-variables-p (operator)
  "True when any pattern term of OPERATOR is a variable."
  (some (lambda (fact)
          (and (consp fact) (some #'variable-symbol-p fact)))
        (append (operator-preconditions operator)
                (operator-add-list operator)
                (operator-delete-list operator))))

(defun merge-induced-operators (existing new &key (lift t))
  "Merge NEW into EXISTING when the new example fits.
When LIFT is true, an existing variable stays and covers the new symbol,
and a symbol that occurs at least twice and differs by a consistent rename
becomes the next ?Xn. When LIFT is false, every term must already be the
same constant: a different symbol or number does not fit, and no variable
is introduced. A different shape returns NIL and leaves EXISTING unused
by the caller. Does not register."
  (let ((counts (%term-counts (append (operator-preconditions existing)
                                      (operator-add-list existing)
                                      (operator-delete-list existing))))
        (mapping nil)
        (vars nil)
        (lifted nil)
        (index (%next-induction-index
                (append (operator-preconditions existing)
                        (operator-add-list existing)
                        (operator-delete-list existing)))))
    (labels ((merge-term (a b)
               (cond
                 ((%same-term-p a b) a)
                 ((and lift (variable-symbol-p a) (%generalizable-term-p b)) a)
                 ((and lift (variable-symbol-p b) (%generalizable-term-p a)) b)
                 ((or (numberp a) (numberp b)) nil)
                 ((and lift (%generalizable-term-p a) (%generalizable-term-p b))
                  (let ((seen (assoc a mapping :test #'equal)))
                    (cond
                      ((and seen (not (%same-term-p (cdr seen) b))) nil)
                      ((< (gethash a counts 0) 2) nil)
                      (t
                       (let ((var (cdr (assoc a vars :test #'equal))))
                         (unless var
                           (setf var (%induction-variable index))
                           (incf index)
                           (push (cons a var) vars)
                           (push a lifted)
                           (push b lifted))
                         (unless seen
                           (push (cons a b) mapping))
                         var)))))
                 (t nil)))
             (merge-fact (a b)
               (let ((out nil))
                 (loop for x in a
                       for y in b
                       for term = (merge-term x y)
                       do (if term
                              (push term out)
                              (return-from merge-fact nil)))
                 (nreverse out)))
             (merge-facts (as bs)
               (multiple-value-bind (pairs ok) (%align-fact-lists as bs)
                 (unless ok
                   (return-from merge-facts (values nil nil)))
                 (let ((out nil))
                   (dolist (pair pairs)
                     (let ((fact (merge-fact (car pair) (cdr pair))))
                       (unless fact
                         (return-from merge-facts (values nil nil)))
                       (push fact out)))
                   (values (nreverse out) t)))))
      (multiple-value-bind (pre pre-ok)
          (merge-facts (operator-preconditions existing)
                       (operator-preconditions new))
        (multiple-value-bind (adds add-ok)
            (merge-facts (operator-add-list existing)
                         (operator-add-list new))
          (multiple-value-bind (deletes delete-ok)
              (merge-facts (operator-delete-list existing)
                           (operator-delete-list new))
            (when (and pre-ok add-ok delete-ok)
              (make-operator :name (operator-name existing)
                             :preconditions pre
                             :add-list adds
                             :delete-list deletes
                             :cost (operator-cost existing)
                             :meta
                             (list :induced t
                                   :examples (1+ (or (getf (operator-meta existing) :examples)
                                                     1))
                                   :generalized
                                   (remove-duplicates
                                    (remove nil
                                            (append (getf (operator-meta existing) :generalized)
                                                    (getf (operator-meta new) :generalized)
                                                    (nreverse lifted))
                                            :test #'eq)
                                    :test #'equal))))))))))
