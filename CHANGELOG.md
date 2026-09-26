# Changelog

All notable changes to AUTOMA GP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows the incremental phases in `docs/PROMPT.md` §25.

## [0.4.0] — 2026-09-26

### Added

- Phase 4 state transition: `transition-facts`, `transition-state`; state kinds
  `:current` / `:simulated` / `:expected` / `:observed`.
- Symbolic executor: `simulate-operator`, `simulate-plan`, `execute-operator!`,
  `execute-plan!`, `execution-result` with CURRENT/EXPECTED/FINAL/divergences.
- REPL: `gp-simulate`, `gp-run`, `gp-last-execution`.
- Confirmation gate for irreversible/high-risk operators on EXECUTE
  (`:confirm t` or `*execution-confirm*` hook).
- Operator slots `reversible` / `risk` (lifted from actions when applicable).
- FiveAM `executor-suite` and REPL Phase-4 coverage.

### Changed

- Version bump to 0.4.0.
- Modes documentation: SIMULATE/EXECUTE are live for symbolic fact effects.
- Plans store operators in meta for simulate/execute lookup.

### Not yet

- External/macOS adapters (Phase 8) — no real side effects.
- Condition restarts (`RETRY`/`SKIP`/…) (Phase 5).
- Explanation / deliberative trace (`gp-explain`) (Phase 6).
- Observed state from external sensors (still = post-execute context facts).

## [0.3.0] — 2026-09-26

### Added

- Phase 3 operators, MEA, planner, `gp-plan`.

## [0.2.0] — 2026-09-26

### Added

- Phase 2 matching, unification, rules, queries.

## [0.1.0] — 2026-09-26

### Added

- Phase 1 context foundation and project bootstrap.
