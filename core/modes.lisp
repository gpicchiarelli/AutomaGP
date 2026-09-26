;;;; core/modes.lisp — operational modes
;;;;
;;;; READ — observe/query
;;;; PLAN — build plans (gp-plan)
;;;; SIMULATE — apply effects to a copy (gp-simulate); no live mutation
;;;; EXECUTE — apply effects to live context facts (gp-run); no adapters yet

(in-package #:automa-gp)

(defparameter *valid-modes* '(:read :plan :simulate :execute)
  "Canonical operational modes.")

(defun mode-p (mode)
  "Return true if MODE is a known operational mode."
  (and (keywordp mode)
       (member mode *valid-modes* :test #'eq)))

(defun ensure-mode (mode)
  "Normalize MODE to a keyword in *VALID-MODES*, or signal an error."
  (let ((m (if (symbolp mode)
               (intern (symbol-name mode) :keyword)
               mode)))
    (unless (mode-p m)
      (error "Unknown AUTOMA GP mode ~S; expected one of ~S" mode *valid-modes*))
    m))

(defun mode-allows-mutation-p (mode)
  "True if MODE permits mutating live context facts."
  (eq (ensure-mode mode) :execute))
