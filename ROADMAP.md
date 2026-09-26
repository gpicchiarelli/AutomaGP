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
- [x] Restarts: `:retry` `:skip` `:abort-execution` `:use-value` `:ask-user` `:use-alternative` (+ `:confirm`)
- [x] Deliberative strategy (`*deliberative-strategy*`, `with-failure-strategy`, `gp-failure-strategy`)
- [x] Integration with simulate/execute plan runners via `handler-bind` + restarts

## Phase 6 — Explanation & introspection *(current)*

- [x] Explanation / deliberative trace (recorded during MEA / plan / simulate / execute)
- [x] `gp-explain` (formats recorded entries only — no invented narratives)
- [x] Introspection helpers (`trace-of`, `last-trace`, `find-trace-entries`, `gp-last-trace`, `gp-trace-history`)

## Phase 7 — Memory & persistence

- [ ] Working / knowledge / episodic / procedural memory
- [ ] Persistence service

## Phase 8 — macOS adapters

- [ ] macOS / filesystem / processes adapters

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
