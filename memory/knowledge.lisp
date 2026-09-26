;;;; memory/knowledge.lisp — knowledge memory (Phase 7)
;;;;
;;;; General knowledge (facts + rules) independent of the active working
;;;; context. Can be queried and merged into a context.

(in-package #:automa-gp)

(defclass knowledge-memory ()
  ((name
    :initarg :name
    :accessor knowledge-memory-name
    :initform 'default)
   (facts
    :initarg :facts
    :accessor knowledge-memory-facts
    :initform nil)
   (rules
    :initarg :rules
    :accessor knowledge-memory-rules
    :initform nil)
   (meta
    :initarg :meta
    :accessor knowledge-memory-meta
    :initform nil))
  (:documentation "General symbolic knowledge base (facts + rules)."))

(defun knowledge-memory-p (object)
  (typep object 'knowledge-memory))

(defvar *knowledge-memory* nil
  "Session knowledge memory (created on demand).")

(defun make-knowledge-memory (&key (name 'default) facts rules meta)
  (make-instance 'knowledge-memory
                 :name name
                 :facts (copy-list facts)
                 :rules (copy-list rules)
                 :meta (copy-tree meta)))

(defun ensure-knowledge-memory ()
  "Return *KNOWLEDGE-MEMORY*, creating an empty one if needed."
  (unless (knowledge-memory-p *knowledge-memory*)
    (setf *knowledge-memory* (make-knowledge-memory)))
  *knowledge-memory*)

(defun clear-knowledge-memory ()
  (setf *knowledge-memory* nil)
  t)

(defun knowledge-add-fact! (fact &optional (km (ensure-knowledge-memory)))
  "Assert FACT into knowledge memory."
  (setf (knowledge-memory-facts km)
        (add-fact! (knowledge-memory-facts km) fact))
  fact)

(defun knowledge-remove-fact! (fact &optional (km (ensure-knowledge-memory)))
  (setf (knowledge-memory-facts km)
        (remove-fact! (knowledge-memory-facts km) fact))
  (knowledge-memory-facts km))

(defun knowledge-add-rule! (rule &optional (km (ensure-knowledge-memory)))
  "Register RULE in knowledge memory (by name when present)."
  (let* ((name (rule-name rule))
         (rules (knowledge-memory-rules km)))
    (setf (knowledge-memory-rules km)
          (if name
              (cons rule (remove name rules :key #'rule-name :test #'equal))
              (append rules (list rule))))
    rule))

(defun knowledge-remove-rule! (name &optional (km (ensure-knowledge-memory)))
  (setf (knowledge-memory-rules km)
        (remove name (knowledge-memory-rules km) :key #'rule-name :test #'equal))
  (knowledge-memory-rules km))

(defun knowledge-query (pattern &key (memory (ensure-knowledge-memory))
                                  (infer nil))
  "Query PATTERN against knowledge facts (optional forward inference)."
  (let ((facts (knowledge-memory-facts memory))
        (rules (knowledge-memory-rules memory)))
    (if infer
        (multiple-value-bind (all _new)
            (forward-chain facts rules)
          (declare (ignore _new))
          (query-facts pattern all))
        (query-facts pattern facts))))

(defun knowledge-from-context (context &key (name nil))
  "Build a knowledge-memory from CONTEXT local facts and rules."
  (make-knowledge-memory :name (or name (context-name context) 'from-context)
                         :facts (copy-list (context-facts context))
                         :rules (copy-list (context-rules context))))

(defun knowledge-merge-into-context! (context &optional (km (ensure-knowledge-memory)))
  "Merge knowledge facts/rules into CONTEXT (local slots). Returns CONTEXT."
  (dolist (f (knowledge-memory-facts km))
    (setf (context-facts context) (add-fact! (context-facts context) f)))
  (dolist (r (knowledge-memory-rules km))
    (register-rule! context r))
  context)
