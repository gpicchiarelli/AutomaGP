;;;; interface/ask.lisp — an Italian phrase becomes a goal, or nothing
;;;;
;;;; A leading voglio, raggiungi, obiettivo, manca, fammi, ottieni, or rendi
;;;; is optional. The remaining words are a goal when an operator add, a
;;;; reaction goal, a rule consequent, or a current goal has that shape.
;;;; The first word may instead be the operator's name, a reaction name, or
;;;; a rule name: the predicate is then supplied by that add, goal, or
;;;; consequent. A word listed in an operator's :ASK meta works the same
;;;; way. A declared word also covers the same stem, so accendi and
;;;; accendere name one operator. GP-NAME-OPERATOR declares that word on
;;;; the operator, reaction, or rule that alone has that name. A :KIND
;;;; picks one of them when the name is shared. An unknown first word
;;;; records nothing. When the other words fit a goal and that word is
;;;; not a term of it, those goals are named and the word is not
;;;; declared. A word alone is offered only when
;;;; it is a fixed term of a goal, or the same stem of that term, or one
;;;; exact piece of that goal's name, and exactly one such goal has no
;;;; variables left. The stem also drops one adverb ending in -MENTE, one
;;;; superlative ending, and one abstract ending in -EZZA, so
;;;; prontamente, prontissimo, prontezza, and pronto share a stem. A
;;;; noun in -SIONE from a verb in -ERE restores the final D, so
;;;; accensione shares the stem of accendi. A noun in -MENTO does the
;;;; same, so accendimento shares that stem. A word whose stem is
;;;; exactly a name, such as power-one for power-on, is not offered as
;;;; a new word. When
;;;; several of those goals
;;;; have no variables, the word names them and records none. The name
;;;; itself is not stemmed.
;;;; The operator's own name stays exact.
;;;; A fixed term at the end may be left unsaid. If those words
;;;; fit two different goals, nothing is recorded. Anything that asks to
;;;; execute, delete, or run a command is refused. The phrase never runs a
;;;; plan step and never touches the shell.

(in-package #:automa-gp)

(defparameter *ask-verbs* '("VOGLIO" "RAGGIUNGI" "OBIETTIVO" "MANCA"
                           "FAMMI" "OTTIENI" "RENDI")
  "Optional words that introduce a goal. The goal shape can also stand alone.")

(defparameter *ask-stops* '("CHE" "SIA" "SIANO" "IL" "LA" "LO" "I" "GLI" "LE"
                            "UN" "UNA" "DI" "DEL" "DELLA" "DELLO" "A" "AD"
                            "PER" "SU" "SUL" "SULLA" "AVERE")
  "Italian glue that carries no term.")

(defparameter *ask-refusals* '("ESEGUI" "ESEGUIRE" "CANCELLA" "ELIMINA"
                              "SHELL" "TERMINALE" "COMANDO" "RM" "SUDO")
  "Words that ask for an action instead of a goal.")

