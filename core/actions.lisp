;;;; core/actions.lisp — abstract action model (Phase 1)
;;;;
;;;; Actions describe symbolic preconditions/effects. No OS calls, no
;;;; executor, no planner selection (Phases 3–4 / 8).

(in-package #:automa-gp)

(defclass action ()
  ((name
    :initarg :name
    :accessor action-name
    :documentation "Symbolic action name.")
   (parameters
    :initarg :parameters
    :accessor action-parameters
    :initform nil
    :documentation "Parameter list (symbols).")
   (preconditions
    :initarg :preconditions
    :accessor action-preconditions
    :initform nil
    :documentation "Facts/patterns that should hold before application.")
   (effects
    :initarg :effects
    :accessor action-effects
    :initform nil
    :documentation "Facts expected after application (symbolic).")
   (cost
    :initarg :cost
    :accessor action-cost
    :initform 1
    :documentation "Relative cost (number).")
   (risk
    :initarg :risk
    :accessor action-risk
    :initform :low
    :documentation "Risk label (:LOW :MEDIUM :HIGH or other symbol).")
   (reversible
    :initarg :reversible
    :accessor action-reversible
    :initform t
    :documentation "Whether the action is considered reversible.")
   (adapter
    :initarg :adapter
    :accessor action-adapter
    :initform nil
    :documentation "Required adapter name (symbolic); unused in Phase 1.")
   (authorization
    :initarg :authorization
    :accessor action-authorization
    :initform nil
    :documentation "Authorization token/requirement; unused in Phase 1."))
  (:documentation "Abstract symbolic action — not an external side effect."))

(defun action-p (object)
  (typep object 'action))

(defun make-action (&key name parameters preconditions effects
                      (cost 1) (risk :low) (reversible t)
                      adapter authorization)
  (unless name
    (error "make-action requires :NAME"))
  (make-instance 'action
                 :name name
                 :parameters parameters
                 :preconditions preconditions
                 :effects effects
                 :cost cost
                 :risk risk
                 :reversible reversible
                 :adapter adapter
                 :authorization authorization))

(defun register-action! (context action)
  "Register ACTION on CONTEXT under (ACTION-NAME ACTION)."
  (let ((name (action-name action)))
    (setf (context-actions context)
          (cons (cons name action)
                (remove name (context-actions context) :key #'car :test #'equal)))
    action))

(defun find-action (context name)
  "Find a registered action by NAME on CONTEXT."
  (cdr (assoc name (context-actions context) :test #'equal)))

(defun actions-of (context)
  "List of ACTION objects registered on CONTEXT."
  (mapcar #'cdr (context-actions context)))

(defun flatten-list (x)
  "Flatten proper lists for variable detection; atoms become singleton."
  (cond
    ((null x) nil)
    ((atom x) (list x))
    (t (append (flatten-list (car x)) (flatten-list (cdr x))))))

(defun pattern-has-variable-p (pattern)
  (some #'variable-symbol-p (flatten-list pattern)))

(defun action-applicable-p (context action)
  "Phase-1 check: each precondition must hold against visible facts.
Concrete facts use EQUAL; patterns with ? variables need ≥1 match.
Does not execute or simulate (Phases 3–4)."
  (let ((facts (context-all-facts context)))
    (every (lambda (pre)
             (cond
               ((null pre) t)
               ((pattern-has-variable-p pre)
                (not (null (find-facts pre facts))))
               (t (not (null (fact-p pre facts))))))
           (action-preconditions action))))
