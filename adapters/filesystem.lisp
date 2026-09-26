;;;; adapters/filesystem.lisp — filesystem adapter (Phase 8)
;;;;
;;;; Thin UIOP wrappers. Not imported by MEA/planner. Used only when the
;;;; executor invokes an :EXTERNAL spec with :ADAPTER :FILESYSTEM.

(in-package #:automa-gp)

(defun file-exists-p (path)
  "Abstract: true if PATH exists (file or directory)."
  (uiop:file-exists-p path))

(defun directory-files (directory &optional (pattern "*.*"))
  "Abstract: list files under DIRECTORY matching PATTERN (UIOP)."
  (uiop:directory-files
   (uiop:ensure-directory-pathname directory)
   pattern))

(defun adapter-ensure-directory (path)
  "Ensure DIRECTORY pathname exists. Returns the directory pathname."
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
  "Write STRING to PATH. Creates parent directories. Returns PATH."
  (let* ((p (uiop:ensure-pathname path :want-pathname t))
         (dir (uiop:pathname-directory-pathname p)))
    (when dir (ensure-directories-exist dir))
    (with-open-file (out p :direction :output
                         :if-exists if-exists
                         :if-does-not-exist :create
                         :external-format :utf-8)
      (write-string string out))
    p))

(defun adapter-delete-file (path)
  "Delete PATH if it exists. Returns T if deleted, NIL otherwise.
Intended for tests / controlled cleanup — not for casual EXECUTE use."
  (when (uiop:file-exists-p path)
    (delete-file path)
    t))

(defun filesystem-dispatch (op args)
  "Dispatch filesystem OP with ARGS plist. Returns a result plist."
  (ecase op
    (:file-exists
     (let ((path (getf args :path)))
       (list :ok t :exists (and path (file-exists-p path)) :path path)))
    (:directory-files
     (let* ((dir (getf args :directory))
            (pattern (or (getf args :pattern) "*.*"))
            (files (when dir (directory-files dir pattern))))
       (list :ok t :files files :directory dir)))
    (:ensure-directory
     (list :ok t :directory (adapter-ensure-directory (getf args :path))))
    (:probe
     (list :ok t :truename (adapter-probe-file (getf args :path))))
    (:read-string
     (list :ok t :string (adapter-read-file-string (getf args :path))))
    (:write-string
     (list :ok t
           :path (adapter-write-file-string (getf args :path)
                                            (or (getf args :content) "")
                                            :if-exists
                                            (or (getf args :if-exists)
                                                :supersede))))
    (:delete-file
     (list :ok t :deleted (adapter-delete-file (getf args :path))))))
