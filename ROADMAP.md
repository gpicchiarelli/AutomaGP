# ROADMAP

Aligned to `docs/PROMPT.md` §25. Each phase must leave a loadable, tested
system. Do not skip ahead with fake capabilities.

## Phase 1 — Context foundation

- [x] Context (create, query, modify, clone, compare; parent/child)
- [x] State
- [x] Facts (lists; `fact-p` / find with simple `?x`)
- [x] Goals
- [x] Actions (abstract model)
- [x] Modes skeleton (`READ` / `PLAN` / `SIMULATE` / `EXECUTE`)
- [x] Minimal honest REPL API

## Phase 2 — Pattern matching & knowledge queries

- [x] Pattern matching (`match`, `match-all`, substitution)
- [x] Unification (`unify`, occur-check)
- [x] Rules (Horn-style; forward chaining)
- [x] Queries (`gp-query`, backward chaining; `gp-infer`)

## Phase 3 — Means-Ends Analysis & planning *(current)*

- [x] Operators (abstract; actions can be lifted)
- [x] Means-Ends Analysis (GPS-style differences → operator → subgoals)
- [x] Planner (`plan-for`, `plan-from-context`, `gp-plan`)
- [x] Subgoals (unsatisfied preconditions)

## Phase 4 — Execution & simulation

- [ ] Executor
- [ ] State transition (live context update)
- [ ] Simulation (apply effects without mutating the live context via `gp-simulate`)

## Phase 5 — Conditions & failure handling

- [ ] Condition System usage
- [ ] Restarts (`RETRY`, `SKIP`, `ABORT`, `USE-VALUE`, `ASK-USER`)
- [ ] Failure handling strategy

## Phase 6 — Explanation & introspection

- [ ] Explanation / deliberative trace
- [ ] Introspection helpers (prefer native CL/SBCL)

## Phase 7 — Memory & persistence

- [ ] Working / knowledge / episodic / procedural memory
- [ ] Persistence service (separate from planner)

## Phase 8 — macOS adapters

- [ ] `adapters/macos.lisp`, `filesystem.lisp`, `processes.lisp`
- [ ] Abstract OS ops via UIOP / safe wrappers (core stays OS-free)

## Phase 9 — Domain adapters

- [ ] `domains/software`, `documents`, `hardware`, `music`, `geometry`
- [ ] Domain knowledge and operators without touching the core planner

## Phase 10 — Event system

- [ ] Events bound to context
- [ ] Goal-directed + event-driven behavior

## Phase 11 — Web interface

- [ ] Thin UI over the symbolic core (REPL remains primary)

## Phase 12 — Autonomous symbolic operation

- [ ] Controlled autonomy: understand → goal → plan → authorize → act → observe → update

---

Priority order for all work: **correctness → clarity → testability → performance**.
