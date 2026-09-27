;;;; tests/suite.lisp — FiveAM suite for AUTOMA GP Phase 1

(defpackage #:automa-gp/tests
  (:use #:cl #:automa-gp #:fiveam)
  (:export #:run-tests
           #:automa-gp-suite))

(in-package #:automa-gp/tests)

(def-suite automa-gp-suite
  :description "AUTOMA GP Phase 1 tests")

(defun run-tests ()
  "Run all AUTOMA GP tests; return T if all pass.
Archive autosave/autoload stay off so the suite does not touch ~/.automa-gp."
  (let ((*procedure-archive-autosave* nil)
        (*procedure-archive-autoload* nil))
    (let ((result (run! 'automa-gp-suite)))
      (unless result
        (error "automa-gp tests failed"))
      result)))
