# Architecture (Phases 1–11)

The web layer is optional and contains **no deliberative logic**.

```text
browser  →  automa-gp/web (Hunchentoot)  →  web-api-handle  →  core/REPL
slime    →  interface/repl.lisp          ↗
```

```text
interface/     REPL · JSON · web-api · (web via automa-gp/web)
    ↓
domains/       software · documents · hardware · music · geometry
    ↓
adapters/      filesystem · processes · macos
    ↓
memory/        working · knowledge · episodic · procedural · persistence
    ↓
core/          events · mea · planner · executor
```

## Web (Phase 11 / PROMPT §18)

- System `automa-gp` — core + `web-api-handle` (no Hunchentoot)
- System `automa-gp/web` — Hunchentoot console on `127.0.0.1:47391`
- API: `/api/status|context|facts|goals|plan|explain|events|…`
- Mutations: `/api/reset|plan|simulate|run|emit|react|load-domain|add-fact`

## Events (Phase 10)

`gp-emit` / `gp-react` — event → reaction → goals → optional plan.

## Dependency policy

Core: ANSI CL + ASDF + UIOP.  
Web (optional): Hunchentoot via Quicklisp.  
Tests: FiveAM.
