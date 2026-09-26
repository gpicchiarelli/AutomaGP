# Changelog

All notable changes to AUTOMA GP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows the incremental phases in `docs/PROMPT.md` §25.

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
