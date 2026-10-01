;;;; tests/test-ask.lisp — a phrase becomes a goal only when the context models it

(in-package #:automa-gp/tests)

(def-suite ask-suite :in automa-gp-suite)
(in-suite ask-suite)

(test ask-rejects-a-phrase-that-is-not-a-goal
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (signals error (gp-ask "esegui power-state interface-01 on"))
  (signals error (gp-ask "voglio eseguire power-state interface-01 on"))
  (signals error (gp-ask "ciao"))
  (signals error (gp-ask "voglio power-state interface-01 off"))
  (is (null (gp-goals)))
  (is (null (gp-facts))))

(test ask-records-a-modeled-goal-without-changing-facts
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (let ((facts (copy-tree (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "voglio che power-state interface-01 sia on")
      (is (equal '(power-state interface-01 on) goal))
      (is (plan-success plan))
      (is (equal facts (gp-facts)))
      (is (not (observation-active-p)))
      (is (find goal (gp-goals) :test #'equal))))
  (gp-add-fact '(power-state interface-01 on))
  (let ((goals (copy-tree (gp-goals)))
        (plan (gp-last-plan)))
    (signals error (gp-ask "voglio power-state interface-01 on"))
    (is (equal goals (gp-goals)))
    (is (eq plan (gp-last-plan)))
    (multiple-value-bind (code body)
        (web-api-handle :post "/api/ask"
                        '(:phrase "voglio power-state interface-01 on"))
      (is (= 400 code))
      (is (search "already holds" (getf body :error))))
    (is (equal goals (gp-goals)))
    (is (eq plan (gp-last-plan)))))

(test ask-accepts-a-goal-shape-without-a-leading-verb
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (let ((facts (copy-tree (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "fammi avere power-state interface-01 on")
      (is (equal '(power-state interface-01 on) goal))
      (is (plan-success plan))
      (is (equal facts (gp-facts)))))
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (multiple-value-bind (goal plan)
      (gp-ask "power-state interface-01 on")
    (is (equal '(power-state interface-01 on) goal))
    (is (plan-success plan))))

(test ask-keeps-a-number-and-a-reaction-goal
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'free-port
                  :add-list '((port-free ?p))))
  (multiple-value-bind (goal plan)
      (gp-ask "obiettivo port-free 47391")
    (declare (ignore plan))
    (is (equal '(port-free 47391) goal)))
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'classify
                        :when '(file-created ?path)
                        :goals '((document-classified ?path report))))
  (multiple-value-bind (goal plan)
      (gp-ask "manca document-classified note.txt report")
    (is (equal '(document-classified "note.txt" report) goal))
    (is (not (plan-success plan)))
    (is (observation-active-p))
    (is (null (gp-facts)))))

(test ask-names-a-reaction-or-a-rule
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'classify
                        :when '(file-created ?path)
                        :goals '((document-classified ?path report))))
  (let ((facts (copy-tree (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "classify note.txt")
      (declare (ignore plan))
      (is (equal '(document-classified "note.txt" report) goal))
      (is (equal facts (gp-facts)))))
  (signals error (gp-ask "classifying note.txt"))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"classify note.txt\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (search "DOCUMENT-CLASSIFIED" json)))
  (gp-reset)
  (gp-add-rule
   (make-rule :name 'device-ready
              :if '((device-configured ?d))
              :then '((peripheral-ready ?d))))
  (multiple-value-bind (goal plan)
      (gp-ask "device-ready interface-01")
    (declare (ignore plan))
    (is (equal '(peripheral-ready interface-01) goal))))

(test ask-refuses-a-reaction-and-an-operator-with-one-name
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'classify
                  :add-list '((filed ?path))))
  (gp-add-reaction
   (make-event-reaction :name 'classify
                        :when '(file-created ?path)
                        :goals '((document-classified ?path report))))
  (signals error (gp-ask "classify note.txt"))
  (is (null (gp-goals))))

(test ask-fills-a-fixed-term-left-unsaid
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (let ((facts (copy-tree (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "power-state interface-01")
      (is (equal '(power-state interface-01 on) goal))
      (is (plan-success plan))
      (is (equal facts (gp-facts)))))
  (signals error (gp-ask "power-state on"))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'free-port
                  :add-list '((port-free 47391))))
  (multiple-value-bind (goal plan)
      (gp-ask "port-free")
    (declare (ignore plan))
    (is (equal '(port-free 47391) goal)))
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'classify
                        :when '(file-created ?path)
                        :goals '((document-classified ?path report))))
  (multiple-value-bind (goal plan)
      (gp-ask "document-classified note.txt")
    (declare (ignore plan))
    (is (equal '(document-classified "note.txt" report) goal))))

(test ask-refuses-when-two-goals-fit
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'power-on
                  :add-list '((power-state ?d on))))
  (gp-add-operator
   (make-operator :name 'power-off
                  :add-list '((power-state ?d off))))
  (signals error (gp-ask "power-state interface-01"))
  (is (null (gp-goals)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"power-state interface-01\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "more than one goal" json))
    (is (search "\"ON\"" json))
    (is (search "\"OFF\"" json)))
  (is (null (gp-goals)))
  (let ((facts (copy-tree (gp-facts))))
    (multiple-value-bind (code ctype json)
        (web-api-handle-json :post "/api/add-goal"
                             "{\"goal\":[\"power-state\",\"interface-01\",\"off\"]}")
      (declare (ignore ctype json))
      (is (= 200 code)))
    (multiple-value-bind (code ctype json)
        (web-api-handle-json :post "/api/plan"
                             "{\"goals\":[[\"power-state\",\"interface-01\",\"off\"]]}")
      (declare (ignore ctype json))
      (is (= 200 code)))
    (is (= 1 (length (gp-goals))))
    (is (equal facts (gp-facts)))
    (gp-remove-goal (first (gp-goals)))
    (is (null (gp-goals))))
  (multiple-value-bind (goal plan)
      (gp-ask "power-state interface-01 off")
    (declare (ignore plan))
    (is (equal '(power-state interface-01 off) goal)))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'free-a
                  :add-list '((port-free 47391))))
  (gp-add-operator
   (make-operator :name 'free-b
                  :add-list '((port-free 47392))))
  (signals error (gp-ask "port-free"))
  (is (null (gp-goals))))

(test ask-names-an-operator-instead-of-the-predicate
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))
                  :meta '(:ask (accendi))))
  (let ((facts (copy-tree (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "power-on interface-01")
      (is (equal '(power-state interface-01 on) goal))
      (is (plan-success plan))
      (is (equal facts (gp-facts)))))
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))
                  :meta '(:ask (accendi))))
  (multiple-value-bind (goal plan)
      (gp-ask "voglio accendi interface-01")
    (is (equal '(power-state interface-01 on) goal))
    (is (plan-success plan))
    (is (fact-p '(power-state interface-01 off) (gp-facts))))
  (signals error (gp-ask "accendi interface-01 off"))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'free-port
                  :add-list '((port-free 47391))))
  (multiple-value-bind (goal plan)
      (gp-ask "free-port")
    (declare (ignore plan))
    (is (equal '(port-free 47391) goal)))
  (gp-reset)
  (gp-load-domain :hardware :seed-demo t)
  (multiple-value-bind (goal plan)
      (gp-ask "accendi interface-01")
    (declare (ignore plan))
    (is (equal '(automa-gp::power-state automa-gp::interface-01 automa-gp::on)
               goal))
    (is (fact-p '(automa-gp::power-state automa-gp::interface-01 automa-gp::off)
                (gp-facts)))))

(test ask-accepts-another-form-of-a-declared-word
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))
                  :meta '(:ask (accendi))))
  (let ((facts (copy-tree (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "accendere interface-01")
      (is (equal '(power-state interface-01 on) goal))
      (is (plan-success plan))
      (is (equal facts (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "accendissimo interface-01")
      (is (equal '(power-state interface-01 on) goal))
      (is (plan-success plan))
      (is (equal facts (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "accensione interface-01")
      (is (equal '(power-state interface-01 on) goal))
      (is (plan-success plan))
      (is (equal facts (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "accendimento interface-01")
      (is (equal '(power-state interface-01 on) goal))
      (is (plan-success plan))
      (is (equal facts (gp-facts)))))
  (let ((goals (copy-tree (gp-goals)))
        (text nil))
    (handler-case (gp-ask "power-one interface-01")
      (error (c) (setf text (princ-to-string c))))
    (is (and text (search "is not the name" text)))
    (is (and text (search "POWER-ONE" text)))
    (is (and text (search "POWER-ON" text)))
    (is (equal goals (gp-goals))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"power-one interface-01\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "is not the name" json))
    (is (search "POWER-ON" json))
    (is (not (search "\"choices\"" json))))
  (signals error (gp-ask "spegnere interface-01"))
  (is (fact-p '(power-state interface-01 off) (gp-facts))))

(test ask-offers-an-undeclared-word-when-the-rest-fits
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 on))
  (gp-add-operator
   (make-operator :name 'power-off
                  :preconditions '((device ?d) (power-state ?d on))
                  :add-list '((power-state ?d off))
                  :delete-list '((power-state ?d on))))
  (signals error (gp-ask "spegni"))
  (signals error (gp-ask "spegni interface-01"))
  (is (null (gp-goals)))
  (is (null (getf (operator-meta (find-operator (gp-context) 'power-off)) :ask)))
  (let ((facts (copy-tree (gp-facts))))
    (multiple-value-bind (code ctype json)
        (web-api-handle-json :post "/api/ask"
                             "{\"phrase\":\"spegni interface-01\"}")
      (declare (ignore ctype))
      (is (= 400 code))
      (is (search "other words fit" json))
      (is (search "POWER-STATE" json))
      (is (search "INTERFACE-01" json))
      (is (search "\"OFF\"" json))
      (is (not (search "\"choices\"" json))))
    (multiple-value-bind (code ctype json)
        (web-api-handle-json :post "/api/ask"
                             "{\"phrase\":\"spegni\"}")
      (declare (ignore ctype))
      (is (= 400 code))
      (is (search "no goal of that shape" json)))
    (is (null (gp-goals)))
    (is (equal facts (gp-facts))))
  (gp-name-operator 'power-off "spegni")
  (let ((facts (copy-tree (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "spegnere interface-01")
      (is (equal '(power-state interface-01 off) goal))
      (is (plan-success plan))
      (is (equal facts (gp-facts)))))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'power-on
                  :add-list '((power-state ?d on))))
  (gp-add-operator
   (make-operator :name 'power-off
                  :add-list '((power-state ?d off))))
  (signals error (gp-ask "spegni interface-01"))
  (is (null (gp-goals)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"spegni interface-01\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "other words fit" json))
    (is (search "\"ON\"" json))
    (is (search "\"OFF\"" json))
    (is (not (search "\"choices\"" json))))
  (is (null (getf (operator-meta (find-operator (gp-context) 'power-on)) :ask)))
  (is (null (getf (operator-meta (find-operator (gp-context) 'power-off)) :ask)))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'note-state
                  :add-list '((system pronto))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"pronti system\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "\"choices\"" json))
    (is (search "NOTE-STATE" json))
    (is (search "PRONTO" json)))
  (is (null (gp-goals)))
  (is (null (getf (operator-meta (find-operator (gp-context) 'note-state)) :ask))))

(test ask-offers-a-lone-word-for-a-constant-goal
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'mark-ready
                  :add-list '((system ready))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"pronto\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "no goal of that shape" json)))
  (is (null (gp-goals)))
  (is (null (getf (operator-meta (find-operator (gp-context) 'mark-ready)) :ask)))
  (signals error (gp-ask "ready"))
  (is (null (gp-goals)))
  (is (null (getf (operator-meta (find-operator (gp-context) 'mark-ready)) :ask)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"ready\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "MARK-READY" json))
    (is (search "READY" json)))
  (is (null (gp-goals)))
  (gp-add-operator
   (make-operator :name 'mark-idle
                  :add-list '((system idle))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"ready\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "MARK-READY" json))
    (is (not (search "MARK-IDLE" json))))
  (gp-add-operator
   (make-operator :name 'raise-flag
                  :add-list '((device ready))))
  (let ((text nil))
    (handler-case (gp-ask "ready")
      (error (c) (setf text (princ-to-string c))))
    (is (and text (search "does not say which" text)))
    (is (and text (search "SYSTEM READY" text)))
    (is (and text (search "DEVICE READY" text))))
  (is (null (gp-goals)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"ready\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "does not say which" json))
    (is (search "SYSTEM READY" json))
    (is (search "DEVICE READY" json))
    (is (not (search "\"choices\"" json))))
  (is (null (getf (operator-meta (find-operator (gp-context) 'mark-ready)) :ask)))
  (is (null (getf (operator-meta (find-operator (gp-context) 'mark-idle)) :ask)))
  (is (null (getf (operator-meta (find-operator (gp-context) 'raise-flag)) :ask)))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'power-off
                  :add-list '((power-state ?d off))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"spegni\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "no goal of that shape" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"off\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "no goal of that shape" json)))
  (is (null (gp-goals)))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'power-on
                  :add-list '((lamp on))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"power-one\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "is not the name" json))
    (is (search "POWER-ON" json))
    (is (not (search "\"choices\"" json))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"on\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "POWER-ON" json))
    (is (search "LAMP" json)))
  (is (null (gp-goals)))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'mark-ready
                  :add-list '((flag up))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"ready\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "MARK-READY" json))
    (is (search "FLAG" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"pronto\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "no goal of that shape" json)))
  (is (null (gp-goals)))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'note-state
                  :add-list '((system pronto))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"pronti\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "NOTE-STATE" json))
    (is (search "PRONTO" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"pronta\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "PRONTO" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"prontissimo\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "NOTE-STATE" json))
    (is (search "PRONTO" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"prontissima\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "PRONTO" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"prontamente\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "NOTE-STATE" json))
    (is (search "PRONTO" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"prontezza\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "NOTE-STATE" json))
    (is (search "PRONTO" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"prontezze\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "PRONTO" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"ready\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "no goal of that shape" json)))
  (is (null (gp-goals)))
  (is (null (getf (operator-meta (find-operator (gp-context) 'note-state)) :ask)))
  (gp-add-operator
   (make-operator :name 'mark-idle
                  :add-list '((device pronto))))
  (let ((text nil))
    (handler-case (gp-ask "pronti")
      (error (c) (setf text (princ-to-string c))))
    (is (and text (search "does not say which" text)))
    (is (and text (search "SYSTEM PRONTO" text)))
    (is (and text (search "DEVICE PRONTO" text))))
  (is (null (gp-goals)))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'segnala-pronto
                  :add-list '((flag up))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"pronti\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "no goal of that shape" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"prontissimo\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "no goal of that shape" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"prontamente\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "no goal of that shape" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"prontezza\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "no goal of that shape" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"pronto\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "SEGNALA-PRONTO" json))
    (is (search "FLAG" json)))
  (is (null (gp-goals)))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'note-state
                  :add-list '((lamp accendi))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"accensione\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "NOTE-STATE" json))
    (is (search "ACCENDI" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"accendimento\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "NOTE-STATE" json))
    (is (search "ACCENDI" json)))
  (is (null (gp-goals)))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'accendi
                  :add-list '((flag up))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"accensione\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "no goal of that shape" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"accendimento\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "no goal of that shape" json)))
  (gp-add-operator
   (make-operator :name 'file-note
                  :add-list '((document classifica))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"classificazione\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "not declared" json))
    (is (search "FILE-NOTE" json))
    (is (search "CLASSIFICA" json)))
  (is (null (gp-goals)))
  (gp-reset)
  (gp-add-fact '(bench clear))
  (gp-add-operator
   (make-operator :name 'mark-ready
                  :preconditions '((bench clear))
                  :add-list '((system ready))
                  :delete-list '((bench clear))))
  (gp-name-operator 'mark-ready "pronto")
  (let ((facts (copy-tree (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "pronti")
      (is (equal '(system ready) goal))
      (is (plan-success plan))
      (is (equal facts (gp-facts))))))

(test ask-refuses-two-operators-that-share-a-word
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'power-on
                  :add-list '((power-state ?d on))
                  :meta '(:ask (accendi))))
  (gp-add-operator
   (make-operator :name 'power-off
                  :add-list '((power-state ?d off))
                  :meta '(:ask (accendi))))
  (signals error (gp-ask "accendi interface-01"))
  (is (null (gp-goals)))
  (multiple-value-bind (goal plan)
      (gp-ask "power-off interface-01")
    (declare (ignore plan))
    (is (equal '(power-state interface-01 off) goal)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           "{\"phrase\":\"accendi interface-01\"}")
    (declare (ignore ctype))
    (is (= 400 code))
    (is (search "more than one goal" json))))

(test name-operator-declares-a-word
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 on))
  (gp-add-operator
   (make-operator :name 'power-off
                  :preconditions '((device ?d) (power-state ?d on))
                  :add-list '((power-state ?d off))
                  :delete-list '((power-state ?d on))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/operator/name"
                           "{\"name\":\"power-off\",\"word\":\"spegnere\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (search "SPEGNERE" json)))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :get "/api/operators")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (search "\"POWER-OFF\"" json))
    (is (search "SPEGNERE" json)))
  (let ((facts (copy-tree (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "spegni interface-01")
      (is (equal '(power-state interface-01 off) goal))
      (is (plan-success plan))
      (is (equal facts (gp-facts)))))
  (gp-name-operator 'power-off "spegni")
  (is (= 1 (length (getf (operator-meta (find-operator (gp-context) 'power-off))
                         :ask))))
  (gp-add-operator
   (make-operator :name 'power-on
                  :add-list '((power-state ?d on))))
  (signals error (gp-name-operator 'power-on "spegnere"))
  (is (null (getf (operator-meta (find-operator (gp-context) 'power-on)) :ask)))
  (signals error (gp-name-operator 'power-off "esegui"))
  (is (= 1 (length (getf (operator-meta (find-operator (gp-context) 'power-off))
                         :ask))))
  (signals error (gp-name-operator 'missing "accendi")))

(test name-operator-declares-a-word-on-a-reaction-or-a-rule
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'classify
                        :when '(file-created ?path)
                        :goals '((document-classified ?path report))))
  (signals error (gp-ask "classificare note.txt"))
  (gp-name-operator 'classify "classifica")
  (let ((facts (copy-tree (gp-facts))))
    (multiple-value-bind (goal plan)
        (gp-ask "classificare note.txt")
      (declare (ignore plan))
      (is (equal '(document-classified "note.txt" report) goal))
      (is (equal facts (gp-facts)))))
  (gp-name-operator 'classify "classifica")
  (is (= 1 (length (getf (event-reaction-meta
                          (find 'classify (gp-reactions)
                                :key #'event-reaction-name))
                         :ask))))
  (gp-add-operator
   (make-operator :name 'power-on
                  :add-list '((power-state ?d on))
                  :meta '(:ask (accendi))))
  (signals error (gp-name-operator 'classify "accendere"))
  (is (= 1 (length (getf (event-reaction-meta
                          (find 'classify (gp-reactions)
                                :key #'event-reaction-name))
                         :ask))))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'classify
                  :add-list '((filed ?path))))
  (gp-add-reaction
   (make-event-reaction :name 'classify
                        :when '(file-created ?path)
                        :goals '((document-classified ?path report))))
  (signals error (gp-name-operator 'classify "etichetta"))
  (is (null (getf (operator-meta (find-operator (gp-context) 'classify)) :ask)))
  (is (null (getf (event-reaction-meta
                   (find 'classify (gp-reactions) :key #'event-reaction-name))
                  :ask)))
  (gp-name-operator 'classify "etichetta" :kind :reaction)
  (is (null (getf (operator-meta (find-operator (gp-context) 'classify)) :ask)))
  (is (equal '("ETICHETTA")
             (getf (event-reaction-meta
                    (find 'classify (gp-reactions) :key #'event-reaction-name))
                   :ask)))
  (multiple-value-bind (goal plan)
      (gp-ask "etichettare note.txt")
    (declare (ignore plan))
    (is (equal '(document-classified "note.txt" report) goal)))
  (signals error (gp-ask "classify note.txt"))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/operator/name"
                           "{\"name\":\"classify\",\"word\":\"archivia\",\"kind\":\"operator\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (search "ARCHIVIA" json)))
  (is (equal '("ARCHIVIA")
             (getf (operator-meta (find-operator (gp-context) 'classify)) :ask)))
  (is (equal '("ETICHETTA")
             (getf (event-reaction-meta
                    (find 'classify (gp-reactions) :key #'event-reaction-name))
                   :ask)))
  (signals error (gp-name-operator 'classify "archiviare" :kind :reaction))
  (is (equal '("ETICHETTA")
             (getf (event-reaction-meta
                    (find 'classify (gp-reactions) :key #'event-reaction-name))
                   :ask)))
  (gp-reset)
  (gp-add-rule
   (make-rule :name 'device-ready
              :if '((device-configured ?d))
              :then '((peripheral-ready ?d))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/operator/name"
                           "{\"name\":\"device-ready\",\"word\":\"pronto\"}")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (search "PRONTO" json)))
  (multiple-value-bind (goal plan)
      (gp-ask "pronti interface-01")
    (declare (ignore plan))
    (is (equal '(peripheral-ready interface-01) goal))
    (is (null (gp-facts))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :get "/api/rules")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (search "DEVICE-READY" json))
    (is (search "PRONTO" json)))
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'classify
                        :when '(file-created ?path)
                        :goals '((document-classified ?path report))))
  (gp-name-operator 'classify "classifica")
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :get "/api/reactions")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (search "\"CLASSIFY\"" json))
    (is (search "CLASSIFICA" json))))
