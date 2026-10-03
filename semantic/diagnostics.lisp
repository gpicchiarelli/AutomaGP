;;;; semantic/diagnostics.lisp — what went wrong, with where and why
;;;;
;;;; PROMPT-SEMANTICA §28: no silent semantic loss. A construct the system
;;;; cannot handle is never dropped on the floor. It is recorded as a
;;;; DIAGNOSTIC in an active collector, or it is signalled as a typed
;;;; condition that the caller has to decide about, with a restart that
;;;; says so in words.

(in-package #:automa-gp/semantic)

;;; ---------------------------------------------------------------------------
;;; Conditions
;;; ---------------------------------------------------------------------------

(defun %standards-error-text (condition)
  "The report of a STANDARDS-ERROR: [code] message (standard@version,
construct) at source:location. Suggestion: text. Each part appears only when
it is known; nothing is read from a part that is not there."
  (with-output-to-string (out)
    (let ((code (standards-error-code condition))
          (standard (standards-error-standard condition))
          (version (standards-error-version condition))
          (construct (standards-error-construct condition))
          (source (standards-error-source condition))
          (location (standards-error-location condition))
          (suggestion (standards-error-suggestion condition)))
      (when code
        (format out "[~(~A~)] " code))
      (write-string (or (standards-error-message condition)
                        "the standards platform could not go on")
                    out)
      (let ((about (remove nil
                           (list (and standard
                                      (if version
                                          (format nil "~A@~A" standard version)
                                          (princ-to-string standard)))
                                 construct))))
        (when about
          (format out " (~{~A~^, ~})" about)))
      (when (or source location)
        (format out " at ~{~A~^:~}" (remove nil (list source location))))
      (when suggestion
        (format out ". Suggestion: ~A" suggestion)))))

