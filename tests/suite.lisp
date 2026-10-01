;;;; tests/suite.lisp — root FiveAM suite and the entry point that runs it

(defpackage #:automa-gp/tests
  (:use #:cl #:automa-gp #:fiveam)
  (:export #:run-tests
           #:automa-gp-suite))

(in-package #:automa-gp/tests)

(def-suite automa-gp-suite
  :description "Every AUTOMA GP test; each file adds its own child suite.")

(defun run-tests ()
  "Run all AUTOMA GP tests; return T if all pass.
Archive autosave/autoload stay off so the suite does not touch ~/.automa-gp."
  (let ((*procedure-archive-autosave* nil)
        (*procedure-archive-autoload* nil))
    (let ((result (run! 'automa-gp-suite)))
      (unless result
        (error "automa-gp tests failed"))
      result)))
