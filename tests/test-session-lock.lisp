;;;; tests/test-session-lock.lisp — one lock for every thread that uses the session

(in-package #:automa-gp/tests)

(def-suite session-lock-suite :in automa-gp-suite)
(in-suite session-lock-suite)

(defun %in-thread (function)
  "Start a thread that calls FUNCTION; return (VALUES THREAD CELL), the
cell being a cons whose car is T and whose cdr holds the primary value once
the thread is done."
  (let ((cell (list nil)))
    (values (sb-thread:make-thread
             (lambda ()
               (let ((value (funcall function)))
                 (setf (cdr cell) value
                       (car cell) t))))
            cell)))

(test a-request-waits-for-whoever-holds-the-session
  "A web request takes turns with every other user of the session: while one
thread holds the session lock, the request is not answered; when it lets
go, the request is answered normally."
  (gp-reset)
  (multiple-value-bind (thread cell)
      (with-session-lock ()
        (multiple-value-bind (thread cell)
            (%in-thread (lambda ()
                          (nth-value 0 (web-api-handle :get "/api/status"))))
          (sleep 0.3)
          (is (null (car cell)) "the request was answered under the lock")
          (values thread cell)))
    (sb-thread:join-thread thread :timeout 5)
    (is (car cell))
    (is (= 200 (cdr cell)))))

(test a-watch-takes-turns-with-a-request
  "A noticed form does not enter the context while a request holds the
session, and does when the request is done."
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction (%test-file-reaction))
  (let ((form '(file-created "turn")))
    (multiple-value-bind (thread cell)
        (with-session-lock ()
          (multiple-value-bind (thread cell)
              (%in-thread (lambda () (automa-gp::%accept-notice form)))
            (sleep 0.3)
            (is (null (car cell)) "the form entered while the session was held")
            (is (null (gp-facts)))
            (values thread cell)))
      (sb-thread:join-thread thread :timeout 5)
      (is (eq t (cdr cell)))
      (is (fact-p form (gp-facts))))))

(test the-session-lock-is-taken-again-by-its-holder
  (is (eq :inner (with-session-lock ()
                   (with-session-lock (:timeout 0.1)
                     :inner)))))

(test a-turn-that-does-not-come-skips-the-body
  "With a timeout, a thread that cannot get the lock in time leaves its
body unrun, so a watch can look at its stop flag instead of waiting."
  (let ((ran nil))
    (with-session-lock ()
      (multiple-value-bind (thread cell)
          (%in-thread (lambda ()
                        (with-session-lock (:timeout 0.05)
                          (setf ran t))))
        (sb-thread:join-thread thread :timeout 5)
        (is (car cell) "the thread did not come back")
        (is (null ran) "the body ran without the lock")))
    (is (eq t (with-session-lock (:timeout 0.05) t)))))
