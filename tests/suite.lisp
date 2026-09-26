;;;; tests/suite.lisp — FiveAM suite for AUTOMA GP Phase 1

(defpackage #:automa-gp/tests
  (:use #:cl #:automa-gp #:fiveam)
  (:export #:run-tests
           #:automa-gp-suite))

(in-package #:automa-gp/tests)

(def-suite automa-gp-suite
  :description "AUTOMA GP Phase 1 tests")

(defun run-tests ()
  "Run all AUTOMA GP tests; return T if all pass."
  (let ((result (run! 'automa-gp-suite)))
    (unless result
      (error "automa-gp tests failed"))
    result))
