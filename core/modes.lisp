;;;; core/modes.lisp — operational modes
;;;;
;;;; READ — observe/query
;;;; PLAN — build plans (gp-plan)
;;;; SIMULATE — apply effects to a copy (gp-simulate); no live mutation
;;;; EXECUTE — apply effects to live context facts (gp-run); an OS adapter
;;;;           runs only for an operator with :EXTERNAL meta, and only while
;;;;           *INVOKE-ADAPTERS* is true

(in-package #:automa-gp)

(defparameter *valid-modes* '(:read :plan :simulate :execute)
  "Canonical operational modes.")

;;; Keyword designators. Modes and state kinds are both written as a symbol
;;; of any package and stored as the keyword of the same name.
;;;
;;; UNKNOWN-KEYWORD is not a GP-ERROR: that hierarchy is defined in
;;; core/conditions.lisp, which loads after this file, and it describes a
;;; step that failed during a plan run, not a mistyped name.

(define-condition unknown-keyword (type-error)
  ((what
    :initarg :what
    :reader unknown-keyword-what
    :documentation "What the datum was meant to name, e.g. \"state kind\"."))
  (:report (lambda (condition stream)
             (format stream "Unknown ~A ~S; expected one of ~S"
                     (unknown-keyword-what condition)
                     (type-error-datum condition)
                     (rest (type-error-expected-type condition)))))
  (:documentation "A value does not name one of a fixed set of keywords.
TYPE-ERROR-DATUM is the value as given; TYPE-ERROR-EXPECTED-TYPE is
(MEMBER . keywords)."))

(defun ensure-keyword-among (value allowed what)
  "Return VALUE as one of the keywords in ALLOWED.
A symbol of any package names the keyword with the same name; no symbol is
interned for a name that is not already a keyword. Otherwise signal
UNKNOWN-KEYWORD, reporting WHAT was being named. The USE-VALUE restart takes
a replacement and checks it the same way."
  (let ((key (if (symbolp value)
                 (find-symbol (symbol-name value) :keyword)
                 value)))
    (if (member key allowed :test #'eq)
        key
        (restart-case
            (error 'unknown-keyword :datum value
                                    :expected-type `(member ,@allowed)
                                    :what what)
          (use-value (replacement)
            :report (lambda (stream)
                      (format stream "Supply another ~A." what))
            :interactive (lambda ()
                           (format *query-io* "~&~A, one of ~S: " what allowed)
                           (finish-output *query-io*)
                           (list (read *query-io*)))
            (ensure-keyword-among replacement allowed what))))))

(defun mode-p (mode)
  "Return true if MODE is one of the keywords in *VALID-MODES*.
A symbol that is not a keyword, such as EXECUTE, is not a mode until
ENSURE-MODE has normalized it."
  (and (keywordp mode)
       (member mode *valid-modes* :test #'eq)))

(defun ensure-mode (mode)
  "Normalize MODE to a keyword in *VALID-MODES*.
Signals UNKNOWN-KEYWORD, with a USE-VALUE restart, for anything else."
  (ensure-keyword-among mode *valid-modes* "AUTOMA GP mode"))

(defun mode-allows-mutation-p (mode)
  "True if MODE permits mutating live context facts."
  (eq (ensure-mode mode) :execute))
