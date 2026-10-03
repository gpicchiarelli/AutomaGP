;;;; adapters/filesystem.lisp — filesystem adapter (Phase 8)
;;;;
;;;; Thin UIOP wrappers. Not imported by MEA/planner. Used only when the
;;;; executor invokes an :EXTERNAL spec with :ADAPTER :FILESYSTEM.

(in-package #:automa-gp)

;;; ---------------------------------------------------------------------------
;;; Refusals shared by the three adapters
;;; ---------------------------------------------------------------------------

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
;;; Primitives
;;; ---------------------------------------------------------------------------

(defun file-exists-p (path)
  "Abstract: true if PATH exists (file or directory)."
  (and (or (uiop:file-exists-p path)
           (uiop:directory-exists-p path))
       t))

(defun directory-files (directory &optional (pattern "*.*"))
  "Abstract: list files under DIRECTORY matching PATTERN (UIOP).
Subdirectories are not listed. A DIRECTORY that does not exist has no files."
  (uiop:directory-files
   (uiop:ensure-directory-pathname directory)
   pattern))

(defun adapter-ensure-directory (path)
  "Ensure the directory PATH exists, creating it and its parents.
PATH names a directory with or without a trailing slash.
Returns the directory pathname."
  (let ((dir (uiop:ensure-directory-pathname path)))
    (ensure-directories-exist dir)
    dir))

(defun adapter-probe-file (path)
  "Return truename of PATH if it exists, else NIL."
  (probe-file path))

(defun adapter-read-file-string (path)
  "Read entire PATH as a string (UTF-8). Signals FILE-ERROR if missing."
  (uiop:read-file-string path))

(defun adapter-write-file-string (path string &key (if-exists :supersede))
  "Write STRING to PATH as UTF-8. Creates parent directories.
IF-EXISTS is as for OPEN. Returns the pathname written, or NIL when the
file exists and IF-EXISTS is NIL: nothing is written then."
  (let* ((p (uiop:ensure-pathname path :want-pathname t))
         (dir (uiop:pathname-directory-pathname p)))
    (when dir (ensure-directories-exist dir))
    (with-open-file (out p :direction :output
                           :if-exists if-exists
                           :if-does-not-exist :create
                           :external-format :utf-8)
      (when out
        (write-string string out)
        p))))

(defun adapter-delete-file (path)
  "Delete the file PATH if it exists. Returns T if deleted, NIL otherwise.
A directory is never deleted and returns NIL.
Intended for tests / controlled cleanup — not for casual EXECUTE use."
  (when (uiop:file-exists-p path)
    (delete-file path)
    t))

(defun filesystem-dispatch (op args)
  "Dispatch filesystem OP with ARGS plist. Returns a result plist.
Signals ACTION-FAILED for an OP this adapter does not have and for a
missing :PATH or :DIRECTORY; the primitive called signals its own errors."
  (flet ((arg (key)
           (%required-argument args key :filesystem op)))
    (case op
      (:file-exists
       (let ((path (arg :path)))
         (list :ok t :exists (file-exists-p path) :path path)))
      (:directory-files
       (let ((dir (arg :directory)))
         (list :ok t
               :files (directory-files dir (or (getf args :pattern) "*.*"))
               :directory dir)))
      (:ensure-directory
       (list :ok t :directory (adapter-ensure-directory (arg :path))))
      (:probe
       (list :ok t :truename (adapter-probe-file (arg :path))))
      (:read-string
       (list :ok t :string (adapter-read-file-string (arg :path))))
      (:write-string
       (list :ok t
             :path (adapter-write-file-string
                    (arg :path)
                    (or (getf args :content) "")
                    :if-exists (or (getf args :if-exists) :supersede))))
      (:delete-file
       (list :ok t :deleted (adapter-delete-file (arg :path))))
      (t
       (%adapter-failure "unknown filesystem op ~S" op)))))
