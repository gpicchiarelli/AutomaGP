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

;; AUTOMA_GP_TEST_SCOPE=web runs the console tests over a loopback socket
;; (system automa-gp/web-tests, which needs Hunchentoot); anything else, or
;; nothing, runs the suite of the core.
(let* ((web (equal (uiop:getenvp "AUTOMA_GP_TEST_SCOPE") "web"))
       (system (if web :automa-gp/web-tests :automa-gp/tests))
       (runner (if web :run-web-tests :run-tests)))
  (ql:quickload system :silent t)
  ;; RUN-TESTS prints the failures and then signals; the exit code carries
  ;; the outcome, so no backtrace is wanted here.
  (let ((ok (handler-case (uiop:symbol-call :automa-gp/tests runner)
              (error () nil))))
    (format t "~&automa-gp ~:[tests~;console tests~]: ~A~%" web
            (if ok "PASSED" "FAILED"))
    (uiop:quit (if ok 0 1))))
