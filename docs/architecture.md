# Architecture (Phases 1–9)

Domain packs add knowledge **outside** the symbolic core. MEA/planner/executor
are unchanged; domains only `register-operator!` / `register-rule!` / facts.

```text
interface/     REPL (gp-load-domain)
    ↓
domains/       software · documents · hardware · music · geometry
    ↓
adapters/      filesystem · processes · macos
    ↓
memory/        …
    ↓
core/          mea → planner → executor  (domain-agnostic)
```

## Domains (Phase 9 / PROMPT §12)

Each pack exports `install-*-domain` and a `*-demo-plan`. Optional
`:external` meta reuses Phase-8 adapters (never required for planning).

## Adapters (Phase 8)

Opt-in on EXECUTE via `*invoke-adapters*` / `(gp-run :adapters t)`.

## Dependency policy

ANSI CL + ASDF + UIOP. Tests: FiveAM.
