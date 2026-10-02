;;;; tests/test-ask.lisp — a phrase becomes a goal only when the context models it

(in-package #:automa-gp/tests)

(def-suite ask-suite :in automa-gp-suite)
(in-suite ask-suite)

(defun %ask-json (phrase)
  "POST PHRASE to /api/ask. Returns the status code and the JSON text."
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/ask"
                           (format nil "{\"phrase\":\"~A\"}" phrase))
    (declare (ignore ctype))
    (values code json)))

(defun %declared-words ()
  "Every :ASK word on an operator, a reaction, or a rule of the context."
  (append (loop for op in (gp-operators)
                append (getf (operator-meta op) :ask))
          (loop for reaction in (gp-reactions)
                append (getf (event-reaction-meta reaction) :ask))
          (loop for rule in (gp-rules)
                append (getf (rule-meta rule) :ask))))

(defun %add-operators (operators)
  "Start an empty context whose operators are OPERATORS.
Each is (NAME ADD): an operator with that one add pattern."
  (gp-clear-memory)
  (gp-reset)
  (loop for (name add) in operators
        do (gp-add-operator (make-operator :name name :add-list (list add)))))

(test ask-rejects-a-phrase-that-is-not-a-goal
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (signals phrase-refused (gp-ask "esegui power-state interface-01 on"))
  (signals phrase-refused (gp-ask "voglio eseguire power-state interface-01 on"))
  (signals phrase-refused (gp-ask "ciao"))
  (signals phrase-refused (gp-ask "voglio power-state interface-01 off"))
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
    ;; The phrase is understood: GP-ADD-GOAL refuses the goal that holds.
    (is (equal '(power-state interface-01 on)
               (gp-interpret "voglio power-state interface-01 on")))
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
  (signals phrase-refused (gp-ask "classifying note.txt"))
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
  (signals phrase-refused (gp-ask "classify note.txt"))
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
  (signals phrase-refused (gp-ask "power-state on"))
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
  (signals phrase-refused (gp-ask "power-state interface-01"))
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
  (signals phrase-refused (gp-ask "port-free"))
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
  (signals phrase-refused (gp-ask "accendi interface-01 off"))
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
  (signals phrase-refused (gp-ask "spegnere interface-01"))
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
  (signals phrase-refused (gp-ask "spegni"))
  (signals phrase-refused (gp-ask "spegni interface-01"))
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
  (signals phrase-refused (gp-ask "spegni interface-01"))
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

(defparameter *lone-word-cases*
  '((((mark-ready (system ready)))
     (("pronto") ("no goal of that shape"))
     (("ready") ("not declared" "\"choices\"" "MARK-READY" "READY")))
    (((mark-ready (system ready)) (mark-idle (system idle)))
     (("ready") ("not declared" "MARK-READY") ("MARK-IDLE")))
    (((mark-ready (system ready)) (mark-idle (system idle))
      (raise-flag (device ready)))
     (("ready") ("does not say which" "SYSTEM READY" "DEVICE READY")
      ("\"choices\"")))
    (((power-off (power-state ?d off)))
     (("spegni" "off") ("no goal of that shape")))
    (((power-on (lamp on)))
     (("power-one") ("is not the name" "POWER-ON") ("\"choices\""))
     (("on") ("not declared" "POWER-ON" "LAMP")))
    (((mark-ready (flag up)))
     (("ready") ("not declared" "MARK-READY" "FLAG"))
     (("pronto") ("no goal of that shape")))
    (((note-state (system pronto)))
     (("pronti" "pronta" "prontissimo" "prontissima" "prontamente"
       "prontezza" "prontezze")
      ("not declared" "NOTE-STATE" "PRONTO"))
     (("ready") ("no goal of that shape")))
    (((note-state (system pronto)) (mark-idle (device pronto)))
     (("pronti") ("does not say which" "SYSTEM PRONTO" "DEVICE PRONTO")
      ("\"choices\"")))
    (((segnala-pronto (flag up)))
     (("pronti" "prontissimo" "prontamente" "prontezza")
      ("no goal of that shape"))
     (("pronto") ("not declared" "SEGNALA-PRONTO" "FLAG")))
    (((note-state (lamp accendi)))
     (("accensione" "accendimento") ("not declared" "NOTE-STATE" "ACCENDI")))
    (((accendi (flag up)))
     (("accensione" "accendimento") ("no goal of that shape")))
    (((accendi (flag up)) (file-note (document classifica)))
     (("classificazione") ("not declared" "FILE-NOTE" "CLASSIFICA"))))
  "Each case is (OPERATORS . ASKS). Each of OPERATORS is (NAME ADD), an
