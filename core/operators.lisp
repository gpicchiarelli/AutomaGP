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
   (meta
    :initarg :meta
    :accessor operator-meta
    :initform nil))
  (:documentation "Abstract MEA/planning operator."))

(defun operator-p (object)
  (typep object 'operator))

(defun make-operator (&key name parameters preconditions add-list delete-list
                        (cost 1) action meta)
  "Construct an OPERATOR. ADD-LIST / DELETE-LIST / PRECONDITIONS accept
a single pattern or a list of patterns."
  (unless name
    (error "make-operator requires :NAME"))
  (make-instance 'operator
                 :name name
                 :parameters parameters
                 :preconditions (normalize-pattern-list preconditions)
                 :add-list (normalize-pattern-list add-list)
                 :delete-list (normalize-pattern-list delete-list)
                 :cost cost
                 :action action
                 :meta meta))

(defun action->operator (action)
  "Lift an ACTION into an OPERATOR (effects → add-list; no delete-list)."
  (make-operator :name (action-name action)
                 :parameters (action-parameters action)
                 :preconditions (action-preconditions action)
                 :add-list (action-effects action)
                 :delete-list nil
                 :cost (action-cost action)
                 :action (action-name action)))

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
  (let ((chain nil)
        (result nil)
        (seen nil))
    (loop for c = context then (context-parent c)
          while c
          do (push c chain))
    (dolist (c (reverse chain))
      (dolist (op (context-operators c))
        (let ((n (operator-name op)))
          (unless (member n seen :test #'equal)
            (push n seen)
            (push op result)))))
    (nreverse result)))

(defun context-planning-operators (context)
  "Operators for planning: explicit operators, else actions lifted."
  (let ((ops (context-all-operators context)))
    (if ops
        ops
        (mapcar #'action->operator (actions-of context)))))

(defun operator-achieves (operator goal)
  "If OPERATOR can achieve GOAL via some add-list pattern, return bindings
(possibly *NO-BINDINGS*); otherwise return *FAIL*."
  (dolist (add (operator-add-list operator) *fail*)
    (let ((b (unify goal add *no-bindings*)))
      (unless (eq b *fail*)
        (return b)))))

(defun operators-for-goal (goal operators)
  "Operators that can achieve GOAL, as alist (OPERATOR . BINDINGS)."
  (loop for op in operators
        for b = (operator-achieves op goal)
        unless (eq b *fail*)
          collect (cons op b)))
