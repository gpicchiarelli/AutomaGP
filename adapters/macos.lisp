;;;; adapters/macos.lisp — OS adapter dispatch (Phase 8)
;;;;
;;;; Keeps macOS/UIOP side effects out of the core. The adapter registers
;;;; MACOS-DISPATCH under :MACOS and :OS (see core/external.lisp); naming and
;;;; gating the external actions of a plan is core/external.lisp as well.

(in-package #:automa-gp)

;;; *INVOKE-ADAPTERS* is defined in core/executor.lisp (default NIL).

(defun macos-p ()
  "True when running on macOS (UIOP)."
  (uiop:os-macosx-p))

(defun adapter-hostname ()
  "Return the system hostname string."
  (uiop:hostname))

(defun adapter-uname ()
  "Return the name of the operating system as `uname -s` prints it
(e.g. Darwin). Asks the Lisp image; no process is run."
  (software-type))

(defun adapter-open (target &key (wait nil))
  "macOS `open` TARGET (path or URL). Real side effect — use with care.
WAIT when true passes -W. TARGET is handed to `open` as one argument after
\"--\", so a target that starts with \"-\" is not read as an option.
Returns result plist; on another system :OK is NIL and nothing is run."
  (unless (macos-p)
    (return-from adapter-open
      (list :ok nil :error :not-macos :target target)))
  (multiple-value-bind (out code)
      (run-program `("open" ,@(when wait '("-W"))
                            "--" ,(%argument-string target))
                   :output :string
                   :ignore-error-status t)
    (list :ok (eql code 0) :exit-code code :output out :target target)))

(defun macos-dispatch (op args)
  "Dispatch macOS OP with ARGS plist. Returns a result plist.
Signals ACTION-FAILED for an OP this adapter does not have and for an
:OPEN without a :TARGET."
  (case op
    (:hostname (list :ok t :hostname (adapter-hostname)))
    (:uname (list :ok t :uname (adapter-uname)))
    (:macos-p (list :ok t :macos (macos-p)))
    (:open (adapter-open (%required-argument args :target :macos op)
                         :wait (getf args :wait)))
    (t (%adapter-failure "unknown macos op ~S" op))))

(register-adapter '(:macos :os) 'macos-dispatch)
