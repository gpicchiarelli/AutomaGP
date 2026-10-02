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
  "True when OBJECT is a KNOWLEDGE-MEMORY."
  (typep object 'knowledge-memory))

(defvar *knowledge-memory* nil
  "Session knowledge memory (created on demand).")

(defun make-knowledge-memory (&key (name 'default) facts rules meta)
  "A KNOWLEDGE-MEMORY called NAME holding FACTS and RULES.
The lists are copied; the facts and RULE objects in them are shared."
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
  "Drop the session knowledge memory. Returns T."
  (setf *knowledge-memory* nil)
  t)

(defun knowledge-add-fact! (fact &optional (km (ensure-knowledge-memory)))
  "Assert FACT into knowledge memory. Returns FACT."
  (setf (knowledge-memory-facts km)
        (add-fact! (knowledge-memory-facts km) fact))
  fact)

(defun knowledge-remove-fact! (fact &optional (km (ensure-knowledge-memory)))
  "Retract FACT from knowledge memory. Returns the facts that remain."
  (setf (knowledge-memory-facts km)
        (remove-fact! (knowledge-memory-facts km) fact))
  (knowledge-memory-facts km))

(defun knowledge-add-rule! (rule &optional (km (ensure-knowledge-memory)))
  "Register RULE in knowledge memory, newest first. Returns RULE.
A rule with a name replaces the rule of that name, as with REGISTER-RULE!."
  (let ((name (rule-name rule))
        (rules (knowledge-memory-rules km)))
    (setf (knowledge-memory-rules km)
          (cons rule
                (if name
                    (remove name rules :key #'rule-name :test #'equal)
                    rules)))
    rule))

(defun knowledge-remove-rule! (name &optional (km (ensure-knowledge-memory)))
  "Remove the rule named NAME from knowledge memory. Returns the rules that
remain."
  (setf (knowledge-memory-rules km)
        (remove name (knowledge-memory-rules km) :key #'rule-name :test #'equal))
  (knowledge-memory-rules km))

(defun knowledge-query (pattern &key (memory (ensure-knowledge-memory))
                                  (infer nil))
  "Query PATTERN against knowledge facts (optional forward inference).
Each hit is a plist (:FACT f :BINDINGS alist), as with QUERY-FACTS."
  (let ((facts (knowledge-memory-facts memory)))
    (query-facts pattern
                 (if infer
                     (forward-chain facts (knowledge-memory-rules memory))
                     facts))))

(defun knowledge-from-context (context &key (name nil))
  "Build a knowledge-memory from CONTEXT local facts and rules."
  (make-knowledge-memory :name (or name (context-name context) 'from-context)
                         :facts (context-facts context)
                         :rules (context-rules context)))

(defun knowledge-merge-into-context! (context &optional (km (ensure-knowledge-memory)))
  "Merge knowledge facts/rules into CONTEXT (local slots). Returns CONTEXT.
A knowledge rule replaces the context rule of the same name. The merged
rules come first, in the order they have in knowledge memory; merging the
same knowledge again changes nothing."
  (dolist (fact (knowledge-memory-facts km))
    (context-add-fact! context fact))
  (let ((rules (knowledge-memory-rules km)))
    ;; REGISTER-RULE! replaces a rule by name only: a rule without a name
    ;; that an earlier merge put in CONTEXT would be there twice.
    (setf (context-rules context)
          (remove-if (lambda (rule) (member rule rules :test #'eq))
                     (context-rules context)))
    ;; REGISTER-RULE! puts each rule first.
    (dolist (rule (reverse rules))
      (register-rule! context rule)))
  context)
