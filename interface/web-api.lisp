;;;; interface/web-api.lisp — HTTP-agnostic operator API (Phase 11)
;;;;
;;;; Thin façade over REPL/core. No Hunchentoot here — the web system maps
;;;; HTTP onto WEB-API-HANDLE. Reasoning stays in the symbolic core.

(in-package #:automa-gp)

(defparameter *web-api-version* "0.16.0"
  "API surface version (operator archive routes included).")

(defun %serialize-bindings (bindings)
  (json-array
   (mapcar (lambda (pair)
             (list (car pair) (cdr pair)))
           (if (and bindings (consp bindings)
                    (not (eq bindings *no-bindings*)))
               bindings
               nil))))

(defun %serialize-step (step)
  (let ((plist (list :operator (getf step :operator)
                     :bindings (%serialize-bindings (getf step :bindings))
                     :goal (getf step :goal)
                     :subgoals (json-array (getf step :subgoals))
                     :cost (or (getf step :cost) 1))))
    (when (getf step :effects-stored)
      (setf plist (list* :adds (json-array (getf step :adds))
                         :deletes (json-array (getf step :deletes))
                         plist)))
    (when (getf step :preconditions-stored)
      (setf plist (list* :preconditions (json-array (getf step :preconditions))
                         plist)))
    (when (getf step :stored-apply)
      (setf plist (list* :stored-apply t plist)))
    (if (getf step :effects-only)
        (list* :effects-only t plist)
        plist)))

(defun %serialize-plan (plan)
  (if (plan-p plan)
      (list :success (and (plan-success plan) t)
            :goals (json-array (plan-goals plan))
            :steps (json-array (mapcar #'%serialize-step (plan-steps plan)))
            :remaining (json-array (plan-remaining plan))
            :operators-used (json-array (plan-operators-used plan))
            :length (plan-length plan)
            :cost (plan-cost plan)
            :from-procedure (or (getf (plan-meta plan) :from-procedure) :null))
      :null))

(defun %serialize-execution (ex)
  (if (execution-result-p ex)
      (list :success (and (execution-success ex) t)
            :mode (execution-mode ex)
            :steps (json-array (execution-steps ex))
            :divergences (json-array (execution-divergences ex))
            :strategy-events (json-array (execution-strategy-events ex)))
      :null))

(defun %serialize-event (ev)
  (list :id (event-id ev)
        :type (event-type ev)
        :data (json-array (event-data ev))
        :status (event-status ev)
        :timestamp (event-timestamp ev)))

(defun %serialize-reaction (r)
  (list :name (event-reaction-name r)
        :when (event-reaction-when r)
        :assert (json-array (event-reaction-assert r))
        :goals (json-array (event-reaction-goals r))))

(defun %serialize-operator (op)
  (list :name (operator-name op)
        :preconditions (operator-preconditions op)
        :add-list (operator-add-list op)
        :delete-list (operator-delete-list op)
        :cost (operator-cost op)
        :meta (operator-meta op)))

(defun %api-status ()
  (let ((ctx (ensure-current-context)))
    (list :ok t
          :version *version*
          :api *web-api-version*
          :context (context-name ctx)
          :mode (context-mode ctx)
          :domains (json-array (gp-domains))
          :plan-p (and (plan-p *current-plan*) t)
          :events (length (gp-events))
          :goals (length (gp-goals))
          :facts (length (gp-facts)))))

(defun %api-context ()
  (let ((ctx (ensure-current-context)))
    (list :name (context-name ctx)
          :mode (context-mode ctx)
          :domains (json-array (gp-domains))
          :fact-count (length (gp-facts))
          :goal-count (length (gp-goals))
          :operator-count (length (gp-operators))
          :rule-count (length (gp-rules))
          :event-count (length (gp-events))
          :reaction-count (length (gp-reactions))
          :meta (or (context-meta ctx) :null))))

(defun %serialize-last-reaction (summary)
  (cond
    ((null summary) :null)
    ((not (listp summary)) :null)
    (t (list :processed (getf summary :processed)
             :matched (json-array (getf summary :matched))
             :facts-added (json-array (getf summary :facts-added))
             :goals-added (json-array (getf summary :goals-added))
             :plan (%serialize-plan (getf summary :plan))))))

(defun %api-explain ()
  (multiple-value-bind (text trace)
      (explain-trace :last :stream nil)
    (list :text (or text "")
          :has-trace (and (deliberative-trace-p trace) t))))

(defun %serialize-autonomy (summary)
  (cond
    ((null summary) :null)
    ((not (listp summary)) :null)
    (t
     (list :status (getf summary :status)
           :halt (getf summary :halt)
           :authority (getf summary :authority)
           :authorized (getf summary :authorized)
           :authorize-reason (getf summary :authorize-reason)
           :iterations (getf summary :iterations)
           :phases (json-array (getf summary :phases))
           :plan (or (getf summary :plan) :null)
           :execution (or (getf summary :execution) :null)
           :goals (json-array (getf summary :goals))
           :pending-events (or (getf summary :pending-events) 0)))))

(defun %api-autonomy-status ()
  (let ((p (ensure-autonomy-policy)))
    (list :ok t
          :policy (list :authority (policy-authority p)
                        :max-steps (policy-max-steps p)
                        :adapters (policy-adapters p)
                        :auto-confirm (policy-auto-confirm p)
                        :react-events (policy-react-events p)
                        :learn (policy-learn p)
                        :prefer-archive (policy-prefer-archive p))
          :last (%serialize-autonomy *last-autonomy*))))

(defun %find-archived-procedure (name)
  "Resolve NAME (symbol or JSON string) to a stored procedure, or NIL.
Exact match first, then a case-insensitive symbol name so the console can
send back the string LISP->JSON produced."
  (when name
    (let* ((procs (gp-procedures))
           (sym (cond
                  ((symbolp name) name)
                  ((stringp name) (json->sexp name))
                  (t nil)))
           (wanted (and (symbolp sym) (symbol-name sym))))
      (or (and (symbolp sym) (find-procedure sym))
          (and wanted
               (find wanted procs
                     :key (lambda (p)
                            (let ((n (procedure-name p)))
                              (if (symbolp n) (symbol-name n) "")))
                     :test #'string-equal))))))

(defun %serialize-procedure (procedure)
  (list :name (procedure-name procedure)
        :goals (json-array (procedure-goals procedure))
        :success-count (procedure-success-count procedure)
        :failure-count (procedure-failure-count procedure)
        :score (procedure-score procedure)
        :operators-used (json-array (procedure-operators-used procedure))
        :step-count (length (procedure-steps procedure))))

(defun %archive-body (&optional procedure)
  (list :ok t
        :procedure (if (procedure-p procedure)
                       (%serialize-procedure procedure)
                       :null)
        :procedures (json-array
                     (mapcar #'%serialize-procedure (gp-archive)))))

(defun %body-get (body key &optional default)
  (let ((v (getf body key :missing)))
    (if (eq v :missing) default v)))

(defun %json-sequence (value)
  "A JSON array is a vector; a Lisp caller may pass a list. One item stays a list."
  (cond
    ((or (null value) (eq value :missing) (eq value :null)) nil)
    ((vectorp value) (coerce value 'list))
    ((listp value) value)
    (t (list value))))

(defun web-api-handle (method path &optional body)
  "Dispatch METHOD (:GET/:POST) and PATH (string) with optional BODY plist
(from JSON). Returns (VALUES STATUS-CODE RESPONSE-PLIST).
STATUS-CODE is an integer; RESPONSE-PLIST is encoded by the HTTP layer."
  (let* ((m (if (stringp method)
                (intern (string-upcase method) :keyword)
                method))
         (p (string path))
         (body (or body nil)))
    (handler-case
        (cond
          ((and (eq m :get) (string= p "/api/status"))
           (values 200 (%api-status)))
          ((and (eq m :get) (string= p "/api/context"))
           (values 200 (%api-context)))
          ((and (eq m :get) (string= p "/api/facts"))
           (values 200 (list :facts (json-array (gp-facts)))))
          ((and (eq m :get) (string= p "/api/goals"))
           (values 200 (list :goals (json-array (gp-goals)))))
          ((and (eq m :get) (string= p "/api/operators"))
           (values 200 (list :operators
                             (json-array
                              (mapcar #'%serialize-operator (gp-operators))))))
          ((and (eq m :get) (string= p "/api/rules"))
           (values 200
                   (list :rules
                         (json-array
                          (mapcar (lambda (r)
                                    (list :name (rule-name r)
                                          :if (json-array (rule-if r))
                                          :then (json-array (rule-then r))))
                                  (gp-rules))))))
          ((and (eq m :get) (string= p "/api/events"))
           (values 200 (list :events
                             (json-array
                              (mapcar #'%serialize-event (gp-events))))))
          ((and (eq m :get) (string= p "/api/reactions"))
           (values 200
                   (list :reactions
                         (json-array
                          (mapcar #'%serialize-reaction (gp-reactions))))))
          ((and (eq m :get) (string= p "/api/plan"))
           (values 200 (list :plan (%serialize-plan (gp-last-plan)))))
          ((and (eq m :get) (string= p "/api/execution"))
           (values 200
                   (list :execution
                         (%serialize-execution (gp-last-execution)))))
          ((and (eq m :get) (string= p "/api/explain"))
           (values 200 (%api-explain)))
          ((and (eq m :get) (string= p "/api/reaction"))
           (values 200 (list :reaction
                             (%serialize-last-reaction *last-reaction*))))
          ((and (eq m :get) (string= p "/api/autonomy"))
           (values 200 (%api-autonomy-status)))
          ((and (eq m :get) (string= p "/api/archive"))
           (values 200 (%archive-body)))

          ((and (eq m :post) (string= p "/api/reset"))
           (gp-reset)
           (values 200 (list :ok t :context (%api-context))))

          ((and (eq m :post) (string= p "/api/add-fact"))
           (let ((fact (json->sexp (%body-get body :fact))))
             (unless (consp fact)
               (error "add-fact requires :fact array"))
             (gp-add-fact fact)
             (values 200 (list :ok t :fact fact
                               :facts (json-array (gp-facts))))))

          ((and (eq m :post) (string= p "/api/add-goal"))
           (let ((goal (json->sexp (%body-get body :goal))))
             (unless goal
               (error "add-goal requires :goal"))
             (gp-add-goal goal)
             (values 200 (list :ok t :goal goal
                               :goals (json-array (gp-goals))))))

          ((and (eq m :post) (string= p "/api/load-domain"))
           (let* ((d (%body-get body :domain))
                  (kw (cond
                        ((keywordp d) d)
                        ((symbolp d) (intern (symbol-name d) :keyword))
                        ((stringp d) (intern (string-upcase d) :keyword))
                        (t (error "load-domain requires :domain"))))
                  (seed (%body-get body :seed-demo t)))
             (gp-load-domain kw :seed-demo (and seed (not (eq seed :null))))
             (values 200 (list :ok t :domains (json-array (gp-domains))
                               :context (%api-context)))))

          ((and (eq m :post) (string= p "/api/plan"))
           (let* ((raw (%body-get body :goals :missing))
                  (goals (unless (eq raw :missing)
                           (mapcar #'json->sexp (%json-sequence raw))))
                  (plan (if goals
                            (gp-plan :goals goals)
                            (gp-plan))))
             (values 200 (list :ok t :plan (%serialize-plan plan)))))

          ((and (eq m :post) (string= p "/api/simulate"))
           (unless (plan-p *current-plan*)
             (error "No plan to simulate; POST /api/plan first"))
           (let ((ex (gp-simulate)))
             (values 200 (list :ok t
                               :execution (%serialize-execution ex)))))

          ((and (eq m :post) (string= p "/api/run"))
           (unless (plan-p *current-plan*)
             (error "No plan to run; POST /api/plan first"))
           (let* ((confirm (%body-get body :confirm t))
                  (adapters (%body-get body :adapters nil))
                  (ex (gp-run :confirm (and confirm (not (eq confirm :null)))
                              :adapters (and adapters
                                             (not (eq adapters :null))))))
             (values 200 (list :ok t
                               :execution (%serialize-execution ex)
                               :facts (json-array (gp-facts))))))

          ((and (eq m :post) (string= p "/api/emit"))
           (let* ((ev (json->sexp (%body-get body :event)))
                  (react (%body-get body :react nil))
                  (plan (%body-get body :plan nil))
                  (event (gp-emit ev
                                  :react (and react (not (eq react :null)))
                                  :plan (and plan (not (eq plan :null))))))
             (values 200
                     (list :ok t
                           :event (%serialize-event event)
                           :reaction (%serialize-last-reaction *last-reaction*)
                           :plan (%serialize-plan *current-plan*)
                           :goals (json-array (gp-goals))
                           :facts (json-array (gp-facts))))))

          ((and (eq m :post) (string= p "/api/react"))
           (let* ((plan (%body-get body :plan nil))
                  (summary (gp-react
                            :plan (and plan (not (eq plan :null))))))
             (values 200
                     (list :ok t
                           :reaction (%serialize-last-reaction summary)
                           :plan (%serialize-plan *current-plan*)
                           :goals (json-array (gp-goals))))))

          ((and (eq m :post) (string= p "/api/archive/remember"))
           (let* ((raw (%body-get body :name :missing))
                  (name (if (eq raw :missing) nil (json->sexp raw)))
                  (proc (if name
                            (gp-remember-procedure :name name)
                            (gp-remember-procedure))))
             (values 200 (%archive-body proc))))

          ((and (eq m :post) (string= p "/api/archive/use"))
           (let* ((raw-name (%body-get body :name :missing))
                  (raw-goals (%body-get body :goals :missing))
                  (found (unless (eq raw-name :missing)
                           (or (%find-archived-procedure raw-name)
                               (error "No archived procedure named ~S." raw-name))))
                  (goals (unless (eq raw-goals :missing)
                           (mapcar #'json->sexp (%json-sequence raw-goals))))
                  (unchecked (and (%body-get body :unchecked nil)
                                  (not (eq (%body-get body :unchecked nil) :null))))
                  (plan (cond
                          (found (gp-use-procedure :name (procedure-name found)
                                                   :unchecked unchecked))
                          (goals (gp-use-procedure :goals goals
                                                   :unchecked unchecked))
                          (t (gp-use-procedure :unchecked unchecked)))))
             (values 200 (list* :plan (%serialize-plan plan)
                                (%archive-body found)))))

          ((and (eq m :post) (string= p "/api/archive/score"))
           (let* ((raw (%body-get body :name :missing))
                  (success (%body-get body :success t))
                  (found (unless (eq raw :missing)
                           (%find-archived-procedure raw))))
             (unless found
               (error "No archived procedure named ~S." raw))
             (gp-score-procedure (procedure-name found)
                                 :success (and success (not (eq success :null))))
             (values 200 (%archive-body
                          (find-procedure (procedure-name found))))))

          ((and (eq m :post) (string= p "/api/autonomy/policy"))
           (let* ((auth (%body-get body :authority :missing))
                  (args nil))
             (unless (eq auth :missing)
               (setf args (list* :authority
                                 (if (stringp auth)
                                     (intern (string-upcase auth) :keyword)
                                     auth)
                                 args)))
             (dolist (key '(:max-steps :adapters :auto-confirm
                            :react-events :learn :prefer-archive))
               (let ((v (%body-get body key :missing)))
                 (unless (eq v :missing)
                   (setf args (list* key v args)))))
             (apply #'gp-policy args)
             (values 200 (%api-autonomy-status))))

          ((and (eq m :post) (string= p "/api/autonomy/step"))
           (let* ((auth (%body-get body :authority :missing))
                  (pol (if (eq auth :missing)
                           (ensure-autonomy-policy)
                           (make-autonomy-policy
                            :authority (if (stringp auth)
                                           (intern (string-upcase auth) :keyword)
                                           auth)
                            :auto-confirm (%body-get body :auto-confirm nil)
                            :adapters (%body-get body :adapters nil)
                            :max-steps (or (%body-get body :max-steps) 8))))
                  (summary (gp-autonomous-step :policy pol)))
             (values 200 (list :ok t
                               :autonomy (%serialize-autonomy summary)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))
                               :plan (%serialize-plan *current-plan*)))))

          ((and (eq m :post) (string= p "/api/autonomy/loop"))
           (let* ((auth (%body-get body :authority :simulate))
                  (pol (make-autonomy-policy
                        :authority (if (stringp auth)
                                       (intern (string-upcase auth) :keyword)
                                       (or auth :simulate))
                        :auto-confirm (%body-get body :auto-confirm nil)
                        :adapters (%body-get body :adapters nil)
                        :max-steps (or (%body-get body :max-steps) 8)))
                  (summary (gp-autonomous-loop :policy pol
                                               :max-steps (policy-max-steps pol))))
             (values 200 (list :ok t
                               :autonomy (%serialize-autonomy summary)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))
                               :plan (%serialize-plan *current-plan*)))))

          (t (values 404 (list :ok nil
                               :error "not-found"
                               :method m
                               :path p))))
      (error (e)
        (values 400 (list :ok nil
                          :error (princ-to-string e)))))))

(defun web-api-handle-json (method path &optional json-body)
  "Like WEB-API-HANDLE but BODY is a JSON string; returns JSON string body."
  (let ((body (when (and json-body (plusp (length (string-trim '(#\Space #\Newline)
                                                              json-body))))
                (json->lisp json-body))))
    (multiple-value-bind (code plist)
        (web-api-handle method path body)
      (values code "application/json; charset=utf-8" (lisp->json plist)))))
