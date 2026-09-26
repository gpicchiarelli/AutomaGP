# ROADMAP

Aligned to `docs/PROMPT.md` §25. Each phase must leave a loadable, tested
system. Do not skip ahead with fake capabilities.

## Phase 1 — Context foundation

- [x] Context, state, facts, goals, actions, modes, REPL

## Phase 2 — Pattern matching & knowledge queries

- [x] Matcher, unification, rules, queries

## Phase 3 — Means-Ends Analysis & planning

- [x] Operators, MEA, planner, subgoals, `gp-plan`

## Phase 4 — Execution & simulation

- [x] Executor, state transition, `gp-simulate`, `gp-run`

## Phase 5 — Conditions & failure handling

- [x] Conditions, restarts, deliberative strategy

## Phase 6 — Explanation & introspection

- [x] Deliberative trace + honest `gp-explain`

## Phase 7 — Memory & persistence

- [x] Multilevel memory + separate persistence service

## Phase 8 — macOS adapters

- [x] filesystem / processes / macos adapters (opt-in on EXECUTE)

## Phase 9 — Domain adapters *(current)*

- [x] `domains/software` — repo → compile → test
- [x] `domains/documents` — ingest → classify → archive (pipeline-aligned)
- [x] `domains/hardware` — power → connect → configure
- [x] `domains/music` — interface → MIDI route → session
- [x] `domains/geometry` — points → segments → triangle
- [x] `gp-load-domain` registry (no core MEA changes)

## Phase 10 — Event system

- [ ] Events bound to context

## Phase 11 — Web interface

- [ ] Thin UI over the symbolic core

## Phase 12 — Autonomous symbolic operation

- [ ] Controlled autonomy loop

---

Priority: **correctness → clarity → testability → performance**.
