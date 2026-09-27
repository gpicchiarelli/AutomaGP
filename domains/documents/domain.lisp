;;;; domains/documents/domain.lisp — ingest → classify → archive (Phase 9)
;;;;
;;;; Aligns with the Dynamic Context Pipeline (Acquisition→Analysis→Output).
;;;; Optional archive step can write a marker file via filesystem adapter.

(in-package #:automa-gp/domain/documents)

(defparameter *documents-domain-name* :documents)

(defun %tag-domains (context name)
  (let ((meta (copy-list (context-meta context))))
    (setf (getf meta :domains)
          (adjoin name (getf meta :domains) :test #'equal))
    (setf (context-meta context) meta)))

(defun %documents-operators (&key archive-path)
  (list
   (make-operator
    :name 'automa-gp::ingest-document
    :preconditions '((automa-gp::document-reader automa-gp::ready)
                     (automa-gp::document-source ?s))
    :add-list '((automa-gp::document-loaded ?s))
    :meta (list :domain *documents-domain-name* :phase :acquire))
   (make-operator
    :name 'automa-gp::classify-document
    :preconditions '((automa-gp::document-loaded ?s)
                     (automa-gp::classification-target ?class))
    :add-list '((automa-gp::document-classified ?s ?class))
    :meta (list :domain *documents-domain-name* :phase :analyze))
   (make-operator
    :name 'automa-gp::archive-document
    :preconditions '((automa-gp::document-classified ?s ?class)
                     (automa-gp::archive automa-gp::ready))
    :add-list '((automa-gp::document-archived ?s))
    :meta (list* :domain *documents-domain-name*
                 :phase :output
                 (when archive-path
                   (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path archive-path
                                           :content "archived"
                                           :if-exists :supersede))))))))

(defun %documents-rules ()
  (list
   (make-rule :name 'automa-gp::document-workflow-complete
              :if '((automa-gp::document-archived ?s))
              :then '(automa-gp::document-workflow-complete ?s)
              :meta (list :domain *documents-domain-name*))))

(defun %documents-event-reactions ()
  "Phase 10: file-created → seed source/class → goal document-classified."
  (list
   (make-event-reaction
    :name 'automa-gp::on-file-created
    :when '(automa-gp::file-created ?path)
    :assert '((automa-gp::document-source ?path)
              (automa-gp::classification-target automa-gp::report))
    :goals '((automa-gp::document-classified ?path automa-gp::report))
    :meta (list :domain *documents-domain-name*
                :prompt-example t))))

(defun install-documents-domain (context &key (seed-demo t) archive-path
                                 &allow-other-keys)
  "Install documents-domain pack into CONTEXT. Returns CONTEXT."
  (unless (context-p context)
    (error "install-documents-domain requires a context"))
  (dolist (op (%documents-operators :archive-path archive-path))
    (register-operator! context op))
  (dolist (r (%documents-rules))
    (register-rule! context r))
  (dolist (er (%documents-event-reactions))
    (register-event-reaction! context er))
  (when seed-demo
    (dolist (f '((automa-gp::document-reader automa-gp::ready)
                 (automa-gp::archive automa-gp::ready)))
      (unless (fact-p f (context-all-facts context))
        (setf (context-facts context)
              (add-fact! (context-facts context) f)))))
  (%tag-domains context *documents-domain-name*)
  context)

(defun documents-demo-plan (context &key (source "note.txt")
                              (class 'automa-gp::memo)
                              archive-path)
  "Seed source/class facts and plan for (document-archived SOURCE)."
  (install-documents-domain context :seed-demo t :archive-path archive-path)
  (setf (context-facts context)
        (add-fact! (context-facts context)
                   (list 'automa-gp::document-source source)))
  (setf (context-facts context)
        (add-fact! (context-facts context)
                   (list 'automa-gp::classification-target class)))
  (plan-from-context context
                     :goals (list (list 'automa-gp::document-archived source))))
