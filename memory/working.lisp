;;;; memory/working.lisp — working memory (Phase 7)
;;;;
;;;; Immediately relevant facts/goals/mode of the current context.
;;;; A snapshot view — not durable persistence.

(in-package #:automa-gp)

(defclass working-memory ()
  ((context-name
    :initarg :context-name
    :accessor working-memory-context-name
    :initform nil)
   (facts
    :initarg :facts
    :accessor working-memory-facts
    :initform nil
    :documentation "Facts immediately relevant (visible in context).")
   (goals
    :initarg :goals
    :accessor working-memory-goals
    :initform nil)
   (mode
    :initarg :mode
    :accessor working-memory-mode
    :initform :read)
   (captured-at
    :initarg :captured-at
    :accessor working-memory-captured-at
    :initform nil))
  (:documentation "Working-memory snapshot of a context."))

(defun working-memory-p (object)
  "True when OBJECT is a WORKING-MEMORY."
  (typep object 'working-memory))

(defvar *working-memory* nil
  "Session working-memory snapshot (refreshed on demand).")

(defun capture-working-memory (context)
  "Build a WORKING-MEMORY snapshot from CONTEXT: the facts visible in it
(inherited ones included), its own goals and its mode."
  (make-instance 'working-memory
                 :context-name (context-name context)
                 :facts (copy-list (context-all-facts context))
                 :goals (copy-list (goals-of context))
                 :mode (context-mode context)
                 :captured-at (get-universal-time)))

(defun refresh-working-memory (&optional (context *current-context*))
  "Refresh *WORKING-MEMORY* from CONTEXT (default: session context).
Returns the snapshot, or NIL if CONTEXT is not a context."
  (when (context-p context)
    (setf *working-memory* (capture-working-memory context))
    *working-memory*))

(defun clear-working-memory ()
  "Clear the session working-memory snapshot."
  (setf *working-memory* nil)
  t)

(defun working-memory-state (&optional (wm *working-memory*))
  "STATE view of WORKING-MEMORY facts, or NIL."
  (when (working-memory-p wm)
    (make-state (working-memory-facts wm)
                :source (working-memory-context-name wm)
                :kind :current)))
