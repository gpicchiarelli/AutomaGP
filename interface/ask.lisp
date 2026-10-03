;;;; interface/ask.lisp — an Italian phrase becomes a goal, or nothing
;;;;
;;;; A leading voglio, raggiungi, obiettivo, manca, fammi, ottieni, or rendi
;;;; is optional. The remaining words are a goal when an operator add, a
;;;; reaction goal, a rule consequent, or a current goal has that shape.
;;;; Punctuation that ends a word is not part of it. A fixed term at the
;;;; end may be left unsaid. If those words fit two different goals,
;;;; nothing is recorded.
;;;;
;;;; The first word may instead be the operator's name, a reaction name, or
;;;; a rule name: the predicate is then supplied by that add, goal, or
;;;; consequent. A word listed in an operator's :ASK meta works the same
;;;; way. A declared word also covers the same stem, so accendi and
;;;; accendere name one operator. The name itself is not stemmed: the
;;;; operator's own name stays exact. GP-NAME-OPERATOR declares that word
;;;; on the operator, reaction, or rule that alone has that name. A :KIND
;;;; picks one of them when the name is shared. An action that planning
;;;; lifts into an operator takes no word: the context holds no operator
;;;; to keep it on.
;;;;
;;;; An unknown first word records nothing. When the other words fit a goal
;;;; and that word is not a term of it, those goals are named and the word
;;;; is not declared. A word alone is offered only when it is a fixed term
;;;; of a goal, or the same stem of that term, or one exact piece of that
;;;; goal's name, and exactly one such goal has no variables left. When
;;;; several of those goals have no variables, the word names them and
;;;; records none. A word whose stem is exactly a name, such as power-one
;;;; for power-on, is not offered as a new word.
;;;;
;;;; The stem also drops one adverb ending in -MENTE, one superlative
;;;; ending, and one abstract ending in -EZZA, so prontamente, prontissimo,
;;;; prontezza, and pronto share a stem. A noun in -SIONE from a verb in
;;;; -ERE restores the final D, so accensione shares the stem of accendi.
;;;; A noun in -MENTO does the same, so accendimento shares that stem.
;;;; A stem keeps at least four letters. A verb with a shorter root has
;;;; none, so apri and aprire are two words, each declared on its own.
;;;;
;;;; A word in a variable's place is the symbol the facts of this context
;;;; already use under that name. A new word is interned beside the fixed
;;;; symbols of the goal, never in COMMON-LISP and never as a keyword.
;;;;
;;;; Every refusal is a PHRASE-REFUSED. Those that name candidate goals
;;;; carry a USE-VALUE restart that takes one of them. Anything that asks
;;;; to execute, delete, or run a command is refused. The phrase never runs
;;;; a plan step and never touches the shell.

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

;;; ---------------------------------------------------------------------------
;;; Refusals
;;; ---------------------------------------------------------------------------

(defun %term-label (term)
  "TERM as text, without a package prefix."
  (typecase term
    (symbol (symbol-name term))
    (string term)
    (t (princ-to-string term))))

