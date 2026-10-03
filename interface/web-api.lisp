;;;; interface/web-api.lisp — HTTP-agnostic operator API (Phase 11)
;;;;
;;;; Thin façade over REPL/core. No Hunchentoot here — the web system maps
;;;; HTTP onto WEB-API-HANDLE. Reasoning stays in the symbolic core.
;;;;
;;;; The file has three parts: how session objects are written for JSON, how
;;;; a request body is read, and the routes. A route calls the same GP-
;;;; function the REPL offers, so the gates of that function are the gates
;;;; of the route.

(in-package #:automa-gp)

(defparameter *web-api-version* "0.17.0"
  "API surface version (operator archive routes included).")

;;; ---------------------------------------------------------------------------
;;; Session objects as JSON
;;; ---------------------------------------------------------------------------

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
        :preconditions (json-array (operator-preconditions op))
        :add-list (json-array (operator-add-list op))
        :delete-list (json-array (operator-delete-list op))
        :cost (operator-cost op)
        :meta (operator-meta op)
        :ask (json-array (getf (operator-meta op) :ask))))

(defun %serialize-rule (rule)
  (list :name (rule-name rule)
        :if (json-array (rule-if rule))
        :then (json-array (rule-then rule))
        :ask (json-array (getf (rule-meta rule) :ask))))

(defun %facts-json ()
  "The facts of the session context, as a JSON array."
  (json-array (gp-facts)))

(defun %goals-json ()
  "The goals of the session context, as a JSON array."
  (json-array (gp-goals)))

(defun %listening-p ()
  "T while the session is listening for an induction, else NIL."
  (and (observation-active-p) t))

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
            :listening (%listening-p)
            :directory-watch (or (gp-directory-watch) :null)
            :process-watch (or (gp-process-watch) :null)
            :terminal-watch (or (gp-terminal-watch) :null)
            :terminal-text-watch (or (gp-terminal-text-watch) :null)
            :terminal-screen-watch (or (gp-terminal-screen-watch) :null)
            :watch-failures (json-array (gp-watch-failures))
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
             :dropped (json-array (getf summary :dropped))
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

(defun %summary-with-arrays (summary keys)
  "The plist SUMMARY with the list under each of KEYS as a JSON array, so
that an empty one is written [] and not false. No summary is :NULL."
  (if (null summary)
      :null
      (loop for (key value) on summary by #'cddr
            collect key
            collect (if (member key keys) (json-array value) value))))

