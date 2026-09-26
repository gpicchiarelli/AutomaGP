;;;; tests/test-actions.lisp

(in-package #:automa-gp/tests)

(def-suite actions-suite :in automa-gp-suite)
(in-suite actions-suite)

(test register-and-applicability
  (let* ((ctx (create-context
               :name 'studio
               :facts '((device interface-01)
                        (power-state interface-01 off))))
         (act (make-action
               :name 'power-on
               :parameters '(device)
               :preconditions '((device interface-01)
                                (power-state interface-01 off))
               :effects '((power-state interface-01 on))
               :cost 1
               :risk :low
               :reversible t
               :adapter 'hardware
               :authorization 'operator)))
    (register-action! ctx act)
    (is (action-p (find-action ctx 'power-on)))
    (is-true (action-applicable-p ctx act))
    (setf (context-facts ctx)
          (remove-fact! (context-facts ctx) '(power-state interface-01 off)))
    (is-false (action-applicable-p ctx act))))

(test action-slots-present
  (let ((act (make-action :name 'n :parameters '(p) :preconditions '(pre)
                          :effects '(eff) :cost 2 :risk :high
                          :reversible nil :adapter 'a :authorization 'auth)))
    (is (eq 'n (action-name act)))
    (is (equal '(p) (action-parameters act)))
    (is (= 2 (action-cost act)))
    (is (eq :high (action-risk act)))
    (is-false (action-reversible act))
    (is (eq 'a (action-adapter act)))
    (is (eq 'auth (action-authorization act)))))
