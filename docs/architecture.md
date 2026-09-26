# Architecture (Phases 1–6)

AUTOMA GP keeps OS/domain details out of the symbolic core. Failures use the
Common Lisp **condition system** with established **restarts**. Significant
decisions are recorded into a **deliberative trace** as they happen.

```text
interface/     REPL (incl. gp-explain)
    ↓
core/          operators → explanation → mea → planner → conditions → executor
```

## Modes

`READ` → `PLAN` → `SIMULATE` → `EXECUTE` (symbolic facts through Phase 6;
adapters arrive in Phase 8).

## Deliberative trace (Phase 6)

`with-trace` / `trace-record` append event plists (`:context`, `:goals`,
`:state`, `:difference`, `:selected-operator`, `:subgoal`, `:precondition`,
`:action`, `:result`, `:execution-step`, …) to an open `deliberative-trace`.

- `plan-for` / `plan-from-context` attach `:trace` on `plan-meta`.
- `simulate-plan` / `execute-plan!` attach `:trace` on `execution-meta`.
- `gp-explain` / `format-explanation` render only recorded entries (PROMPT §17).
- Session buffer: `*last-trace*`, `*trace-history*` (capped) — not persistence.

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
select automatic policy: `:signal`, `:skip`, `:retry`, `:abort`, `:ask`.

## State transition & executor

Symbolic `transition-facts`; simulate does not mutate live context; execute
updates context facts only.

## Dependency policy

ANSI CL + ASDF + UIOP. Tests: FiveAM.