(defun %serialize-autonomy (summary)
  "SUMMARY of an autonomous step or loop, as *LAST-AUTONOMY* keeps it.
A loop summary is that of its last step with :ITERATIONS added, so one
shape serves both."
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
           :plan (%summary-with-arrays (getf summary :plan)
                                       '(:operators :remaining))
           :execution (%summary-with-arrays (getf summary :execution)
                                            '(:divergences))
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

;;; ---------------------------------------------------------------------------
;;; The procedure archive
;;; ---------------------------------------------------------------------------

(defun %procedure-name-text (procedure)
  "The name of PROCEDURE as text, without a package."
  (let ((name (procedure-name procedure)))
    (if (symbolp name)
        (symbol-name name)
        (princ-to-string name))))

(defun %find-archived-procedure (name)
  "Resolve NAME (a symbol, or a string as JSON sends it) to a stored
procedure, or NIL.
The name is looked up as the REPL would look it up: a JSON word as the
symbol JSON->SEXP makes of it, a JSON string that stays a string as that
string. When that finds nothing the names are compared as text without
regard to case or package, so the console can send back the string
LISP->JSON produced for a procedure named at the REPL."
  (let ((designator (if (stringp name) (json->sexp name) name)))
    (when (and designator
               (not (eq designator :null))
               (typep designator '(or symbol string)))
      (or (find-procedure designator)
          (find (string designator) (gp-procedures)
                :key #'%procedure-name-text
                :test #'string-equal)))))

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
  "Probe PROCEDURE on FACTS without touching the session deliberative trace.
With tracing off the replay opens no trace and publishes none."
  (let ((*trace-enabled* nil))
    (and (replay-procedure procedure facts operators) t)))

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
         (key (%procedure-name-text procedure))
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

;;; ---------------------------------------------------------------------------
;;; Reading a request
;;; ---------------------------------------------------------------------------

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

(defun %api-flag (value &optional (what "A flag"))
  "Read VALUE, from a request body, as a boolean. Returns T or NIL.
True is JSON true, 1, or one of the strings 1 true yes t. False is JSON
false, null, a missing key (:MISSING), 0, or one of the strings 0 false no
nil and the empty string. Strings are compared without regard to case.
Anything else is an error that names WHAT: a flag that opens a gate is
never guessed from a value that does not say yes or no."
  (flet ((one-of (&rest words)
           (member value words :test #'string-equal)))
    (cond
      ((member value '(nil :null :missing)) nil)
      ((eq value t) t)
      ((eql value 1) t)
      ((eql value 0) nil)
      ((and (stringp value) (one-of "1" "true" "yes" "t")) t)
      ((and (stringp value) (one-of "0" "false" "no" "nil" "")) nil)
      (t (error "~A must be true or false, not ~S." what value)))))

(defun %body-get (body key &optional default)
  (let ((v (getf body key :missing)))
    (if (eq v :missing) default v)))

(defun %body-flag (body key &optional default)
  "The boolean BODY states for KEY, see %API-FLAG; DEFAULT when BODY has no
such key. This is the one reading of a flag for every route."
  (let ((value (getf body key :missing)))
    (if (eq value :missing)
        default
        (%api-flag value (string-downcase (symbol-name key))))))

(defun %body-required (body key message)
  "The value BODY gives for KEY. A missing key or JSON null is an error
that says MESSAGE."
  (let ((value (getf body key :missing)))
    (when (member value '(:missing :null))
      (error "~A" message))
    value))

(defun %body-interval (body route)
  "The watch interval BODY states, in seconds; 1 when it states none."
  (let ((interval (%body-get body :interval 1)))
    (unless (realp interval)
      (error "~A requires :interval number" route))
    interval))

(defun %body-path (body route)
  "The path string BODY states for ROUTE."
  (let ((path (%body-get body :path)))
    (unless (stringp path)
      (error "~A requires :path string" route))
    path))

(defun %json-sequence (value)
  "A JSON array is a vector; a Lisp caller may pass a list. One item stays a list."
  (cond
    ((or (null value) (eq value :missing) (eq value :null)) nil)
    ((vectorp value) (coerce value 'list))
    ((listp value) value)
    (t (list value))))

(defun %body-sexps (body key)
  "The facts or goals BODY lists under KEY, each through JSON->SEXP."
  (mapcar #'json->sexp (%json-sequence (%body-get body key))))

;;; Vocabulary. JSON has no packages: JSON->SEXP reads every word into
;;; AUTOMA-GP. The facts a user typed at the REPL, or a domain installed,
;;; may live in another package, so a fact from JSON is rewritten onto the
;;; symbols the context already uses.

(defun %context-symbols ()
  "Symbols already used in the current facts and goals."
  (let ((bag nil))
    (dolist (fact (append (gp-facts) (gp-goals)))
      (when (consp fact)
        (dolist (term fact)
          (when (and (symbolp term) (not (keywordp term)))
            (push term bag)))))
    bag))

(defun %adopt-term (term symbols)
  "The member of SYMBOLS with the name of TERM, else TERM. Numbers,
strings and keywords stay."
  (if (and (symbolp term) (not (keywordp term)))
      (or (find (symbol-name term) symbols :key #'symbol-name :test #'string=)
          term)
      term))

(defun %vocabulary-package (term)
  "The package a new word joins because TERM is in it, or NIL.
TERM counts when the context supplied it from a package of its own: a
symbol that is not the one AUTOMA-GP reads under that name. A word such as
OPEN or FIRST is the COMMON-LISP symbol in every package that uses CL, so
it says nothing about where the other words of a fact belong. Nothing is
ever added to COMMON-LISP or to another locked package: a word such as
EXIT typed in COMMON-LISP-USER is the symbol of SB-EXT, which is not the
user's to extend."
  (let ((package (and (symbolp term) (symbol-package term))))
    (and package
         (not (keywordp term))
         (not (eq term (find-symbol (symbol-name term) :automa-gp)))
         (not (eq package (find-package :common-lisp)))
         (not (sb-ext:package-locked-p package))
         package)))

(defun %adopt-fact (fact)
  "Rewrite FACT onto the vocabulary already in the context.
JSON has no packages. A new word joins the package of the facts the
user is looking at, so a later edit matches them."
  (unless (consp fact)
    (return-from %adopt-fact fact))
  (let* ((symbols (%context-symbols))
         (adopted (mapcar (lambda (term) (%adopt-term term symbols)) fact))
         (home (some #'%vocabulary-package adopted)))
    (if (null home)
        adopted
        (mapcar (lambda (term)
                  (if (and (symbolp term)
                           (eq (symbol-package term) (find-package :automa-gp)))
                      (intern (symbol-name term) home)
                      term))
                adopted))))

(defun %live-fact (fact)
  "The stored fact whose names match FACT, or NIL."
  (find-fact-by-names fact (gp-facts)))

(defun %domain-designator (value)
  "The keyword of *KNOWN-DOMAINS* that VALUE names without regard to case,
else VALUE, so that GP-LOAD-DOMAIN says which domains exist. Nothing is
interned for a name no domain has."
  (unless (and value
               (not (eq value :null))
               (typep value '(or symbol string)))
    (error "load-domain requires :domain"))
  (or (car (assoc value *known-domains* :test #'string-equal))
      value))

;;; Autonomy policy

(defun %step-count (value)
  "VALUE, the max-steps of a request, as an integer of at least 1."
  (unless (realp value)
    (error "max-steps must be a number, not ~S." value))
  (max 1 (round value)))

(defun %policy-arguments (body)
  "The keyword arguments of GP-POLICY that BODY states.
A key BODY does not have is left out, so GP-POLICY keeps the session value
for it. The authority goes through as sent: MAKE-AUTONOMY-POLICY accepts a
string and interns nothing. A flag is read by %BODY-FLAG, so JSON null,
\"false\" and 0 never open a gate."
  (let ((arguments nil))
    (flet ((state (key value)
             (setf arguments (list* key value arguments))))
      (let ((authority (getf body :authority :missing))
            (max-steps (getf body :max-steps :missing)))
        (unless (eq authority :missing)
          (state :authority authority))
        (unless (eq max-steps :missing)
          (state :max-steps (%step-count max-steps))))
      (dolist (key '(:adapters :auto-confirm :react-events :learn
                     :prefer-archive))
        (unless (eq (getf body key :missing) :missing)
          (state key (%body-flag body key)))))
    arguments))

(defun %policy-for-request (body)
  "The policy one autonomy request runs under: the session policy with the
keys BODY states in place of its own, as (GP-POLICY ...) merges them at the
REPL. The session policy itself is not changed."
  (apply #'gp-policy :set nil (%policy-arguments body)))

;;; Plan gates

(defun %require-runnable-plan (verb gerund)
  "Signal unless the session plan may go to GP-SIMULATE or GP-RUN.
These are the gates GET /api/status reports, checked before the mode
changes: a plan, its success, and its external actions as
%PLAN-EXTERNAL-GATES reads them. VERB and GERUND name the route in the
message. The external refusals are the core's PLAN-REFUSED."
  (let ((plan *current-plan*)
        (context (ensure-current-context)))
    (unless (plan-p plan)
      (error "No plan to ~A; POST /api/plan first" verb))
    (unless (plan-success plan)
      (error "The plan did not succeed; plan again before ~A." gerund))
    (multiple-value-bind (matches supported)
        (%plan-external-gates plan context)
      (unless matches
        (error 'plan-refused :reason :external-mismatch :context context))
      (unless supported
        (error 'plan-refused :reason :external-unsupported :context context)))))

;;; ---------------------------------------------------------------------------
;;; Routes
;;; ---------------------------------------------------------------------------

(defvar *api-routes* (make-hash-table :test #'equal)
  "Path string → alist of (METHOD . FUNCTION), filled by DEFINE-API-ROUTE.
FUNCTION takes the request body plist and the query string.")

(defun %register-api-route (method path function)
  "Make FUNCTION the answer to METHOD on PATH. Returns PATH."
  (setf (gethash path *api-routes*)
        (acons method function
               (remove method (gethash path *api-routes*) :key #'car)))
  path)

(defmacro define-api-route (method path (&optional body query) &body forms)
  "Define what the API answers to METHOD (:GET or :POST) on PATH.
FORMS run with the variable named by BODY bound to the request body plist
and the one named by QUERY to the query string or NIL. They return the
response plist, which is answered 200, or two values: the plist and
another status code. An error they signal is answered by WEB-API-HANDLE."
  (let ((body (or body (gensym "BODY")))
        (query (or query (gensym "QUERY"))))
    `(%register-api-route ,method ,path
                          (lambda (,body ,query)
                            (declare (ignorable ,body ,query))
                            ,@forms))))

(defun %noticed-response (noticed &rest more)
  "The answer of a notice or watch route: what was NOTICED, then MORE, then
the facts and goals as they are now."
  (append (list :ok t :noticed (json-array noticed))
          more
          (list :facts (%facts-json) :goals (%goals-json))))

;;; Reading the session

(define-api-route :get "/api/status" ()
  (%api-status))

(define-api-route :get "/api/context" ()
  (%api-context))

(define-api-route :get "/api/facts" ()
  (list :facts (%facts-json)))

(define-api-route :get "/api/goals" ()
  (list :goals (%goals-json)))

(define-api-route :get "/api/operators" ()
  (list :operators (json-array (mapcar #'%serialize-operator (gp-operators)))))

(define-api-route :get "/api/rules" ()
  (list :rules (json-array (mapcar #'%serialize-rule (gp-rules)))))

(define-api-route :get "/api/events" ()
  (list :events (json-array (mapcar #'%serialize-event (gp-events)))))

(define-api-route :get "/api/reactions" ()
  (list :reactions (json-array (mapcar #'%serialize-reaction (gp-reactions)))))

(define-api-route :get "/api/plan" ()
  (list :plan (%serialize-plan (gp-last-plan))))

(define-api-route :get "/api/execution" ()
  (list :execution (%serialize-execution (gp-last-execution))))

(define-api-route :get "/api/explain" ()
  (%api-explain))

(define-api-route :get "/api/reaction" ()
  (list :reaction (%serialize-last-reaction *last-reaction*)))

(define-api-route :get "/api/autonomy" ()
  (%api-autonomy-status))

(define-api-route :get "/api/archive" (body query)
  (%archive-body :include-applies (or (%query-has-flag query "applies")
                                      (%body-flag body :applies))))

;;; Context, facts and goals

(define-api-route :post "/api/reset" ()
  (gp-reset)
  (list :ok t :context (%api-context)))

(define-api-route :post "/api/add-fact" (body)
  (let ((fact (%adopt-fact (json->sexp (%body-get body :fact)))))
    (unless (consp fact)
      (error "add-fact requires :fact array"))
    (gp-add-fact fact)
    (list :ok t :fact fact :facts (%facts-json))))

(define-api-route :post "/api/remove-fact" (body)
  (let* ((raw (json->sexp (%body-get body :fact)))
         (fact (%live-fact raw)))
    (unless (consp raw)
      (error "remove-fact requires :fact array"))
    (unless fact
      (error "No fact with those names is in the context."))
    (gp-remove-fact fact)
    (list :ok t :fact fact :facts (%facts-json))))

(define-api-route :post "/api/add-goal" (body)
  (let ((goal (%adopt-fact (json->sexp (%body-get body :goal)))))
    (unless goal
      (error "add-goal requires :goal"))
    (gp-add-goal goal)
    (list :ok t :goal goal :goals (%goals-json))))

(define-api-route :post "/api/load-domain" (body)
  (gp-load-domain (%domain-designator (%body-get body :domain))
                  :seed-demo (%body-flag body :seed-demo t))
  (list :ok t :domains (json-array (gp-domains)) :context (%api-context)))

;;; Noticing the computer

(define-api-route :post "/api/watch-directory" (body)
  (let ((path (%body-path body "watch-directory"))
        (interval (%body-interval body "watch-directory")))
    (%noticed-response (gp-watch-directory path :interval interval)
                       :path (gp-directory-watch))))

(define-api-route :post "/api/watch-directory/stop" ()
  (%noticed-response (gp-stop-directory-watch)))

(define-api-route :post "/api/watch-processes" (body)
  (%noticed-response
   (gp-watch-processes :interval (%body-interval body "watch-processes"))
   :watching (gp-process-watch)))

(define-api-route :post "/api/watch-processes/stop" ()
  (%noticed-response (gp-stop-process-watch)))

(define-api-route :post "/api/watch-terminals" (body)
  (%noticed-response
   (gp-watch-terminals :interval (%body-interval body "watch-terminals"))
   :watching (gp-terminal-watch)))

(define-api-route :post "/api/watch-terminals/stop" ()
  (%noticed-response (gp-stop-terminal-watch)))

(define-api-route :post "/api/watch-terminal-text" (body)
  (%noticed-response
   (gp-watch-terminal-text
    :interval (%body-interval body "watch-terminal-text"))
   :watching (gp-terminal-text-watch)))

(define-api-route :post "/api/watch-terminal-text/stop" ()
  (%noticed-response (gp-stop-terminal-text-watch)))

(define-api-route :post "/api/watch-terminal-screen" (body)
  (%noticed-response
   (gp-watch-terminal-screen
    :interval (%body-interval body "watch-terminal-screen"))
   :watching (gp-terminal-screen-watch)))

(define-api-route :post "/api/watch-terminal-screen/stop" ()
  (%noticed-response (gp-stop-terminal-screen-watch)))

(define-api-route :post "/api/notice-terminal-screen" ()
  (%noticed-response (gp-notice-terminal-screen) :listening (%listening-p)))

(define-api-route :post "/api/notice-terminal-text" ()
  (%noticed-response (gp-notice-terminal-text) :listening (%listening-p)))

(define-api-route :post "/api/notice-terminals" ()
  (%noticed-response (gp-notice-terminals) :listening (%listening-p)))

(define-api-route :post "/api/notice-processes" ()
  (%noticed-response (gp-notice-processes) :listening (%listening-p)))

(define-api-route :post "/api/notice-directory" (body)
  (%noticed-response (gp-notice-directory (%body-path body "notice-directory"))
                     :listening (%listening-p)))

(define-api-route :post "/api/notice-path" (body)
  (let ((fact (gp-notice-path (%body-path body "notice-path"))))
    (list :ok t
          :fact fact
          :listening (%listening-p)
          :facts (%facts-json))))

;;; Asking in words

(define-api-route :post "/api/ask" (body)
  (let ((phrase (%body-get body :phrase)))
    (unless (stringp phrase)
      (error "ask requires :phrase string"))
    (flet ((refused (condition &rest more)
             (values (list* :ok nil :error (princ-to-string condition) more)
                     400)))
      (handler-case
          (multiple-value-bind (goal plan) (gp-ask phrase)
            (list :ok t
                  :goal goal
                  :plan (%serialize-plan plan)
                  :listening (%listening-p)
                  :goals (%goals-json)))
        (ambiguous-goal (c)
          (refused c :goals (json-array (ambiguous-goal-goals c))))
        (unspecific-word (c)
          (refused c :goals (json-array (unspecific-word-goals c))))
        (unrelated-word (c)
          (refused c :goals (json-array (unrelated-word-goals c))))
        (not-that-name (c)
          (refused c :word (not-that-name-word c) :name (not-that-name-name c)))
        (undeclared-word (c)
          (refused c
                   :word (undeclared-word-word c)
                   :choices
                   (json-array
                    (mapcar (lambda (choice)
                              (list :kind (string-downcase
                                           (%kind-label (first choice)))
                                    :name (second choice)
                                    :goal (third choice)))
                            (undeclared-word-choices c)))))))))

(define-api-route :post "/api/operator/name" (body)
  (let* ((name (%body-required body :name "The operator needs a name."))
         (word (%body-required body :word "The operator needs one word."))
         (kind (%body-get body :kind))
         (named (gp-name-operator name
                                  (if (stringp word) word (string word))
                                  :kind kind)))
    (cond
      ((operator-p named)
       (list :ok t :operator (%serialize-operator named)))
      ((event-reaction-p named)
       (list :ok t
             :reaction (event-reaction-name named)
             :ask (json-array (getf (event-reaction-meta named) :ask))))
      ((rule-p named)
       (list :ok t
             :rule (rule-name named)
             :ask (json-array (getf (rule-meta named) :ask))))
      (t (list :ok t)))))

;;; Planning and running

(define-api-route :post "/api/plan-open-goals" ()
  (let ((plan (gp-plan-open-goals)))
    (list :ok t
          :plan (%serialize-plan plan)
          :facts (%facts-json)
          :goals (%goals-json))))

(define-api-route :post "/api/plan" (body)
  (let* ((goals (%body-sexps body :goals))
         (plan (if goals
                   (gp-plan :goals goals)
                   (gp-plan))))
    (list :ok t :plan (%serialize-plan plan))))

(define-api-route :post "/api/simulate" ()
  (%require-runnable-plan "simulate" "simulating")
  (list :ok t :execution (%serialize-execution (gp-simulate))))

;;; A body that does not say confirm is not a confirmation, as with GP-RUN:
;;; an irreversible or high-risk step is then not executed.
(define-api-route :post "/api/run" (body)
  (%require-runnable-plan "run" "running")
  (let ((execution (gp-run :confirm (%body-flag body :confirm)
                           :adapters (%body-flag body :adapters))))
    (list :ok t
          :execution (%serialize-execution execution)
          :facts (%facts-json))))

;;; Events

(define-api-route :post "/api/emit" (body)
  (let ((event (gp-emit (json->sexp (%body-get body :event))
                        :react (%body-flag body :react)
                        :plan (%body-flag body :plan))))
    (list :ok t
          :event (%serialize-event event)
          :reaction (%serialize-last-reaction *last-reaction*)
          :plan (%serialize-plan *current-plan*)
          :goals (%goals-json)
          :facts (%facts-json))))

(define-api-route :post "/api/react" (body)
  (let ((summary (gp-react :plan (%body-flag body :plan))))
    (list :ok t
          :reaction (%serialize-last-reaction summary)
          :plan (%serialize-plan *current-plan*)
          :goals (%goals-json))))

;;; Induction

(defun %induction-arguments (body)
  "What an induce route hands to GP-INDUCE-RULE or GP-LEARN-ACTION: the
name, then :BEFORE and :AFTER for the lists BODY states."
  (let ((name (%body-required body :name "induce requires :name")))
    (list* (if (stringp name) (json->sexp name) name)
           (loop for key in '(:before :after)
                 unless (eq (getf body key :missing) :missing)
                   append (list key (%body-sexps body key))))))

(define-api-route :post "/api/listen" (body)
  (gp-listen :missing (%body-sexps body :missing) :reason :manual)
  (list :ok t :listening t :facts (%facts-json)))

(define-api-route :post "/api/induce/rule" (body)
  (let ((operator (apply #'gp-induce-rule (%induction-arguments body))))
    (list :ok t
          :listening (%listening-p)
          :operator (%serialize-operator operator))))

(define-api-route :post "/api/induce/note" ()
  (gp-note-state)
  (list :ok t :facts (%facts-json)))

(define-api-route :post "/api/induce" (body)
  (let ((operator (apply #'gp-learn-action (%induction-arguments body))))
    (list :ok t :operator (%serialize-operator operator))))

;;; Procedure archive

(define-api-route :post "/api/archive/remember" (body)
  (let* ((name (json->sexp (%body-get body :name)))
         (procedure (if name
                        (gp-remember-procedure :name name)
                        (gp-remember-procedure))))
    (%archive-body :procedure procedure)))

(define-api-route :post "/api/archive/use" (body)
  (let* ((name (%body-get body :name :missing))
         (found (unless (eq name :missing)
                  (or (%find-archived-procedure name)
                      (error "No archived procedure named ~S." name))))
         (goals (%body-sexps body :goals))
         (unchecked (%body-flag body :unchecked))
         (plan (cond
                 (found (gp-use-procedure :name (procedure-name found)
                                          :unchecked unchecked))
                 (goals (gp-use-procedure :goals goals :unchecked unchecked))
                 (t (gp-use-procedure :unchecked unchecked)))))
    (list* :plan (%serialize-plan plan)
           (%archive-body :procedure found))))

(define-api-route :post "/api/archive/score" (body)
  (let* ((name (%body-required body :name "archive/score requires :name"))
         (found (%find-archived-procedure name)))
    (unless found
      (error "No archived procedure named ~S." name))
    (gp-score-procedure (procedure-name found)
                        :success (%body-flag body :success t))
    (%archive-body :procedure (find-procedure (procedure-name found)))))

;;; Autonomy

(defun %autonomy-response (summary)
  "The answer of an autonomous step or loop that ended with SUMMARY."
  (list :ok t
        :autonomy (%serialize-autonomy summary)
        :facts (%facts-json)
        :goals (%goals-json)
        :plan (%serialize-plan *current-plan*)))

(define-api-route :post "/api/autonomy/policy" (body)
  (apply #'gp-policy (%policy-arguments body))
  (%api-autonomy-status))

(define-api-route :post "/api/autonomy/step" (body)
  (%autonomy-response
   (gp-autonomous-step :policy (%policy-for-request body))))

(define-api-route :post "/api/autonomy/loop" (body)
  (%autonomy-response
   (gp-autonomous-loop :policy (%policy-for-request body))))

;;; ---------------------------------------------------------------------------
;;; Dispatch
;;; ---------------------------------------------------------------------------

(defun %abort-instead-of-asking (condition restart-names)
  "The *ASK-USER-FN* of a request: give the plan up.
A failure strategy of :ASK would otherwise read the answer from the
*QUERY-IO* of the server, where nobody is, and the request would never
return."
  (declare (ignore condition restart-names))
  :abort-execution)

(defun %failure (condition)
  "The response plist that reports CONDITION."
  (list :ok nil :error (princ-to-string condition)))

(defun %answer (function body query)
  "Call the route FUNCTION on BODY and QUERY.
Returns (VALUES STATUS-CODE RESPONSE-PLIST). An error is the refusal of a
gate or a body the route cannot use, and is answered 400 with its report.
An exhausted stack or heap is answered 500: the request is given up and
the image goes on.
A procedure archive file that cannot be read or written does not end the
request. The error comes with the SKIP restart, after which session memory
is coherent and the file is as it was; a request has nobody at a debugger
to choose it, and giving up instead would answer a refusal for a run or a
remembered procedure that did happen. So SKIP is taken, and the response
says what went wrong with the file under :ARCHIVE-ERROR."
  (let ((archive-errors nil))
    (flet ((skip-archive-file (condition)
             (let ((skip (find-restart :skip condition)))
               (when skip
                 (pushnew (princ-to-string condition) archive-errors
                          :test #'string=)
                 (invoke-restart skip))))
           (noting-archive (response)
             (if archive-errors
                 (append response
                         (list :archive-error
                               (format nil "~{~A~^ ~}"
                                       (reverse archive-errors))))
                 response)))
      (handler-case
          (with-session-lock ()
            (let ((*ask-user-fn* (or *ask-user-fn*
                                     #'%abort-instead-of-asking)))
              (multiple-value-bind (response status)
                  (handler-bind ((procedure-archive-error #'skip-archive-file))
                    (funcall function body query))
                (values (or status 200) (noting-archive response)))))
        (storage-condition (condition)
          (values 500 (noting-archive (%failure condition))))
        (error (condition)
          (values 400 (noting-archive (%failure condition))))))))

(defun web-api-handle (method path &optional body)
  "Dispatch METHOD (:GET/:POST) and PATH (string) with optional BODY plist
(from JSON). Returns (VALUES STATUS-CODE RESPONSE-PLIST).
STATUS-CODE is an integer; RESPONSE-PLIST is encoded by the HTTP layer.
PATH may include a query string (e.g. /api/archive?applies=1).
200 is an answer. 400 is a refusal, with :OK NIL and the reason in :ERROR:
a gate of the REPL function behind the route, or a body the route cannot
use. 404 is a path the API does not have and 405 a path it has for
another method, listed in :ALLOW. 500 is a request that exhausted the
stack or the heap. An answer with :ARCHIVE-ERROR was given while the
procedure archive file could not be read or written: the session went on
without the file, and the text says which file and why.
Requests are answered one at a time."
  (let ((method (if (stringp method)
                    (or (find method '(:get :post) :test #'string-equal)
                        method)
                    method)))
    (multiple-value-bind (path query)
        (%split-path-query (string path))
      (let* ((routes (gethash path *api-routes*))
             (route (cdr (assoc method routes))))
        (cond
          ((null routes)
           (values 404 (list :ok nil
                             :error "not-found"
                             :method method
                             :path path)))
          ((null route)
           (values 405 (list :ok nil
                             :error "method-not-allowed"
                             :method method
                             :path path
                             :allow (json-array (mapcar #'car routes)))))
          ((not (listp body))
           (values 400 (list :ok nil
                             :error "The request body must be a JSON object.")))
          (t (%answer route body query)))))))

(defun web-api-allowed-methods (path)
  "The methods the API answers on PATH, as upper-case strings, NIL for a
path it does not have. PATH may carry a query string. A 405 names them in
its Allow header."
  (mapcar (lambda (route) (symbol-name (car route)))
          (gethash (nth-value 0 (%split-path-query (string path)))
                   *api-routes*)))

(defun web-api-handle-json (method path &optional json-body)
  "Like WEB-API-HANDLE, with the body as JSON text and the answer as JSON
text. Returns (VALUES STATUS-CODE CONTENT-TYPE JSON-STRING).
A JSON-BODY that is NIL or only whitespace is no body. One that is not
JSON is answered 400 in the same envelope as any other refusal."
  (flet ((answer (code response)
           (values code "application/json; charset=utf-8"
                   (lisp->json response))))
    (handler-case
        (when (and json-body
                   (< (%skip-ws json-body 0) (length json-body)))
          (json->lisp json-body))
      (json-parse-error (condition)
        (answer 400 (list :ok nil
                          :error (format nil "The request body is not JSON: ~A"
                                         condition))))
      (:no-error (body)
        ;; The response is made of session objects, so it is written as
        ;; text before another request may change them.
        (with-session-lock ()
          (multiple-value-call #'answer
            (web-api-handle method path body)))))))
