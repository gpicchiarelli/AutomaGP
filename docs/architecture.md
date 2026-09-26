# Architecture (Phases 1–3)

AUTOMA GP is layered so the **symbolic core** never embeds OS or domain
details. The planner works only on abstract operators and actions.

```text
interface/          REPL (SLIME) — first UI
    ↓
core/               Context … matcher, rules, queries,
                    operators, MEA, planner
    ↓ (later)
memory/             Working / knowledge / episodic / procedural + persistence
domains/            software, documents, hardware, music, geometry
adapters/           macOS, filesystem, processes
```

## Central abstraction: Context

A **context** holds facts, goals, actions, rules, operators, mode, and
optional parent/children. Children inherit ancestor facts/rules/operators
(local name wins for rules/operators; EQUAL fact override for facts).

## Modules

| Module | Phase | Responsibility |
|--------|-------|----------------|
| `core/modes.lisp` | 1 | Mode enum skeleton |
| `core/matcher.lisp` | 2 | Pattern match, bindings, substitution |
| `core/unification.lisp` | 2 | Unify with occur-check |
| `core/facts.lisp` | 1–2 | Fact store |
| `core/context.lisp` | 1–3 | Context object + hierarchy |
| `core/state.lisp` | 1 | Explicit state snapshot |
| `core/goals.lisp` | 1 | Goal registry |
| `core/actions.lisp` | 1 | Abstract action records |
| `core/rules.lisp` | 2 | Horn rules + forward chaining |
| `core/queries.lisp` | 2 | Fact/rule query + backward chaining |
| `core/operators.lisp` | 3 | Planning operators |
| `core/mea.lisp` | 3 | Means-Ends Analysis |
| `core/planner.lisp` | 3 | Plan objects + `plan-from-context` |
| `interface/repl.lisp` | 1–3 | `gp-*` entry points |

## Means-Ends Analysis (Phase 3)

```text
GOAL → DIFFERENCES → OPERATOR → PRECONDITIONS → SUBGOALS → SUBPLANS → PLAN
```

1. Compute differences (desired facts not holding in the current fact list).
2. Select an operator whose add-list unifies with a difference.
3. Unsatisfied (grounded) preconditions become subgoals.
4. Recursively achieve subgoals, then symbolically apply add/delete lists.
5. Assemble an ordered plan of steps.

Symbolic application during planning **does not** mutate the live context and
**does not** invoke adapters. That is Phase 4 (`gp-run` / `gp-simulate`).

Planning goals must be **fact lists**. Bare symbol goals (e.g. `audio-system-ready`)
are labels only until expressed as desired facts.

## Modes

- **READ** — observe and query.
- **PLAN** — set by `gp-plan` (advisory); planning does not require it.
- **SIMULATE** / **EXECUTE** — reserved for Phase 4.

## Dependency policy

ANSI CL + ASDF + UIOP. Tests may use FiveAM via Quicklisp.
