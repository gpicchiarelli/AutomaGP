;;;; domains/geometry/domain.lisp — points, segments, shapes (Phase 9)

(in-package #:automa-gp/domain/geometry)

(defparameter *geometry-domain-name* :geometry)

(defun %tag-domains (context name)
  (let ((meta (copy-list (context-meta context))))
    (setf (getf meta :domains)
          (adjoin name (getf meta :domains) :test #'equal))
    (setf (context-meta context) meta)))

(defun %geometry-operators ()
  (list
   (make-operator
    :name 'automa-gp::define-point
    :preconditions '((automa-gp::canvas automa-gp::ready)
                     (automa-gp::point-id ?id))
    :add-list '((automa-gp::point ?id automa-gp::defined))
    :meta (list :domain *geometry-domain-name*))
   (make-operator
    :name 'automa-gp::make-segment
    :preconditions '((automa-gp::point ?a automa-gp::defined)
                     (automa-gp::point ?b automa-gp::defined)
                     (automa-gp::segment-request ?a ?b))
    :add-list '((automa-gp::segment ?a ?b))
    :meta (list :domain *geometry-domain-name*))
   (make-operator
    :name 'automa-gp::close-triangle
    :preconditions '((automa-gp::segment ?a ?b)
                     (automa-gp::segment ?b ?c)
                     (automa-gp::segment ?c ?a))
    :add-list '((automa-gp::triangle ?a ?b ?c))
    :meta (list :domain *geometry-domain-name*))))

(defun %geometry-rules ()
  (list
   (make-rule :name 'automa-gp::shape-ready
              :if '((automa-gp::triangle ?a ?b ?c))
              :then '(automa-gp::shape-constructed automa-gp::triangle)
              :meta (list :domain *geometry-domain-name*))))

(defun install-geometry-domain (&optional (context *current-context*)
                                 &key (seed-demo t) &allow-other-keys)
  "Install geometry-domain operators/rules into CONTEXT."
  (unless (context-p context)
    (error "install-geometry-domain requires a context"))
  (dolist (op (%geometry-operators))
    (register-operator! context op))
  (dolist (r (%geometry-rules))
    (register-rule! context r))
  (when seed-demo
    (unless (fact-p '(automa-gp::canvas automa-gp::ready)
                    (context-all-facts context))
      (setf (context-facts context)
            (add-fact! (context-facts context)
                       '(automa-gp::canvas automa-gp::ready)))))
  (%tag-domains context *geometry-domain-name*)
  context)

(defun geometry-demo-plan (&optional (context *current-context*))
  "Seed three points and segment requests; plan for a triangle."
  (install-geometry-domain context :seed-demo t)
  (dolist (f '((automa-gp::point-id automa-gp::a)
               (automa-gp::point-id automa-gp::b)
               (automa-gp::point-id automa-gp::c)
               (automa-gp::segment-request automa-gp::a automa-gp::b)
               (automa-gp::segment-request automa-gp::b automa-gp::c)
               (automa-gp::segment-request automa-gp::c automa-gp::a)))
    (setf (context-facts context)
          (add-fact! (context-facts context) f)))
  (plan-from-context context
                     :goals '((automa-gp::triangle automa-gp::a
                               automa-gp::b automa-gp::c))))
