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
;;;; A watch keeps to the context it was started on, whichever context is
;;;; current later. One noticed form enters a context at a time, so two
;;;; watches never interleave their writes. A command that is not a notice
;;;; is not held back by that: the session state is not locked, and a
;;;; front end that runs commands beside a watch holds *NOTICE-ACCEPT-LOCK*
;;;; around each of them. A later look that signals is counted with its
;;;; message: GP-WATCH-FAILURES lists the watches whose latest look failed.
;;;; A watch whose thread ends without a stop frees its slot.
;;;; An open session keeps its before-state, so the new fact can be the
;;;; change that GP-INDUCE-RULE generalizes.

(in-package #:automa-gp)

(define-condition notice-refused (gp-error)
  ((reason :initarg :reason :reader notice-refused-reason))
  (:report (lambda (condition stream)
             (write-string (notice-refused-reason condition) stream)))
  (:documentation "A notice, a watch start, or a watch stop was refused.
NOTICE-REFUSED-REASON is the sentence that says why: the argument, the
reactions of the context, the watch slot, or the host does not allow it.
It is signalled before that call asserts anything, so the context is as
it was."))

(defun %refuse-notice (control &rest arguments)
  "Signal NOTICE-REFUSED with the reason FORMAT builds."
  (error 'notice-refused :reason (apply #'format nil control arguments)))

(defvar *notice-context* nil
  "The context a watch look reads and writes, or NIL outside a watch.")

(defun %notice-context ()
  "The context this look reads and writes.
A watch look keeps the context its watch was started on. Any other
notice uses the current context."
  (or *notice-context* (ensure-current-context)))

(defun %notice-reactions ()
  "Event reactions visible in the context of this look."
  (context-all-event-reactions (%notice-context)))

(defun %reaction-type-p (reaction name)
  "True when REACTION's WHEN type is named NAME, in any package."
  (let ((pattern (event-reaction-when reaction)))
    (and (consp pattern)
         (symbolp (car pattern))
         (string-equal (symbol-name (car pattern)) name))))

(defun %modeled-type-p (name)
  "True when some reaction's WHEN type is named NAME."
  (some (lambda (reaction) (%reaction-type-p reaction name))
        (%notice-reactions)))

(defun %modeled-form (name &rest terms)
  "A (NAME . TERMS) form some reaction already matches, or NIL.
The type symbol is the one the reaction uses."
  (dolist (reaction (%notice-reactions))
    (when (%reaction-type-p reaction name)
      (let* ((pattern (event-reaction-when reaction))
             (form (cons (car pattern) (copy-list terms))))
        (when (match-p pattern form)
          (return form))))))

(defun %reaction-targets (name arity parse)
  "What the reactions whose WHEN type is named NAME already state.
A WHEN with exactly ARITY terms after the type hands those terms to PARSE.
A NIL result is not a target. Each target is listed once, in the order of
the reactions."
  (let ((targets nil))
    (dolist (reaction (%notice-reactions))
      (when (%reaction-type-p reaction name)
        (let* ((terms (cdr (event-reaction-when reaction)))
               (rest terms))
          (when (and (loop repeat arity
                           always (consp rest)
                           do (pop rest))
                     (null rest))
            (let ((target (apply parse terms)))
              (when target
                (pushnew target targets :test #'equal)))))))
    (nreverse targets)))

(defvar *notice-halt* nil
  "Nil, or a function of no arguments. A true result ends this look.")

(defun %notice-halted-p ()
  "True when the current look has been asked to stop."
  (and (functionp *notice-halt*)
       (funcall *notice-halt*)))

(defvar *notice-accept-lock* (sb-thread:make-mutex :name "automa-gp-notice-accept")
  "Held while one noticed form enters a context.
Every notice and every watch thread takes it, so their writes to a context
never interleave. A command that is not a notice does not take it: a front
end that runs commands while a watch runs holds it around each command,
with SB-THREAD:WITH-RECURSIVE-LOCK, and no watch writes meanwhile. The
thread that holds it may notice.")

(defun %accept-notice (form &key (react t))
  "Record FORM in the context of this look, unless the look has been stopped.
Returns NIL when the look is stopped and T when FORM belongs in the
result. A stop is seen while the look waits for its turn to write. A fact
already present is not asserted again. With REACT the event is reacted at
once, and so is an event still pending for a fact already present, as
GP-NOTICE-PATH leaves one: the reaction's facts and goals enter the
context either way. When that context is the current one,
*LAST-REACTION* follows it. The working-memory snapshot follows it when
the current context is that one or inherits from it."
  (loop
    (when (%notice-halted-p)
      (return nil))
    ;; A turn that does not come within the timeout skips the body, and the
    ;; stop is looked at again.
    (sb-thread:with-recursive-lock (*notice-accept-lock* :timeout 0.1)
      (when (%notice-halted-p)
        (return nil))
      ;; A watch thread that has to be terminated is not interrupted here,
      ;; so a form is never left half entered.
      (sb-sys:without-interrupts
        (let* ((context (%notice-context))
               (event (if (fact-p form (context-all-facts context))
                          (and react
                               (find form (pending-events context)
                                     :key #'event-form :test #'equal))
                          (emit-event! context form)))
               (result (and event react (react-to-event! context event)))
               (current *current-context*))
          (when (and result (eq context current))
            (setf *last-reaction*
                  (list :processed 1
                        :matched (copy-list (getf result :matched))
                        :facts-added (copy-list (getf result :facts-added))
                        :goals-added (copy-list (getf result :goals-added))
                        :dropped (copy-list (getf result :dropped))
                        :plan nil
                        :results (list result))))
          ;; The snapshot lists inherited facts too.
          (when (and event
                     (context-p current)
                     (member context (context-lineage current) :test #'eq))
            (refresh-working-memory current))))
      (return t))))

(defun %notice-path-text (path kind)
  "PATH, a string or a pathname, as a trimmed string that is not empty.
KIND, \"file\" or \"directory\", names it when it is refused."
  (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return)
                           (cond
                             ((pathnamep path) (namestring path))
                             ((stringp path) path)
                             (t (%refuse-notice "Notice a ~A path as a string."
                                                kind))))))
    (when (zerop (length text))
      (%refuse-notice "Notice a ~A path." kind))
    text))

(defun gp-notice-path (path)
  "Assert (FILE-CREATED PATH) when a reaction already models that file.
PATH is one existing file, as a string or pathname. A directory, a missing
path, and a file no reaction accepts are refused with NOTICE-REFUSED:
nothing is asserted. A second notice of the same file does not add another
fact or event. The event is recorded and stays pending: GP-REACT, or a
later GP-NOTICE-DIRECTORY that finds the file, applies the reaction.
Does not scan a directory, does not watch the terminal, and does not
change an open listening session. Returns the fact."
  (let ((text (%notice-path-text path "file")))
    (when (uiop:directory-exists-p text)
      (%refuse-notice "A directory is not a file this context notices."))
    (unless (uiop:file-exists-p text)
      (%refuse-notice "That file is not on disk."))
    (let ((form (%modeled-form "FILE-CREATED" text)))
      (unless form
        (%refuse-notice "No reaction in this context models that file."))
      (%accept-notice form :react nil)
      form)))

(defun %entered-directory-p (path)
  "True when the walk enters the directory PATH.
PATH is examined under the name the system knows it by, whatever
characters that name has. A symbolic link is not entered, and neither is
a directory that cannot be examined."
  (handler-case
      (not (sb-posix:s-islnk
            (sb-posix:stat-mode
             (sb-posix:lstat (sb-ext:native-namestring path :as-file t)))))
    (error () nil)))

(defun %files-under-directory (root)
  "Files under ROOT, including subdirectories.
A subdirectory that is a symbolic link is not entered. A file that is a
symbolic link is listed under its own path. A stop ends the walk. Files
not yet listed are left out."
  (let ((files nil)
        (seen (make-hash-table :test #'equal)))
    (labels ((visit (dir)
               (when (%notice-halted-p)
                 (return-from visit))
               (let ((id (handler-case (namestring (truename dir))
                           (error () nil))))
                 (when (or (null id) (gethash id seen))
                   (return-from visit))
                 (setf (gethash id seen) t)
                 (dolist (file (uiop:directory-files dir))
                   (when (%notice-halted-p)
                     (return-from visit))
                   (push file files))
                 (dolist (sub (uiop:subdirectories dir))
                   (when (%notice-halted-p)
                     (return-from visit))
                   (when (%entered-directory-p sub)
                     (visit sub))))))
      (visit (uiop:ensure-directory-pathname root)))
    (sort files #'string< :key #'namestring)))

(defun gp-notice-directory (path)
  "Notice each file under one existing directory that a reaction models.
PATH is a string or pathname. Subdirectories are entered. A subdirectory
that is a symbolic link is not. A file that is a symbolic link is noticed
under its own path, and no file is read. A file no reaction accepts is
skipped. Each accepted file is asserted as GP-NOTICE-PATH would, and that
event is reacted, so the reaction's facts and goals enter the context. A
file GP-NOTICE-PATH already recorded is not asserted again, and its
pending event is reacted now. A stop during the walk leaves out every
file not yet accepted. A stop between files keeps the file already
accepted. A second notice does not add the same fact again. A path that
is not an existing directory, and a context with no FILE-CREATED
reaction, are refused with NOTICE-REFUSED. Does not plan, does not run
adapters, and does not change an open listening session. Returns the file
facts, including ones already present."
  (let ((text (%notice-path-text path "directory")))
    (cond
      ((uiop:directory-exists-p text) nil)
      ((uiop:file-exists-p text)
       (%refuse-notice "A file is not a directory this context notices."))
      (t (%refuse-notice "That directory is not on disk.")))
    (unless (%modeled-type-p "FILE-CREATED")
      (%refuse-notice "No reaction in this context models a created file."))
    (let ((noticed nil))
      (dolist (file (%files-under-directory text))
        (when (%notice-halted-p)
          (return))
        (let ((form (%modeled-form "FILE-CREATED" (namestring file))))
          (when (and form (%accept-notice form))
            (push form noticed))))
      (nreverse noticed))))

(defstruct notice-watch
  "One watch. INTERVAL, CONTEXT, WAKE and JOIN-SLACK never change. LOOK
and LABEL are set once, before the thread starts. The other slots are
read and written with the lock of the watch's kind held."
  interval
  context
  thread
  stop
  (wake (sb-thread:make-waitqueue :name "automa-gp-notice-watch"))
  noticed
  look
  label
  join-slack
  (failed-looks 0)
  failure)

(defun %call-notice-look (watch lock thunk)
  "Call THUNK as one look of WATCH and return every value THUNK returns.
The look reads and writes the context WATCH was started on. A stop of
WATCH ends the look before the next target. The lock is not held across
THUNK."
  (let ((*notice-context* (notice-watch-context watch))
        (*notice-halt*
         (lambda ()
           (sb-thread:with-mutex (lock)
             (notice-watch-stop watch)))))
    (funcall thunk)))

(defun %notice-watch-wait (watch lock)
  "Wait out WATCH's interval, or less when WATCH is stopped meanwhile.
True when WATCH is stopped."
  (let ((deadline (+ (get-internal-real-time)
                     (* (notice-watch-interval watch)
                        internal-time-units-per-second))))
    (loop
      (sb-thread:with-mutex (lock)
        (when (notice-watch-stop watch)
          (return t))
        (let ((left (/ (- deadline (get-internal-real-time))
                       internal-time-units-per-second)))
          (unless (plusp left)
            (return nil))
          ;; A wait that times out comes back without the lock, and the
          ;; next turn takes it again. One wait is a minute at most, so
          ;; any interval is a timeout the system accepts.
          (sb-thread:condition-wait (notice-watch-wake watch) lock
                                    :timeout (min left 60)))))))

(defun %notice-watch-loop (watch place lock)
  "Repeat WATCH's look every interval until its stop flag is set.
The first look already ran on the caller. A stop ends the wait between
two looks at once. A later look that signals is counted with its message,
for GP-WATCH-FAILURES, and the facts of the last good look stay. The next
good look clears that count. The lock is not held during the look, so a
stop is seen before the next target. However the thread ends, PLACE no
longer holds WATCH afterwards: a watch without its thread is not running."
  (unwind-protect
       (loop until (%notice-watch-wait watch lock)
             do (handler-case
                    (let ((noticed (%call-notice-look
                                    watch lock (notice-watch-look watch))))
                      (sb-thread:with-mutex (lock)
                        (unless (notice-watch-stop watch)
                          (setf (notice-watch-noticed watch) noticed
                                (notice-watch-failed-looks watch) 0
                                (notice-watch-failure watch) nil))))
                  (error (condition)
                    (let ((message
                            (or (ignore-errors (princ-to-string condition))
                                (prin1-to-string (type-of condition)))))
                      (sb-thread:with-mutex (lock)
                        (incf (notice-watch-failed-looks watch))
                        (setf (notice-watch-failure watch) message))))))
    (sb-thread:with-mutex (lock)
      (when (eq (symbol-value place) watch)
        (setf (symbol-value place) nil)))))

(defun %watch-interval (interval)
  "INTERVAL as a rational number of seconds, or refuse it.
A watch repeats every positive, finite number of seconds."
  (or (and (realp interval)
           (handler-case (and (plusp interval) (rational interval))
             (arithmetic-error () nil)))
      (%refuse-notice "Watch interval must be a positive number of seconds.")))

(defun %begin-notice-watch (place lock interval thread-name busy prepare
                            &key (join-slack 2))
  "Reserve PLACE, run PREPARE once, then repeat its look until stopped.
PREPARE returns the first facts, the look, and an optional label. The
slot is taken before PREPARE, so a second start is refused at once. If
this watch is stopped while PREPARE runs, the repeat does not start. A
PREPARE that signals leaves the slot empty. A stop during that look
records nothing after the target already accepted. The watch keeps the
context that is current now for every later look. PLACE is the symbol
of one watch variable."
  (let ((watch (make-notice-watch :interval (%watch-interval interval)
                                  :join-slack join-slack
                                  :context (ensure-current-context))))
    (sb-thread:with-mutex (lock)
      (when (symbol-value place)
        (%refuse-notice "~A" busy))
      (setf (symbol-value place) watch))
    (unwind-protect
        (multiple-value-bind (noticed look label)
            (%call-notice-look watch lock prepare)
          (sb-thread:with-mutex (lock)
            (setf (notice-watch-noticed watch) noticed
                  (notice-watch-look watch) look
                  (notice-watch-label watch) label)
            (when (and (eq (symbol-value place) watch)
                       (not (notice-watch-stop watch)))
              (setf (notice-watch-thread watch)
                    (sb-thread:make-thread
                     (lambda () (%notice-watch-loop watch place lock))
                     :name thread-name))))
          noticed)
      (sb-thread:with-mutex (lock)
        (when (and (eq (symbol-value place) watch)
                   (not (notice-watch-thread watch)))
          (setf (symbol-value place) nil))))))

(defun %end-notice-watch (place lock absent)
  "Stop the watch in PLACE and return the facts last seen.
A watch waiting for its next look ends at once. A look in progress has
the join slack of the watch to see the stop. Only a look still running
after that has its thread terminated. PLACE is empty afterwards. No
watch in PLACE is refused with the sentence ABSENT."
  (multiple-value-bind (watch thread)
      (sb-thread:with-mutex (lock)
        (let ((watch (or (symbol-value place)
                         (%refuse-notice "~A" absent))))
          (setf (notice-watch-stop watch) t)
          (sb-thread:condition-broadcast (notice-watch-wake watch))
          (values watch (notice-watch-thread watch))))
    (unwind-protect
        (when thread
          (sb-thread:join-thread thread
                                 :default nil
                                 :timeout (notice-watch-join-slack watch))
          (when (sb-thread:thread-alive-p thread)
            ;; The thread may end between the test and the call.
            (ignore-errors (sb-thread:terminate-thread thread))
            (sb-thread:join-thread thread :default nil :timeout 1)))
      (sb-thread:with-mutex (lock)
        (when (eq (symbol-value place) watch)
          (setf (symbol-value place) nil))))
    (sb-thread:with-mutex (lock)
      (notice-watch-noticed watch))))

(defun %notice-watch-active-p (place lock)
  "True when PLACE holds a watch."
  (sb-thread:with-mutex (lock)
    (and (symbol-value place) t)))

(defvar *directory-watch* nil
  "The active directory watch, or NIL. One watch at a time.")

(defvar *directory-watch-lock* (sb-thread:make-mutex :name "automa-gp-directory-watch")
  "Guards the directory-watch slot and that watch. Not held during a look.")

(defun gp-directory-watch ()
  "The path of the active directory watch, or NIL."
  (sb-thread:with-mutex (*directory-watch-lock*)
    (and *directory-watch* (notice-watch-label *directory-watch*))))

(defun gp-watch-directory (path &key (interval 1))
  "Look at PATH now, then again every INTERVAL seconds until stopped.
Each look is GP-NOTICE-DIRECTORY, including subdirectories. A
subdirectory that is a symbolic link is not entered. One watch at a
time. A file that appears later is noticed on a later look. The watch
keeps to the context that is current now. A later look that signals is
listed by GP-WATCH-FAILURES. Processes, planning, and adapters stay out.
Returns the file facts from the first look."
  (%begin-notice-watch
   '*directory-watch* *directory-watch-lock* interval
   "automa-gp-directory-watch"
   "A directory watch is already running."
   (lambda ()
     (let ((text (%notice-path-text path "directory")))
       (values (gp-notice-directory text)
               (lambda () (gp-notice-directory text))
               text)))))

(defun gp-stop-directory-watch ()
  "Stop the active directory watch and return the file facts last seen.
The stop does not wait for the interval to pass. No watch is refused
with NOTICE-REFUSED."
  (%end-notice-watch '*directory-watch* *directory-watch-lock*
                     "No directory watch is running."))

(defparameter *notice-text-format* '(:utf-8 :replacement #\Replacement_Character)
  "How a transcript and the output of a command are decoded.
UTF-8, with U+FFFD for bytes that are not UTF-8, so a stray byte never
hides the text after it.")

(defun %cancellable-program (argv &key timeout output (reader-name "automa-gp-command-read"))
  "Run ARGV. NIL when this notice look stops, or when TIMEOUT seconds pass.
With OUTPUT, return the text. Without it, return the exit code. The
process is stopped if the wait is cut short, and its pipe is closed on
every way out. A program that cannot be started signals."
  (when (%notice-halted-p)
    (return-from %cancellable-program nil))
  (let* ((process (uiop:launch-program
                   argv
                   :output (if output :stream #P"/dev/null")
                   :error-output #P"/dev/null"
                   :external-format *notice-text-format*))
         (text nil)
         (reader (when output
                   (sb-thread:make-thread
                    (lambda ()
                      (setf text
                            (ignore-errors
                             (uiop:slurp-stream-string
                              (uiop:process-info-output process)))))
                    :name reader-name))))
    (unwind-protect
        (progn
          (loop for waited = 0 then (+ waited 0.1)
                until (or (not (uiop:process-alive-p process))
                          (and timeout (>= waited timeout))
                          (%notice-halted-p))
                do (sleep 0.1))
          (cond
            ((or (%notice-halted-p) (uiop:process-alive-p process)) nil)
            (output
             (sb-thread:join-thread reader :default nil :timeout 1)
             text)
            (t (uiop:wait-process process))))
      (when (uiop:process-alive-p process)
        (ignore-errors (uiop:terminate-process process :urgent t)))
      (ignore-errors (uiop:wait-process process))
      (when (and reader (sb-thread:thread-alive-p reader))
        ;; The reader may end between the test and the call.
        (ignore-errors (sb-thread:terminate-thread reader))
        (sb-thread:join-thread reader :default nil :timeout 1))
      (ignore-errors (uiop:close-streams process)))))

(defun %process-target (term)
  "A process name or pid from a fixed TERM, or NIL when TERM names none.
A variable, an empty name, and a pid below 1 name no process."
  (cond
    ((integerp term)
     (and (plusp term) term))
    ((stringp term)
     (let ((text (string-trim '(#\Space #\Tab) term)))
       (unless (zerop (length text))
         text)))
    ((and (symbolp term) (not (variable-symbol-p term)))
     (symbol-name term))))

(defparameter *process-listing* "ps -axww -o pid=,command="
  "The ps call that prints the pid and the whole command line of every process.
It is run as a list of arguments, never by a shell, and it is the command
line ps prints for itself.")

(defun %process-line (line)
  "The pid and the command line of one LINE of *PROCESS-LISTING*, or NIL."
  (let* ((text (string-trim '(#\Space #\Tab) line))
         (gap (position #\Space text))
         (pid (and gap (parse-integer text :end gap :junk-allowed t))))
    (when pid
      (values pid (string-left-trim '(#\Space #\Tab) (subseq text gap))))))

(defun %command-names-p (name pid command)
  "True when process PID, whose command line is COMMAND, counts as NAME.
NAME is literal text. Any other process counts when COMMAND contains
NAME. The listing that printed COMMAND does not count. This Lisp image
counts only by the program COMMAND starts with, as a path or as its last
component: a name that occurs in the arguments the image was started with
is not a process."
  (cond
    ((string= command *process-listing*) nil)
    ((eql pid (current-process-id))
     (let* ((program (subseq command 0 (position #\Space command)))
            (slash (position #\/ program :from-end t)))
       (or (string= name program)
           (and slash (string= name program :start2 (1+ slash))))))
    (t (and (search name command) t))))

(defun %notice-process-running-p (name-or-pid)
  "True when NAME-OR-PID is running. NIL when this notice look has stopped.
A pid counts when ps lists it, whoever owns the process. A pid below 1
names no process. A name is literal text, never a pattern: it counts when
the command line ps prints for some process contains it, as
%COMMAND-NAMES-P says."
  (if (integerp name-or-pid)
      (and (plusp name-or-pid)
           (eql 0 (%cancellable-program
                   (list "ps" "-p" (princ-to-string name-or-pid) "-o" "pid="))))
      (let ((name (princ-to-string name-or-pid))
            (text (%cancellable-program
                   (uiop:split-string *process-listing* :separator " ")
                   :output t)))
        (and text
             (loop for line in (uiop:split-string
                                text :separator '(#\Newline #\Return))
                   thereis (multiple-value-bind (pid command)
                               (%process-line line)
                             (and pid (%command-names-p name pid command))))))))

(defun gp-notice-processes ()
  "Notice each running process that a reaction already names.
A reaction whose WHEN is (PROCESS-RUNNING name) or (PROCESS-RUNNING pid)
is checked once. A variable does not name a process, and neither does a
pid below 1. A pid is running when ps lists it. A name is literal text,
not a pattern: it is running when the command line of some process
contains it. This Lisp image counts by the name of its program only, and
the ps that lists the processes does not count. A process that is not
running is skipped. Each running one is asserted and reacted, so the
reaction's facts and goals enter the context. A stop during the check
does not record that process. A second notice does not add the same fact
again. A context with no PROCESS-RUNNING reaction, or with none that
names a process, is refused with NOTICE-REFUSED. Does not plan, does not
run adapters, does not watch the terminal, and does not change an open
listening session. Returns the process facts, including ones already
present."
  (unless (%modeled-type-p "PROCESS-RUNNING")
    (%refuse-notice "No reaction in this context models a running process."))
  (let ((targets (%reaction-targets "PROCESS-RUNNING" 1 #'%process-target)))
    (unless targets
      (%refuse-notice "A process reaction needs a name or a pid."))
    (let ((noticed nil))
      (dolist (target targets)
        (when (%notice-halted-p)
          (return))
        (when (%notice-process-running-p target)
          (let ((form (%modeled-form "PROCESS-RUNNING" target)))
            (when (and form (%accept-notice form))
              (push form noticed)))))
      (nreverse noticed))))

(defvar *process-watch* nil
  "The active process watch, or NIL. One watch at a time.")

(defvar *process-watch-lock* (sb-thread:make-mutex :name "automa-gp-process-watch")
  "Guards the process-watch slot and that watch. Not held during a look.")

(defun gp-process-watch ()
  "True when a process watch is running."
  (%notice-watch-active-p '*process-watch* *process-watch-lock*))

(defun gp-watch-processes (&key (interval 1))
  "Look at named processes now, then again every INTERVAL seconds until stopped.
Each look is GP-NOTICE-PROCESSES. One process watch at a time. A process
that appears later is noticed on a later look. The watch keeps to the
context that is current now. A later look that signals is listed by
GP-WATCH-FAILURES. The process table is not returned. Does not watch the
terminal, plan, or run adapters. Returns the process facts from the
first look."
  (%begin-notice-watch
   '*process-watch* *process-watch-lock* interval
   "automa-gp-process-watch"
   "A process watch is already running."
   (lambda ()
     (values (gp-notice-processes) #'gp-notice-processes nil))))

(defun gp-stop-process-watch ()
  "Stop the active process watch and return the process facts last seen.
The stop does not wait for the interval to pass. No watch is refused
with NOTICE-REFUSED."
  (%end-notice-watch '*process-watch* *process-watch-lock*
                     "No process watch is running."))

(defun %terminal-target (term)
  "A terminal name from a fixed TERM, or NIL when TERM is a variable."
  (cond
    ((stringp term)
     (let ((text (string-trim '(#\Space #\Tab) term)))
       (unless (zerop (length text))
         text)))
    ((and (symbolp term) (not (variable-symbol-p term)))
     (symbol-name term))))

(defvar *notice-open-terminals-override* :ps
  "When a list, GP-NOTICE-TERMINALS treats these names as open (tests).
:PS (default) means ask ps. An empty list means no terminals are open.")

(defun %open-terminal-names ()
  "TTY names ps currently reports. ?? and console are not terminals.
NIL when this notice look has stopped.
*NOTICE-OPEN-TERMINALS-OVERRIDE*, when a list, replaces the ps look — used by
tests on hosts that cannot allocate a PTY."
  (when (listp *notice-open-terminals-override*)
    (return-from %open-terminal-names
      (copy-list *notice-open-terminals-override*)))
  (let ((text (%cancellable-program '("ps" "-axww" "-o" "tty=") :output t)))
    (when text
      (remove-duplicates
       (loop for raw in (uiop:split-string text :separator '(#\Newline #\Return))
             for name = (string-trim '(#\Space #\Tab) raw)
             unless (or (zerop (length name))
                        (string= name "??")
                        (string= name "?")
                        (string= name "console")
                        (string= name "-"))
               collect name)
       :test #'string=))))

(defun gp-notice-terminals ()
  "Notice each open terminal that a reaction already names.
A reaction whose WHEN is (TERMINAL-OPEN name) is checked once. The name
is the tty ps prints, such as ttys000. A variable does not name a
terminal, and the open terminals are not listed. A name that is not
open is skipped. What is written on the terminal is not read. Each open
one is asserted and reacted, so the reaction's facts and goals enter
the context. A second notice does not add the same fact again. A context
with no TERMINAL-OPEN reaction, or with none that names a terminal, is
refused with NOTICE-REFUSED. Does not plan, does not run adapters, does
not stay listening, and does not change an open listening session.
Returns the terminal facts, including ones already present."
  (unless (%modeled-type-p "TERMINAL-OPEN")
    (%refuse-notice "No reaction in this context models an open terminal."))
  (let ((targets (%reaction-targets "TERMINAL-OPEN" 1 #'%terminal-target)))
    (unless targets
      (%refuse-notice "A terminal reaction needs a name."))
    (let ((open (%open-terminal-names))
          (noticed nil))
      (dolist (target targets)
        (when (%notice-halted-p)
          (return))
        (when (find target open :test #'string=)
          (let ((form (%modeled-form "TERMINAL-OPEN" target)))
            (when (and form (%accept-notice form))
              (push form noticed)))))
      (nreverse noticed))))

(defvar *terminal-watch* nil
  "The active terminal watch, or NIL. One watch at a time.")

(defvar *terminal-watch-lock* (sb-thread:make-mutex :name "automa-gp-terminal-watch")
  "Guards the terminal-watch slot and that watch. Not held during a look.")

(defun gp-terminal-watch ()
  "True when a terminal watch is running."
  (%notice-watch-active-p '*terminal-watch* *terminal-watch-lock*))

(defun gp-watch-terminals (&key (interval 1))
  "Look at named terminals now, then again every INTERVAL seconds until stopped.
Each look is GP-NOTICE-TERMINALS. One terminal watch at a time. A terminal
that opens later is noticed on a later look, when a reaction already names
it. The watch keeps to the context that is current now. A later look that
signals is listed by GP-WATCH-FAILURES. The open terminals are not listed,
and what is written there is not read. Does not plan or run adapters.
Returns the terminal facts from the first look."
  (%begin-notice-watch
   '*terminal-watch* *terminal-watch-lock* interval
   "automa-gp-terminal-watch"
   "A terminal watch is already running."
   (lambda ()
     (values (gp-notice-terminals) #'gp-notice-terminals nil))))

(defun gp-stop-terminal-watch ()
  "Stop the active terminal watch and return the terminal facts last seen.
The stop does not wait for the interval to pass. No watch is refused
with NOTICE-REFUSED."
  (%end-notice-watch '*terminal-watch* *terminal-watch-lock*
                     "No terminal watch is running."))

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

(defun %terminal-text-target (path text)
  "A (PATH . TEXT) pair from the two fixed terms of a TERMINAL-TEXT WHEN.
NIL when either is a variable or empty. PATH is trimmed."
  (let ((path (%fixed-notice-string path))
        (text (%fixed-notice-string text)))
    (when (and path text)
      (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) path)))
        (unless (zerop (length trimmed))
          (cons trimmed text))))))

(defun %regular-transcript-p (path)
  "True when PATH itself is a regular file. A link or a device is not."
  (handler-case
      (sb-posix:s-isreg (sb-posix:stat-mode (sb-posix:lstat path)))
    (error () nil)))

(defun %file-contains-p (path text &key (chunk 8192))
  "True when PATH contains TEXT. NIL when this notice look stops.
A match that crosses a read is still found. TEXT is not a pattern. Bytes
that are not UTF-8 read as U+FFFD and the text after them is still
searched."
  (with-open-file (in path :direction :input
                           :element-type 'character
                           :external-format *notice-text-format*)
    (let ((buffer (make-string (max chunk (length text))))
          (keep (max 0 (1- (length text))))
          (carry ""))
      (loop
        (when (%notice-halted-p)
          (return nil))
        (let ((n (read-sequence buffer in)))
          (when (zerop n)
            (return nil))
          (let ((window (concatenate 'string carry (subseq buffer 0 n))))
            (when (search text window)
              (return (not (%notice-halted-p))))
            (setf carry (subseq window (max 0 (- (length window) keep))))))))))

(defun %transcript-contains-p (path text)
  "True when the regular file PATH contains TEXT as written.
A link is not followed. A device is not opened. A path that is not there
is not a transcript yet. TEXT is not a pattern. NIL when this notice look
stops during the read. A transcript that cannot be opened or read
signals."
  (and (not (%notice-halted-p))
       (%regular-transcript-p path)
       ;; The file is opened under the name that was just examined.
       (%file-contains-p (sb-ext:parse-native-namestring path) text)))

(defun gp-notice-terminal-text ()
  "Notice each transcript text that a reaction already names.
A reaction whose WHEN is (TERMINAL-TEXT path text) is checked once.
PATH is a regular file, such as a script transcript. TEXT is the exact
characters to find. A variable does not name a path or a text. A link
is not followed, and a device is not opened. The rest of the file is
not returned. Bytes that are not UTF-8 do not hide the text after them.
A text that is absent is skipped. Each text that is present is asserted
and reacted, so the reaction's facts and goals enter the context. A stop
during the read does not record that text. A second notice does not add
the same fact again. A context with no TERMINAL-TEXT reaction, or with
none that names a path and a text, is refused with NOTICE-REFUSED. A
transcript that cannot be read signals, and the texts already found
stay. Does not stay listening, plan, or run adapters, and does not
change an open listening session. Returns the transcript facts,
including ones already present."
  (unless (%modeled-type-p "TERMINAL-TEXT")
    (%refuse-notice "No reaction in this context models terminal text."))
  (let ((targets (%reaction-targets "TERMINAL-TEXT" 2 #'%terminal-text-target)))
    (unless targets
      (%refuse-notice "A terminal text reaction needs a path and a text."))
    (let ((noticed nil))
      (dolist (target targets)
        (when (%notice-halted-p)
          (return))
        (when (%transcript-contains-p (car target) (cdr target))
          (let ((form (%modeled-form "TERMINAL-TEXT" (car target) (cdr target))))
            (when (and form (%accept-notice form))
              (push form noticed)))))
      (nreverse noticed))))

(defvar *terminal-text-watch* nil
  "The active transcript watch, or NIL. One watch at a time.")

(defvar *terminal-text-watch-lock*
  (sb-thread:make-mutex :name "automa-gp-terminal-text-watch")
  "Guards the transcript-watch slot and that watch. Not held during a look.")

(defun gp-terminal-text-watch ()
  "True when a transcript watch is running."
  (%notice-watch-active-p '*terminal-text-watch* *terminal-text-watch-lock*))

(defun gp-watch-terminal-text (&key (interval 1))
  "Read named transcript text now, then again every INTERVAL seconds until stopped.
Each look is GP-NOTICE-TERMINAL-TEXT. One transcript watch at a time. A
text that appears later is noticed on a later look, when a reaction
already names it. The watch keeps to the context that is current now. A
later look that signals is listed by GP-WATCH-FAILURES. A link is not
followed, and a device is not opened. The rest of the file is not
returned. Does not read the live terminal screen, plan, or run adapters.
Returns the transcript facts from the first look."
  (%begin-notice-watch
   '*terminal-text-watch* *terminal-text-watch-lock* interval
   "automa-gp-terminal-text-watch"
   "A transcript watch is already running."
   (lambda ()
     (values (gp-notice-terminal-text) #'gp-notice-terminal-text nil))))

(defun gp-stop-terminal-text-watch ()
  "Stop the active transcript watch and return the transcript facts last seen.
The stop does not wait for the interval to pass. No watch is refused
with NOTICE-REFUSED."
  (%end-notice-watch '*terminal-text-watch* *terminal-text-watch-lock*
                     "No transcript watch is running."))

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

(defun %terminal-screen-target (name text)
  "A (NAME . TEXT) pair from the two fixed terms of a TERMINAL-SCREEN WHEN.
NIL when either is a variable or empty, or when NAME is not a tty name."
  (let ((name (%fixed-notice-string name))
        (text (%fixed-notice-string text)))
    (when (and name text (%tty-device-name name))
      (cons name text))))

(defun %osascript (source &key (timeout 2))
  "Run SOURCE with osascript, or NIL if it does not finish in TIMEOUT seconds.
A stop of the current notice look also returns NIL. The caller must not
put an untrusted string into SOURCE. The osascript process is stopped
if this wait is cut short. Only macOS has osascript."
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

(defun gp-notice-terminal-screen ()
  "Notice each Terminal.app tab text that a reaction already names.
A reaction whose WHEN is (TERMINAL-SCREEN tty text) is checked once.
TTY is ttys012 or /dev/ttys012. TEXT is the exact characters to find.
A variable does not name a tab or a text. The rest of the screen is
not returned. The look does not type and does not run a command in
the tab. If Terminal.app is closed or does not answer within two
seconds, that text is skipped. A second notice does not add the same
fact again. Terminal.app exists only on macOS: any other host is refused
with NOTICE-REFUSED, and so is a context with no TERMINAL-SCREEN
reaction, or with none that names a tty and a text. Does not stay
listening, plan, or run adapters, and does not change an open listening
session. Returns the screen facts, including ones already present."
  (unless (macos-p)
    (%refuse-notice "A Terminal.app screen can be read only on macOS."))
  (unless (%modeled-type-p "TERMINAL-SCREEN")
    (%refuse-notice "No reaction in this context models a terminal screen."))
  (let ((targets (%reaction-targets "TERMINAL-SCREEN" 2
                                    #'%terminal-screen-target)))
    (unless targets
      (%refuse-notice "A terminal screen reaction needs a tty name and a text."))
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
            (let ((form (%modeled-form "TERMINAL-SCREEN"
                                       (car target) (cdr target))))
              (when (and form (%accept-notice form))
                (push form noticed))))))
      (nreverse noticed))))

(defvar *terminal-screen-watch* nil
  "The active Terminal.app screen watch, or NIL. One watch at a time.")

(defvar *terminal-screen-watch-lock*
  (sb-thread:make-mutex :name "automa-gp-terminal-screen-watch")
  "Guards the screen-watch slot and that watch. Not held during a look.")

(defun gp-terminal-screen-watch ()
  "True when a Terminal.app screen watch is running."
  (%notice-watch-active-p '*terminal-screen-watch* *terminal-screen-watch-lock*))

(defun gp-watch-terminal-screen (&key (interval 1))
  "Look at named Terminal.app tabs now, then again every INTERVAL seconds until stopped.
Each look is GP-NOTICE-TERMINAL-SCREEN. One screen watch at a time. A
text that appears later is noticed on a later look, when a reaction
already names it and Terminal.app answers. The watch keeps to the
context that is current now. A later look that signals is listed by
GP-WATCH-FAILURES. A host that is not macOS is refused and no watch
starts. The rest of the screen is not returned. The look does not type
and does not run a command in the tab. Does not plan or run adapters.
Returns the screen facts from the first look."
  (%begin-notice-watch
   '*terminal-screen-watch* *terminal-screen-watch-lock* interval
   "automa-gp-terminal-screen-watch"
   "A terminal screen watch is already running."
   (lambda ()
     (values (gp-notice-terminal-screen) #'gp-notice-terminal-screen nil))
   :join-slack 3))

(defun gp-stop-terminal-screen-watch ()
  "Stop the active Terminal.app screen watch and return the screen facts last seen.
The stop does not wait for the interval to pass. No watch is refused
with NOTICE-REFUSED."
  (%end-notice-watch '*terminal-screen-watch* *terminal-screen-watch-lock*
                     "No terminal screen watch is running."))

(defparameter *notice-watch-kinds*
  '((:directory-watch *directory-watch* *directory-watch-lock*)
    (:process-watch *process-watch* *process-watch-lock*)
    (:terminal-watch *terminal-watch* *terminal-watch-lock*)
    (:terminal-text-watch *terminal-text-watch* *terminal-text-watch-lock*)
    (:terminal-screen-watch *terminal-screen-watch* *terminal-screen-watch-lock*))
  "Each kind of watch: its name, its slot variable, and its lock variable.")

(defun gp-watch-failures ()
  "The running watches whose latest look signalled, or NIL when none did.
Each one is a plist (:WATCH kind :FAILED-LOOKS count :ERROR message).
KIND is :DIRECTORY-WATCH, :PROCESS-WATCH, :TERMINAL-WATCH,
:TERMINAL-TEXT-WATCH, or :TERMINAL-SCREEN-WATCH. COUNT is how many looks
in a row have signalled, and MESSAGE is what the latest one reported.
Such a watch keeps the facts of its last good look and keeps looking: a
look that succeeds again takes it off this list. A first look that
signals is not listed, because that watch never starts."
  (loop for (kind place lock) in *notice-watch-kinds*
        for failure = (sb-thread:with-mutex ((symbol-value lock))
                        (let ((watch (symbol-value place)))
                          (when (and watch (notice-watch-failure watch))
                            (list :watch kind
                                  :failed-looks (notice-watch-failed-looks watch)
                                  :error (notice-watch-failure watch)))))
        when failure
          collect failure))

(defun %stop-notice-watches ()
  "Stop every notice watch that is reserved or running.
A directory watch is included before its path is known. One kind does
not stop another."
  (loop for (nil place lock) in *notice-watch-kinds*
        do (handler-case
               (%end-notice-watch place (symbol-value lock)
                                  "That watch is not running.")
             (notice-refused () nil)))
  nil)
