;;;; automa-gp.asd — AUTOMA GP ASDF system definition
;;;;
;;;; Phases 1–6 load through explanation + conditions + executor + REPL.
;;;; Later-phase files exist as scaffolds and are NOT components yet.

(defsystem "automa-gp"
  :description "AUTOMA GP — context-centric symbolic deliberative automaton"
  :author "Giacomo Picchiarelli <gpicchiarelli@gmail.com>"
  :license "BSD-2-Clause"
  :version (:read-file-form "version.lisp-expr")
  :depends-on ("uiop")
  :serial t
  :components ((:file "packages")
               (:file "version")
               (:module "core"
                :serial t
                :components ((:file "modes")
                             (:file "matcher")
                             (:file "unification")
                             (:file "facts")
                             (:file "context")
                             (:file "state")
                             (:file "goals")
                             (:file "actions")
                             (:file "rules")
                             (:file "queries")
                             (:file "operators")
                             (:file "explanation")
                             (:file "mea")
                             (:file "planner")
                             (:file "conditions")
                             (:file "executor")))
               (:module "interface"
                :serial t
                :components ((:file "repl"))))
  :in-order-to ((test-op (test-op "automa-gp/tests"))))

(defsystem "automa-gp/tests"
  :description "Tests for AUTOMA GP"
  :author "Giacomo Picchiarelli <gpicchiarelli@gmail.com>"
  :license "BSD-2-Clause"
  :depends-on ("automa-gp" "fiveam")
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "suite")
                             (:file "test-context")
                             (:file "test-facts")
                             (:file "test-state")
                             (:file "test-goals")
                             (:file "test-actions")
                             (:file "test-matcher")
                             (:file "test-unification")
                             (:file "test-rules")
                             (:file "test-queries")
                             (:file "test-operators")
                             (:file "test-mea")
                             (:file "test-planner")
                             (:file "test-executor")
                             (:file "test-conditions")
                             (:file "test-explanation")
                             (:file "test-tavolo")
                             (:file "test-framework-pipeline")
                             (:file "test-repl"))))
  :perform (test-op (op c)
             (symbol-call :automa-gp/tests :run-tests)))
