;;;; domains/music/domain.lisp — instruments, MIDI routing, sessions (Phase 9)

(in-package #:automa-gp/domain/music)

(defparameter *music-domain-name* :music)

(defun %tag-domains (context name)
  (let ((meta (copy-list (context-meta context))))
    (setf (getf meta :domains)
          (adjoin name (getf meta :domains) :test #'equal))
    (setf (context-meta context) meta)))

(defun %music-operators ()
  (list
   (make-operator
    :name 'automa-gp::power-audio-interface
    :preconditions '((automa-gp::audio-interface ?i)
                     (automa-gp::power-state ?i automa-gp::off))
    :add-list '((automa-gp::power-state ?i automa-gp::on))
    :delete-list '((automa-gp::power-state ?i automa-gp::off))
    :meta (list :domain *music-domain-name*))
   (make-operator
    :name 'automa-gp::route-midi
    :preconditions '((automa-gp::audio-interface ?i)
                     (automa-gp::power-state ?i automa-gp::on)
                     (automa-gp::midi-destination ?dest))
    :add-list '((automa-gp::midi-routed ?i ?dest))
    :meta (list :domain *music-domain-name*))
   (make-operator
    :name 'automa-gp::open-music-session
    :preconditions '((automa-gp::midi-routed ?i ?dest)
                     (automa-gp::daw automa-gp::ready))
    :add-list '((automa-gp::session-ready ?i))
    :meta (list :domain *music-domain-name*))))

(defun %music-rules ()
  (list
   (make-rule :name 'automa-gp::studio-live
              :if '((automa-gp::session-ready ?i))
              :then '(automa-gp::studio-session-live ?i)
              :meta (list :domain *music-domain-name*))))

(defun install-music-domain (context &key (seed-demo t) &allow-other-keys)
  "Install music-domain operators/rules into CONTEXT."
  (unless (context-p context)
    (error "install-music-domain requires a context"))
  (dolist (op (%music-operators))
    (register-operator! context op))
  (dolist (r (%music-rules))
    (register-rule! context r))
  (when seed-demo
    (dolist (f '((automa-gp::daw automa-gp::ready)))
      (unless (fact-p f (context-all-facts context))
        (setf (context-facts context)
              (add-fact! (context-facts context) f)))))
  (%tag-domains context *music-domain-name*)
  context)

(defun music-demo-plan (context &key (interface 'automa-gp::scarlett-2i2)
                           (destination 'automa-gp::logic-pro))
  "Seed interface/MIDI facts and plan for (session-ready INTERFACE)."
  (install-music-domain context :seed-demo t)
  (setf (context-facts context)
        (add-fact! (context-facts context)
                   (list 'automa-gp::audio-interface interface)))
  (setf (context-facts context)
        (add-fact! (context-facts context)
                   (list 'automa-gp::power-state interface 'automa-gp::off)))
  (setf (context-facts context)
        (add-fact! (context-facts context)
                   (list 'automa-gp::midi-destination destination)))
  (plan-from-context context
                     :goals (list (list 'automa-gp::session-ready interface))))
