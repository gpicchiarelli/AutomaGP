;;;; tests/test-state.lisp

(in-package #:automa-gp/tests)

(def-suite state-suite :in automa-gp-suite)
(in-suite state-suite)

(test state-from-context-and-compare
  (let* ((ctx (create-context :name 's
                              :facts '((a 1) (b 2))))
         (st (state-from-context ctx))
         (st2 (make-instance 'state :facts '((b 2) (a 1)))))
    (is (state-p st))
    (is (state-equal st st2))
    (let ((diff (compare-states st (make-instance 'state :facts '((a 1))))))
      (is (equal '((b 2)) (getf diff :facts-only-in-a)))
      (is-false (getf diff :equal)))))
