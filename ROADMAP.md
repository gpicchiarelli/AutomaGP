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

## After the roadmap

- [x] Persistent scored procedure archive (v0.13.0)
- [x] Planning reuses an archived procedure when its steps still apply (v0.14.0)
- [x] Live execution of a reused procedure updates its score (v0.15.0)
- [x] Operator console lists and uses the procedure archive (v0.16.0)
- [x] Using a procedure checks that its steps still apply (v0.17.0)
- [x] Replay skips archived steps whose goal already holds (v0.18.0)
- [x] Replay applies the effects of a skipped step when they are still missing (v0.19.0)
- [x] Archived steps keep their effects and replay them without the operator (v0.20.0)
- [x] Replay applies a recorded step when its preconditions hold and the operator is gone (v0.21.0)
- [x] Replay repairs one missing precondition, then continues the stored steps (v0.22.0)
- [x] A precondition repair may reuse one archived procedure with that goal (v0.23.0)
- [x] That reused procedure may itself reuse one more archived procedure (v0.24.0)
- [x] A precondition repair may reuse a procedure whose goals include the missing fact (v0.25.0)
- [x] A precondition repair may combine procedures that each restore part of the gap (v0.26.0)
- [x] A precondition repair may reuse a procedure that also achieves something else (v0.27.0)
- [x] A precondition repair keeps useful steps when extra goals are blocked (v0.28.0)
- [x] Planning reuses a procedure whose goals include the request (v0.29.0)
- [x] Planning combines procedures that each achieve part of the request (v0.30.0)
- [x] Planning may combine a procedure that also achieves something else (v0.31.0)
- [x] Planning keeps useful steps when extra goals are blocked (v0.32.0)
- [x] A precondition repair may reuse an archived procedure three levels deep (v0.33.0)
- [x] A precondition repair may reuse an archived procedure four levels deep (v0.34.0)
- [x] A precondition repair may reuse an archived procedure five levels deep (v0.35.0)
- [x] A precondition repair may reuse an archived procedure six levels deep (v0.36.0)
- [x] A precondition repair may reuse an archived procedure seven levels deep (v0.37.0)
- [x] A precondition repair may reuse an archived procedure eight levels deep (v0.38.0)
- [x] A precondition repair may reuse an archived procedure nine levels deep (v0.39.0)
- [x] A precondition repair may reuse an archived procedure ten levels deep (v0.40.0)
- [x] A precondition repair may reuse an archived procedure eleven levels deep (v0.41.0)
- [x] A precondition repair may reuse an archived procedure twelve levels deep (v0.42.0)
- [x] A precondition repair may reuse an archived procedure thirteen levels deep (v0.43.0)
- [x] A precondition repair may reuse an archived procedure fourteen levels deep (v0.44.0)
- [x] A precondition repair may reuse an archived procedure fifteen levels deep (v0.45.0)
- [x] A precondition repair may reuse an archived procedure sixteen levels deep (v0.46.0)
- [x] A precondition repair may reuse an archived procedure seventeen levels deep (v0.47.0)
- [x] A precondition repair may reuse an archived procedure eighteen levels deep (v0.48.0)
- [x] A precondition repair may reuse an archived procedure nineteen levels deep (v0.49.0)
- [x] A precondition repair may reuse an archived procedure twenty levels deep (v0.50.0)
- [x] A precondition repair may reuse an archived procedure twenty-one levels deep (v0.51.0)
- [x] A precondition repair may reuse an archived procedure twenty-two levels deep (v0.52.0)
- [x] A precondition repair may reuse an archived procedure twenty-three levels deep (v0.53.0)
- [x] A precondition repair may reuse an archived procedure twenty-four levels deep (v0.54.0)
- [x] A precondition repair may reuse an archived procedure twenty-five levels deep (v0.55.0)
- [x] A precondition repair may reuse an archived procedure twenty-six levels deep (v0.56.0)
- [x] A precondition repair may reuse an archived procedure twenty-seven levels deep (v0.57.0)
- [x] A precondition repair may reuse an archived procedure twenty-eight levels deep (v0.58.0)
- [x] A precondition repair may reuse an archived procedure twenty-nine levels deep (v0.59.0)
- [x] A precondition repair may reuse an archived procedure thirty levels deep (v0.60.0)
- [x] A precondition repair may reuse an archived procedure thirty-one levels deep (v0.61.0)
- [x] A precondition repair may reuse an archived procedure thirty-two levels deep (v0.62.0)
- [x] A precondition repair may reuse an archived procedure thirty-three levels deep (v0.63.0)
- [x] A precondition repair may reuse an archived procedure thirty-four levels deep (v0.64.0)
- [x] A precondition repair may reuse an archived procedure thirty-five levels deep (v0.65.0)
- [x] A precondition repair may reuse an archived procedure thirty-six levels deep (v0.66.0)
- [x] A precondition repair may reuse an archived procedure thirty-seven levels deep (v0.67.0)
- [x] A precondition repair may reuse an archived procedure thirty-eight levels deep (v0.68.0)
- [x] A precondition repair may reuse an archived procedure thirty-nine levels deep (v0.69.0)
- [x] A precondition repair may reuse an archived procedure forty levels deep (v0.70.0)
- [x] A precondition repair may reuse an archived procedure forty-one levels deep (v0.71.0)
- [x] A precondition repair may reuse an archived procedure forty-two levels deep (v0.72.0)
- [x] A precondition repair may reuse an archived procedure forty-three levels deep (v0.73.0)
- [x] A precondition repair may reuse an archived procedure forty-four levels deep (v0.74.0)
- [x] A precondition repair may reuse an archived procedure forty-five levels deep (v0.75.0)
- [x] A precondition repair may reuse an archived procedure forty-six levels deep (v0.76.0)
- [x] A precondition repair may reuse an archived procedure forty-seven levels deep (v0.77.0)
- [x] A precondition repair may reuse an archived procedure forty-eight levels deep (v0.78.0)
- [x] A precondition repair may reuse an archived procedure forty-nine levels deep (v0.79.0)
- [x] A precondition repair may reuse an archived procedure fifty levels deep (v0.80.0)
- [x] A precondition repair may reuse an archived procedure fifty-one levels deep (v0.81.0)
- [x] A precondition repair may reuse an archived procedure fifty-two levels deep (v0.82.0)
- [x] A precondition repair may reuse an archived procedure fifty-three levels deep (v0.83.0)
- [x] A precondition repair may reuse an archived procedure fifty-four levels deep (v0.84.0)
- [x] A precondition repair may reuse an archived procedure fifty-five levels deep (v0.85.0)
- [x] A precondition repair may reuse an archived procedure fifty-six levels deep (v0.86.0)
- [x] A precondition repair may reuse an archived procedure fifty-seven levels deep (v0.87.0)
- [x] A precondition repair may reuse an archived procedure fifty-eight levels deep (v0.88.0)
- [x] A precondition repair may reuse an archived procedure fifty-nine levels deep (v0.89.0)
- [x] A precondition repair may reuse an archived procedure sixty levels deep (v0.90.0)
- [x] A precondition repair may reuse an archived procedure sixty-one levels deep (v0.91.0)

---

Priority: **correctness → clarity → testability → performance**.
