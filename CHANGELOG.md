# Changelog

All notable changes to AUTOMA GP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows the incremental phases in `docs/PROMPT.md` §25.

## [0.1.0] — 2026-09-26

### Added

- Project bootstrap: ASDF system `automa-gp`, packages, BSD-2-Clause license.
- Phase 1 core: context (create, query, modify, clone, compare, parent/child),
  state, facts (lists + simple `?x` find), goals, actions, mode skeleton
  (`READ` / `PLAN` / `SIMULATE` / `EXECUTE`).
- Minimal REPL surface: `gp-context`, `gp-state`, `gp-facts`, `gp-goals`,
  `gp-actions`, `gp-add-fact`, `gp-remove-fact`, `gp-add-goal`, `gp-reset`,
  and honest stubs for later commands (`gp-rules`, `gp-plan`, …).
- FiveAM tests for Phase 1; `scripts/run-tests.lisp`.
- Docs: master prompt (`docs/PROMPT.md`), architecture note, ROADMAP.
- Scaffold directories for memory, domains, adapters, and later core modules
  (explicitly not implemented).

### Not yet

- Pattern matching / unification / rules (Phase 2).
- MEA / planner (Phase 3).
- Executor / full simulation (Phase 4).
- Condition restarts, explanation, memory, adapters, domains, events, web UI.
