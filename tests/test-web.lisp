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
    (is (eq t (getf body :external-matches)))
    (is (eq t (getf body :external-supported)))
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
    (is (search "typedGoalsReady" src))
    (is (search "normalizeGoalsInput" src))
    (is (search "setDisabled('btnPlan'" src))
    (is (search "setDisabled('btnSim'" src))
    (is (search "setDisabled('btnRun'" src))
    (is (search "external-matches" src))
    (is (search "external-supported" src))
    (is (search "canSimRun" src))
    (is (search "st['external-matches']" src))
    (is (search "st['external-supported']" src))
    (is (search "btnSim\\\" disabled" src))
    (is (search "btnRun\\\" disabled" src))
    (is (search "setDisabled('btnRemember'" src))
    (is (search "Remember stays idle until a successful plan exists" src))
    (is (null (search "same rule as Simulate and Run" src)))
    (is (search "setDisabled('btnReact'" src))
    (is (search "setDisabled('btnEmit'" src))
    (is (search "setDisabled('btnFact'" src))
    (is (search "setDisabled('btnUse'" src))
    (is (search "found.applies" src))
    (is (search "setDisabled('btnScoreOk'" src))
    (is (search "setDisabled('btnScoreFail'" src))
    (is (search "setDisabled('btnAutoStep'" src))
    (is (search "setDisabled('btnAutoLoop'" src))
    (is (search "syncAutonomyControls" src))
    (is (search "autonomyMaxSteps" src))
    (is (search "autonomyPayload" src))
    (is (search "adapters = true" src))
    (is (search "planTouchesComputer" src))
    (is (search "setDisabled('btnRun', true)" src))
    (is (search "matching, supported plan" src))
    (is (search "markDisconnected" src))
    (is (search "idleMutationControls" src))
    (is (search "serverReachable" src))
    (is (search "if (!serverReachable)" src))
    (is (search "recognizes pending events" src))
    (is (search "Adapter actions run only if a new plan requires them" src))
    (is (null (search "may update facts and run adapter actions on this computer" src)))
    (is (null (search "adapters: false }).then(refresh)" src)))
    (is (search "/api/autonomy/policy" src))
    (is (null (search "max_steps: 4" src)))))

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
    (is (eq t (getf status :plan-success)))
    (is (eq t (getf status :external-matches)))
    (is (eq t (getf status :external-supported))))
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

