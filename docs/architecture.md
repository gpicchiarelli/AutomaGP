# Architecture (Phase 1)

AUTOMA GP is layered so the **symbolic core** never embeds OS or domain
details. Adapters and domains plug in later; the planner (Phase 3+) works only
on abstract operators and actions.

```text
interface/          REPL (SLIME) — first UI
    ↓
core/               Context, state, facts, goals, actions, modes
    ↓ (later)
memory/             Working / knowledge / episodic / procedural + persistence
domains/            software, documents, hardware, music, geometry
adapters/           macOS, filesystem, processes
```

## Central abstraction: Context

A **context** is the unit GP works inside (project, procedure, device set,
session, …). It holds facts, goals, a mode, optional parent/children, and
metadata. Contexts can be created, queried, modified, cloned, and compared.
Children inherit ancestor facts as a **union**; an identical local fact
(EQUAL) replaces the ancestor copy. Predicate-level shadowing is not Phase 1.

## Phase 1 modules

| Module | Responsibility |
|--------|----------------|
| `core/context.lisp` | Context object + hierarchy + clone/compare |
| `core/facts.lisp` | Fact assert/retract; `fact-p`; simple `?x` find |
| `core/state.lisp` | Explicit state snapshot from a context’s facts |
| `core/goals.lisp` | Goal registry on a context |
| `core/actions.lisp` | Abstract action records (no OS calls) |
| `core/modes.lisp` | Mode enum + session mode; no planner/executor |
| `interface/repl.lisp` | `gp-*` entry points |

## Symbolic representation

Facts are ordinary Lisp lists, e.g. `(power-state interface-01 off)`. Pattern
variables are symbols whose names begin with `?`. Phase 1 provides only
shallow find/match against facts — not general unification or a rule engine.

## Modes (skeleton)

- **READ** — observe and query (default).
- **PLAN** — reserved; planning not implemented.
- **SIMULATE** — reserved; effect application not implemented.
- **EXECUTE** — reserved; external actions not implemented.

Mode can be switched; later phases attach real behavior. Destructive external
actions must never be implied by Phase 1 APIs.

## Deliberate non-goals of this layer

No MEA, no planner, no executor, no condition-restart policy, no persistence,
no macOS calls in `core/`. Placeholder files under `core/`, `memory/`,
`adapters/`, and `domains/` document future phases without exporting fake
capabilities.

## Dependency policy

ANSI CL + ASDF + UIOP. Tests may use FiveAM via Quicklisp. No other libraries
unless verified on Quicklisp and justified.
