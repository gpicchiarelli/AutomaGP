# Architecture (Phases 1–5)

AUTOMA GP keeps OS/domain details out of the symbolic core. Failures use the
Common Lisp **condition system** with established **restarts**, not bare
catch-all handlers.

```text
interface/     REPL
    ↓
core/          … planner → conditions → executor
```

## Modes

`READ` → `PLAN` → `SIMULATE` → `EXECUTE` (symbolic facts through Phase 5;
adapters arrive in Phase 8).

## Conditions & restarts (Phase 5)

| Condition | Typical cause |
|-----------|----------------|
| `precondition-failure` | Operator preconditions not held |
| `confirmation-required` | Irreversible / high-risk execute |
| `unknown-operator` | Plan step names a missing operator |
| `action-failed` | General step failure |

| Restart | Effect |
|---------|--------|
| `:retry` | Re-enter the step |
| `:skip` | Skip step; continue plan |
| `:abort-execution` | Stop the plan |
| `:use-value` | Supply replacement fact list |
| `:use-alternative` | Retry with another operator |
| `:ask-user` | Choose among the above (`*ask-user-fn*`) |
| `:confirm` | Proceed past confirmation-required |

### Deliberative strategy

`*deliberative-strategy*` / `with-failure-strategy` / `gp-failure-strategy`
select automatic policy: `:signal` (default for interactive), `:skip`,
`:retry`, `:abort`, `:ask`. Plan runners bind a handler that applies the
strategy, then defaults to `:abort-execution` when `*plan-runner-default-abort*`
is true — so batch simulate/run still completes with a result object.

Strategy events are recorded and copied onto `execution-result`.

## State transition & executor

Unchanged from Phase 4: symbolic `transition-facts`; simulate does not mutate
live context; execute updates context facts only.

## Dependency policy

ANSI CL + ASDF + UIOP. Tests: FiveAM.
