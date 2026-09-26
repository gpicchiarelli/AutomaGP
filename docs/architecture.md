# Architecture (Phases 1–7)

AUTOMA GP keeps OS/domain details out of the symbolic core. Failures use the
Common Lisp **condition system**. Significant decisions are recorded into a
**deliberative trace**. Multilevel **memory** is in-process; **persistence**
is a separate file service (never inside the planner).

```text
interface/     REPL (gp-explain, gp-save, gp-remember-procedure, …)
    ↓
memory/        working → knowledge → episodic → procedural → persistence
    ↓
core/          operators → explanation → mea → planner → conditions → executor
```

## Modes

`READ` → `PLAN` → `SIMULATE` → `EXECUTE` (symbolic facts; adapters in Phase 8).

## Memory (Phase 7)

| Layer | Role |
|-------|------|
| Working | Snapshot of current context facts/goals/mode |
| Knowledge | General facts/rules, import/export with contexts |
| Episodic | Past plan/simulate/execute episodes (bounded) |
| Procedural | Reusable procedures learned from successful plans |

Retrieval of procedures is **explicit** (`gp-find-procedure` /
`procedure->plan`). The planner does not auto-rewrite from procedural memory.

## Persistence (Phase 7)

`save-snapshot` / `load-snapshot` write readable s-expression bundles
(contexts, knowledge, episodic, procedural, meta). `persist-context` /
`restore-context` for context-only files. UIOP + ANSI file I/O only.

Honest limits: no parent/child graph in snapshots (local slots); no DB;
no encryption.

## Deliberative trace (Phase 6)

Recorded during MEA / plan / simulate / execute; `gp-explain` formats entries
only. Session buffer — use persistence to save contexts/memory, not traces
as a first-class store (traces remain attachable on plan/execution meta).

## Conditions & restarts (Phase 5)

Restarts: `:retry` `:skip` `:abort-execution` `:use-value` `:use-alternative`
`:ask-user` `:confirm`. Strategy via `*deliberative-strategy*`.

## Dependency policy

ANSI CL + ASDF + UIOP. Tests: FiveAM.
