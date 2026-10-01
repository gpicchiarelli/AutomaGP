;;;; tests/test-modes.lisp

(in-package #:automa-gp/tests)

(def-suite modes-suite :in automa-gp-suite)
(in-suite modes-suite)

(test every-mode-is-normalized-from-any-package
  (dolist (mode *valid-modes*)
    (let ((plain (make-symbol (symbol-name mode))))
      (is-true (mode-p mode))
      (is-false (mode-p plain))
      (is (eq mode (ensure-mode mode)))
      (is (eq mode (ensure-mode plain)))
      (is (eq mode (context-mode (make-context :mode plain))))
      (is (eq (eq mode :execute) (mode-allows-mutation-p plain))))))

(test an-unknown-mode-is-a-typed-condition
  (dolist (bad (list :bogus 'bogus 42 "plan" nil))
    (signals unknown-keyword (ensure-mode bad))
    (signals unknown-keyword (mode-allows-mutation-p bad)))
  (signals unknown-keyword (make-context :mode :bogus))
  (handler-case (ensure-mode 'bogus)
    (type-error (c)
      (is (eq 'bogus (type-error-datum c)))
      (is (equal `(member ,@*valid-modes*) (type-error-expected-type c)))
      (is (equal "AUTOMA GP mode" (unknown-keyword-what c)))
      (is (search "Unknown AUTOMA GP mode" (princ-to-string c)))
      (is (search "BOGUS" (princ-to-string c))))))

(test use-value-replaces-an-unknown-mode
  ;; The replacement is checked in turn, so a second bad value is asked about
  ;; again.
  (let ((offers (list 'still-bogus 'simulate)))
    (is (eq :simulate
            (handler-bind ((unknown-keyword
                             (lambda (c)
                               (declare (ignore c))
                               (use-value (pop offers)))))
              (ensure-mode :bogus))))
    (is (null offers))))

(test a-refused-mode-is-not-interned-as-a-keyword
  (let ((name "NO-SUCH-AUTOMA-GP-MODE"))
    (signals unknown-keyword (ensure-mode (make-symbol name)))
    (is (null (find-symbol name :keyword)))))
