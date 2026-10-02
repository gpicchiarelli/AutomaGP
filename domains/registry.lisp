;;;; domains/registry.lisp — load domain packs into the current context (Phase 9)

(in-package #:automa-gp)

(defparameter *known-domains*
  '((:software . automa-gp/domain/software:install-software-domain)
    (:documents . automa-gp/domain/documents:install-documents-domain)
    (:hardware . automa-gp/domain/hardware:install-hardware-domain)
    (:music . automa-gp/domain/music:install-music-domain)
    (:geometry . automa-gp/domain/geometry:install-geometry-domain))
  "Alist of domain keyword → install function designator.")

(defun install-domain-pack (context name &key operators rules actions
                                           event-reactions facts)
  "Install the parts of the domain pack NAME into CONTEXT. Returns CONTEXT.
OPERATORS, RULES, ACTIONS and EVENT-REACTIONS are registered under their
names, so installing a pack again replaces its parts and adds nothing.
Each fact of FACTS is asserted unless it is already visible in CONTEXT.
NAME, a keyword, is added to the :DOMAINS of the context meta once.
The five packs of domains/ are installed through this function; a pack
of your own can be too. Signals a TYPE-ERROR, with a STORE-VALUE restart,
when CONTEXT is not a context."
  (check-type context context "a context")
  (dolist (operator operators)
    (register-operator! context operator))
  (dolist (rule rules)
    (register-rule! context rule))
  (dolist (action actions)
    (register-action! context action))
  (dolist (reaction event-reactions)
    (register-event-reaction! context reaction))
  (dolist (fact facts)
    (unless (fact-p fact (context-all-facts context))
      (context-add-fact! context fact)))
  (let ((meta (copy-list (context-meta context))))
    (setf (getf meta :domains) (adjoin name (getf meta :domains)))
    (setf (context-meta context) meta))
  context)

(defun gp-load-domain (domain &rest keys &key (context nil context-p)
                      &allow-other-keys)
  "Install DOMAIN (:SOFTWARE :DOCUMENTS :HARDWARE :MUSIC :GEOMETRY).
Keyword args (e.g. :SEED-DEMO :ARCHIVE-PATH) go to the installer.
:CONTEXT selects the target context (default: current). Returns the context.
The working-memory snapshot is refreshed only when the target is the
session context: it describes the session, not any context a pack went to."
  (let ((ctx (if context-p context (ensure-current-context)))
        (entry (assoc domain *known-domains* :test #'eq)))
    (unless entry
      (error "Unknown domain ~S; expected one of ~S"
             domain (mapcar #'car *known-domains*)))
    (apply (fdefinition (cdr entry)) ctx
           (uiop:remove-plist-key :context keys))
    (when (eq ctx *current-context*)
      (refresh-working-memory ctx))
    ctx))

(defun gp-domains ()
  "Return domain keywords currently tagged on the current context meta."
  (copy-list (getf (context-meta (ensure-current-context)) :domains)))
