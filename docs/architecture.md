# Architecture (Phases 1–12)

```text
browser  →  automa-gp/web  →  web-api-handle  →  core / REPL / autonomy
slime    →  interface/repl.lisp              ↗
```

```text
interface/     REPL · JSON · web-api · (web via automa-gp/web)
    ↓
domains/       software · documents · hardware · music · geometry
    ↓
autonomy       policy-gated observe→plan→(simulate|execute)→update
    ↓
adapters/      filesystem · processes · macos
    ↓
memory/        working · knowledge · episodic · procedural · persistence
    ↓
core/          events · mea · planner · executor
```

## Autonomy (Phase 12 / PROMPT §28)

- `make-autonomy-policy` — `:authority` `:read` | `:simulate` | `:execute`
- `autonomous-step` / `gp-autonomous-step` — one controlled cycle
- `autonomous-loop` / `gp-autonomous-loop` — repeat until done/halt/max-steps
- High-risk / irreversible operators require `auto-confirm` or `confirm-fn`
- Default authority `:simulate`; adapters still opt-in

## Web (Phase 11)

Optional Hunchentoot console on `127.0.0.1:47391`.

## Dependency policy

Core: ANSI CL + ASDF + UIOP.  
Web (optional): Hunchentoot.  
Tests: FiveAM.
