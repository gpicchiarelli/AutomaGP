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
  (string-trim '(#\Newline #\Return #\Space)
               (nth-value 0 (run-program '("hostname") :output :string))))

(defun adapter-uname ()
  "Return `uname -s` (e.g. Darwin)."
  (string-trim '(#\Newline #\Return #\Space)
               (nth-value 0 (run-program '("uname" "-s") :output :string))))

(defun adapter-open (target &key (wait nil))
  "macOS `open` TARGET (path or URL). Real side effect — use with care.
WAIT when true passes -W. Returns result plist."
  (unless (macos-p)
    (return-from adapter-open
      (list :ok nil :error :not-macos :target target)))
  (multiple-value-bind (out code)
      (run-program (if wait
                       (list "open" "-W" (princ-to-string target))
                       (list "open" (princ-to-string target)))
                   :output :string
                   :ignore-error-status t)
    (list :ok (eql code 0) :exit-code code :output out :target target)))

(defun macos-dispatch (op args)
  (ecase op
    (:hostname (list :ok t :hostname (adapter-hostname)))
    (:uname (list :ok t :uname (adapter-uname)))
    (:macos-p (list :ok t :macos (macos-p)))
    (:open (adapter-open (getf args :target) :wait (getf args :wait)))))

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

(defun %plan-external-entries (plan &key context operators effects-only)
  "Grounded external actions of PLAN whose effects-only flag matches.
EFFECTS-ONLY selects steps that execute will not hand to an adapter.
Does not invoke adapters and does not change facts."
  (when (plan-p plan)
    (let ((ctx (or context
                   (and (fboundp 'ensure-current-context)
                        (funcall 'ensure-current-context))))
          (want (and effects-only t)))
      (loop for step in (plan-steps plan)
            for action = (%external-action-for-step step ctx operators)
            when (and action
                      (eq (and (getf step :effects-only) t) want))
            collect action))))

(defun plan-external-actions (plan &key context operators)
  "Actions PLAN would hand to an adapter if a later execute asks for them.
Does not invoke adapters and does not change facts.
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

(defun plan-external-actions-supported-p (plan &key context operators)
  "True when every action PLAN would hand to an adapter is reachable.
Earlier steps are applied symbolically, so a precondition produced by a
previous step still counts. Does not invoke adapters and does not change
facts. A plan with no such action is supported. An effects-only step is
not handed to an adapter."
  (unless (plan-p plan)
    (return-from plan-external-actions-supported-p nil))
  (let* ((ctx (or context
                  (and (fboundp 'ensure-current-context)
                       (funcall 'ensure-current-context))))
         (facts (copy-list (if ctx (context-all-facts ctx) nil))))
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

(defun invoke-external-spec (spec bindings)
  "Run an external SPEC (:ADAPTER :OP :ARGS …) with BINDINGS substituted.
Signals ACTION-FAILED on unknown adapter or failed :OK NIL (unless :SOFT T)."
  (let* ((adapter (getf spec :adapter))
         (op (getf spec :op))
         (args (substitute-external-tree (copy-tree (getf spec :args)) bindings))
         (soft (getf spec :soft))
         (result
          (handler-case
              (ecase adapter
                ((:filesystem :fs) (filesystem-dispatch op args))
                ((:processes :process) (processes-dispatch op args))
                ((:macos :os) (macos-dispatch op args)))
            (error (e)
              (list :ok nil :error (format nil "~A" e) :adapter adapter :op op)))))
    (unless (or soft (getf result :ok))
      (error 'action-failed
             :reason (or (getf result :error)
                         (format nil "adapter ~A op ~A failed: ~S"
                                 adapter op result))))
    result))

(defun maybe-invoke-external! (operator bindings)
  "If *INVOKE-ADAPTERS* and OPERATOR has :EXTERNAL meta, invoke it.
Returns the adapter result plist, or NIL when skipped."
  (when *invoke-adapters*
    (let ((spec (operator-external-spec operator)))
      (when spec
        (invoke-external-spec spec bindings)))))

(defun with-adapters-enabled (fn)
  "Call FN with *INVOKE-ADAPTERS* bound to T."
  (let ((*invoke-adapters* t))
    (funcall fn)))