(defun %ask-word (token)
  "TOKEN without a trailing colon or period, in upper case."
  (string-upcase (string-right-trim '(#\: #\. #\, #\;) token)))

(defun %ask-tokens (phrase)
  "Words of PHRASE. A token with '.' or '/' keeps its case; the rest are upper case."
  (mapcar (lambda (token)
            (if (or (find #\. token) (find #\/ token))
                (string-right-trim '(#\: #\. #\, #\;) token)
                (%ask-word token)))
          (remove "" (uiop:split-string phrase :separator '(#\Space #\Tab #\Newline #\Return))
                  :test #'string=)))

(defun %push-named-symbols (pattern bag)
  (when (consp pattern)
    (dolist (term pattern)
      (when (and (symbolp term)
                 (not (keywordp term))
                 (not (variable-symbol-p term)))
        (push term bag))))
  bag)

(defun %context-named-symbols ()
  "Non-variable symbols already used in this context."
  (let ((bag nil))
    (dolist (fact (append (gp-facts) (gp-goals)))
      (setf bag (%push-named-symbols fact bag)))
    (dolist (op (gp-operators))
      (dolist (pattern (append (operator-preconditions op)
                               (operator-add-list op)
                               (operator-delete-list op)))
        (setf bag (%push-named-symbols pattern bag))))
    (dolist (reaction (gp-reactions))
      (dolist (pattern (append (event-reaction-goals reaction)
                               (and (consp (event-reaction-when reaction))
                                    (list (event-reaction-when reaction)))
                               (event-reaction-assert reaction)))
        (setf bag (%push-named-symbols pattern bag))))
    (dolist (rule (gp-rules))
      (dolist (pattern (append (rule-if rule) (rule-then rule)))
        (setf bag (%push-named-symbols pattern bag))))
    bag))

(defun %ask-term (raw home)
  "A number, a path string, or a symbol already used under this name."
  (cond
    ((and (plusp (length raw)) (every #'digit-char-p raw))
     (parse-integer raw))
    ((or (find #\. raw) (find #\/ raw))
     raw)
    (t
     (or (find raw (%context-named-symbols) :key #'symbol-name :test #'string=)
         (intern raw (or home (find-package :automa-gp)))))))

(defun %goal-patterns ()
  "Patterns this context already treats as something to achieve."
  (let ((patterns nil))
    (dolist (op (gp-operators))
      (dolist (pattern (operator-add-list op))
        (push pattern patterns)))
    (dolist (reaction (gp-reactions))
      (dolist (pattern (event-reaction-goals reaction))
        (push pattern patterns)))
    (dolist (rule (gp-rules))
      (dolist (pattern (rule-then rule))
        (push pattern patterns)))
    (dolist (goal (gp-goals))
      (when (consp goal)
        (push goal patterns)))
    patterns))

(defun %term-said-p (pat raw)
  "True when RAW is the word for a fixed term PAT."
  (cond
    ((and (symbolp pat)
          (not (variable-symbol-p pat))
          (string= (symbol-name pat) raw))
     t)
    ((and (numberp pat)
          (plusp (length raw))
          (every #'digit-char-p raw)
          (= pat (parse-integer raw)))
     t)
    ((and (stringp pat) (string-equal pat raw))
     t)
    (t nil)))

(defun %ground-goal (pattern tokens &key (home nil home-p))
  "Ground PATTERN with TOKENS, or NIL when the shape does not match.
The words follow the pattern in order. A variable takes the next word,
unless that word is a fixed term later in the pattern. A fixed term may
be left unsaid only after the words run out. A term in the middle has to
be said. HOME is the package for a word that is not already in the context."
  (unless (and (consp pattern) tokens)
    (return-from %ground-goal nil))
  (let ((home (if home-p
                  home
                  (and (symbolp (car pattern))
                       (not (variable-symbol-p (car pattern)))
                       (symbol-package (car pattern))))))
    (labels ((walk (pat toks goal)
               (cond
                 ((null pat)
                  (if (null toks) (nreverse goal) nil))
                 ((and (null toks) (not (variable-symbol-p (first pat))))
                  (walk (rest pat) nil (cons (first pat) goal)))
                 ((null toks) nil)
                 ((variable-symbol-p (first pat))
                  (if (some (lambda (term) (%term-said-p term (first toks)))
                            (rest pat))
                      nil
                      (walk (rest pat)
                            (rest toks)
                            (cons (%ask-term (first toks) home) goal))))
                 ((%term-said-p (first pat) (first toks))
                  (walk (rest pat) (rest toks) (cons (first pat) goal)))
                 (t nil))))
      (walk pattern tokens nil))))

(defun %ask-label (word)
  "WORD as an upper-case name."
  (string-upcase (string word)))

(defun %ask-cut (word endings)
  "WORD without one of ENDINGS, when at least four letters remain."
  (some (lambda (ending)
          (let ((n (length ending))
                (w (length word)))
            (when (and (> w n)
                       (>= (- w n) 4)
                       (string= word ending :start1 (- w n)))
              (subseq word 0 (- w n)))))
        endings))

(defun %ask-zione (word)
  "Stem of a -ZIONE noun, or NIL.
ZIONE leaves the verb stem for the usual vowel cut. A noun in -SIONE
from a verb in -ERE restores the final D, so accensione shares the
stem of accendere. A name is not passed here."
  (or (%ask-cut word '("ZIONE" "ZIONI"))
      (let ((head (%ask-cut word '("SIONE" "SIONI"))))
        (when head
          (concatenate 'string head "D")))))

(defun %ask-stem (word)
  "Stem of WORD, or NIL when it would be shorter than four letters.
One adverb ending in -MENTE comes off first, then one superlative,
then one abstract ending in -EZZA, then one -ZIONE noun, then one
-MENTO noun. Then one infinitive or gerund ending, otherwise one
final vowel. A name is not passed here."
  (let* ((adverb (%ask-cut word '("MENTE")))
         (base (or adverb word))
         (super (%ask-cut base '("ISSIMO" "ISSIMA" "ISSIMI" "ISSIME")))
         (abstract (%ask-cut (or super base) '("EZZA" "EZZE")))
         (zione (%ask-zione (or abstract super base)))
         (mento (%ask-cut (or zione abstract super base) '("MENTO" "MENTI")))
         (stem (or mento zione abstract super base)))
    (or (%ask-cut stem '("ANDO" "ENDO" "ARE" "ERE" "IRE"))
        (when (and (>= (length stem) 5)
                   (find (char stem (1- (length stem))) "AEIO"))
          (subseq stem 0 (1- (length stem))))
        mento
        zione
        abstract
        super
        adverb)))

(defun %ask-alias-p (alias word)
  "True when WORD is ALIAS, or both share a stem of at least four letters."
  (let ((alias (%ask-label alias)))
    (or (string= alias word)
        (let ((a (%ask-stem alias))
              (b (%ask-stem word)))
          (and a b (string= a b))))))

(defun %declared-word (word)
  "One upper-case word, or an error when WORD is empty or several words."
  (let ((raw (string-trim '(#\Space #\Tab #\Newline #\Return) (string word))))
    (when (or (zerop (length raw))
              (find-if (lambda (ch)
                         (member ch '(#\Space #\Tab #\Newline #\Return)))
                       raw))
      (error "The operator needs one word."))
    (%ask-word raw)))

(defun %find-operator-named (name)
  "The operator whose name matches NAME, ignoring package."
  (let ((label (%ask-label name)))
    (find-if (lambda (op)
               (string= label (%ask-label (operator-name op))))
             (gp-operators))))

(defun %meta-put (meta key value)
  "META with KEY set to VALUE, other entries kept."
  (cons key
        (cons value
              (loop for (k v) on meta by #'cddr
                    unless (eq k key)
                      nconc (list k v)))))

(defun %declared-answers-p (name ask word)
  "True when WORD is exactly NAME, or the stem of a word in ASK.
NAME itself is not stemmed."
  (or (and name (string= word (%ask-label name)))
      (some (lambda (alias) (%ask-alias-p alias word)) ask)))

(defun %named-entries ()
  "Each operator, reaction, and rule as (KIND OBJECT NAME ASK)."
  (append (mapcar (lambda (op)
                    (list :operator op (operator-name op)
                          (getf (operator-meta op) :ask)))
                  (gp-operators))
          (mapcar (lambda (reaction)
                    (list :reaction reaction (event-reaction-name reaction)
                          (getf (event-reaction-meta reaction) :ask)))
                  (gp-reactions))
          (mapcar (lambda (rule)
                    (list :rule rule (rule-name rule)
                          (getf (rule-meta rule) :ask)))
                  (gp-rules))))

(defun %kind-label (kind)
  (ecase kind
    (:operator "Operator")
    (:reaction "Reaction")
    (:rule "Rule")))

(defun %declare-word (kind object token)
  "Register OBJECT again with TOKEN added to its :ASK list."
  (let* ((ask (ecase kind
                (:operator (getf (operator-meta object) :ask))
                (:reaction (getf (event-reaction-meta object) :ask))
                (:rule (getf (rule-meta object) :ask))))
         (meta (ecase kind
                 (:operator (%meta-put (operator-meta object) :ask
                                       (append ask (list token))))
                 (:reaction (%meta-put (event-reaction-meta object) :ask
                                       (append ask (list token))))
                 (:rule (%meta-put (rule-meta object) :ask
                                   (append ask (list token)))))))
    (ecase kind
      (:operator
       (gp-add-operator
        (make-operator :name (operator-name object)
                       :parameters (operator-parameters object)
                       :preconditions (operator-preconditions object)
                       :add-list (operator-add-list object)
                       :delete-list (operator-delete-list object)
                       :cost (operator-cost object)
                       :action (operator-action object)
                       :reversible (operator-reversible object)
                       :risk (operator-risk object)
                       :meta meta)))
      (:reaction
       (gp-add-reaction
        (make-event-reaction :name (event-reaction-name object)
                             :when (event-reaction-when object)
                             :assert (event-reaction-assert object)
                             :goals (event-reaction-goals object)
                             :meta meta)))
      (:rule
       (gp-add-rule
        (make-rule :name (rule-name object)
                   :if (rule-if object)
                   :then (rule-then object)
                   :meta meta))))))

(defun %name-kind (kind)
  "KIND as :OPERATOR, :REACTION, or :RULE. NIL when KIND is omitted.
An unknown kind is an error."
  (when kind
    (let ((label (%ask-label kind)))
      (cond
        ((string= label "OPERATOR") :operator)
        ((string= label "REACTION") :reaction)
        ((string= label "RULE") :rule)
        (t (error "That kind is not an operator, a reaction, or a rule."))))))

(defun gp-name-operator (name word &key kind)
  "Declare that WORD names the operator, reaction, or rule NAME.
NAME must pick out one of those, unless KIND says which. The same stem
counts, as with GP-ASK. A command word is refused. If another one already
answers to WORD, or more than one thing has NAME and KIND is omitted,
that is an error and nothing changes. Declaring the same word again keeps
a single entry. Returns the object."
  (let* ((token (%declared-word word))
         (label (%ask-label name))
         (wanted (%name-kind kind))
         (found (remove-if-not
                 (lambda (entry)
                   (and (third entry)
                        (string= label (%ask-label (third entry)))
                        (or (null wanted) (eq wanted (first entry)))))
                 (%named-entries))))
    (cond
      ((null found)
       (if wanted
           (error "No ~A named ~A." (string-downcase (%kind-label wanted)) name)
           (error "No operator, reaction, or rule named ~A." name)))
      ((rest found)
       (error "More than one thing is named ~A." name))
      ((or (member token *ask-refusals* :test #'string=)
           (member token *ask-verbs* :test #'string=)
           (member token *ask-stops* :test #'string=))
       (error "That word cannot name an operator."))
      (t
       (destructuring-bind (kind object entry-name ask) (first found)
         (dolist (entry (%named-entries))
           (unless (and (eq kind (first entry))
                        (string= label (%ask-label (third entry))))
             (when (%declared-answers-p (third entry) (fourth entry) token)
               (error "~A ~A already answers to ~A."
                      (%kind-label (first entry)) (third entry) token))))
         (if (%declared-answers-p entry-name ask token)
             object
             (%declare-word kind object token)))))))

(defun %operator-answers-p (operator word)
  "True when WORD is OPERATOR's name, or the stem of one :ASK word.
The operator name itself is exact: power-on does not match power-one."
  (%declared-answers-p (operator-name operator)
                       (getf (operator-meta operator) :ask)
                       word))

(defun %operator-add-goal (pattern tail)
  "Ground PATTERN from TAIL, which follows an operator's name.
TAIL may omit the predicate: the operator supplies it. With no TAIL, the
pattern is the goal only when it has no variables."
  (cond
    ((null pattern) nil)
    ((and (null tail) (notany #'variable-symbol-p pattern))
     (copy-list pattern))
    ((null tail) nil)
    (t
     (or (%ground-goal pattern tail)
         (let* ((predicate (first pattern))
                (home (and (symbolp predicate)
                           (not (variable-symbol-p predicate))
                           (symbol-package predicate)))
                (rest-goal (and (rest pattern)
                                (%ground-goal (rest pattern) tail :home home))))
           (when rest-goal
             (cons predicate rest-goal)))))))

(defun %goals-from-operator-word (body)
  "Goals named by the first word of BODY as an operator, or NIL."
  (let ((goals nil))
    (dolist (op (gp-operators))
      (when (%operator-answers-p op (first body))
        (dolist (pattern (operator-add-list op))
          (let ((goal (%operator-add-goal pattern (rest body))))
            (when goal (push goal goals))))))
    goals))

(defun %goals-named-by (patterns word tail name ask)
  "Goals from PATTERNS when WORD names NAME or a word in ASK.
The name itself is not stemmed. A declared word's stem counts."
  (when (%declared-answers-p name ask word)
    (let ((goals nil))
      (dolist (pattern patterns)
        (let ((goal (%operator-add-goal pattern tail)))
          (when goal (push goal goals))))
      goals)))

(defun %goals-from-reaction-word (body)
  "Goals named by the first word of BODY as a reaction, or NIL."
  (let ((goals nil))
    (dolist (reaction (gp-reactions))
      (setf goals (append (%goals-named-by (event-reaction-goals reaction)
                                           (first body)
                                           (rest body)
                                           (event-reaction-name reaction)
                                           (getf (event-reaction-meta reaction) :ask))
                          goals)))
    goals))

(defun %goals-from-rule-word (body)
  "Goals named by the first word of BODY as a rule, or NIL."
  (let ((goals nil))
    (dolist (rule (gp-rules))
      (setf goals (append (%goals-named-by (rule-then rule)
                                           (first body)
                                           (rest body)
                                           (rule-name rule)
                                           (getf (rule-meta rule) :ask))
                          goals)))
    goals))

(defun %term-label (term)
  "TERM as text, without a package prefix."
  (typecase term
    (symbol (symbol-name term))
    (string term)
    (t (princ-to-string term))))

(define-condition ambiguous-goal (error)
  ((goals :initarg :goals :reader ambiguous-goal-goals :initform nil))
  (:report (lambda (c stream)
             (format stream
                     "This context has more than one goal of that shape: ~{~A~^; ~}."
                     (mapcar (lambda (goal)
                               (format nil "~{~A~^ ~}"
                                       (mapcar #'%term-label goal)))
                             (ambiguous-goal-goals c)))))
  (:documentation
   "PHRASE fits more than one goal. None of them is recorded."))

(defun %entry-patterns (entry)
  "Add patterns, reaction goals, or rule consequents of ENTRY."
  (ecase (first entry)
    (:operator (operator-add-list (second entry)))
    (:reaction (event-reaction-goals (second entry)))
    (:rule (rule-then (second entry)))))

(defun %goal-mentions-word-p (goal word)
  "True when WORD is a fixed term of GOAL, or the same stem of a symbol.
Names are not stemmed here: power-one does not match power-on."
  (some (lambda (term)
          (or (%term-said-p term word)
              (and (symbolp term)
                   (not (variable-symbol-p term))
                   (%ask-alias-p term word))))
        goal))

(defun %name-mentions-word-p (name word)
  "True when WORD is NAME, or one hyphenated piece of NAME.
power-one does not match power-on."
  (when name
    (let ((label (%ask-label name)))
      (or (string= label word)
          (member word (uiop:split-string label :separator "-")
                  :test #'string=)))))

(defun %candidates-for-new-word (body)
  "Goals the words of BODY can point at.
Returns (VALUES CHOICES SEVERAL FITTED). CHOICES names a goal only when
WORD is one of its fixed terms, or the same stem of that term, or one
exact piece of its name. With no other words, CHOICES is set only when
exactly one such goal has no variables left. SEVERAL is those goals
when there are more. FITTED is the goals the other words already fit
when WORD is not a term of them. Nothing here is recorded, and FITTED
does not declare WORD."
  (let ((word (first body))
        (tail (rest body))
        (declares nil)
        (fits nil))
    (when (or (member word *ask-refusals* :test #'string=)
              (member word *ask-verbs* :test #'string=)
              (member word *ask-stops* :test #'string=)
              (some (lambda (entry)
                      (%declared-answers-p (third entry) (fourth entry) word))
                    (%named-entries)))
      (return-from %candidates-for-new-word (values nil nil nil)))
    (dolist (entry (%named-entries))
      (dolist (pattern (%entry-patterns entry))
        (let ((goal (%operator-add-goal pattern tail)))
          (when goal
            (if (or (%goal-mentions-word-p goal word)
                    (%name-mentions-word-p (third entry) word))
                (push (list (first entry) (third entry) goal) declares)
                (when tail
                  (push goal fits)))))))
    (let ((choices (remove-duplicates (nreverse declares) :test #'equal))
          (fitted (remove-duplicates (nreverse fits) :test #'equal)))
      (cond
        ((and (null tail) (rest choices))
         (values nil
                 (remove-duplicates (mapcar #'third choices) :test #'equal)
                 nil))
        (choices
         (values choices nil nil))
        (t
         (values nil nil fitted))))))

(define-condition undeclared-word (error)
  ((word :initarg :word :reader undeclared-word-word :initform nil)
   (choices :initarg :choices :reader undeclared-word-choices :initform nil))
  (:report (lambda (c stream)
             (format stream
                     "The word ~A is not declared. It would name: ~{~A~^; ~}."
                     (undeclared-word-word c)
                     (mapcar (lambda (choice)
                               (format nil "~A ~A ~{~A~^ ~}"
                                       (string-downcase (%kind-label (first choice)))
                                       (%term-label (second choice))
                                       (mapcar #'%term-label (third choice))))
                             (undeclared-word-choices c)))))
  (:documentation
   "The first word is not a name. The other words fit one or more goals.
None of them is recorded."))

(define-condition unspecific-word (error)
  ((word :initarg :word :reader unspecific-word-word :initform nil)
   (goals :initarg :goals :reader unspecific-word-goals :initform nil))
  (:report (lambda (c stream)
             (format stream
                     "The word ~A does not say which goal: ~{~A~^; ~}."
                     (unspecific-word-word c)
                     (mapcar (lambda (goal)
                               (format nil "~{~A~^ ~}"
                                       (mapcar #'%term-label goal)))
                             (unspecific-word-goals c)))))
  (:documentation
   "A word alone fits more than one goal that has no variables.
None of them is recorded, and the word is not declared."))

(defun %name-stemmed-as (word)
  "The name that is exactly the stem of WORD, or NIL.
The name itself is not stemmed, so power-one is not power-on."
  (let ((stem (%ask-stem word)))
    (when (and stem (not (string= stem word)))
      (some (lambda (entry)
              (let ((name (third entry)))
                (when (and name (string= stem (%ask-label name)))
                  name)))
            (%named-entries)))))

(define-condition not-that-name (error)
  ((word :initarg :word :reader not-that-name-word :initform nil)
   (name :initarg :name :reader not-that-name-name :initform nil))
  (:report (lambda (c stream)
             (format stream "The word ~A is not the name ~A."
                     (not-that-name-word c)
                     (%term-label (not-that-name-name c)))))
  (:documentation
   "WORD's stem is exactly a name. The name stays exact.
Nothing is recorded."))

(define-condition unrelated-word (error)
  ((word :initarg :word :reader unrelated-word-word :initform nil)
   (goals :initarg :goals :reader unrelated-word-goals :initform nil))
  (:report (lambda (c stream)
             (format stream
                     "The other words fit: ~{~A~^; ~}. The word ~A is not a name for ~:[them~;it~]."
                     (mapcar (lambda (goal)
                               (format nil "~{~A~^ ~}"
                                       (mapcar #'%term-label goal)))
                             (unrelated-word-goals c))
                     (unrelated-word-word c)
                     (null (rest (unrelated-word-goals c))))))
  (:documentation
   "The other words fit these goals. WORD is not a term of them.
None of them is recorded, and WORD is not declared."))

(defun gp-interpret (phrase)
  "Return the goal PHRASE names, or signal an error.
Does not add the goal, plan, or change facts. The first word may be an
operator name, a reaction name, a rule name, or a word that one of
them lists under :ASK. A declared word also matches the same stem, so
accendere matches accendi. Those names themselves stay exact. A fixed
term at the end of the shape may be left unsaid. A phrase that fits two
goals, is not a goal request, or whose shape no pattern achieves, is
an error."
  (unless (stringp phrase)
    (error "Ask needs a phrase."))
  (let ((tokens (%ask-tokens phrase)))
    (when (null tokens)
      (error "Ask needs a phrase."))
    (when (some (lambda (word) (member word *ask-refusals* :test #'string=))
                tokens)
      (error "The phrase is not a request for a goal."))
    (let* ((stripped (if (member (first tokens) *ask-verbs* :test #'string=)
                         (rest tokens)
                         tokens))
           (body (remove-if (lambda (word)
                              (member word *ask-stops* :test #'string=))
                            stripped)))
      (when (null body)
        (error "The phrase does not name a goal."))
      (let ((goals (remove-duplicates
                    (remove nil
                            (append
                             (mapcar (lambda (pattern)
                                       (%ground-goal pattern body))
                                     (%goal-patterns))
                             (%goals-from-operator-word body)
                             (%goals-from-reaction-word body)
                             (%goals-from-rule-word body)))
                    :test #'equal)))
        (cond
          ((null goals)
           (let ((near (%name-stemmed-as (first body))))
             (if near
                 (error 'not-that-name :word (first body) :name near)
                 (multiple-value-bind (choices several fitted)
                     (%candidates-for-new-word body)
                   (cond
                     (choices
                      (error 'undeclared-word :word (first body) :choices choices))
                     (several
                      (error 'unspecific-word :word (first body) :goals several))
                     (fitted
                      (error 'unrelated-word :word (first body) :goals fitted))
                     (t (error "This context has no goal of that shape.")))))))
          ((rest goals)
           (error 'ambiguous-goal :goals goals))
          (t (first goals)))))))

(defun gp-ask (phrase)
  "Interpret PHRASE as a goal, record it, and plan for it.
Planning does not change facts and does not execute. Returns
 (VALUES GOAL PLAN)."
  (let ((goal (gp-interpret phrase)))
    (gp-add-goal goal)
    (values goal (gp-plan :goals (list goal)))))
