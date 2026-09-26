;;;; core/context.lisp — context core (Phase 1)
;;;;
;;;; A context is the fundamental unit GP works inside. Hierarchical
;;;; parent/child contexts support inherited fact lookup (local shadows parent).

(in-package #:automa-gp)

(defclass context ()
  ((name
    :initarg :name
    :accessor context-name
    :initform nil
    :documentation "Symbolic name of this context.")
   (parent
    :initarg :parent
    :accessor context-parent
    :initform nil
    :documentation "Optional parent context for hierarchical lookup.")
   (children
    :initarg :children
    :accessor context-children
    :initform nil
    :documentation "List of direct child contexts.")
   (facts
    :initarg :facts
    :accessor context-facts
    :initform nil
    :documentation "Local symbolic facts (lists).")
   (goals
    :initarg :goals
    :accessor context-goals
    :initform nil
    :documentation "Goals associated with this context.")
   (actions
    :initarg :actions
    :accessor context-actions
    :initform nil
    :documentation "Action registry for this context (alist name → action).")
   (rules
    :initarg :rules
    :accessor context-rules
    :initform nil
    :documentation "Local symbolic rules (Phase 2).")
   (mode
    :initarg :mode
    :accessor context-mode
    :initform :read
    :documentation "Operational mode skeleton (:READ :PLAN :SIMULATE :EXECUTE).")
   (meta
    :initarg :meta
    :accessor context-meta
    :initform nil
    :documentation "Arbitrary metadata plist/alist."))
  (:documentation "AUTOMA GP context — symbolic work unit."))

(defun context-p (object)
  (typep object 'context))

(defun make-context (&key name parent facts goals actions rules mode meta children)
  "Construct a CONTEXT. MODE defaults to :READ."
  (make-instance 'context
                 :name name
                 :parent parent
                 :children (copy-list children)
                 :facts (copy-list facts)
                 :goals (copy-list goals)
                 :actions (copy-tree actions)
                 :rules (copy-list rules)
                 :mode (if mode (ensure-mode mode) :read)
                 :meta (copy-tree meta)))

(defun create-context (&key name parent facts goals actions rules mode meta)
  "Create a context and, if PARENT is given, register it as a child."
  (let ((ctx (make-context :name name
                           :parent parent
                           :facts facts
                           :goals goals
                           :actions actions
                           :rules rules
                           :mode mode
                           :meta meta)))
    (when parent
      (context-add-child! parent ctx))
    ctx))

(defun context-add-child! (parent child)
  "Register CHILD under PARENT (mutates both)."
  (setf (context-parent child) parent)
  (pushnew child (context-children parent) :test #'eq)
  child)

(defun facts-of (context)
  "Local facts on CONTEXT (no inheritance)."
  (context-facts context))

(defun context-all-facts (context)
  "Facts visible in CONTEXT along the parent chain.
Ancestors contribute first; a local fact EQUAL to an ancestor fact replaces it."
  (let ((chain nil)
        (result nil))
    (loop for c = context then (context-parent c)
          while c
          do (push c chain))
    (dolist (c chain)
      (dolist (f (context-facts c))
        (setf result (remove f result :test #'fact-equal))
        (setf result (append result (list f)))))
    result))

(defun context-query (context pattern)
  "Find facts visible in CONTEXT matching PATTERN (no rule inference).
For inference, see QUERY / GP-QUERY."
  (find-facts pattern (context-all-facts context)))

(defun context-modify! (context &key name mode meta
                                 (facts nil facts-p)
                                 (goals nil goals-p)
                                 (actions nil actions-p)
                                 (rules nil rules-p))
  "Destructively modify CONTEXT slots when supplied."
  (when name (setf (context-name context) name))
  (when mode (setf (context-mode context) (ensure-mode mode)))
  (when meta (setf (context-meta context) meta))
  (when facts-p (setf (context-facts context) (copy-list facts)))
  (when goals-p (setf (context-goals context) (copy-list goals)))
  (when actions-p (setf (context-actions context) (copy-tree actions)))
  (when rules-p (setf (context-rules context) (copy-list rules)))
  context)

(defun clone-context (context &key name as-child)
  "Deep-enough copy of CONTEXT (facts/goals/actions/rules/meta lists copied).
Parent link is cleared unless AS-CHILD is true (then registered under original)."
  (let ((copy (make-context :name (or name (context-name context))
                            :parent nil
                            :facts (copy-list (context-facts context))
                            :goals (copy-list (context-goals context))
                            :actions (copy-tree (context-actions context))
                            :rules (copy-list (context-rules context))
                            :mode (context-mode context)
                            :meta (copy-tree (context-meta context))
                            :children nil)))
    (when as-child
      (context-add-child! context copy))
    copy))

(defun compare-contexts (a b)
  "Return a plist describing differences between contexts A and B.
Keys: :NAME-EQUAL :FACTS-ONLY-IN-A :FACTS-ONLY-IN-B :GOALS-ONLY-IN-A
:GOALS-ONLY-IN-B :MODE-EQUAL."
  (let* ((fa (context-all-facts a))
         (fb (context-all-facts b))
         (ga (context-goals a))
         (gb (context-goals b)))
    (list :name-equal (equal (context-name a) (context-name b))
          :mode-equal (eq (context-mode a) (context-mode b))
          :facts-only-in-a (set-difference fa fb :test #'fact-equal)
          :facts-only-in-b (set-difference fb fa :test #'fact-equal)
          :goals-only-in-a (set-difference ga gb :test #'equal)
          :goals-only-in-b (set-difference gb ga :test #'equal))))
