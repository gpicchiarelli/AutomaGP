# Changelog

All notable changes to AUTOMA GP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows the incremental phases in `docs/PROMPT.md` §25.

## [0.9.0] — 2026-09-26

### Added

- Phase 9 domain packs (knowledge/operators/actions without core changes):
  `software`, `documents`, `hardware`, `music`, `geometry`.
- `gp-load-domain` / `gp-domains` registry.
- Demo planners per domain; documents/software can hook Phase-8 adapters.
- FiveAM `domains-suite`.

### Changed

- Version bump to 0.9.0.

### Not yet

- Event system (Phase 10), web UI (Phase 11).

## [0.8.0] — 2026-09-26

### Added

- Phase 8 OS adapters (separated from symbolic core):
  `adapters/filesystem.lisp`, `adapters/processes.lisp`, `adapters/macos.lisp`.
- Abstract primitives via UIOP: `file-exists-p`, `directory-files`, `run-program`,
  `process-running-p`, plus safe helpers for temp-file I/O.
- Operator `:external` meta dispatch on EXECUTE when `*invoke-adapters*` /
  `(gp-run :adapters t)` / `gp-adapters`.
- SIMULATE never invokes adapters; default EXECUTE remains symbolic-only.
- FiveAM `adapters-suite` (temp directories only).

### Changed

- Version bump to 0.8.0.

### Not yet

- Full domain packs (Phase 9).
- Privileged macOS automation beyond thin `open` / hostname helpers.

## [0.7.0] — 2026-09-26

### Added

- Phase 7 multilevel memory: working, knowledge, episodic, procedural.
- Persistence service (separate from planner): `save-snapshot` / `load-snapshot`,
  `persist-context` / `restore-context`, readable sexp files via UIOP.
- Learn reusable procedures from successful plans:
  `gp-remember-procedure`, `procedure->plan`, `gp-find-procedure`.
- REPL: `gp-working`, `gp-knowledge*`, `gp-episodes`, `gp-procedures`,
  `gp-save` / `gp-load`, `gp-save-context` / `gp-load-context`, `gp-clear-memory`.
- Automatic episodic recording on `gp-plan` / `gp-simulate` / `gp-run`
  (disable with `:remember nil`).
- FiveAM `memory-suite`.

### Changed

- Version bump to 0.7.0.
- `gp-reset` clears working + episodic session memory (keeps knowledge/procedural).

### Not yet

- macOS adapters (Phase 8).
- Automatic planner use of procedural memory (retrieval is explicit).
- Parent/child context graph persistence (local context slots only).

## [0.6.0] — 2026-09-26

### Added

- Phase 6 deliberative trace and honest `gp-explain`.
- Workbench examples: tavolo-di-lavoro, Dynamic Context Pipeline framework.
- FiveAM explanation / tavolo / framework suites.

### Not yet

- Durable memory / persistence (Phase 7) — delivered in 0.7.0.
- macOS adapters (Phase 8).

## [0.5.0] — 2026-09-26

### Added

- Phase 5 condition hierarchy: `gp-condition`, `gp-error`, `precondition-failure`,
  `confirmation-required`, `unknown-operator`, `action-failed`.
- Restarts on step failures: `:retry`, `:skip`, `:abort-execution`, `:use-value`,
  `:ask-user`, `:use-alternative`; `:confirm` for irreversible execute.
- `call-with-gp-restarts`, deliberative strategy object, `with-failure-strategy`,
  `gp-failure-strategy`, strategy event log on `execution-result`.
- Plan runners use `handler-bind` + strategy (not catch-all `handler-case`).
- FiveAM `conditions-suite`.

### Changed

- Version bump to 0.5.0.
- Executor integrates Phase-5 restarts for simulate/execute steps.

### Not yet

- Full interactive debugger UX beyond `*ask-user-fn*`.
- Explanation / `gp-explain` (Phase 6).
- macOS adapters (Phase 8).

## [0.4.0] — 2026-09-26

- Phase 4 executor, simulation, state transition.

## [0.3.0] — 2026-09-26

- Phase 3 operators, MEA, planner.

## [0.2.0] — 2026-09-26

- Phase 2 matching, unification, rules, queries.

## [0.1.0] — 2026-09-26

- Phase 1 bootstrap.
