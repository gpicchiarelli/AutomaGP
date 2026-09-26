;;;; adapters/processes.lisp — process adapter (Phase 8)
;;;;
;;;; UIOP run-program wrappers. No process killing helpers in Phase 8.

(in-package #:automa-gp)

(defun run-program (command &key (output nil) (error-output nil)
                              (ignore-error-status nil)
                              (input nil)
                              (force-shell nil))
  "Abstract: run COMMAND (string or list) via UIOP:RUN-PROGRAM.
Returns (VALUES OUTPUT EXIT-CODE). OUTPUT may be a string when :OUTPUT :STRING."
  (let ((out-arg (case output
                   ((nil) nil)
                   ((:string :interactive) output)
                   (t output)))
        (err-arg (case error-output
                   ((nil) nil)
                   ((:string :interactive :output) error-output)
                   (t error-output))))
    (multiple-value-bind (out err code)
        (uiop:run-program command
                          :output out-arg
                          :error-output err-arg
                          :ignore-error-status ignore-error-status
                          :input input
                          :force-shell force-shell)
      (declare (ignore err))
      (values out code))))

(defun current-process-id ()
  "PID of this Lisp image. SBCL only (the project target)."
  #+sbcl (sb-unix:unix-getpid)
  #-sbcl (error "CURRENT-PROCESS-ID is implemented for SBCL."))

(defun process-running-p (name-or-pid)
  "Abstract: true if a process with PID (integer) or name (string/symbol) runs.
Uses kill -0 for PIDs; for names tries `pgrep -x` then `pgrep -f`.
Returns NIL on error."
  (handler-case
      (cond
        ((integerp name-or-pid)
         (zerop
          (nth-value 1
                     (run-program
                      (list "kill" "-0" (princ-to-string name-or-pid))
                      :ignore-error-status t
                      :output nil
                      :error-output nil))))
        (t
         (let ((name (princ-to-string name-or-pid)))
           (or (zerop
                (nth-value 1
                           (run-program (list "pgrep" "-xq" name)
                                        :ignore-error-status t
                                        :output nil
                                        :error-output nil)))
               (zerop
                (nth-value 1
                           (run-program (list "pgrep" "-fq" name)
                                        :ignore-error-status t
                                        :output nil
                                        :error-output nil)))))))
    (error () nil)))

(defun processes-dispatch (op args)
  "Dispatch process OP with ARGS plist. Returns a result plist."
  (ecase op
    (:run
     (multiple-value-bind (out code)
         (run-program (getf args :command)
                      :output (or (getf args :output) :string)
                      :error-output (getf args :error-output)
                      :ignore-error-status
                      (getf args :ignore-error-status)
                      :force-shell (getf args :force-shell))
       (list :ok (or (getf args :ignore-error-status) (eql code 0))
             :output out
             :exit-code code)))
    (:running
     (list :ok t
           :running (process-running-p (getf args :name))))))
