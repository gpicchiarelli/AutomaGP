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

(defun %plan-external-gates (plan &optional context)
  "Return (VALUES MATCHES-P SUPPORTED-P) for PLAN's external-action gates.
No plan yields (VALUES T T) — callers still require plan-success to enable
simulate/run. MATCHES and SUPPORTED use the same rules as GET /api/plan."
  (unless (plan-p plan)
    (return-from %plan-external-gates (values t t)))
  (let* ((ctx (or context (ensure-current-context)))
         (recorded (getf (plan-meta plan) :external-actions-recorded))
         (live (plan-external-actions plan :context ctx))
         (actions (if recorded
                      (getf (plan-meta plan) :external-actions)
                      live))
         (matches (if recorded
                      (and (plan-external-actions-match-p plan :context ctx) t)
                      (null live)))
         (supported (or (null actions)
                        (plan-external-actions-supported-p plan :context ctx))))
    (values (and matches t) (and supported t))))

(defun %serialize-plan (plan)
  (if (plan-p plan)
      (let* ((ctx (ensure-current-context))
             (recorded (getf (plan-meta plan) :external-actions-recorded))
             (live (plan-external-actions plan :context ctx))
             (withheld (plan-external-actions-withheld plan :context ctx)))
        (multiple-value-bind (matches supported)
            (%plan-external-gates plan ctx)
          (list :success (and (plan-success plan) t)
                :goals (json-array (plan-goals plan))
                :steps (json-array (mapcar #'%serialize-step (plan-steps plan)))
                :remaining (json-array (plan-remaining plan))
                :operators-used (json-array (plan-operators-used plan))
                :length (plan-length plan)
                :cost (plan-cost plan)
                :from-procedure (or (getf (plan-meta plan) :from-procedure) :null)
                :external (json-array
                           (if recorded
                               (getf (plan-meta plan) :external-actions)
                               live))
                :external-matches matches
                :external-withheld
                (json-array
                 (if recorded
                     (getf (plan-meta plan) :external-actions-withheld)
                     withheld))
                :external-supported supported)))
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
        :goals (json-array (event-reaction-goals r))
        :ask (json-array (getf (event-reaction-meta r) :ask))))

(defun %serialize-operator (op)
  (list :name (operator-name op)
        :preconditions (operator-preconditions op)
        :add-list (operator-add-list op)
        :delete-list (operator-delete-list op)
        :cost (operator-cost op)
        :meta (operator-meta op)
        :ask (json-array (getf (operator-meta op) :ask))))

(defun %api-status ()
  (let* ((ctx (ensure-current-context))
         (goals (normalize-planning-goals (goals-of ctx)))
         (open (differences (context-all-facts ctx) goals)))
    (multiple-value-bind (matches supported)
        (%plan-external-gates *current-plan* ctx)
      (list :ok t
            :version *version*
            :api *web-api-version*
            :context (context-name ctx)
            :mode (context-mode ctx)
            :domains (json-array (gp-domains))
            :plan-p (and (plan-p *current-plan*) t)
            :plan-success (and (plan-p *current-plan*)
                               (plan-success *current-plan*)
                               t)
            :external-matches matches
            :external-supported supported
            :events (length (gp-events))
            :pending-events (length (pending-events ctx))
            :goals (length (gp-goals))
            :open-goals (length open)
            :facts (length (gp-facts))
            :repair-depth *procedure-repair-archive-depth*
            :listening (and (observation-active-p) t)
            :directory-watch (or (and (fboundp 'gp-directory-watch)
                                      (gp-directory-watch))
                                 :null)
            :process-watch (or (and (fboundp 'gp-process-watch)
                                    (gp-process-watch))
                               :null)
            :terminal-watch (or (and (fboundp 'gp-terminal-watch)
                                     (gp-terminal-watch))
                                :null)
            :terminal-text-watch (or (and (fboundp 'gp-terminal-text-watch)
                                          (gp-terminal-text-watch))
                                     :null)
            :terminal-screen-watch (or (and (fboundp 'gp-terminal-screen-watch)
                                            (gp-terminal-screen-watch))
                                       :null)
            :listening-missing
            (json-array (if (observation-active-p)
                            (getf *observation* :missing)
                            nil))))))

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
    (multiple-value-bind (narration nodes)
        (narrate-trace trace)
      (list :text (or text "")
            :narration (or narration "")
            :graph (json-array nodes)
            :has-trace (and (deliberative-trace-p trace) t)))))

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

(defun %positive-step-count (value &optional default)
  "Coerce VALUE to an integer ≥ 1, or DEFAULT when VALUE is not a number."
  (cond
    ((integerp value) (max 1 value))
    ((and (realp value) (not (complexp value)))
     (max 1 (round value)))
    (t default)))

(defun %autonomy-policy-from-body (body &key (default-authority :simulate))
  "Build a policy for one step or loop from BODY, inheriting max-steps
from the session policy when the body omits it."
  (let* ((base (ensure-autonomy-policy))
         (auth-raw (%body-get body :authority :missing))
         (auth (cond
                 ((eq auth-raw :missing) default-authority)
                 ((stringp auth-raw)
                  (intern (string-upcase auth-raw) :keyword))
                 (t auth-raw)))
         (steps-raw (%body-get body :max-steps :missing))
         (steps (if (eq steps-raw :missing)
                    (policy-max-steps base)
                    (%positive-step-count steps-raw (policy-max-steps base))))
         (adapters (%body-get body :adapters nil))
         (auto-confirm (%body-get body :auto-confirm nil)))
    (make-autonomy-policy
     :authority auth
     :max-steps steps
     :adapters (and adapters (not (eq adapters :null)))
     :auto-confirm (and auto-confirm (not (eq auto-confirm :null))))))

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

(defvar *applies-result-cache* nil
  "Cache for %PROCEDURE-APPLIES-P across identical fact/operator snapshots.
Plist :FACTS :OP-NAMES :BY-NAME (hash name-string → (fingerprint . applies)).
Fingerprint changes when a procedure is remembered or scored.")

(defun %clear-applies-result-cache ()
  "Drop the applies probe cache (reset / memory clear)."
  (setf *applies-result-cache* nil))

(defun %procedure-fingerprint (procedure)
  (list (procedure-name procedure)
        (procedure-success-count procedure)
        (procedure-failure-count procedure)
        (procedure-score procedure)
        (length (procedure-steps procedure))))

(defun %procedure-applies-uncached (procedure facts operators)
  "Probe PROCEDURE on FACTS without touching the session deliberative trace."
  (let ((saved-last *last-trace*)
        (saved-history *trace-history*)
        (saved-current *current-trace*))
    (unwind-protect
        (let ((*current-trace* nil)
              (*trace-enabled* nil))
          (and (nth-value 0 (replay-procedure procedure facts operators))
               t))
      (setf *last-trace* saved-last
            *trace-history* saved-history
            *current-trace* saved-current))))

(defun %procedure-applies-p (procedure)
  "True when PROCEDURE would rebuild a plan on the current facts.
Caches per fact/operator snapshot and procedure fingerprint so a workbench
poll with applies=1 does not replay every procedure twice a second when
nothing changed. Does not disturb the session deliberative trace."
  (let* ((ctx (ensure-current-context))
         (facts (context-all-facts ctx))
         (ops (context-planning-operators ctx))
         (op-names (mapcar #'operator-name ops))
         (cache *applies-result-cache*)
         (by-name (when (and (equal facts (getf cache :facts))
                             (equal op-names (getf cache :op-names)))
                    (getf cache :by-name)))
         (pname (procedure-name procedure))
         (key (if (symbolp pname)
                  (symbol-name pname)
                  (princ-to-string pname)))
         (fp (%procedure-fingerprint procedure)))
    (unless by-name
      (setf by-name (make-hash-table :test #'equal)
            *applies-result-cache* (list :facts (copy-list facts)
                                         :op-names (copy-list op-names)
                                         :by-name by-name)))
    (multiple-value-bind (entry present) (gethash key by-name)
      (if (and present (equal (car entry) fp))
          (cdr entry)
          (let ((applies (%procedure-applies-uncached procedure facts ops)))
            (setf (gethash key by-name) (cons fp applies))
            applies)))))

(defun %serialize-procedure (procedure &key include-applies)
  (let ((base (list :name (procedure-name procedure)
                    :goals (json-array (procedure-goals procedure))
                    :success-count (procedure-success-count procedure)
                    :failure-count (procedure-failure-count procedure)
                    :score (procedure-score procedure)
                    :operators-used (json-array (procedure-operators-used procedure))
                    :step-count (length (procedure-steps procedure)))))
    (if include-applies
        (append base (list :applies (and (%procedure-applies-p procedure) t)))
        base)))

(defun %archive-body (&key procedure include-applies)
  (list :ok t
        :procedure (if (procedure-p procedure)
                       (%serialize-procedure procedure
                                             :include-applies include-applies)
                       :null)
        :procedures (json-array
                     (mapcar (lambda (p)
                               (%serialize-procedure p
                                                     :include-applies include-applies))
                             (gp-archive)))))

(defun %split-path-query (path)
  "Return (VALUES PATH-WITHOUT-QUERY QUERY-STRING-OR-NIL)."
  (let ((qpos (position #\? path)))
    (if qpos
        (values (subseq path 0 qpos)
                (subseq path (1+ qpos)))
        (values path nil))))

(defun %query-has-flag (query flag)
  "True when QUERY contains FLAG=1|true|yes|t (case-insensitive)."
  (when (and query (plusp (length query)))
    (let* ((q (string-downcase (concatenate 'string "&" query "&")))
           (f (string-downcase (string flag))))
      (some (lambda (val)
              (search (format nil "&~A=~A&" f val) q))
            '("1" "true" "yes" "t")))))

(defun %api-flag (value)
  "Interpret a JSON/body flag: non-null true-ish values."
  (cond
    ((or (eq value :missing) (eq value :null) (null value)) nil)
    ((eq value t) t)
    ((and (numberp value) (not (zerop value))) t)
    ((stringp value)
     (member (string-downcase value) '("1" "true" "yes" "t") :test #'string=))
    (t nil)))

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

(defun %context-symbols ()
  "Symbols already used in the current facts and goals."
  (let ((bag nil))
    (dolist (fact (append (gp-facts) (gp-goals)))
      (when (consp fact)
        (dolist (term fact)
          (when (and (symbolp term) (not (keywordp term)))
            (push term bag)))))
    bag))

(defun %adopt-term (term)
  "Reuse a context symbol with the same name. Numbers and strings stay."
  (if (and (symbolp term) (not (keywordp term)))
      (or (find (symbol-name term) (%context-symbols)
                :key #'symbol-name :test #'string=)
          term)
      term))

(defun %adopt-fact (fact)
  "Rewrite FACT onto the vocabulary already in the context.
JSON has no packages. A new word joins the package of the facts the
user is looking at, so a later edit matches them."
  (unless (consp fact)
    (return-from %adopt-fact fact))
  (let* ((adopted (mapcar #'%adopt-term fact))
         (home (some (lambda (term)
                       (and (symbolp term)
                            (not (keywordp term))
                            (not (eq (symbol-package term)
                                     (find-package :automa-gp)))
                            (symbol-package term)))
                     adopted)))
    (if (null home)
        adopted
        (mapcar (lambda (term)
                  (if (and (symbolp term)
                           (not (keywordp term))
                           (eq (symbol-package term) (find-package :automa-gp)))
                      (intern (symbol-name term) home)
                      term))
                adopted))))

(defun %fact-same-names-p (a b)
  "True when two facts use the same names, whatever their packages."
  (fact-same-names-p a b))

(defun %live-fact (fact)
  "The stored fact whose names match FACT, or NIL."
  (find-fact-by-names fact (gp-facts)))

(defun web-api-handle (method path &optional body)
  "Dispatch METHOD (:GET/:POST) and PATH (string) with optional BODY plist
(from JSON). Returns (VALUES STATUS-CODE RESPONSE-PLIST).
STATUS-CODE is an integer; RESPONSE-PLIST is encoded by the HTTP layer.
PATH may include a query string (e.g. /api/archive?applies=1)."
  (let* ((m (if (stringp method)
                (intern (string-upcase method) :keyword)
                method))
         (body (or body nil)))
    (multiple-value-bind (p query)
        (%split-path-query (string path))
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
                                          :then (json-array (rule-then r))
                                          :ask (json-array (getf (rule-meta r) :ask))))
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
           (let ((include-applies
                  (or (%query-has-flag query "applies")
                      (%api-flag (%body-get body :applies :missing)))))
             (values 200 (%archive-body :include-applies include-applies))))

          ((and (eq m :post) (string= p "/api/reset"))
           (gp-reset)
           (values 200 (list :ok t :context (%api-context))))

          ((and (eq m :post) (string= p "/api/add-fact"))
           (let ((fact (%adopt-fact (json->sexp (%body-get body :fact)))))
             (unless (consp fact)
               (error "add-fact requires :fact array"))
             (gp-add-fact fact)
             (values 200 (list :ok t :fact fact
                               :facts (json-array (gp-facts))))))

          ((and (eq m :post) (string= p "/api/remove-fact"))
           (let* ((raw (json->sexp (%body-get body :fact)))
                  (fact (%live-fact raw)))
             (unless (consp raw)
               (error "remove-fact requires :fact array"))
             (unless fact
               (error "No fact with those names is in the context."))
             (gp-remove-fact fact)
             (values 200 (list :ok t :fact fact
                               :facts (json-array (gp-facts))))))

          ((and (eq m :post) (string= p "/api/watch-directory"))
           (let ((path (%body-get body :path))
                 (interval (%body-get body :interval 1)))
             (unless (stringp path)
               (error "watch-directory requires :path string"))
             (unless (realp interval)
               (error "watch-directory requires :interval number"))
             (let ((noticed (gp-watch-directory path :interval interval)))
               (values 200 (list :ok t
                                 :path (gp-directory-watch)
                                 :noticed (json-array noticed)
                                 :facts (json-array (gp-facts))
                                 :goals (json-array (gp-goals)))))))

          ((and (eq m :post) (string= p "/api/watch-directory/stop"))
           (let ((noticed (gp-stop-directory-watch)))
             (values 200 (list :ok t
                               :noticed (json-array noticed)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))))))

          ((and (eq m :post) (string= p "/api/watch-processes"))
           (let ((interval (%body-get body :interval 1)))
             (unless (realp interval)
               (error "watch-processes requires :interval number"))
             (let ((noticed (gp-watch-processes :interval interval)))
               (values 200 (list :ok t
                                 :watching (gp-process-watch)
                                 :noticed (json-array noticed)
                                 :facts (json-array (gp-facts))
                                 :goals (json-array (gp-goals)))))))

          ((and (eq m :post) (string= p "/api/watch-processes/stop"))
           (let ((noticed (gp-stop-process-watch)))
             (values 200 (list :ok t
                               :noticed (json-array noticed)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))))))

          ((and (eq m :post) (string= p "/api/watch-terminals"))
           (let ((interval (%body-get body :interval 1)))
             (unless (realp interval)
               (error "watch-terminals requires :interval number"))
             (let ((noticed (gp-watch-terminals :interval interval)))
               (values 200 (list :ok t
                                 :watching (gp-terminal-watch)
                                 :noticed (json-array noticed)
                                 :facts (json-array (gp-facts))
                                 :goals (json-array (gp-goals)))))))

          ((and (eq m :post) (string= p "/api/watch-terminals/stop"))
           (let ((noticed (gp-stop-terminal-watch)))
             (values 200 (list :ok t
                               :noticed (json-array noticed)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))))))

          ((and (eq m :post) (string= p "/api/watch-terminal-text"))
           (let ((interval (%body-get body :interval 1)))
             (unless (realp interval)
               (error "watch-terminal-text requires :interval number"))
             (let ((noticed (gp-watch-terminal-text :interval interval)))
               (values 200 (list :ok t
                                 :watching (gp-terminal-text-watch)
                                 :noticed (json-array noticed)
                                 :facts (json-array (gp-facts))
                                 :goals (json-array (gp-goals)))))))

          ((and (eq m :post) (string= p "/api/watch-terminal-text/stop"))
           (let ((noticed (gp-stop-terminal-text-watch)))
             (values 200 (list :ok t
                               :noticed (json-array noticed)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))))))

          ((and (eq m :post) (string= p "/api/watch-terminal-screen"))
           (let ((interval (%body-get body :interval 1)))
             (unless (realp interval)
               (error "watch-terminal-screen requires :interval number"))
             (let ((noticed (gp-watch-terminal-screen :interval interval)))
               (values 200 (list :ok t
                                 :watching (gp-terminal-screen-watch)
                                 :noticed (json-array noticed)
                                 :facts (json-array (gp-facts))
                                 :goals (json-array (gp-goals)))))))

          ((and (eq m :post) (string= p "/api/watch-terminal-screen/stop"))
           (let ((noticed (gp-stop-terminal-screen-watch)))
             (values 200 (list :ok t
                               :noticed (json-array noticed)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))))))

          ((and (eq m :post) (string= p "/api/notice-terminal-screen"))
           (let ((noticed (gp-notice-terminal-screen)))
             (values 200 (list :ok t
                               :noticed (json-array noticed)
                               :listening (and (observation-active-p) t)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))))))

          ((and (eq m :post) (string= p "/api/notice-terminal-text"))
           (let ((noticed (gp-notice-terminal-text)))
             (values 200 (list :ok t
                               :noticed (json-array noticed)
                               :listening (and (observation-active-p) t)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))))))

          ((and (eq m :post) (string= p "/api/notice-terminals"))
           (let ((noticed (gp-notice-terminals)))
             (values 200 (list :ok t
                               :noticed (json-array noticed)
                               :listening (and (observation-active-p) t)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))))))

          ((and (eq m :post) (string= p "/api/notice-processes"))
           (let ((noticed (gp-notice-processes)))
             (values 200 (list :ok t
                               :noticed (json-array noticed)
                               :listening (and (observation-active-p) t)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))))))

          ((and (eq m :post) (string= p "/api/notice-directory"))
           (let ((path (%body-get body :path)))
             (unless (stringp path)
               (error "notice-directory requires :path string"))
             (let ((noticed (gp-notice-directory path)))
               (values 200 (list :ok t
                                 :noticed (json-array noticed)
                                 :listening (and (observation-active-p) t)
                                 :facts (json-array (gp-facts))
                                 :goals (json-array (gp-goals)))))))

          ((and (eq m :post) (string= p "/api/notice-path"))
           (let ((path (%body-get body :path)))
             (unless (stringp path)
               (error "notice-path requires :path string"))
             (let ((fact (gp-notice-path path)))
               (values 200 (list :ok t
                                 :fact fact
                                 :listening (and (observation-active-p) t)
                                 :facts (json-array (gp-facts)))))))

          ((and (eq m :post) (string= p "/api/ask"))
           (let ((phrase (%body-get body :phrase)))
             (unless (stringp phrase)
               (error "ask requires :phrase string"))
             (handler-case
                 (multiple-value-bind (goal plan) (gp-ask phrase)
                   (values 200 (list :ok t
                                     :goal goal
                                     :plan (%serialize-plan plan)
                                     :listening (and (observation-active-p) t)
                                     :goals (json-array (gp-goals)))))
               (ambiguous-goal (c)
                 (values 400 (list :ok nil
                                   :error (princ-to-string c)
                                   :goals (json-array (ambiguous-goal-goals c)))))
               (unspecific-word (c)
                 (values 400 (list :ok nil
                                   :error (princ-to-string c)
                                   :goals (json-array (unspecific-word-goals c)))))
               (unrelated-word (c)
                 (values 400 (list :ok nil
                                   :error (princ-to-string c)
                                   :goals (json-array (unrelated-word-goals c)))))
               (not-that-name (c)
                 (values 400 (list :ok nil
                                   :error (princ-to-string c)
                                   :word (not-that-name-word c)
                                   :name (not-that-name-name c))))
               (undeclared-word (c)
                 (values 400
                         (list :ok nil
                               :error (princ-to-string c)
                               :word (undeclared-word-word c)
                               :choices
                               (json-array
                                (mapcar (lambda (choice)
                                          (list :kind (string-downcase
                                                       (%kind-label (first choice)))
                                                :name (second choice)
                                                :goal (third choice)))
                                        (undeclared-word-choices c)))))))))

          ((and (eq m :post) (string= p "/api/add-goal"))
           (let ((goal (%adopt-fact (json->sexp (%body-get body :goal)))))
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

          ((and (eq m :post) (string= p "/api/plan-open-goals"))
           (let ((plan (gp-plan-open-goals)))
             (values 200 (list :ok t
                               :plan (%serialize-plan plan)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))))))

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
           (unless (plan-success *current-plan*)
             (error "The plan did not succeed; plan again before simulating."))
           (multiple-value-bind (matches supported)
               (%plan-external-gates *current-plan*)
             (unless matches
               (error "The external action no longer matches the plan."))
             (unless supported
               (error "The facts no longer support the external action.")))
           (let ((ex (gp-simulate)))
             (values 200 (list :ok t
                               :execution (%serialize-execution ex)))))

          ((and (eq m :post) (string= p "/api/run"))
           (unless (plan-p *current-plan*)
             (error "No plan to run; POST /api/plan first"))
           (unless (plan-success *current-plan*)
             (error "The plan did not succeed; plan again before running."))
           (multiple-value-bind (matches supported)
               (%plan-external-gates *current-plan*)
             (unless matches
               (error "The external action no longer matches the plan."))
             (unless supported
               (error "The facts no longer support the external action.")))
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

          ((and (eq m :post) (string= p "/api/listen"))
           (let ((missing (mapcar #'json->sexp
                                  (%json-sequence (%body-get body :missing nil)))))
             (gp-listen :missing missing :reason :manual)
             (values 200 (list :ok t
                               :listening t
                               :facts (json-array (gp-facts))))))

          ((and (eq m :post) (string= p "/api/induce/rule"))
           (let* ((raw-name (%body-get body :name :missing))
                  (name (cond
                          ((eq raw-name :missing)
                           (error "induce requires :name"))
                          ((stringp raw-name) (json->sexp raw-name))
                          (t raw-name)))
                  (before-raw (%body-get body :before :missing))
                  (after-raw (%body-get body :after :missing))
                  (kwargs nil))
             (unless (eq before-raw :missing)
               (setf kwargs (list* :before
                                   (mapcar #'json->sexp (%json-sequence before-raw))
                                   kwargs)))
             (unless (eq after-raw :missing)
               (setf kwargs (list* :after
                                   (mapcar #'json->sexp (%json-sequence after-raw))
                                   kwargs)))
             (let ((op (apply #'gp-induce-rule name kwargs)))
               (values 200 (list :ok t
                                 :listening (and (observation-active-p) t)
                                 :operator (%serialize-operator op))))))

          ((and (eq m :post) (string= p "/api/induce/note"))
           (gp-note-state)
           (values 200 (list :ok t
                             :facts (json-array (gp-facts)))))

          ((and (eq m :post) (string= p "/api/induce"))
           (let* ((raw-name (%body-get body :name :missing))
                  (name (cond
                          ((eq raw-name :missing)
                           (error "induce requires :name"))
                          ((stringp raw-name) (json->sexp raw-name))
                          (t raw-name)))
                  (before-raw (%body-get body :before :missing))
                  (after-raw (%body-get body :after :missing))
                  (kwargs nil))
             (unless (eq before-raw :missing)
               (setf kwargs (list* :before
                                   (mapcar #'json->sexp (%json-sequence before-raw))
                                   kwargs)))
             (unless (eq after-raw :missing)
               (setf kwargs (list* :after
                                   (mapcar #'json->sexp (%json-sequence after-raw))
                                   kwargs)))
             (let ((op (apply #'gp-learn-action name kwargs)))
               (values 200 (list :ok t
                                 :operator (%serialize-operator op))))))

          ((and (eq m :post) (string= p "/api/operator/name"))
           (let* ((raw-name (%body-get body :name :missing))
                  (raw-word (%body-get body :word :missing))
                  (raw-kind (%body-get body :kind :missing))
                  (name (cond
                          ((eq raw-name :missing)
                           (error "The operator needs a name."))
                          (t raw-name)))
                  (word (cond
                          ((eq raw-word :missing)
                           (error "The operator needs one word."))
                          ((stringp raw-word) raw-word)
                          (t (string raw-word))))
                  (kind (if (eq raw-kind :missing) nil raw-kind))
                  (named (gp-name-operator name word :kind kind)))
             (values 200
                     (cond
                       ((operator-p named)
                        (list :ok t :operator (%serialize-operator named)))
                       ((event-reaction-p named)
                        (list :ok t
                              :reaction (event-reaction-name named)
                              :ask (json-array
                                    (getf (event-reaction-meta named) :ask))))
                       ((rule-p named)
                        (list :ok t
                              :rule (rule-name named)
                              :ask (json-array
                                    (getf (rule-meta named) :ask))))
                       (t (list :ok t))))))

          ((and (eq m :post) (string= p "/api/archive/remember"))
           (let* ((raw (%body-get body :name :missing))
                  (name (if (eq raw :missing) nil (json->sexp raw)))
                  (proc (if name
                            (gp-remember-procedure :name name)
                            (gp-remember-procedure))))
             (values 200 (%archive-body :procedure proc))))

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
                                (%archive-body :procedure found)))))

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
                          :procedure (find-procedure (procedure-name found))))))

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
                           (%autonomy-policy-from-body body)))
                  (summary (gp-autonomous-step :policy pol)))
             (values 200 (list :ok t
                               :autonomy (%serialize-autonomy summary)
                               :facts (json-array (gp-facts))
                               :goals (json-array (gp-goals))
                               :plan (%serialize-plan *current-plan*)))))

          ((and (eq m :post) (string= p "/api/autonomy/loop"))
           (let* ((pol (%autonomy-policy-from-body body))
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
                            :error (princ-to-string e))))))))

(defun web-api-handle-json (method path &optional json-body)
  "Like WEB-API-HANDLE but BODY is a JSON string; returns JSON string body."
  (let ((body (when (and json-body (plusp (length (string-trim '(#\Space #\Newline)
                                                              json-body))))
                (json->lisp json-body))))
    (multiple-value-bind (code plist)
        (web-api-handle method path body)
      (values code "application/json; charset=utf-8" (lisp->json plist)))))
