;;;; packages.lisp — package definitions for AUTOMA GP (Phase 1)

(defpackage #:automa-gp
  (:use #:cl)
  (:export
   ;; version
   #:*version*
   ;; modes
   #:*valid-modes*
   #:mode-p
   #:ensure-mode
   ;; facts
   #:variable-symbol-p
   #:fact-equal
   #:fact-matches-p
   #:fact-p
   #:find-facts
   #:add-fact!
   #:remove-fact!
   #:facts-of
   ;; context
   #:context
   #:context-p
   #:context-name
   #:context-parent
   #:context-children
   #:context-facts
   #:context-goals
   #:context-actions
   #:context-mode
   #:context-meta
   #:make-context
   #:create-context
   #:context-add-child!
   #:context-query
   #:context-modify!
   #:clone-context
   #:compare-contexts
   #:context-all-facts
   ;; state
   #:state
   #:state-p
   #:state-facts
   #:state-from-context
   #:state-equal
   #:compare-states
   ;; goals
   #:add-goal!
   #:remove-goal!
   #:goals-of
   #:goal-active-p
   ;; actions
   #:action
   #:action-p
   #:action-name
   #:action-parameters
   #:action-preconditions
   #:action-effects
   #:action-cost
   #:action-risk
   #:action-reversible
   #:action-adapter
   #:action-authorization
   #:make-action
   #:register-action!
   #:find-action
   #:actions-of
   #:action-applicable-p
   ;; session / REPL
   #:*current-context*
   #:gp-reset
   #:gp-context
   #:gp-state
   #:gp-facts
   #:gp-goals
   #:gp-actions
   #:gp-add-fact
   #:gp-remove-fact
   #:gp-add-goal
   #:gp-remove-goal
   #:gp-mode
   #:gp-register-action
   ;; deferred Phase 2+ (honest signals)
   #:gp-rules
   #:gp-query
   #:gp-plan
   #:gp-explain
   #:gp-run
   #:gp-simulate
   #:not-yet-implemented
   #:not-yet-implemented-error))
