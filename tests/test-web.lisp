;;;; tests/test-web.lisp — Phase 11 web API (no browser / no live server)

(in-package #:automa-gp/tests)

(def-suite web-suite :in automa-gp-suite)
(in-suite web-suite)

(test json-roundtrip-basics
  (is (string= "true" (lisp->json t)))
  (is (string= "false" (lisp->json nil)))
  (is (string= "null" (lisp->json :null)))
  (is (string= "[]" (lisp->json (json-array nil))))
  (is (equalp #(1 2 3) (json->lisp "[1,2,3]")))
  (let ((obj (json->lisp "{\"seed_demo\":true,\"domain\":\"documents\"}")))
    (is (eq t (getf obj :seed-demo)))
    (is (string= "documents" (getf obj :domain))))
  (is (equal '(automa-gp::file-created "document.pdf")
             (json->sexp '("file-created" "document.pdf")))))

(test web-api-status-and-reset
  (gp-clear-memory)
  (gp-reset)
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/status")
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (is (string= "0.16.0" (getf body :api)))
    (is (null (getf body :plan-p)))
    (is (null (getf body :plan-success)))
    (is (= 0 (getf body :open-goals)))
    (is (= 0 (getf body :pending-events)))
    (is (= 0 (getf body :goals)))
    (is (= 0 (getf body :events))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/reset")
    (is (= 200 code))
    (is (eq t (getf body :ok)))))

(test operator-console-disables-until-ready
  "HTML console mirrors workbench gates from /api/status."
  (let* ((path (asdf:system-relative-pathname :automa-gp "interface/web.lisp"))
         (src (uiop:read-file-string path)))
    (is (search "btnSim" src))
    (is (search "btnRemember" src))
    (is (search "btnPlan" src))
    (is (search "btnUse" src))
    (is (search "btnReact" src))
    (is (search "btnEmit" src))
    (is (search "btnFact" src))
    (is (search "plan-success" src))
    (is (search "open-goals" src))
    (is (search "pending-events" src))
    (is (search "plan-open-goals" src))
    (is (search "updatePlanButton" src))
    (is (search "updateArchiveButtons" src))
    (is (search "/api/archive?applies=1" src))
    (is (search "updateEmitFactButtons" src))
    (is (search "validJsonArray" src))
    (is (search "namedProcedureExists" src))
    (is (search "namedProcedureApplies" src))
    (is (search "typedGoalsAllHold" src))
    (is (search "normalizeGoalsInput" src))
    (is (search "setDisabled('btnPlan'" src))
    (is (search "setDisabled('btnSim'" src))
    (is (search "setDisabled('btnRun'" src))
    (is (search "external-matches" src))
    (is (search "external-supported" src))
    (is (search "canSimRun" src))
    (is (search "setDisabled('btnRemember'" src))
    (is (search "setDisabled('btnReact'" src))
    (is (search "setDisabled('btnEmit'" src))
    (is (search "setDisabled('btnFact'" src))
    (is (search "setDisabled('btnUse'" src))
    (is (search "found.applies" src))
    (is (search "setDisabled('btnScoreOk'" src))
    (is (search "setDisabled('btnScoreFail'" src))
    (is (search "setDisabled('btnAutoStep'" src))
    (is (search "setDisabled('btnAutoLoop'" src))))

(test web-api-archive-query-helpers
  (multiple-value-bind (p q)
      (automa-gp::%split-path-query "/api/archive?applies=1")
    (is (string= "/api/archive" p))
    (is (string= "applies=1" q)))
  (is (null (nth-value 1 (automa-gp::%split-path-query "/api/archive"))))
  (is-true (automa-gp::%query-has-flag "applies=1" "applies"))
  (is-true (automa-gp::%query-has-flag "foo=1&applies=true" "applies"))
  (is-false (automa-gp::%query-has-flag "mapplies=1" "applies"))
  (is-false (automa-gp::%query-has-flag "applies=0" "applies"))
  (is-true (automa-gp::%api-flag t))
  (is-true (automa-gp::%api-flag "1"))
  (is-false (automa-gp::%api-flag :null))
  (is-false (automa-gp::%api-flag 0)))

(test web-api-archive-applies-cache-survives-identical-snapshot
  (gp-clear-memory)
  (gp-reset)
  (setf automa-gp::*applies-result-cache* nil)
  (web-api-handle :post "/api/load-domain"
                  '(:domain "hardware" :seed-demo t))
  (web-api-handle :post "/api/plan"
                  (list :goals '(("device-configured" "interface-01"))))
  (web-api-handle :post "/api/archive/remember" '(:name "connect-hw"))
  (multiple-value-bind (code1 body1)
      (web-api-handle :get "/api/archive?applies=1")
    (is (= 200 code1))
    (is (eq t (getf (first (coerce (getf body1 :procedures) 'list)) :applies)))
    (is (not (null automa-gp::*applies-result-cache*))))
  (multiple-value-bind (code2 body2)
      (web-api-handle :get "/api/archive?applies=1")
    (is (= 200 code2))
    (is (eq t (getf (first (coerce (getf body2 :procedures) 'list)) :applies))))
  (web-api-handle :post "/api/archive/score"
                  '(:name "connect-hw" :success nil))
  (multiple-value-bind (code3 body3)
      (web-api-handle :get "/api/archive?applies=1")
    (is (= 200 code3))
    (is (eq t (getf (first (coerce (getf body3 :procedures) 'list)) :applies))))
  (is (not (null automa-gp::*applies-result-cache*)))
  (gp-reset)
  (is (null automa-gp::*applies-result-cache*)))

(test web-api-status-open-goals-and-pending-events
  (gp-clear-memory)
  (gp-reset)
  (gp-add-goal '(power-state interface-01 on))
  (gp-add-fact '(power-state interface-01 off))
  (gp-emit '(automa-gp::file-created "brief.pdf"))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/status")
    (is (= 200 code))
    (is (= 1 (getf body :goals)))
    (is (= 1 (getf body :open-goals)))
    (is (= 1 (getf body :events)))
    (is (= 1 (getf body :pending-events))))
  (gp-remove-fact '(power-state interface-01 off))
  (gp-add-fact '(power-state interface-01 on))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/status")
    (is (= 200 code))
    (is (= 1 (getf body :goals)))
    (is (= 0 (getf body :open-goals)))
    (is (= 1 (getf body :events)))
    (is (= 1 (getf body :pending-events)))))

(test web-api-domain-emit-plan-flow
  (gp-clear-memory)
  (gp-reset)
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/load-domain"
                      '(:domain "documents" :seed-demo t))
    (is (= 200 code))
    (is (eq t (getf body :ok))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/emit"
                      (list :event '("file-created" "document.pdf")
                            :react t :plan t))
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (let ((plan (getf body :plan)))
      (is (not (eq plan :null)))
      (is (eq t (getf plan :success)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/plan")
    (is (= 200 code))
    (is (eq t (getf (getf body :plan) :success))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/events")
    (is (= 200 code))
    (is (= 1 (length (coerce (getf body :events) 'list))))))

(test web-api-goal-directed-plan
  (gp-clear-memory)
  (gp-reset)
  (web-api-handle :post "/api/load-domain"
                  '(:domain "hardware" :seed-demo t))
  (is (null (getf (nth-value 1 (web-api-handle :get "/api/status")) :plan-p)))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan"
                      (list :goals '(("device-configured" "interface-01"))))
    (is (= 200 code))
    (is (eq t (getf (getf body :plan) :success))))
  (let ((status (nth-value 1 (web-api-handle :get "/api/status"))))
    (is (eq t (getf status :plan-p)))
    (is (eq t (getf status :plan-success))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/simulate")
    (is (= 200 code))
    (is (eq t (getf (getf body :execution) :success)))))

(test web-api-failed-plan-is-not-ready
  (gp-clear-memory)
  (gp-reset)
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan"
                      '(:goals ((ready interface-01))))
    (is (= 200 code))
    (is (null (getf (getf body :plan) :success))))
  (let ((status (nth-value 1 (web-api-handle :get "/api/status"))))
    (is (eq t (getf status :plan-p)))
    (is (null (getf status :plan-success)))
    (is (eq t (getf status :listening))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/simulate")
    (is (= 400 code))
    (is (search "did not succeed" (getf body :error))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/run"
                      '(:confirm t :adapters nil))
    (is (= 400 code))
    (is (search "did not succeed" (getf body :error)))))

(test web-api-plan-refuses-goals-that-already-hold
  (gp-clear-memory)
  (gp-reset)
  (web-api-handle :post "/api/add-fact"
                  (list :fact '("power-state" "interface-01" "on")))
  (setf *current-plan* nil)
  (is (null (getf (nth-value 1 (web-api-handle :get "/api/status")) :plan-p)))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan"
                      (list :goals '(("power-state" "interface-01" "on"))))
    (is (= 400 code))
    (is (search "no open goal" (getf body :error))))
  (is (null *current-plan*))
  (is (null (getf (nth-value 1 (web-api-handle :get "/api/status")) :plan-p))))

(test web-api-json-envelope
  (gp-clear-memory)
  (gp-reset)
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :get "/api/facts" nil)
    (is (= 200 code))
    (is (search "application/json" ctype))
    (let ((parsed (json->lisp json)))
      (is (vectorp (getf parsed :facts)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/nope")
    (is (= 404 code))
    (is (eq nil (getf body :ok)))))

(test web-api-add-fact
  (gp-clear-memory)
  (gp-reset)
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/add-fact"
                      (list :fact '("toolchain" "ready")))
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (is-true (fact-p '(automa-gp::toolchain automa-gp::ready) (gp-facts)))))

(test web-api-plan-accepts-json-goal-array
  (gp-clear-memory)
  (gp-reset)
  (web-api-handle :post "/api/load-domain"
                  '(:domain "hardware" :seed-demo t))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json
       :post "/api/plan"
       "{\"goals\":[[\"device-configured\",\"interface-01\"]]}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((body (json->lisp json))
           (plan (getf body :plan)))
      (is (eq t (getf plan :success)))
      (is (= 3 (getf plan :length))))))

(test web-api-archive-remember-use-and-score
  (gp-clear-memory)
  (gp-reset)
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/archive")
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (is (= 0 (length (coerce (getf body :procedures) 'list)))))
  (web-api-handle :post "/api/load-domain"
                  '(:domain "hardware" :seed-demo t))
  (web-api-handle :post "/api/plan"
                  (list :goals '(("device-configured" "interface-01"))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/archive/remember" '(:name "connect-hw"))
    (is (= 200 code))
    (let ((procs (coerce (getf body :procedures) 'list)))
      (is (= 1 (length procs)))
      (is (eq 'automa-gp::connect-hw (getf (first procs) :name)))
      (is (= 1 (getf (first procs) :success-count)))
      (is (plusp (getf (first procs) :score)))
      ;; POST archive bodies omit applies (cheap); probe with GET.
      (is (null (getf (first procs) :applies)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/archive" '(:applies t))
    (is (= 200 code))
    (is (eq t (getf (first (coerce (getf body :procedures) 'list)) :applies))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/archive?applies=1")
    (is (= 200 code))
    (is (eq t (getf (first (coerce (getf body :procedures) 'list)) :applies))))
  (gp-reset)
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/archive")
    (is (= 200 code))
    (let ((procs (coerce (getf body :procedures) 'list)))
      (is (= 1 (length procs)))
      (is (null (getf (first procs) :applies)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/archive" '(:applies t))
    (is (= 200 code))
    (is (null (getf (first (coerce (getf body :procedures) 'list)) :applies))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/archive/use" '(:name "CONNECT-HW"))
    (is (= 400 code))
    (is (eq nil (getf body :ok)))
    (is (search "does not apply" (getf body :error))))
  (web-api-handle :post "/api/load-domain"
                  '(:domain "hardware" :seed-demo t))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/archive/use" '(:name "CONNECT-HW"))
    (is (= 200 code))
    (is (eq 'automa-gp::connect-hw (getf (getf body :plan) :from-procedure)))
    (is (eq t (getf (getf body :plan) :success)))
    (is (= 3 (getf (getf body :plan) :length))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan"
                      '(:goals ((ready interface-01))))
    (declare (ignore body))
    (is (= 200 code)))
  (is (eq t (getf (nth-value 1 (web-api-handle :get "/api/status")) :listening)))
  (is (null (getf (nth-value 1 (web-api-handle :get "/api/status")) :plan-success)))
  (let ((before (length (gp-procedures))))
    (multiple-value-bind (code body)
        (web-api-handle :post "/api/archive/remember" '(:name "failed-plan"))
      (is (= 400 code))
      (is (search "did not succeed" (getf body :error))))
    (signals error (gp-remember-procedure :name 'failed-plan))
    (is (= before (length (gp-procedures)))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/archive/use" '(:name "CONNECT-HW"))
    (is (= 200 code))
    (is (eq t (getf (getf body :plan) :success))))
  (let ((status (nth-value 1 (web-api-handle :get "/api/status"))))
    (is (null (getf status :listening)))
    (is (eq t (getf status :plan-success))))
  (is (null *observed-before*))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/induce/rule" '(:name "stale"))
    (is (= 400 code))
    (is (search "listening" (getf body :error))))
  (gp-reset)
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/archive/use"
                      '(:name "CONNECT-HW" :unchecked t))
    (is (= 200 code))
    (is (eq 'automa-gp::connect-hw (getf (getf body :plan) :from-procedure))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/archive/score"
                      '(:name "connect-hw" :success nil))
    (is (= 200 code))
    (is (= 1 (getf (getf body :procedure) :failure-count)))
    (is (= 1 (getf (getf body :procedure) :success-count))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/archive")
    (is (= 200 code))
    (is (= 1 (length (coerce (getf body :procedures) 'list))))))

(test web-api-archive-use-projects-missing-effects
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::charge
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::charge-state ?d automa-gp::empty))
                  :add-list '((automa-gp::charge-state ?d automa-gp::full)
                              (automa-gp::ready ?d))
                  :delete-list '((automa-gp::charge-state ?d automa-gp::empty))))
  (gp-add-operator
   (make-operator :name 'automa-gp::use-device
                  :preconditions '((automa-gp::device ?d) (automa-gp::ready ?d))
                  :add-list '((automa-gp::in-use ?d))))
  (install-procedure!
   (make-procedure
    :name 'automa-gp::charge-then-use
    :goals '((automa-gp::in-use automa-gp::interface-01))
    :operators-used '(automa-gp::charge automa-gp::use-device)
    :success-count 1
    :steps (list
            (list :operator 'automa-gp::charge
                  :bindings '((?d . automa-gp::interface-01))
                  :goal '(automa-gp::charge-state automa-gp::interface-01
                          automa-gp::full))
            (list :operator 'automa-gp::use-device
                  :bindings '((?d . automa-gp::interface-01))
                  :goal '(automa-gp::in-use automa-gp::interface-01)))))
  (web-api-handle :post "/api/add-fact"
                  (list :fact '("device" "interface-01")))
  (web-api-handle :post "/api/add-fact"
                  (list :fact '("charge-state" "interface-01" "full")))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((body (json->lisp json))
           (plan (getf body :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (eq t (getf plan :success)))
      (is (= 2 (getf plan :length)))
      (is (eq t (getf (first steps) :effects-only)))
      (is (string= "CHARGE" (getf (first steps) :operator))))))

(test web-api-archive-use-applies-stored-effects-without-operator
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::charge
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::charge-state ?d automa-gp::empty))
                  :add-list '((automa-gp::charge-state ?d automa-gp::full)
                              (automa-gp::ready ?d))
                  :delete-list '((automa-gp::charge-state ?d automa-gp::empty))))
  (gp-add-operator
   (make-operator :name 'automa-gp::use-device
                  :preconditions '((automa-gp::device ?d) (automa-gp::ready ?d))
                  :add-list '((automa-gp::in-use ?d))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-plan :goals '((automa-gp::in-use automa-gp::interface-01)) :archive nil)
  (gp-remember-procedure :name 'automa-gp::charge-then-use)
  (gp-remove-operator 'automa-gp::charge)
  (web-api-handle :post "/api/add-fact"
                  (list :fact '("ready" "interface-01")))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (search "READY" json))
    (is (search "effects-only" json))
    (let* ((body (json->lisp json))
           (plan (getf body :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (eq t (getf plan :success)))
      (is (eq t (getf (first steps) :effects-only)))
      (is (string= "CHARGE" (getf (first steps) :operator))))))

(test web-api-archive-use-applies-recorded-step-without-operator
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::charge
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::charge-state ?d automa-gp::empty))
                  :add-list '((automa-gp::charge-state ?d automa-gp::full)
                              (automa-gp::ready ?d))
                  :delete-list '((automa-gp::charge-state ?d automa-gp::empty))))
  (gp-add-operator
   (make-operator :name 'automa-gp::use-device
                  :preconditions '((automa-gp::device ?d) (automa-gp::ready ?d))
                  :add-list '((automa-gp::in-use ?d))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-plan :goals '((automa-gp::in-use automa-gp::interface-01)) :archive nil)
  (gp-remember-procedure :name 'automa-gp::charge-then-use)
  (gp-remove-operator 'automa-gp::charge)
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (search "stored-apply" json))
    (let* ((steps (coerce (getf (getf (json->lisp json) :plan) :steps) 'list)))
      (is (eq t (getf (first steps) :stored-apply)))
      (is (string= "CHARGE" (getf (first steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/run" '(:confirm t))
    (is (= 200 code))
    (is (eq t (getf (getf body :execution) :success))))
  (is (fact-p '(automa-gp::in-use automa-gp::interface-01) (gp-facts)))
  (is (not (fact-p '(automa-gp::charge-state automa-gp::interface-01
                      automa-gp::empty)
                   (gp-facts)))))

(test web-api-archive-use-repairs-missing-precondition
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::charge
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::charge-state ?d automa-gp::empty))
                  :add-list '((automa-gp::charge-state ?d automa-gp::full)
                              (automa-gp::ready ?d))
                  :delete-list '((automa-gp::charge-state ?d automa-gp::empty))))
  (gp-add-operator
   (make-operator :name 'automa-gp::use-device
                  :preconditions '((automa-gp::device ?d) (automa-gp::ready ?d))
                  :add-list '((automa-gp::in-use ?d))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-plan :goals '((automa-gp::in-use automa-gp::interface-01)) :archive nil)
  (gp-remember-procedure :name 'automa-gp::charge-then-use)
  (gp-remove-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-add-operator
   (make-operator :name 'automa-gp::fill
                  :preconditions '((automa-gp::device ?d))
                  :add-list '((automa-gp::charge-state ?d automa-gp::empty))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "CHARGE-THEN-USE" (getf plan :from-procedure)))
      (is (string= "FILL" (getf (first steps) :operator)))
      (is (= 3 (getf plan :length)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "Missing precondition" (getf body :text)))))

(test web-api-archive-repair-reuses-another-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::pour
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::reservoir ?d automa-gp::full))
                  :add-list '((automa-gp::charge-state ?d automa-gp::empty))
                  :delete-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (gp-plan :goals '((automa-gp::charge-state automa-gp::interface-01
                     automa-gp::empty))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::refill)
  (gp-remove-operator 'automa-gp::pour)
  (gp-add-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-add-operator
   (make-operator :name 'automa-gp::charge
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::charge-state ?d automa-gp::empty))
                  :add-list '((automa-gp::charge-state ?d automa-gp::full)
                              (automa-gp::ready ?d))
                  :delete-list '((automa-gp::charge-state ?d automa-gp::empty))))
  (gp-add-operator
   (make-operator :name 'automa-gp::use-device
                  :preconditions '((automa-gp::device ?d) (automa-gp::ready ?d))
                  :add-list '((automa-gp::in-use ?d))))
  (gp-plan :goals '((automa-gp::in-use automa-gp::interface-01)) :archive nil)
  (gp-remember-procedure :name 'automa-gp::charge-then-use)
  (gp-remove-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "CHARGE-THEN-USE" (getf plan :from-procedure)))
      (is (string= "POUR" (getf (first steps) :operator)))
      (is (eq t (getf (first steps) :stored-apply)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "reused procedure" (getf body :text)))
    (is (search "REFILL" (getf body :text)))))

(test web-api-archive-repair-reuses-a-nested-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::prime
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::tank ?d automa-gp::sealed))
                  :add-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::tank automa-gp::interface-01 automa-gp::sealed))
  (gp-plan :goals '((automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::prime-reservoir)
  (gp-remove-operator 'automa-gp::prime)
  (gp-add-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (gp-add-operator
   (make-operator :name 'automa-gp::pour
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::reservoir ?d automa-gp::full))
                  :add-list '((automa-gp::charge-state ?d automa-gp::empty))
                  :delete-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-plan :goals '((automa-gp::charge-state automa-gp::interface-01
                     automa-gp::empty))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::refill)
  (gp-remove-operator 'automa-gp::pour)
  (gp-add-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-add-operator
   (make-operator :name 'automa-gp::charge
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::charge-state ?d automa-gp::empty))
                  :add-list '((automa-gp::charge-state ?d automa-gp::full)
                              (automa-gp::ready ?d))
                  :delete-list '((automa-gp::charge-state ?d automa-gp::empty))))
  (gp-add-operator
   (make-operator :name 'automa-gp::use-device
                  :preconditions '((automa-gp::device ?d) (automa-gp::ready ?d))
                  :add-list '((automa-gp::in-use ?d))))
  (gp-plan :goals '((automa-gp::in-use automa-gp::interface-01)) :archive nil)
  (gp-remember-procedure :name 'automa-gp::charge-then-use)
  (gp-remove-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-remove-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "PRIME" (getf (first steps) :operator)))
      (is (string= "POUR" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "REFILL" (getf body :text)))
    (is (search "PRIME-RESERVOIR" (getf body :text)))))

(test web-api-archive-repair-reuses-a-third-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::seal
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::cap ?d automa-gp::on))
                  :add-list '((automa-gp::tank ?d automa-gp::sealed))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::cap automa-gp::interface-01 automa-gp::on))
  (gp-plan :goals '((automa-gp::tank automa-gp::interface-01 automa-gp::sealed))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::seal-tank)
  (gp-remove-operator 'automa-gp::seal)
  (gp-add-fact '(automa-gp::tank automa-gp::interface-01 automa-gp::sealed))
  (gp-add-operator
   (make-operator :name 'automa-gp::prime
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::tank ?d automa-gp::sealed))
                  :add-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-plan :goals '((automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::prime-reservoir)
  (gp-remove-operator 'automa-gp::prime)
  (gp-add-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (gp-add-operator
   (make-operator :name 'automa-gp::pour
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::reservoir ?d automa-gp::full))
                  :add-list '((automa-gp::charge-state ?d automa-gp::empty))
                  :delete-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-plan :goals '((automa-gp::charge-state automa-gp::interface-01
                     automa-gp::empty))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::refill)
  (gp-remove-operator 'automa-gp::pour)
  (gp-add-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-add-operator
   (make-operator :name 'automa-gp::charge
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::charge-state ?d automa-gp::empty))
                  :add-list '((automa-gp::charge-state ?d automa-gp::full)
                              (automa-gp::ready ?d))
                  :delete-list '((automa-gp::charge-state ?d automa-gp::empty))))
  (gp-add-operator
   (make-operator :name 'automa-gp::use-device
                  :preconditions '((automa-gp::device ?d) (automa-gp::ready ?d))
                  :add-list '((automa-gp::in-use ?d))))
  (gp-plan :goals '((automa-gp::in-use automa-gp::interface-01)) :archive nil)
  (gp-remember-procedure :name 'automa-gp::charge-then-use)
  (gp-remove-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-remove-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (gp-remove-fact '(automa-gp::tank automa-gp::interface-01 automa-gp::sealed))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "SEAL" (getf (first steps) :operator)))
      (is (string= "PRIME" (getf (second steps) :operator)))
      (is (string= "POUR" (getf (third steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "SEAL-TANK" (getf body :text)))
    (is (search "PRIME-RESERVOIR" (getf body :text)))
    (is (search "REFILL" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fourth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(latch interface-01 free))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "PLACE-CAP" (getf (first steps) :operator)))
      (is (string= "SEAL" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "PLACE-CAP" (getf body :text)))
    (is (search "SEAL-TANK" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fifth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pin interface-01 pulled))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "RELEASE-LATCH" (getf (first steps) :operator)))
      (is (string= "PLACE-CAP" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "RELEASE-LATCH" (getf body :text)))
    (is (search "PLACE-CAP" (getf body :text)))))

(test web-api-archive-repair-reuses-a-sixth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(clip interface-01 off))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "PULL-PIN" (getf (first steps) :operator)))
      (is (string= "RELEASE-LATCH" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "PULL-PIN" (getf body :text)))
    (is (search "RELEASE-LATCH" (getf body :text)))))

(test web-api-archive-repair-reuses-a-seventh-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cover interface-01 lifted))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "OPEN-CLIP" (getf (first steps) :operator)))
      (is (string= "PULL-PIN" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "OPEN-CLIP" (getf body :text)))
    (is (search "PULL-PIN" (getf body :text)))))

(test web-api-archive-repair-reuses-an-eighth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hinge interface-01 free))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "LIFT-COVER" (getf (first steps) :operator)))
      (is (string= "OPEN-CLIP" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "LIFT-COVER" (getf body :text)))
    (is (search "OPEN-CLIP" (getf body :text)))))

(test web-api-archive-repair-reuses-a-ninth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bolt interface-01 loose))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "FREE-HINGE" (getf (first steps) :operator)))
      (is (string= "LIFT-COVER" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FREE-HINGE" (getf body :text)))
    (is (search "LIFT-COVER" (getf body :text)))))

(test web-api-archive-repair-reuses-a-tenth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wrench interface-01 ready))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "LOOSEN-BOLT" (getf (first steps) :operator)))
      (is (string= "FREE-HINGE" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "LOOSEN-BOLT" (getf body :text)))
    (is (search "FREE-HINGE" (getf body :text)))))

(test web-api-archive-repair-reuses-an-eleventh-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(drawer interface-01 open))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "FETCH-WRENCH" (getf (first steps) :operator)))
      (is (string= "LOOSEN-BOLT" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FETCH-WRENCH" (getf body :text)))
    (is (search "LOOSEN-BOLT" (getf body :text)))))

(test web-api-archive-repair-reuses-a-twelfth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(key interface-01 turned))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "OPEN-DRAWER" (getf (first steps) :operator)))
      (is (string= "FETCH-WRENCH" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "OPEN-DRAWER" (getf body :text)))
    (is (search "FETCH-WRENCH" (getf body :text)))))

(test web-api-archive-repair-reuses-a-thirteenth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lock interface-01 free))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "TURN-KEY" (getf (first steps) :operator)))
      (is (string= "OPEN-DRAWER" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "TURN-KEY" (getf body :text)))
    (is (search "OPEN-DRAWER" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fourteenth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(catch interface-01 clear))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "FREE-LOCK" (getf (first steps) :operator)))
      (is (string= "TURN-KEY" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FREE-LOCK" (getf body :text)))
    (is (search "TURN-KEY" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fifteenth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(tab interface-01 flush))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "ALIGN-TAB" (getf (first steps) :operator)))
      (is (string= "FREE-LOCK" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "ALIGN-TAB" (getf body :text)))
    (is (search "FREE-LOCK" (getf body :text)))))

(test web-api-archive-repair-reuses-a-sixteenth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(guide interface-01 set))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "SEAT-TAB" (getf (first steps) :operator)))
      (is (string= "ALIGN-TAB" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "SEAT-TAB" (getf body :text)))
    (is (search "ALIGN-TAB" (getf body :text)))))

(test web-api-archive-repair-reuses-a-seventeenth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(rail interface-01 clear))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "SET-GUIDE" (getf (first steps) :operator)))
      (is (string= "SEAT-TAB" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "SET-GUIDE" (getf body :text)))
    (is (search "SEAT-TAB" (getf body :text)))))

(test web-api-archive-repair-reuses-an-eighteenth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(slot interface-01 open))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "CLEAR-RAIL" (getf (first steps) :operator)))
      (is (string= "SET-GUIDE" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "CLEAR-RAIL" (getf body :text)))
    (is (search "SET-GUIDE" (getf body :text)))))

(test web-api-archive-repair-reuses-a-nineteenth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(shutter interface-01 raised))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "OPEN-SLOT" (getf (first steps) :operator)))
      (is (string= "CLEAR-RAIL" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "OPEN-SLOT" (getf body :text)))
    (is (search "CLEAR-RAIL" (getf body :text)))))

(test web-api-archive-repair-reuses-a-twentieth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cord interface-01 free))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "RAISE-SHUTTER" (getf (first steps) :operator)))
      (is (string= "OPEN-SLOT" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "RAISE-SHUTTER" (getf body :text)))
    (is (search "OPEN-SLOT" (getf body :text)))))

(test web-api-archive-repair-reuses-a-twenty-first-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(knot interface-01 loose))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "FREE-CORD" (getf (first steps) :operator)))
      (is (string= "RAISE-SHUTTER" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FREE-CORD" (getf body :text)))
    (is (search "RAISE-SHUTTER" (getf body :text)))))

(test web-api-archive-repair-reuses-a-twenty-second-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(loop interface-01 free))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "SLIP-LOOP" (getf (first steps) :operator)))
      (is (string= "FREE-CORD" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "SLIP-LOOP" (getf body :text)))
    (is (search "FREE-CORD" (getf body :text)))))

(test web-api-archive-repair-reuses-a-twenty-third-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(eye interface-01 clear))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "OPEN-EYE" (getf (first steps) :operator)))
      (is (string= "SLIP-LOOP" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "OPEN-EYE" (getf body :text)))
    (is (search "SLIP-LOOP" (getf body :text)))))

(test web-api-archive-repair-reuses-a-twenty-fourth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lid interface-01 raised))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "LIFT-LID" (getf (first steps) :operator)))
      (is (string= "OPEN-EYE" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "LIFT-LID" (getf body :text)))
    (is (search "OPEN-EYE" (getf body :text)))))

(test web-api-archive-repair-reuses-a-twenty-fifth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hook interface-01 off))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "UNHOOK" (getf (first steps) :operator)))
      (is (string= "LIFT-LID" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "UNHOOK" (getf body :text)))
    (is (search "LIFT-LID" (getf body :text)))))

(test web-api-archive-repair-reuses-a-twenty-sixth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barb interface-01 down))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "FREE-HOOK" (getf (first steps) :operator)))
      (is (string= "UNHOOK" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FREE-HOOK" (getf body :text)))
    (is (search "UNHOOK" (getf body :text)))))

(test web-api-archive-repair-reuses-a-twenty-seventh-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "LOWER-BARB" (getf (first steps) :operator)))
      (is (string= "FREE-HOOK" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "LOWER-BARB" (getf body :text)))
    (is (search "FREE-HOOK" (getf body :text)))))

(test web-api-archive-repair-reuses-a-twenty-eighth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "EASE-SPRING" (getf (first steps) :operator)))
      (is (string= "LOWER-BARB" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "EASE-SPRING" (getf body :text)))
    (is (search "LOWER-BARB" (getf body :text)))))

(test web-api-archive-repair-reuses-a-twenty-ninth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "FREE-COIL" (getf (first steps) :operator)))
      (is (string= "EASE-SPRING" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FREE-COIL" (getf body :text)))
    (is (search "EASE-SPRING" (getf body :text)))))

(test web-api-archive-repair-reuses-a-thirtieth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "OPEN-SPOOL" (getf (first steps) :operator)))
      (is (string= "FREE-COIL" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "OPEN-SPOOL" (getf body :text)))
    (is (search "FREE-COIL" (getf body :text)))))

(test web-api-archive-repair-reuses-a-thirty-first-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "RELEASE-BRAKE" (getf (first steps) :operator)))
      (is (string= "OPEN-SPOOL" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "RELEASE-BRAKE" (getf body :text)))
    (is (search "OPEN-SPOOL" (getf body :text)))))

(test web-api-archive-repair-reuses-a-thirty-second-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "RAISE-LEVER" (getf (first steps) :operator)))
      (is (string= "RELEASE-BRAKE" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "RAISE-LEVER" (getf body :text)))
    (is (search "RELEASE-BRAKE" (getf body :text)))))

(test web-api-archive-repair-reuses-a-thirty-third-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "SEAT-CAM" (getf (first steps) :operator)))
      (is (string= "RAISE-LEVER" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "SEAT-CAM" (getf body :text)))
    (is (search "RAISE-LEVER" (getf body :text)))))

(test web-api-archive-repair-reuses-a-thirty-fourth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "CLEAR-JOURNAL" (getf (first steps) :operator)))
      (is (string= "SEAT-CAM" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "CLEAR-JOURNAL" (getf body :text)))
    (is (search "SEAT-CAM" (getf body :text)))))

(test web-api-archive-repair-reuses-a-thirty-fifth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "FREE-BUSH" (getf (first steps) :operator)))
      (is (string= "CLEAR-JOURNAL" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FREE-BUSH" (getf body :text)))
    (is (search "CLEAR-JOURNAL" (getf body :text)))))

(test web-api-archive-repair-reuses-a-thirty-sixth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "LOOSEN-COLLAR" (getf (first steps) :operator)))
      (is (string= "FREE-BUSH" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "LOOSEN-COLLAR" (getf body :text)))
    (is (search "FREE-BUSH" (getf body :text)))))

(test web-api-archive-repair-reuses-a-thirty-seventh-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "DRAW-STUD" (getf (first steps) :operator)))
      (is (string= "LOOSEN-COLLAR" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "DRAW-STUD" (getf body :text)))
    (is (search "LOOSEN-COLLAR" (getf body :text)))))

(test web-api-archive-repair-reuses-a-thirty-eighth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "DRIVE-WEDGE" (getf (first steps) :operator)))
      (is (string= "DRAW-STUD" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "DRIVE-WEDGE" (getf body :text)))
    (is (search "DRAW-STUD" (getf body :text)))))

(test web-api-archive-repair-reuses-a-thirty-ninth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "BED-ANVIL" (getf (first steps) :operator)))
      (is (string= "DRIVE-WEDGE" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "BED-ANVIL" (getf body :text)))
    (is (search "DRIVE-WEDGE" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fortieth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "LEVEL-PLINTH" (getf (first steps) :operator)))
      (is (string= "BED-ANVIL" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "LEVEL-PLINTH" (getf body :text)))
    (is (search "BED-ANVIL" (getf body :text)))))

