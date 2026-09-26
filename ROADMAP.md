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

- [x] Idiomatic CL condition hierarchy (`gp-condition` / `gp-error`)
- [x] Restarts + deliberative failure strategy

## Phase 6 — Explanation & introspection

- [x] Deliberative trace + honest `gp-explain`

## Phase 7 — Memory & persistence

- [x] Working / knowledge / episodic / procedural memory
- [x] Persistence as a separate service

## Phase 8 — macOS adapters *(current)*

- [x] `adapters/macos.lisp`, `filesystem.lisp`, `processes.lisp`
- [x] Abstract ops: `run-program`, `file-exists-p`, `directory-files`, `process-running-p`
- [x] EXECUTE may invoke `:external` specs when `*invoke-adapters*` / `:adapters t`
- [x] MEA/planner remain OS-free; symbolic-only path default

## Phase 9 — Domain adapters

- [ ] software, documents, hardware, music, geometry

## Phase 10 — Event system

- [ ] Events bound to context

## Phase 11 — Web interface

- [ ] Thin UI over the symbolic core

## Phase 12 — Autonomous symbolic operation

- [ ] Controlled autonomy loop

---

Priority: **correctness → clarity → testability → performance**.
