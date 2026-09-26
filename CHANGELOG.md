# Changelog

All notable changes to AUTOMA GP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows the incremental phases in `docs/PROMPT.md` §25.

## [0.2.0] — 2026-09-26

### Added

- Phase 2 pattern matching: `match`, `match-p`, `match-all`, `substitute-bindings`,
  anonymous `?` variable.
- Unification with occur-check: `unify`, `unify-p`.
- Horn-style rules on contexts: `make-rule`, `register-rule!`, `forward-chain`,
  parent-chain rule visibility.
- Queries: `query` / `gp-query` (facts-only or backward chaining), `gp-infer`
  (forward chain, optional assert), `gp-add-rule`, `gp-remove-rule`, `gp-rules`.
- FiveAM suites for matcher, unification, rules, queries; REPL Phase-2 coverage.

### Changed

- `fact-matches-p` / `find-facts` now use the Phase-2 matcher.
- Contexts carry a `rules` slot; clone/modify updated accordingly.
- Version bump to 0.2.0.

### Not yet

- MEA / planner / operators (Phase 3).
- Executor / simulation (Phase 4).
- Negation, cuts, segment variables, TMS, certainty factors.
- Condition restarts, explanation, memory, adapters, domains, events, web UI.

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
