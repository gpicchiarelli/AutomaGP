;;;; adapters/macos.lisp — OS adapter dispatch (Phase 8)
;;;;
;;;; Keeps macOS/UIOP side effects out of MEA/planner. The executor calls
;;;; INVOKE-EXTERNAL-SPEC only when *INVOKE-ADAPTERS* is true (EXECUTE).

(in-package #:automa-gp)

;;; *INVOKE-ADAPTERS* is defined in core/executor.lisp (default NIL).

(defun macos-p ()
  "True when running on macOS (UIOP)."
  (uiop:os-macosx-p))

(defun adapter-hostname ()
  "Return the system hostname string."
  (uiop:hostname))

(defun adapter-uname ()
  "Return the name of the operating system as `uname -s` prints it
(e.g. Darwin). Asks the Lisp image; no process is run."
  (software-type))

(defun adapter-open (target &key (wait nil))
  "macOS `open` TARGET (path or URL). Real side effect — use with care.
WAIT when true passes -W. TARGET is handed to `open` as one argument after
\"--\", so a target that starts with \"-\" is not read as an option.
Returns result plist; on another system :OK is NIL and nothing is run."
  (unless (macos-p)
    (return-from adapter-open
      (list :ok nil :error :not-macos :target target)))
  (multiple-value-bind (out code)
      (run-program `("open" ,@(when wait '("-W"))
                            "--" ,(%argument-string target))
                   :output :string
                   :ignore-error-status t)
    (list :ok (eql code 0) :exit-code code :output out :target target)))

(defun macos-dispatch (op args)
  "Dispatch macOS OP with ARGS plist. Returns a result plist.
Signals ACTION-FAILED for an OP this adapter does not have and for an
:OPEN without a :TARGET."
  (case op
    (:hostname (list :ok t :hostname (adapter-hostname)))
    (:uname (list :ok t :uname (adapter-uname)))
    (:macos-p (list :ok t :macos (macos-p)))
    (:open (adapter-open (%required-argument args :target :macos op)
                         :wait (getf args :wait)))
    (t (%adapter-failure "unknown macos op ~S" op))))

;;; ---------------------------------------------------------------------------
;;; External specs on operators
;;; ---------------------------------------------------------------------------

(defun substitute-external-tree (tree bindings)
  "Replace variable symbols in TREE using BINDINGS (planner bindings)."
  (cond
    ((and (symbolp tree) (variable-symbol-p tree))
     (let ((pair (lookup-binding tree bindings)))
       (if pair (cdr pair) tree)))
    ((consp tree)
     (cons (substitute-external-tree (car tree) bindings)
           (substitute-external-tree (cdr tree) bindings)))
    (t tree)))

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
                (case adapter
                  ((:filesystem :fs) (filesystem-dispatch op args))
                  ((:processes :process) (processes-dispatch op args))
                  ((:macos :os) (macos-dispatch op args))
                  (t (%adapter-failure "unknown adapter ~S" adapter)))
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
