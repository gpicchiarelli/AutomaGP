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
    (is (string= "0.11.0" (getf body :api))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/reset")
    (is (= 200 code))
    (is (eq t (getf body :ok)))))

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
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan"
                      (list :goals '(("device-configured" "interface-01"))))
    (is (= 200 code))
    (is (eq t (getf (getf body :plan) :success))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/simulate")
    (is (= 200 code))
    (is (eq t (getf (getf body :execution) :success)))))

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
