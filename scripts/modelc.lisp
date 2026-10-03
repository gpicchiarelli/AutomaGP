;;;; scripts/modelc.lisp — the modelc command line
;;;;
;;;; Invoked by scripts/modelc with the arguments of the command after the
;;;; end of the toplevel options. Loads the system of this checkout through
;;;; ASDF, so a second clone or a git worktree always runs itself.

(require :asdf)

#-quicklisp
(let ((ql (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file ql)
    (load ql)))

(push (uiop:pathname-parent-directory-pathname
       (uiop:pathname-directory-pathname *load-truename*))
      asdf:*central-registry*)

(defun run ()
  "The exit status of the command in the arguments. A failure the command
does not report itself is reported here, in a line, with status 1: a
command line gives a message, not a backtrace. A closed pipe, as in
`modelc standard list | head`, ends the command quietly."
  (handler-case
      (handler-bind ((warning #'muffle-warning))
        ;; Compiler chatter goes to the error stream: stdout is the output.
        (let ((*standard-output* *error-output*))
          (asdf:load-system :automa-gp/semantic))
        (prog1 (uiop:symbol-call :automa-gp/semantic :modelc-main
                                 (uiop:command-line-arguments))
          (finish-output)))
    (stream-error () 141)
    (error (condition)
      (format *error-output* "modelc: ~A~%" condition)
      1)))

(uiop:quit (run))
