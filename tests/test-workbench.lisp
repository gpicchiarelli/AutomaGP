;;;; tests/test-workbench.lisp — narration and one-shot induction

(in-package #:automa-gp/tests)

(def-suite workbench-suite :in automa-gp-suite)
(in-suite workbench-suite)

(test narrate-trace-uses-recorded-operators-only
  (clear-trace-session)
  (let* ((facts '((device interface-01) (power-state interface-01 off)))
         (goals '((connection interface-01 computer)))
         (ops (list (make-operator :name 'power-on
                                   :preconditions '((device ?d) (power-state ?d off))
                                   :add-list '((power-state ?d on))
                                   :delete-list '((power-state ?d off)))
                    (make-operator :name 'connect
                                   :preconditions '((device ?d) (power-state ?d on))
                                   :add-list '((connection ?d computer)))))
         (plan (plan-for facts goals ops :context-name 'studio-audio)))
    (multiple-value-bind (text nodes) (narrate-trace (trace-of plan))
      (is (search "POWER-ON" text))
      (is (search "CONNECT" text))
      (is (search "Manca" text))
      (is (search "Scelgo" text))
      (is (not (search "QUICKLIME" text)))
      (is (find :missing nodes :key (lambda (n) (getf n :tone))))
      (is (find :action nodes :key (lambda (n) (getf n :tone)))))))

(test narrate-without-trace-does-not-invent
  (clear-trace-session)
  (multiple-value-bind (text nodes) (gp-narrate :last)
    (is (null nodes))
    (is (search "Non c'è ancora un ragionamento registrato" text))
    (is (not (search "POWER-ON" text)))))

(test induce-operator-ignores-unrelated-facts
  (let ((op (induce-operator 'free-port
                             '((device interface-01) (port-bound 47391))
                             '((device interface-01) (port-free 47391)))))
    (is (equal '((port-bound 47391)) (operator-preconditions op)))
    (is (equal '((port-free 47391)) (operator-add-list op)))
    (is (equal '((port-bound 47391)) (operator-delete-list op)))
    (is (eq t (getf (operator-meta op) :induced)))))

(test induce-rule-lifts-the-shared-object
  (let ((op (induce-operator 'power-on
                             '((weather sunny)
                               (device interface-01)
                               (power-state interface-01 off))
                             '((weather sunny)
                               (device interface-01)
                               (power-state interface-01 on))
                             :generalize t)))
    (let ((x (find-symbol "?X0" :automa-gp)))
      (is (eq x (second (first (operator-preconditions op)))))
      (is (equal `((device ,x) (power-state ,x off))
                 (operator-preconditions op)))
      (is (equal `((power-state ,x on)) (operator-add-list op)))
      (is (equal `((power-state ,x off)) (operator-delete-list op)))
      (is (equal '(interface-01) (getf (operator-meta op) :generalized))))))

(test induce-rule-keeps-numbers-ground
  (let ((op (induce-operator 'free-port
                             '((device interface-01) (port-bound 47391))
                             '((device interface-01) (port-free 47391))
                             :generalize t)))
    (is (equal '((port-bound 47391)) (operator-preconditions op)))
    (is (equal '((port-free 47391)) (operator-add-list op)))
    (is (null (getf (operator-meta op) :generalized)))))

(test failed-plan-listens-and-the-learned-rule-replans
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (let ((failed (gp-plan :goals '((power-state interface-01 on)) :archive nil)))
    (is (not (plan-success failed)))
    (is (observation-active-p))
    (is (fact-p '(power-state interface-01 on) (getf (gp-observation) :missing))))
  (gp-remove-fact '(power-state interface-01 off))
  (gp-add-fact '(power-state interface-01 on))
  (gp-induce-rule 'power-on)
  (is (not (observation-active-p)))
  (gp-remove-fact '(power-state interface-01 on))
  (gp-remove-fact '(device interface-01))
  (gp-add-fact '(device interface-02))
  (gp-add-fact '(power-state interface-02 off))
  (let ((plan (gp-plan :goals '((power-state interface-02 on)) :archive nil)))
    (is (plan-success plan))
    (is (eq 'power-on (getf (first (plan-steps plan)) :operator)))
    (is (not (observation-active-p)))))

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

(test induce-operator-rejects-an-unchanged-state
  (signals error (induce-operator 'noop '((folder notes missing))
                                  '((folder notes missing)))))

(test learn-action-registers-the-induced-operator
  (gp-reset)
  (gp-add-fact '(folder notes missing))
  (gp-note-state)
  (gp-remove-fact '(folder notes missing))
  (gp-add-fact '(folder notes present))
  (let ((op (gp-learn-action 'create-folder)))
    (is (eq 'create-folder (operator-name op)))
    (is (equal '((folder notes missing)) (operator-preconditions op)))
    (is (equal '((folder notes present)) (operator-add-list op)))
    (is (operator-p (find-operator (gp-context) 'create-folder)))))

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

(test notice-path-rejects-an-unmodeled-file
  (gp-clear-memory)
  (gp-reset)
  (uiop:with-temporary-file (:pathname path)
    (signals error (gp-notice-path (namestring path)))
    (is (null (gp-facts)))
    (is (null (gp-events)))))

(test notice-path-rejects-a-directory-and-a-missing-file
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'on-file
                        :when '(automa-gp::file-created ?path)))
  (signals error (gp-notice-path (namestring (uiop:temporary-directory))))
  (signals error (gp-notice-path "/tmp/automa-gp-notice-missing-file"))
  (is (null (gp-facts)))
  (is (null (gp-events))))

(test notice-path-keeps-the-listening-before-state
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'on-file
                        :when '(automa-gp::file-created ?path)))
  (gp-add-fact '(device interface-01))
  (gp-listen :reason :manual)
  (let ((before (copy-tree *observed-before*)))
    (uiop:with-temporary-file (:pathname path)
      (let* ((name (namestring path))
             (fact (gp-notice-path name)))
        (is (equal (list 'automa-gp::file-created name) fact))
        (is (fact-p fact (gp-facts)))
        (is (not (fact-p fact before)))
        (is (equal before *observed-before*))
        (is (observation-active-p))
        (is (= 1 (length (gp-events))))
        (gp-notice-path name)
        (is (= 1 (length (gp-events))))
        (is (= 1 (count 'automa-gp::file-created (gp-facts) :key #'car))))))
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'only-one
                        :when '(automa-gp::file-created "only-this.txt")))
  (uiop:with-temporary-file (:pathname path)
    (signals error (gp-notice-path (namestring path)))
    (is (null (gp-events)))))

(test notice-directory-applies-the-reaction-and-leaves-the-disk-to-run
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-notice-dir-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (source (merge-pathnames "note.txt" dir))
         (nested (merge-pathnames "nested/skip.txt" dir))
         (marker (merge-pathnames "marker.txt" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist nested)
           (adapter-write-file-string source "hello")
           (adapter-write-file-string nested "skip")
           (signals error (gp-notice-directory (namestring dir)))
           (is (null (gp-facts)))
           (gp-add-reaction
            (make-event-reaction :name 'on-file
                                 :when '(automa-gp::file-created ?path)
                                 :assert '((seen ?path))
                                 :goals '((noted ?path))))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((seen ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path (namestring marker)
                                           :content "noticed")))))
           (gp-add-fact '(bench clear))
           (gp-listen :reason :manual)
           (let ((before (copy-tree *observed-before*))
                 (name (namestring source)))
             (let ((noticed (gp-notice-directory (namestring dir))))
               (is (equal (list (list 'automa-gp::file-created name)) noticed))
               (is (fact-p (list 'automa-gp::file-created name) (gp-facts)))
               (is (fact-p (list 'seen name) (gp-facts)))
               (is (not (find "skip.txt" (gp-facts)
                              :test (lambda (text fact)
                                      (and (stringp (second fact))
                                           (search text (second fact)))))))
               (is (equal (list (list 'noted name)) (gp-goals)))
               (is (equal before *observed-before*))
               (is-false (file-exists-p marker))
               (gp-notice-directory (namestring dir))
               (is (= 1 (count 'automa-gp::file-created (gp-facts) :key #'car)))
               (is (= 1 (length (gp-events))))
               (let ((plan (gp-plan :goals (list (list 'noted name)))))
                 (is (plan-success plan))
                 (gp-simulate)
                 (is-false (file-exists-p marker))
                 (is (fact-p '(bench clear) (gp-facts)))
                 (let ((ex (gp-run :adapters t)))
                   (is-true (execution-success ex))
                   (is (equal "noticed" (adapter-read-file-string marker)))
                   (is (fact-p (list 'noted name) (gp-facts))))))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test notice-directory-rejects-a-file-and-a-missing-directory
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'on-file
                        :when '(automa-gp::file-created ?path)))
  (uiop:with-temporary-file (:pathname path)
    (signals error (gp-notice-directory (namestring path))))
  (signals error (gp-notice-directory "/tmp/automa-gp-notice-missing-dir"))
  (is (null (gp-facts))))

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
      (is (find goal (gp-goals) :test #'equal)))))

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

(test induce-rule-merges-a-second-example
  (gp-clear-memory)
  (gp-reset)
  (gp-induce-rule 'power-on
                  :before '((device interface-01) (power-state interface-01 off))
                  :after '((device interface-01) (power-state interface-01 on)))
  (let ((op (gp-induce-rule 'power-on
                            :before '((power-state interface-02 off) (device interface-02))
                            :after '((device interface-02) (power-state interface-02 on)))))
    (let ((x (find-symbol "?X0" :automa-gp)))
      (is (equal `((device ,x) (power-state ,x off))
                 (operator-preconditions op)))
      (is (equal `((power-state ,x on)) (operator-add-list op)))
      (is (= 2 (getf (operator-meta op) :examples)))
      (is (equal '(interface-01 interface-02)
                 (getf (operator-meta op) :generalized))))))

(test induce-rule-refuses-a-different-value-and-a-different-number
  (gp-clear-memory)
  (gp-reset)
  (gp-induce-rule 'power-on
                  :before '((device interface-01) (power-state interface-01 off))
                  :after '((device interface-01) (power-state interface-01 on)))
  (signals error
    (gp-induce-rule 'power-on
                    :before '((device interface-01) (power-state interface-01 off))
                    :after '((device interface-01) (power-state interface-01 ready))))
  (let ((op (find-operator (gp-context) 'power-on)))
    (is (= 1 (getf (operator-meta op) :examples)))
    (is (equal '(interface-01) (getf (operator-meta op) :generalized))))
  (gp-reset)
  (gp-induce-rule 'free-port
                  :before '((port-bound 47391))
                  :after '((port-free 47391)))
  (signals error
    (gp-induce-rule 'free-port
                    :before '((port-bound 47392))
                    :after '((port-free 47392))))
  (let ((op (find-operator (gp-context) 'free-port)))
    (is (equal '((port-bound 47391)) (operator-preconditions op)))
    (is (equal '((port-free 47391)) (operator-add-list op)))
    (is (= 1 (getf (operator-meta op) :examples)))))

(test learn-action-merges-a-second-ground-example
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(folder notes missing))
  (gp-note-state)
  (gp-learn-action 'create-folder
                   :before '((weather sunny) (folder notes missing))
                   :after '((folder notes present) (weather sunny)))
  (is (not (observation-active-p)))
  (let ((op (gp-learn-action 'create-folder
                             :before '((folder notes missing) (weather rainy))
                             :after '((weather rainy) (folder notes present)))))
    (is (equal '((folder notes missing)) (operator-preconditions op)))
    (is (equal '((folder notes present)) (operator-add-list op)))
    (is (equal '((folder notes missing)) (operator-delete-list op)))
    (is (= 2 (getf (operator-meta op) :examples)))
    (is (null (getf (operator-meta op) :generalized)))))

(test learn-action-refuses-a-different-constant
  (gp-clear-memory)
  (gp-reset)
  (gp-learn-action 'create-folder
                   :before '((folder notes missing))
                   :after '((folder notes present)))
  (gp-add-fact '(folder notes present))
  (gp-note-state)
  (signals error
    (gp-learn-action 'create-folder
                     :before '((folder photos missing))
                     :after '((folder photos present))))
  (is (observation-active-p))
  (let ((op (find-operator (gp-context) 'create-folder)))
    (is (equal '((folder notes missing)) (operator-preconditions op)))
    (is (= 1 (getf (operator-meta op) :examples))))
  (gp-reset)
  (gp-learn-action 'free-port
                   :before '((port-bound 47391))
                   :after '((port-free 47391)))
  (signals error
    (gp-learn-action 'free-port
                     :before '((port-bound 47392))
                     :after '((port-free 47392))))
  (let ((op (find-operator (gp-context) 'free-port)))
    (is (equal '((port-bound 47391)) (operator-preconditions op)))
    (is (equal '((port-free 47391)) (operator-add-list op)))
    (is (= 1 (getf (operator-meta op) :examples))))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'create-folder
                  :preconditions '((folder notes missing))
                  :add-list '((folder notes present))))
  (signals error
    (gp-learn-action 'create-folder
                     :before '((folder notes missing))
                     :after '((folder notes present))))
  (is (not (getf (operator-meta (find-operator (gp-context) 'create-folder))
                 :induced)))
  (gp-reset)
  (gp-induce-rule 'power-on
                  :before '((device interface-01) (power-state interface-01 off))
                  :after '((device interface-01) (power-state interface-01 on)))
  (signals error
    (gp-learn-action 'power-on
                     :before '((device interface-01) (power-state interface-01 off))
                     :after '((device interface-01) (power-state interface-01 on))))
  (let ((op (find-operator (gp-context) 'power-on)))
    (is (= 1 (getf (operator-meta op) :examples)))
    (is (equal '(interface-01) (getf (operator-meta op) :generalized)))))

(test induce-rule-lifts-a-repeated-symbol-from-two-examples
  (gp-clear-memory)
  (gp-reset)
  (gp-induce-rule 'paint
                  :before '()
                  :after '((left alpha) (right alpha)))
  (let ((op (gp-induce-rule 'paint
                            :before '()
                            :after '((right beta) (left beta)))))
    (let ((x (find-symbol "?X0" :automa-gp)))
      (is (equal `((left ,x) (right ,x)) (operator-add-list op)))
      (is (= 2 (getf (operator-meta op) :examples)))
      (is (member 'alpha (getf (operator-meta op) :generalized)))
      (is (member 'beta (getf (operator-meta op) :generalized))))))
