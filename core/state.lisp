;;;; core/state.lisp — explicit state representation & transition (Phases 1, 4)
;;;;
;;;; States distinguish CURRENT / SIMULATED / EXPECTED / OBSERVED.
;;;; Transition: STATE A + operator effects → STATE B (symbolic facts only).

(in-package #:automa-gp)

(defparameter *valid-state-kinds* '(:current :simulated :expected :observed)
  "Kinds of explicit state snapshots.")

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
    :documentation "Optional context name or label this state was taken from.")
   (kind
    :initarg :kind
    :accessor state-kind
    :initform :current
    :documentation "One of *VALID-STATE-KINDS*."))
  (:documentation "Explicit symbolic state snapshot."))

(defun state-p (object)
  (typep object 'state))

(defun ensure-state-kind (kind)
  (let ((k (if (symbolp kind)
               (intern (symbol-name kind) :keyword)
               kind)))
    (unless (member k *valid-state-kinds* :test #'eq)
      (error "Unknown state kind ~S; expected one of ~S" kind *valid-state-kinds*))
    k))

(defun make-state (facts &key source (kind :current))
  "Construct a STATE from FACTS."
  (make-instance 'state
                 :facts (copy-list facts)
                 :source source
                 :kind (ensure-state-kind kind)))

(defun state-from-context (context &key (kind :current))
  "Build a STATE from facts visible in CONTEXT."
  (make-state (context-all-facts context)
              :source (context-name context)
              :kind kind))

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
        :equal (state-equal a b)
        :kind-a (state-kind a)
        :kind-b (state-kind b)))

(defun transition-facts (facts operator bindings &key (conflict-retract t))
  "STATE A (facts) + OPERATOR effects → STATE B (new fact list).
Delegates to APPLY-OPERATOR (symbolic; no adapters)."
  (apply-operator facts operator bindings :conflict-retract conflict-retract))

(defun transition-state (state operator bindings &key (kind :simulated) source)
  "Apply OPERATOR to STATE; return a new STATE of KIND."
  (make-state (transition-facts (state-facts state) operator bindings)
              :source (or source (state-source state))
              :kind kind))
