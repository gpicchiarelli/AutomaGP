;;;; core/modes.lisp — operational mode skeleton (Phase 1)
;;;;
;;;; Modes exist as session/context state. PLAN / SIMULATE / EXECUTE do not
;;;; yet attach planner, simulator, or executor behavior (Phases 3–4).

(in-package #:automa-gp)

(defparameter *valid-modes* '(:read :plan :simulate :execute)
  "Canonical operational modes. Phase 1 only stores/switches them.")

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
