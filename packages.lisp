;;;; packages.lisp — package definitions for AUTOMA GP

(defpackage #:automa-gp
  (:use #:cl)
  (:export
   ;; version
   #:*version*
   ;; modes
   #:*valid-modes*
   #:mode-p
   #:ensure-mode
   ;; matcher / bindings
   #:*fail*
   #:*no-bindings*
   #:fail-p
   #:variable-symbol-p
   #:anonymous-variable-p
   #:lookup-binding
   #:extend-bindings
   #:substitute-bindings
   #:match
   #:match-p
   #:match-all
   ;; unification
   #:occurs-check-p
   #:unify
   #:unify-p
   ;; facts
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
   #:context-rules
   #:context-operators
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
   #:context-all-rules
   #:context-all-operators
   #:context-planning-operators
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
   ;; rules
   #:rule
   #:rule-p
   #:rule-name
   #:rule-if
   #:rule-then
   #:rule-meta
   #:make-rule
   #:register-rule!
   #:remove-rule!
   #:rules-of
   #:rule-conclusions
   #:forward-chain
   #:*forward-chain-limit*
   ;; queries
   #:query
   #:query-facts
   #:query-bindings
   #:prove
   #:prove-all
   #:*query-depth-limit*
   ;; operators
   #:operator
   #:operator-p
   #:operator-name
   #:operator-parameters
   #:operator-preconditions
   #:operator-add-list
   #:operator-delete-list
   #:operator-cost
   #:operator-action
   #:operator-meta
   #:make-operator
   #:action->operator
   #:register-operator!
   #:remove-operator!
   #:operators-of
   #:operator-achieves
   #:operators-for-goal
   ;; MEA
   #:*plan-depth-limit*
   #:goal-holds-p
   #:differences
   #:apply-operator
   #:precondition-subgoals
   #:achieve
   #:achieve-all
   #:means-ends-analyze
   ;; planner
   #:plan
   #:plan-p
   #:plan-goals
   #:plan-steps
   #:plan-success
   #:plan-initial-state
   #:plan-final-state
   #:plan-remaining
   #:plan-operators-used
   #:plan-meta
   #:plan-for
   #:plan-from-context
   #:plan-length
   #:plan-cost
   #:normalize-planning-goals
   #:*current-plan*
   ;; session / REPL
   #:*current-context*
   #:gp-reset
   #:gp-context
   #:gp-state
   #:gp-facts
   #:gp-goals
   #:gp-actions
   #:gp-rules
   #:gp-operators
   #:gp-add-fact
   #:gp-remove-fact
   #:gp-add-goal
   #:gp-remove-goal
   #:gp-add-rule
   #:gp-remove-rule
   #:gp-add-operator
   #:gp-remove-operator
   #:gp-query
   #:gp-infer
   #:gp-plan
   #:gp-last-plan
   #:gp-mode
   #:gp-register-action
   ;; deferred Phase 4+
   #:gp-explain
   #:gp-run
   #:gp-simulate
   #:not-yet-implemented
   #:not-yet-implemented-error))