(defun %goal-label (goal)
  "GOAL as text: its terms without package prefixes."
  (format nil "~{~A~^ ~}" (mapcar #'%term-label goal)))

(defun %kind-label (kind)
  (ecase kind
    (:operator "Operator")
    (:reaction "Reaction")
    (:rule "Rule")))

(define-condition phrase-refused (error)
  ((reason
    :initarg :reason :reader phrase-refused-reason :initform nil
    :documentation ":NO-PHRASE (not a string, or no word in it), :COMMAND
(a word asks to execute, delete, or run a command), :NO-TERMS (nothing but
an introducing verb and glue) or :UNMODELED (no goal of this context has
that shape). NIL in a subtype, whose own slots say more."))
  (:report (lambda (c stream)
             (write-string
              (case (phrase-refused-reason c)
                (:no-phrase "Ask needs a phrase.")
                (:command "The phrase is not a request for a goal.")
                (:no-terms "The phrase does not name a goal.")
                (:unmodeled "This context has no goal of that shape.")
                (t "The phrase did not become a goal."))
              stream)))
  (:documentation "GP-INTERPRET did not turn a phrase into a goal.
Nothing was recorded, declared, planned, or run."))

(define-condition ambiguous-goal (phrase-refused)
  ((goals :initarg :goals :reader ambiguous-goal-goals :initform nil))
  (:report (lambda (c stream)
             (format stream
                     "This context has more than one goal of that shape: ~{~A~^; ~}."
                     (mapcar #'%goal-label (ambiguous-goal-goals c)))))
  (:documentation
   "PHRASE fits more than one goal. None of them is recorded.
USE-VALUE takes one of GOALS."))

(define-condition undeclared-word (phrase-refused)
  ((word :initarg :word :reader undeclared-word-word :initform nil)
   (choices :initarg :choices :reader undeclared-word-choices :initform nil))
  (:report (lambda (c stream)
             (format stream
                     "The word ~A is not declared. It would name: ~{~A~^; ~}."
                     (undeclared-word-word c)
                     (mapcar (lambda (choice)
                               (format nil "~A ~A ~A"
                                       (string-downcase (%kind-label (first choice)))
                                       (%term-label (second choice))
                                       (%goal-label (third choice))))
                             (undeclared-word-choices c)))))
  (:documentation
   "The first word is not a name. The other words fit one or more goals.
Each of CHOICES is (KIND NAME GOAL). None of them is recorded.
USE-VALUE takes one of those goals; it does not declare WORD."))

(define-condition unspecific-word (phrase-refused)
  ((word :initarg :word :reader unspecific-word-word :initform nil)
   (goals :initarg :goals :reader unspecific-word-goals :initform nil))
  (:report (lambda (c stream)
             (format stream
                     "The word ~A does not say which goal: ~{~A~^; ~}."
                     (unspecific-word-word c)
                     (mapcar #'%goal-label (unspecific-word-goals c)))))
  (:documentation
   "A word alone fits more than one goal that has no variables.
None of them is recorded, and the word is not declared.
USE-VALUE takes one of GOALS."))

(define-condition not-that-name (phrase-refused)
  ((word :initarg :word :reader not-that-name-word :initform nil)
   (name :initarg :name :reader not-that-name-name :initform nil))
  (:report (lambda (c stream)
             (format stream "The word ~A is not the name ~A."
                     (not-that-name-word c)
                     (%term-label (not-that-name-name c)))))
  (:documentation
   "WORD's stem is exactly a name. The name stays exact.
Nothing is recorded."))

(define-condition unrelated-word (phrase-refused)
  ((word :initarg :word :reader unrelated-word-word :initform nil)
   (goals :initarg :goals :reader unrelated-word-goals :initform nil))
  (:report (lambda (c stream)
             (format stream
                     "The other words fit: ~{~A~^; ~}. The word ~A is not a name for ~:[them~;it~]."
                     (mapcar #'%goal-label (unrelated-word-goals c))
                     (unrelated-word-word c)
                     (null (rest (unrelated-word-goals c))))))
  (:documentation
   "The other words fit these goals. WORD is not a term of them.
None of them is recorded, and WORD is not declared.
USE-VALUE takes one of GOALS."))

(define-condition word-refused (error)
  ((word
    :initarg :word :reader word-refused-word :initform nil
    :documentation "The word that was to be declared.")
   (name
    :initarg :name :reader word-refused-name :initform nil
    :documentation "The name the word was meant for.")
   (kind
    :initarg :kind :reader word-refused-kind :initform nil
    :documentation "The kind asked for: :OPERATOR, :REACTION, :RULE, or NIL.")
   (reason
    :initarg :reason :reader word-refused-reason
    :documentation ":NOT-A-WORD (empty, several words, or a path), :RESERVED
(GP-ASK reads the word as a verb, as glue, or as a command),
:UNKNOWN-NAME, :SHARED-NAME (several things have NAME and no kind picks
one), :TAKEN (HOLDER already answers to the word) or :LIFTED-ACTION (NAME
is an action that planning lifts, not an operator of the context).")
   (holder
    :initarg :holder :reader word-refused-holder :initform nil
    :documentation "For :TAKEN, (KIND NAME) of what answers to the word."))
  (:report (lambda (c stream)
             (let ((word (word-refused-word c))
                   (name (%term-label (word-refused-name c)))
                   (kind (word-refused-kind c))
                   (holder (word-refused-holder c)))
               (ecase (word-refused-reason c)
                 (:not-a-word
                  (format stream "A name needs one word, and ~S is not one."
                          word))
                 (:reserved
                  (format stream "The word ~A cannot be a name." word))
                 (:unknown-name
                  (format stream "No ~:[operator, reaction, or rule~;~:*~A~] named ~A."
                          (and kind (string-downcase (%kind-label kind)))
                          name))
                 (:shared-name
                  (format stream "More than one thing is named ~A." name))
                 (:taken
                  (format stream "~A ~A already answers to ~A."
                          (%kind-label (first holder))
                          (%term-label (second holder))
                          word))
                 (:lifted-action
                  (format stream "~A is an action, not an operator of this ~
                                  context. Register it as an operator before ~
                                  naming it."
                          name))))))
  (:documentation "GP-NAME-OPERATOR did not declare WORD on NAME.
Nothing changed."))

;;; ---------------------------------------------------------------------------
;;; Words and terms
;;; ---------------------------------------------------------------------------

(defun %path-word-p (word)
  "True when WORD holds '.' or '/': it is a path, kept as a string."
  (or (find #\. word) (find #\/ word)))

(defun %ask-tokens (phrase)
  "Words of PHRASE in order, each without the punctuation that ends it.
A word that still holds '.' or '/' keeps its case; the rest are upper
case. Punctuation alone is not a word."
  (loop for token in (uiop:split-string
                      phrase :separator '(#\Space #\Tab #\Newline #\Return))
        for word = (string-right-trim ".,;:!?" token)
        unless (string= word "")
          collect (if (%path-word-p word) word (string-upcase word))))

(defun %fixed-symbols (patterns)
  "Symbols of PATTERNS that are neither variables nor keywords, in order."
  (loop for pattern in patterns
        when (consp pattern)
          append (remove-if-not (lambda (term)
                                  (and (symbolp term)
                                       (not (keywordp term))
                                       (not (variable-symbol-p term))))
                                pattern)))

(defun %context-patterns ()
  "Every pattern of the operators, reactions, and rules of this context."
  (append (loop for op in (gp-operators)
                append (operator-preconditions op)
                append (operator-add-list op)
                append (operator-delete-list op))
          (loop for reaction in (gp-reactions)
                append (event-reaction-goals reaction)
                when (consp (event-reaction-when reaction))
                  collect (event-reaction-when reaction)
                append (event-reaction-assert reaction))
          (loop for rule in (gp-rules)
                append (rule-if rule)
                append (rule-then rule))))

(defun %word-home (pattern)
  "The package a new word of PATTERN is interned in.
That of the first fixed symbol of PATTERN that is in neither COMMON-LISP
nor KEYWORD, else AUTOMA-GP: a predicate such as OPEN or :STATE never
makes a word a symbol of those two."
  (let ((term (find-if (lambda (term)
                         (and (symbolp term)
                              (not (variable-symbol-p term))
                              (symbol-package term)
                              (not (member (symbol-package term)
                                           (list (find-package :common-lisp)
                                                 (find-package :keyword))))))
                       pattern)))
    (if term
        (symbol-package term)
        (find-package :automa-gp))))

(defun %ask-term (raw home)
  "RAW as a term: a number, a path string, or a symbol.
The symbol is one this context already uses under that name: a fact's or
a goal's before one that only a pattern mentions, and of several the one
in HOME. A new word is interned in HOME."
  (flet ((used (patterns)
           (let ((same (remove-if-not (lambda (symbol)
                                        (string= raw (symbol-name symbol)))
                                      (%fixed-symbols patterns))))
             (or (find home same :key #'symbol-package)
                 (first same)))))
    (cond
      ((and (plusp (length raw)) (every #'digit-char-p raw))
       (parse-integer raw))
      ((%path-word-p raw)
       raw)
      (t
       (or (used (append (gp-facts) (gp-goals)))
           (used (%context-patterns))
           (intern raw home))))))

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

(defun %ground-goal (pattern tokens &optional (home (%word-home pattern)))
  "Ground PATTERN with TOKENS, or NIL when the shape does not match.
The words follow the pattern in order. A variable takes the next word,
unless that word is a fixed term later in the pattern. A fixed term may
be left unsaid only after the words run out. A term in the middle has to
be said. HOME is the package for a word that is not already in the context."
  (unless (and (consp pattern) tokens)
    (return-from %ground-goal nil))
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
    (walk pattern tokens nil)))

;;; ---------------------------------------------------------------------------
;;; Stems
;;; ---------------------------------------------------------------------------

(defun %ask-label (word)
  "WORD as an upper-case name."
  (string-upcase (%term-label word)))

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

;;; ---------------------------------------------------------------------------
;;; Names and declared words
;;; ---------------------------------------------------------------------------

(defun %declared-word (word)
  "WORD as the one upper-case word GP-ASK would read.
NIL when WORD is empty, several words, or a path."
  (let ((tokens (%ask-tokens (string word))))
    (and tokens
         (null (rest tokens))
         (not (%path-word-p (first tokens)))
         (first tokens))))

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

(defun %entry-patterns (entry)
  "Add patterns, reaction goals, or rule consequents of ENTRY."
  (ecase (first entry)
    (:operator (operator-add-list (second entry)))
    (:reaction (event-reaction-goals (second entry)))
    (:rule (rule-then (second entry)))))

(defun %declare-word (kind object token)
  "Register a copy of OBJECT with TOKEN added to its :ASK list; return it.
OBJECT itself is not changed, so a context that shares it keeps its own
words. A rule that was built past UNSAFE-RULE is built past it again."
  (flet ((meta (old)
           (%meta-put old :ask (append (getf old :ask) (list token)))))
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
                       :meta (meta (operator-meta object)))))
      (:reaction
       (gp-add-reaction
        (make-event-reaction :name (event-reaction-name object)
                             :when (event-reaction-when object)
                             :assert (event-reaction-assert object)
                             :goals (event-reaction-goals object)
                             :meta (meta (event-reaction-meta object)))))
      (:rule
       (gp-add-rule
        (handler-bind ((unsafe-rule #'continue))
          (make-rule :name (rule-name object)
                     :if (rule-if object)
                     :then (rule-then object)
                     :meta (meta (rule-meta object)))))))))

(defun %name-kind (kind)
  "KIND as :OPERATOR, :REACTION, or :RULE. NIL when KIND is omitted.
A string or a symbol of any package names the keyword spelled that way.
Anything else is an UNKNOWN-KEYWORD; its USE-VALUE restart takes a kind."
  (when kind
    (ensure-keyword-among
     (or (and (stringp kind) (find-symbol (string-upcase kind) :keyword))
         kind)
     '(:operator :reaction :rule)
     "kind")))

(defun gp-name-operator (name word &key kind)
  "Declare that WORD names the operator, reaction, or rule NAME.
NAME must pick out one of those, unless KIND says which: :OPERATOR,
:REACTION, or :RULE, as a keyword, a symbol, or a string. The same stem
counts, as with GP-ASK, when it keeps at least four letters. Declaring
the same word again keeps a single entry. Returns the object.
Signals WORD-REFUSED, and changes nothing, when WORD is not one word or is
a word GP-ASK reads as its own, when nothing or more than one thing has
NAME, when another one already answers to WORD, and when NAME is an
action that planning lifts: the context holds no operator to keep the
word on. A KIND that is none of the three is an UNKNOWN-KEYWORD."
  (let* ((token (%declared-word word))
         (label (%ask-label name))
         (wanted (%name-kind kind))
         (found (remove-if-not
                 (lambda (entry)
                   (and (third entry)
                        (string= label (%ask-label (third entry)))
                        (or (null wanted) (eq wanted (first entry)))))
                 (%named-entries))))
    (flet ((refuse (reason &optional holder)
             (error 'word-refused :reason reason :word (or token word)
                                  :name name :kind wanted :holder holder)))
      (cond
        ((null token)
         (refuse :not-a-word))
        ((null found)
         (refuse :unknown-name))
        ((rest found)
         (refuse :shared-name))
        ((or (member token *ask-refusals* :test #'string=)
             (member token *ask-verbs* :test #'string=)
             (member token *ask-stops* :test #'string=))
         (refuse :reserved))
        (t
         (destructuring-bind (kind object entry-name ask) (first found)
           (dolist (entry (%named-entries))
             (unless (and (eq kind (first entry))
                          (string= label (%ask-label (third entry))))
               (when (%declared-answers-p (third entry) (fourth entry) token)
                 (refuse :taken (list (first entry) (third entry))))))
           (cond
             ((%declared-answers-p entry-name ask token)
              object)
             ((and (eq kind :operator)
                   (not (member object (context-all-operators
                                        (ensure-current-context)))))
              (refuse :lifted-action))
             (t
              (%declare-word kind object token)))))))))

;;; ---------------------------------------------------------------------------
;;; Goals a phrase names
;;; ---------------------------------------------------------------------------

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
         (let ((rest-goal (and (rest pattern)
                               (%ground-goal (rest pattern) tail
                                             (%word-home pattern)))))
           (when rest-goal
             (cons (first pattern) rest-goal)))))))

(defun %goals-from-named-word (body)
  "Goals the first word of BODY names, grounded from the other words.
That word is the name of an operator, a reaction, or a rule, or a word
one of them declares. The name itself is not stemmed: power-on does not
match power-one. A declared word's stem counts."
  (loop for entry in (%named-entries)
        when (%declared-answers-p (third entry) (fourth entry) (first body))
          append (loop for pattern in (%entry-patterns entry)
                       for goal = (%operator-add-goal pattern (rest body))
                       when goal
                         collect goal)))

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
Returns (VALUES CHOICES SEVERAL FITTED). Each of CHOICES is
 (KIND NAME GOAL): it names a goal only when WORD is one of its fixed
terms, or the same stem of that term, or one exact piece of its name.
With no other words, CHOICES is set only when exactly one such goal has
no variables left, whatever number of operators, reactions, and rules
reach it. SEVERAL is those goals when there are more. FITTED is the goals
the other words already fit when WORD is not a term of them. Nothing here
is recorded, and FITTED does not declare WORD."
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
    (let* ((choices (remove-duplicates (nreverse declares) :test #'equal))
           (goals (remove-duplicates (mapcar #'third choices) :test #'equal))
           (fitted (remove-duplicates (nreverse fits) :test #'equal)))
      (cond
        ((and (null tail) (rest goals))
         (values nil goals nil))
        (choices
         (values choices nil nil))
        (t
         (values nil nil fitted))))))

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

(defun %refuse-among (goals type &rest initargs)
  "Signal the PHRASE-REFUSED of TYPE and INITARGS, which names GOALS.
Its USE-VALUE restart returns the one of GOALS that has the names of the
goal it is given, whatever the packages. Any other value is refused the
same way."
  (restart-case (apply #'error type initargs)
    (use-value (goal)
      :report "Use one of the goals named."
      :interactive (lambda () (read-form-prompt "Goal"))
      (or (find goal goals :test #'fact-same-names-p)
          (apply #'%refuse-among goals type initargs)))))

(defun gp-interpret (phrase)
  "Return the goal PHRASE names, or signal PHRASE-REFUSED.
Does not add the goal, plan, or change facts. The first word may be an
operator name, a reaction name, a rule name, or a word that one of
them lists under :ASK. A declared word also matches the same stem, so
accendere matches accendi. Those names themselves stay exact. A fixed
term at the end of the shape may be left unsaid.
A phrase that is not a goal request, or whose shape no pattern achieves,
is refused with a reason. A phrase that fits several goals is refused as
an AMBIGUOUS-GOAL; a first word that is no name as an UNDECLARED-WORD, an
UNSPECIFIC-WORD, an UNRELATED-WORD, or NOT-THAT-NAME. Where the refusal
names candidate goals, its USE-VALUE restart returns the one chosen."
  (flet ((refuse (reason)
           (error 'phrase-refused :reason reason)))
    (let ((tokens (and (stringp phrase) (%ask-tokens phrase))))
      (when (null tokens)
        (refuse :no-phrase))
      (when (some (lambda (word) (member word *ask-refusals* :test #'string=))
                  tokens)
        (refuse :command))
      (let* ((stripped (if (member (first tokens) *ask-verbs* :test #'string=)
                           (rest tokens)
                           tokens))
             (body (remove-if (lambda (word)
                                (member word *ask-stops* :test #'string=))
                              stripped))
             (word (first body)))
        (when (null body)
          (refuse :no-terms))
        (let ((goals (remove-duplicates
                      (append (loop for pattern in (%goal-patterns)
                                    for goal = (%ground-goal pattern body)
                                    when goal
                                      collect goal)
                              (%goals-from-named-word body))
                      :test #'equal))
              (near (%name-stemmed-as word)))
          (cond
            ((rest goals)
             (%refuse-among goals 'ambiguous-goal :goals goals))
            (goals
             (first goals))
            (near
             (error 'not-that-name :word word :name near))
            (t
             (multiple-value-bind (choices several fitted)
                 (%candidates-for-new-word body)
               (cond
                 (choices
                  (%refuse-among (mapcar #'third choices)
                                 'undeclared-word :word word :choices choices))
                 (several
                  (%refuse-among several
                                 'unspecific-word :word word :goals several))
                 (fitted
                  (%refuse-among fitted
                                 'unrelated-word :word word :goals fitted))
                 (t
                  (refuse :unmodeled)))))))))))

(defun gp-ask (phrase)
  "Interpret PHRASE as a goal, record it, and plan for it.
Planning does not change facts and does not execute. Returns
 (VALUES GOAL PLAN). A phrase GP-INTERPRET refuses records nothing. When
the interpreted goal already holds, GP-ADD-GOAL signals: the goal is not
recorded and the previous plan stays."
  (let ((goal (gp-interpret phrase)))
    (gp-add-goal goal)
    (values goal (gp-plan :goals (list goal)))))
