;;;; scripts/run-tests.lisp — load and run AUTOMA GP tests under SBCL
;;;;
;;;; Invoked by scripts/run-tests.sh. Expects Quicklisp and the project
;;;; registered under ~/quicklisp/local-projects/automa-gp.

(require :asdf)

#-quicklisp
(let ((ql (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (unless (probe-file ql)
    (error "Quicklisp setup not found: ~A" ql))
  (load ql))

(ql:quickload :automa-gp/tests :silent t)

(let ((ok (automa-gp/tests:run-tests)))
  (format t "~&automa-gp tests: ~A~%" (if ok "PASSED" "FAILED"))
  (uiop:quit (if ok 0 1)))