(test web-api-archive-repair-reuses-a-forty-first-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "PACK-FOOTING" (getf (first steps) :operator)))
      (is (string= "LEVEL-PLINTH" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "PACK-FOOTING" (getf body :text)))
    (is (search "LEVEL-PLINTH" (getf body :text)))))

(test web-api-archive-repair-reuses-a-forty-second-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "DRY-GRAVEL" (getf (first steps) :operator)))
      (is (string= "PACK-FOOTING" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "DRY-GRAVEL" (getf body :text)))
    (is (search "PACK-FOOTING" (getf body :text)))))

(test web-api-archive-repair-reuses-a-forty-third-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "AIR-PILE" (getf (first steps) :operator)))
      (is (string= "DRY-GRAVEL" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "AIR-PILE" (getf body :text)))
    (is (search "DRY-GRAVEL" (getf body :text)))))

(test web-api-archive-repair-reuses-a-forty-fourth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "RAKE-MOUND" (getf (first steps) :operator)))
      (is (string= "AIR-PILE" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "RAKE-MOUND" (getf body :text)))
    (is (search "AIR-PILE" (getf body :text)))))

(test web-api-archive-repair-reuses-a-forty-fifth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "GRADE-BERM" (getf (first steps) :operator)))
      (is (string= "RAKE-MOUND" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "GRADE-BERM" (getf body :text)))
    (is (search "RAKE-MOUND" (getf body :text)))))

