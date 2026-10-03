;;;; domains/software/domain.lisp — projects, repos, build, test (Phase 9)
;;;;
;;;; Adds knowledge/operators/actions into a context. Optional :EXTERNAL
;;;; compile step uses Phase-8 run-program ("true") when adapters are on.
;;;; Predicates live in #:automa-gp for cross-package REPL planning.

(in-package #:automa-gp/domain/software)

(defparameter *software-domain-name* :software
  "Symbolic domain tag stored on installed operators' meta.")

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

(defun %software-actions (operators)
  "One ACTION for each operator of OPERATORS, built from the operator:
its preconditions, its add list as effects, its cost, risk and
reversibility. :ADAPTER is the adapter of the operator's :EXTERNAL spec,
and NIL for an operator that only changes facts. The two descriptions of
a step cannot disagree, because only one of them is written down."
  (loop for operator in operators
        collect (make-action
                 :name (operator-name operator)
                 :preconditions (operator-preconditions operator)
                 :effects (operator-add-list operator)
                 :cost (operator-cost operator)
                 :risk (operator-risk operator)
                 :reversible (operator-reversible operator)
                 :adapter (getf (operator-external-spec operator) :adapter))))

(defun install-software-domain (context &key (seed-demo t) &allow-other-keys)
  "Install software-domain operators, rules, and actions into CONTEXT.
When SEED-DEMO, assert (toolchain ready) if missing.
Returns CONTEXT."
  (let ((operators (%software-operators)))
    (install-domain-pack
     context *software-domain-name*
     :operators operators
     :rules (%software-rules)
     :actions (%software-actions operators)
     :facts (when seed-demo
              '((automa-gp::toolchain automa-gp::ready))))))

(defun software-demo-plan (context &key (project 'automa-gp::myapp))
  "Seed a project fact and plan for (tests-ok PROJECT). Returns PLAN."
  (install-software-domain context :seed-demo t)
  (context-add-fact! context (list 'automa-gp::project project))
  (plan-from-context context
                     :goals (list (list 'automa-gp::tests-ok project))))
