;;;; tests/test-architecture.lisp — the layers keep to their side of the line
;;;;
;;;; docs/PROMPT.md §3 and §13: the planner and the core know nothing of
;;;; the operating system; an adapter turns an abstract action into a
;;;; concrete one. These tests hold the code to that, with a fake adapter
;;;; that the core reaches by name only, and by reading the sources.

(in-package #:automa-gp/tests)

(def-suite architecture-suite :in automa-gp-suite)
(in-suite architecture-suite)

(defmacro %with-adapter ((name dispatch) &body body)
  "Run BODY with DISPATCH registered under NAME, and the registry as it was after."
  `(let ((*adapters* (copy-list *adapters*)))
     (register-adapter ,name ,dispatch)
     ,@body))

(defun %fake-adapter-context (&key (adapter :fake) (soft nil))
  "A context whose one operator hands (:ECHO (PAYLOAD ?D)) to ADAPTER."
  (let ((ctx (make-context
              :name 'workshop
              :facts '((device d1))
              :mode :execute
              :operators
              (list (make-operator
                     :name 'announce
                     :preconditions '((device ?d))
                     :add-list '((announced ?d))
                     :meta (list :external
                                 (list :adapter adapter :op :echo
                                       :args '(:payload ?d) :soft soft)))))))
    ctx))

(test an-adapter-is-reached-by-the-name-it-registered-under
  (let ((seen nil))
    (%with-adapter ('(:fake :imaginary)
                    (lambda (op args)
                      (push (list op args) seen)
                      (list :ok t :echoed (getf args :payload))))
      (dolist (name '(:fake :imaginary))
        (setf seen nil)
        (let* ((ctx (%fake-adapter-context :adapter name))
               (plan (plan-from-context ctx :goals '((announced d1)))))
          (is-true (plan-success plan))
          (is (equal `((:adapter ,name :op :echo :args (:payload d1)
                        :operator announce))
                     (mapcar (lambda (action)
                               (list :adapter (getf action :adapter)
                                     :op (getf action :op)
                                     :args (getf action :args)
                                     :operator (getf action :operator)))
                             (plan-external-actions plan :context ctx))))
          (is (null seen) "planning invoked the adapter")
          (execute-plan! ctx plan :adapters t)
          (is (equal '((:echo (:payload d1))) seen)))))))

(test no-adapter-runs-unless-adapters-are-on
  (let ((calls 0))
    (%with-adapter (:fake (lambda (op args)
                            (declare (ignore op args))
                            (incf calls)
                            (list :ok t)))
      (let* ((ctx (%fake-adapter-context))
             (plan (plan-from-context ctx :goals '((announced d1)))))
        (simulate-plan plan :context ctx)
        (is (zerop calls) "a simulation invoked the adapter")
        (let ((ctx (%fake-adapter-context)))
          (execute-plan! ctx plan :adapters nil)
          (is (zerop calls) "an execute without adapters invoked the adapter")
          (is (fact-p '(announced d1) (context-all-facts ctx))))))))

(test an-unregistered-adapter-fails-the-step-and-changes-nothing
  "The failure reaches the step restarts as ACTION-FAILED; with no handler
the run is aborted, and the facts are as they were."
  (let* ((ctx (%fake-adapter-context :adapter :nowhere))
         (plan (plan-from-context ctx :goals '((announced d1))))
         (before (copy-list (context-all-facts ctx))))
    (is-false (find-adapter :nowhere))
    (let ((failure (handler-case (let ((*plan-runner-default-abort* nil))
                                   (execute-plan! ctx plan :adapters t))
                     (action-failed (c) c))))
      (is (typep failure 'action-failed))
      (is (search "unknown adapter" (action-failed-reason failure)))
      (is (search "NOWHERE" (string-upcase (action-failed-reason failure)))))
    (let ((result (execute-plan! ctx plan :adapters t)))
      (is-false (execution-success result))
      (is (eq :aborted (getf (first (execution-steps result)) :status))))
    (is (equal before (context-all-facts ctx)))))

(test registering-a-name-again-takes-it-over
  (let ((*adapters* nil))
    (register-adapter '(:a :b) 'identity)
    (register-adapter :a 'list)
    (is (eq 'list (find-adapter :a)))
    (is (eq 'identity (find-adapter :b)))
    (is (equal '(:b :a) (mapcar #'car *adapters*)) "a name taken over moves last")
    (signals type-error (register-adapter "a" 'identity))))

(test the-shipped-adapters-register-themselves
  (dolist (name '(:filesystem :fs :processes :process :macos :os))
    (is-true (find-adapter name) "~S is not registered" name)))

;;; ---------------------------------------------------------------------------
;;; The sources
;;; ---------------------------------------------------------------------------

(defun %source-text (relative)
  (uiop:read-file-string (asdf:system-relative-pathname :automa-gp relative)))

(defun %sources-in (directory)
  "Relative pathnames of the .lisp files directly in DIRECTORY."
  (mapcar (lambda (path)
            (format nil "~A/~A" directory (file-namestring path)))
          (directory (asdf:system-relative-pathname
                      :automa-gp (format nil "~A/*.lisp" directory)))))

(defparameter *operating-system-tokens*
  '("sb-posix" "sb-unix" "run-program" "osascript" "uiop:hostname"
    "uiop:os-macosx-p" "uiop:getenv" "uiop:native-namestring"
    "uiop:directory-files" "uiop:file-exists-p" "probe-file" "delete-file"
    "rename-file" "ensure-directories-exist")
  "What reaches the machine. Only adapters/ and the persistence service of
memory/ may name these.")

(test the-core-names-no-operating-system-primitive
  (dolist (file (%sources-in "core"))
    (let ((text (%source-text file)))
      (dolist (token *operating-system-tokens*)
        (is (null (search token text :test #'char-equal))
            "~A names ~A: only adapters/ may" file token)))))

(test the-core-never-names-an-adapter
  (let ((names '("filesystem-dispatch" "processes-dispatch" "macos-dispatch"
                 "adapter-open" "adapter-hostname" "adapter-uname"
                 "adapter-probe-file" "adapter-read-file" "adapter-write-file"
                 "adapter-delete-file" "adapter-ensure-directory"
                 "process-running-p" "current-process-id")))
    (dolist (file (append (%sources-in "core") (%sources-in "memory")))
      (let ((text (%source-text file)))
        (dolist (name names)
          (is (null (search name text :test #'char-equal))
              "~A names the adapter function ~A" file name))))))

(test no-code-reaches-a-function-that-may-not-exist
  "FBOUNDP/FUNCALL by quoted name is how a layer calls one that loads
after it; with the registry nothing needs it."
  (dolist (file (append (%sources-in "core") (%sources-in "memory")
                        (%sources-in "adapters")))
    (is (null (search "(fboundp '" (%source-text file)))
        "~A tests a function with FBOUNDP" file)))

;;; ---------------------------------------------------------------------------
;;; The public surface
;;; ---------------------------------------------------------------------------

(defun %slot-accessor-names ()
  "Every reader, writer and accessor name that a class, condition or
structure of AUTOMA-GP defines for a slot. Their documentation belongs to
the slot, so they are not asked for a docstring of their own."
  (let ((names (make-hash-table :test #'eq))
        (package (find-package :automa-gp)))
    (do-all-symbols (symbol package)
      (when (and (eq (symbol-package symbol) package) (find-class symbol nil))
        (let ((class (find-class symbol)))
          (if (typep class 'structure-class)
              (dolist (slot (sb-kernel:dd-slots
                             (sb-kernel:find-defstruct-description symbol)))
                (setf (gethash (sb-kernel:dsd-accessor-name slot) names) t))
              (progn
                (ignore-errors (sb-mop:finalize-inheritance class))
                (dolist (slot (sb-mop:class-direct-slots class))
                  (dolist (name (append (sb-mop:slot-definition-readers slot)
                                        (sb-mop:slot-definition-writers slot)))
                    (setf (gethash (if (consp name) (second name) name) names)
                          t))))))))
    names))

(test every-exported-symbol-is-defined-and-documented
  "PROMPT-FASE-2 §4: every public function is exported and has a docstring;
and nothing is exported that does not exist."
  (let ((accessors (%slot-accessor-names))
        (undefined nil) (undocumented nil))
    (do-external-symbols (symbol :automa-gp)
      (let ((function (fboundp symbol))
            (macro (macro-function symbol))
            (variable (and (boundp symbol) (not (constantp symbol))))
            (class (find-class symbol nil)))
        (cond
          ((not (or function variable class (constantp symbol)))
           (push symbol undefined))
          ((gethash symbol accessors))
          (t
           (when (and function (not (special-operator-p symbol))
                      (null (documentation symbol 'function)))
             (push (list (if macro :macro :function) symbol) undocumented))
           (when (and variable (null (documentation symbol 'variable)))
             (push (list :variable symbol) undocumented))
           (when (and class (null (documentation symbol 'type)))
             (push (list :class symbol) undocumented))))))
    (is (null undefined) "exported but never defined: ~{~S~^ ~}" undefined)
    (is (null undocumented) "exported without a docstring: ~{~S~^ ~}"
        undocumented)))
