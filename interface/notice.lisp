;;;; interface/notice.lisp — notice one file the context already models
;;;;
;;;; A path is accepted only when a registered reaction matches
;;;; (FILE-CREATED path). The file must already exist. GP-NOTICE-DIRECTORY
;;;; looks once at the files in one directory and applies those reactions,
;;;; so their facts and goals enter the context. GP-WATCH-DIRECTORY repeats
;;;; that look until it is stopped. Subdirectories are entered. A directory
;;;; that is a symbolic link is not. It does not watch the terminal or
;;;; processes, plan, or run an adapter. GP-NOTICE-PROCESSES looks once at
;;;; each process a reaction already names. GP-WATCH-PROCESSES repeats that
;;;; look until it is stopped. GP-NOTICE-TERMINALS looks once at each
;;;; terminal a reaction already names. GP-WATCH-TERMINALS repeats that
;;;; look until it is stopped. GP-NOTICE-TERMINAL-TEXT reads one transcript
;;;; file a reaction already names, and only for the text that reaction
;;;; names. GP-WATCH-TERMINAL-TEXT repeats that read until it is stopped.
;;;; GP-NOTICE-TERMINAL-SCREEN looks once at one Terminal.app tab a
;;;; reaction already names, and only for the text that reaction names.
;;;; GP-WATCH-TERMINAL-SCREEN repeats that look until it is stopped.
;;;; The five watches share one start, repeat, and stop. Each kind keeps
;;;; its own lock, so one can run while another runs. The slot is taken
;;;; before the first look. A stop during a look records nothing further.
;;;; A directory walk, a process check, a transcript read, and a
;;;; Terminal.app read stop when that stop is seen.
;;;; An open session keeps its
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

