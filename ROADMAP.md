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

## Phase 9 — Domain adapters

- [x] `domains/software` — repo → compile → test
- [x] `domains/documents` — ingest → classify → archive (pipeline-aligned)
- [x] `domains/hardware` — power → connect → configure
- [x] `domains/music` — interface → MIDI route → session
- [x] `domains/geometry` — points → segments → triangle
- [x] `gp-load-domain` registry (no core MEA changes)

## Phase 10 — Event system

- [x] Events bound to context (`gp-emit` / `gp-events`)
- [x] Event → reaction → goal → plan → update (`gp-react`)
- [x] Goal-directed and event-driven behavior coexist

## Phase 11 — Web interface

- [x] Thin Hunchentoot operator console (`automa-gp/web`)
- [x] JSON API façade in core (no chatbot / no second brain)
- [x] REPL remains first-class; web optional

## Phase 12 — Autonomous symbolic operation

- [x] Controlled autonomy loop (`gp-autonomous-step` / `gp-autonomous-loop`)
- [x] Explicit policy gates (:READ / :SIMULATE / :EXECUTE + confirm)
- [x] Web console autonomy status / step / loop

**Roadmap status:** phases 1–12 delivered as scaffold + working core (v0.12.0).
Further work is deepening domains, adapters, and autonomy policy — not missing phases.

---

Priority: **correctness → clarity → testability → performance**.
