;;;; scripts/run-tests.lisp — load and run the AUTOMA GP tests under SBCL
;;;;
;;;; Invoked by scripts/run-tests.sh. Needs Quicklisp for FiveAM. The
;;;; checkout this file lives in is registered with ASDF ahead of any other
;;;; copy, so a second clone or a git worktree always tests itself.

(require :asdf)

#-quicklisp
(let ((ql (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (unless (probe-file ql)
    (error "Quicklisp setup not found: ~A" ql))
  (load ql))

(push (uiop:pathname-parent-directory-pathname
       (uiop:pathname-directory-pathname *load-truename*))
      asdf:*central-registry*)

(ql:quickload :automa-gp/tests :silent t)

(let ((ok (uiop:symbol-call :automa-gp/tests :run-tests)))
  (format t "~&automa-gp tests: ~A~%" (if ok "PASSED" "FAILED"))
  (uiop:quit (if ok 0 1)))
