;;;; interface/notice.lisp — notice one file the context already models
;;;;
;;;; A path is accepted only when a registered reaction matches
;;;; (FILE-CREATED path). The file must already exist. GP-NOTICE-DIRECTORY
;;;; looks once at the files in one directory and applies those reactions,
;;;; so their facts and goals enter the context. It does not recurse, watch
;;;; the terminal, plan, or run an adapter. An open session keeps its
;;;; before-state, so the new fact can be the change that GP-INDUCE-RULE
;;;; generalizes.

(in-package #:automa-gp)

(defun %modeled-file-created-form (path-string)
  "A (FILE-CREATED PATH-STRING) form some reaction already matches, or NIL.
The type symbol is the one the reaction uses."
  (dolist (reaction (gp-reactions))
    (let ((pattern (event-reaction-when reaction)))
      (when (and (consp pattern)
                 (symbolp (car pattern))
                 (string-equal (symbol-name (car pattern)) "FILE-CREATED"))
        (let ((form (list (car pattern) path-string)))
          (when (match-p pattern form)
            (return form)))))))

(defun gp-notice-path (path)
  "Assert (FILE-CREATED PATH) when a reaction already models that file.
PATH is one existing file, as a string or pathname. A directory, a missing
path, and a file no reaction accepts are errors: nothing is asserted.
A second notice of the same file does not add another fact or event.
Does not scan a directory, does not watch the terminal, and does not
change an open listening session. Returns the fact."
  (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return)
                           (cond
                             ((pathnamep path) (namestring path))
                             ((stringp path) path)
                             (t (error "Notice a file path as a string."))))))
    (when (zerop (length text))
      (error "Notice a file path."))
    (when (uiop:directory-exists-p text)
      (error "A directory is not a file this context notices."))
    (unless (uiop:file-exists-p text)
      (error "That file is not on disk."))
    (let ((form (%modeled-file-created-form text)))
      (unless form
        (error "No reaction in this context models that file."))
      (unless (fact-p form (gp-facts))
        (gp-emit form :react nil :assert-fact t))
      form)))

(defun %file-created-reaction-p (reaction)
  "True when REACTION's WHEN type is named FILE-CREATED."
  (let ((pattern (event-reaction-when reaction)))
    (and (consp pattern)
         (symbolp (car pattern))
         (string-equal (symbol-name (car pattern)) "FILE-CREATED"))))

(defun gp-notice-directory (path)
  "Notice each file in one existing directory that a reaction models.
PATH is a string or pathname. Subdirectories are not entered. A file no
reaction accepts is skipped. Each accepted file is asserted as
GP-NOTICE-PATH would, and that event is reacted, so the reaction's facts
and goals enter the context. A second notice does not add the same fact
again. Does not plan, does not run adapters, and does not change an open
listening session. Returns the file facts, including ones already present."
  (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return)
                           (cond
                             ((pathnamep path) (namestring path))
                             ((stringp path) path)
                             (t (error "Notice a directory path as a string."))))))
    (when (zerop (length text))
      (error "Notice a directory path."))
    (cond
      ((uiop:directory-exists-p text) nil)
      ((uiop:file-exists-p text)
       (error "A file is not a directory this context notices."))
      (t (error "That directory is not on disk.")))
    (unless (some #'%file-created-reaction-p (gp-reactions))
      (error "No reaction in this context models a created file."))
    (let ((noticed nil)
          (fresh nil))
      (dolist (file (sort (uiop:directory-files
                           (uiop:ensure-directory-pathname text))
                          #'string< :key #'namestring))
        (let* ((name (namestring file))
               (form (%modeled-file-created-form name)))
          (when form
            (push form noticed)
            (unless (fact-p form (gp-facts))
              (push (gp-emit form :react nil :assert-fact t) fresh)))))
      (dolist (event (nreverse fresh))
        (react-to-event! (ensure-current-context) event))
      (nreverse noticed))))
