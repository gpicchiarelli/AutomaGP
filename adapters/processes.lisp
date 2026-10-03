;;;; adapters/processes.lisp — process adapter (Phase 8)
;;;;
;;;; UIOP run-program wrappers. No process killing helpers in Phase 8.

(in-package #:automa-gp)

(defun run-program (command &key (output nil) (error-output nil)
                              (ignore-error-status nil)
                              (input nil)
                              (force-shell nil))
  "Abstract: run COMMAND via UIOP:RUN-PROGRAM and wait for it to end.
COMMAND is a list of strings, the program and its arguments, which reach
the program as they are. A string COMMAND is a shell command line, and
FORCE-SHELL hands a list to the shell as well: never build either from
data. OUTPUT, ERROR-OUTPUT and INPUT are passed to UIOP unchanged.
Returns (VALUES OUTPUT EXIT-CODE). OUTPUT may be a string when :OUTPUT :STRING.
A non-zero exit signals UIOP:SUBPROCESS-ERROR unless IGNORE-ERROR-STATUS."
  (multiple-value-bind (out err code)
      (uiop:run-program command
                        :output output
                        :error-output error-output
                        :ignore-error-status ignore-error-status
                        :input input
                        :force-shell force-shell)
    (declare (ignore err))
    (values out code)))

(defun current-process-id ()
  "PID of this Lisp image. SBCL only (the project target)."
  #+sbcl (sb-unix:unix-getpid)
  #-sbcl (error "CURRENT-PROCESS-ID is implemented for SBCL."))

(defun %argument-string (value)
  "VALUE as one argument of a program: a string as it is, a pathname as its
native namestring, an integer in decimal, any other real in fixed notation,
a symbol as its name. Signals ACTION-FAILED for NIL, for a variable no step
bound, and for any other object: none of them names an argument."
  (cond
    ((stringp value) value)
    ((pathnamep value) (uiop:native-namestring value))
    ((integerp value) (format nil "~D" value))
    ((realp value) (format nil "~F" value))
    ((null value)
     (%adapter-failure "NIL is not a program argument"))
    ((variable-symbol-p value)
     (%adapter-failure "the program argument ~S is an unbound variable"
                       value))
    ((symbolp value) (symbol-name value))
    (t
     (%adapter-failure "~S is not a program argument" value))))

(defun %command-argv (command)
  "COMMAND, a non-empty list, as the list of strings a program is run with.
Each element goes through %ARGUMENT-STRING. Signals ACTION-FAILED when
COMMAND is not such a list. A string would be a shell command line, and
the adapter never hands data to a shell."
  (unless (consp command)
    (%adapter-failure
     "a command is a list of the program and its arguments, not ~S"
     command))
  (mapcar #'%argument-string command))

(defun %lookup-finds-p (argv)
  "True when the lookup program ARGV (ps or pgrep) finds a process.
Both exit with 0 when they find one and with 1 when they find none. Any
other status means the lookup was not made, and is signalled as an ERROR
together with a program that could not be started."
  (let ((code (nth-value 1 (run-program argv
                                        :ignore-error-status t
                                        :output nil
                                        :error-output nil))))
    (case code
      (0 t)
      (1 nil)
      (t (error "~{~A~^ ~} ended with status ~S" argv code)))))

(defun process-running-p (name-or-pid)
  "Abstract: true if a process with PID (integer) or name (string/symbol) runs.
A PID is looked up with `ps -p`, which also sees the processes of other
users. An integer that is not positive is no PID and is never running.
A name is tried as the exact process name (`pgrep -x`), then anywhere in
a command line (`pgrep -f`); pgrep reads it as an extended regular
expression. The empty name is never running.
Returns NIL on error, with :UNKNOWN as a second value: the lookup could
not be made, which is not the same answer as not running."
  (handler-case
      (if (integerp name-or-pid)
          (and (plusp name-or-pid)
               (%lookup-finds-p
                (list "ps" "-p" (format nil "~D" name-or-pid) "-o" "pid=")))
          (let ((name (princ-to-string name-or-pid)))
            ;; "--" ends the options: a name that starts with "-" stays a name.
            (and (plusp (length name))
                 (or (%lookup-finds-p (list "pgrep" "-x" "--" name))
                     (%lookup-finds-p (list "pgrep" "-f" "--" name))))))
    (error () (values nil :unknown))))

(defun processes-dispatch (op args)
  "Dispatch process OP with ARGS plist. Returns a result plist.
:RUN runs :COMMAND, a list of the program and its arguments: strings,
pathnames, numbers and symbols, each handed to the program as one
argument. A string :COMMAND and a true :FORCE-SHELL are refused: nothing
that comes from a fact reaches a shell. :OK is true only for exit status
0; :IGNORE-ERROR-STATUS keeps a non-zero status from being signalled, so
the result still carries :OUTPUT and :EXIT-CODE, and does not turn it
into a success.
:RUNNING reports whether :NAME (a PID or a process name) is running.
Signals ACTION-FAILED for an OP this adapter does not have, for a missing
argument, for a command that is not such a list or asks for a shell, and
when the lookup of :RUNNING could not be made."
  (case op
    (:run
     (when (getf args :force-shell)
       (%adapter-failure
        "processes :RUN does not hand a command to a shell: ~
         :FORCE-SHELL is not accepted"))
     (multiple-value-bind (out code)
         (run-program (%command-argv
                       (%required-argument args :command :processes op))
                      :output (or (getf args :output) :string)
                      :error-output (getf args :error-output)
                      :ignore-error-status (getf args :ignore-error-status))
       (list :ok (eql code 0)
             :output out
             :exit-code code)))
    (:running
     (let ((name (%required-argument args :name :processes op)))
       (multiple-value-bind (running unknown) (process-running-p name)
         (when unknown
           (%adapter-failure "could not look up the process ~S" name))
         (list :ok t :running running))))
    (t
     (%adapter-failure "unknown processes op ~S" op))))

(register-adapter '(:processes :process) 'processes-dispatch)
