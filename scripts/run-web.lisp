;;;; scripts/run-web.lisp — start the AUTOMA GP operator console under SBCL
;;;;
;;;; Invoked by scripts/run-web.sh. Needs Quicklisp for Hunchentoot. The
;;;; checkout this file lives in is registered with ASDF ahead of any other
;;;; copy. The port comes from AUTOMA_GP_WEB_PORT (default 47391).

(require :asdf)

#-quicklisp
(let ((ql (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (unless (probe-file ql)
    (error "Quicklisp setup not found: ~A" ql))
  (load ql))

(push (uiop:pathname-parent-directory-pathname
       (uiop:pathname-directory-pathname *load-truename*))
      asdf:*central-registry*)

(ql:quickload :automa-gp/web :silent t)

(let ((port (parse-integer (or (uiop:getenvp "AUTOMA_GP_WEB_PORT") "47391"))))
  (uiop:symbol-call :automa-gp/web :start-web :port port)
  (format t "~&Serving until Ctrl-C. URL: ~A~%"
          (uiop:symbol-call :automa-gp/web :web-url))
  (handler-case (loop (sleep 3600))
    (sb-sys:interactive-interrupt ()
      (uiop:symbol-call :automa-gp/web :stop-web)
      (uiop:quit 0))))
