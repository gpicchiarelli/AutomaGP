;;;; domains/registry.lisp — load domain packs into the current context (Phase 9)

(in-package #:automa-gp)

(defparameter *known-domains*
  '((:software . automa-gp/domain/software:install-software-domain)
    (:documents . automa-gp/domain/documents:install-documents-domain)
    (:hardware . automa-gp/domain/hardware:install-hardware-domain)
    (:music . automa-gp/domain/music:install-music-domain)
    (:geometry . automa-gp/domain/geometry:install-geometry-domain))
  "Alist of domain keyword → install function designator.")

(defun %plist-without (plist &rest keys)
  (loop for (k v) on plist by #'cddr
        unless (member k keys :test #'eq)
          collect k and collect v))

(defun gp-load-domain (domain &rest keys &key (context nil context-p)
                      &allow-other-keys)
  "Install DOMAIN (:SOFTWARE :DOCUMENTS :HARDWARE :MUSIC :GEOMETRY).
Keyword args (e.g. :SEED-DEMO :ARCHIVE-PATH) go to the installer.
:CONTEXT selects the target context (default: current). Returns the context."
  (declare (ignore context))
  (let* ((ctx (if context-p
                  (getf keys :context)
                  (ensure-current-context)))
         (entry (assoc domain *known-domains* :test #'eq))
         (args (%plist-without keys :context)))
    (unless entry
      (error "Unknown domain ~S; expected one of ~S"
             domain (mapcar #'car *known-domains*)))
    (apply (fdefinition (cdr entry)) ctx args)
    (refresh-working-memory ctx)
    ctx))

(defun gp-domains ()
  "Return domain keywords currently tagged on the current context meta."
  (copy-list (getf (context-meta (ensure-current-context)) :domains)))
