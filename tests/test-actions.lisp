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

(test applicability-needs-one-consistent-set-of-bindings
  ;; Each case is (FACTS PRECONDITIONS APPLICABLE).
  (loop for (facts preconditions applicable)
          in '(;; ?x must name the same thing in both preconditions
               (((lamp on) (door ready)) ((?x on) (?x ready)) nil)
               (((lamp on) (lamp ready)) ((?x on) (?x ready)) t)
               ;; the first fact that matches (?x on) is not the one that works
               (((lamp on) (door on) (door ready)) ((?x on) (?x ready)) t)
               (((lamp on) (door ready)) ((?x on) (?y ready)) t)
               (((lamp on)) ((? on)) t)
               (((lamp on)) ((lamp on) nil) t)
               (((lamp on)) () t)
               (() ((lamp on)) nil)
               (((lamp on)) ((lamp off)) nil)
               (((lamp on)) (ready) nil))
        do (let ((ctx (create-context :facts facts))
                 (act (make-action :name 'probe :preconditions preconditions)))
             (is (eq applicable (action-applicable-p ctx act))
                 "~S against ~S should be ~:[inapplicable~;applicable~]"
                 preconditions facts applicable))))

(test applicability-sees-inherited-facts
  (let* ((parent (create-context :facts '((lamp on))))
         (child (create-context :parent parent :facts '((lamp ready))))
         (act (make-action :name 'probe :preconditions '((?x on) (?x ready)))))
    (is-true (action-applicable-p child act))
    (is-false (action-applicable-p parent act))))

(test make-action-requires-a-name
  (signals type-error (make-action :effects '((done))))
  (is (eq 'named
          (action-name
           (handler-bind ((type-error (lambda (c)
                                        (declare (ignore c))
                                        (store-value 'named))))
             (make-action :effects '((done))))))))

(test registering-an-action-again-replaces-it
  (let ((ctx (create-context))
        (old (make-action :name 'power-on :cost 1))
        (new (make-action :name 'power-on :cost 2)))
    (register-action! ctx old)
    (register-action! ctx (make-action :name 'other))
    (is (eq new (register-action! ctx new)))
    (is (eq new (find-action ctx 'power-on)))
    (is (= 2 (length (actions-of ctx))))
    (is (null (find-action ctx 'missing)))))
