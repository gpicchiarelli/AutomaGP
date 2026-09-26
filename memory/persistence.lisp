;;;; memory/persistence.lisp — persistence service (Phase 7)
;;;;
;;;; Separate from the planner. Save/restore contexts, facts, rules, goals,
;;;; operators, actions, episodic and procedural memory as readable sexps
;;;; via UIOP / ANSI CL file I/O.

(in-package #:automa-gp)

(defparameter *persistence-format-version* "0.7"
  "Snapshot format version written by SAVE-SNAPSHOT.")

(defparameter *default-snapshot-directory*
  (uiop:merge-pathnames* "snapshots/" (uiop:getcwd))
  "Default directory for named snapshots (relative to process cwd).")

;;; ---------------------------------------------------------------------------
;;; Serialization helpers (objects → readable plists)
;;; ---------------------------------------------------------------------------

(defun serialize-rule (rule)
  (list :rule
        :name (rule-name rule)
        :if (copy-tree (rule-if rule))
        :then (copy-tree (rule-then rule))
        :meta (copy-tree (rule-meta rule))))

(defun deserialize-rule (form)
  (destructuring-bind (&key name if then meta &allow-other-keys) (cdr form)
    (make-rule :name name :if if :then then :meta meta)))

(defun serialize-operator (op)
  (list :operator
        :name (operator-name op)
        :parameters (copy-list (operator-parameters op))
        :preconditions (copy-tree (operator-preconditions op))
        :add-list (copy-tree (operator-add-list op))
        :delete-list (copy-tree (operator-delete-list op))
        :cost (operator-cost op)
        :action (operator-action op)
        :reversible (operator-reversible op)
        :risk (operator-risk op)
        :meta (copy-tree (operator-meta op))))

(defun deserialize-operator (form)
  (destructuring-bind (&key name parameters preconditions add-list delete-list
                         (cost 1) action (reversible t) (risk :low) meta
                         &allow-other-keys)
      (cdr form)
    (make-operator :name name
                   :parameters parameters
                   :preconditions preconditions
                   :add-list add-list
                   :delete-list delete-list
                   :cost cost
                   :action action
                   :reversible reversible
                   :risk risk
                   :meta meta)))

(defun serialize-action (action)
  (list :action
        :name (action-name action)
        :parameters (copy-list (action-parameters action))
        :preconditions (copy-tree (action-preconditions action))
        :effects (copy-tree (action-effects action))
        :cost (action-cost action)
        :risk (action-risk action)
        :reversible (action-reversible action)
        :adapter (action-adapter action)
        :authorization (action-authorization action)))

(defun deserialize-action (form)
  (destructuring-bind (&key name parameters preconditions effects
                         (cost 1) (risk :low) (reversible t)
                         adapter authorization
                         &allow-other-keys)
      (cdr form)
    (make-action :name name
                 :parameters parameters
                 :preconditions preconditions
                 :effects effects
                 :cost cost
                 :risk risk
                 :reversible reversible
                 :adapter adapter
                 :authorization authorization)))

(defun serialize-event (event)
  (list :event
        :id (event-id event)
        :type (event-type event)
        :data (copy-list (event-data event))
        :timestamp (event-timestamp event)
        :status (event-status event)
        :meta (copy-tree (event-meta event))))

(defun deserialize-event (form)
  (destructuring-bind (&key id type data timestamp status meta
                         &allow-other-keys)
      (cdr form)
    (make-event :id id
                :type type
                :data data
                :timestamp timestamp
                :status (or status :pending)
                :meta meta)))

(defun serialize-event-reaction (reaction)
  (list :event-reaction
        :name (event-reaction-name reaction)
        :when (copy-tree (event-reaction-when reaction))
        :assert (copy-tree (event-reaction-assert reaction))
        :goals (copy-tree (event-reaction-goals reaction))
        :meta (copy-tree (event-reaction-meta reaction))))

(defun deserialize-event-reaction (form)
  (destructuring-bind (&key name when assert goals meta &allow-other-keys)
      (cdr form)
    (make-event-reaction :name name
                         :when when
                         :assert assert
                         :goals goals
                         :meta meta)))

(defun serialize-context (context)
  "Serialize CONTEXT (local slots only — no parent/children links)."
  (list :context
        :name (context-name context)
        :facts (copy-list (context-facts context))
        :goals (copy-list (context-goals context))
        :rules (mapcar #'serialize-rule (context-rules context))
        :operators (mapcar #'serialize-operator (context-operators context))
        :actions (mapcar (lambda (pair)
                           (serialize-action (cdr pair)))
                         (context-actions context))
        :events (mapcar #'serialize-event (context-events context))
        :event-reactions (mapcar #'serialize-event-reaction
                                 (context-event-reactions context))
        :mode (context-mode context)
        :meta (copy-tree (context-meta context))))

(defun deserialize-context (form)
  (destructuring-bind (&key name facts goals rules operators actions
                         events event-reactions mode meta
                         &allow-other-keys)
      (cdr form)
    (let ((ctx (make-context :name name
                             :facts facts
                             :goals goals
                             :mode (or mode :read)
                             :meta meta)))
      (dolist (r rules)
        (register-rule! ctx (deserialize-rule r)))
      (dolist (o operators)
        (register-operator! ctx (deserialize-operator o)))
      (dolist (a actions)
        (register-action! ctx (deserialize-action a)))
      (dolist (e events)
        (setf (context-events ctx)
              (append (context-events ctx)
                      (list (deserialize-event e)))))
      (dolist (er event-reactions)
        (register-event-reaction! ctx (deserialize-event-reaction er)))
      ctx)))

(defun serialize-episode (ep)
  (list :episode
        :id (episode-id ep)
        :kind (episode-kind ep)
        :context-name (episode-context-name ep)
        :summary (copy-tree (episode-summary ep))
        :success (episode-success ep)
        :payload (copy-tree (episode-payload ep))
        :timestamp (episode-timestamp ep)))

(defun deserialize-episode (form)
  (destructuring-bind (&key id kind context-name summary success payload
                         timestamp &allow-other-keys)
      (cdr form)
    (make-instance 'episode
                   :id (or id (gentemp "EP-"))
                   :kind (or kind :event)
                   :context-name context-name
                   :summary summary
                   :success success
                   :payload payload
                   :timestamp (or timestamp (get-universal-time)))))

(defun serialize-procedure (proc)
  (list :procedure
        :name (procedure-name proc)
        :goals (copy-list (procedure-goals proc))
        :steps (copy-tree (procedure-steps proc))
        :operators-used (copy-list (procedure-operators-used proc))
        :initial-state (copy-list (procedure-initial-state proc))
        :success-count (procedure-success-count proc)
        :meta (copy-tree (procedure-meta proc))))

(defun deserialize-procedure (form)
  (destructuring-bind (&key name goals steps operators-used initial-state
                         success-count meta &allow-other-keys)
      (cdr form)
    (make-procedure :name name
                    :goals goals
                    :steps steps
                    :operators-used operators-used
                    :initial-state initial-state
                    :success-count (or success-count 1)
                    :meta meta)))

(defun serialize-knowledge-memory (km)
  (list :knowledge
        :name (knowledge-memory-name km)
        :facts (copy-list (knowledge-memory-facts km))
        :rules (mapcar #'serialize-rule (knowledge-memory-rules km))
        :meta (copy-tree (knowledge-memory-meta km))))

(defun deserialize-knowledge-memory (form)
  (destructuring-bind (&key name facts rules meta &allow-other-keys) (cdr form)
    (make-knowledge-memory
     :name (or name 'default)
     :facts facts
     :rules (mapcar #'deserialize-rule rules)
     :meta meta)))

(defun serialize-episodic-memory (em)
  (list :episodic
        :limit (episodic-memory-limit em)
        :episodes (mapcar #'serialize-episode
                          (episodic-memory-episodes em))))

(defun deserialize-episodic-memory (form)
  (destructuring-bind (&key limit episodes &allow-other-keys) (cdr form)
    (make-episodic-memory
     :limit (or limit *episodic-memory-limit*)
     :episodes (mapcar #'deserialize-episode episodes))))

(defun serialize-procedural-memory (pm)
  (list :procedural
        :procedures (mapcar #'serialize-procedure
                            (procedural-memory-procedures pm))
        :meta (copy-tree (procedural-memory-meta pm))))

(defun deserialize-procedural-memory (form)
  (destructuring-bind (&key procedures meta &allow-other-keys) (cdr form)
    (make-procedural-memory
     :procedures (mapcar #'deserialize-procedure procedures)
     :meta meta)))

;;; ---------------------------------------------------------------------------
;;; Suspend / restore (in-memory or file)
;;; ---------------------------------------------------------------------------

(defun suspend-context (context)
  "Return a serializable plist for CONTEXT (does not write a file)."
  (serialize-context context))

(defun resume-context (form)
  "Rebuild a CONTEXT from a suspend/serialize form."
  (unless (and (consp form) (eq (car form) :context))
    (error "resume-context expects a (:CONTEXT ...) form, got ~S" (car form)))
  (deserialize-context form))

;;; ---------------------------------------------------------------------------
;;; File path helpers
;;; ---------------------------------------------------------------------------

(defun ensure-snapshot-path (path &key (ensure-directory t))
  "Resolve PATH to an absolute pathname. If PATH has no type, use .agp."
  (let* ((p (uiop:ensure-pathname path :want-pathname t))
         (p (if (pathname-type p)
                p
                (make-pathname :defaults p :type "agp"))))
    (when ensure-directory
      (ensure-directories-exist (uiop:pathname-directory-pathname p)))
    (uiop:ensure-pathname p :want-pathname t)))

(defun write-sexp-file (path form)
  "Write FORM readably to PATH. Returns PATH."
  (let ((p (ensure-snapshot-path path)))
    (with-open-file (out p :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
      (let ((*package* (find-package :automa-gp))
            (*print-pretty* t)
            (*print-readably* t)
            (*print-circle* t))
        (prin1 form out)
        (terpri out)))
    p))

(defun read-sexp-file (path)
  "Read one sexp from PATH."
  (let ((p (ensure-snapshot-path path :ensure-directory nil)))
    (with-open-file (in p :direction :input)
      (let ((*package* (find-package :automa-gp)))
        (read in)))))

;;; ---------------------------------------------------------------------------
;;; Snapshot bundle
;;; ---------------------------------------------------------------------------

(defun make-snapshot (&key context knowledge episodic procedural
                        (meta nil))
  "Build a snapshot plist from live objects (NIL slots omitted as NIL)."
  (list :snapshot
        :format-version *persistence-format-version*
        :saved-at (get-universal-time)
        :meta (copy-tree meta)
        :context (when (context-p context) (serialize-context context))
        :knowledge (when (knowledge-memory-p knowledge)
                     (serialize-knowledge-memory knowledge))
        :episodic (when (episodic-memory-p episodic)
                    (serialize-episodic-memory episodic))
        :procedural (when (procedural-memory-p procedural)
                      (serialize-procedural-memory procedural))))

(defun save-snapshot (path &key context knowledge episodic procedural meta)
  "Persist a snapshot bundle to PATH. Returns the pathname."
  (write-sexp-file
   path
   (make-snapshot :context context
                  :knowledge knowledge
                  :episodic episodic
                  :procedural procedural
                  :meta meta)))

(defun load-snapshot (path)
  "Load a snapshot from PATH.
Returns a plist:
  :CONTEXT :KNOWLEDGE :EPISODIC :PROCEDURAL :FORMAT-VERSION :META :SAVED-AT
Objects are reconstituted; missing sections are NIL."
  (let ((form (read-sexp-file path)))
    (unless (and (consp form) (eq (car form) :snapshot))
      (error "load-snapshot: expected :SNAPSHOT form in ~A" path))
    (destructuring-bind (&key format-version saved-at meta context knowledge
                           episodic procedural &allow-other-keys)
        (cdr form)
      (list :format-version format-version
            :saved-at saved-at
            :meta meta
            :context (when context (deserialize-context context))
            :knowledge (when knowledge (deserialize-knowledge-memory knowledge))
            :episodic (when episodic (deserialize-episodic-memory episodic))
            :procedural (when procedural
                          (deserialize-procedural-memory procedural))))))

(defun persist-context (context path)
  "Save CONTEXT alone to PATH. Returns pathname."
  (write-sexp-file path (serialize-context context)))

(defun restore-context (path)
  "Load a CONTEXT from PATH (a :CONTEXT file or a :SNAPSHOT with :CONTEXT)."
  (let ((form (read-sexp-file path)))
    (cond
      ((and (consp form) (eq (car form) :context))
       (deserialize-context form))
      ((and (consp form) (eq (car form) :snapshot))
       (let ((bundle (load-snapshot path)))
         (or (getf bundle :context)
             (error "restore-context: snapshot in ~A has no context" path))))
      (t (error "restore-context: unrecognized form ~S" (car form))))))

(defun apply-snapshot! (bundle &key (set-current t)
                          (set-knowledge t)
                          (set-episodic t)
                          (set-procedural t))
  "Install loaded BUNDLE into session variables. Returns BUNDLE."
  (when (and set-current (getf bundle :context))
    (setf *current-context* (getf bundle :context))
    (refresh-working-memory *current-context*))
  (when (and set-knowledge (getf bundle :knowledge))
    (setf *knowledge-memory* (getf bundle :knowledge)))
  (when (and set-episodic (getf bundle :episodic))
    (setf *episodic-memory* (getf bundle :episodic)))
  (when (and set-procedural (getf bundle :procedural))
    (setf *procedural-memory* (getf bundle :procedural)))
  bundle)
