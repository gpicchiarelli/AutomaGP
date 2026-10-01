;;;; tests/test-docs.lisp — the Lisp examples in the documentation run

(in-package #:automa-gp/tests)

(def-suite docs-suite :in automa-gp-suite)
(in-suite docs-suite)

(defparameter *documents-with-examples*
  '("README.md"
    "docs/tavolo-di-lavoro.md"
    "docs/framework-pipeline-contesto.md")
  "Documents whose ```lisp blocks are session transcripts a reader can paste
into a REPL. docs/PROMPT.md and docs/PROMPT-FASE-2.md are specifications:
their blocks sketch notation and are not meant to run.")

(defun %lisp-blocks (text)
  "The contents of each ```lisp fenced block of TEXT, in order."
  (let ((open (format nil "```lisp~%"))
        (blocks nil)
        (start 0))
    (loop
      (let* ((at (search open text :start2 start))
             (begin (and at (+ at (length open))))
             (end (and begin (search "```" text :start2 begin))))
        (unless end
          (return (nreverse blocks)))
        (push (subseq text begin end) blocks)
        (setf start (+ end 3))))))

(defun %without-loading-lines (block)
  "BLOCK without the lines that load the system or change package: the
suite already runs in a loaded image, and Quicklisp may not be present."
  (with-output-to-string (out)
    (with-input-from-string (in block)
      (loop for line = (read-line in nil)
            while line
            do (let ((code (string-left-trim " " line)))
                 (unless (or (uiop:string-prefix-p "(ql:" code)
                             (uiop:string-prefix-p "(in-package" code))
                   (write-line line out)))))))

(defun %run-block (block)
  "Evaluate each form of BLOCK as if typed in the AUTOMA-GP package."
  (let ((*package* (find-package :automa-gp))
        (*read-eval* nil)
        (*standard-output* (make-broadcast-stream)))
    (with-input-from-string (in (%without-loading-lines block))
      (loop for form = (read in nil in)
            until (eq form in)
            do (eval form)))))

(test documented-examples-run
  "Every example block of the documents runs without an error, in order,
starting each document from a fresh session."
  (let ((*autonomy-policy* *autonomy-policy*))
    (unwind-protect
         (dolist (document *documents-with-examples*)
           (gp-clear-memory)
           (gp-reset)
           (let ((blocks (%lisp-blocks
                          (uiop:read-file-string
                           (asdf:system-relative-pathname :automa-gp document)))))
             (is (plusp (length blocks)) "~A has no Lisp example" document)
             (loop for block in blocks
                   for n from 1
                   do (let ((problem (handler-case (progn (%run-block block) nil)
                                       (error (e) (princ-to-string e)))))
                        (is (null problem)
                            "~A, example ~D: ~A" document n problem)))))
      (gp-clear-memory)
      (gp-reset))))
