;;;; scripts/coverage.lisp — expression and branch coverage of the suite
;;;;
;;;; Invoked by `make coverage`. Compiles automa-gp with SB-COVER
;;;; instrumentation into coverage/fasl/ (the normal fasl cache is left
;;;; alone), runs the FiveAM suite, and writes an HTML report to
;;;; coverage/report/cover-index.html. SBCL only.

(require :asdf)
(require :sb-cover)

#-quicklisp
(let ((ql (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (unless (probe-file ql)
    (error "Quicklisp setup not found: ~A" ql))
  (load ql))

(defparameter *root*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname *load-truename*)))

(push *root* asdf:*central-registry*)

;; Dependencies compile uninstrumented, into the normal cache.
(ql:quickload '(:fiveam) :silent t)

;; This tree compiles into coverage/fasl/ so instrumented fasls never
;; reach the cache that `make test` and the REPL use.
(asdf:initialize-output-translations
 `(:output-translations
   ((,*root* :**/ :*.*.*)
    (,(merge-pathnames "coverage/fasl/" *root*) :**/ :*.*.*))
   :inherit-configuration))

(declaim (optimize sb-cover:store-coverage-data))
(asdf:load-system :automa-gp :force t)
(asdf:load-system :automa-gp/semantic :force t)
(declaim (optimize (sb-cover:store-coverage-data 0)))
(asdf:load-system :automa-gp/tests :force t)

(defun cell-values (html start count)
  "The contents of the next COUNT <td> cells of HTML after position START."
  (loop repeat count
        for open = (search "<td>" html :start2 start)
        for close = (and open (search "</td>" html :start2 open))
        while close
        collect (string-trim " " (subseq html (+ open 4) close))
        do (setf start close)))

(defun print-summary (index)
  "Sum the per-file rows of SB-COVER's index page and print the totals.
SB-COVER exposes no totals of its own, so they are read from its report."
  (let ((html (uiop:read-file-string index))
        (marker ".lisp</a></td>")
        (expressions 0) (expressions-total 0) (branches 0) (branches-total 0))
    (loop for at = (search marker html) then (search marker html :start2 (1+ at))
          while at
          do (destructuring-bind (e e-total e-percent b b-total b-percent)
                 (cell-values html at 6)
               (declare (ignore e-percent b-percent))
               (incf expressions (parse-integer e))
               (incf expressions-total (parse-integer e-total))
               (incf branches (parse-integer b))
               (incf branches-total (parse-integer b-total))))
    (format t "~&coverage: expressions ~D/~D (~,1F%), branches ~D/~D (~,1F%)~%"
            expressions expressions-total
            (* 100.0 (/ expressions (max 1 expressions-total)))
            branches branches-total
            (* 100.0 (/ branches (max 1 branches-total))))))

(let ((ok (uiop:symbol-call :automa-gp/tests :run-tests))
      (report (merge-pathnames "coverage/report/" *root*)))
  (ensure-directories-exist report)
  (let ((*standard-output* (make-broadcast-stream)))
    (sb-cover:report report))
  (let ((index (merge-pathnames "cover-index.html" report)))
    (print-summary index)
    (format t "~&coverage report: ~A~%" index))
  (uiop:quit (if ok 0 1)))
