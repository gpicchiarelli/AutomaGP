;;;; domains/hardware/domain.lisp — devices, power, connections (Phase 9)
;;;;
;;;; Fact/predicate symbols are interned in #:automa-gp so REPL goals
;;;; written in that package unify with seeded facts and operators.

(in-package #:automa-gp/domain/hardware)

(defparameter *hardware-domain-name* :hardware)

(defun %tag-domains (context name)
  (let ((meta (copy-list (context-meta context))))
    (setf (getf meta :domains)
          (adjoin name (getf meta :domains) :test #'equal))
    (setf (context-meta context) meta)))

(defun %hardware-operators ()
  (list
   (make-operator
    :name 'automa-gp::power-on-device
    :preconditions '((automa-gp::device ?d) (automa-gp::power-state ?d automa-gp::off))
    :add-list '((automa-gp::power-state ?d automa-gp::on))
    :delete-list '((automa-gp::power-state ?d automa-gp::off))
    :meta (list :domain *hardware-domain-name*
                :ask '(accendi)))
   (make-operator
    :name 'automa-gp::connect-device
    :preconditions '((automa-gp::device ?d) (automa-gp::power-state ?d automa-gp::on))
    :add-list '((automa-gp::connection ?d automa-gp::host))
    :meta (list :domain *hardware-domain-name*))
   (make-operator
    :name 'automa-gp::configure-device
    :preconditions '((automa-gp::connection ?d automa-gp::host))
    :add-list '((automa-gp::device-configured ?d))
    :meta (list :domain *hardware-domain-name*))))

(defun %hardware-rules ()
  (list
   (make-rule :name 'automa-gp::device-ready
              :if '((automa-gp::device-configured ?d))
              :then '(automa-gp::peripheral-ready ?d)
              :meta (list :domain *hardware-domain-name*))))

(defun install-hardware-domain (context &key (seed-demo nil) &allow-other-keys)
  "Install hardware-domain operators/rules into CONTEXT."
  (unless (context-p context)
    (error "install-hardware-domain requires a context"))
  (dolist (op (%hardware-operators))
    (register-operator! context op))
  (dolist (r (%hardware-rules))
    (register-rule! context r))
  (when seed-demo
    (dolist (f '((automa-gp::device automa-gp::interface-01)
                 (automa-gp::power-state automa-gp::interface-01 automa-gp::off)))
      (setf (context-facts context)
            (add-fact! (context-facts context) f))))
  (%tag-domains context *hardware-domain-name*)
  context)

(defun hardware-demo-plan (context &key (device 'automa-gp::interface-01))
  "Seed device off and plan for (device-configured DEVICE)."
  (install-hardware-domain context)
  (setf (context-facts context)
        (add-fact! (context-facts context) (list 'automa-gp::device device)))
  (setf (context-facts context)
        (add-fact! (context-facts context)
                   (list 'automa-gp::power-state device 'automa-gp::off)))
  (plan-from-context context
                     :goals (list (list 'automa-gp::device-configured device))))
