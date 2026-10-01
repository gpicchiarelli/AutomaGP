;;;; core/induction.lisp — one-shot operator induction
;;;;
;;;; A before/after observation becomes a STRIPS operator. The objects of a
;;;; change are the terms it both removes a fact about and adds a fact
;;;; about; a change that only adds or only removes cannot tell an object
;;;; from a value, so every term of it counts. Preconditions are the removed
;;;; facts plus the before-facts that mention an object. A value such as OFF
;;;; never pulls in another fact, and unrelated facts stay out. With
;;;; generalization, an object symbol that the whole change shares becomes
;;;; ?X0; numbers stay ground. A second example merges only when it fits the
;;;; operator already induced under the same name. A ground merge keeps
;;;; every constant: a different symbol or number does not fit and does not
;;;; become a variable.

(in-package #:automa-gp)

(defvar *observed-before* nil
  "Fact list noted by GP-NOTE-STATE or GP-LISTEN, consumed by learning.")

(defvar *observation* nil
  "Plist for the current listening session: :ACTIVE :BEFORE :MISSING :REASON.")

(defvar *listen-on-plan-failure* t
  "When true, a failed GP-PLAN starts a listening session.")

(define-condition induction-error (error)
  ((name :initarg :name :reader induction-error-name :initform nil)
   (reason :initarg :reason :reader induction-error-reason))
  (:report (lambda (c stream)
             (case (induction-error-reason c)
               (:unchanged-state
                (format stream "The observation did not change the state."))
               (t
                (format stream "Operator ~A cannot be induced: ~(~A~)."
                        (induction-error-name c) (induction-error-reason c))))))
  (:documentation "An observation cannot become the operator NAME.
REASON is a keyword. INDUCE-OPERATOR signals :UNCHANGED-STATE when the
before and after states hold the same facts."))

(defun observation-active-p ()
  "True while a listening session is open."
  (and (listp *observation*) (getf *observation* :active)))

(defun gp-observation ()
  "Copy of the listening session plist, or NIL."
  (copy-list *observation*))

;;; One example

(defun %fact-terms (fact)
  "The terms of FACT other than the predicate. Shares structure with FACT."
  (if (consp fact) (rest fact) nil))

(defun %term-in-fact-p (term fact)
  (member term (%fact-terms fact) :test #'equal))

(defun %terms-of-facts (facts)
  "Each term of FACTS once, in order of first occurrence."
  (remove-duplicates (loop for fact in facts append (%fact-terms fact))
                     :test #'equal :from-end t))

(defun %generalizable-term-p (term)
  "Symbols can be lifted. Numbers stay ground: a port is not a variable."
  (and (symbolp term)
       (not (variable-symbol-p term))
       (not (keywordp term))))

(defun %induction-variable (index)
  (intern (format nil "?X~D" index) :automa-gp))

(defun %lift-fact (fact bindings)
  "FACT with each term that the alist BINDINGS names replaced by its
variable. The predicate is not a term and stays."
  (if (consp fact)
      (cons (first fact)
            (mapcar (lambda (term)
                      (or (cdr (assoc term bindings :test #'equal)) term))
                    (rest fact)))
      fact))

(defun %change-objects (adds deletes)
  "The terms a change is about.
When the change both adds and deletes, they are the terms that occur on
both sides: a value such as ON or OFF occurs on one side only. A change
that only adds or only deletes gives no such evidence, so every term of
it counts."
  (if (and adds deletes)
      (intersection (%terms-of-facts adds) (%terms-of-facts deletes)
                    :test #'equal)
      (%terms-of-facts (or adds deletes))))

(defun %liftable-objects (adds deletes unchanged)
  "Symbols worth lifting from one before/after pair, sorted by name.
A symbol qualifies when it occurs in every changed fact and either the
action both adds and deletes, or the same symbol also occurs in a fact
that stayed true. One example never lifts a value that appears on only
one side, and never lifts a number."
  (let ((changed (append adds deletes)))
    (sort (copy-list
           (remove-if-not
            (lambda (term)
              (and (%generalizable-term-p term)
                   (every (lambda (fact) (%term-in-fact-p term fact)) changed)
                   (or (and adds deletes)
                       (some (lambda (fact) (%term-in-fact-p term fact))
                             unchanged))))
            (%terms-of-facts changed)))
          #'string< :key #'symbol-name)))

(defun induce-operator (name before after &key (generalize nil))
  "Build an OPERATOR named NAME from one observation.
ADDS are facts in AFTER missing from BEFORE. DELETES are the reverse.
PRECONDITIONS are the deleted facts plus the BEFORE facts that mention an
object of the change: a term the change both deletes and adds a fact
about or, when it only adds or only deletes, any of its terms. A value
that occurs on one side only, such as ON or OFF, selects no precondition,
and an unrelated fact in the same state is not required.
When GENERALIZE is true, a repeated object symbol becomes ?X0, ?X1, …
in name order, and the operator's :GENERALIZED meta lists those symbols.
Numbers stay as they are. Lifting changes the terms of the patterns, not
which facts are chosen.
Signals INDUCTION-ERROR when the two states are equal and a TYPE-ERROR
when NAME is NIL. Does not register the operator."
  (check-type name (not null) "an operator name")
  (let ((adds (remove-if (lambda (fact) (fact-p fact before)) after))
        (deletes (remove-if (lambda (fact) (fact-p fact after)) before)))
    (unless (or adds deletes)
      (error 'induction-error :name name :reason :unchanged-state))
    (let* ((unchanged (remove-if-not (lambda (fact) (fact-p fact after)) before))
           (objects (when generalize
                      (%liftable-objects adds deletes unchanged)))
           (bindings (loop for object in objects
                           for i from 0
                           collect (cons object (%induction-variable i))))
           (focus (%change-objects adds deletes)))
      (flet ((lift (facts)
               (mapcar (lambda (fact) (%lift-fact fact bindings)) facts))
             (required-p (fact)
               (or (fact-p fact deletes)
                   (some (lambda (term) (%term-in-fact-p term fact)) focus))))
        (make-operator :name name
                       :preconditions (lift (remove-if-not #'required-p before))
                       :add-list (lift adds)
                       :delete-list (lift deletes)
                       :meta (list :induced t :generalized objects))))))

;;; A further example

(defun %same-term-p (a b)
  "True when A and B are the same term. Symbols compare by name: a term the
JSON façade read equals the one typed at the REPL."
  (if (and (symbolp a) (symbolp b))
      (string= (symbol-name a) (symbol-name b))
      (equal a b)))

(defun %next-induction-index (facts)
  "The next ?Xn index after those already used in FACTS."
  (let ((max -1))
    (dolist (fact facts)
      (dolist (term (%fact-terms fact))
        (when (variable-symbol-p term)
          (let ((name (symbol-name term)))
            (when (and (>= (length name) 3)
                       (char-equal (char name 1) #\X)
                       (every #'digit-char-p (subseq name 2)))
              (setf max (max max (parse-integer name :start 2))))))))
    (1+ max)))

(defun %term-counts (facts)
  "How often each generalizable symbol occurs as a term across FACTS."
  (let ((counts (make-hash-table :test #'equal)))
    (dolist (fact facts counts)
      (dolist (term (%fact-terms fact))
        (when (%generalizable-term-p term)
          (incf (gethash term counts 0)))))))

(defun %operator-patterns (operator)
  (append (operator-preconditions operator)
          (operator-add-list operator)
          (operator-delete-list operator)))

(defun %operator-uses-variables-p (operator)
  "True when any pattern term of OPERATOR is a variable."
  (some (lambda (fact)
          (and (consp fact) (some #'variable-symbol-p fact)))
        (%operator-patterns operator)))

(defun %merged-operator (existing new preconditions adds deletes covered)
  "EXISTING with the merged patterns and one more example on record.
COVERED lists the symbols its variables newly stand for. Everything else
EXISTING carries stays: parameters, cost, action, risk, reversibility and
every other meta key."
  (let ((meta (copy-list (operator-meta existing))))
    (setf (getf meta :induced) t
          (getf meta :examples) (1+ (or (getf meta :examples) 1))
          (getf meta :generalized)
          (remove-duplicates
           (remove nil (append (getf meta :generalized)
                               (getf (operator-meta new) :generalized)
                               covered))
           :test #'equal :from-end t))
    (make-operator :name (operator-name existing)
                   :parameters (operator-parameters existing)
                   :preconditions preconditions
                   :add-list adds
                   :delete-list deletes
                   :cost (operator-cost existing)
                   :action (operator-action existing)
                   :reversible (operator-reversible existing)
                   :risk (operator-risk existing)
                   :meta meta)))

(defun merge-induced-operators (existing new &key (lift t))
  "Merge the example NEW into the operator EXISTING when it fits.
Returns the merged operator, or NIL when NEW does not fit; EXISTING is
never modified, and nothing is registered.

Each fact of EXISTING is paired with a distinct fact of NEW that has the
same predicate and length, whatever the order of the lists, and the two
are merged term by term. Equal terms stay. When LIFT is false nothing
else fits: a different symbol or number is refused and no variable is
introduced. When LIFT is true:
- a variable of EXISTING stands for one object of the example, so it must
  meet the same symbol of NEW wherever it occurs (a variable of NEW counts
  as a symbol, so NEW may be generalized or ground);
- a constant symbol that occurs at least twice in EXISTING and meets the
  same different symbol of NEW each time becomes the next ?Xn;
- a different number, and a symbol that occurs once, are refused.
Of the pairings that fit, one that turns the fewest constants into
variables is taken: an example that only repeats EXISTING lifts nothing,
in whatever order it lists its facts.

The merged operator keeps the parameters, cost, action, risk,
reversibility and meta of EXISTING; its :EXAMPLES count grows by one and
:GENERALIZED gains the symbols its variables newly stand for."
  (let* ((patterns (%operator-patterns existing))
         (counts (%term-counts patterns))
         (first-index (%next-induction-index patterns))
         (liftable (if lift
                       (loop for count being the hash-values of counts
                             count (>= count 2))
                       0))
         (budget 0))
    ;; STATE is (IMAGES . LIFTS), newest entry first. IMAGES maps a variable
    ;; of EXISTING to the term of NEW it stands for. LIFTS maps a constant
    ;; of EXISTING to (TERM-OF-NEW . VARIABLE) and holds at most BUDGET
    ;; entries. A NIL state means no fit.
    (labels ((merge-term (a b state)
               (destructuring-bind (images . lifts) state
                 (cond
                   ((not lift)
                    (values a (and (%same-term-p a b) state)))
                   ((variable-symbol-p a)
                    (let ((image (assoc a images :test #'eq)))
                      (cond
                        (image
                         (values a (and (%same-term-p (cdr image) b) state)))
                        ((and (symbolp b) (not (keywordp b)))
                         (values a (cons (acons a b images) lifts)))
                        (t
                         (values a nil)))))
                   ((%same-term-p a b)
                    (values a state))
                   ((and (%generalizable-term-p a) (%generalizable-term-p b))
                    (let ((lifted (assoc a lifts :test #'eq)))
                      (cond
                        (lifted
                         (destructuring-bind (term . variable) (cdr lifted)
                           (values variable
                                   (and (%same-term-p term b) state))))
                        ((and (>= (gethash a counts 0) 2)
                              (< (length lifts) budget))
                         (let ((variable (%induction-variable
                                          (+ first-index (length lifts)))))
                           (values variable
                                   (cons images
                                         (acons a (cons b variable) lifts)))))
                        (t
                         (values a nil)))))
                   (t
                    (values a nil)))))
             (merge-fact (a b state)
               ;; (VALUES FACT STATE), or NIL when B does not fit A.
               (when (and (consp a) (consp b)
                          (%same-term-p (first a) (first b))
                          (= (length a) (length b)))
                 (let ((terms nil))
                   (loop for x in (rest a)
                         for y in (rest b)
                         do (multiple-value-bind (term next)
                                (merge-term x y state)
                              (unless next
                                (return-from merge-fact nil))
                              (push term terms)
                              (setf state next)))
                   (values (cons (first a) (nreverse terms)) state))))
             (merge-facts (as bs state k)
               ;; Call K on the merged facts, in the order of AS, and the
               ;; state they leave. A pairing K rejects with NIL is undone
               ;; and the next one tried; the first non-NIL value of K wins.
               (if (null as)
                   (and (null bs) (funcall k nil state))
                   (some (lambda (b)
                           (multiple-value-bind (fact next)
                               (merge-fact (first as) b state)
                             (and fact
                                  (merge-facts
                                   (rest as)
                                   (remove b bs :test #'eq :count 1)
                                   next
                                   (lambda (facts state)
                                     (funcall k (cons fact facts) state))))))
                         bs)))
             (merge-operators ()
               (merge-facts
                (operator-preconditions existing) (operator-preconditions new)
                (cons nil nil)
                (lambda (preconditions state)
                  (merge-facts
                   (operator-add-list existing) (operator-add-list new) state
                   (lambda (adds state)
                     (merge-facts
                      (operator-delete-list existing) (operator-delete-list new)
                      state
                      (lambda (deletes state)
                        (destructuring-bind (images . lifts) state
                          (%merged-operator
                           existing new preconditions adds deletes
                           (append
                            (loop for (nil . term) in (reverse images)
                                  unless (variable-symbol-p term)
                                    collect term)
                            (loop for (constant term) in (reverse lifts)
                                  collect constant
                                  collect term))))))))))))
      ;; The smallest number of lifted constants that fits comes first.
      (loop for limit from 0 to liftable
            do (setf budget limit)
            thereis (merge-operators)))))