(test web-api-archive-repair-reuses-a-forty-sixth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "SCATTER-SPOIL" (getf (first steps) :operator)))
      (is (string= "GRADE-BERM" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "SCATTER-SPOIL" (getf body :text)))
    (is (search "GRADE-BERM" (getf body :text)))))

(test web-api-archive-repair-reuses-a-forty-seventh-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "TIP-BARROW" (getf (first steps) :operator)))
      (is (string= "SCATTER-SPOIL" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "TIP-BARROW" (getf body :text)))
    (is (search "SCATTER-SPOIL" (getf body :text)))))

(test web-api-archive-repair-reuses-a-forty-eighth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "LOAD-BARROW" (getf (first steps) :operator)))
      (is (string= "TIP-BARROW" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "LOAD-BARROW" (getf body :text)))
    (is (search "TIP-BARROW" (getf body :text)))))

(test web-api-archive-repair-reuses-a-forty-ninth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "FILL-HOD" (getf (first steps) :operator)))
      (is (string= "LOAD-BARROW" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FILL-HOD" (getf body :text)))
    (is (search "LOAD-BARROW" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fiftieth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'mix-mortar
                  :preconditions '((device ?d) (lime ?d slaked))
                  :add-list '((mortar ?d mixed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lime interface-01 slaked))
  (gp-plan :goals '((mortar interface-01 mixed)) :archive nil)
  (gp-remember-procedure :name 'mix-mortar)
  (gp-remove-operator 'mix-mortar)
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (gp-remove-fact '(mortar interface-01 mixed))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "MIX-MORTAR" (getf (first steps) :operator)))
      (is (string= "FILL-HOD" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "MIX-MORTAR" (getf body :text)))
    (is (search "FILL-HOD" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fifty-first-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'slake-lime
                  :preconditions '((device ?d) (quicklime ?d burnt))
                  :add-list '((lime ?d slaked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-plan :goals '((lime interface-01 slaked)) :archive nil)
  (gp-remember-procedure :name 'slake-lime)
  (gp-remove-operator 'slake-lime)
  (gp-add-fact '(lime interface-01 slaked))
  (gp-add-operator
   (make-operator :name 'mix-mortar
                  :preconditions '((device ?d) (lime ?d slaked))
                  :add-list '((mortar ?d mixed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lime interface-01 slaked))
  (gp-plan :goals '((mortar interface-01 mixed)) :archive nil)
  (gp-remember-procedure :name 'mix-mortar)
  (gp-remove-operator 'mix-mortar)
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (gp-remove-fact '(mortar interface-01 mixed))
  (gp-remove-fact '(lime interface-01 slaked))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "SLAKE-LIME" (getf (first steps) :operator)))
      (is (string= "MIX-MORTAR" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "SLAKE-LIME" (getf body :text)))
    (is (search "MIX-MORTAR" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fifty-second-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'burn-lime
                  :preconditions '((device ?d) (kiln ?d hot))
                  :add-list '((quicklime ?d burnt))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(kiln interface-01 hot))
  (gp-plan :goals '((quicklime interface-01 burnt)) :archive nil)
  (gp-remember-procedure :name 'burn-lime)
  (gp-remove-operator 'burn-lime)
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-add-operator
   (make-operator :name 'slake-lime
                  :preconditions '((device ?d) (quicklime ?d burnt))
                  :add-list '((lime ?d slaked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-plan :goals '((lime interface-01 slaked)) :archive nil)
  (gp-remember-procedure :name 'slake-lime)
  (gp-remove-operator 'slake-lime)
  (gp-add-fact '(lime interface-01 slaked))
  (gp-add-operator
   (make-operator :name 'mix-mortar
                  :preconditions '((device ?d) (lime ?d slaked))
                  :add-list '((mortar ?d mixed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lime interface-01 slaked))
  (gp-plan :goals '((mortar interface-01 mixed)) :archive nil)
  (gp-remember-procedure :name 'mix-mortar)
  (gp-remove-operator 'mix-mortar)
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (gp-remove-fact '(mortar interface-01 mixed))
  (gp-remove-fact '(lime interface-01 slaked))
  (gp-remove-fact '(quicklime interface-01 burnt))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "BURN-LIME" (getf (first steps) :operator)))
      (is (string= "SLAKE-LIME" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "BURN-LIME" (getf body :text)))
    (is (search "SLAKE-LIME" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fifty-third-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'light-kiln
                  :preconditions '((device ?d) (fuel ?d stacked))
                  :add-list '((kiln ?d hot))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-plan :goals '((kiln interface-01 hot)) :archive nil)
  (gp-remember-procedure :name 'light-kiln)
  (gp-remove-operator 'light-kiln)
  (gp-add-fact '(kiln interface-01 hot))
  (gp-add-operator
   (make-operator :name 'burn-lime
                  :preconditions '((device ?d) (kiln ?d hot))
                  :add-list '((quicklime ?d burnt))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(kiln interface-01 hot))
  (gp-plan :goals '((quicklime interface-01 burnt)) :archive nil)
  (gp-remember-procedure :name 'burn-lime)
  (gp-remove-operator 'burn-lime)
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-add-operator
   (make-operator :name 'slake-lime
                  :preconditions '((device ?d) (quicklime ?d burnt))
                  :add-list '((lime ?d slaked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-plan :goals '((lime interface-01 slaked)) :archive nil)
  (gp-remember-procedure :name 'slake-lime)
  (gp-remove-operator 'slake-lime)
  (gp-add-fact '(lime interface-01 slaked))
  (gp-add-operator
   (make-operator :name 'mix-mortar
                  :preconditions '((device ?d) (lime ?d slaked))
                  :add-list '((mortar ?d mixed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lime interface-01 slaked))
  (gp-plan :goals '((mortar interface-01 mixed)) :archive nil)
  (gp-remember-procedure :name 'mix-mortar)
  (gp-remove-operator 'mix-mortar)
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (gp-remove-fact '(mortar interface-01 mixed))
  (gp-remove-fact '(lime interface-01 slaked))
  (gp-remove-fact '(quicklime interface-01 burnt))
  (gp-remove-fact '(kiln interface-01 hot))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "LIGHT-KILN" (getf (first steps) :operator)))
      (is (string= "BURN-LIME" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "LIGHT-KILN" (getf body :text)))
    (is (search "BURN-LIME" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fifty-fourth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'stack-fuel
                  :preconditions '((device ?d) (cordwood ?d split))
                  :add-list '((fuel ?d stacked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cordwood interface-01 split))
  (gp-plan :goals '((fuel interface-01 stacked)) :archive nil)
  (gp-remember-procedure :name 'stack-fuel)
  (gp-remove-operator 'stack-fuel)
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-add-operator
   (make-operator :name 'light-kiln
                  :preconditions '((device ?d) (fuel ?d stacked))
                  :add-list '((kiln ?d hot))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-plan :goals '((kiln interface-01 hot)) :archive nil)
  (gp-remember-procedure :name 'light-kiln)
  (gp-remove-operator 'light-kiln)
  (gp-add-fact '(kiln interface-01 hot))
  (gp-add-operator
   (make-operator :name 'burn-lime
                  :preconditions '((device ?d) (kiln ?d hot))
                  :add-list '((quicklime ?d burnt))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(kiln interface-01 hot))
  (gp-plan :goals '((quicklime interface-01 burnt)) :archive nil)
  (gp-remember-procedure :name 'burn-lime)
  (gp-remove-operator 'burn-lime)
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-add-operator
   (make-operator :name 'slake-lime
                  :preconditions '((device ?d) (quicklime ?d burnt))
                  :add-list '((lime ?d slaked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-plan :goals '((lime interface-01 slaked)) :archive nil)
  (gp-remember-procedure :name 'slake-lime)
  (gp-remove-operator 'slake-lime)
  (gp-add-fact '(lime interface-01 slaked))
  (gp-add-operator
   (make-operator :name 'mix-mortar
                  :preconditions '((device ?d) (lime ?d slaked))
                  :add-list '((mortar ?d mixed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lime interface-01 slaked))
  (gp-plan :goals '((mortar interface-01 mixed)) :archive nil)
  (gp-remember-procedure :name 'mix-mortar)
  (gp-remove-operator 'mix-mortar)
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (gp-remove-fact '(mortar interface-01 mixed))
  (gp-remove-fact '(lime interface-01 slaked))
  (gp-remove-fact '(quicklime interface-01 burnt))
  (gp-remove-fact '(kiln interface-01 hot))
  (gp-remove-fact '(fuel interface-01 stacked))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "STACK-FUEL" (getf (first steps) :operator)))
      (is (string= "LIGHT-KILN" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "STACK-FUEL" (getf body :text)))
    (is (search "LIGHT-KILN" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fifty-fifth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'split-cordwood
                  :preconditions '((device ?d) (log ?d whole))
                  :add-list '((cordwood ?d split))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(log interface-01 whole))
  (gp-plan :goals '((cordwood interface-01 split)) :archive nil)
  (gp-remember-procedure :name 'split-cordwood)
  (gp-remove-operator 'split-cordwood)
  (gp-add-fact '(cordwood interface-01 split))
  (gp-add-operator
   (make-operator :name 'stack-fuel
                  :preconditions '((device ?d) (cordwood ?d split))
                  :add-list '((fuel ?d stacked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cordwood interface-01 split))
  (gp-plan :goals '((fuel interface-01 stacked)) :archive nil)
  (gp-remember-procedure :name 'stack-fuel)
  (gp-remove-operator 'stack-fuel)
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-add-operator
   (make-operator :name 'light-kiln
                  :preconditions '((device ?d) (fuel ?d stacked))
                  :add-list '((kiln ?d hot))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-plan :goals '((kiln interface-01 hot)) :archive nil)
  (gp-remember-procedure :name 'light-kiln)
  (gp-remove-operator 'light-kiln)
  (gp-add-fact '(kiln interface-01 hot))
  (gp-add-operator
   (make-operator :name 'burn-lime
                  :preconditions '((device ?d) (kiln ?d hot))
                  :add-list '((quicklime ?d burnt))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(kiln interface-01 hot))
  (gp-plan :goals '((quicklime interface-01 burnt)) :archive nil)
  (gp-remember-procedure :name 'burn-lime)
  (gp-remove-operator 'burn-lime)
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-add-operator
   (make-operator :name 'slake-lime
                  :preconditions '((device ?d) (quicklime ?d burnt))
                  :add-list '((lime ?d slaked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-plan :goals '((lime interface-01 slaked)) :archive nil)
  (gp-remember-procedure :name 'slake-lime)
  (gp-remove-operator 'slake-lime)
  (gp-add-fact '(lime interface-01 slaked))
  (gp-add-operator
   (make-operator :name 'mix-mortar
                  :preconditions '((device ?d) (lime ?d slaked))
                  :add-list '((mortar ?d mixed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lime interface-01 slaked))
  (gp-plan :goals '((mortar interface-01 mixed)) :archive nil)
  (gp-remember-procedure :name 'mix-mortar)
  (gp-remove-operator 'mix-mortar)
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (gp-remove-fact '(mortar interface-01 mixed))
  (gp-remove-fact '(lime interface-01 slaked))
  (gp-remove-fact '(quicklime interface-01 burnt))
  (gp-remove-fact '(kiln interface-01 hot))
  (gp-remove-fact '(fuel interface-01 stacked))
  (gp-remove-fact '(cordwood interface-01 split))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "SPLIT-CORDWOOD" (getf (first steps) :operator)))
      (is (string= "STACK-FUEL" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "SPLIT-CORDWOOD" (getf body :text)))
    (is (search "STACK-FUEL" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fifty-sixth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'fell-timber
                  :preconditions '((device ?d) (tree ?d standing))
                  :add-list '((log ?d whole))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(tree interface-01 standing))
  (gp-plan :goals '((log interface-01 whole)) :archive nil)
  (gp-remember-procedure :name 'fell-timber)
  (gp-remove-operator 'fell-timber)
  (gp-add-fact '(log interface-01 whole))
  (gp-add-operator
   (make-operator :name 'split-cordwood
                  :preconditions '((device ?d) (log ?d whole))
                  :add-list '((cordwood ?d split))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(log interface-01 whole))
  (gp-plan :goals '((cordwood interface-01 split)) :archive nil)
  (gp-remember-procedure :name 'split-cordwood)
  (gp-remove-operator 'split-cordwood)
  (gp-add-fact '(cordwood interface-01 split))
  (gp-add-operator
   (make-operator :name 'stack-fuel
                  :preconditions '((device ?d) (cordwood ?d split))
                  :add-list '((fuel ?d stacked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cordwood interface-01 split))
  (gp-plan :goals '((fuel interface-01 stacked)) :archive nil)
  (gp-remember-procedure :name 'stack-fuel)
  (gp-remove-operator 'stack-fuel)
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-add-operator
   (make-operator :name 'light-kiln
                  :preconditions '((device ?d) (fuel ?d stacked))
                  :add-list '((kiln ?d hot))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-plan :goals '((kiln interface-01 hot)) :archive nil)
  (gp-remember-procedure :name 'light-kiln)
  (gp-remove-operator 'light-kiln)
  (gp-add-fact '(kiln interface-01 hot))
  (gp-add-operator
   (make-operator :name 'burn-lime
                  :preconditions '((device ?d) (kiln ?d hot))
                  :add-list '((quicklime ?d burnt))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(kiln interface-01 hot))
  (gp-plan :goals '((quicklime interface-01 burnt)) :archive nil)
  (gp-remember-procedure :name 'burn-lime)
  (gp-remove-operator 'burn-lime)
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-add-operator
   (make-operator :name 'slake-lime
                  :preconditions '((device ?d) (quicklime ?d burnt))
                  :add-list '((lime ?d slaked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-plan :goals '((lime interface-01 slaked)) :archive nil)
  (gp-remember-procedure :name 'slake-lime)
  (gp-remove-operator 'slake-lime)
  (gp-add-fact '(lime interface-01 slaked))
  (gp-add-operator
   (make-operator :name 'mix-mortar
                  :preconditions '((device ?d) (lime ?d slaked))
                  :add-list '((mortar ?d mixed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lime interface-01 slaked))
  (gp-plan :goals '((mortar interface-01 mixed)) :archive nil)
  (gp-remember-procedure :name 'mix-mortar)
  (gp-remove-operator 'mix-mortar)
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (gp-remove-fact '(mortar interface-01 mixed))
  (gp-remove-fact '(lime interface-01 slaked))
  (gp-remove-fact '(quicklime interface-01 burnt))
  (gp-remove-fact '(kiln interface-01 hot))
  (gp-remove-fact '(fuel interface-01 stacked))
  (gp-remove-fact '(cordwood interface-01 split))
  (gp-remove-fact '(log interface-01 whole))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "FELL-TIMBER" (getf (first steps) :operator)))
      (is (string= "SPLIT-CORDWOOD" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FELL-TIMBER" (getf body :text)))
    (is (search "SPLIT-CORDWOOD" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fifty-seventh-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'plant-sapling
                  :preconditions '((device ?d) (seedling ?d rooted))
                  :add-list '((tree ?d standing))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(seedling interface-01 rooted))
  (gp-plan :goals '((tree interface-01 standing)) :archive nil)
  (gp-remember-procedure :name 'plant-sapling)
  (gp-remove-operator 'plant-sapling)
  (gp-add-fact '(tree interface-01 standing))
  (gp-add-operator
   (make-operator :name 'fell-timber
                  :preconditions '((device ?d) (tree ?d standing))
                  :add-list '((log ?d whole))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(tree interface-01 standing))
  (gp-plan :goals '((log interface-01 whole)) :archive nil)
  (gp-remember-procedure :name 'fell-timber)
  (gp-remove-operator 'fell-timber)
  (gp-add-fact '(log interface-01 whole))
  (gp-add-operator
   (make-operator :name 'split-cordwood
                  :preconditions '((device ?d) (log ?d whole))
                  :add-list '((cordwood ?d split))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(log interface-01 whole))
  (gp-plan :goals '((cordwood interface-01 split)) :archive nil)
  (gp-remember-procedure :name 'split-cordwood)
  (gp-remove-operator 'split-cordwood)
  (gp-add-fact '(cordwood interface-01 split))
  (gp-add-operator
   (make-operator :name 'stack-fuel
                  :preconditions '((device ?d) (cordwood ?d split))
                  :add-list '((fuel ?d stacked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cordwood interface-01 split))
  (gp-plan :goals '((fuel interface-01 stacked)) :archive nil)
  (gp-remember-procedure :name 'stack-fuel)
  (gp-remove-operator 'stack-fuel)
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-add-operator
   (make-operator :name 'light-kiln
                  :preconditions '((device ?d) (fuel ?d stacked))
                  :add-list '((kiln ?d hot))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-plan :goals '((kiln interface-01 hot)) :archive nil)
  (gp-remember-procedure :name 'light-kiln)
  (gp-remove-operator 'light-kiln)
  (gp-add-fact '(kiln interface-01 hot))
  (gp-add-operator
   (make-operator :name 'burn-lime
                  :preconditions '((device ?d) (kiln ?d hot))
                  :add-list '((quicklime ?d burnt))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(kiln interface-01 hot))
  (gp-plan :goals '((quicklime interface-01 burnt)) :archive nil)
  (gp-remember-procedure :name 'burn-lime)
  (gp-remove-operator 'burn-lime)
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-add-operator
   (make-operator :name 'slake-lime
                  :preconditions '((device ?d) (quicklime ?d burnt))
                  :add-list '((lime ?d slaked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-plan :goals '((lime interface-01 slaked)) :archive nil)
  (gp-remember-procedure :name 'slake-lime)
  (gp-remove-operator 'slake-lime)
  (gp-add-fact '(lime interface-01 slaked))
  (gp-add-operator
   (make-operator :name 'mix-mortar
                  :preconditions '((device ?d) (lime ?d slaked))
                  :add-list '((mortar ?d mixed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lime interface-01 slaked))
  (gp-plan :goals '((mortar interface-01 mixed)) :archive nil)
  (gp-remember-procedure :name 'mix-mortar)
  (gp-remove-operator 'mix-mortar)
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (gp-remove-fact '(mortar interface-01 mixed))
  (gp-remove-fact '(lime interface-01 slaked))
  (gp-remove-fact '(quicklime interface-01 burnt))
  (gp-remove-fact '(kiln interface-01 hot))
  (gp-remove-fact '(fuel interface-01 stacked))
  (gp-remove-fact '(cordwood interface-01 split))
  (gp-remove-fact '(log interface-01 whole))
  (gp-remove-fact '(tree interface-01 standing))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "PLANT-SAPLING" (getf (first steps) :operator)))
      (is (string= "FELL-TIMBER" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "PLANT-SAPLING" (getf body :text)))
    (is (search "FELL-TIMBER" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fifty-eighth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'pot-seedling
                  :preconditions '((device ?d) (cutting ?d taken))
                  :add-list '((seedling ?d rooted))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cutting interface-01 taken))
  (gp-plan :goals '((seedling interface-01 rooted)) :archive nil)
  (gp-remember-procedure :name 'pot-seedling)
  (gp-remove-operator 'pot-seedling)
  (gp-add-fact '(seedling interface-01 rooted))
  (gp-add-operator
   (make-operator :name 'plant-sapling
                  :preconditions '((device ?d) (seedling ?d rooted))
                  :add-list '((tree ?d standing))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(seedling interface-01 rooted))
  (gp-plan :goals '((tree interface-01 standing)) :archive nil)
  (gp-remember-procedure :name 'plant-sapling)
  (gp-remove-operator 'plant-sapling)
  (gp-add-fact '(tree interface-01 standing))
  (gp-add-operator
   (make-operator :name 'fell-timber
                  :preconditions '((device ?d) (tree ?d standing))
                  :add-list '((log ?d whole))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(tree interface-01 standing))
  (gp-plan :goals '((log interface-01 whole)) :archive nil)
  (gp-remember-procedure :name 'fell-timber)
  (gp-remove-operator 'fell-timber)
  (gp-add-fact '(log interface-01 whole))
  (gp-add-operator
   (make-operator :name 'split-cordwood
                  :preconditions '((device ?d) (log ?d whole))
                  :add-list '((cordwood ?d split))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(log interface-01 whole))
  (gp-plan :goals '((cordwood interface-01 split)) :archive nil)
  (gp-remember-procedure :name 'split-cordwood)
  (gp-remove-operator 'split-cordwood)
  (gp-add-fact '(cordwood interface-01 split))
  (gp-add-operator
   (make-operator :name 'stack-fuel
                  :preconditions '((device ?d) (cordwood ?d split))
                  :add-list '((fuel ?d stacked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cordwood interface-01 split))
  (gp-plan :goals '((fuel interface-01 stacked)) :archive nil)
  (gp-remember-procedure :name 'stack-fuel)
  (gp-remove-operator 'stack-fuel)
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-add-operator
   (make-operator :name 'light-kiln
                  :preconditions '((device ?d) (fuel ?d stacked))
                  :add-list '((kiln ?d hot))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-plan :goals '((kiln interface-01 hot)) :archive nil)
  (gp-remember-procedure :name 'light-kiln)
  (gp-remove-operator 'light-kiln)
  (gp-add-fact '(kiln interface-01 hot))
  (gp-add-operator
   (make-operator :name 'burn-lime
                  :preconditions '((device ?d) (kiln ?d hot))
                  :add-list '((quicklime ?d burnt))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(kiln interface-01 hot))
  (gp-plan :goals '((quicklime interface-01 burnt)) :archive nil)
  (gp-remember-procedure :name 'burn-lime)
  (gp-remove-operator 'burn-lime)
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-add-operator
   (make-operator :name 'slake-lime
                  :preconditions '((device ?d) (quicklime ?d burnt))
                  :add-list '((lime ?d slaked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-plan :goals '((lime interface-01 slaked)) :archive nil)
  (gp-remember-procedure :name 'slake-lime)
  (gp-remove-operator 'slake-lime)
  (gp-add-fact '(lime interface-01 slaked))
  (gp-add-operator
   (make-operator :name 'mix-mortar
                  :preconditions '((device ?d) (lime ?d slaked))
                  :add-list '((mortar ?d mixed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lime interface-01 slaked))
  (gp-plan :goals '((mortar interface-01 mixed)) :archive nil)
  (gp-remember-procedure :name 'mix-mortar)
  (gp-remove-operator 'mix-mortar)
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (gp-remove-fact '(mortar interface-01 mixed))
  (gp-remove-fact '(lime interface-01 slaked))
  (gp-remove-fact '(quicklime interface-01 burnt))
  (gp-remove-fact '(kiln interface-01 hot))
  (gp-remove-fact '(fuel interface-01 stacked))
  (gp-remove-fact '(cordwood interface-01 split))
  (gp-remove-fact '(log interface-01 whole))
  (gp-remove-fact '(tree interface-01 standing))
  (gp-remove-fact '(seedling interface-01 rooted))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "POT-SEEDLING" (getf (first steps) :operator)))
      (is (string= "PLANT-SAPLING" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "POT-SEEDLING" (getf body :text)))
    (is (search "PLANT-SAPLING" (getf body :text)))))

(test web-api-archive-repair-reuses-a-fifty-ninth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'take-cutting
                  :preconditions '((device ?d) (shoot ?d green))
                  :add-list '((cutting ?d taken))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(shoot interface-01 green))
  (gp-plan :goals '((cutting interface-01 taken)) :archive nil)
  (gp-remember-procedure :name 'take-cutting)
  (gp-remove-operator 'take-cutting)
  (gp-add-fact '(cutting interface-01 taken))
  (gp-add-operator
   (make-operator :name 'pot-seedling
                  :preconditions '((device ?d) (cutting ?d taken))
                  :add-list '((seedling ?d rooted))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cutting interface-01 taken))
  (gp-plan :goals '((seedling interface-01 rooted)) :archive nil)
  (gp-remember-procedure :name 'pot-seedling)
  (gp-remove-operator 'pot-seedling)
  (gp-add-fact '(seedling interface-01 rooted))
  (gp-add-operator
   (make-operator :name 'plant-sapling
                  :preconditions '((device ?d) (seedling ?d rooted))
                  :add-list '((tree ?d standing))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(seedling interface-01 rooted))
  (gp-plan :goals '((tree interface-01 standing)) :archive nil)
  (gp-remember-procedure :name 'plant-sapling)
  (gp-remove-operator 'plant-sapling)
  (gp-add-fact '(tree interface-01 standing))
  (gp-add-operator
   (make-operator :name 'fell-timber
                  :preconditions '((device ?d) (tree ?d standing))
                  :add-list '((log ?d whole))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(tree interface-01 standing))
  (gp-plan :goals '((log interface-01 whole)) :archive nil)
  (gp-remember-procedure :name 'fell-timber)
  (gp-remove-operator 'fell-timber)
  (gp-add-fact '(log interface-01 whole))
  (gp-add-operator
   (make-operator :name 'split-cordwood
                  :preconditions '((device ?d) (log ?d whole))
                  :add-list '((cordwood ?d split))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(log interface-01 whole))
  (gp-plan :goals '((cordwood interface-01 split)) :archive nil)
  (gp-remember-procedure :name 'split-cordwood)
  (gp-remove-operator 'split-cordwood)
  (gp-add-fact '(cordwood interface-01 split))
  (gp-add-operator
   (make-operator :name 'stack-fuel
                  :preconditions '((device ?d) (cordwood ?d split))
                  :add-list '((fuel ?d stacked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cordwood interface-01 split))
  (gp-plan :goals '((fuel interface-01 stacked)) :archive nil)
  (gp-remember-procedure :name 'stack-fuel)
  (gp-remove-operator 'stack-fuel)
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-add-operator
   (make-operator :name 'light-kiln
                  :preconditions '((device ?d) (fuel ?d stacked))
                  :add-list '((kiln ?d hot))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-plan :goals '((kiln interface-01 hot)) :archive nil)
  (gp-remember-procedure :name 'light-kiln)
  (gp-remove-operator 'light-kiln)
  (gp-add-fact '(kiln interface-01 hot))
  (gp-add-operator
   (make-operator :name 'burn-lime
                  :preconditions '((device ?d) (kiln ?d hot))
                  :add-list '((quicklime ?d burnt))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(kiln interface-01 hot))
  (gp-plan :goals '((quicklime interface-01 burnt)) :archive nil)
  (gp-remember-procedure :name 'burn-lime)
  (gp-remove-operator 'burn-lime)
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-add-operator
   (make-operator :name 'slake-lime
                  :preconditions '((device ?d) (quicklime ?d burnt))
                  :add-list '((lime ?d slaked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-plan :goals '((lime interface-01 slaked)) :archive nil)
  (gp-remember-procedure :name 'slake-lime)
  (gp-remove-operator 'slake-lime)
  (gp-add-fact '(lime interface-01 slaked))
  (gp-add-operator
   (make-operator :name 'mix-mortar
                  :preconditions '((device ?d) (lime ?d slaked))
                  :add-list '((mortar ?d mixed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lime interface-01 slaked))
  (gp-plan :goals '((mortar interface-01 mixed)) :archive nil)
  (gp-remember-procedure :name 'mix-mortar)
  (gp-remove-operator 'mix-mortar)
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (gp-remove-fact '(mortar interface-01 mixed))
  (gp-remove-fact '(lime interface-01 slaked))
  (gp-remove-fact '(quicklime interface-01 burnt))
  (gp-remove-fact '(kiln interface-01 hot))
  (gp-remove-fact '(fuel interface-01 stacked))
  (gp-remove-fact '(cordwood interface-01 split))
  (gp-remove-fact '(log interface-01 whole))
  (gp-remove-fact '(tree interface-01 standing))
  (gp-remove-fact '(seedling interface-01 rooted))
  (gp-remove-fact '(cutting interface-01 taken))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "TAKE-CUTTING" (getf (first steps) :operator)))
      (is (string= "POT-SEEDLING" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "TAKE-CUTTING" (getf body :text)))
    (is (search "POT-SEEDLING" (getf body :text)))))

(test web-api-archive-repair-reuses-a-sixtieth-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'water-shoot
                  :preconditions '((device ?d) (bud ?d swelling))
                  :add-list '((shoot ?d green))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bud interface-01 swelling))
  (gp-plan :goals '((shoot interface-01 green)) :archive nil)
  (gp-remember-procedure :name 'water-shoot)
  (gp-remove-operator 'water-shoot)
  (gp-add-fact '(shoot interface-01 green))
  (gp-add-operator
   (make-operator :name 'take-cutting
                  :preconditions '((device ?d) (shoot ?d green))
                  :add-list '((cutting ?d taken))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(shoot interface-01 green))
  (gp-plan :goals '((cutting interface-01 taken)) :archive nil)
  (gp-remember-procedure :name 'take-cutting)
  (gp-remove-operator 'take-cutting)
  (gp-add-fact '(cutting interface-01 taken))
  (gp-add-operator
   (make-operator :name 'pot-seedling
                  :preconditions '((device ?d) (cutting ?d taken))
                  :add-list '((seedling ?d rooted))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cutting interface-01 taken))
  (gp-plan :goals '((seedling interface-01 rooted)) :archive nil)
  (gp-remember-procedure :name 'pot-seedling)
  (gp-remove-operator 'pot-seedling)
  (gp-add-fact '(seedling interface-01 rooted))
  (gp-add-operator
   (make-operator :name 'plant-sapling
                  :preconditions '((device ?d) (seedling ?d rooted))
                  :add-list '((tree ?d standing))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(seedling interface-01 rooted))
  (gp-plan :goals '((tree interface-01 standing)) :archive nil)
  (gp-remember-procedure :name 'plant-sapling)
  (gp-remove-operator 'plant-sapling)
  (gp-add-fact '(tree interface-01 standing))
  (gp-add-operator
   (make-operator :name 'fell-timber
                  :preconditions '((device ?d) (tree ?d standing))
                  :add-list '((log ?d whole))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(tree interface-01 standing))
  (gp-plan :goals '((log interface-01 whole)) :archive nil)
  (gp-remember-procedure :name 'fell-timber)
  (gp-remove-operator 'fell-timber)
  (gp-add-fact '(log interface-01 whole))
  (gp-add-operator
   (make-operator :name 'split-cordwood
                  :preconditions '((device ?d) (log ?d whole))
                  :add-list '((cordwood ?d split))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(log interface-01 whole))
  (gp-plan :goals '((cordwood interface-01 split)) :archive nil)
  (gp-remember-procedure :name 'split-cordwood)
  (gp-remove-operator 'split-cordwood)
  (gp-add-fact '(cordwood interface-01 split))
  (gp-add-operator
   (make-operator :name 'stack-fuel
                  :preconditions '((device ?d) (cordwood ?d split))
                  :add-list '((fuel ?d stacked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cordwood interface-01 split))
  (gp-plan :goals '((fuel interface-01 stacked)) :archive nil)
  (gp-remember-procedure :name 'stack-fuel)
  (gp-remove-operator 'stack-fuel)
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-add-operator
   (make-operator :name 'light-kiln
                  :preconditions '((device ?d) (fuel ?d stacked))
                  :add-list '((kiln ?d hot))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-plan :goals '((kiln interface-01 hot)) :archive nil)
  (gp-remember-procedure :name 'light-kiln)
  (gp-remove-operator 'light-kiln)
  (gp-add-fact '(kiln interface-01 hot))
  (gp-add-operator
   (make-operator :name 'burn-lime
                  :preconditions '((device ?d) (kiln ?d hot))
                  :add-list '((quicklime ?d burnt))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(kiln interface-01 hot))
  (gp-plan :goals '((quicklime interface-01 burnt)) :archive nil)
  (gp-remember-procedure :name 'burn-lime)
  (gp-remove-operator 'burn-lime)
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-add-operator
   (make-operator :name 'slake-lime
                  :preconditions '((device ?d) (quicklime ?d burnt))
                  :add-list '((lime ?d slaked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-plan :goals '((lime interface-01 slaked)) :archive nil)
  (gp-remember-procedure :name 'slake-lime)
  (gp-remove-operator 'slake-lime)
  (gp-add-fact '(lime interface-01 slaked))
  (gp-add-operator
   (make-operator :name 'mix-mortar
                  :preconditions '((device ?d) (lime ?d slaked))
                  :add-list '((mortar ?d mixed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lime interface-01 slaked))
  (gp-plan :goals '((mortar interface-01 mixed)) :archive nil)
  (gp-remember-procedure :name 'mix-mortar)
  (gp-remove-operator 'mix-mortar)
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (gp-remove-fact '(mortar interface-01 mixed))
  (gp-remove-fact '(lime interface-01 slaked))
  (gp-remove-fact '(quicklime interface-01 burnt))
  (gp-remove-fact '(kiln interface-01 hot))
  (gp-remove-fact '(fuel interface-01 stacked))
  (gp-remove-fact '(cordwood interface-01 split))
  (gp-remove-fact '(log interface-01 whole))
  (gp-remove-fact '(tree interface-01 standing))
  (gp-remove-fact '(seedling interface-01 rooted))
  (gp-remove-fact '(cutting interface-01 taken))
  (gp-remove-fact '(shoot interface-01 green))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "WATER-SHOOT" (getf (first steps) :operator)))
      (is (string= "TAKE-CUTTING" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "WATER-SHOOT" (getf body :text)))
    (is (search "TAKE-CUTTING" (getf body :text)))))

(test web-api-archive-repair-reuses-a-sixty-first-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'warm-bud
                  :preconditions '((device ?d) (twig ?d dormant))
                  :add-list '((bud ?d swelling))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(twig interface-01 dormant))
  (gp-plan :goals '((bud interface-01 swelling)) :archive nil)
  (gp-remember-procedure :name 'warm-bud)
  (gp-remove-operator 'warm-bud)
  (gp-add-fact '(bud interface-01 swelling))
  (gp-add-operator
   (make-operator :name 'water-shoot
                  :preconditions '((device ?d) (bud ?d swelling))
                  :add-list '((shoot ?d green))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bud interface-01 swelling))
  (gp-plan :goals '((shoot interface-01 green)) :archive nil)
  (gp-remember-procedure :name 'water-shoot)
  (gp-remove-operator 'water-shoot)
  (gp-add-fact '(shoot interface-01 green))
  (gp-add-operator
   (make-operator :name 'take-cutting
                  :preconditions '((device ?d) (shoot ?d green))
                  :add-list '((cutting ?d taken))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(shoot interface-01 green))
  (gp-plan :goals '((cutting interface-01 taken)) :archive nil)
  (gp-remember-procedure :name 'take-cutting)
  (gp-remove-operator 'take-cutting)
  (gp-add-fact '(cutting interface-01 taken))
  (gp-add-operator
   (make-operator :name 'pot-seedling
                  :preconditions '((device ?d) (cutting ?d taken))
                  :add-list '((seedling ?d rooted))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cutting interface-01 taken))
  (gp-plan :goals '((seedling interface-01 rooted)) :archive nil)
  (gp-remember-procedure :name 'pot-seedling)
  (gp-remove-operator 'pot-seedling)
  (gp-add-fact '(seedling interface-01 rooted))
  (gp-add-operator
   (make-operator :name 'plant-sapling
                  :preconditions '((device ?d) (seedling ?d rooted))
                  :add-list '((tree ?d standing))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(seedling interface-01 rooted))
  (gp-plan :goals '((tree interface-01 standing)) :archive nil)
  (gp-remember-procedure :name 'plant-sapling)
  (gp-remove-operator 'plant-sapling)
  (gp-add-fact '(tree interface-01 standing))
  (gp-add-operator
   (make-operator :name 'fell-timber
                  :preconditions '((device ?d) (tree ?d standing))
                  :add-list '((log ?d whole))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(tree interface-01 standing))
  (gp-plan :goals '((log interface-01 whole)) :archive nil)
  (gp-remember-procedure :name 'fell-timber)
  (gp-remove-operator 'fell-timber)
  (gp-add-fact '(log interface-01 whole))
  (gp-add-operator
   (make-operator :name 'split-cordwood
                  :preconditions '((device ?d) (log ?d whole))
                  :add-list '((cordwood ?d split))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(log interface-01 whole))
  (gp-plan :goals '((cordwood interface-01 split)) :archive nil)
  (gp-remember-procedure :name 'split-cordwood)
  (gp-remove-operator 'split-cordwood)
  (gp-add-fact '(cordwood interface-01 split))
  (gp-add-operator
   (make-operator :name 'stack-fuel
                  :preconditions '((device ?d) (cordwood ?d split))
                  :add-list '((fuel ?d stacked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cordwood interface-01 split))
  (gp-plan :goals '((fuel interface-01 stacked)) :archive nil)
  (gp-remember-procedure :name 'stack-fuel)
  (gp-remove-operator 'stack-fuel)
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-add-operator
   (make-operator :name 'light-kiln
                  :preconditions '((device ?d) (fuel ?d stacked))
                  :add-list '((kiln ?d hot))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(fuel interface-01 stacked))
  (gp-plan :goals '((kiln interface-01 hot)) :archive nil)
  (gp-remember-procedure :name 'light-kiln)
  (gp-remove-operator 'light-kiln)
  (gp-add-fact '(kiln interface-01 hot))
  (gp-add-operator
   (make-operator :name 'burn-lime
                  :preconditions '((device ?d) (kiln ?d hot))
                  :add-list '((quicklime ?d burnt))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(kiln interface-01 hot))
  (gp-plan :goals '((quicklime interface-01 burnt)) :archive nil)
  (gp-remember-procedure :name 'burn-lime)
  (gp-remove-operator 'burn-lime)
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-add-operator
   (make-operator :name 'slake-lime
                  :preconditions '((device ?d) (quicklime ?d burnt))
                  :add-list '((lime ?d slaked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(quicklime interface-01 burnt))
  (gp-plan :goals '((lime interface-01 slaked)) :archive nil)
  (gp-remember-procedure :name 'slake-lime)
  (gp-remove-operator 'slake-lime)
  (gp-add-fact '(lime interface-01 slaked))
  (gp-add-operator
   (make-operator :name 'mix-mortar
                  :preconditions '((device ?d) (lime ?d slaked))
                  :add-list '((mortar ?d mixed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lime interface-01 slaked))
  (gp-plan :goals '((mortar interface-01 mixed)) :archive nil)
  (gp-remember-procedure :name 'mix-mortar)
  (gp-remove-operator 'mix-mortar)
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-add-operator
   (make-operator :name 'fill-hod
                  :preconditions '((device ?d) (mortar ?d mixed))
                  :add-list '((hod ?d filled))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mortar interface-01 mixed))
  (gp-plan :goals '((hod interface-01 filled)) :archive nil)
  (gp-remember-procedure :name 'fill-hod)
  (gp-remove-operator 'fill-hod)
  (gp-add-fact '(hod interface-01 filled))
  (gp-add-operator
   (make-operator :name 'load-barrow
                  :preconditions '((device ?d) (hod ?d filled))
                  :add-list '((barrow ?d loaded))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(hod interface-01 filled))
  (gp-plan :goals '((barrow interface-01 loaded)) :archive nil)
  (gp-remember-procedure :name 'load-barrow)
  (gp-remove-operator 'load-barrow)
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-add-operator
   (make-operator :name 'tip-barrow
                  :preconditions '((device ?d) (barrow ?d loaded))
                  :add-list '((heap ?d tossed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(barrow interface-01 loaded))
  (gp-plan :goals '((heap interface-01 tossed)) :archive nil)
  (gp-remember-procedure :name 'tip-barrow)
  (gp-remove-operator 'tip-barrow)
  (gp-add-fact '(heap interface-01 tossed))
  (gp-add-operator
   (make-operator :name 'scatter-spoil
                  :preconditions '((device ?d) (heap ?d tossed))
                  :add-list '((spoil ?d spread))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(heap interface-01 tossed))
  (gp-plan :goals '((spoil interface-01 spread)) :archive nil)
  (gp-remember-procedure :name 'scatter-spoil)
  (gp-remove-operator 'scatter-spoil)
  (gp-add-fact '(spoil interface-01 spread))
  (gp-add-operator
   (make-operator :name 'grade-berm
                  :preconditions '((device ?d) (spoil ?d spread))
                  :add-list '((berm ?d even))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spoil interface-01 spread))
  (gp-plan :goals '((berm interface-01 even)) :archive nil)
  (gp-remember-procedure :name 'grade-berm)
  (gp-remove-operator 'grade-berm)
  (gp-add-fact '(berm interface-01 even))
  (gp-add-operator
   (make-operator :name 'rake-mound
                  :preconditions '((device ?d) (berm ?d even))
                  :add-list '((mound ?d raked))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(berm interface-01 even))
  (gp-plan :goals '((mound interface-01 raked)) :archive nil)
  (gp-remember-procedure :name 'rake-mound)
  (gp-remove-operator 'rake-mound)
  (gp-add-fact '(mound interface-01 raked))
  (gp-add-operator
   (make-operator :name 'air-pile
                  :preconditions '((device ?d) (mound ?d raked))
                  :add-list '((pile ?d aired))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(mound interface-01 raked))
  (gp-plan :goals '((pile interface-01 aired)) :archive nil)
  (gp-remember-procedure :name 'air-pile)
  (gp-remove-operator 'air-pile)
  (gp-add-fact '(pile interface-01 aired))
  (gp-add-operator
   (make-operator :name 'dry-gravel
                  :preconditions '((device ?d) (pile ?d aired))
                  :add-list '((gravel ?d dry))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(pile interface-01 aired))
  (gp-plan :goals '((gravel interface-01 dry)) :archive nil)
  (gp-remember-procedure :name 'dry-gravel)
  (gp-remove-operator 'dry-gravel)
  (gp-add-fact '(gravel interface-01 dry))
  (gp-add-operator
   (make-operator :name 'pack-footing
                  :preconditions '((device ?d) (gravel ?d dry))
                  :add-list '((footing ?d packed))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(gravel interface-01 dry))
  (gp-plan :goals '((footing interface-01 packed)) :archive nil)
  (gp-remember-procedure :name 'pack-footing)
  (gp-remove-operator 'pack-footing)
  (gp-add-fact '(footing interface-01 packed))
  (gp-add-operator
   (make-operator :name 'level-plinth
                  :preconditions '((device ?d) (footing ?d packed))
                  :add-list '((plinth ?d level))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(footing interface-01 packed))
  (gp-plan :goals '((plinth interface-01 level)) :archive nil)
  (gp-remember-procedure :name 'level-plinth)
  (gp-remove-operator 'level-plinth)
  (gp-add-fact '(plinth interface-01 level))
  (gp-add-operator
   (make-operator :name 'bed-anvil
                  :preconditions '((device ?d) (plinth ?d level))
                  :add-list '((anvil ?d firm))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(plinth interface-01 level))
  (gp-plan :goals '((anvil interface-01 firm)) :archive nil)
  (gp-remember-procedure :name 'bed-anvil)
  (gp-remove-operator 'bed-anvil)
  (gp-add-fact '(anvil interface-01 firm))
  (gp-add-operator
   (make-operator :name 'drive-wedge
                  :preconditions '((device ?d) (anvil ?d firm))
                  :add-list '((wedge ?d set))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(anvil interface-01 firm))
  (gp-plan :goals '((wedge interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'drive-wedge)
  (gp-remove-operator 'drive-wedge)
  (gp-add-fact '(wedge interface-01 set))
  (gp-add-operator
   (make-operator :name 'draw-stud
                  :preconditions '((device ?d) (wedge ?d set))
                  :add-list '((stud ?d out))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(wedge interface-01 set))
  (gp-plan :goals '((stud interface-01 out)) :archive nil)
  (gp-remember-procedure :name 'draw-stud)
  (gp-remove-operator 'draw-stud)
  (gp-add-fact '(stud interface-01 out))
  (gp-add-operator
   (make-operator :name 'loosen-collar
                  :preconditions '((device ?d) (stud ?d out))
                  :add-list '((collar ?d loose))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(stud interface-01 out))
  (gp-plan :goals '((collar interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-collar)
  (gp-remove-operator 'loosen-collar)
  (gp-add-fact '(collar interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-bush
                  :preconditions '((device ?d) (collar ?d loose))
                  :add-list '((bush ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(collar interface-01 loose))
  (gp-plan :goals '((bush interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-bush)
  (gp-remove-operator 'free-bush)
  (gp-add-fact '(bush interface-01 free))
  (gp-add-operator
   (make-operator :name 'clear-journal
                  :preconditions '((device ?d) (bush ?d free))
                  :add-list '((journal ?d clear))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(bush interface-01 free))
  (gp-plan :goals '((journal interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-journal)
  (gp-remove-operator 'clear-journal)
  (gp-add-fact '(journal interface-01 clear))
  (gp-add-operator
   (make-operator :name 'seat-cam
                  :preconditions '((device ?d) (journal ?d clear))
                  :add-list '((cam ?d seated))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(journal interface-01 clear))
  (gp-plan :goals '((cam interface-01 seated)) :archive nil)
  (gp-remember-procedure :name 'seat-cam)
  (gp-remove-operator 'seat-cam)
  (gp-add-fact '(cam interface-01 seated))
  (gp-add-operator
   (make-operator :name 'raise-lever
                  :preconditions '((device ?d) (cam ?d seated))
                  :add-list '((lever ?d up))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(cam interface-01 seated))
  (gp-plan :goals '((lever interface-01 up)) :archive nil)
  (gp-remember-procedure :name 'raise-lever)
  (gp-remove-operator 'raise-lever)
  (gp-add-fact '(lever interface-01 up))
  (gp-add-operator
   (make-operator :name 'release-brake
                  :preconditions '((device ?d) (lever ?d up))
                  :add-list '((brake ?d off))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(lever interface-01 up))
  (gp-plan :goals '((brake interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'release-brake)
  (gp-remove-operator 'release-brake)
  (gp-add-fact '(brake interface-01 off))
  (gp-add-operator
   (make-operator :name 'open-spool
                  :preconditions '((device ?d) (brake ?d off))
                  :add-list '((spool ?d open))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(brake interface-01 off))
  (gp-plan :goals '((spool interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-spool)
  (gp-remove-operator 'open-spool)
  (gp-add-fact '(spool interface-01 open))
  (gp-add-operator
   (make-operator :name 'free-coil
                  :preconditions '((device ?d) (spool ?d open))
                  :add-list '((coil ?d free))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spool interface-01 open))
  (gp-plan :goals '((coil interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-coil)
  (gp-remove-operator 'free-coil)
  (gp-add-fact '(coil interface-01 free))
  (gp-add-operator
   (make-operator :name 'ease-spring
                  :preconditions '((device ?d) (coil ?d free))
                  :add-list '((spring ?d slack))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(coil interface-01 free))
  (gp-plan :goals '((spring interface-01 slack)) :archive nil)
  (gp-remember-procedure :name 'ease-spring)
  (gp-remove-operator 'ease-spring)
  (gp-add-fact '(spring interface-01 slack))
  (gp-add-operator
   (make-operator :name 'lower-barb
                  :preconditions '((device ?d) (spring ?d slack))
                  :add-list '((barb ?d down))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(spring interface-01 slack))
  (gp-plan :goals '((barb interface-01 down)) :archive nil)
  (gp-remember-procedure :name 'lower-barb)
  (gp-remove-operator 'lower-barb)
  (gp-add-fact '(barb interface-01 down))
  (gp-add-operator
   (make-operator :name 'free-hook
                  :preconditions '((device ?d) (barb ?d down))
                  :add-list '((hook ?d off))))
  (gp-plan :goals '((hook interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'free-hook)
  (gp-remove-operator 'free-hook)
  (gp-add-fact '(hook interface-01 off))
  (gp-add-operator
   (make-operator :name 'unhook
                  :preconditions '((device ?d) (hook ?d off))
                  :add-list '((lid ?d raised))))
  (gp-plan :goals '((lid interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'unhook)
  (gp-remove-operator 'unhook)
  (gp-add-fact '(lid interface-01 raised))
  (gp-add-operator
   (make-operator :name 'lift-lid
                  :preconditions '((device ?d) (lid ?d raised))
                  :add-list '((eye ?d clear))))
  (gp-plan :goals '((eye interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'lift-lid)
  (gp-remove-operator 'lift-lid)
  (gp-add-fact '(eye interface-01 clear))
  (gp-add-operator
   (make-operator :name 'open-eye
                  :preconditions '((device ?d) (eye ?d clear))
                  :add-list '((loop ?d free))))
  (gp-plan :goals '((loop interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'open-eye)
  (gp-remove-operator 'open-eye)
  (gp-add-fact '(loop interface-01 free))
  (gp-add-operator
   (make-operator :name 'slip-loop
                  :preconditions '((device ?d) (loop ?d free))
                  :add-list '((knot ?d loose))))
  (gp-plan :goals '((knot interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'slip-loop)
  (gp-remove-operator 'slip-loop)
  (gp-add-fact '(knot interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-cord
                  :preconditions '((device ?d) (knot ?d loose))
                  :add-list '((cord ?d free))))
  (gp-plan :goals '((cord interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-cord)
  (gp-remove-operator 'free-cord)
  (gp-add-fact '(cord interface-01 free))
  (gp-add-operator
   (make-operator :name 'raise-shutter
                  :preconditions '((device ?d) (cord ?d free))
                  :add-list '((shutter ?d raised))))
  (gp-plan :goals '((shutter interface-01 raised)) :archive nil)
  (gp-remember-procedure :name 'raise-shutter)
  (gp-remove-operator 'raise-shutter)
  (gp-add-fact '(shutter interface-01 raised))
  (gp-add-operator
   (make-operator :name 'open-slot
                  :preconditions '((device ?d) (shutter ?d raised))
                  :add-list '((slot ?d open))))
  (gp-plan :goals '((slot interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-slot)
  (gp-remove-operator 'open-slot)
  (gp-add-fact '(slot interface-01 open))
  (gp-add-operator
   (make-operator :name 'clear-rail
                  :preconditions '((device ?d) (slot ?d open))
                  :add-list '((rail ?d clear))))
  (gp-plan :goals '((rail interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'clear-rail)
  (gp-remove-operator 'clear-rail)
  (gp-add-fact '(rail interface-01 clear))
  (gp-add-operator
   (make-operator :name 'set-guide
                  :preconditions '((device ?d) (rail ?d clear))
                  :add-list '((guide ?d set))))
  (gp-plan :goals '((guide interface-01 set)) :archive nil)
  (gp-remember-procedure :name 'set-guide)
  (gp-remove-operator 'set-guide)
  (gp-add-fact '(guide interface-01 set))
  (gp-add-operator
   (make-operator :name 'seat-tab
                  :preconditions '((device ?d) (guide ?d set))
                  :add-list '((tab ?d flush))))
  (gp-plan :goals '((tab interface-01 flush)) :archive nil)
  (gp-remember-procedure :name 'seat-tab)
  (gp-remove-operator 'seat-tab)
  (gp-add-fact '(tab interface-01 flush))
  (gp-add-operator
   (make-operator :name 'align-tab
                  :preconditions '((device ?d) (tab ?d flush))
                  :add-list '((catch ?d clear))))
  (gp-plan :goals '((catch interface-01 clear)) :archive nil)
  (gp-remember-procedure :name 'align-tab)
  (gp-remove-operator 'align-tab)
  (gp-add-fact '(catch interface-01 clear))
  (gp-add-operator
   (make-operator :name 'free-lock
                  :preconditions '((device ?d) (catch ?d clear))
                  :add-list '((lock ?d free))))
  (gp-plan :goals '((lock interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-lock)
  (gp-remove-operator 'free-lock)
  (gp-add-fact '(lock interface-01 free))
  (gp-add-operator
   (make-operator :name 'turn-key
                  :preconditions '((device ?d) (lock ?d free))
                  :add-list '((key ?d turned))))
  (gp-plan :goals '((key interface-01 turned)) :archive nil)
  (gp-remember-procedure :name 'turn-key)
  (gp-remove-operator 'turn-key)
  (gp-add-fact '(key interface-01 turned))
  (gp-add-operator
   (make-operator :name 'open-drawer
                  :preconditions '((device ?d) (key ?d turned))
                  :add-list '((drawer ?d open))))
  (gp-plan :goals '((drawer interface-01 open)) :archive nil)
  (gp-remember-procedure :name 'open-drawer)
  (gp-remove-operator 'open-drawer)
  (gp-add-fact '(drawer interface-01 open))
  (gp-add-operator
   (make-operator :name 'fetch-wrench
                  :preconditions '((device ?d) (drawer ?d open))
                  :add-list '((wrench ?d ready))))
  (gp-plan :goals '((wrench interface-01 ready)) :archive nil)
  (gp-remember-procedure :name 'fetch-wrench)
  (gp-remove-operator 'fetch-wrench)
  (gp-add-fact '(wrench interface-01 ready))
  (gp-add-operator
   (make-operator :name 'loosen-bolt
                  :preconditions '((device ?d) (wrench ?d ready))
                  :add-list '((bolt ?d loose))))
  (gp-plan :goals '((bolt interface-01 loose)) :archive nil)
  (gp-remember-procedure :name 'loosen-bolt)
  (gp-remove-operator 'loosen-bolt)
  (gp-add-fact '(bolt interface-01 loose))
  (gp-add-operator
   (make-operator :name 'free-hinge
                  :preconditions '((device ?d) (bolt ?d loose))
                  :add-list '((hinge ?d free))))
  (gp-plan :goals '((hinge interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'free-hinge)
  (gp-remove-operator 'free-hinge)
  (gp-add-fact '(hinge interface-01 free))
  (gp-add-operator
   (make-operator :name 'lift-cover
                  :preconditions '((device ?d) (hinge ?d free))
                  :add-list '((cover ?d lifted))))
  (gp-plan :goals '((cover interface-01 lifted)) :archive nil)
  (gp-remember-procedure :name 'lift-cover)
  (gp-remove-operator 'lift-cover)
  (gp-add-fact '(cover interface-01 lifted))
  (gp-add-operator
   (make-operator :name 'open-clip
                  :preconditions '((device ?d) (cover ?d lifted))
                  :add-list '((clip ?d off))))
  (gp-plan :goals '((clip interface-01 off)) :archive nil)
  (gp-remember-procedure :name 'open-clip)
  (gp-remove-operator 'open-clip)
  (gp-add-fact '(clip interface-01 off))
  (gp-add-operator
   (make-operator :name 'pull-pin
                  :preconditions '((device ?d) (clip ?d off))
                  :add-list '((pin ?d pulled))))
  (gp-plan :goals '((pin interface-01 pulled)) :archive nil)
  (gp-remember-procedure :name 'pull-pin)
  (gp-remove-operator 'pull-pin)
  (gp-add-fact '(pin interface-01 pulled))
  (gp-add-operator
   (make-operator :name 'release-latch
                  :preconditions '((device ?d) (pin ?d pulled))
                  :add-list '((latch ?d free))))
  (gp-plan :goals '((latch interface-01 free)) :archive nil)
  (gp-remember-procedure :name 'release-latch)
  (gp-remove-operator 'release-latch)
  (gp-add-fact '(latch interface-01 free))
  (gp-add-operator
   (make-operator :name 'place-cap
                  :preconditions '((device ?d) (latch ?d free))
                  :add-list '((cap ?d on))))
  (gp-plan :goals '((cap interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'place-cap)
  (gp-remove-operator 'place-cap)
  (gp-add-fact '(cap interface-01 on))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((device ?d) (cap ?d on))
                  :add-list '((tank ?d sealed))))
  (gp-plan :goals '((tank interface-01 sealed)) :archive nil)
  (gp-remember-procedure :name 'seal-tank)
  (gp-remove-operator 'seal)
  (gp-add-fact '(tank interface-01 sealed))
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-remove-fact '(tank interface-01 sealed))
  (gp-remove-fact '(cap interface-01 on))
  (gp-remove-fact '(latch interface-01 free))
  (gp-remove-fact '(pin interface-01 pulled))
  (gp-remove-fact '(clip interface-01 off))
  (gp-remove-fact '(cover interface-01 lifted))
  (gp-remove-fact '(hinge interface-01 free))
  (gp-remove-fact '(bolt interface-01 loose))
  (gp-remove-fact '(wrench interface-01 ready))
  (gp-remove-fact '(drawer interface-01 open))
  (gp-remove-fact '(key interface-01 turned))
  (gp-remove-fact '(lock interface-01 free))
  (gp-remove-fact '(catch interface-01 clear))
  (gp-remove-fact '(tab interface-01 flush))
  (gp-remove-fact '(guide interface-01 set))
  (gp-remove-fact '(rail interface-01 clear))
  (gp-remove-fact '(slot interface-01 open))
  (gp-remove-fact '(shutter interface-01 raised))
  (gp-remove-fact '(cord interface-01 free))
  (gp-remove-fact '(knot interface-01 loose))
  (gp-remove-fact '(loop interface-01 free))
  (gp-remove-fact '(eye interface-01 clear))
  (gp-remove-fact '(lid interface-01 raised))
  (gp-remove-fact '(hook interface-01 off))
  (gp-remove-fact '(barb interface-01 down))
  (gp-remove-fact '(spring interface-01 slack))
  (gp-remove-fact '(coil interface-01 free))
  (gp-remove-fact '(spool interface-01 open))
  (gp-remove-fact '(brake interface-01 off))
  (gp-remove-fact '(lever interface-01 up))
  (gp-remove-fact '(cam interface-01 seated))
  (gp-remove-fact '(journal interface-01 clear))
  (gp-remove-fact '(bush interface-01 free))
  (gp-remove-fact '(collar interface-01 loose))
  (gp-remove-fact '(stud interface-01 out))
  (gp-remove-fact '(wedge interface-01 set))
  (gp-remove-fact '(anvil interface-01 firm))
  (gp-remove-fact '(plinth interface-01 level))
  (gp-remove-fact '(footing interface-01 packed))
  (gp-remove-fact '(gravel interface-01 dry))
  (gp-remove-fact '(pile interface-01 aired))
  (gp-remove-fact '(mound interface-01 raked))
  (gp-remove-fact '(berm interface-01 even))
  (gp-remove-fact '(spoil interface-01 spread))
  (gp-remove-fact '(heap interface-01 tossed))
  (gp-remove-fact '(barrow interface-01 loaded))
  (gp-remove-fact '(hod interface-01 filled))
  (gp-remove-fact '(mortar interface-01 mixed))
  (gp-remove-fact '(lime interface-01 slaked))
  (gp-remove-fact '(quicklime interface-01 burnt))
  (gp-remove-fact '(kiln interface-01 hot))
  (gp-remove-fact '(fuel interface-01 stacked))
  (gp-remove-fact '(cordwood interface-01 split))
  (gp-remove-fact '(log interface-01 whole))
  (gp-remove-fact '(tree interface-01 standing))
  (gp-remove-fact '(seedling interface-01 rooted))
  (gp-remove-fact '(cutting interface-01 taken))
  (gp-remove-fact '(shoot interface-01 green))
  (gp-remove-fact '(bud interface-01 swelling))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "WARM-BUD" (getf (first steps) :operator)))
      (is (string= "WATER-SHOOT" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "WARM-BUD" (getf body :text)))
    (is (search "WATER-SHOOT" (getf body :text)))))

(test web-api-archive-repair-reuses-a-covering-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::pour
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::reservoir ?d automa-gp::full))
                  :add-list '((automa-gp::charge-state ?d automa-gp::empty)
                              (automa-gp::note ?d automa-gp::poured))
                  :delete-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (gp-plan :goals '((automa-gp::charge-state automa-gp::interface-01
                     automa-gp::empty)
                    (automa-gp::note automa-gp::interface-01 automa-gp::poured))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::refill-noted)
  (gp-remove-operator 'automa-gp::pour)
  (gp-add-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-add-operator
   (make-operator :name 'automa-gp::charge
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::charge-state ?d automa-gp::empty))
                  :add-list '((automa-gp::charge-state ?d automa-gp::full)
                              (automa-gp::ready ?d))
                  :delete-list '((automa-gp::charge-state ?d automa-gp::empty))))
  (gp-add-operator
   (make-operator :name 'automa-gp::use-device
                  :preconditions '((automa-gp::device ?d) (automa-gp::ready ?d))
                  :add-list '((automa-gp::in-use ?d))))
  (gp-plan :goals '((automa-gp::in-use automa-gp::interface-01)) :archive nil)
  (gp-remember-procedure :name 'automa-gp::charge-then-use)
  (gp-remove-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "POUR" (getf (first steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "REFILL-NOTED" (getf body :text)))))

(test web-api-archive-repair-combines-partial-procedures
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::pour
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::reservoir ?d automa-gp::full))
                  :add-list '((automa-gp::charge-state ?d automa-gp::empty))
                  :delete-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (gp-plan :goals '((automa-gp::charge-state automa-gp::interface-01
                     automa-gp::empty))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::fill-empty)
  (gp-remove-operator 'automa-gp::pour)
  (gp-add-operator
   (make-operator :name 'automa-gp::attach
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::socket ?d automa-gp::free))
                  :add-list '((automa-gp::cable ?d automa-gp::connected))
                  :delete-list '((automa-gp::socket ?d automa-gp::free))))
  (gp-add-fact '(automa-gp::socket automa-gp::interface-01 automa-gp::free))
  (gp-plan :goals '((automa-gp::cable automa-gp::interface-01 automa-gp::connected))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::plug-cable)
  (gp-remove-operator 'automa-gp::attach)
  (gp-add-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-add-fact '(automa-gp::cable automa-gp::interface-01 automa-gp::connected))
  (gp-add-operator
   (make-operator :name 'automa-gp::charge
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::charge-state ?d automa-gp::empty)
                                   (automa-gp::cable ?d automa-gp::connected))
                  :add-list '((automa-gp::charge-state ?d automa-gp::full)
                              (automa-gp::ready ?d))
                  :delete-list '((automa-gp::charge-state ?d automa-gp::empty))))
  (gp-add-operator
   (make-operator :name 'automa-gp::use-device
                  :preconditions '((automa-gp::device ?d) (automa-gp::ready ?d))
                  :add-list '((automa-gp::in-use ?d))))
  (gp-plan :goals '((automa-gp::in-use automa-gp::interface-01)) :archive nil)
  (gp-remember-procedure :name 'automa-gp::charge-then-use)
  (gp-remove-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-remove-fact '(automa-gp::cable automa-gp::interface-01 automa-gp::connected))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "POUR" (getf (first steps) :operator)))
      (is (string= "ATTACH" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FILL-EMPTY" (getf body :text)))
    (is (search "PLUG-CABLE" (getf body :text)))))

(test web-api-archive-repair-reuses-procedure-with-an-extra-goal
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::pour-noted
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::reservoir ?d automa-gp::full))
                  :add-list '((automa-gp::charge-state ?d automa-gp::empty)
                              (automa-gp::note ?d automa-gp::poured))
                  :delete-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (gp-plan :goals '((automa-gp::charge-state automa-gp::interface-01
                     automa-gp::empty)
                    (automa-gp::note automa-gp::interface-01 automa-gp::poured))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::fill-noted)
  (gp-remove-operator 'automa-gp::pour-noted)
  (gp-add-operator
   (make-operator :name 'automa-gp::attach
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::socket ?d automa-gp::free))
                  :add-list '((automa-gp::cable ?d automa-gp::connected))
                  :delete-list '((automa-gp::socket ?d automa-gp::free))))
  (gp-add-fact '(automa-gp::socket automa-gp::interface-01 automa-gp::free))
  (gp-plan :goals '((automa-gp::cable automa-gp::interface-01 automa-gp::connected))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::plug-cable)
  (gp-remove-operator 'automa-gp::attach)
  (gp-add-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-add-fact '(automa-gp::cable automa-gp::interface-01 automa-gp::connected))
  (gp-add-operator
   (make-operator :name 'automa-gp::charge
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::charge-state ?d automa-gp::empty)
                                   (automa-gp::cable ?d automa-gp::connected))
                  :add-list '((automa-gp::charge-state ?d automa-gp::full)
                              (automa-gp::ready ?d))
                  :delete-list '((automa-gp::charge-state ?d automa-gp::empty))))
  (gp-add-operator
   (make-operator :name 'automa-gp::use-device
                  :preconditions '((automa-gp::device ?d) (automa-gp::ready ?d))
                  :add-list '((automa-gp::in-use ?d))))
  (gp-plan :goals '((automa-gp::in-use automa-gp::interface-01)) :archive nil)
  (gp-remember-procedure :name 'automa-gp::charge-then-use)
  (gp-remove-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-remove-fact '(automa-gp::cable automa-gp::interface-01 automa-gp::connected))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "ATTACH" (getf (first steps) :operator)))
      (is (string= "POUR-NOTED" (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FILL-NOTED" (getf body :text)))))

(test web-api-archive-repair-leaves-a-blocked-extra-step-aside
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::stamp
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::ink ?d automa-gp::ready))
                  :add-list '((automa-gp::note ?d automa-gp::poured))))
  (gp-add-operator
   (make-operator :name 'automa-gp::pour
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::reservoir ?d automa-gp::full))
                  :add-list '((automa-gp::charge-state ?d automa-gp::empty))
                  :delete-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::ink automa-gp::interface-01 automa-gp::ready))
  (gp-add-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (gp-plan :goals '((automa-gp::note automa-gp::interface-01 automa-gp::poured)
                    (automa-gp::charge-state automa-gp::interface-01
                     automa-gp::empty))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::fill-noted)
  (gp-remove-operator 'automa-gp::stamp)
  (gp-remove-operator 'automa-gp::pour)
  (gp-remove-fact '(automa-gp::ink automa-gp::interface-01 automa-gp::ready))
  (gp-add-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (gp-add-operator
   (make-operator :name 'automa-gp::charge
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::charge-state ?d automa-gp::empty))
                  :add-list '((automa-gp::charge-state ?d automa-gp::full)
                              (automa-gp::ready ?d))
                  :delete-list '((automa-gp::charge-state ?d automa-gp::empty))))
  (gp-add-operator
   (make-operator :name 'automa-gp::use-device
                  :preconditions '((automa-gp::device ?d) (automa-gp::ready ?d))
                  :add-list '((automa-gp::in-use ?d))))
  (gp-plan :goals '((automa-gp::in-use automa-gp::interface-01)) :archive nil)
  (gp-remember-procedure :name 'automa-gp::charge-then-use)
  (gp-remove-fact '(automa-gp::charge-state automa-gp::interface-01 automa-gp::empty))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/archive/use"
                           "{\"name\":\"CHARGE-THEN-USE\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (let* ((plan (getf (json->lisp json) :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (string= "POUR" (getf (first steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "Left aside" (getf body :text)))
    (is (search "STAMP" (getf body :text)))))

(test web-api-plan-reuses-procedure-whose-goals-include-the-request
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::draw-noted
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::reservoir ?d automa-gp::full))
                  :add-list '((automa-gp::charge-state ?d automa-gp::empty)
                              (automa-gp::note ?d automa-gp::poured))
                  :delete-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (gp-plan :goals '((automa-gp::charge-state automa-gp::interface-01
                     automa-gp::empty)
                    (automa-gp::note automa-gp::interface-01 automa-gp::poured))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::wide-fill)
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan"
                      (list :goals '((automa-gp::charge-state
                                      automa-gp::interface-01
                                      automa-gp::empty))))
    (is (= 200 code))
    (let* ((plan (getf body :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (eq 'automa-gp::wide-fill (getf plan :from-procedure)))
      (is (eq 'automa-gp::draw-noted (getf (first steps) :operator)))))
  (is (not (fact-p '(automa-gp::note automa-gp::interface-01 automa-gp::poured)
                   (gp-facts)))))

(test web-api-plan-combines-procedures-that-each-cover-part
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::pour
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::reservoir ?d automa-gp::full))
                  :add-list '((automa-gp::charge-state ?d automa-gp::empty))
                  :delete-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (gp-plan :goals '((automa-gp::charge-state automa-gp::interface-01
                     automa-gp::empty))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::fill-empty)
  (gp-remove-operator 'automa-gp::pour)
  (gp-add-operator
   (make-operator :name 'automa-gp::attach
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::socket ?d automa-gp::free))
                  :add-list '((automa-gp::cable ?d automa-gp::connected))
                  :delete-list '((automa-gp::socket ?d automa-gp::free))))
  (gp-add-fact '(automa-gp::socket automa-gp::interface-01 automa-gp::free))
  (gp-plan :goals '((automa-gp::cable automa-gp::interface-01
                     automa-gp::connected))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::plug-cable)
  (gp-remove-operator 'automa-gp::attach)
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan"
                      (list :goals '((automa-gp::charge-state
                                      automa-gp::interface-01
                                      automa-gp::empty)
                                     (automa-gp::cable
                                      automa-gp::interface-01
                                      automa-gp::connected))))
    (is (= 200 code))
    (let* ((plan (getf body :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (eq :null (getf plan :from-procedure)))
      (is (eq 'automa-gp::pour (getf (first steps) :operator)))
      (is (eq 'automa-gp::attach (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FILL-EMPTY" (getf body :text)))
    (is (search "PLUG-CABLE" (getf body :text)))))

(test web-api-plan-combines-a-procedure-that-also-achieves-something-else
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::pour-noted
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::reservoir ?d automa-gp::full))
                  :add-list '((automa-gp::charge-state ?d automa-gp::empty)
                              (automa-gp::note ?d automa-gp::poured))
                  :delete-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (gp-plan :goals '((automa-gp::charge-state automa-gp::interface-01
                     automa-gp::empty)
                    (automa-gp::note automa-gp::interface-01 automa-gp::poured))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::fill-noted)
  (gp-remove-operator 'automa-gp::pour-noted)
  (gp-add-operator
   (make-operator :name 'automa-gp::attach
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::socket ?d automa-gp::free))
                  :add-list '((automa-gp::cable ?d automa-gp::connected))
                  :delete-list '((automa-gp::socket ?d automa-gp::free))))
  (gp-add-fact '(automa-gp::socket automa-gp::interface-01 automa-gp::free))
  (gp-plan :goals '((automa-gp::cable automa-gp::interface-01
                     automa-gp::connected))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::plug-cable)
  (gp-remove-operator 'automa-gp::attach)
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan"
                      (list :goals '((automa-gp::charge-state
                                      automa-gp::interface-01
                                      automa-gp::empty)
                                     (automa-gp::cable
                                      automa-gp::interface-01
                                      automa-gp::connected))))
    (is (= 200 code))
    (let* ((plan (getf body :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (eq 'automa-gp::attach (getf (first steps) :operator)))
      (is (eq 'automa-gp::pour-noted (getf (second steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "FILL-NOTED" (getf body :text)))
    (is (search "PLUG-CABLE" (getf body :text)))))

(test web-api-plan-leaves-a-blocked-extra-step-aside
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'automa-gp::stamp
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::ink ?d automa-gp::ready))
                  :add-list '((automa-gp::note ?d automa-gp::poured))))
  (gp-add-operator
   (make-operator :name 'automa-gp::pour
                  :preconditions '((automa-gp::device ?d)
                                   (automa-gp::reservoir ?d automa-gp::full))
                  :add-list '((automa-gp::charge-state ?d automa-gp::empty))
                  :delete-list '((automa-gp::reservoir ?d automa-gp::full))))
  (gp-add-fact '(automa-gp::device automa-gp::interface-01))
  (gp-add-fact '(automa-gp::ink automa-gp::interface-01 automa-gp::ready))
  (gp-add-fact '(automa-gp::reservoir automa-gp::interface-01 automa-gp::full))
  (gp-plan :goals '((automa-gp::note automa-gp::interface-01 automa-gp::poured)
                    (automa-gp::charge-state automa-gp::interface-01
                     automa-gp::empty))
           :archive nil)
  (gp-remember-procedure :name 'automa-gp::fill-noted)
  (gp-remove-operator 'automa-gp::stamp)
  (gp-remove-operator 'automa-gp::pour)
  (gp-remove-fact '(automa-gp::ink automa-gp::interface-01 automa-gp::ready))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan"
                      (list :goals '((automa-gp::charge-state
                                      automa-gp::interface-01
                                      automa-gp::empty))))
    (is (= 200 code))
    (let* ((plan (getf body :plan))
           (steps (coerce (getf plan :steps) 'list)))
      (is (eq 'automa-gp::fill-noted (getf plan :from-procedure)))
      (is (eq 'automa-gp::pour (getf (first steps) :operator)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "Left aside" (getf body :text)))
    (is (search "STAMP" (getf body :text)))))
