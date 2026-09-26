;;;; memory/procedural.lisp — procedural memory (Phase 7)
;;;;
;;;; Reusable procedures derived from successful plans. Does not embed
;;;; persistence or planner logic — stores symbolic step sequences.

(in-package #:automa-gp)

(defclass gp-procedure ()
  ((name
    :initarg :name
    :accessor procedure-name
    :initform nil)
   (goals
    :initarg :goals
    :accessor procedure-goals
    :initform nil
    :documentation "Goals this procedure was built to achieve.")
   (steps
    :initarg :steps
    :accessor procedure-steps
    :initform nil
    :documentation "Ordered plan steps (operator + bindings plists).")
   (operators-used
    :initarg :operators-used
    :accessor procedure-operators-used
    :initform nil)
   (initial-state
    :initarg :initial-state
    :accessor procedure-initial-state
    :initform nil
    :documentation "Facts that held when the procedure succeeded.")
   (success-count
    :initarg :success-count
    :accessor procedure-success-count
    :initform 1)
   (meta
    :initarg :meta
    :accessor procedure-meta
    :initform nil))
  (:documentation "Reusable symbolic procedure (from a successful plan)."))

(defun procedure-p (object)
  (typep object 'gp-procedure))

(defclass procedural-memory ()
  ((procedures
    :initarg :procedures
    :accessor procedural-memory-procedures
    :initform nil
    :documentation "Alist or list of GP-PROCEDURE objects.")
   (meta
    :initarg :meta
    :accessor procedural-memory-meta
    :initform nil))
  (:documentation "Store of reusable procedures."))

(defun procedural-memory-p (object)
  (typep object 'procedural-memory))

(defvar *procedural-memory* nil
  "Session procedural memory.")

(defun make-procedural-memory (&key procedures meta)
  (make-instance 'procedural-memory
                 :procedures (copy-list procedures)
                 :meta (copy-tree meta)))

(defun ensure-procedural-memory ()
  (unless (procedural-memory-p *procedural-memory*)
    (setf *procedural-memory* (make-procedural-memory)))
  *procedural-memory*)

(defun clear-procedural-memory ()
  (setf *procedural-memory* nil)
  t)

(defun make-procedure (&key name goals steps operators-used initial-state
                         (success-count 1) meta)
  (make-instance 'gp-procedure
                 :name name
                 :goals (copy-list goals)
                 :steps (copy-tree steps)
                 :operators-used (copy-list operators-used)
                 :initial-state (copy-list initial-state)
                 :success-count success-count
                 :meta (copy-tree meta)))

(defun procedure-from-plan (plan &key name)
  "Turn a successful PLAN into a reusable GP-PROCEDURE.
Signals an error if PLAN is missing or unsuccessful."
  (unless (plan-p plan)
    (error "procedure-from-plan requires a PLAN"))
  (unless (plan-success plan)
    (error "procedure-from-plan requires a successful plan"))
  (make-procedure :name (or name
                            (intern (format nil "PROC-~A"
                                           (or (getf (plan-meta plan) :context)
                                               'unnamed))))
                  :goals (plan-goals plan)
                  :steps (plan-steps plan)
                  :operators-used (plan-operators-used plan)
                  :initial-state (plan-initial-state plan)
                  :meta (list :from-plan t
                              :context (getf (plan-meta plan) :context))))

(defun remember-procedure! (procedure &optional (memory (ensure-procedural-memory)))
  "Store PROCEDURE in MEMORY (replace same name). Returns PROCEDURE."
  (let ((name (procedure-name procedure)))
    (setf (procedural-memory-procedures memory)
          (cons procedure
                (remove name (procedural-memory-procedures memory)
                        :key #'procedure-name :test #'equal)))
    procedure))

(defun remember-procedure-from-plan! (plan &key name
                                          (memory (ensure-procedural-memory)))
  "Convert a successful PLAN into a procedure and store it."
  (remember-procedure! (procedure-from-plan plan :name name) memory))

(defun find-procedure (name &optional (memory (ensure-procedural-memory)))
  (find name (procedural-memory-procedures memory)
        :key #'procedure-name :test #'equal))

(defun procedures-for-goals (goals &optional (memory (ensure-procedural-memory)))
  "Procedures whose goal set equals GOALS (order-insensitive EQUAL)."
  (let ((g (copy-list goals)))
    (remove-if-not
     (lambda (p)
       (and (null (set-difference g (procedure-goals p) :test #'equal))
            (null (set-difference (procedure-goals p) g :test #'equal))))
     (procedural-memory-procedures memory))))

(defun procedure->plan (procedure &key (meta nil))
  "Rebuild a PLAN object from a stored PROCEDURE (does not re-run MEA)."
  (make-instance 'plan
                 :goals (copy-list (procedure-goals procedure))
                 :steps (copy-tree (procedure-steps procedure))
                 :success t
                 :initial-state (copy-list (procedure-initial-state procedure))
                 :final-state nil
                 :remaining nil
                 :operators-used (copy-list (procedure-operators-used procedure))
                 :meta (list* :from-procedure (procedure-name procedure)
                              meta)))
