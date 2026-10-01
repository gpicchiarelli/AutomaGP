;;;; core/operators.lisp — abstract planning operators (Phase 3)
;;;;
;;;; Operators are what the planner/MEA reason about. They must not embed
;;;; macOS/filesystem calls — adapters come later (Phase 8).
;;;; Actions (Phase 1) can be lifted into operators via ACTION->OPERATOR.

(in-package #:automa-gp)

(defclass operator ()
  ((name
    :initarg :name
    :accessor operator-name
    :documentation "Symbolic operator name.")
   (parameters
    :initarg :parameters
    :accessor operator-parameters
    :initform nil
    :documentation "Parameter list (symbols), optional documentation.")
   (preconditions
    :initarg :preconditions
    :accessor operator-preconditions
    :initform nil
    :documentation "Fact patterns that must hold before application.")
   (add-list
    :initarg :add-list
    :accessor operator-add-list
    :initform nil
    :documentation "Fact patterns asserted by the operator.")
   (delete-list
    :initarg :delete-list
    :accessor operator-delete-list
    :initform nil
    :documentation "Fact patterns retracted by the operator.")
   (cost
    :initarg :cost
    :accessor operator-cost
    :initform 1
    :documentation "Relative planning cost.")
   (action
    :initarg :action
    :accessor operator-action
    :initform nil
    :documentation "Optional linked ACTION name for later execution.")
   (reversible
    :initarg :reversible
    :accessor operator-reversible
    :initform t
    :documentation "Whether the operator is considered reversible.")
   (risk
    :initarg :risk
    :accessor operator-risk
    :initform :low
    :documentation "Risk label (:LOW :MEDIUM :HIGH …).")
   (meta
    :initarg :meta
    :accessor operator-meta
    :initform nil
    :documentation "Metadata plist, e.g. :INDUCED :EXAMPLES :ASK :EXTERNAL."))
  (:documentation "Abstract MEA/planning operator."))

(defun operator-p (object)
  "True if OBJECT is an OPERATOR."
  (typep object 'operator))

(defun make-operator (&key name parameters preconditions add-list delete-list
                        (cost 1) action (reversible t) (risk :low) meta)
  "Construct an OPERATOR. ADD-LIST / DELETE-LIST / PRECONDITIONS accept
a single pattern or a list of patterns. NAME is required: without one a
TYPE-ERROR is signalled, and its STORE-VALUE restart takes the name."
  (check-type name (not null) "an operator name")
  (make-instance 'operator
                 :name name
                 :parameters parameters
                 :preconditions (normalize-pattern-list preconditions)
                 :add-list (normalize-pattern-list add-list)
                 :delete-list (normalize-pattern-list delete-list)
                 :cost cost
                 :action action
                 :reversible reversible
                 :risk risk
                 :meta meta))

(defun action->operator (action)
  "Lift an ACTION into an OPERATOR (effects → add-list; no delete-list)."
  (make-operator :name (action-name action)
                 :parameters (action-parameters action)
                 :preconditions (action-preconditions action)
                 :add-list (action-effects action)
                 :delete-list nil
                 :cost (action-cost action)
                 :action (action-name action)
                 :reversible (action-reversible action)
                 :risk (action-risk action)))

(defun find-operator (context name)
  "Find operator named NAME among planning operators for CONTEXT.
While CONTEXT has no operator of its own or inherited, those are its
actions lifted by ACTION->OPERATOR: the result is then a fresh object on
every call, and changing it changes nothing in CONTEXT."
  (find name (context-planning-operators context)
        :key #'operator-name :test #'equal))

(defun register-operator! (context operator)
  "Register OPERATOR on CONTEXT by name."
  (let ((name (operator-name operator)))
    (setf (context-operators context)
          (cons operator
                (remove name (context-operators context)
                        :key #'operator-name :test #'equal)))
    operator))

(defun remove-operator! (context name)
  "Remove operator named NAME from CONTEXT."
  (setf (context-operators context)
        (remove name (context-operators context)
                :key #'operator-name :test #'equal))
  (context-operators context))

(defun operators-of (context)
  "Local operators on CONTEXT."
  (context-operators context))

(defun context-all-operators (context)
  "Operators visible along the parent chain (local name wins)."
  (visible-by-name context #'context-operators #'operator-name))

(defun context-planning-operators (context)
  "Operators for planning: explicit operators, else actions lifted."
  (or (context-all-operators context)
      (mapcar #'action->operator (actions-of context))))

(defun %achieving-bindings (operator goal)
  "The distinct binding sets under which an add-list pattern of OPERATOR
unifies with GOAL, in add-list order."
  (remove-duplicates
   (loop for add in (operator-add-list operator)
         for b = (unify goal add *no-bindings*)
         unless (fail-p b)
           collect b)
   :test #'equal :from-end t))

(defun operator-achieves (operator goal)
  "If OPERATOR can achieve GOAL via some add-list pattern, return the
bindings of the first such pattern (possibly *NO-BINDINGS*); otherwise
return *FAIL*. OPERATORS-FOR-GOAL gives every such pattern."
  (let ((ways (%achieving-bindings operator goal)))
    (if ways (first ways) *fail*)))

(defun operators-for-goal (goal operators)
  "Every way OPERATORS can achieve GOAL, as a list of (OPERATOR . BINDINGS).
An operator appears once for each add-list pattern that unifies with GOAL
under different bindings, so a planner can try each of them."
  (loop for op in operators
        nconc (loop for b in (%achieving-bindings op goal)
                    collect (cons op b))))