(defun %symbolic-link-p (path)
  "True when PATH itself is a symbolic link."
  (let ((text (string-right-trim '(#\/) (namestring path))))
    (handler-case
        (sb-posix:s-islnk (sb-posix:stat-mode (sb-posix:lstat text)))
      (error () nil))))

(defvar *notice-halt* nil
  "Nil, or a function of no arguments. A true result ends this look.")

(defun %notice-halted-p ()
  "True when the current look has been asked to stop."
  (and (functionp *notice-halt*)
       (funcall *notice-halt*)))

(defun %files-under-directory (root)
  "Files under ROOT, including subdirectories.
A subdirectory that is a symbolic link is not entered. A stop ends
the walk. Files not yet listed are left out."
  (let ((files nil)
        (seen nil))
    (labels ((visit (dir)
               (when (%notice-halted-p)
                 (return-from visit))
               (let ((id (handler-case (namestring (truename dir))
                           (error () nil))))
                 (unless id
                   (return-from visit))
                 (when (member id seen :test #'string=)
                   (return-from visit))
                 (push id seen)
                 (dolist (file (uiop:directory-files dir))
                   (when (%notice-halted-p)
                     (return-from visit))
                   (push file files))
                 (dolist (sub (uiop:subdirectories dir))
                   (when (%notice-halted-p)
                     (return-from visit))
                   (unless (%symbolic-link-p sub)
                     (visit sub))))))
      (visit (uiop:ensure-directory-pathname root)))
    (sort files #'string< :key #'namestring)))

(defun %accept-notice (form)
  "Assert FORM and react to it, unless this look has been stopped.
Returns NIL when the look is stopped. Returns T when FORM belongs in
the result. A fact already present is not asserted again."
  (when (%notice-halted-p)
    (return-from %accept-notice nil))
  (unless (fact-p form (gp-facts))
    (react-to-event! (ensure-current-context)
                     (gp-emit form :react nil :assert-fact t)))
  t)

(defun gp-notice-directory (path)
  "Notice each file under one existing directory that a reaction models.
PATH is a string or pathname. Subdirectories are entered. A subdirectory
that is a symbolic link is not. A file no reaction accepts is skipped.
Each accepted file is asserted as GP-NOTICE-PATH would, and that event is
reacted, so the reaction's facts and goals enter the context. A stop
during the walk leaves out every file not yet accepted. A stop between
files keeps the file already accepted. A second notice does not add the
same fact again. Does not plan, does not run
adapters, and does not change an open listening session. Returns the file
facts, including ones already present."
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
    (let ((noticed nil))
      (dolist (file (%files-under-directory text))
        (when (%notice-halted-p)
          (return))
        (let ((form (%modeled-file-created-form (namestring file))))
          (when (and form (%accept-notice form))
            (push form noticed))))
      (nreverse noticed))))

(defstruct notice-watch
  interval
  thread
  stop
  noticed
  look
  label
  join-slack)

(defun %call-notice-look (watch lock thunk)
  "Call THUNK where a stop of WATCH ends the look before the next target.
Returns every value THUNK returns. The lock is not held across THUNK."
  (let ((*notice-halt*
         (lambda ()
           (sb-thread:with-mutex (lock)
             (notice-watch-stop watch)))))
    (funcall thunk)))

(defun %notice-watch-loop (watch lock)
  "Repeat WATCH's look until its stop flag is set.
The first look already ran on the caller. A later look that signals is
ignored and the last facts stay. The lock is not held during the look,
so a stop is seen before the next target."
  (loop
    (when (sb-thread:with-mutex (lock)
            (notice-watch-stop watch))
      (return))
    (sleep (notice-watch-interval watch))
    (when (sb-thread:with-mutex (lock)
            (notice-watch-stop watch))
      (return))
    (handler-case
        (let ((noticed (%call-notice-look watch lock
                                          (notice-watch-look watch))))
          (sb-thread:with-mutex (lock)
            (unless (notice-watch-stop watch)
              (setf (notice-watch-noticed watch) noticed))))
      (error () nil))))

(defun %begin-notice-watch (place lock interval thread-name busy prepare
                            &key (join-slack 2))
  "Reserve PLACE, run PREPARE once, then repeat its look until stopped.
PREPARE returns the first facts, the look, and an optional label. The
slot is taken before PREPARE, so a second start fails at once. If this
watch is stopped while PREPARE runs, the repeat does not start. A
PREPARE that signals leaves the slot empty. A stop during that look
records nothing after the target already accepted. PLACE is the symbol
of one watch variable."
  (unless (and (realp interval) (plusp interval))
    (error "Watch interval must be a positive number of seconds."))
  (let ((watch (make-notice-watch :interval interval
                                  :join-slack join-slack
                                  :stop nil)))
    (sb-thread:with-mutex (lock)
      (when (symbol-value place)
        (error busy))
      (setf (symbol-value place) watch))
    (unwind-protect
        (multiple-value-bind (noticed look label)
            (%call-notice-look watch lock prepare)
          (setf (notice-watch-noticed watch) noticed
                (notice-watch-look watch) look
                (notice-watch-label watch) label)
          (sb-thread:with-mutex (lock)
            (cond
              ((and (eq (symbol-value place) watch)
                    (not (notice-watch-stop watch)))
               (setf (notice-watch-thread watch)
                     (sb-thread:make-thread
                      (lambda () (%notice-watch-loop watch lock))
                      :name thread-name))
               noticed)
              (t
               (when (eq (symbol-value place) watch)
                 (setf (symbol-value place) nil))
               noticed))))
      (sb-thread:with-mutex (lock)
        (when (and (eq (symbol-value place) watch)
                   (not (notice-watch-thread watch)))
          (setf (symbol-value place) nil))))))

(defun %end-notice-watch (place lock absent)
  "Stop the watch in PLACE and return the facts last seen."
  (let ((watch (sb-thread:with-mutex (lock)
                 (or (symbol-value place)
                     (error absent)))))
    (sb-thread:with-mutex (lock)
      (setf (notice-watch-stop watch) t))
    (let ((thread (notice-watch-thread watch)))
      (when (and thread (sb-thread:thread-alive-p thread))
        (handler-case
            (sb-thread:join-thread
             thread
             :timeout (+ (notice-watch-interval watch)
                         (notice-watch-join-slack watch)))
          (sb-thread:join-thread-error ()
            (sb-thread:terminate-thread thread)))))
    (sb-thread:with-mutex (lock)
      (when (eq (symbol-value place) watch)
        (setf (symbol-value place) nil)))
    (notice-watch-noticed watch)))

(defun %notice-watch-active-p (place lock)
  "True when PLACE holds a watch."
  (sb-thread:with-mutex (lock)
    (and (symbol-value place) t)))

(defvar *directory-watch* nil
  "The active directory watch, or NIL. One watch at a time.")

(defvar *directory-watch-lock* (sb-thread:make-mutex :name "automa-gp-directory-watch")
  "Serializes watch start, stop, and each look.")

(defun gp-directory-watch ()
  "The path of the active directory watch, or NIL."
  (sb-thread:with-mutex (*directory-watch-lock*)
    (and *directory-watch* (notice-watch-label *directory-watch*))))

(defun gp-watch-directory (path &key (interval 1))
  "Look at PATH now, then again every INTERVAL seconds until stopped.
Each look is GP-NOTICE-DIRECTORY, including subdirectories. A
subdirectory that is a symbolic link is not entered. One watch at a
time. A file that appears later is noticed on a later look. Processes,
planning, and adapters stay out. Returns the file facts from the first look."
  (%begin-notice-watch
   '*directory-watch* *directory-watch-lock* interval
   "automa-gp-directory-watch"
   "A directory watch is already running."
   (lambda ()
     (let ((noticed (gp-notice-directory path))
           (text (string-trim '(#\Space #\Tab #\Newline #\Return)
                              (if (pathnamep path) (namestring path) path))))
       (values noticed
               (lambda () (gp-notice-directory text))
               text)))))

(defun gp-stop-directory-watch ()
  "Stop the active directory watch and return the file facts last seen.
No watch is an error."
  (%end-notice-watch '*directory-watch* *directory-watch-lock*
                     "No directory watch is running."))

(defun %process-running-reaction-p (reaction)
  "True when REACTION's WHEN type is named PROCESS-RUNNING."
  (let ((pattern (event-reaction-when reaction)))
    (and (consp pattern)
         (symbolp (car pattern))
         (string-equal (symbol-name (car pattern)) "PROCESS-RUNNING"))))

(defun %process-target (term)
  "A process name or pid from a fixed TERM, or NIL when TERM is a variable."
  (cond
    ((integerp term) term)
    ((stringp term)
     (let ((text (string-trim '(#\Space #\Tab) term)))
       (unless (zerop (length text))
         text)))
    ((and (symbolp term) (not (variable-symbol-p term)))
     (symbol-name term))))

(defun %process-running-targets ()
  "Names and pids that PROCESS-RUNNING reactions already state."
  (let ((targets nil))
    (dolist (reaction (gp-reactions))
      (let ((pattern (event-reaction-when reaction)))
        (when (%process-running-reaction-p reaction)
          (let ((target (and (consp (cdr pattern))
                             (null (cddr pattern))
                             (%process-target (second pattern)))))
            (when target
              (push target targets))))))
    (remove-duplicates (nreverse targets) :test #'equal)))

(defun %modeled-process-running-form (target)
  "A (PROCESS-RUNNING TARGET) form some reaction matches, or NIL."
  (dolist (reaction (gp-reactions))
    (let ((pattern (event-reaction-when reaction)))
      (when (%process-running-reaction-p reaction)
        (let ((form (list (car pattern) target)))
          (when (match-p pattern form)
            (return form)))))))

(defun gp-notice-processes ()
  "Notice each running process that a reaction already names.
A reaction whose WHEN is (PROCESS-RUNNING name) or (PROCESS-RUNNING pid)
is checked once. A variable does not name a process, and the process
table is not listed. A process that is not running is skipped. Each
running one is asserted and reacted, so the reaction's facts and goals
enter the context. A stop during the check does not record that process.
A second notice does not add the same fact again.
Does not plan, does not run adapters, does not watch the terminal, and
does not change an open listening session. Returns the process facts,
including ones already present."
  (unless (some #'%process-running-reaction-p (gp-reactions))
    (error "No reaction in this context models a running process."))
  (let ((targets (%process-running-targets)))
    (unless targets
      (error "A process reaction needs a name or a pid."))
    (let ((noticed nil))
      (dolist (target targets)
        (when (%notice-halted-p)
          (return))
        (when (%notice-process-running-p target)
          (let ((form (%modeled-process-running-form target)))
            (when (and form (%accept-notice form))
              (push form noticed)))))
      (nreverse noticed))))

(defvar *process-watch* nil
  "The active process watch, or NIL. One watch at a time.")

(defvar *process-watch-lock* (sb-thread:make-mutex :name "automa-gp-process-watch")
  "Serializes process-watch start, stop, and each look.")

(defun gp-process-watch ()
  "True when a process watch is running."
  (%notice-watch-active-p '*process-watch* *process-watch-lock*))

(defun gp-watch-processes (&key (interval 1))
  "Look at named processes now, then again every INTERVAL seconds until stopped.
Each look is GP-NOTICE-PROCESSES. One process watch at a time. A process
that appears later is noticed on a later look. The process table is not
listed. Does not watch the terminal, plan, or run adapters. Returns the
process facts from the first look."
  (%begin-notice-watch
   '*process-watch* *process-watch-lock* interval
   "automa-gp-process-watch"
   "A process watch is already running."
   (lambda ()
     (values (gp-notice-processes) #'gp-notice-processes nil))))

(defun gp-stop-process-watch ()
  "Stop the active process watch and return the process facts last seen.
No watch is an error."
  (%end-notice-watch '*process-watch* *process-watch-lock*
                     "No process watch is running."))

(defun %terminal-open-reaction-p (reaction)
  "True when REACTION's WHEN type is named TERMINAL-OPEN."
  (let ((pattern (event-reaction-when reaction)))
    (and (consp pattern)
         (symbolp (car pattern))
         (string-equal (symbol-name (car pattern)) "TERMINAL-OPEN"))))

(defun %terminal-target (term)
  "A terminal name from a fixed TERM, or NIL when TERM is a variable."
  (cond
    ((stringp term)
     (let ((text (string-trim '(#\Space #\Tab) term)))
       (unless (zerop (length text))
         text)))
    ((and (symbolp term) (not (variable-symbol-p term)))
     (symbol-name term))))

(defun %terminal-open-targets ()
  "Names that TERMINAL-OPEN reactions already state."
  (let ((targets nil))
    (dolist (reaction (gp-reactions))
      (let ((pattern (event-reaction-when reaction)))
        (when (%terminal-open-reaction-p reaction)
          (let ((target (and (consp (cdr pattern))
                             (null (cddr pattern))
                             (%terminal-target (second pattern)))))
            (when target
              (push target targets))))))
    (remove-duplicates (nreverse targets) :test #'equal)))

(defun %open-terminal-names ()
  "TTY names ps currently reports. ?? and console are not terminals.
NIL when this notice look has stopped."
  (let ((text (%cancellable-program '("ps" "-ax" "-o" "tty=") :output t)))
    (when text
      (remove-duplicates
       (loop for raw in (uiop:split-string text :separator '(#\Newline #\Return))
             for name = (string-trim '(#\Space #\Tab) raw)
             unless (or (zerop (length name))
                        (string= name "??")
                        (string= name "?")
                        (string= name "console"))
               collect name)
       :test #'string=))))

(defun %modeled-terminal-open-form (target)
  "A (TERMINAL-OPEN TARGET) form some reaction matches, or NIL."
  (dolist (reaction (gp-reactions))
    (let ((pattern (event-reaction-when reaction)))
      (when (%terminal-open-reaction-p reaction)
        (let ((form (list (car pattern) target)))
          (when (match-p pattern form)
            (return form)))))))

(defun gp-notice-terminals ()
  "Notice each open terminal that a reaction already names.
A reaction whose WHEN is (TERMINAL-OPEN name) is checked once. The name
is the tty ps prints, such as ttys000. A variable does not name a
terminal, and the open terminals are not listed. A name that is not
open is skipped. What is written on the terminal is not read. Each open
one is asserted and reacted, so the reaction's facts and goals enter
the context. A second notice does not add the same fact again. Does
not plan, does not run adapters, does not stay listening, and does not
change an open listening session. Returns the terminal facts, including
ones already present."
  (unless (some #'%terminal-open-reaction-p (gp-reactions))
    (error "No reaction in this context models an open terminal."))
  (let ((targets (%terminal-open-targets)))
    (unless targets
      (error "A terminal reaction needs a name."))
    (let ((open (%open-terminal-names))
          (noticed nil))
      (dolist (target targets)
        (when (%notice-halted-p)
          (return))
        (when (find target open :test #'string=)
          (let ((form (%modeled-terminal-open-form target)))
            (when (and form (%accept-notice form))
              (push form noticed)))))
      (nreverse noticed))))

(defvar *terminal-watch* nil
  "The active terminal watch, or NIL. One watch at a time.")

(defvar *terminal-watch-lock* (sb-thread:make-mutex :name "automa-gp-terminal-watch")
  "Serializes terminal-watch start, stop, and each look.")

(defun gp-terminal-watch ()
  "True when a terminal watch is running."
  (%notice-watch-active-p '*terminal-watch* *terminal-watch-lock*))

(defun gp-watch-terminals (&key (interval 1))
  "Look at named terminals now, then again every INTERVAL seconds until stopped.
Each look is GP-NOTICE-TERMINALS. One terminal watch at a time. A terminal
that opens later is noticed on a later look, when a reaction already names
it. The open terminals are not listed, and what is written there is not
read. Does not plan or run adapters. Returns the terminal facts from the
first look."
  (%begin-notice-watch
   '*terminal-watch* *terminal-watch-lock* interval
   "automa-gp-terminal-watch"
   "A terminal watch is already running."
   (lambda ()
     (values (gp-notice-terminals) #'gp-notice-terminals nil))))

(defun gp-stop-terminal-watch ()
  "Stop the active terminal watch and return the terminal facts last seen.
No watch is an error."
  (%end-notice-watch '*terminal-watch* *terminal-watch-lock*
                     "No terminal watch is running."))

(defun %terminal-text-reaction-p (reaction)
  "True when REACTION's WHEN type is named TERMINAL-TEXT."
  (let ((pattern (event-reaction-when reaction)))
    (and (consp pattern)
         (symbolp (car pattern))
         (string-equal (symbol-name (car pattern)) "TERMINAL-TEXT"))))

(defun %fixed-notice-string (term)
  "A non-empty string from a fixed TERM, or NIL when TERM is a variable."
  (cond
    ((stringp term)
     (unless (zerop (length term))
       term))
    ((and (symbolp term) (not (variable-symbol-p term)))
     (let ((name (symbol-name term)))
       (unless (zerop (length name))
         name)))))

(defun %terminal-text-targets ()
  "Path and text pairs that TERMINAL-TEXT reactions already state."
  (let ((targets nil))
    (dolist (reaction (gp-reactions))
      (let ((pattern (event-reaction-when reaction)))
        (when (%terminal-text-reaction-p reaction)
          (let ((path (and (consp (cdr pattern))
                           (consp (cddr pattern))
                           (null (cdddr pattern))
                           (%fixed-notice-string (second pattern))))
                (text (and (consp (cdr pattern))
                           (consp (cddr pattern))
                           (null (cdddr pattern))
                           (%fixed-notice-string (third pattern)))))
            (when (and path text)
              (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) path)))
                (unless (zerop (length trimmed))
                  (push (cons trimmed text) targets))))))))
    (remove-duplicates (nreverse targets) :test #'equal)))

(defun %regular-transcript-p (path)
  "True when PATH itself is a regular file. A link or a device is not."
  (handler-case
      (sb-posix:s-isreg (sb-posix:stat-mode (sb-posix:lstat path)))
    (error () nil)))

(defun %file-contains-p (path text &key (chunk 8192))
  "True when PATH contains TEXT. NIL when this notice look stops.
A match that crosses a read is still found. TEXT is not a pattern."
  (with-open-file (in path :direction :input :element-type 'character)
    (let ((carry "")
          (size (max chunk (length text))))
      (loop
        (when (%notice-halted-p)
          (return nil))
        (let* ((buf (make-string size))
               (n (read-sequence buf in)))
          (when (zerop n)
            (return nil))
          (let ((window (concatenate 'string carry (subseq buf 0 n))))
            (when (search text window)
              (return (not (%notice-halted-p))))
            (let ((keep (max 0 (1- (length text)))))
              (setf carry
                    (if (zerop keep)
                        ""
                        (subseq window (max 0 (- (length window) keep))))))))))))

(defun %transcript-contains-p (path text)
  "True when the regular file PATH contains TEXT as written.
A link is not followed. A device is not opened. TEXT is not a pattern.
NIL when this notice look stops during the read."
  (and (not (%notice-halted-p))
       (%regular-transcript-p path)
       (handler-case
           (%file-contains-p path text)
         (error () nil))))

(defun %modeled-terminal-text-form (path text)
  "A (TERMINAL-TEXT PATH TEXT) form some reaction matches, or NIL."
  (dolist (reaction (gp-reactions))
    (let ((pattern (event-reaction-when reaction)))
      (when (%terminal-text-reaction-p reaction)
        (let ((form (list (car pattern) path text)))
          (when (match-p pattern form)
            (return form)))))))

(defun gp-notice-terminal-text ()
  "Notice each transcript text that a reaction already names.
A reaction whose WHEN is (TERMINAL-TEXT path text) is checked once.
PATH is a regular file, such as a script transcript. TEXT is the exact
characters to find. A variable does not name a path or a text. A link
is not followed, and a device is not opened. The rest of the file is
not returned. A text that is absent is skipped. Each text that is
present is asserted and reacted, so the reaction's facts and goals
enter the context. A stop during the read does not record that text.
A second notice does not add the same fact again.
Does not stay listening, plan, or run adapters, and does not change an
open listening session. Returns the transcript facts, including ones
already present."
  (unless (some #'%terminal-text-reaction-p (gp-reactions))
    (error "No reaction in this context models terminal text."))
  (let ((targets (%terminal-text-targets)))
    (unless targets
      (error "A terminal text reaction needs a path and a text."))
    (let ((noticed nil))
      (dolist (target targets)
        (when (%notice-halted-p)
          (return))
        (when (%transcript-contains-p (car target) (cdr target))
          (let ((form (%modeled-terminal-text-form (car target) (cdr target))))
            (when (and form (%accept-notice form))
              (push form noticed)))))
      (nreverse noticed))))

(defvar *terminal-text-watch* nil
  "The active transcript watch, or NIL. One watch at a time.")

(defvar *terminal-text-watch-lock*
  (sb-thread:make-mutex :name "automa-gp-terminal-text-watch")
  "Serializes transcript-watch start, stop, and each look.")

(defun gp-terminal-text-watch ()
  "True when a transcript watch is running."
  (%notice-watch-active-p '*terminal-text-watch* *terminal-text-watch-lock*))

(defun gp-watch-terminal-text (&key (interval 1))
  "Read named transcript text now, then again every INTERVAL seconds until stopped.
Each look is GP-NOTICE-TERMINAL-TEXT. One transcript watch at a time. A
text that appears later is noticed on a later look, when a reaction
already names it. A link is not followed, and a device is not opened.
The rest of the file is not returned. Does not read the live terminal
screen, plan, or run adapters. Returns the transcript facts from the
first look."
  (%begin-notice-watch
   '*terminal-text-watch* *terminal-text-watch-lock* interval
   "automa-gp-terminal-text-watch"
   "A transcript watch is already running."
   (lambda ()
     (values (gp-notice-terminal-text) #'gp-notice-terminal-text nil))))

(defun gp-stop-terminal-text-watch ()
  "Stop the active transcript watch and return the transcript facts last seen.
No watch is an error."
  (%end-notice-watch '*terminal-text-watch* *terminal-text-watch-lock*
                     "No transcript watch is running."))

(defun %terminal-screen-reaction-p (reaction)
  "True when REACTION's WHEN type is named TERMINAL-SCREEN."
  (let ((pattern (event-reaction-when reaction)))
    (and (consp pattern)
         (symbolp (car pattern))
         (string-equal (symbol-name (car pattern)) "TERMINAL-SCREEN"))))

(defun %tty-device-name (name)
  "\"ttys012\" or \"/dev/ttys012\" as a device path, or NIL."
  (when (stringp name)
    (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return) name)))
      (cond
        ((and (> (length text) 4)
              (string= "ttys" text :end2 4)
              (every #'digit-char-p (subseq text 4)))
         (concatenate 'string "/dev/" text))
        ((and (> (length text) 9)
              (string= "/dev/ttys" text :end2 9)
              (every #'digit-char-p (subseq text 9)))
         text)))))

(defun %terminal-screen-targets ()
  "Tty and text pairs that TERMINAL-SCREEN reactions already state."
  (let ((targets nil))
    (dolist (reaction (gp-reactions))
      (let ((pattern (event-reaction-when reaction)))
        (when (and (%terminal-screen-reaction-p reaction)
                   (consp (cdr pattern))
                   (consp (cddr pattern))
                   (null (cdddr pattern)))
          (let ((name (%fixed-notice-string (second pattern)))
                (text (%fixed-notice-string (third pattern))))
            (when (and name text (%tty-device-name name))
              (push (cons name text) targets))))))
    (remove-duplicates (nreverse targets) :test #'equal)))

(defun %read-stream-text (stream)
  (when stream
    (with-output-to-string (out)
      (let ((buf (make-string 4096)))
        (loop for n = (read-sequence buf stream)
              until (zerop n)
              do (write-string buf out :end n))))))

(defun %cancellable-program (argv &key timeout output (reader-name "automa-gp-command-read"))
  "Run ARGV. NIL when this notice look stops, or when TIMEOUT seconds pass.
With OUTPUT, return the text. Without it, return the exit code. The
process is stopped if the wait is cut short."
  (when (%notice-halted-p)
    (return-from %cancellable-program nil))
  (handler-case
      (let* ((proc (uiop:launch-program
                    argv
                    :output (if output :stream #P"/dev/null")
                    :error-output #P"/dev/null"))
             (box (list nil))
             (reader (when output
                       (sb-thread:make-thread
                        (lambda ()
                          (setf (car box)
                                (handler-case
                                    (%read-stream-text (uiop:process-info-output proc))
                                  (error () nil))))
                        :name reader-name))))
        (unwind-protect
            (progn
              (loop for waited = 0 then (+ waited 0.1)
                    until (or (not (uiop:process-alive-p proc))
                              (and timeout (>= waited timeout))
                              (%notice-halted-p))
                    do (sleep 0.1))
              (if (or (%notice-halted-p) (uiop:process-alive-p proc))
                  nil
                  (if output
                      (progn
                        (when reader
                          (ignore-errors (sb-thread:join-thread reader :timeout 1)))
                        (car box))
                      (uiop:wait-process proc))))
          (when (uiop:process-alive-p proc)
            (ignore-errors (uiop:terminate-process proc :urgent t))
            (ignore-errors (uiop:wait-process proc)))
          (when (and reader
                     (sb-thread:thread-alive-p reader)
                     (not (eq reader sb-thread:*current-thread*)))
            (ignore-errors (sb-thread:terminate-thread reader)))))
    (error () nil)))

(defun %notice-process-running-p (name-or-pid)
  "True when NAME-OR-PID is running. NIL when this notice look has stopped.
A pid uses kill -0. A name uses pgrep -x, then pgrep -f, then a ps scan."
  (flet ((exited-zero (argv)
           (eql 0 (%cancellable-program argv)))
         (ps-has-name (name)
           (let ((text (%cancellable-program
                        '("ps" "-ax" "-o" "command=") :output t)))
             (and text
                  (loop for line in (uiop:split-string
                                     text :separator '(#\Newline #\Return))
                        thereis (search name line))))))
    (cond
      ((integerp name-or-pid)
       (exited-zero (list "kill" "-0" (princ-to-string name-or-pid))))
      (t
       (let ((name (princ-to-string name-or-pid)))
         (or (exited-zero (list "pgrep" "-xq" name))
             (and (not (%notice-halted-p))
                  (exited-zero (list "pgrep" "-fq" name)))
             (and (not (%notice-halted-p))
                  (ps-has-name name))))))))

(defun %osascript (source &key (timeout 2))
  "Run SOURCE with osascript, or NIL if it does not finish in TIMEOUT seconds.
A stop of the current notice look also returns NIL. The caller must not
put an untrusted string into SOURCE. The osascript process is stopped
if this wait is cut short."
  (%cancellable-program (list "osascript" "-e" source)
                        :timeout timeout
                        :output t
                        :reader-name "automa-gp-osascript-read"))

(defun %terminal-screen-script (device)
  "AppleScript that returns the text of the Terminal tab on DEVICE.
It does not type, and it does not run a command in the tab."
  (format nil "if application \"Terminal\" is not running then return \"\"
tell application \"Terminal\"
  set wanted to \"~A\"
  repeat with w in windows
    try
      repeat with t in tabs of w
        try
          if tty of t is wanted then return contents of t
        end try
      end repeat
    end try
  end repeat
end tell
return \"\""
          device))

(defun %terminal-screen-text (device)
  "Text of the Terminal.app tab on DEVICE, or NIL when it does not answer.
DEVICE is a /dev/ttys path already checked to be only that shape."
  (%osascript (%terminal-screen-script device) :timeout 2))

(defun %modeled-terminal-screen-form (name text)
  "A (TERMINAL-SCREEN NAME TEXT) form some reaction matches, or NIL."
  (dolist (reaction (gp-reactions))
    (let ((pattern (event-reaction-when reaction)))
      (when (%terminal-screen-reaction-p reaction)
        (let ((form (list (car pattern) name text)))
          (when (match-p pattern form)
            (return form)))))))

(defun gp-notice-terminal-screen ()
  "Notice each Terminal.app tab text that a reaction already names.
A reaction whose WHEN is (TERMINAL-SCREEN tty text) is checked once.
TTY is ttys012 or /dev/ttys012. TEXT is the exact characters to find.
A variable does not name a tab or a text. The rest of the screen is
not returned. The look does not type and does not run a command in
the tab. If Terminal.app is closed or does not answer within two
seconds, that text is skipped. A second notice does not add the same
fact again. Does not stay listening, plan, or run adapters, and does
not change an open listening session. Returns the screen facts,
including ones already present."
  (unless (some #'%terminal-screen-reaction-p (gp-reactions))
    (error "No reaction in this context models a terminal screen."))
  (let ((targets (%terminal-screen-targets)))
    (unless targets
      (error "A terminal screen reaction needs a tty name and a text."))
    (let ((screens nil)
          (noticed nil))
      (dolist (target targets)
        (when (%notice-halted-p)
          (return))
        (let* ((device (%tty-device-name (car target)))
               (known (assoc device screens :test #'string=))
               (body (if known
                         (cdr known)
                         (let ((text (%terminal-screen-text device)))
                           (push (cons device text) screens)
                           text))))
          (when (and body (search (cdr target) body))
            (let ((form (%modeled-terminal-screen-form (car target) (cdr target))))
              (when (and form (%accept-notice form))
                (push form noticed))))))
      (nreverse noticed))))

(defvar *terminal-screen-watch* nil
  "The active Terminal.app screen watch, or NIL. One watch at a time.")

(defvar *terminal-screen-watch-lock*
  (sb-thread:make-mutex :name "automa-gp-terminal-screen-watch")
  "Serializes screen-watch start, stop, and each look.")

(defun gp-terminal-screen-watch ()
  "True when a Terminal.app screen watch is running."
  (%notice-watch-active-p '*terminal-screen-watch* *terminal-screen-watch-lock*))

(defun gp-watch-terminal-screen (&key (interval 1))
  "Look at named Terminal.app tabs now, then again every INTERVAL seconds until stopped.
Each look is GP-NOTICE-TERMINAL-SCREEN. One screen watch at a time. A
text that appears later is noticed on a later look, when a reaction
already names it and Terminal.app answers. The rest of the screen is
not returned. The look does not type and does not run a command in the
tab. Does not plan or run adapters. Returns the screen facts from the
first look."
  (%begin-notice-watch
   '*terminal-screen-watch* *terminal-screen-watch-lock* interval
   "automa-gp-terminal-screen-watch"
   "A terminal screen watch is already running."
   (lambda ()
     (values (gp-notice-terminal-screen) #'gp-notice-terminal-screen nil))
   :join-slack 3))

(defun gp-stop-terminal-screen-watch ()
  "Stop the active Terminal.app screen watch and return the screen facts last seen.
No watch is an error."
  (%end-notice-watch '*terminal-screen-watch* *terminal-screen-watch-lock*
                     "No terminal screen watch is running."))

(defun %stop-notice-watches ()
  "Stop every notice watch that is reserved or running.
A directory watch is included before its path is known. One kind does
not stop another."
  (when (%notice-watch-active-p '*directory-watch* *directory-watch-lock*)
    (gp-stop-directory-watch))
  (when (%notice-watch-active-p '*process-watch* *process-watch-lock*)
    (gp-stop-process-watch))
  (when (%notice-watch-active-p '*terminal-watch* *terminal-watch-lock*)
    (gp-stop-terminal-watch))
  (when (%notice-watch-active-p '*terminal-text-watch* *terminal-text-watch-lock*)
    (gp-stop-terminal-text-watch))
  (when (%notice-watch-active-p '*terminal-screen-watch* *terminal-screen-watch-lock*)
    (gp-stop-terminal-screen-watch))
  nil)
