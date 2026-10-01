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
    :documentation "Required adapter name (symbolic). Kept and persisted;
neither the planner nor the executor reads it.")
   (authorization
    :initarg :authorization
    :accessor action-authorization
    :initform nil
    :documentation "Authorization token/requirement. Kept and persisted;
neither the planner nor the executor reads it."))
  (:documentation "Abstract symbolic action — not an external side effect."))

(defun action-p (object)
  "True if OBJECT is an ACTION."
  (typep object 'action))

(defun make-action (&key name parameters preconditions effects
                      (cost 1) (risk :low) (reversible t)
                      adapter authorization)
  "Construct an ACTION. NAME is required: without one the TYPE-ERROR of
CHECK-TYPE is signaled, and its STORE-VALUE restart takes a name."
  (check-type name (not null) "an action name")
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

(defun action-applicable-p (context action)
  "True if the preconditions of ACTION hold together in the facts visible in
CONTEXT: one choice of bindings must satisfy every pattern, so a variable
shared by two preconditions names the same thing in both. NIL preconditions
are ignored. Does not execute or simulate (Phases 3–4)."
  (and (match-all (remove nil (action-preconditions action))
                  (context-all-facts context))
       t))
