;;;; memory/persistence.lisp — persistence service (Phase 7)
;;;;
;;;; Separate from the planner. Save/restore contexts, facts, rules, goals,
;;;; operators, actions, events, episodic and procedural memory as readable
;;;; s-expressions in UTF-8 .agp files, via UIOP / ANSI CL file I/O.
;;;;
;;;; A file is written whole or not at all (WRITE-SEXP-FILE) and is read as
;;;; data, never as code (READ-SEXP-FILE). What goes wrong on the way is a
;;;; PERSISTENCE-ERROR.

(in-package #:automa-gp)

(defparameter *persistence-format-version* "0.7"
  "Snapshot format version. SAVE-SNAPSHOT writes it and LOAD-SNAPSHOT
requires it.")

(defparameter *procedure-archive-format* 1
  "Procedure archive format number. SAVE-PROCEDURE-ARCHIVE writes it and
LOAD-PROCEDURE-ARCHIVE requires it.")

(defparameter *default-snapshot-directory* nil
  "Directory that relative snapshot and archive paths are placed under.
NIL, the default, leaves them relative to *DEFAULT-PATHNAME-DEFAULTS*.")

(defparameter *persistence-symbol-packages*
  '("AUTOMA-GP" "KEYWORD" "COMMON-LISP-USER")
  "Names of the packages in which READ-SEXP-FILE may create a symbol that
does not exist yet; the package current at the call is always one of them.
T allows every existing package. A symbol that already exists is read
whatever its package, and no package is ever created.")

(defparameter *persistence-symbol-limit* 10000
  "Most symbols that reading one file may create, or NIL for no limit.")

(defparameter *persistence-depth-limit* 1000
  "Deepest nesting of data that READ-SEXP-FILE reads and WRITE-SEXP-FILE
writes.")

;;; ---------------------------------------------------------------------------
;;; Conditions
;;; ---------------------------------------------------------------------------

(define-condition persistence-error (gp-error)
  ((path
    :initarg :path :reader persistence-error-path :initform nil
    :documentation "The file involved, or NIL when no file is.")
   (reason
    :initarg :reason :reader persistence-error-reason :initform nil
    :documentation "A string, or the condition that stopped the work."))
  (:report (lambda (c stream)
             (format stream "Persistence failed~@[ for ~A~]: ~A"
                     (persistence-error-path c)
                     (persistence-error-reason c))))
  (:documentation "A file or form could not be saved or loaded. The stores
of the session are as they were before the call."))

(define-condition persistence-version-error (persistence-error)
  ((found
    :initarg :found :reader persistence-version-error-found)
   (expected
    :initarg :expected :reader persistence-version-error-expected))
  (:report (lambda (c stream)
             (format stream "Persistence failed~@[ for ~A~]: the format ~
                             version is ~S, this image reads ~S"
                     (persistence-error-path c)
                     (persistence-version-error-found c)
                     (persistence-version-error-expected c))))
  (:documentation "A file carries another format version than this image
writes. The CONTINUE restart loads it anyway."))

(defvar *persistence-path* nil
  "The file being read or written; the errors signalled meanwhile name it.")

(defun %persistence-failure (control &rest arguments)
  "Signal a PERSISTENCE-ERROR whose reason is CONTROL formatted with
ARGUMENTS."
  (error 'persistence-error
         :path *persistence-path*
         :reason (apply #'format nil control arguments)))

(defun call-with-persistence-errors (path thunk)
  "Call THUNK for the file PATH. An error it signals that is not a
PERSISTENCE-ERROR already is signalled again as one, with PATH and with the
original condition as its reason."
  (let ((*persistence-path* path))
    (handler-bind ((error (lambda (c)
                            (unless (typep c 'persistence-error)
                              (error 'persistence-error :path path :reason c)))))
      (funcall thunk))))

(defmacro with-persistence-errors ((path) &body body)
  "Run BODY for the file PATH; see CALL-WITH-PERSISTENCE-ERRORS."
  `(call-with-persistence-errors ,path (lambda () ,@body)))

;;; ---------------------------------------------------------------------------
;;; Reading data
;;;
;;; A file is untrusted input, so it is not given to READ: READ runs #. forms,
;;; calls structure constructors for #S and interns every symbol it meets in
;;; whatever package the text names. The functions below read the syntax that
;;; WRITE-SEXP-FILE prints for symbolic data and nothing else: lists, symbols,
;;; integers, ratios, floats, strings, characters, simple vectors, pathnames,
;;; 'x, #'x, #:x, the #n= and #n# labels of shared structure, and ; comments.
;;; ---------------------------------------------------------------------------

(defvar *read-symbol-packages* nil
  "During a read: the packages a new symbol may be created in, or T.")

(defvar *read-symbols-created* 0
  "During a read: how many symbols the read has created so far.")

(defvar *read-labels* nil
  "During a read: alist from the n of each #n= read so far to its datum.")

(defvar *read-depth* 0
  "During a read: how many data enclose the one being read.")

(defun %whitespace-p (char)
  (member char '(#\Space #\Tab #\Newline #\Return #\Page #\Rubout)))

(defun %token-end-p (char)
  "True when CHAR ends a token under standard syntax."
  (or (%whitespace-p char) (find char "()\"';`,")))

(defun %next-char (stream)
  "Read one character of a datum that has begun."
  (or (read-char stream nil nil)
      (%persistence-failure "the file ends in the middle of a datum")))

(defun %peek-datum (stream)
  "Skip whitespace and ; comments. Returns the character that comes next
without reading it, or NIL at the end of the file."
  (loop for char = (peek-char nil stream nil nil)
        do (cond ((null char) (return nil))
                 ((%whitespace-p char) (read-char stream))
                 ((char= char #\;) (read-line stream nil))
                 (t (return char)))))

(defun %read-token (stream)
  "Read a token as the Lisp reader delimits one under standard syntax.
Returns its characters, the unescaped ones in upper case; the positions
of its unescaped colons; and whether any character was escaped."
  (let* ((colons nil)
         (escaped nil)
         (in-bars nil)
         (position 0)
         (text (with-output-to-string (out)
                 (flet ((keep (char)
                          (write-char char out)
                          (incf position)))
                   (loop for char = (peek-char nil stream nil nil)
                         while (and char (or in-bars (not (%token-end-p char))))
                         do (read-char stream)
                            (cond ((char= char #\\)
                                   (setf escaped t)
                                   (keep (%next-char stream)))
                                  ((char= char #\|)
                                   (setf escaped t
                                         in-bars (not in-bars)))
                                  (in-bars
                                   (keep char))
                                  (t
                                   (when (char= char #\:)
                                     (push position colons))
                                   (keep (char-upcase char)))))))))
    (when in-bars
      (%persistence-failure "the file ends inside |...|"))
    (values text (nreverse colons) escaped)))

(defun %number-token-p (text)
  "True when TEXT, in upper case, is written as an integer, a ratio or a
float in base ten (CLHS 2.3.1)."
  (let ((position 0)
        (end (length text)))
    (flet ((accept (characters)
             (when (and (< position end)
                        (find (char text position) characters))
               (incf position)))
           (digits ()
             (loop while (and (< position end)
                              (digit-char-p (char text position)))
                   do (incf position)
                   count t)))
      (accept "+-")
      (let ((whole (digits)))
        (if (and (plusp whole) (accept "/"))
            (and (plusp (digits)) (= position end))
            (let* ((fraction (if (accept ".") (digits) 0))
                   (exponent (and (accept "ESFDL")
                                  (progn (accept "+-") (digits)))))
              (and (= position end)
                   (or (plusp whole) (plusp fraction))
                   (or (null exponent) (plusp exponent)))))))))

(defun %read-symbol (name package-name)
  "The symbol called NAME in the package called PACKAGE-NAME. It is created
only in a package of *READ-SYMBOL-PACKAGES* and within
*PERSISTENCE-SYMBOL-LIMIT*."
  (let ((package (or (find-package package-name)
                     (%persistence-failure
                      "the symbol ~A::~A names a package that does not exist"
                      package-name name))))
    (multiple-value-bind (symbol found) (find-symbol name package)
      (cond
        (found symbol)
        ((not (or (eq *read-symbol-packages* t)
                  (member package *read-symbol-packages*)))
         (%persistence-failure
          "the file would create the symbol ~A in the package ~A, which ~
           *PERSISTENCE-SYMBOL-PACKAGES* does not allow"
          name (package-name package)))
        ((and *persistence-symbol-limit*
              (>= *read-symbols-created* *persistence-symbol-limit*))
         (%persistence-failure
          "the file would create more than ~D symbols ~
           (*PERSISTENCE-SYMBOL-LIMIT*)"
          *persistence-symbol-limit*))
        (t
         (incf *read-symbols-created*)
         (intern name package))))))

(defun %token-datum (text colons escaped)
  "The number or the symbol that a token denotes; the arguments are the
values of %READ-TOKEN."
  (destructuring-bind (&optional first second &rest more) colons
    (flet ((symbol-of (name package-name)
             (when (and (string= name "") (not escaped))
               (%persistence-failure "the token ~A lacks a symbol name" text))
             (%read-symbol name package-name)))
      (cond
        ((or more (and second (/= second (1+ first))))
         (%persistence-failure "the token ~A has too many colons" text))
        ((null first)
         (cond (escaped (symbol-of text "AUTOMA-GP"))
               ((%number-token-p text)
                (with-standard-io-syntax
                  (let ((*read-eval* nil))
                    (read-from-string text))))
               ((every (lambda (char) (char= char #\.)) text)
                (%persistence-failure "a token made only of dots"))
               (t (symbol-of text "AUTOMA-GP"))))
        ((plusp first)
         (symbol-of (subseq text (1+ (or second first)))
                    (subseq text 0 first)))
        (second
         (%persistence-failure "the token ~A has too many colons" text))
        (t (symbol-of (subseq text 1) "KEYWORD"))))))

(defun %read-string (stream)
  "The rest of a string whose opening quote has been read."
  (with-output-to-string (out)
    (loop for char = (%next-char stream)
          until (char= char #\")
          do (write-char (if (char= char #\\) (%next-char stream) char) out))))

(defun %read-character (stream)
  "The character written after #\\, which has been read."
  (let* ((first (%next-char stream))
         (next (peek-char nil stream nil nil))
         (rest (if (and next (not (%token-end-p next)))
                   (%read-token stream)
                   "")))
    (cond ((string= rest "") first)
          ((name-char (concatenate 'string (string first) rest)))
          (t (%persistence-failure "there is no character named ~A~A"
                                   first rest)))))

(defun %read-list (stream)
  "The rest of a list whose opening parenthesis has been read."
  (let* ((head (list nil))
         (tail head))
    (flet ((add (datum)
             (setf tail (setf (cdr tail) (list datum)))))
      (loop
        (case (or (%peek-datum stream)
                  (%persistence-failure "the file ends inside a list"))
          (#\)
           (read-char stream)
           (return (cdr head)))
          (#\.
           (multiple-value-bind (text colons escaped) (%read-token stream)
             (cond
               ((or escaped (string/= text "."))
                (add (%token-datum text colons escaped)))
               ((eq tail head)
                (%persistence-failure "a list begins with a dot"))
               (t
                (setf (cdr tail) (%read-datum stream))
                (unless (eql (%peek-datum stream) #\))
                  (%persistence-failure
                   "a dot is not followed by exactly one datum"))
                (read-char stream)
                (return (cdr head))))))
          (t
           (add (%read-datum stream))))))))

(defun %read-sharp (stream)
  "The datum that a # introduces; the # has been read."
  (let* ((digits (loop for char = (peek-char nil stream nil nil)
                       while (and char (digit-char-p char))
                       collect (read-char stream)))
         (label (and digits (parse-integer (coerce digits 'string))))
         (char (%next-char stream)))
    (cond
      ((and label (char= char #\=))
       (when (assoc label *read-labels*)
         (%persistence-failure "the label #~D= is defined twice" label))
       (let ((datum (%read-datum stream)))
         (push (cons label datum) *read-labels*)
         datum))
      ((and label (char= char #\#))
       (cdr (or (assoc label *read-labels*)
                (%persistence-failure
                 "#~D# comes before the end of #~D=; circular data is not read"
                 label label))))
      (label
       (%persistence-failure "#~D~C is not read as data" label char))
      (t
       (case char
         (#\\ (%read-character stream))
         (#\( (coerce (%read-list stream) 'simple-vector))
         (#\' (list 'function (%read-datum stream)))
         (#\: (make-symbol (%read-token stream)))
         ((#\P #\p)
          (let ((namestring (%read-datum stream)))
            (unless (stringp namestring)
              (%persistence-failure "#P is not followed by a string"))
            (parse-namestring namestring)))
         (t (%persistence-failure "#~C is not read as data" char)))))))

(defun %read-datum (stream)
  "Read the next datum from STREAM."
  (let ((char (or (%peek-datum stream)
                  (%persistence-failure
                   "the file ends where a datum should be")))
        (*read-depth* (1+ *read-depth*)))
    (when (> *read-depth* *persistence-depth-limit*)
      (%persistence-failure
       "the data are nested deeper than ~D levels (*PERSISTENCE-DEPTH-LIMIT*)"
       *persistence-depth-limit*))
    (case char
      (#\( (read-char stream) (%read-list stream))
      (#\" (read-char stream) (%read-string stream))
      (#\' (read-char stream) (list 'quote (%read-datum stream)))
      (#\# (read-char stream) (%read-sharp stream))
      ((#\) #\` #\,)
       (%persistence-failure "a ~C where a datum should be" char))
      (t (multiple-value-call #'%token-datum (%read-token stream))))))

(defun %read-data (stream)
  "Read the one datum that STREAM holds, as READ-SEXP-FILE describes."
  (let ((*read-symbol-packages*
          (or (eq *persistence-symbol-packages* t)
              (cons *package*
                    (remove nil (mapcar #'find-package
                                        *persistence-symbol-packages*)))))
        (*read-symbols-created* 0)
        (*read-labels* nil)
        (*read-depth* 0)
        ;; FIND-PACKAGE may consult the local nicknames of *PACKAGE*.
        (*package* (find-package :automa-gp)))
    (prog1 (%read-datum stream)
      (when (%peek-datum stream)
        (%persistence-failure "the file holds more than one datum")))))

(defun %print-data (form)
  "FORM printed as the text of a file. Signals when FORM holds an object
that has no readable print or that %READ-DATA would not read back."
  (let ((text (with-standard-io-syntax
                (let ((*package* (find-package :automa-gp))
                      (*print-pretty* t)
                      (*print-circle* t))
                  (prin1-to-string form)))))
    (handler-case (with-input-from-string (in text)
                    (%read-data in))
      (persistence-error (c)
        (%persistence-failure "the data would not load again: ~A"
                              (persistence-error-reason c))))
    text))

;;; ---------------------------------------------------------------------------
;;; Files
;;; ---------------------------------------------------------------------------

(defun ensure-snapshot-path (path &key (ensure-directory t))
  "PATH as a pathname, with the type agp when it has none. A relative PATH
is placed under *DEFAULT-SNAPSHOT-DIRECTORY* when that is set and is left
relative otherwise. Creates its directory unless ENSURE-DIRECTORY is NIL."
  (let* ((p (uiop:ensure-pathname path :want-pathname t))
         (p (if (pathname-type p)
                p
                (make-pathname :defaults p :type "agp")))
         (p (if *default-snapshot-directory*
                (uiop:merge-pathnames*
                 p (uiop:ensure-directory-pathname *default-snapshot-directory*))
                p)))
    (when ensure-directory
      (ensure-directories-exist p))
    p))

(defun write-sexp-file (path form)
  "Write FORM to PATH as one readable s-expression in UTF-8. Returns the
pathname.
FORM is printed in full first, then written to a temporary file beside PATH
that replaces PATH in one rename. A failure, an unprintable object in FORM
included, leaves a file that was there before as it was, and a reader never
finds half a file. Printer variables of the caller have no effect.
Signals PERSISTENCE-ERROR."
  (let ((p (ensure-snapshot-path path :ensure-directory nil)))
    (with-persistence-errors (p)
      (let ((text (%print-data form)))
        (ensure-directories-exist p)
        ;; Through a symbolic link, replace the file it leads to.
        (uiop:with-staging-pathname (staged (or (probe-file p) p))
          (with-open-file (out staged :direction :output
                                      :if-exists :supersede
                                      :external-format :utf-8)
            (write-string text out)
            (terpri out)))))
    p))

(defun read-sexp-file (path)
  "Read the one s-expression in the UTF-8 file PATH, as data.
Nothing in the file is evaluated and reader variables of the caller have
no effect. A symbol with no package prefix belongs to AUTOMA-GP. A symbol
that does not exist yet is created only in a package of
*PERSISTENCE-SYMBOL-PACKAGES* or in the current *PACKAGE*, and at most
*PERSISTENCE-SYMBOL-LIMIT* of them are; no package is created.
Signals PERSISTENCE-ERROR for a file that is missing, is not such data,
or breaks one of those limits."
  (let ((p (ensure-snapshot-path path :ensure-directory nil)))
    (with-persistence-errors (p)
      (with-open-file (in p :direction :input :external-format :utf-8)
        (%read-data in)))))

;;; ---------------------------------------------------------------------------
;;; Serialization (objects → readable plists and back)
;;; ---------------------------------------------------------------------------

(defun %form-plist (form tag)
  "The property list of FORM, which must be a list that begins with TAG."
  (unless (and (consp form) (eq (car form) tag))
    (%persistence-failure "expected a (~S ...) form, found ~S"
                          tag (if (consp form) (car form) form)))
  (cdr form))

(defun %check-format-version (found expected)
  "Signal a continuable PERSISTENCE-VERSION-ERROR unless FOUND is EXPECTED."
  (unless (equal found expected)
    (cerror "Load the file anyway." 'persistence-version-error
            :path *persistence-path* :found found :expected expected)))

(defun serialize-rule (rule)
  "RULE as a (:RULE ...) form."
  (list :rule
        :name (rule-name rule)
        :if (copy-tree (rule-if rule))
        :then (copy-tree (rule-then rule))
        :meta (copy-tree (rule-meta rule))))

(defun deserialize-rule (form)
  "The RULE that a (:RULE ...) form describes."
  (destructuring-bind (&key name if then meta &allow-other-keys)
      (%form-plist form :rule)
    (make-rule :name name :if if :then then :meta meta)))

(defun serialize-operator (op)
  "The operator OP as an (:OPERATOR ...) form."
  (list :operator
        :name (operator-name op)
        :parameters (copy-list (operator-parameters op))
        :preconditions (copy-tree (operator-preconditions op))
        :add-list (copy-tree (operator-add-list op))
        :delete-list (copy-tree (operator-delete-list op))
        :cost (operator-cost op)
        :action (operator-action op)
        :reversible (operator-reversible op)
        :risk (operator-risk op)
        :meta (copy-tree (operator-meta op))))

(defun deserialize-operator (form)
  "The operator that an (:OPERATOR ...) form describes."
  (destructuring-bind (&key name parameters preconditions add-list delete-list
                         (cost 1) action (reversible t) (risk :low) meta
                         &allow-other-keys)
      (%form-plist form :operator)
    (make-operator :name name
                   :parameters parameters
                   :preconditions preconditions
                   :add-list add-list
                   :delete-list delete-list
                   :cost cost
                   :action action
                   :reversible reversible
                   :risk risk
                   :meta meta)))

(defun serialize-action (action)
  "ACTION as an (:ACTION ...) form."
  (list :action
        :name (action-name action)
        :parameters (copy-list (action-parameters action))
        :preconditions (copy-tree (action-preconditions action))
        :effects (copy-tree (action-effects action))
        :cost (action-cost action)
        :risk (action-risk action)
        :reversible (action-reversible action)
        :adapter (action-adapter action)
        :authorization (action-authorization action)))

(defun deserialize-action (form)
  "The action that an (:ACTION ...) form describes."
  (destructuring-bind (&key name parameters preconditions effects
                         (cost 1) (risk :low) (reversible t)
                         adapter authorization
                         &allow-other-keys)
      (%form-plist form :action)
    (make-action :name name
                 :parameters parameters
                 :preconditions preconditions
                 :effects effects
                 :cost cost
                 :risk risk
                 :reversible reversible
                 :adapter adapter
                 :authorization authorization)))

(defun serialize-event (event)
  "EVENT as an (:EVENT ...) form."
  (list :event
        :id (event-id event)
        :type (event-type event)
        :data (copy-list (event-data event))
        :timestamp (event-timestamp event)
        :status (event-status event)
        :meta (copy-tree (event-meta event))))

(defun %event-id-number (id)
  "The n of an event id EVT-n, or NIL when ID is not written that way."
  (let ((name (and (symbolp id) (symbol-name id))))
    (and name
         (> (length name) 4)
         (string= "EVT-" name :end2 4)
         (every #'digit-char-p (subseq name 4))
         (parse-integer name :start 4))))

(defun deserialize-event (form)
  "The event that an (:EVENT ...) form describes, with the id it was saved
with. *EVENT-COUNTER* is moved past that id, so an event posted later
cannot be given it again."
  (destructuring-bind (&key id type data timestamp status meta
                         &allow-other-keys)
      (%form-plist form :event)
    (let ((number (%event-id-number id)))
      (when number
        (setf *event-counter* (max *event-counter* number))))
    (make-event :id id
                :type type
                :data data
                :timestamp timestamp
                :status (or status :pending)
                :meta meta)))

(defun serialize-event-reaction (reaction)
  "REACTION as an (:EVENT-REACTION ...) form."
  (list :event-reaction
        :name (event-reaction-name reaction)
        :when (copy-tree (event-reaction-when reaction))
        :assert (copy-tree (event-reaction-assert reaction))
        :goals (copy-tree (event-reaction-goals reaction))
        :meta (copy-tree (event-reaction-meta reaction))))

(defun deserialize-event-reaction (form)
  "The event reaction that an (:EVENT-REACTION ...) form describes."
  (destructuring-bind (&key name when assert goals meta &allow-other-keys)
      (%form-plist form :event-reaction)
    (make-event-reaction :name name
                         :when when
                         :assert assert
                         :goals goals
                         :meta meta)))

(defun serialize-context (context)
  "Serialize CONTEXT (local slots only — no parent/children links)."
  (list :context
        :name (context-name context)
        :facts (copy-list (context-facts context))
        :goals (copy-list (context-goals context))
        :rules (mapcar #'serialize-rule (context-rules context))
        :operators (mapcar #'serialize-operator (context-operators context))
        :actions (mapcar (lambda (pair)
                           (serialize-action (cdr pair)))
                         (context-actions context))
        :events (mapcar #'serialize-event (context-events context))
        :event-reactions (mapcar #'serialize-event-reaction
                                 (context-event-reactions context))
        :mode (context-mode context)
        :meta (copy-tree (context-meta context))))

(defun deserialize-context (form)
  "The context that a (:CONTEXT ...) form describes, without parent or
children. Its rules, operators, actions, events and reactions are in the
order the form lists them, which is the order SERIALIZE-CONTEXT found."
  (destructuring-bind (&key name facts goals rules operators actions
                         events event-reactions mode meta
                         &allow-other-keys)
      (%form-plist form :context)
    (make-context :name name
                  :facts facts
                  :goals goals
                  :rules (mapcar #'deserialize-rule rules)
                  :operators (mapcar #'deserialize-operator operators)
                  :actions (mapcar (lambda (action-form)
                                     (let ((action (deserialize-action action-form)))
                                       (cons (action-name action) action)))
                                   actions)
                  :events (mapcar #'deserialize-event events)
                  :event-reactions (mapcar #'deserialize-event-reaction
                                           event-reactions)
                  :mode mode
                  :meta meta)))

(defun serialize-episode (ep)
  "The episode EP as an (:EPISODE ...) form."
  (list :episode
        :id (episode-id ep)
        :kind (episode-kind ep)
        :context-name (episode-context-name ep)
        :summary (copy-tree (episode-summary ep))
        :success (episode-success ep)
        :payload (copy-tree (episode-payload ep))
        :timestamp (episode-timestamp ep)))

(defun deserialize-episode (form)
  "The episode that an (:EPISODE ...) form describes, with the id it was
saved with. *EPISODE-COUNTER* is moved past an integer id, so an episode
recorded later cannot be given it again."
  (destructuring-bind (&key id kind context-name summary success payload
                         timestamp &allow-other-keys)
      (%form-plist form :episode)
    (when (integerp id)
      (setf *episode-counter* (max *episode-counter* id)))
    (make-instance 'episode
                   :id (or id (next-episode-id))
                   :kind (or kind :event)
                   :context-name context-name
                   :summary summary
                   :success success
                   :payload payload
                   :timestamp (or timestamp (get-universal-time)))))

(defun serialize-procedure (proc)
  "The procedure PROC as a (:PROCEDURE ...) form. :SCORE is written for
the reader of the file; it is computed again from the counts on load."
  (list :procedure
        :name (procedure-name proc)
        :goals (copy-list (procedure-goals proc))
        :steps (copy-tree (procedure-steps proc))
        :operators-used (copy-list (procedure-operators-used proc))
        :initial-state (copy-list (procedure-initial-state proc))
        :success-count (procedure-success-count proc)
        :failure-count (procedure-failure-count proc)
        :last-success-at (procedure-last-success-at proc)
        :last-failure-at (procedure-last-failure-at proc)
        :score (procedure-score proc)
        :meta (copy-tree (procedure-meta proc))))

(defun deserialize-procedure (form)
  "The procedure that a (:PROCEDURE ...) form describes."
  (destructuring-bind (&key name goals steps operators-used initial-state
                         success-count failure-count
                         last-success-at last-failure-at
                         meta &allow-other-keys)
      (%form-plist form :procedure)
    (make-procedure :name name
                    :goals goals
                    :steps steps
                    :operators-used operators-used
                    :initial-state initial-state
                    :success-count (or success-count 1)
                    :failure-count (or failure-count 0)
                    :last-success-at last-success-at
                    :last-failure-at last-failure-at
                    :meta meta)))

(defun serialize-knowledge-memory (km)
  "The knowledge memory KM as a (:KNOWLEDGE ...) form."
  (list :knowledge
        :name (knowledge-memory-name km)
        :facts (copy-list (knowledge-memory-facts km))
        :rules (mapcar #'serialize-rule (knowledge-memory-rules km))
        :meta (copy-tree (knowledge-memory-meta km))))

(defun deserialize-knowledge-memory (form)
  "The knowledge memory that a (:KNOWLEDGE ...) form describes."
  (destructuring-bind (&key name facts rules meta &allow-other-keys)
      (%form-plist form :knowledge)
    (make-knowledge-memory
     :name (or name 'default)
     :facts facts
     :rules (mapcar #'deserialize-rule rules)
     :meta meta)))

(defun serialize-episodic-memory (em)
  "The episodic memory EM as an (:EPISODIC ...) form."
  (list :episodic
        :limit (episodic-memory-limit em)
        :episodes (mapcar #'serialize-episode
                          (episodic-memory-episodes em))))

(defun deserialize-episodic-memory (form)
  "The episodic memory that an (:EPISODIC ...) form describes, cut to its
limit. A form without a limit gets *EPISODIC-MEMORY-LIMIT*."
  (destructuring-bind (&key limit episodes &allow-other-keys)
      (%form-plist form :episodic)
    (make-episodic-memory
     :limit (or limit *episodic-memory-limit*)
     :episodes (mapcar #'deserialize-episode episodes))))

(defun serialize-procedural-memory (pm)
  "The procedural memory PM as a (:PROCEDURAL ...) form."
  (list :procedural
        :procedures (mapcar #'serialize-procedure
                            (procedural-memory-procedures pm))
        :meta (copy-tree (procedural-memory-meta pm))))

(defun deserialize-procedural-memory (form)
  "The procedural memory that a (:PROCEDURAL ...) form describes."
  (destructuring-bind (&key procedures meta &allow-other-keys)
      (%form-plist form :procedural)
    (make-procedural-memory
     :procedures (mapcar #'deserialize-procedure procedures)
     :meta meta)))

;;; ---------------------------------------------------------------------------
;;; Procedure archive
;;; ---------------------------------------------------------------------------

(defun save-procedure-archive (&key (path *procedure-archive-path*)
                                 (memory nil memory-p))
  "Write procedural memory to PATH as a procedure-archive s-expression.
Separate from the planner and from full session snapshots. MEMORY defaults
to the session procedural memory. Returns PATH."
  (let ((mem (if memory-p memory (ensure-procedural-memory))))
    (write-sexp-file
     path
     (list :kind :automa-gp-procedure-archive
           :format *procedure-archive-format*
           :saved-at (get-universal-time)
           :procedures (mapcar #'serialize-procedure
                               (procedural-memory-procedures mem))))
    path))

(defun %procedure-archive-read-path (path)
  "The file to read for the archive PATH: PATH, with the type agp when it
has none, if that file exists; else its sibling of type sexp, the type
archives had before agp, if that one exists; else PATH."
  (let ((p (ensure-snapshot-path path :ensure-directory nil)))
    (or (probe-file p)
        (when (equalp (pathname-type p) "agp")
          (probe-file (make-pathname :defaults p :type "sexp")))
        p)))

(defun %archive-procedures (form)
  "The procedure forms of FORM, a procedure archive of the format this
image writes."
  (unless (and (consp form)
               (eq (getf form :kind) :automa-gp-procedure-archive))
    (%persistence-failure "the file is not an AUTOMA GP procedure archive"))
  (%check-format-version (getf form :format) *procedure-archive-format*)
  (getf form :procedures))

(defun load-procedure-archive (&optional (path *procedure-archive-path*))
  "Merge procedures from PATH into session procedural memory (same name wins).
The merged procedures keep the order they have in the file. Returns the
memory store. When no file is at PATH, a sibling of type sexp is read
instead: archives had that type before agp. A PATH with no type means agp.
Signals PERSISTENCE-ERROR, and merges nothing, when the file cannot be
read as a procedure archive."
  (let ((resolved (%procedure-archive-read-path path)))
    (with-persistence-errors (resolved)
      (let* ((*loading-procedure-archive* t)
             (procedures (mapcar #'deserialize-procedure
                                 (%archive-procedures (read-sexp-file resolved))))
             (memory (ensure-procedural-memory)))
        ;; INSTALL-PROCEDURE! puts each procedure first.
        (dolist (procedure (reverse procedures))
          (install-procedure! procedure memory))
        (setf *procedure-archive-loaded* t)
        memory))))

;;; ---------------------------------------------------------------------------
;;; Suspend / restore (in-memory or file)
;;; ---------------------------------------------------------------------------

(defun suspend-context (context)
  "Return a serializable plist for CONTEXT (does not write a file)."
  (serialize-context context))

(defun resume-context (form)
  "Rebuild a CONTEXT from a suspend/serialize form."
  (deserialize-context form))

;;; ---------------------------------------------------------------------------
;;; Snapshot bundle
;;; ---------------------------------------------------------------------------

(defun make-snapshot (&key context knowledge episodic procedural
                        (meta nil))
  "Build a snapshot plist from live objects (NIL slots omitted as NIL)."
  (list :snapshot
        :format-version *persistence-format-version*
        :saved-at (get-universal-time)
        :meta (copy-tree meta)
        :context (when (context-p context) (serialize-context context))
        :knowledge (when (knowledge-memory-p knowledge)
                     (serialize-knowledge-memory knowledge))
        :episodic (when (episodic-memory-p episodic)
                    (serialize-episodic-memory episodic))
        :procedural (when (procedural-memory-p procedural)
                      (serialize-procedural-memory procedural))))

(defun save-snapshot (path &key context knowledge episodic procedural meta)
  "Persist a snapshot bundle to PATH. Returns the pathname."
  (write-sexp-file
   path
   (make-snapshot :context context
                  :knowledge knowledge
                  :episodic episodic
                  :procedural procedural
                  :meta meta)))

(defun %snapshot-plist (form)
  "The sections of FORM, a (:SNAPSHOT ...) form of the format version this
image writes."
  (let ((plist (%form-plist form :snapshot)))
    (%check-format-version (getf plist :format-version)
                           *persistence-format-version*)
    plist))

(defun load-snapshot (path)
  "Load a snapshot from PATH.
Returns a plist:
  :CONTEXT :KNOWLEDGE :EPISODIC :PROCEDURAL :FORMAT-VERSION :META :SAVED-AT
Objects are reconstituted; missing sections are NIL.
Signals PERSISTENCE-ERROR when the file cannot be read as a snapshot, and
the continuable PERSISTENCE-VERSION-ERROR when it carries another format
version than *PERSISTENCE-FORMAT-VERSION*."
  (let ((p (ensure-snapshot-path path :ensure-directory nil)))
    (with-persistence-errors (p)
      (destructuring-bind (&key format-version saved-at meta context knowledge
                             episodic procedural &allow-other-keys)
          (%snapshot-plist (read-sexp-file p))
        (list :format-version format-version
              :saved-at saved-at
              :meta meta
              :context (when context (deserialize-context context))
              :knowledge (when knowledge
                           (deserialize-knowledge-memory knowledge))
              :episodic (when episodic
                          (deserialize-episodic-memory episodic))
              :procedural (when procedural
                            (deserialize-procedural-memory procedural)))))))

(defun persist-context (context path)
  "Save CONTEXT alone to PATH. Returns pathname."
  (write-sexp-file path (serialize-context context)))

(defun restore-context (path)
  "Load a CONTEXT from PATH (a :CONTEXT file or a :SNAPSHOT with :CONTEXT).
Signals PERSISTENCE-ERROR when the file holds neither."
  (let ((p (ensure-snapshot-path path :ensure-directory nil)))
    (with-persistence-errors (p)
      (let ((form (read-sexp-file p)))
        (case (and (consp form) (car form))
          (:context (deserialize-context form))
          (:snapshot
           (deserialize-context
            (or (getf (%snapshot-plist form) :context)
                (%persistence-failure "the snapshot holds no context"))))
          (t (%persistence-failure
              "the file holds neither a context nor a snapshot")))))))

(defun apply-snapshot! (bundle &key (set-current t)
                          (set-knowledge t)
                          (set-episodic t)
                          (set-procedural t))
  "Install loaded BUNDLE into session variables. Returns BUNDLE.
Procedural memory from BUNDLE replaces the session's; the procedure
archive file is then not merged into it on its own, only by
LOAD-PROCEDURE-ARCHIVE."
  (when (and set-current (getf bundle :context))
    (setf *current-context* (getf bundle :context))
    (refresh-working-memory *current-context*))
  (when (and set-knowledge (getf bundle :knowledge))
    (setf *knowledge-memory* (getf bundle :knowledge)))
  (when (and set-episodic (getf bundle :episodic))
    (setf *episodic-memory* (getf bundle :episodic)))
  (when (and set-procedural (getf bundle :procedural))
    (setf *procedural-memory* (getf bundle :procedural)
          *procedure-archive-loaded* t))
  bundle)
