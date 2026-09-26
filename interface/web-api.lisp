;;;; interface/web-api.lisp — HTTP-agnostic operator API (Phase 11)
;;;;
;;;; Thin façade over REPL/core. No Hunchentoot here — the web system maps
;;;; HTTP onto WEB-API-HANDLE. Reasoning stays in the symbolic core.

(in-package #:automa-gp)

(defparameter *web-api-version* "0.11.0"
  "API surface version (aligned with AUTOMA GP Phase 11).")

(defun %serialize-bindings (bindings)
  (json-array
   (mapcar (lambda (pair)
             (list (car pair) (cdr pair)))
           (if (and bindings (consp bindings)
                    (not (eq bindings *no-bindings*)))
               bindings
               nil))))

(defun %serialize-step (step)
  (list :operator (getf step :operator)
        :bindings (%serialize-bindings (getf step :bindings))
        :goal (getf step :goal)
        :subgoals (json-array (getf step :subgoals))
        :cost (or (getf step :cost) 1)))

(defun %serialize-plan (plan)
  (if (plan-p plan)
      (list :success (and (plan-success plan) t)
            :goals (json-array (plan-goals plan))
            :steps (json-array (mapcar #'%serialize-step (plan-steps plan)))
            :remaining (json-array (plan-remaining plan))
            :operators-used (json-array (plan-operators-used plan))
            :length (plan-length plan)
            :cost (plan-cost plan))
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

(defun %body-get (body key &optional default)
  (let ((v (getf body key :missing)))
    (if (eq v :missing) default v)))

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
                  (goals (if (eq raw :missing)
                             nil
                             (mapcar #'json->sexp
                                     (if (listp raw) raw (list raw)))))
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
