;;;; automa-gp.asd — AUTOMA GP ASDF system definition
;;;;
;;;; Phases 1–12: core + autonomy + optional Hunchentoot web system.

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
                             (:file "induction")
                             (:file "explanation")
                             (:file "mea")
                             (:file "planner")
                             (:file "conditions")
                             (:file "executor")
                             (:file "events")))
               (:module "adapters"
                :serial t
                :components ((:file "filesystem")
                             (:file "processes")
                             (:file "macos")))
               (:module "memory"
                :serial t
                :components ((:file "working")
                             (:file "knowledge")
                             (:file "episodic")
                             (:file "procedural")
                             (:file "persistence")))
               ;; Autonomy needs planner + memory; load after both.
               (:file "autonomy" :pathname "core/autonomy")
               (:module "domains"
                :serial t
                :components ((:module "software"
                              :serial t
                              :components ((:file "package")
                                           (:file "domain")))
                             (:module "documents"
                              :serial t
                              :components ((:file "package")
                                           (:file "domain")))
                             (:module "hardware"
                              :serial t
                              :components ((:file "package")
                                           (:file "domain")))
                             (:module "music"
                              :serial t
                              :components ((:file "package")
                                           (:file "domain")))
                             (:module "geometry"
                              :serial t
                              :components ((:file "package")
                                           (:file "domain")))
                             (:file "registry")))
               (:module "interface"
                :serial t
                :components ((:file "repl")
                             (:file "notice")
                             (:file "ask")
                             (:file "narration")
                             (:file "json")
                             (:file "web-api"))))
  :in-order-to ((test-op (test-op "automa-gp/tests"))))

(defsystem "automa-gp/web"
  :description "Optional Hunchentoot operator console for AUTOMA GP"
  :author "Giacomo Picchiarelli <gpicchiarelli@gmail.com>"
  :license "BSD-2-Clause"
  :version (:read-file-form "version.lisp-expr")
  :depends-on ("automa-gp" "hunchentoot")
  :serial t
  :components ((:module "interface"
                :serial t
                :components ((:file "web")))))

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
                             (:file "test-workbench")
                             (:file "test-tavolo")
                             (:file "test-framework-pipeline")
                             (:file "test-memory")
                             (:file "test-persistence")
                             (:file "test-adapters")
                             (:file "test-domains")
                             (:file "test-events")
                             (:file "test-web")
                             (:file "test-autonomy")
                             (:file "test-archive")
                             (:file "test-repl"))))
  :perform (test-op (op c)
             (symbol-call :automa-gp/tests :run-tests)))
