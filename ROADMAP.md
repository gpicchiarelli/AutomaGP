# Roadmap

Aligned to `docs/PROMPT.md` §25. Each phase leaves a loadable, tested
system. A capability appears here once it is loadable and tested.
Phases 1 to 12 are delivered; the list under
[After the roadmap](#after-the-roadmap) records each later increment
with the version that shipped it. `version.lisp` holds the current number.

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

**Status:** phases 1 to 12 delivered as a working core (v0.12.0). Everything
after that deepens memory, observation, adapters, and the autonomy policy.

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
- [x] A precondition repair may reuse archived procedures three to sixty-one levels deep, one level per version (v0.33.0 to v0.91.0); the bound is `*procedure-repair-archive-depth*`
- [x] macOS workbench: narrated trace, archive cards, simulate/execute gate (v0.92.0)
- [x] One-shot induction of a ground operator from a before/after observation (v0.92.0)
- [x] A failed plan listens; one manual change induces an operator and lifts the shared object (v0.93.0)
- [x] Workbench ergonomics: one next step, editable facts, confirm before execute (v0.94.0)
- [x] Notice one existing file when a reaction already models it (v0.95.0)
- [x] An Italian phrase becomes a goal only when that shape already exists (v0.96.0)
- [x] A second example merges into an induced operator when it fits (v0.97.0)
- [x] A phrase is a goal when its words match a shape already in the context (v0.98.0)
- [x] A second ground example merges when every constant stays the same (v0.99.0)
- [x] A phrase may leave a fixed trailing term unsaid when only one goal fits (v0.100.0)
- [x] A phrase may name an operator, or a word that operator declares (v0.101.0)
- [x] A declared word also matches the same stem (v0.102.0)
- [x] A word can be declared on an existing operator (v0.103.0)
- [x] A reaction name or a rule name can ask for its goal (v0.104.0)
- [x] A declared word can name a reaction or a rule (v0.105.0)
- [x] The workbench can declare that word on a reaction or a rule (v0.106.0)
- [x] The workbench can declare that word on an operator already in the context (v0.107.0)
- [x] A declared word can pick one of two things that share a name (v0.108.0)
- [x] An ambiguous phrase names its goals, and one of them can be recorded (v0.109.0)
- [x] An undeclared word can be offered when the other words already fit (v0.110.0)
- [x] A lone word can name a goal that has no variables (v0.111.0)
- [x] A lone word names that goal only when it is the only one (v0.112.0)
- [x] A lone word names every such goal when there is more than one (v0.113.0)
- [x] A lone word names a goal only when the word occurs in it (v0.114.0)
- [x] A lone word matches the same stem of a goal term (v0.115.0)
- [x] A stem drops one superlative ending (v0.116.0)
- [x] A stem drops one -mente ending (v0.117.0)
- [x] A stem drops one -ezza ending (v0.118.0)
- [x] A -sione noun restores a final D (v0.119.0)
- [x] A -mento noun shares the verb stem (v0.120.0)
- [x] A word whose stem is exactly a name is not a new word (v0.121.0)
- [x] An unknown word is not declared when the other words already fit (v0.122.0)
- [x] One directory is noticed once, and its reactions update the context (v0.123.0)
- [x] One directory stays under watch until stopped (v0.124.0)
- [x] A directory notice enters subdirectories and skips a linked directory (v0.125.0)
- [x] A named running process is noticed once (v0.126.0)
- [x] A named process stays under watch until stopped (v0.127.0)
- [x] A named open terminal is noticed once (v0.128.0)
- [x] A named terminal stays under watch until stopped (v0.129.0)
- [x] A named transcript text is noticed once (v0.130.0)
- [x] A named transcript stays under watch until stopped (v0.131.0)
- [x] A named Terminal tab text is noticed once (v0.132.0)
- [x] A named Terminal tab stays under watch until stopped (v0.133.0)
- [x] Notice watches share one lifecycle and stay independent (v0.134.0)
- [x] A notice watch is reserved before its first look (v0.135.0)
- [x] A stop ends a notice look before the next target (v0.136.0)
- [x] A stop drops the notice read still open (v0.137.0)
- [x] A stop drops a process check and a transcript read (v0.138.0)
- [x] Plan the goals a notice already recorded (v0.139.0)
- [x] A plan names its external action before anything runs (v0.140.0)
- [x] An execute refuses an external action that changed (v0.141.0)
- [x] A replay records the external action it would run again (v0.142.0)
- [x] An effects-only replay withholds the external action (v0.143.0)
- [x] A plan names only the external action it would run (v0.144.0)
- [x] An external action refuses when the facts no longer support it (v0.145.0)
- [x] A refused execute leaves the mode unchanged (v0.146.0)
- [x] An autonomous execute halts when the external action is refused (v0.147.0)
- [x] An unsupported external action refuses before earlier steps apply (v0.148.0)
- [x] A changed external action refuses before earlier steps apply (v0.149.0)
- [x] A simulation refuses when the external action no longer matches (v0.150.0)
- [x] A simulation refuses when the facts no longer support the external action (v0.151.0)
- [x] The workbench can take one autonomous step (v0.152.0)
- [x] The workbench can run a bounded autonomous loop (v0.153.0)
- [x] The workbench shows the last autonomous outcome (v0.154.0)
- [x] The workbench can set the autonomous loop bound (v0.155.0)
- [x] Status reports open goals and pending events (v0.156.0)
- [x] Passo and Ciclo wait for open work (v0.157.0)
- [x] REPL and API refuse idle autonomy (v0.158.0)
- [x] Plan open goals refuses when none are open (v0.159.0)
- [x] Plan refuses goals that already hold (v0.160.0)
- [x] Simula and Esegui wait for a plan (v0.161.0)
- [x] Simula and Esegui wait for a successful plan (v0.162.0)
- [x] Archive use ends plan-failed listening (v0.163.0)
- [x] Ask refuses a goal that already holds (v0.164.0)
- [x] Add-goal refuses a fact that already holds (v0.165.0)
- [x] Induce refuses without listening (v0.166.0)
- [x] Remember refuses without a successful plan (v0.167.0)
- [x] Operator console disables until ready (v0.168.0)
- [x] Operator console Plan matches open goals (v0.169.0)
- [x] Operator console Plan idle when typed goals hold (v0.170.0)
- [x] Operator console Use/Score idle without archive (v0.171.0)
- [x] Operator console React idle without pending events (v0.172.0)
- [x] Archive applies gates Use (v0.173.0)
- [x] Operator console Emit/Fact idle without valid JSON (v0.174.0)
- [x] Archive applies is opt-in (v0.175.0)
- [x] Archive applies probe cache (v0.176.0)
- [x] Applies cache clear on reset; changelog .agp (v0.177.0)
- [x] README suite counts and archive applies query (v0.178.0)
- [x] Operator console Sim/Run match external gates (v0.179.0)
- [x] Notice PTY/test hygiene and Remember caption (v0.180.0)
- [x] Status external gates before plan GET (v0.181.0)
- [x] Plan idle on invalid Goals; archive refresh gate (v0.182.0)
- [x] Operator console autonomy policy sync (v0.183.0)
- [x] Operator console execute autonomy confirms adapters (v0.184.0)
- [x] Operator console Run confirm and adapters parity (v0.185.0)
- [x] Workbench archive applies refresh gate (v0.186.0)
- [x] Run/Esegui wait for live plan external list (v0.187.0)
- [x] Workbench idle when disconnected (v0.188.0)
- [x] Simulate/run façade gates; workbench externalSupported help (v0.189.0)
- [x] Workbench Esegui waits for live plan external list (v0.190.0)
- [x] HTML console idle when unreachable (v0.191.0)
- [x] Workbench autonomy :read parity (v0.192.0)
- [x] Leggi react-then-halt honesty; Passo help (v0.193.0)
- [x] Esegui confirm honesty; HTML autonomy confirm (v0.194.0)

---

Priority: correctness, then clarity, then testability, then performance.