(test web-api-archive-use-repairs-up-to-the-archive-depth
  "POST /api/archive/use repairs the chain at every depth the archive
allows, and /api/explain names every reused procedure."
  (loop for depth from 1 to *procedure-repair-archive-depth*
        do (gp-clear-memory)
           (let ((chain (%build-repair-chain depth :package :automa-gp)))
             (multiple-value-bind (code ctype json)
                 (web-api-handle-json :post "/api/archive/use"
                                      "{\"name\":\"CHARGE-THEN-USE\"}")
               (declare (ignore ctype))
               (is (= 200 code) "depth ~D: status ~D" depth code)
               (let* ((plan (getf (json->lisp json) :plan))
                      (steps (coerce (getf plan :steps) 'list)))
                 (loop for link in (getf chain :links)
                       for step in steps
                       do (is (string= (symbol-name link) (getf step :operator))
                              "depth ~D: expected ~A, got ~A"
                              depth link (getf step :operator)))
                 (is (string= "CHARGE" (getf (nth depth steps) :operator))
                     "depth ~D: CHARGE does not follow the repaired links"
                     depth)))
             (multiple-value-bind (code body)
                 (web-api-handle :get "/api/explain")
               (is (= 200 code) "depth ~D: explain status ~D" depth code)
               (dolist (name (getf chain :procedures))
                 (is (search (symbol-name name) (getf body :text))
                     "depth ~D: explanation does not mention ~A" depth name))))))

(test web-api-archive-use-stops-past-the-archive-depth
  "One level past the archive depth the façade answers 400 and the goal
stays open."
  (gp-clear-memory)
  (let ((chain (%build-repair-chain (1+ *procedure-repair-archive-depth*)
                                    :package :automa-gp)))
    (multiple-value-bind (code ctype json)
        (web-api-handle-json :post "/api/archive/use"
                             "{\"name\":\"CHARGE-THEN-USE\"}")
      (declare (ignore ctype))
      (is (= 400 code))
      (is (eq nil (getf (json->lisp json) :ok :missing))))
    (is (not (fact-p (getf chain :in-use) (gp-facts))))
    (is (fact-p (getf chain :root) (gp-facts)))))

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

(test web-api-listen-and-induce-rule
  (gp-clear-memory)
  (gp-reset)
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan"
                      '(:goals ((ready interface-01))))
    (declare (ignore body))
    (is (= 200 code)))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/status")
    (is (= 200 code))
    (is (eq t (getf body :listening))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-listen :reason :manual)
  (gp-remove-fact '(power-state interface-01 off))
  (gp-add-fact '(power-state interface-01 on))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/induce/rule"
                      (list :name 'power-on))
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (is (not (getf body :listening)))
    (let ((op (getf body :operator)))
      (is (eq 'power-on (getf op :name)))
      (is (equal '(interface-01) (getf (getf op :meta) :generalized))))))

(test web-api-edits-facts-by-symbol-name
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-plan :goals '((power-state interface-01 on)))
  (multiple-value-bind (code body)
      (web-api-handle-json :post "/api/remove-fact"
                           "{\"fact\":[\"POWER-STATE\",\"INTERFACE-01\",\"OFF\"]}")
    (declare (ignore body))
    (is (= 200 code)))
  (is (not (fact-p '(power-state interface-01 off) (gp-facts))))
  (web-api-handle-json :post "/api/add-fact"
                       "{\"fact\":[\"power-state\",\"interface-01\",\"on\"]}")
  (is (fact-p '(power-state interface-01 on) (gp-facts)))
  (let ((op (gp-induce-rule 'power-on)))
    (let ((x (find-symbol "?X0" :automa-gp)))
      (is (equal `((device ,x) (power-state ,x off))
                 (operator-preconditions op)))
      (is (equal `((power-state ,x on)) (operator-add-list op)))
      (is (equal `((power-state ,x off)) (operator-delete-list op)))
      (is (equal '(interface-01) (getf (operator-meta op) :generalized))))))

(test web-api-remove-fact
  (gp-clear-memory)
  (gp-reset)
  (web-api-handle :post "/api/add-fact"
                  (list :fact '(device interface-01)))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/remove-fact"
                      (list :fact '(device interface-01)))
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (is (not (fact-p '(device interface-01) (gp-facts))))))

(test web-api-explain-includes-narration
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (gp-plan :goals '((power-state interface-01 on)) :archive nil)
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/explain")
    (is (= 200 code))
    (is (search "POWER-ON" (getf body :narration)))
    (is (plusp (length (getf body :graph)))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/status")
    (is (= 200 code))
    (is (= automa-gp::*procedure-repair-archive-depth*
           (getf body :repair-depth)))))

(test web-api-induce-from-before-and-after
  (gp-clear-memory)
  (gp-reset)
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/induce"
                      (list :name 'free-port
                            :before '((port-bound 47391) (device interface-01))
                            :after '((port-free 47391) (device interface-01))))
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (let ((op (getf body :operator)))
      (is (eq 'free-port (getf op :name)))
      (is (equal '((port-bound 47391)) (getf op :preconditions)))
      (is (equal '((port-free 47391)) (getf op :add-list)))))
  (is (operator-p (find-operator (gp-context) 'free-port)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/induce"
                           "{\"name\":\"OPEN-FOLDER\",\"before\":[[\"folder\",\"notes\",\"missing\"]],\"after\":[[\"folder\",\"notes\",\"present\"]]}")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (search "OPEN-FOLDER" json))
    (is (operator-p (find-operator (gp-context) 'automa-gp::open-folder)))))

(test web-api-notice-path
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'on-file
                        :when '(automa-gp::file-created ?path)))
  (uiop:with-temporary-file (:pathname path)
    (let ((name (namestring path)))
      (multiple-value-bind (code ctype json)
          (web-api-handle-json :post "/api/notice-path"
                               (format nil "{\"path\":~A}" (lisp->json name)))
        (declare (ignore ctype))
        (is (= 200 code))
        (is (search "FILE-CREATED" json))
        (is (fact-p (list 'automa-gp::file-created name) (gp-facts)))))))

(test web-api-ask
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"raggiungi power-state interface-01 on\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (search "POWER-STATE" json))
    (is (find '(power-state interface-01 on) (gp-goals) :test #'equal)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"esegui rm\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not a request for a goal" json))))
