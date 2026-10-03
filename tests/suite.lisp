;;;; tests/suite.lisp — root FiveAM suite and the entry point that runs it

(defpackage #:automa-gp/tests
  (:use #:cl #:automa-gp #:fiveam)
  (:local-nicknames (#:sem #:automa-gp/semantic))
  (:export #:run-tests
           #:automa-gp-suite))

(in-package #:automa-gp/tests)

(def-suite automa-gp-suite
  :description "Every AUTOMA GP test; each file adds its own child suite.")

(defun run-tests (&key (verbose (uiop:getenvp "AUTOMA_GP_TEST_VERBOSE")))
  "Run all AUTOMA GP tests; return T when every check passes, signal an
error otherwise. Prints the totals and every failure; with VERBOSE (or the
environment variable AUTOMA_GP_TEST_VERBOSE set) also one line per test.
Archive autosave/autoload stay off so the suite does not touch ~/.automa-gp."
  (let* ((*procedure-archive-autosave* nil)
         (*procedure-archive-autoload* nil)
         (results (let ((fiveam:*test-dribble* (if verbose
                                                   *standard-output*
                                                   (make-broadcast-stream))))
                    (run 'automa-gp-suite))))
    (explain! results)
    (unless (results-status results)
      (error "automa-gp tests failed"))
    t))
