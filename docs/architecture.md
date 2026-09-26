# Architecture (Phases 1–4)

AUTOMA GP is layered so the **symbolic core** never embeds OS or domain
details. The planner and executor work on abstract operators and fact states.

```text
interface/          REPL (SLIME)
    ↓
core/               Context … operators, MEA, planner, executor
    ↓ (later)
memory/  domains/  adapters/
```

## Modes

| Mode | Role |
|------|------|
| `READ` | Observe / query |
| `PLAN` | Build plans (`gp-plan`) — no fact mutation |
| `SIMULATE` | Apply effects to a copy (`gp-simulate`) — live context unchanged |
| `EXECUTE` | Apply effects to live context facts (`gp-run`) — still no adapters |

## State kinds

| Kind | Meaning |
|------|---------|
| `CURRENT` | Live / pre-run snapshot |
| `SIMULATED` | Result of symbolic simulation |
| `EXPECTED` | Plan's predicted final facts |
| `OBSERVED` | Post-execute context facts (Phase 4: symbolic only) |

`execution-result` carries current, expected, final, and optional divergences
(`compare-states` of expected vs final).

## State transition

```text
STATE A  +  OPERATOR (bindings)  →  STATE B
```

Implemented as `transition-facts` / `transition-state` (add/delete lists,
optional 3-element slot conflict retract). Same mechanism used by MEA
planning, simulation, and execution.

## Executor honesty

- **Simulate** never mutates the live context.
- **Execute** updates `context-facts` only.
- No filesystem, process, or macOS calls (Phase 8).
- Irreversible or `:high`/`:critical` risk operators require `:confirm t`
  on `gp-run` (or a non-nil `*execution-confirm*` function).

## Module map (Phase 4 additions)

| Module | Role |
|--------|------|
| `core/state.lisp` | State object, kinds, transition |
| `core/executor.lisp` | Simulate / execute plans and operators |
| `interface/repl.lisp` | `gp-simulate`, `gp-run`, `gp-last-execution` |

## Dependency policy

ANSI CL + ASDF + UIOP. Tests use FiveAM via Quicklisp.
