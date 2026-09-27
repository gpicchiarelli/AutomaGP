;;;; tests/test-workbench.lisp — narration and one-shot induction

(in-package #:automa-gp/tests)

(def-suite workbench-suite :in automa-gp-suite)
(in-suite workbench-suite)

(defun %test-tty-name-p (name)
  "True when NAME looks like a pty (ttys000, ttyv0, pts/0)."
  (and (stringp name)
       (plusp (length name))
       (or (search "tty" name :test #'char-equal)
           (and (>= (length name) 4)
                (string-equal "pts/" name :end2 4)))))

(defun %test-linux-script-p ()
  "util-linux script(1) needs -c; BSD/macOS take a trailing command."
  (eq (uiop:operating-system) :linux))

(defun %test-script-argv (typescript &rest command)
  "Argv that runs COMMAND under script(1) writing TYPESCRIPT."
  (if (%test-linux-script-p)
      (list "script" "-q" "-c" (uiop:escape-shell-command command) typescript)
      (list* "script" "-q" typescript command)))

(defun %test-session-tty (marker)
  "TTY name and pid of the process whose command contains MARKER."
  ;; -ww keeps BSD/Linux from truncating the marker off the command line.
  (let ((text (uiop:run-program '("ps" "-axww" "-o" "pid=,tty=,command=")
                                :output :string
                                :ignore-error-status t)))
    (dolist (line (uiop:split-string text :separator '(#\Newline #\Return)))
      (when (search marker line)
        (let* ((trim (string-left-trim '(#\Space #\Tab) line))
               (gap (position #\Space trim))
               (pid (and gap (subseq trim 0 gap)))
               (rest (and gap
                          (string-left-trim '(#\Space #\Tab)
                                            (subseq trim gap))))
               (gap2 (and rest (position #\Space rest)))
               (tty (and gap2 (subseq rest 0 gap2))))
          (when (and tty (%test-tty-name-p tty) pid)
            (return (values tty pid))))))))

(defun %test-open-pty-session (marker)
  "Launch a short-lived PTY session whose command line contains MARKER."
  ;; A real typescript path is more reliable than /dev/null on FreeBSD.
  (let ((typescript (format nil "/tmp/automa-gp-script-~A" marker)))
    (uiop:launch-program
     (%test-script-argv typescript "perl" "-e"
                        (format nil "sleep 60; # ~A" marker))
     :output #P"/dev/null"
     :error-output #P"/dev/null")))

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
               (is (member (list 'automa-gp::file-created name) noticed :test #'equal))
               (is (member (list 'automa-gp::file-created (namestring nested))
                           noticed :test #'equal))
               (is (= 2 (length noticed)))
               (is (fact-p (list 'automa-gp::file-created name) (gp-facts)))
               (is (fact-p (list 'seen name) (gp-facts)))
               (is (fact-p (list 'automa-gp::file-created (namestring nested))
                           (gp-facts)))
               (is (member (list 'noted (namestring nested)) (gp-goals)
                           :test #'equal))
               (is (member (list 'noted name) (gp-goals) :test #'equal))
               (is (equal before *observed-before*))
               (is-false (file-exists-p marker))
               (gp-notice-directory (namestring dir))
               (is (= 2 (count 'automa-gp::file-created (gp-facts) :key #'car)))
               (is (= 2 (length (gp-events))))
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

(test plan-open-goals-uses-a-noticed-goal-without-running
  (gp-clear-memory)
  (gp-reset)
  (signals error (gp-plan-open-goals))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan-open-goals")
    (is (= 400 code))
    (is (search "no open goal" (getf body :error))))
  (gp-add-goal '(power-state interface-01 on))
  (gp-add-fact '(power-state interface-01 on))
  (signals error (gp-plan-open-goals))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan-open-goals")
    (is (= 400 code))
    (is (search "no open goal" (getf body :error))))
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-plan-open-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (source (merge-pathnames "note.txt" dir))
         (marker (merge-pathnames "marker.txt" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist source)
           (adapter-write-file-string source "hello")
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
           (let ((name (namestring source)))
             (gp-notice-directory (namestring dir))
             (is (member (list 'noted name) (gp-goals) :test #'equal))
             (let ((facts (copy-tree (gp-facts)))
                   (plan (gp-plan-open-goals)))
               (is (plan-success plan))
               (is (eq 'note-file (getf (first (plan-steps plan)) :operator)))
               (is (equal facts (gp-facts)))
               (is (null (gp-last-execution)))
               (is-false (file-exists-p marker)))
             (multiple-value-bind (code body)
                 (web-api-handle :post "/api/plan-open-goals")
               (is (= 200 code))
               (is (eq t (getf (getf body :plan) :success)))
               (is (find 'note-file (getf (getf body :plan) :operators-used)))
               (is (not (getf body :execution)))
               (is (not (fact-p (list 'noted name) (gp-facts))))
               (is-false (file-exists-p marker)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test plan-names-an-external-action-without-running
  (gp-clear-memory)
  (gp-reset)
  (is (null (plan-external-actions nil)))
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-plan-external-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-fact (list 'seen path))
           (gp-add-operator
            (make-operator :name 'note-file
                           :preconditions '((seen ?path))
                           :add-list '((noted ?path))))
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-success plan))
             (is (null (plan-external-actions plan))))
           (gp-remove-operator 'note-file)
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((seen ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-success plan))
             (let ((actions (plan-external-actions plan)))
               (is (= 1 (length actions)))
               (is (null (plan-external-actions-withheld plan)))
               (is (eq 'note-file (getf (first actions) :operator)))
               (is (eq :filesystem (getf (first actions) :adapter)))
               (is (eq :write-string (getf (first actions) :op)))
               (is (equal path (getf (getf (first actions) :args) :path)))
               (is (equal "noticed" (getf (getf (first actions) :args) :content))))
             (is-false (file-exists-p marker))
             (gp-simulate)
             (is (fact-p (list 'seen path) (gp-facts)))
             (is (not (fact-p (list 'noted path) (gp-facts))))
             (is-false (file-exists-p marker)))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (let ((ext (getf (getf body :plan) :external)))
               (is (= 1 (length ext)))
               (is (eq :filesystem (getf (aref ext 0) :adapter)))
               (is (equal path (getf (getf (aref ext 0) :args) :path)))))
           (gp-run :adapters nil :confirm t)
           (is (fact-p (list 'noted path) (gp-facts)))
           (is-false (file-exists-p marker))
           (gp-remove-fact (list 'noted path))
           (gp-run :adapters t :confirm t)
           (is (equal "noticed" (adapter-read-file-string marker)))
           (gp-remove-operator 'note-file)
           (is (null (plan-external-actions (gp-last-plan))))
           (is (not (plan-external-actions-match-p (gp-last-plan))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (declare (ignore code))
             (is (= 1 (length (getf (getf body :plan) :external))))
             (is (null (getf (getf body :plan) :external-matches)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test execute-refuses-an-external-action-that-changed
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-plan-changed-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-fact (list 'seen path))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((seen ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-success plan))
             (is (plan-external-actions-match-p plan)))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (eq t (getf (getf body :plan) :external-matches)))
             (is (equal "noticed"
                        (getf (getf (aref (getf (getf body :plan) :external) 0)
                                    :args)
                              :content))))
           (setf (operator-meta (find-operator (gp-context) 'note-file))
                 (list :external
                       (list :adapter :filesystem
                             :op :write-string
                             :args (list :path '?path
                                         :content "changed"))))
           (is (not (plan-external-actions-match-p (gp-last-plan))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (null (getf (getf body :plan) :external-matches)))
             (is (equal "noticed"
                        (getf (getf (aref (getf (getf body :plan) :external) 0)
                                    :args)
                              :content))))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/run" '(:confirm t :adapters t))
             (is (= 400 code))
             (is (search "no longer matches" (getf body :error))))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/run" '(:confirm t :adapters nil))
             (is (= 400 code))
             (is (search "no longer matches" (getf body :error))))
           (is (eq :plan (context-mode (gp-context))))
           (is-false (file-exists-p marker))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (handler-case (gp-run :adapters nil :confirm t)
             (error (condition)
               (is (search "no longer matches" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is-false (file-exists-p marker))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (handler-case (gp-simulate)
             (error (condition)
               (is (search "no longer matches" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/simulate")
             (is (= 400 code))
             (is (search "no longer matches" (getf body :error))))
           (is (eq :plan (context-mode (gp-context))))
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-external-actions-match-p plan))
             (is (equal "changed"
                        (getf (getf (first (plan-external-actions plan)) :args)
                              :content))))
           (gp-run :adapters t :confirm t)
           (is (equal "changed" (adapter-read-file-string marker))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test replay-runs-the-recorded-external-action
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-replay-external-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-fact (list 'seen path))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((seen ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-success plan)))
           (gp-remember-procedure :name 'note-once)
           (gp-run :adapters t :confirm t)
           (is (equal "noticed" (adapter-read-file-string marker)))
           (adapter-delete-file marker)
           (gp-remove-fact (list 'noted path))
           (let ((plan (gp-use-procedure :name 'note-once)))
             (is (eq 'note-once (getf (plan-meta plan) :from-procedure)))
             (is (plan-external-actions-match-p plan))
             (is (equal path
                        (getf (getf (first (plan-external-actions plan)) :args)
                              :path))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (eq t (getf (getf body :plan) :external-matches)))
             (is (equal "noticed"
                        (getf (getf (aref (getf (getf body :plan) :external) 0)
                                    :args)
                              :content))))
           (gp-simulate)
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (is-false (file-exists-p marker))
           (gp-run :adapters nil :confirm t)
           (is (fact-p (list 'noted path) (gp-facts)))
           (is-false (file-exists-p marker))
           (gp-remove-fact (list 'noted path))
           (gp-run :adapters t :confirm t)
           (is (equal "noticed" (adapter-read-file-string marker)))
           (adapter-delete-file marker)
           (gp-remove-fact (list 'noted path))
           (gp-remove-operator 'note-file)
           (let ((plan (gp-use-procedure :name 'note-once)))
             (is (plan-external-actions-match-p plan))
             (is (null (plan-external-actions plan))))
           (gp-run :adapters t :confirm t)
           (is (fact-p (list 'noted path) (gp-facts)))
           (is-false (file-exists-p marker)))
      (gp-clear-memory)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test effects-only-replay-withholds-the-external-action
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-withhold-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((seen ?path) (open ?path))
             :add-list '((noted ?path) (closed ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (install-procedure!
            (make-procedure
             :name 'note-once
             :goals (list (list 'noted path))
             :operators-used '(note-file)
             :steps (list
                     (list :operator 'note-file
                           :bindings (list (cons '?path path))
                           :goal (list 'noted path)))))
           (gp-add-fact (list 'seen path))
           (gp-add-fact (list 'noted path))
           (let ((plan (gp-use-procedure :name 'note-once)))
             (is (eq t (getf (first (plan-steps plan)) :effects-only)))
             (is (null (plan-external-actions plan)))
             (is (plan-external-actions-match-p plan))
             (let ((held (plan-external-actions-withheld plan)))
               (is (= 1 (length held)))
               (is (equal path (getf (getf (first held) :args) :path)))
               (is (equal "noticed" (getf (getf (first held) :args) :content)))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (zerop (length (getf (getf body :plan) :external))))
             (is (eq t (getf (getf body :plan) :external-matches)))
             (is (equal "noticed"
                        (getf (getf (aref (getf (getf body :plan) :external-withheld) 0)
                                    :args)
                              :content))))
           (gp-simulate)
           (is (not (fact-p (list 'closed path) (gp-facts))))
           (is-false (file-exists-p marker))
           (is (not (eq :withheld
                        (getf (first (execution-steps (gp-last-execution)))
                              :external))))
           (gp-run :adapters nil :confirm t)
           (is (fact-p (list 'closed path) (gp-facts)))
           (is-false (file-exists-p marker))
           (is (not (eq :withheld
                        (getf (first (execution-steps (gp-last-execution)))
                              :external))))
           (gp-remove-fact (list 'closed path))
           (setf (operator-meta (find-operator (gp-context) 'note-file))
                 (list :external
                       (list :adapter :filesystem
                             :op :write-string
                             :args (list :path '?path
                                         :content "changed"))))
           (is (plan-external-actions-match-p (gp-last-plan)))
           (is (null (plan-external-actions (gp-last-plan))))
           (is (equal "changed"
                      (getf (getf (first (plan-external-actions-withheld
                                          (gp-last-plan)))
                                  :args)
                            :content)))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (eq t (getf (getf body :plan) :external-matches)))
             (is (equal "noticed"
                        (getf (getf (aref (getf (getf body :plan) :external-withheld) 0)
                                    :args)
                              :content))))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/run" '(:confirm t :adapters t))
             (is (= 200 code))
             (is (eq :withheld
                     (getf (aref (getf (getf body :execution) :steps) 0)
                           :external))))
           (is (fact-p (list 'closed path) (gp-facts)))
           (is-false (file-exists-p marker)))
      (gp-clear-memory)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test external-action-refuses-when-the-facts-no-longer-support-it
  (gp-clear-memory)
  (gp-reset)
  (is (null (plan-external-actions-supported-p nil)))
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-support-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-fact (list 'seen path))
           (gp-add-operator
            (make-operator :name 'open-file
                           :preconditions '((seen ?path))
                           :add-list '((open ?path))))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((open ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-success plan))
             (is (eq 'open-file (getf (first (plan-steps plan)) :operator)))
             (is (eq 'note-file (getf (second (plan-steps plan)) :operator)))
             (is (= 1 (length (plan-external-actions plan))))
             (is (null (plan-external-actions-withheld plan)))
             (is (plan-external-actions-match-p plan))
             (is (plan-external-actions-supported-p plan))
             (is (not (fact-p (list 'open path) (gp-facts)))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (eq t (getf (getf body :plan) :external-supported)))
             (is (equal "noticed"
                        (getf (getf (aref (getf (getf body :plan) :external) 0)
                                    :args)
                              :content))))
           (gp-remove-fact (list 'seen path))
           (is (plan-external-actions-match-p (gp-last-plan)))
           (is (not (plan-external-actions-supported-p (gp-last-plan))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (eq t (getf (getf body :plan) :external-matches)))
             (is (null (getf (getf body :plan) :external-supported)))
             (is (= 1 (length (getf (getf body :plan) :external)))))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/run" '(:confirm t :adapters t))
             (is (= 400 code))
             (is (search "no longer support" (getf body :error))))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/run" '(:confirm t :adapters nil))
             (is (= 400 code))
             (is (search "no longer support" (getf body :error))))
           (is (eq :plan (context-mode (gp-context))))
           (is-false (file-exists-p marker))
           (is (not (fact-p (list 'open path) (gp-facts))))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (handler-case (gp-run :adapters nil :confirm t)
             (error (condition)
               (is (search "no longer support" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is-false (file-exists-p marker))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (handler-case (gp-simulate)
             (error (condition)
               (is (search "no longer support" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/simulate")
             (is (= 400 code))
             (is (search "no longer support" (getf body :error))))
           (is (eq :plan (context-mode (gp-context))))
           (is (not (fact-p (list 'open path) (gp-facts))))
           (gp-add-fact (list 'seen path))
           (is (plan-external-actions-supported-p (gp-last-plan)))
           (gp-run :adapters t :confirm t)
           (is (equal "noticed" (adapter-read-file-string marker))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test unsupported-external-action-does-not-apply-earlier-steps
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-prefix-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-operator
            (make-operator :name 'mark
                           :preconditions '((ready ?path))
                           :add-list '((marked ?path))))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((open ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (install-procedure!
            (make-procedure
             :name 'mark-then-note
             :goals (list (list 'marked path) (list 'noted path))
             :operators-used '(mark note-file)
             :steps (list
                     (list :operator 'mark
                           :bindings (list (cons '?path path))
                           :goal (list 'marked path))
                     (list :operator 'note-file
                           :bindings (list (cons '?path path))
                           :goal (list 'noted path)))))
           (gp-add-fact (list 'ready path))
           (gp-add-fact (list 'open path))
           (let ((plan (gp-use-procedure :name 'mark-then-note)))
             (is (eq 'mark (getf (first (plan-steps plan)) :operator)))
             (is (eq 'note-file (getf (second (plan-steps plan)) :operator)))
             (is (plan-external-actions-supported-p plan)))
           (gp-remove-fact (list 'open path))
           (is (not (plan-external-actions-supported-p (gp-last-plan))))
           (handler-case (gp-run :adapters nil :confirm t)
             (error (condition)
               (is (search "no longer support" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is (not (fact-p (list 'marked path) (gp-facts))))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (is-false (file-exists-p marker))
           (handler-case (gp-simulate)
             (error (condition)
               (is (search "no longer support" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is (not (fact-p (list 'marked path) (gp-facts))))
           (gp-add-fact (list 'open path))
           (gp-run :adapters nil :confirm t)
           (is (fact-p (list 'marked path) (gp-facts)))
           (is (fact-p (list 'noted path) (gp-facts)))
           (is-false (file-exists-p marker)))
      (gp-clear-memory)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test changed-external-action-does-not-apply-earlier-steps
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-changed-prefix-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-operator
            (make-operator :name 'mark
                           :preconditions '((ready ?path))
                           :add-list '((marked ?path))))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((open ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (install-procedure!
            (make-procedure
             :name 'mark-then-note
             :goals (list (list 'marked path) (list 'noted path))
             :operators-used '(mark note-file)
             :steps (list
                     (list :operator 'mark
                           :bindings (list (cons '?path path))
                           :goal (list 'marked path))
                     (list :operator 'note-file
                           :bindings (list (cons '?path path))
                           :goal (list 'noted path)))))
           (gp-add-fact (list 'ready path))
           (gp-add-fact (list 'open path))
           (let ((plan (gp-use-procedure :name 'mark-then-note)))
             (is (eq 'mark (getf (first (plan-steps plan)) :operator)))
             (is (eq 'note-file (getf (second (plan-steps plan)) :operator)))
             (is (plan-external-actions-match-p plan)))
           (setf (operator-meta (find-operator (gp-context) 'note-file))
                 (list :external
                       (list :adapter :filesystem
                             :op :write-string
                             :args (list :path '?path
                                         :content "changed"))))
           (is (not (plan-external-actions-match-p (gp-last-plan))))
           (is (plan-external-actions-supported-p (gp-last-plan)))
           (handler-case (gp-run :adapters nil :confirm t)
             (error (condition)
               (is (search "no longer matches" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is (not (fact-p (list 'marked path) (gp-facts))))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (is-false (file-exists-p marker))
           (let ((plan (gp-use-procedure :name 'mark-then-note)))
             (is (plan-external-actions-match-p plan))
             (is (equal "changed"
                        (getf (getf (first (plan-external-actions plan)) :args)
                              :content))))
           (gp-run :adapters nil :confirm t)
           (is (fact-p (list 'marked path) (gp-facts)))
           (is (fact-p (list 'noted path) (gp-facts)))
           (is-false (file-exists-p marker)))
      (gp-clear-memory)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test a-refused-execute-leaves-the-mode-unchanged
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-mode-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-fact (list 'seen path))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((seen ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (gp-plan :goals (list (list 'noted path)) :archive nil)
           (is (eq :plan (context-mode (gp-context))))
           (gp-remove-fact (list 'seen path))
           (handler-case (gp-run :adapters t :confirm t)
             (error (condition)
               (is (search "no longer support" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is-false (file-exists-p marker))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/run" '(:confirm t :adapters t))
             (is (= 400 code))
             (is (search "no longer support" (getf body :error))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/status")
             (is (= 200 code))
             (is (eq :plan (getf body :mode))))
           (gp-add-fact (list 'seen path))
           (setf (operator-meta (find-operator (gp-context) 'note-file))
                 (list :external
                       (list :adapter :filesystem
                             :op :write-string
                             :args (list :path '?path
                                         :content "changed"))))
           (handler-case (gp-run :adapters t :confirm t)
             (error (condition)
               (is (search "no longer matches" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is-false (file-exists-p marker))
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-external-actions-match-p plan))
             (is (plan-external-actions-supported-p plan)))
           (gp-run :adapters t :confirm t)
           (is (eq :execute (context-mode (gp-context))))
           (is (equal "changed" (adapter-read-file-string marker))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test notice-directory-does-not-follow-a-linked-directory
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-notice-link-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (outside (uiop:ensure-directory-pathname
                   (merge-pathnames
                    (format nil "automa-gp-notice-outside-~A/" (get-universal-time))
                    (uiop:temporary-directory))))
         (secret (merge-pathnames "secret.txt" outside))
         (link (merge-pathnames "linked" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (ensure-directories-exist secret)
           (adapter-write-file-string secret "outside")
           (sb-posix:symlink (namestring outside) (namestring link))
           (gp-add-reaction
            (make-event-reaction :name 'on-file
                                 :when '(automa-gp::file-created ?path)))
           (gp-notice-directory (namestring dir))
           (is (not (find "secret.txt" (gp-facts)
                          :test (lambda (text fact)
                                  (and (consp fact)
                                       (stringp (second fact))
                                       (search text (second fact)))))))
           (is (null (gp-facts))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore)
      (uiop:delete-directory-tree outside :validate t :if-does-not-exist :ignore))))

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

(test watch-directory-notices-a-file-that-appears-later
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-watch-dir-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (source (merge-pathnames "note.txt" dir))
         (nested (merge-pathnames "nested/skip.txt" dir))
         (later (merge-pathnames "later.txt" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (ensure-directories-exist nested)
           (gp-add-reaction
            (make-event-reaction :name 'on-file
                                 :when '(automa-gp::file-created ?path)
                                 :assert '((seen ?path))
                                 :goals '((noted ?path))))
           (let ((noticed (gp-watch-directory (namestring dir) :interval 0.05)))
             (is (null noticed))
             (is (search (namestring dir) (gp-directory-watch))))
           (signals error (gp-watch-directory (namestring dir) :interval 0.05))
           (adapter-write-file-string source "hello")
           (adapter-write-file-string nested "skip")
           (let ((name (namestring source)))
             (loop repeat 40
                   until (and (fact-p (list 'automa-gp::file-created name) (gp-facts))
                              (fact-p (list 'automa-gp::file-created (namestring nested))
                                      (gp-facts)))
                   do (sleep 0.05))
             (gp-stop-directory-watch)
             (is (null (gp-directory-watch)))
             (is (fact-p (list 'automa-gp::file-created name) (gp-facts)))
             (is (fact-p (list 'seen name) (gp-facts)))
             (is (member (list 'noted name) (gp-goals) :test #'equal))
             (is (fact-p (list 'automa-gp::file-created (namestring nested))
                         (gp-facts)))
             (is (member (list 'noted (namestring nested)) (gp-goals) :test #'equal))
             (adapter-write-file-string later "later")
             (sleep 0.2)
             (is (not (find "later.txt" (gp-facts)
                            :test (lambda (text fact)
                                    (and (consp fact)
                                         (stringp (second fact))
                                         (search text (second fact))))))))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :post "/api/watch-directory"
                                    (format nil "{\"path\":~A,\"interval\":0.05}"
                                            (lisp->json (namestring dir))))
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search "\"ok\":true" json)))
           (let ((status (nth-value 2 (web-api-handle-json :get "/api/status"))))
             (is (search (namestring dir) status)))
           (gp-stop-directory-watch)
           (is (null (gp-directory-watch)))
           (gp-watch-directory (namestring dir) :interval 0.05)
           (gp-reset)
           (is (null (gp-directory-watch)))
           (is (not (find "automa-gp-directory-watch"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=))))
      (when (gp-directory-watch)
        (gp-stop-directory-watch))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test notice-processes-records-the-running-image
  (gp-clear-memory)
  (gp-reset)
  (signals error (gp-notice-processes))
  (is (null (gp-facts)))
  (let ((pid (current-process-id)))
    (gp-add-reaction
     (make-event-reaction :name 'on-self
                          :when (list 'automa-gp::process-running pid)
                          :assert '((lisp-image up))
                          :goals '((noted-image up))))
    (gp-add-reaction
     (make-event-reaction :name 'on-missing
                          :when '(automa-gp::process-running
                                  "automa-gp-no-such-process-xyzzy")))
    (gp-add-fact '(bench clear))
    (gp-listen :reason :manual)
    (let ((before (copy-tree *observed-before*)))
      (let ((noticed (gp-notice-processes)))
        (is (equal (list (list 'automa-gp::process-running pid)) noticed))
        (is (fact-p (list 'automa-gp::process-running pid) (gp-facts)))
        (is (fact-p '(lisp-image up) (gp-facts)))
        (is (equal '((noted-image up)) (gp-goals)))
        (is (not (find "xyzzy" (gp-facts)
                       :test (lambda (text fact)
                               (and (consp fact)
                                    (stringp (second fact))
                                    (search text (second fact)))))))
        (is (equal before *observed-before*))
        (gp-notice-processes)
        (is (= 1 (count 'automa-gp::process-running (gp-facts) :key #'car)))
        (is (= 1 (length (gp-events))))))
    (multiple-value-bind (code ctype json)
        (web-api-handle-json :post "/api/notice-processes" "{}")
      (declare (ignore ctype))
      (is (= 200 code))
      (is (search (princ-to-string pid) json))
      (is (search "LISP-IMAGE" json))
      (is (not (search "xyzzy" json)))))
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'only-var
                        :when '(automa-gp::process-running ?name)))
  (signals error (gp-notice-processes))
  (is (null (gp-facts))))

(test watch-processes-notices-a-process-that-appears-later
  (let* ((stamp (format nil "~A-~A" (get-universal-time) (random 100000)))
         (token (format nil "automa-gp-watch-proc-~A" stamp))
         (later (format nil "automa-gp-watch-later-~A" stamp))
         (born nil)
         (late nil))
    (unwind-protect
         (progn
           (gp-clear-memory)
           (gp-reset)
           (gp-add-reaction
            (make-event-reaction :name 'on-token
                                 :when (list 'automa-gp::process-running token)
                                 :assert '((watched-process up))
                                 :goals '((noted-process up))))
           (let ((noticed (gp-watch-processes :interval 0.05)))
             (is (null noticed))
             (is (gp-process-watch)))
           (signals error (gp-watch-processes :interval 0.05))
           (setf born (uiop:launch-program
                       (list "perl" "-e"
                             (format nil "sleep 60; # ~A" token))
                       :output :stream :error-output :stream))
           (loop repeat 80
                 until (fact-p (list 'automa-gp::process-running token) (gp-facts))
                 do (sleep 0.05))
           (is (fact-p (list 'automa-gp::process-running token) (gp-facts)))
           (is (fact-p '(watched-process up) (gp-facts)))
           (is (equal '((noted-process up)) (gp-goals)))
           (gp-stop-process-watch)
           (is (not (gp-process-watch)))
           (gp-add-reaction
            (make-event-reaction :name 'on-later
                                 :when (list 'automa-gp::process-running later)))
           (setf late (uiop:launch-program
                       (list "perl" "-e"
                             (format nil "sleep 60; # ~A" later))
                       :output :stream :error-output :stream))
           (sleep 0.3)
           (is (not (fact-p (list 'automa-gp::process-running later) (gp-facts))))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :post "/api/watch-processes" "{\"interval\":0.05}")
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search "\"watching\":true" json)))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :get "/api/status" "")
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search "\"process-watch\":true" json)))
           (web-api-handle-json :post "/api/watch-processes/stop" "{}")
           (gp-watch-processes :interval 0.05)
           (gp-reset)
           (is (not (gp-process-watch)))
           (is (not (find "automa-gp-process-watch"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=))))
      (when (and born (uiop:process-alive-p born))
        (ignore-errors (uiop:terminate-process born :urgent t)))
      (when (and late (uiop:process-alive-p late))
        (ignore-errors (uiop:terminate-process late :urgent t)))
      (when (gp-process-watch)
        (ignore-errors (gp-stop-process-watch))))))

(test notice-terminals-records-an-open-session
  (let ((marker (format nil "automa-gp-tty-~A-~A"
                        (get-universal-time) (random 100000)))
        (session nil)
        (child nil)
        (tty nil))
    (unwind-protect
         (progn
           (gp-clear-memory)
           (gp-reset)
           (signals error (gp-notice-terminals))
           (is (null (gp-facts)))
           (setf session (%test-open-pty-session marker))
           (loop repeat 80
                 until tty
                 do (sleep 0.05)
                    (setf (values tty child) (%test-session-tty marker)))
           (is (stringp tty))
           (gp-add-reaction
            (make-event-reaction :name 'on-tty
                                 :when (list 'automa-gp::terminal-open tty)
                                 :assert '((session up))
                                 :goals '((noted-terminal up))))
           (gp-add-reaction
            (make-event-reaction :name 'on-missing
                                 :when '(automa-gp::terminal-open
                                         "ttys-automa-gp-missing")))
           (gp-add-fact '(bench clear))
           (gp-listen :reason :manual)
           (let ((before (copy-tree *observed-before*)))
             (let ((noticed (gp-notice-terminals)))
               (is (equal (list (list 'automa-gp::terminal-open tty)) noticed))
               (is (fact-p (list 'automa-gp::terminal-open tty) (gp-facts)))
               (is (fact-p '(session up) (gp-facts)))
               (is (equal '((noted-terminal up)) (gp-goals)))
               (is (not (find "ttys-automa-gp-missing" (gp-facts)
                              :test (lambda (text fact)
                                      (and (consp fact)
                                           (stringp (second fact))
                                           (search text (second fact)))))))
               (is (equal before *observed-before*))
               (gp-notice-terminals)
               (is (= 1 (count 'automa-gp::terminal-open (gp-facts) :key #'car)))
               (is (= 1 (length (gp-events))))))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :post "/api/notice-terminals" "{}")
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search tty json))
             (is (search "SESSION" json))
             (is (not (search "ttys-automa-gp-missing" json))))
           (when child
             (ignore-errors
              (uiop:run-program (list "kill" child) :ignore-error-status t)))
           (when (and session (uiop:process-alive-p session))
             (ignore-errors (uiop:terminate-process session :urgent t)))
           (setf session nil)
           (loop repeat 40
                 while (%test-session-tty marker)
                 do (sleep 0.05))
           (gp-reset)
           (gp-add-reaction
            (make-event-reaction :name 'on-closed
                                 :when (list 'automa-gp::terminal-open tty)))
           (is (null (gp-notice-terminals)))
           (is (null (gp-facts)))
           (gp-reset)
           (gp-add-reaction
            (make-event-reaction :name 'only-var
                                 :when '(automa-gp::terminal-open ?name)))
           (signals error (gp-notice-terminals))
           (is (null (gp-facts))))
      (when child
        (ignore-errors
         (uiop:run-program (list "kill" "-9" child) :ignore-error-status t)))
      (when (and session (uiop:process-alive-p session))
        (ignore-errors (uiop:terminate-process session :urgent t))))))

(test watch-terminals-notices-a-terminal-that-opens-later
  (labels (           (tty-open-p (name)
             (let ((text (uiop:run-program '("ps" "-axww" "-o" "tty=")
                                           :output :string
                                           :ignore-error-status t)))
               (find name (uiop:split-string text :separator '(#\Newline #\Return #\Space #\Tab))
                     :test #'string=)))
           (close-session (session child)
             (when child
               (ignore-errors
                (uiop:run-program (list "kill" child) :ignore-error-status t)))
             (when (and session (uiop:process-alive-p session))
               (ignore-errors (uiop:terminate-process session :urgent t)))))
    (let* ((stamp (format nil "~A-~A" (get-universal-time) (random 100000)))
           (probe (format nil "automa-gp-tty-probe-~A" stamp))
           (born-mark (format nil "automa-gp-tty-born-~A" stamp))
           (later (format nil "automa-gp-tty-later-~A" stamp))
           (session nil)
           (child nil)
           (tty nil))
      (unwind-protect
           (progn
             (gp-clear-memory)
             (gp-reset)
             (setf session (%test-open-pty-session probe))
             (loop repeat 80
                   until tty
                   do (sleep 0.05)
                      (setf (values tty child) (%test-session-tty probe)))
             (is (stringp tty))
             (close-session session child)
             (setf session nil child nil)
             (loop repeat 40
                   while (or (%test-session-tty probe) (tty-open-p tty))
                   do (sleep 0.05))
             (is (not (tty-open-p tty)))
             (gp-add-reaction
              (make-event-reaction :name 'on-tty
                                   :when (list 'automa-gp::terminal-open tty)
                                   :assert '((watched-terminal up))
                                   :goals '((noted-terminal up))))
             (let ((noticed (gp-watch-terminals :interval 0.05)))
               (is (null noticed))
               (is (gp-terminal-watch)))
             (signals error (gp-watch-terminals :interval 0.05))
             (setf session (%test-open-pty-session born-mark))
             (let ((opened nil))
               (loop repeat 40
                     until opened
                     do (sleep 0.05)
                        (setf (values opened child) (%test-session-tty born-mark)))
               (is (equal tty opened)))
             (loop repeat 80
                   until (fact-p (list 'automa-gp::terminal-open tty) (gp-facts))
                   do (sleep 0.05))
             (is (fact-p (list 'automa-gp::terminal-open tty) (gp-facts)))
             (is (fact-p '(watched-terminal up) (gp-facts)))
             (is (equal '((noted-terminal up)) (gp-goals)))
             (gp-stop-terminal-watch)
             (is (not (gp-terminal-watch)))
             (gp-remove-fact (list 'automa-gp::terminal-open tty))
             (gp-remove-fact '(watched-terminal up))
             (close-session session child)
             (setf session nil child nil)
             (loop repeat 40
                   while (or (%test-session-tty born-mark) (tty-open-p tty))
                   do (sleep 0.05))
             (setf session (%test-open-pty-session later))
             (let ((opened nil))
               (loop repeat 40
                     until opened
                     do (sleep 0.05)
                        (setf (values opened child) (%test-session-tty later)))
               (is (equal tty opened)))
             (sleep 0.3)
             (is (not (fact-p (list 'automa-gp::terminal-open tty) (gp-facts))))
             (multiple-value-bind (code ctype json)
                 (web-api-handle-json :post "/api/watch-terminals" "{\"interval\":0.05}")
               (declare (ignore ctype))
               (is (= 200 code))
               (is (search "\"watching\":true" json)))
             (multiple-value-bind (code ctype json)
                 (web-api-handle-json :get "/api/status" "")
               (declare (ignore ctype))
               (is (= 200 code))
               (is (search "\"terminal-watch\":true" json)))
             (web-api-handle-json :post "/api/watch-terminals/stop" "{}")
             (gp-watch-terminals :interval 0.05)
             (gp-reset)
             (is (not (gp-terminal-watch)))
             (is (not (find "automa-gp-terminal-watch"
                            (sb-thread:list-all-threads)
                            :key #'sb-thread:thread-name
                            :test #'string=))))
        (close-session session child)
        (when (gp-terminal-watch)
          (ignore-errors (gp-stop-terminal-watch)))))))

(test notice-terminal-text-reads-a-named-line
  (let* ((stamp (format nil "~A-~A" (get-universal-time) (random 100000)))
         (token (format nil "automa-gp-line-~A" stamp))
         (path (format nil "/tmp/automa-gp-transcript-~A" stamp))
         (link (format nil "/tmp/automa-gp-transcript-link-~A" stamp)))
    (unwind-protect
         (progn
           (gp-clear-memory)
           (gp-reset)
           (signals error (gp-notice-terminal-text))
           (is (null (gp-facts)))
           (uiop:run-program
            (%test-script-argv path "perl" "-e"
                               (format nil "print \"~A\\n\";" token))
            :output #P"/dev/null"
            :error-output #P"/dev/null"
            :ignore-error-status t)
           (sb-posix:symlink path link)
           (gp-add-reaction
            (make-event-reaction :name 'on-line
                                 :when (list 'automa-gp::terminal-text path token)
                                 :assert '((transcript heard))
                                 :goals '((noted-text up))))
           (gp-add-reaction
            (make-event-reaction :name 'on-missing
                                 :when (list 'automa-gp::terminal-text path
                                             "automa-gp-no-such-line")))
           (gp-add-reaction
            (make-event-reaction :name 'on-link
                                 :when (list 'automa-gp::terminal-text link token)))
           (gp-add-reaction
            (make-event-reaction :name 'on-device
                                 :when '(automa-gp::terminal-text "/dev/null" "x")))
           (gp-add-fact '(bench clear))
           (gp-listen :reason :manual)
           (let ((before (copy-tree *observed-before*)))
             (let ((noticed (gp-notice-terminal-text)))
               (is (equal (list (list 'automa-gp::terminal-text path token)) noticed))
               (is (fact-p (list 'automa-gp::terminal-text path token) (gp-facts)))
               (is (fact-p '(transcript heard) (gp-facts)))
               (is (equal '((noted-text up)) (gp-goals)))
               (is (not (find "automa-gp-no-such-line" (gp-facts)
                              :test (lambda (text fact)
                                      (and (consp fact)
                                           (some (lambda (term)
                                                   (and (stringp term)
                                                        (search text term)))
                                                 fact))))))
               (is (not (fact-p (list 'automa-gp::terminal-text link token) (gp-facts))))
               (is (not (fact-p '(automa-gp::terminal-text "/dev/null" "x") (gp-facts))))
               (is (equal before *observed-before*))
               (gp-notice-terminal-text)
               (is (= 1 (count 'automa-gp::terminal-text (gp-facts) :key #'car)))
               (is (= 1 (length (gp-events))))))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :post "/api/notice-terminal-text" "{}")
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search token json))
             (is (search "TRANSCRIPT" json))
             (is (not (search "automa-gp-no-such-line" json)))
             (is (not (search link json)))))
         (ignore-errors (delete-file link))
         (ignore-errors (delete-file path))))
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'only-var
                        :when '(automa-gp::terminal-text ?path ?text)))
  (signals error (gp-notice-terminal-text))
  (is (null (gp-facts))))

(test watch-terminal-text-notices-a-line-that-appears-later
  (let* ((stamp (format nil "~A-~A" (get-universal-time) (random 100000)))
         (token (format nil "automa-gp-watch-line-~A" stamp))
         (later (format nil "automa-gp-watch-later-~A" stamp))
         (path (format nil "/tmp/automa-gp-watch-text-~A" stamp)))
    (unwind-protect
         (progn
           (gp-clear-memory)
           (gp-reset)
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "" out))
           (gp-add-reaction
            (make-event-reaction :name 'on-line
                                 :when (list 'automa-gp::terminal-text path token)
                                 :assert '((watched-text up))
                                 :goals '((noted-text up))))
           (let ((noticed (gp-watch-terminal-text :interval 0.05)))
             (is (null noticed))
             (is (gp-terminal-text-watch)))
           (signals error (gp-watch-terminal-text :interval 0.05))
           (with-open-file (out path :direction :output :if-exists :append)
             (write-line token out))
           (loop repeat 80
                 until (fact-p (list 'automa-gp::terminal-text path token) (gp-facts))
                 do (sleep 0.05))
           (is (fact-p (list 'automa-gp::terminal-text path token) (gp-facts)))
           (is (fact-p '(watched-text up) (gp-facts)))
           (is (equal '((noted-text up)) (gp-goals)))
           (gp-stop-terminal-text-watch)
           (is (not (gp-terminal-text-watch)))
           (gp-add-reaction
            (make-event-reaction :name 'on-later
                                 :when (list 'automa-gp::terminal-text path later)))
           (with-open-file (out path :direction :output :if-exists :append)
             (write-line later out))
           (sleep 0.3)
           (is (not (fact-p (list 'automa-gp::terminal-text path later) (gp-facts))))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :post "/api/watch-terminal-text" "{\"interval\":0.05}")
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search "\"watching\":true" json)))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :get "/api/status" "")
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search "\"terminal-text-watch\":true" json)))
           (web-api-handle-json :post "/api/watch-terminal-text/stop" "{}")
           (gp-watch-terminal-text :interval 0.05)
           (gp-reset)
           (is (not (gp-terminal-text-watch)))
           (is (not (find "automa-gp-terminal-text-watch"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=))))
      (ignore-errors (delete-file path))
      (when (gp-terminal-text-watch)
        (ignore-errors (gp-stop-terminal-text-watch))))))

(test notice-stop-drops-the-read-still-open
  (let ((started (get-internal-real-time)))
    (let ((automa-gp::*notice-halt* (lambda () t)))
      (is (null (automa-gp::%osascript "delay 5" :timeout 2))))
    (is (< (/ (- (get-internal-real-time) started)
              internal-time-units-per-second)
           0.5)))
  (let ((box (list nil))
        (started (get-internal-real-time)))
    (let ((setter (sb-thread:make-thread
                   (lambda ()
                     (sleep 0.2)
                     (setf (car box) t))
                   :name "automa-gp-halt-setter")))
      (unwind-protect
           (let ((automa-gp::*notice-halt* (lambda () (car box))))
             (is (null (automa-gp::%osascript "delay 5" :timeout 2)))
             (is (< (/ (- (get-internal-real-time) started)
                       internal-time-units-per-second)
                    1.5)))
        (setf (car box) t)
        (ignore-errors (sb-thread:join-thread setter :timeout 1)))))
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (ensure-directories-exist
               (pathname (format nil "/tmp/automa-gp-halt-walk-~D/" (random 1000000)))))
         (path (namestring (merge-pathnames "a-first.txt" dir))))
    (unwind-protect
         (progn
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "a" out))
           (gp-add-reaction
            (make-event-reaction :name 'on-file
                                 :when '(automa-gp::file-created ?path)
                                 :assert '((seen ?path))
                                 :goals '((noted ?path))))
           (let ((automa-gp::*notice-halt* (lambda () t)))
             (is (null (gp-notice-directory (namestring dir))))
             (is (null (gp-facts)))
             (is (null (gp-goals)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test notice-stop-drops-a-process-check-and-a-transcript
  (is (eql 0 (automa-gp::%cancellable-program '("/usr/bin/true"))))
  (is (not (eql 0 (automa-gp::%cancellable-program '("/usr/bin/false")))))
  (let ((box (list nil))
        (started (get-internal-real-time)))
    (let ((setter (sb-thread:make-thread
                   (lambda ()
                     (sleep 0.2)
                     (setf (car box) t))
                   :name "automa-gp-halt-setter")))
      (unwind-protect
           (let ((automa-gp::*notice-halt* (lambda () (car box))))
             (is (null (automa-gp::%cancellable-program
                        '("/usr/bin/perl" "-e" "sleep 5"))))
             (is (< (/ (- (get-internal-real-time) started)
                       internal-time-units-per-second)
                    1.5)))
        (setf (car box) t)
        (ignore-errors (sb-thread:join-thread setter :timeout 1)))))
  (let ((path (namestring
               (merge-pathnames "span.txt"
                                (ensure-directories-exist
                                 (pathname (format nil "/tmp/automa-gp-span-~D/"
                                                   (random 1000000))))))))
    (unwind-protect
         (progn
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "xxabcdyy" out))
           (is (automa-gp::%file-contains-p path "abcd" :chunk 3))
           (let ((automa-gp::*notice-halt* (lambda () t)))
             (is (null (automa-gp::%file-contains-p path "abcd" :chunk 3)))))
      (ignore-errors (delete-file path))
      (ignore-errors (uiop:delete-directory-tree
                      (uiop:pathname-directory-pathname path)
                      :validate t :if-does-not-exist :ignore))))
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (ensure-directories-exist
               (pathname (format nil "/tmp/automa-gp-halt-text-~D/" (random 1000000)))))
         (path (namestring (merge-pathnames "transcript.txt" dir))))
    (unwind-protect
         (progn
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "token-is-here" out))
           (gp-add-reaction
            (make-event-reaction :name 'on-text
                                 :when (list 'automa-gp::terminal-text path "token-is-here")
                                 :assert '((transcript heard))
                                 :goals '((noted-text up))))
           (gp-add-reaction
            (make-event-reaction :name 'on-proc
                                 :when (list 'automa-gp::process-running (current-process-id))
                                 :assert '((proc heard))
                                 :goals '((noted-proc up))))
           (let ((automa-gp::*notice-halt* (lambda () t)))
             (is (null (gp-notice-terminal-text)))
             (is (null (gp-notice-processes)))
             (is (null (gp-facts)))
             (is (null (gp-goals)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test notice-terminal-screen-skips-a-tab-that-does-not-answer
  (gp-clear-memory)
  (gp-reset)
  (signals error (gp-notice-terminal-screen))
  (is (null (gp-facts)))
  (let ((started (get-internal-real-time)))
    (is (null (automa-gp::%osascript "delay 5" :timeout 1)))
    (is (< (/ (- (get-internal-real-time) started)
              internal-time-units-per-second)
           3)))
  (gp-add-reaction
   (make-event-reaction :name 'on-screen
                        :when '(automa-gp::terminal-screen
                                "ttys99999"
                                "automa-gp-screen-missing")
                        :assert '((screen heard))
                        :goals '((noted-screen up))))
  (gp-add-reaction
   (make-event-reaction :name 'on-bad
                        :when '(automa-gp::terminal-screen
                                "ttys000; say hi"
                                "x")))
  (gp-add-fact '(bench clear))
  (gp-listen :reason :manual)
  (let ((before (copy-tree *observed-before*)))
    (let ((noticed (gp-notice-terminal-screen)))
      (is (null noticed))
      (is (not (fact-p '(screen heard) (gp-facts))))
      (is (not (fact-p '(noted-screen up) (gp-goals))))
      (is (equal before *observed-before*))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/notice-terminal-screen" "{}")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (not (search "automa-gp-screen-missing" json)))
    (is (not (search "say hi" json))))
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'only-var
                        :when '(automa-gp::terminal-screen ?tty ?text)))
  (signals error (gp-notice-terminal-screen))
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'only-bad
                        :when '(automa-gp::terminal-screen "not-a-tty" "x")))
  (signals error (gp-notice-terminal-screen))
  (is (null (gp-facts))))

(test watch-terminal-screen-stays-until-stopped
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'on-screen
                        :when '(automa-gp::terminal-screen
                                "ttys99999"
                                "automa-gp-screen-missing")
                        :assert '((screen heard))
                        :goals '((noted-screen up))))
  (unwind-protect
       (progn
         (let ((noticed (gp-watch-terminal-screen :interval 0.2)))
           (is (null noticed))
           (is (gp-terminal-screen-watch)))
         (signals error (gp-watch-terminal-screen :interval 0.2))
         (is (not (fact-p '(screen heard) (gp-facts))))
         (gp-stop-terminal-screen-watch)
         (is (not (gp-terminal-screen-watch)))
         (is (not (fact-p '(screen heard) (gp-facts))))
         (multiple-value-bind (code ctype json)
             (web-api-handle-json :post "/api/watch-terminal-screen" "{\"interval\":0.2}")
           (declare (ignore ctype))
           (is (= 200 code))
           (is (search "\"watching\":true" json))
           (is (not (search "automa-gp-screen-missing" json))))
         (multiple-value-bind (code ctype json)
             (web-api-handle-json :get "/api/status" "")
           (declare (ignore ctype))
           (is (= 200 code))
           (is (search "\"terminal-screen-watch\":true" json)))
         (web-api-handle-json :post "/api/watch-terminal-screen/stop" "{}")
         (gp-watch-terminal-screen :interval 0.2)
         (gp-reset)
         (is (not (gp-terminal-screen-watch)))
         (is (not (find "automa-gp-terminal-screen-watch"
                        (sb-thread:list-all-threads)
                        :key #'sb-thread:thread-name
                        :test #'string=))))
    (when (gp-terminal-screen-watch)
      (ignore-errors (gp-stop-terminal-screen-watch)))))

(test notice-watches-of-different-kinds-stay-separate
  (gp-clear-memory)
  (gp-reset)
  (signals error (gp-watch-processes :interval 0))
  (is (not (gp-process-watch)))
  (signals error (gp-watch-processes :interval 0.2))
  (is (not (gp-process-watch)))
  (let* ((dir (ensure-directories-exist
               (pathname (format nil "/tmp/automa-gp-watches-~D/" (random 1000000)))))
         (path (namestring (merge-pathnames "transcript.txt" dir))))
    (unwind-protect
         (progn
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "" out))
           (gp-add-reaction
            (make-event-reaction :name 'on-proc
                                 :when '(automa-gp::process-running
                                         "automa-gp-no-such-process")))
           (gp-add-reaction
            (make-event-reaction :name 'on-text
                                 :when (list 'automa-gp::terminal-text path
                                             "automa-gp-absent-line")))
           (is (null (gp-watch-processes :interval 0.2)))
           (is (null (gp-watch-terminal-text :interval 0.2)))
           (is (gp-process-watch))
           (is (gp-terminal-text-watch))
           (signals error (gp-watch-processes :interval 0.2))
           (is (gp-terminal-text-watch))
           (gp-stop-process-watch)
           (is (not (gp-process-watch)))
           (is (gp-terminal-text-watch))
           (is (not (fact-p '(automa-gp::process-running "automa-gp-no-such-process")
                            (gp-facts))))
           (gp-reset)
           (is (not (gp-terminal-text-watch)))
           (is (not (find "automa-gp-process-watch"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=)))
           (is (not (find "automa-gp-terminal-text-watch"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=))))
      (when (gp-process-watch)
        (ignore-errors (gp-stop-process-watch)))
      (when (gp-terminal-text-watch)
        (ignore-errors (gp-stop-terminal-text-watch)))
      (ignore-errors (delete-file path))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(defvar *notice-watch-probe* nil)

(defvar *notice-watch-probe-lock* (sb-thread:make-mutex :name "automa-gp-notice-watch-probe"))

(test notice-watch-is-reserved-before-the-first-look
  (let ((lock *notice-watch-probe-lock*))
    (unwind-protect
         (progn
           (setf *notice-watch-probe* nil)
           (let ((saw-busy nil))
             (is (equal '(:seen)
                        (automa-gp::%begin-notice-watch
                         '*notice-watch-probe* lock 0.05
                         "automa-gp-notice-watch-probe" "busy"
                         (lambda ()
                           (handler-case
                               (automa-gp::%begin-notice-watch
                                '*notice-watch-probe* lock 0.05
                                "automa-gp-notice-watch-probe" "busy"
                                (lambda () (values nil (lambda () nil) nil)))
                             (error (condition)
                               (setf saw-busy
                                     (search "busy" (princ-to-string condition)))))
                           (values '(:seen) (lambda () '(:seen)) nil)))))
             (is (not (null saw-busy))))
           (is (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock))
           (automa-gp::%end-notice-watch '*notice-watch-probe* lock "absent")
           (is (not (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock)))
           (is (equal '(:seen)
                      (automa-gp::%begin-notice-watch
                       '*notice-watch-probe* lock 0.05
                       "automa-gp-notice-watch-probe" "busy"
                       (lambda ()
                         (automa-gp::%end-notice-watch
                          '*notice-watch-probe* lock "absent")
                         (values '(:seen) (lambda () '(:seen)) "label")))))
           (is (not (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock)))
           (is (not (find "automa-gp-notice-watch-probe"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=)))
           (signals error
             (automa-gp::%begin-notice-watch
              '*notice-watch-probe* lock 0.05
              "automa-gp-notice-watch-probe" "busy"
              (lambda () (error "look failed"))))
           (is (not (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock))))
      (when (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock)
        (ignore-errors
         (automa-gp::%end-notice-watch '*notice-watch-probe* lock "absent"))))))

(test notice-stops-before-the-next-file
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (ensure-directories-exist
               (pathname (format nil "/tmp/automa-gp-halt-~D/" (random 1000000)))))
         (first (namestring (merge-pathnames "a-first.txt" dir)))
         (second (namestring (merge-pathnames "b-second.txt" dir))))
    (unwind-protect
         (progn
           (with-open-file (out first :direction :output :if-exists :supersede)
             (write-string "a" out))
           (with-open-file (out second :direction :output :if-exists :supersede)
             (write-string "b" out))
           (gp-add-reaction
            (make-event-reaction :name 'on-file
                                 :when '(automa-gp::file-created ?path)
                                 :assert '((seen ?path))
                                 :goals '((noted ?path))))
           (let ((automa-gp::*notice-halt*
                  (lambda ()
                    (find 'automa-gp::file-created (gp-facts) :key #'car))))
             (let ((noticed (gp-notice-directory (namestring dir))))
               (is (= 1 (length noticed)))
               (is (search "a-first.txt" (second (first noticed))))
               (is (= 1 (count 'automa-gp::file-created (gp-facts) :key #'car)))
               (is (= 1 (count 'seen (gp-facts) :key #'car)))
               (is (= 1 (length (gp-goals))))
               (is (not (find "b-second.txt" (gp-facts)
                              :test (lambda (text fact)
                                      (and (consp fact)
                                           (some (lambda (term)
                                                   (and (stringp term)
                                                        (search text term)))
                                                 fact))))))))
           (let ((noticed (gp-notice-directory (namestring dir))))
             (is (= 2 (length noticed)))
             (is (find "b-second.txt" noticed
                       :test (lambda (text fact)
                               (and (consp fact)
                                    (some (lambda (term)
                                            (and (stringp term)
                                                 (search text term)))
                                          fact)))))
             (is (= 2 (length (gp-goals))))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test notice-watch-stop-is-visible-during-the-look
  (let ((lock *notice-watch-probe-lock*))
    (unwind-protect
         (progn
           (setf *notice-watch-probe* nil)
           (is (equal '(nil t)
                      (automa-gp::%begin-notice-watch
                       '*notice-watch-probe* lock 0.05
                       "automa-gp-notice-watch-probe" "busy"
                       (lambda ()
                         (let ((before (automa-gp::%notice-halted-p)))
                           (automa-gp::%end-notice-watch
                            '*notice-watch-probe* lock "absent")
                           (values (list before (automa-gp::%notice-halted-p))
                                   (lambda () nil)
                                   nil))))))
           (is (not (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock)))
           (is (not (find "automa-gp-notice-watch-probe"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=))))
      (when (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock)
        (ignore-errors
         (automa-gp::%end-notice-watch '*notice-watch-probe* lock "absent"))))))

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
