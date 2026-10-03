;;;; semantic/registry.lisp — the standards AutomaGP knows about
;;;;
;;;; PROMPT-SEMANTICA §3: which standards exist, which versions, what they
;;;; need, which are implemented, which tests passed. The registry answers
;;;; from records; it implements nothing.

(in-package #:automa-gp/semantic)

(defstruct (registry (:constructor %make-registry) (:predicate nil))
  "A table of STANDARD-DEFINITIONs by identifier and version."
  (table (make-hash-table :test 'equal) :read-only t)
  (requirements (make-hash-table :test 'equal) :read-only t))

(defun registry-p (object)
  "True if OBJECT is a REGISTRY."
  (typep object (quote registry)))

(defun make-registry ()
  "An empty REGISTRY."
  (%make-registry))

(defvar *registry* (make-registry)
  "The registry the functions of this package use unless told otherwise.")

(defun call-with-registry (registry function)
  "Call FUNCTION with *REGISTRY* bound to REGISTRY."
  (let ((*registry* registry))
    (funcall function)))

(defmacro with-registry ((registry) &body body)
  "Run BODY with *REGISTRY* bound to REGISTRY."
  `(call-with-registry ,registry (lambda () ,@body)))

(defun %key (identifier version)
  (cons identifier version))

(defun register-standard (definition &key replace)
  "Add DEFINITION to the registry. A standard registered at that version
already is an error, STANDARD-RESOLUTION-ERROR with the restart
:REPLACE-STANDARD, unless REPLACE is true. Returns DEFINITION."
  (check-type definition standard-definition)
  (let ((key (%key (standard-identifier definition)
                   (standard-version definition)))
        (table (registry-table *registry*)))
    (when (and (gethash key table) (not replace))
      (restart-case
          (error 'standard-resolution-error
                 :code :duplicate-standard
                 :message (format nil "~A is already registered"
                                  (standard-designator definition))
                 :standard (standard-identifier definition)
                 :version (standard-version definition)
                 :suggestion "register it with :REPLACE T, or use another version")
        (:replace-standard ()
          :report "Replace the registered standard with this one.")))
    (setf (gethash key table) definition)))

(defun standard-versions (identifier)
  "The versions registered for IDENTIFIER, sorted as text."
  (let ((versions nil))
    (maphash (lambda (key definition)
               (declare (ignore definition))
               (when (eq identifier (car key))
                 (push (cdr key) versions)))
             (registry-table *registry*))
    (sort versions #'string<)))

(defun find-standard (identifier &optional version)
  "The standard IDENTIFIER at VERSION, or NIL when it is not registered.
IDENTIFIER may also be a designator string, IDENTIFIER@VERSION, and then
VERSION is not given. With no version, a standard registered at exactly one
version is that one; at several, the choice is not made here: the answer is
a STANDARD-RESOLUTION-ERROR that lists them."
  (when (stringp identifier)
    (multiple-value-setq (identifier version) (parse-designator identifier)))
  (cond
    (version
     (values (gethash (%key identifier version) (registry-table *registry*))))
    (t
     (let ((versions (standard-versions identifier)))
       (case (length versions)
         (0 nil)
         (1 (gethash (%key identifier (first versions))
                     (registry-table *registry*)))
         (t (error 'standard-resolution-error
                   :code :ambiguous-version
                   :message (format nil "~(~A~) is registered at ~{~A~^, ~}"
                                    identifier versions)
                   :standard identifier
                   :suggestion "name a version: IDENTIFIER@VERSION")))))))

(defun list-standards ()
  "Every registered standard, by identifier and then version."
  (let ((all nil))
    (maphash (lambda (key definition)
               (declare (ignore key))
               (push definition all))
             (registry-table *registry*))
    (sort all (lambda (a b)
                (or (string< (symbol-name (standard-identifier a))
                             (symbol-name (standard-identifier b)))
                    (and (eq (standard-identifier a) (standard-identifier b))
                         (string< (standard-version a) (standard-version b))))))))

(defun standard-closure (designator)
  "The standard DESIGNATOR names and everything it depends on, as a list of
STANDARD-DEFINITIONs, dependencies before the standards that need them and
the standard itself last. The order is the same every time.
A dependency that is not registered signals DEPENDENCY-MISSING, naming what
required it; a cycle signals DEPENDENCY-CYCLE. DESIGNATOR must name a version."
  (multiple-value-bind (identifier version) (parse-designator designator)
    (let ((root (and version (find-standard identifier version))))
      (unless root
        (error 'dependency-missing
               :name designator :required-by nil
               :message (format nil "~A is not registered" designator)))
      (values
       (dependency-closure
        root
        (lambda (definition)
          (mapcar (lambda (dependency)
                    (multiple-value-bind (id v) (parse-designator dependency)
                      (or (find-standard id v)
                          (error 'dependency-missing
                                 :name dependency
                                 :required-by (standard-designator definition)))))
                  (standard-dependencies definition)))
        :key #'standard-designator)))))