operator with that one add. Each of ASKS is (WORDS PRESENT ABSENT): every
one of WORDS, said alone, is refused, and the answer of /api/ask holds
every string of PRESENT and none of ABSENT.")

(test ask-offers-a-lone-word-for-a-constant-goal
  (loop for (operators . asks) in *lone-word-cases*
        do (%add-operators operators)
           (loop for (words present absent) in asks
                 do (dolist (word words)
                      (signals phrase-refused (gp-ask word))
                      (multiple-value-bind (code json) (%ask-json word)
                        (is (= 400 code) "~S answered ~D." word code)
                        (dolist (text present)
                          (is (search text json)
                              "~S: ~S is missing from ~A" word text json))
                        (dolist (text absent)
                          (is (not (search text json))
                              "~S: ~S is in ~A" word text json)))
                      (is (null (gp-goals)))
                      (is (null (%declared-words)))))))

(test ask-names-a-constant-goal-by-a-declared-word
  (gp-clear-memory)
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

(test ask-offers-one-goal-that-two-names-reach
  ;; One goal is one goal, however many operators and rules reach it: the
  ;; word is offered for each of them and is not called unspecific.
  (%add-operators '((raise-flag (flag-raised red))))
  (gp-add-rule
   (make-rule :name 'flag-rule
              :if '((wind strong))
              :then '((flag-raised red))))
  (handler-case (progn (gp-interpret "red")
                       (fail "A lone word became a goal."))
    (undeclared-word (c)
      (is (equal "RED" (undeclared-word-word c)))
      (is (equal '((:operator raise-flag (flag-raised red))
                   (:rule flag-rule (flag-raised red)))
                 (undeclared-word-choices c)))))
  (multiple-value-bind (code json) (%ask-json "red")
    (is (= 400 code))
    (dolist (text '("not declared" "\"choices\"" "RAISE-FLAG" "FLAG-RULE"))
      (is (search text json) "~S is missing from ~A" text json)))
  (is (null (gp-goals)))
  (is (null (%declared-words))))

(test ask-drops-the-punctuation-that-ends-a-word
  (%add-operators '((power-on (power-state ?d on))))
  (gp-name-operator 'power-on "accendi")
  (gp-add-reaction
   (make-event-reaction :name 'classify
                        :when '(file-created ?path)
                        :goals '((document-classified ?path report))))
  (loop for (phrase goal)
          in '(("accendi interface-01." (power-state interface-01 on))
               ("accendi interface-01!" (power-state interface-01 on))
               ("voglio power-state interface-01 on."
                (power-state interface-01 on))
               ("power-state interface-01, on;" (power-state interface-01 on))
               ("power-state: interface-01 on?" (power-state interface-01 on))
               ("power-state interface-01 on ." (power-state interface-01 on))
               ("... power-state interface-01 !?" (power-state interface-01 on))
               ("classify note.txt." (document-classified "note.txt" report))
               ("classify Note.TXT, report."
                (document-classified "Note.TXT" report)))
        do (is (equal goal (gp-interpret phrase))
               "~S became ~S." phrase (ignore-errors (gp-interpret phrase))))
  ;; A word that asks for a command is one with a period after it too.
  (is (eq :command
          (handler-case (gp-interpret "power-state interface-01 on, esegui.")
            (phrase-refused (c) (phrase-refused-reason c)))))
  ;; A variable takes a word, never the punctuation that follows it.
  (%add-operators '((tag (tagged ?thing ?label))))
  (dolist (phrase '("tagged crate ." "tagged crate !" "tagged . crate"))
    (is (eq :unmodeled
            (handler-case (gp-interpret phrase)
              (phrase-refused (c) (phrase-refused-reason c))))
        "~S was not refused as unmodeled." phrase)))

(test ask-interns-a-new-word-beside-the-goal
  ;; A predicate that is a symbol of COMMON-LISP, or a keyword, is not the
  ;; place for a new word: it goes beside another fixed symbol of the
  ;; pattern, else in AUTOMA-GP.
  (loop for (add phrase goal home)
          in '(((open ?door) "open zz-ask-gate"
                (open zz-ask-gate) :automa-gp)
               ((open ?door wide) "open zz-ask-gate"
                (open zz-ask-gate wide) :automa-gp/tests)
               ((:zz-ask-state ?thing) "zz-ask-state zz-ask-gate"
                (:zz-ask-state zz-ask-gate) :automa-gp)
               ((:zz-ask-state ?thing held) "zz-ask-state zz-ask-gate"
                (:zz-ask-state zz-ask-gate held) :automa-gp/tests))
        do (%add-operators (list (list 'shape add)))
           (let ((found (gp-interpret phrase)))
             (is (fact-same-names-p goal found)
                 "~S became ~S." phrase found)
             (is (eq (find-package home) (symbol-package (second found)))
                 "~S put its word in ~A." phrase (symbol-package (second found)))))
  (dolist (package '(:common-lisp :keyword))
    (is (null (find-symbol "ZZ-ASK-GATE" package)))))

(test ask-takes-a-word-from-the-facts-before-a-pattern
  ;; The word for a variable is the symbol the facts use, so the goal is
  ;; one the operator's preconditions can meet. A symbol of the same name
  ;; that only a pattern mentions, in another package, does not win.
  (dolist (facts '(((device crate) (device cl-user::crate))
                   ((device cl-user::crate) (device crate))
                   ((device crate))))
    (gp-clear-memory)
    (gp-reset)
    (mapc #'gp-add-fact facts)
    (gp-add-operator
     (make-operator :name 'power-on
                    :preconditions '((device ?d))
                    :add-list '((power-state ?d on))))
    (gp-add-operator
     (make-operator :name 'stock
                    :preconditions '((cl-user::crate ?x))
                    :add-list '((stocked ?x))))
    (gp-add-rule
     (make-rule :name 'stored
                :if '((holds cl-user::crate))
                :then '((stock-known))))
    (multiple-value-bind (goal plan)
        (gp-ask "power-state crate on")
      (is (equal '(power-state crate on) goal)
          "With the facts ~S the goal is ~S." facts goal)
      (is (plan-success plan)))))

(test ask-refuses-with-a-reason
  (%add-operators '((power-on (power-state ?d on))))
  (loop for (phrase reason)
          in '((42 :no-phrase)
               ("" :no-phrase)
               ("  ?! ... " :no-phrase)
               ("esegui power-state lamp on" :command)
               ("voglio eseguire power-state lamp on" :command)
               ("power-state lamp on sudo." :command)
               ("voglio" :no-terms)
               ("voglio che sia" :no-terms)
               ("ciao" :unmodeled)
               ("power-state lamp off" :unmodeled))
        do (let ((refusal (handler-case (gp-ask phrase)
                            (phrase-refused (c) c))))
             (is (typep refusal 'phrase-refused)
                 "~S became ~S." phrase refusal)
             (when (typep refusal 'phrase-refused)
               (is (eq reason (phrase-refused-reason refusal))
                   "~S was refused as ~S." phrase (phrase-refused-reason refusal))
               (is (plusp (length (princ-to-string refusal)))))))
  (is (null (gp-goals)))
  (is (null (gp-facts))))

(defun %goals-named (refusal)
  "The candidate goals the PHRASE-REFUSED REFUSAL names."
  (etypecase refusal
    (ambiguous-goal (ambiguous-goal-goals refusal))
    (unspecific-word (unspecific-word-goals refusal))
    (unrelated-word (unrelated-word-goals refusal))
    (undeclared-word (mapcar #'third (undeclared-word-choices refusal)))))

(test ask-use-value-takes-one-of-the-goals-named
  (loop for (type operators phrase)
          in '((ambiguous-goal
                ((power-on (power-state ?d on)) (power-off (power-state ?d off)))
                "power-state lamp")
               (unrelated-word
                ((power-on (power-state ?d on)) (power-off (power-state ?d off)))
                "spegni lamp")
               (unspecific-word
                ((mark-ready (system ready)) (raise-flag (device ready)))
                "ready")
               (undeclared-word
                ((mark-ready (system ready)))
                "ready"))
        do (%add-operators operators)
           ;; Without a handler the refusal stands and nothing is recorded.
           (signals phrase-refused (gp-ask phrase))
           (is (null (gp-goals)))
           ;; A handler picks a candidate. It may spell it with symbols of
           ;; any package: the goal recorded is the candidate itself.
           (let* ((picked nil)
                  (goal (handler-bind
                            ((phrase-refused
                               (lambda (c)
                                 (is (typep c type)
                                     "~S signalled a ~S." phrase (type-of c))
                                 (setf picked (first (last (%goals-named c))))
                                 (use-value
                                  (mapcar (lambda (term)
                                            (if (symbolp term)
                                                (make-symbol (symbol-name term))
                                                term))
                                          picked)
                                  c))))
                          (gp-ask phrase))))
             (is (eq picked goal))
             (is (equal (list picked) (gp-goals)))
             (is (null (%declared-words))))
           ;; A value that is not a candidate is refused the same way.
           (gp-remove-goal (first (gp-goals)))
           (let* ((refusals 0)
                  (goal (handler-bind
                            ((phrase-refused
                               (lambda (c)
                                 (use-value (if (= 1 (incf refusals))
                                                '(not a candidate)
                                                (first (%goals-named c)))
                                            c))))
                          (gp-interpret phrase))))
             (is (= 2 refusals))
             (is (consp goal))
             (is (null (gp-goals))))))

(test ask-use-value-reads-the-goal-at-the-terminal
  (%add-operators '((power-on (power-state ?d on))
                    (power-off (power-state ?d off))))
  (let* ((*package* (find-package :automa-gp/tests))
         (*query-io* (make-two-way-stream
                      (make-string-input-stream "(power-state lamp off)")
                      (make-broadcast-stream)))
         (goal (handler-bind ((ambiguous-goal
                                (lambda (c)
                                  (invoke-restart-interactively
                                   (find-restart 'use-value c)))))
                 (gp-interpret "power-state lamp"))))
    (is (equal '(power-state lamp off) goal))
    (is (null (gp-goals)))))

(test ask-conditions-are-public-and-documented
  (let ((refusals '(ambiguous-goal undeclared-word unspecific-word
                    unrelated-word not-that-name)))
    (dolist (type refusals)
      (is (subtypep type 'phrase-refused)))
    (dolist (type (list* 'phrase-refused 'word-refused refusals))
      (is (subtypep type 'error))
      (is (documentation type 'type))
      (is (eq :external
              (nth-value 1 (find-symbol (symbol-name type) :automa-gp))))))
  (dolist (reader '(phrase-refused-reason ambiguous-goal-goals
                    undeclared-word-word undeclared-word-choices
                    unspecific-word-word unspecific-word-goals
                    unrelated-word-word unrelated-word-goals
                    not-that-name-word not-that-name-name
                    word-refused-word word-refused-name word-refused-kind
                    word-refused-reason word-refused-holder))
    (is (fboundp reader))
    (is (eq :external
            (nth-value 1 (find-symbol (symbol-name reader) :automa-gp))))))

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
  (signals phrase-refused (gp-ask "accendi interface-01"))
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
  (signals word-refused (gp-name-operator 'power-on "spegnere"))
  (is (null (getf (operator-meta (find-operator (gp-context) 'power-on)) :ask)))
  (signals word-refused (gp-name-operator 'power-off "esegui"))
  (is (= 1 (length (getf (operator-meta (find-operator (gp-context) 'power-off))
                         :ask))))
  (signals word-refused (gp-name-operator 'missing "accendi")))

(test name-operator-declares-a-word-on-a-reaction-or-a-rule
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'classify
                        :when '(file-created ?path)
                        :goals '((document-classified ?path report))))
  (signals phrase-refused (gp-ask "classificare note.txt"))
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
  (signals word-refused (gp-name-operator 'classify "accendere"))
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
  (signals word-refused (gp-name-operator 'classify "etichetta"))
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
  (signals phrase-refused (gp-ask "classify note.txt"))
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
  (signals word-refused (gp-name-operator 'classify "archiviare" :kind :reaction))
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

(test name-operator-refuses-with-a-reason
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'power-on
                  :add-list '((power-state ?d on))
                  :meta '(:ask (accendi))))
  (gp-add-operator
   (make-operator :name 'classify
                  :add-list '((filed ?path))))
  (gp-add-reaction
   (make-event-reaction :name 'classify
                        :when '(file-created ?path)
                        :goals '((document-classified ?path report))))
  (loop for (name word kind reason holder)
          in '((power-on "" nil :not-a-word)
               (power-on "?!" nil :not-a-word)
               (power-on "due parole" nil :not-a-word)
               (power-on "note.txt" nil :not-a-word)
               (power-on "bin/avvia" nil :not-a-word)
               (missing "avvia" nil :unknown-name)
               (power-on "avvia" :rule :unknown-name)
               (power-on "avvia" "reaction" :unknown-name)
               (classify "archivia" nil :shared-name)
               (power-on "esegui" nil :reserved)
               (power-on "voglio" nil :reserved)
               (power-on "della" nil :reserved)
               (classify "accendere" :reaction :taken (:operator power-on))
               (classify "power-on" :operator :taken (:operator power-on))
               (power-on "classify" nil :taken (:operator classify)))
        do (let ((refusal (handler-case (gp-name-operator name word :kind kind)
                            (word-refused (c) c))))
             (is (typep refusal 'word-refused)
                 "~S was declared on ~S." word name)
             (when (typep refusal 'word-refused)
               (is (eq reason (word-refused-reason refusal))
                   "~S on ~S was refused as ~S."
                   word name (word-refused-reason refusal))
               (is (equal holder (word-refused-holder refusal)))
               (is (eq name (word-refused-name refusal)))
               (is (plusp (length (princ-to-string refusal)))))))
  (is (equal '(accendi) (%declared-words)))
  ;; A kind that is none of the three is not a refusal of the word.
  (signals unknown-keyword (gp-name-operator 'power-on "avvia" :kind "banana"))
  (is (equal '(accendi) (%declared-words)))
  ;; The word is read as GP-ASK reads it: without the punctuation after it.
  (gp-name-operator 'power-on "avvia.")
  (is (equal '(accendi "AVVIA") (%declared-words)))
  (is (equal '(power-state lamp on) (gp-interpret "avviare lamp."))))

(test name-operator-refuses-an-action-lifted-for-planning
  ;; While a context has no operator, planning lifts its actions afresh on
  ;; every call. Registering one of them as an operator would hide all the
  ;; others, so a word for it is refused and nothing changes.
  (gp-clear-memory)
  (gp-reset)
  (register-action! (gp-context)
                    (make-action :name 'open-door :effects '((door open))))
  (register-action! (gp-context)
                    (make-action :name 'light-on :effects '((light on))))
  (let ((names (mapcar #'operator-name (gp-operators))))
    (is (= 2 (length names)))
    (handler-case (progn (gp-name-operator 'open-door "apri")
                         (fail "A lifted action took a word."))
      (word-refused (c)
        (is (eq :lifted-action (word-refused-reason c)))
        (is (search "OPEN-DOOR is an action" (princ-to-string c)))))
    (is (equal names (mapcar #'operator-name (gp-operators))))
    (is (null (context-all-operators (gp-context))))
    (is (equal '(light on) (gp-interpret "light on")))
    (is (equal '(door open) (gp-interpret "open-door")))
    ;; Its own name is already its word: there is nothing to declare.
    (is (operator-p (gp-name-operator 'open-door "open-door")))
    (is (null (context-all-operators (gp-context)))))
  ;; Once it is an operator of the context, it takes the word.
  (gp-add-operator (find-operator (gp-context) 'open-door))
  (gp-name-operator 'open-door "apri")
  (is (equal '("APRI") (%declared-words)))
  (is (equal '(door open) (gp-interpret "apri"))))

(test name-operator-keeps-a-rule-built-past-unsafe-rule
  (gp-clear-memory)
  (gp-reset)
  (gp-add-rule (handler-bind ((unsafe-rule #'continue))
                 (make-rule :name 'loose
                            :if '((seen ?x))
                            :then '((linked ?x ?y)))))
  (let ((rule (gp-name-operator 'loose "sciolto")))
    (is (rule-p rule))
    (is (equal '("SCIOLTO") (getf (rule-meta rule) :ask)))
    (is (equal '((seen ?x)) (rule-if rule)))
    (is (equal '((linked ?x ?y)) (rule-then rule)))
    (is (equal (list rule) (gp-rules)))))

(test name-operator-leaves-an-inherited-operator-as-it-was
  ;; The word is declared on a copy in the current context. The operator
  ;; the parent holds, and every other context that inherits it, keep
  ;; their own words.
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'power-on
                  :add-list '((power-state ?d on))
                  :cost 3
                  :risk :medium
                  :reversible nil
                  :meta '(:domain bench)))
  (let* ((parent (gp-context))
         (inherited (find-operator parent 'power-on)))
    (gp-context :name 'child :parent parent)
    (let ((named (gp-name-operator 'power-on "accendi")))
      (is (not (eq inherited named)))
      (is (eq named (find-operator (gp-context) 'power-on)))
      (is (eq inherited (find-operator parent 'power-on)))
      (is (null (getf (operator-meta inherited) :ask)))
      (is (equal '("ACCENDI") (getf (operator-meta named) :ask)))
      (is (eq 'bench (getf (operator-meta named) :domain)))
      (loop for reader in (list #'operator-name #'operator-parameters
                                #'operator-preconditions #'operator-add-list
                                #'operator-delete-list #'operator-cost
                                #'operator-action #'operator-reversible
                                #'operator-risk)
            do (is (equal (funcall reader inherited) (funcall reader named)))))))
