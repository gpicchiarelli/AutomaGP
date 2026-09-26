# Changelog

All notable changes to AUTOMA GP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows the incremental phases in `docs/PROMPT.md` §25.

## [0.3.0] — 2026-09-26

### Added

- Phase 3 operators: `make-operator`, registry on context, `action->operator`,
  `operator-achieves` / `operators-for-goal`.
- Means-Ends Analysis: `differences`, `achieve` / `achieve-all`,
  `means-ends-analyze`, precondition subgoals, symbolic `apply-operator`.
- Planner: `plan` object, `plan-for`, `plan-from-context`, `gp-plan`,
  `gp-last-plan`, `gp-operators`, `gp-add-operator`.
- FiveAM suites for operators, MEA, planner; REPL Phase-3 coverage.

### Changed

- Contexts carry an `operators` slot.
- Version bump to 0.3.0.
- `gp-plan` is live (sets advisory mode `:PLAN`); does not mutate live facts.

### Not yet

- Executor / `gp-run` / `gp-simulate` (Phase 4).
- Hierarchical / conditional / temporal planning, alternatives search beyond
  first successful operator, rollback strategies.
- Explanation trace (`gp-explain`), adapters, domains, events, web UI.

## [0.2.0] — 2026-09-26

### Added

- Phase 2 pattern matching, unification, rules, queries (`gp-query`, `gp-infer`).

## [0.1.0] — 2026-09-26

### Added

- Phase 1 context/state/facts/goals/actions/modes and bootstrap hygiene.
