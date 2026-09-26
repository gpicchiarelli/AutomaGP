;;;; core/state.lisp — explicit state representation (Phase 1)
;;;;
;;;; State is a snapshot of the facts visible in a context. Applying actions
;;;; to transition state is Phase 4; here we only build and compare states.

(in-package #:automa-gp)

(defclass state ()
  ((facts
    :initarg :facts
    :accessor state-facts
    :initform nil
    :documentation "Ordered list of facts comprising this state.")
   (source
    :initarg :source
    :accessor state-source
    :initform nil
    :documentation "Optional context name or label this state was taken from."))
  (:documentation "Explicit symbolic state snapshot."))

(defun state-p (object)
  (typep object 'state))

(defun state-from-context (context)
  "Build a STATE from facts visible in CONTEXT."
  (make-instance 'state
                 :facts (copy-list (context-all-facts context))
                 :source (context-name context)))

(defun state-equal (a b)
  "True if A and B contain the same facts (order-insensitive)."
  (and (null (set-difference (state-facts a) (state-facts b) :test #'fact-equal))
       (null (set-difference (state-facts b) (state-facts a) :test #'fact-equal))))

(defun compare-states (a b)
  "Plist of fact differences between states A and B."
  (list :facts-only-in-a (set-difference (state-facts a) (state-facts b)
                                         :test #'fact-equal)
        :facts-only-in-b (set-difference (state-facts b) (state-facts a)
                                         :test #'fact-equal)
        :equal (state-equal a b)))
