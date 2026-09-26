# Architecture (Phases 1–10)

Domain packs and events sit outside the MEA kernel. Events bind to a context;
reactions assert facts / add goals; planning reuses the same planner.

```text
interface/     REPL (gp-emit · gp-react · gp-load-domain)
    ↓
domains/       software · documents · hardware · music · geometry
    ↓
adapters/      filesystem · processes · macos
    ↓
memory/        working · knowledge · episodic · procedural · persistence
    ↓
core/          events → mea → planner → executor  (domain-agnostic)
```

## Events (Phase 10 / PROMPT §16)

- `emit-event!` / `gp-emit` — post `(type . data)` on the context; optional fact assert
- `event-reaction` — match event → assert facts + add goals
- `process-pending-events!` / `gp-react` — drain pending; optional `:plan t`
- Goal-directed `gp-plan` remains available with or without events

Honest limits: no filesystem watchers; events are posted by API/REPL.

## Domains (Phase 9 / PROMPT §12)

Each pack exports `install-*-domain` and a `*-demo-plan`. Documents registers
an `on-file-created` reaction for the §16 example.

## Adapters (Phase 8)

Opt-in on EXECUTE via `*invoke-adapters*` / `(gp-run :adapters t)`.

## Dependency policy

ANSI CL + ASDF + UIOP. Tests: FiveAM.
