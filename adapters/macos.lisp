;;;; adapters/macos.lisp — OS adapter dispatch (Phase 8)
;;;;
;;;; Keeps macOS/UIOP side effects out of MEA/planner. The executor calls
;;;; INVOKE-EXTERNAL-SPEC only when *INVOKE-ADAPTERS* is true (EXECUTE).

(in-package #:automa-gp)

;;; *INVOKE-ADAPTERS* is defined in core/executor.lisp (default NIL).

(defun macos-p ()
  "True when running on macOS (UIOP)."
  (uiop:os-macosx-p))

(defun adapter-hostname ()
  "Return the system hostname string."
  (string-trim '(#\Newline #\Return #\Space)
               (nth-value 0 (run-program '("hostname") :output :string))))

(defun adapter-uname ()
  "Return `uname -s` (e.g. Darwin)."
  (string-trim '(#\Newline #\Return #\Space)
               (nth-value 0 (run-program '("uname" "-s") :output :string))))

(defun adapter-open (target &key (wait nil))
  "macOS `open` TARGET (path or URL). Real side effect — use with care.
WAIT when true passes -W. Returns result plist."
  (unless (macos-p)
    (return-from adapter-open
      (list :ok nil :error :not-macos :target target)))
  (multiple-value-bind (out code)
      (run-program (if wait
                       (list "open" "-W" (princ-to-string target))
                       (list "open" (princ-to-string target)))
                   :output :string
                   :ignore-error-status t)
    (list :ok (eql code 0) :exit-code code :output out :target target)))

(defun macos-dispatch (op args)
  (ecase op
    (:hostname (list :ok t :hostname (adapter-hostname)))
    (:uname (list :ok t :uname (adapter-uname)))
    (:macos-p (list :ok t :macos (macos-p)))
    (:open (adapter-open (getf args :target) :wait (getf args :wait)))))

;;; ---------------------------------------------------------------------------
;;; External specs on operators
;;; ---------------------------------------------------------------------------

(defun substitute-external-tree (tree bindings)
  "Replace variable symbols in TREE using BINDINGS (planner bindings)."
  (cond
    ((and (symbolp tree) (variable-symbol-p tree))
     (let ((pair (lookup-binding tree bindings)))
       (if pair (cdr pair) tree)))
    ((consp tree)
     (cons (substitute-external-tree (car tree) bindings)
           (substitute-external-tree (cdr tree) bindings)))
    (t tree)))

(defun operator-external-spec (operator)
  "Return the :EXTERNAL plist from OPERATOR meta, or NIL."
  (when (operator-p operator)
    (getf (operator-meta operator) :external)))

(defun invoke-external-spec (spec bindings)
  "Run an external SPEC (:ADAPTER :OP :ARGS …) with BINDINGS substituted.
Signals ACTION-FAILED on unknown adapter or failed :OK NIL (unless :SOFT T)."
  (let* ((adapter (getf spec :adapter))
         (op (getf spec :op))
         (args (substitute-external-tree (copy-tree (getf spec :args)) bindings))
         (soft (getf spec :soft))
         (result
          (handler-case
              (ecase adapter
                ((:filesystem :fs) (filesystem-dispatch op args))
                ((:processes :process) (processes-dispatch op args))
                ((:macos :os) (macos-dispatch op args)))
            (error (e)
              (list :ok nil :error (format nil "~A" e) :adapter adapter :op op)))))
    (unless (or soft (getf result :ok))
      (error 'action-failed
             :reason (or (getf result :error)
                         (format nil "adapter ~A op ~A failed: ~S"
                                 adapter op result))))
    result))

(defun maybe-invoke-external! (operator bindings)
  "If *INVOKE-ADAPTERS* and OPERATOR has :EXTERNAL meta, invoke it.
Returns the adapter result plist, or NIL when skipped."
  (when *invoke-adapters*
    (let ((spec (operator-external-spec operator)))
      (when spec
        (invoke-external-spec spec bindings)))))

(defun with-adapters-enabled (fn)
  "Call FN with *INVOKE-ADAPTERS* bound to T."
  (let ((*invoke-adapters* t))
    (funcall fn)))