(define-condition standards-error (gp-error)
  ((code
    :initarg :code :initform nil :reader standards-error-code
    :documentation "A keyword that names this kind of failure.")
   (message
    :initarg :message :initform nil :reader standards-error-message
    :documentation "What happened, in a sentence.")
   (source
    :initarg :source :initform nil :reader standards-error-source
    :documentation "The document, IRI or file the failure was found in.")
   (location
    :initarg :location :initform nil :reader standards-error-location
    :documentation "Where in SOURCE: a line, an offset, a path, a section.")
   (standard
    :initarg :standard :initform nil :reader standards-error-standard
    :documentation "The identifier of the standard concerned.")
   (version
    :initarg :version :initform nil :reader standards-error-version
    :documentation "The version of that standard.")
   (construct
    :initarg :construct :initform nil :reader standards-error-construct
    :documentation "The construct of the standard concerned.")
   (suggestion
    :initarg :suggestion :initform nil :reader standards-error-suggestion
    :documentation "What to do about it."))
  (:report (lambda (condition stream)
             (write-string (%standards-error-text condition) stream)))
  (:documentation "Base of every failure of the standards platform. Carries
what PROMPT-SEMANTICA §28 asks of an error: a code, a message, the source and
location, the standard, its version, the construct, and a suggestion; each is
NIL when it is not known."))

(define-condition standard-parse-error (standards-error)
  ()
  (:default-initargs :code :parse-error)
  (:documentation "A document is not in the syntax its standard defines."))

(define-condition standard-resolution-error (standards-error)
  ()
  (:default-initargs :code :resolution-error)
  (:documentation "A name, IRI or designator cannot be resolved to one thing:
it names nothing, or it names more than one."))

(define-condition standard-dependency-error (standards-error)
  ()
  (:default-initargs :code :dependency-error)
  (:documentation "The dependencies of a standard or an ontology cannot be
closed."))

(define-condition dependency-cycle (standard-dependency-error)
  ((path
    :initarg :path :initform nil :reader dependency-cycle-path
    :documentation "The nodes of the cycle, the first one repeated last."))
  (:default-initargs :code :dependency-cycle)
  (:report (lambda (condition stream)
             (format stream "[dependency-cycle] ~{~A~^ -> ~}"
                     (dependency-cycle-path condition))))
  (:documentation "A dependency graph has a cycle, which no order of loading
resolves."))

(define-condition dependency-missing (standard-dependency-error)
  ((name
    :initarg :name :initform nil :reader dependency-missing-name
    :documentation "What was asked for and not found.")
   (required-by
    :initarg :required-by :initform nil :reader dependency-missing-required-by
    :documentation "What asked for it."))
  (:default-initargs :code :dependency-missing)
  (:report (lambda (condition stream)
             (format stream "[dependency-missing] ~A~@[ is required by ~A~] ~
                             but is not registered"
                     (dependency-missing-name condition)
                     (dependency-missing-required-by condition))))
  (:documentation "A dependency names something that is not there."))

(define-condition standard-semantic-error (standards-error)
  ()
  (:default-initargs :code :semantic-error)
  (:documentation "A document is well formed and means something its standard
does not allow."))

(define-condition unsupported-construct (standards-error)
  ()
  (:default-initargs :code :unsupported-construct)
  (:documentation "A construct of a standard is not implemented. It is not
ignored: this condition is signalled, with the restart
:CONTINUE-UNSUPPORTED, unless *UNSUPPORTED-POLICY* is :RECORD and a collector
is active."))

(define-condition implementation-error (standards-error)
  ()
  (:default-initargs :code :implementation-error)
  (:documentation "The implementation of a standard failed on its own: a
defect in the platform, not in the input."))

(define-condition conformance-failure (standards-error)
  ()
  (:default-initargs :code :conformance-failure)
  (:documentation "An implementation does not conform: a test of the
standard's suite failed."))

(define-condition standard-runtime-error (standards-error)
  ()
  (:default-initargs :code :runtime-error)
  (:documentation "A failure while executing an implemented standard."))

;;; ---------------------------------------------------------------------------
;;; Diagnostics
;;; ---------------------------------------------------------------------------

(defstruct (diagnostic (:constructor %make-diagnostic) (:predicate nil))
  "One finding about an input: how serious, what, where, and what the
platform can say about the construct it concerns."
  (severity :warning :type (member :error :warning :info) :read-only t)
  (code nil :read-only t)
  (message nil :read-only t)
  (source nil :read-only t)
  (location nil :read-only t)
  (standard nil :read-only t)
  (version nil :read-only t)
  (construct nil :read-only t)
  (support nil :type (member nil :implemented :partially-implemented
                             :not-implemented :invalid)
           :read-only t)
  (suggestion nil :read-only t))

(defun diagnostic-p (object)
  "True if OBJECT is a DIAGNOSTIC."
  (typep object (quote diagnostic)))

(defun make-diagnostic (&rest initargs &key severity code message source
                                         location standard version construct
                                         support suggestion)
  "A DIAGNOSTIC. SEVERITY is :ERROR, :WARNING or :INFO (default :WARNING).
SUPPORT, when the diagnostic is about a construct, is one of :IMPLEMENTED,
:PARTIALLY-IMPLEMENTED, :NOT-IMPLEMENTED and :INVALID, the four answers
PROMPT-SEMANTICA §2 asks for."
  (declare (ignore severity code message source location standard version
                   construct support suggestion))
  (apply #'%make-diagnostic initargs))

(defvar *diagnostics* nil
  "NIL, or the cell that CALL-COLLECTING-DIAGNOSTICS fills: a list in
reverse order of arrival.")

(defun call-collecting-diagnostics (function)
  "Call FUNCTION with a collector active. Returns (VALUES RESULT
DIAGNOSTICS): the first value of FUNCTION and the list of diagnostics noted
meanwhile, in the order they were noted."
  (let* ((cell (list :collector))
         (*diagnostics* cell)
         (result (funcall function)))
    (values result (reverse (rest cell)))))

(defmacro collecting-diagnostics (&body body)
  "Run BODY with a collector active; see CALL-COLLECTING-DIAGNOSTICS."
  `(call-collecting-diagnostics (lambda () ,@body)))

(defun note-diagnostic (&rest initargs)
  "Make a diagnostic from INITARGS (see MAKE-DIAGNOSTIC), add it to the
active collector and return it. Without a collector the diagnostic would be
lost, which is not allowed: an :ERROR or :WARNING is then signalled as a
STANDARDS-ERROR, and an :INFO is returned and dropped."
  (let ((diagnostic (apply #'make-diagnostic initargs)))
    (cond
      (*diagnostics*
       (push diagnostic (rest *diagnostics*)))
      ((member (diagnostic-severity diagnostic) '(:error :warning))
       (error 'standards-error
              :code (or (diagnostic-code diagnostic) :uncollected-diagnostic)
              :message (diagnostic-message diagnostic)
              :source (diagnostic-source diagnostic)
              :location (diagnostic-location diagnostic)
              :standard (diagnostic-standard diagnostic)
              :version (diagnostic-version diagnostic)
              :construct (diagnostic-construct diagnostic)
              :suggestion (diagnostic-suggestion diagnostic))))
    diagnostic))

(defvar *unsupported-policy* :signal
  "What REPORT-UNSUPPORTED does: :SIGNAL (the default) signals
UNSUPPORTED-CONSTRUCT; :RECORD records the construct and goes on, which is
meant for a run whose report is the result. :RECORD without an active
collector signals all the same.")

(defun report-unsupported (construct &key standard version source location
                                       suggestion)
  "CONSTRUCT of STANDARD is not implemented. Records a :NOT-IMPLEMENTED
diagnostic in the active collector, then signals UNSUPPORTED-CONSTRUCT, with
the restart :CONTINUE-UNSUPPORTED to go on, unless *UNSUPPORTED-POLICY* is
:RECORD and a collector is active. Either the construct is in a report or a
caller has chosen to go on without it; it is never silently ignored.
Returns the diagnostic."
  (let ((diagnostic (make-diagnostic
                     :severity :error :code :unsupported-construct
                     :message (format nil "~A is not implemented" construct)
                     :source source :location location
                     :standard standard :version version
                     :construct construct :support :not-implemented
                     :suggestion suggestion)))
    (when *diagnostics*
      (push diagnostic (rest *diagnostics*)))
    (unless (and *diagnostics* (eq *unsupported-policy* :record))
      (restart-case
          (error 'unsupported-construct
                 :message (diagnostic-message diagnostic)
                 :source source :location location
                 :standard standard :version version
                 :construct construct :suggestion suggestion)
        (:continue-unsupported ()
          :report "Go on without this construct; the diagnostic stays on record."
          ;; Without a collector the diagnostic would be lost, so it is
          ;; returned for the caller to keep.
          nil)))
    diagnostic))
