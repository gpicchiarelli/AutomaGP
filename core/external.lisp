;;;; core/external.lisp — what a plan would hand to an adapter
;;;;
;;;; An operator may carry an :EXTERNAL spec in its meta: the adapter, the
;;;; operation and the arguments that make a symbolic step real. This file
;;;; is the symbolic side of that. It names the actions a plan stands for,
;;;; records them on the plan, decides whether they would still run as
;;;; recorded, and, only under EXECUTE with *INVOKE-ADAPTERS*, hands a spec
;;;; to the adapter that registered under its name. It touches nothing
;;;; outside the Lisp image: adapters/ holds the operating system, and
;;;; each adapter registers itself here with REGISTER-ADAPTER, so the core
;;;; never names one.

(in-package #:automa-gp)

;;; ---------------------------------------------------------------------------
;;; Adapter registry
;;; ---------------------------------------------------------------------------

(defvar *adapters* nil
  "The adapters, as an alist (NAME . DISPATCH-FUNCTION-DESIGNATOR) in
registration order. DISPATCH is called with an operation keyword and an
argument plist and returns a result plist.")

(defun register-adapter (names dispatch)
  "Register DISPATCH, a function designator of (OP ARGS), as the adapter
known by each keyword in NAMES, a keyword or a list of them. A name that is
already registered is taken over, and moves to the end of *ADAPTERS*.
Returns NAMES as a list."
  (let ((names (if (listp names) names (list names))))
    (dolist (name names)
      (check-type name keyword "an adapter name")
      (setf *adapters* (append (remove name *adapters* :key #'car)
                               (list (cons name dispatch)))))
    names))

(defun find-adapter (name)
  "The dispatch function registered under NAME, or NIL."
  (cdr (assoc name *adapters*)))

(defun %adapter-failure (control &rest arguments)
  "Signal ACTION-FAILED with the reason CONTROL and ARGUMENTS format to.
An adapter refuses this way what it will not do: an operation it does not
have, an argument it was not given."
  (error 'action-failed :reason (apply #'format nil control arguments)))

(defun %required-argument (args key adapter op)
  "The value of KEY in ARGS, the argument plist of OP of ADAPTER.
Signals ACTION-FAILED when ARGS gives KEY no value, or gives it a variable
no step bound. An adapter does not guess an argument: a check made on
nothing would be reported as a check that was made."
  (let ((value (getf args key)))
    (cond
      ((null value)
       (%adapter-failure "~(~A~) ~S needs ~S" adapter op key))
      ((variable-symbol-p value)
       (%adapter-failure "~(~A~) ~S: ~S is the unbound variable ~S"
                         adapter op key value))
      (t value))))

;;; ---------------------------------------------------------------------------
;;; External specs on operators
;;; ---------------------------------------------------------------------------

(defun substitute-external-tree (tree bindings)
  "Replace variable symbols in TREE using BINDINGS (planner bindings).
An external spec is grounded as the core grounds an operator pattern,
with SUBSTITUTE-BINDINGS: a variable bound to another variable is followed
to its value, so the adapter gets what the symbolic step is about."
  (substitute-bindings tree bindings))

(defun operator-external-spec (operator)
  "Return the :EXTERNAL plist from OPERATOR meta, or NIL."
  (when (operator-p operator)
    (getf (operator-meta operator) :external)))

(defun %external-action-for-step (step context operators)
  "Grounded external action of STEP, or NIL when it would not be named.
Does not invoke adapters."
  (let* ((name (getf step :operator))
         (operator (lookup-operator name :context context :operators operators))
         (spec (and operator (operator-external-spec operator))))
    (when spec
      (list :operator name
            :adapter (getf spec :adapter)
            :op (getf spec :op)
            :args (or (substitute-external-tree
                       (copy-tree (getf spec :args))
                       (bindings-from-step step))
                      :null)))))

(defun %external-context (context operators)
  "The context the external actions of a plan are grounded against:
CONTEXT when the caller names one; otherwise the session context, when
there is one and the caller gave no OPERATORS. OPERATORS without a context
stand alone, so a plan made elsewhere is not read against the operators
and facts of whatever session happens to be open. No session is created."
  (or context
      (and (null operators) *current-context*)))

(defun %plan-external-entries (plan &key context operators effects-only)
  "Grounded external actions of PLAN whose effects-only flag matches.
EFFECTS-ONLY selects steps that execute will not hand to an adapter.
Does not invoke adapters and does not change facts."
  (when (plan-p plan)
    (let ((ctx (%external-context context operators))
          (want (and effects-only t)))
      (loop for step in (plan-steps plan)
            for action = (%external-action-for-step step ctx operators)
            when (and action
                      (eq (and (getf step :effects-only) t) want))
            collect action))))

(defun plan-external-actions (plan &key context operators)
  "Actions PLAN would hand to an adapter if a later execute asks for them.
Does not invoke adapters and does not change facts.
Operators are looked up in CONTEXT, then in OPERATORS. With neither, the
session context is used; OPERATORS alone are used without it.
Each item is (:operator :adapter :op :args). Args are grounded with the
step bindings. A step with no operator, or an operator with no :external
spec, is omitted. An effects-only step is omitted: its preconditions no
longer hold, so execute applies the symbolic leftovers and does not
invoke the adapter. An operator removed after the plan contributes nothing."
  (%plan-external-entries plan
                          :context context
                          :operators operators
                          :effects-only nil))

(defun plan-external-actions-withheld (plan &key context operators)
  "External actions on effects-only steps of PLAN.
Execute does not invoke them. Does not change facts.
Each item has the same shape as PLAN-EXTERNAL-ACTIONS."
  (%plan-external-entries plan
                          :context context
                          :operators operators
                          :effects-only t))

(defun remember-plan-external-actions (plan &key context operators)
  "Record the grounded external actions on PLAN.
Does not invoke adapters. The record is a copy, so a later change to an
operator does not rewrite it. Actions an effects-only step would not run
are recorded separately and do not take part in the match."
  (when (plan-p plan)
    (let ((meta (copy-list (plan-meta plan))))
      (setf (getf meta :external-actions)
            (copy-tree (plan-external-actions plan
                                              :context context
                                              :operators operators)))
      (setf (getf meta :external-actions-withheld)
            (copy-tree (plan-external-actions-withheld plan
                                                       :context context
                                                       :operators operators)))
      (setf (getf meta :external-actions-recorded) t)
      (setf (plan-meta plan) meta)))
  plan)

(defun %step-invocable-p (step context operators)
  "True when STEP would be handed to an adapter."
  (and (not (getf step :effects-only))
       (%external-action-for-step step context operators)))

(defun %advance-step-facts (facts step context operators)
  "Facts after applying STEP the way execute would, without adapters.
Returns (VALUES NEW-FACTS APPLIED-P). APPLIED-P is false when the step
cannot be applied. Does not change the live context."
  (let* ((op (lookup-operator (getf step :operator)
                              :context context
                              :operators operators))
         (stored (and (getf step :effects-only)
                      (getf step :effects-stored)))
         (b0 (bindings-from-step step)))
    (cond
      ((and (getf step :effects-only) (operator-p op))
       (values (project-operator-effects facts op b0) t))
      ((and (getf step :effects-only)
            (not (operator-p op))
            stored)
       (values (project-stored-effects facts step) t))
      ((and (getf step :stored-apply) (not (operator-p op)))
       (if (missing-stored-preconditions step facts)
           (values nil nil)
           (values (apply-stored-effects facts
                                         (getf step :adds)
                                         (getf step :deletes))
                   t)))
      ((not (operator-p op))
       (values nil nil))
      (t
       (let* ((b (extend-bindings-from-state
                  (operator-preconditions op) b0 facts))
              (missing (check-operator-preconditions facts op b)))
         (if missing
             (values nil nil)
             (values (transition-facts facts op b) t)))))))

(defun plan-external-actions-supported-p (plan &key context operators
                                                 (facts nil facts-p))
  "True when every action PLAN would hand to an adapter is reachable.
Earlier steps are applied symbolically, so a precondition produced by a
previous step still counts. Does not invoke adapters and does not change
facts. A plan with no such action is supported. An effects-only step is
not handed to an adapter.
The walk starts from FACTS when supplied: a caller that runs PLAN from
facts of its own passes them, so the answer is about that run. Otherwise
it starts from the facts visible in CONTEXT, which defaults as in
PLAN-EXTERNAL-ACTIONS, and from the initial state PLAN recorded when
there is no context at all."
  (unless (plan-p plan)
    (return-from plan-external-actions-supported-p nil))
  (let* ((ctx (%external-context context operators))
         (facts (copy-list (cond
                             (facts-p facts)
                             (ctx (context-all-facts ctx))
                             (t (plan-initial-state plan))))))
    (loop for tail on (plan-steps plan)
          for step = (car tail)
          do (multiple-value-bind (new applied)
                 (%advance-step-facts facts step ctx operators)
               (cond
                 (applied
                  (setf facts new))
                 ((or (%step-invocable-p step ctx operators)
                      (some (lambda (later)
                              (%step-invocable-p later ctx operators))
                            (cdr tail)))
                  (return-from plan-external-actions-supported-p nil))
                 (t
                  (return-from plan-external-actions-supported-p t)))))
    t))

(defun plan-external-actions-match-p (plan &key context operators)
  "True when PLAN recorded its external actions and they still ground the same way.
A plan with no record does not match. Actions recorded as withheld are not
compared: execute does not hand them to an adapter. Does not invoke adapters."
  (and (plan-p plan)
       (getf (plan-meta plan) :external-actions-recorded)
       (equal (getf (plan-meta plan) :external-actions)
              (plan-external-actions plan :context context :operators operators))))

;;; ---------------------------------------------------------------------------
;;; Invoking a spec
;;; ---------------------------------------------------------------------------

(defun invoke-external-spec (spec bindings &key operator)
  "Run an external SPEC (:ADAPTER :OP :ARGS …) with BINDINGS substituted.
Returns the result plist of the adapter. An adapter that signals an error
yields (:OK NIL :ERROR text :ADAPTER :OP) in its place.
Signals ACTION-FAILED on unknown adapter or failed :OK NIL (unless :SOFT T).
The condition names OPERATOR, the operator the spec belongs to, when given."
  (let* ((adapter (getf spec :adapter))
         (op (getf spec :op))
         (args (substitute-external-tree (copy-tree (getf spec :args)) bindings))
         (soft (getf spec :soft))
         (result
          (flet ((failure (text)
                   (list :ok nil :error text :adapter adapter :op op)))
            (handler-case
                (let ((dispatch (find-adapter adapter)))
                  (unless dispatch
                    (%adapter-failure "unknown adapter ~S" adapter))
                  (funcall dispatch op args))
              (action-failed (c)
                (failure (action-failed-reason c)))
              (error (e)
                (failure (princ-to-string e)))))))
    (unless (or soft (getf result :ok))
      (error 'action-failed
             :reason (or (getf result :error)
                         (format nil "adapter ~A op ~A failed: ~S"
                                 adapter op result))
             :operator operator
             :bindings bindings
             :mode :execute))
    result))

(defun maybe-invoke-external! (operator bindings)
  "If *INVOKE-ADAPTERS* and OPERATOR has :EXTERNAL meta, invoke it.
Returns the adapter result plist, or NIL when skipped."
  (when *invoke-adapters*
    (let ((spec (operator-external-spec operator)))
      (when spec
        (invoke-external-spec spec bindings :operator operator)))))

(defun with-adapters-enabled (fn)
  "Call FN with *INVOKE-ADAPTERS* bound to T."
  (let ((*invoke-adapters* t))
    (funcall fn)))
