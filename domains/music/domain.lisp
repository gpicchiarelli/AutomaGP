;;;; domains/music/domain.lisp — instruments, MIDI routing, sessions (Phase 9)

(in-package #:automa-gp/domain/music)

(defparameter *music-domain-name* :music)

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
  "Install music-domain operators/rules into CONTEXT. Returns CONTEXT.
When SEED-DEMO, assert (daw ready) if missing."
  (install-domain-pack
   context *music-domain-name*
   :operators (%music-operators)
   :rules (%music-rules)
   :facts (when seed-demo
            '((automa-gp::daw automa-gp::ready)))))

(defun music-demo-plan (context &key (interface 'automa-gp::scarlett-2i2)
                           (destination 'automa-gp::logic-pro))
  "Seed interface/MIDI facts and plan for (session-ready INTERFACE)."
  (install-music-domain context :seed-demo t)
  (dolist (fact (list (list 'automa-gp::audio-interface interface)
                      (list 'automa-gp::power-state interface 'automa-gp::off)
                      (list 'automa-gp::midi-destination destination)))
    (context-add-fact! context fact))
  (plan-from-context context
                     :goals (list (list 'automa-gp::session-ready interface))))
