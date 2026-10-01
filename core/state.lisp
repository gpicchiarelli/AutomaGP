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
  "True if OBJECT is a STATE."
  (typep object 'state))

(defun ensure-state-kind (kind)
  "Normalize KIND to a keyword in *VALID-STATE-KINDS*.
Signals UNKNOWN-KEYWORD, with a USE-VALUE restart, for anything else."
  (ensure-keyword-among kind *valid-state-kinds* "state kind"))

(defun make-state (facts &key source (kind :current))
  "Construct a STATE from a copy of the list FACTS.
KIND is normalized by ENSURE-STATE-KIND."
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
  "Plist of fact differences between states A and B.
Keys: :FACTS-ONLY-IN-A :FACTS-ONLY-IN-B :EQUAL :KIND-A :KIND-B."
  (let ((only-a (set-difference (state-facts a) (state-facts b)
                                :test #'fact-equal))
        (only-b (set-difference (state-facts b) (state-facts a)
                                :test #'fact-equal)))
    (list :facts-only-in-a only-a
          :facts-only-in-b only-b
          :equal (and (null only-a) (null only-b))
          :kind-a (state-kind a)
          :kind-b (state-kind b))))

(defun transition-facts (facts operator bindings &key (conflict-retract t))
  "STATE A (facts) + OPERATOR effects → STATE B (new fact list).
Delegates to APPLY-OPERATOR (symbolic; no adapters). With CONFLICT-RETRACT
(the default) an added (PRED OBJ VAL) fact replaces any other (PRED OBJ *)."
  (apply-operator facts operator bindings :conflict-retract conflict-retract))

(defun transition-state (state operator bindings
                         &key (kind :simulated) source (conflict-retract t))
  "Apply OPERATOR to STATE; return a new STATE of KIND.
SOURCE defaults to that of STATE. CONFLICT-RETRACT is passed to
TRANSITION-FACTS."
  (make-state (transition-facts (state-facts state) operator bindings
                                :conflict-retract conflict-retract)
              :source (or source (state-source state))
              :kind kind))
