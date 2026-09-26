;;;; domains/software/domain.lisp — projects, repos, build, test (Phase 9)
;;;;
;;;; Adds knowledge/operators/actions into a context. Optional :EXTERNAL
;;;; compile step uses Phase-8 run-program ("true") when adapters are on.
;;;; Predicates live in #:automa-gp for cross-package REPL planning.

(in-package #:automa-gp/domain/software)

(defparameter *software-domain-name* :software
  "Symbolic domain tag stored on installed operators' meta.")

(defun %tag-domains (context name)
  (let ((meta (copy-list (context-meta context))))
    (setf (getf meta :domains)
          (adjoin name (getf meta :domains) :test #'equal))
    (setf (context-meta context) meta)))

(defun %software-operators ()
  (list
   (make-operator
    :name 'automa-gp::fetch-repository
    :preconditions '((automa-gp::toolchain automa-gp::ready) (automa-gp::project ?p))
    :add-list '((automa-gp::repository-present ?p))
    :meta (list :domain *software-domain-name* :phase :acquire))
   (make-operator
    :name 'automa-gp::compile-project
    :preconditions '((automa-gp::repository-present ?p)
                     (automa-gp::toolchain automa-gp::ready))
    :add-list '((automa-gp::build-ok ?p))
    :meta (list :domain *software-domain-name*
                :phase :build
                :external (list :adapter :processes
                                :op :run
                                :args (list :command '("true")
                                            :ignore-error-status t))))
   (make-operator
    :name 'automa-gp::run-project-tests
    :preconditions '((automa-gp::build-ok ?p))
    :add-list '((automa-gp::tests-ok ?p))
    :meta (list :domain *software-domain-name* :phase :test))))

(defun %software-rules ()
  (list
   (make-rule :name 'automa-gp::project-verified
              :if '((automa-gp::tests-ok ?p))
              :then '(automa-gp::project-verified ?p)
              :meta (list :domain *software-domain-name*))))

(defun %software-actions ()
  (list
   (make-action :name 'automa-gp::fetch-repository
                :preconditions '((automa-gp::toolchain automa-gp::ready)
                                 (automa-gp::project ?p))
                :effects '((automa-gp::repository-present ?p))
                :adapter :processes)
   (make-action :name 'automa-gp::compile-project
                :preconditions '((automa-gp::repository-present ?p))
                :effects '((automa-gp::build-ok ?p))
                :adapter :processes)
   (make-action :name 'automa-gp::run-project-tests
                :preconditions '((automa-gp::build-ok ?p))
                :effects '((automa-gp::tests-ok ?p))
                :adapter :processes)))

(defun install-software-domain (&optional (context *current-context*)
                                &key (seed-demo t) &allow-other-keys)
  "Install software-domain operators, rules, and actions into CONTEXT.
When SEED-DEMO, assert (toolchain ready) if missing.
Returns CONTEXT."
  (unless (context-p context)
    (error "install-software-domain requires a context"))
  (dolist (op (%software-operators))
    (register-operator! context op))
  (dolist (r (%software-rules))
    (register-rule! context r))
  (dolist (a (%software-actions))
    (register-action! context a))
  (when seed-demo
    (unless (fact-p '(automa-gp::toolchain automa-gp::ready)
                    (context-all-facts context))
      (setf (context-facts context)
            (add-fact! (context-facts context)
                       '(automa-gp::toolchain automa-gp::ready)))))
  (%tag-domains context *software-domain-name*)
  context)

(defun software-demo-plan (&optional (context *current-context*)
                           &key (project 'automa-gp::myapp))
  "Seed a project fact and plan for (tests-ok PROJECT). Returns PLAN."
  (install-software-domain context :seed-demo t)
  (setf (context-facts context)
        (add-fact! (context-facts context)
                   (list 'automa-gp::project project)))
  (plan-from-context context
                     :goals (list (list 'automa-gp::tests-ok project))))
