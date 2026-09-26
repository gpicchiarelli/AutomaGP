# Architecture (Phases 1–2)

AUTOMA GP is layered so the **symbolic core** never embeds OS or domain
details. Adapters and domains plug in later; the planner (Phase 3+) works only
on abstract operators and actions.

```text
interface/          REPL (SLIME) — first UI
    ↓
core/               Context, state, facts, matcher, unification, rules, queries,
                    goals, actions, modes
    ↓ (later)
memory/             Working / knowledge / episodic / procedural + persistence
domains/            software, documents, hardware, music, geometry
adapters/           macOS, filesystem, processes
```

## Central abstraction: Context

A **context** is the unit GP works inside. It holds facts, goals, actions,
rules, a mode, optional parent/children, and metadata. Children inherit
ancestor facts and rules as a **union**; an identical local fact (EQUAL)
replaces the ancestor copy; a same-named local rule replaces an ancestor rule.

## Modules

| Module | Phase | Responsibility |
|--------|-------|----------------|
| `core/modes.lisp` | 1 | Mode enum skeleton |
| `core/matcher.lisp` | 2 | Pattern match, bindings, substitution |
| `core/unification.lisp` | 2 | Unify with occur-check |
| `core/facts.lisp` | 1–2 | Fact store; uses matcher |
| `core/context.lisp` | 1–2 | Context object + hierarchy |
| `core/state.lisp` | 1 | Explicit state snapshot |
| `core/goals.lisp` | 1 | Goal registry |
| `core/actions.lisp` | 1 | Abstract action records |
| `core/rules.lisp` | 2 | Horn rules + forward chaining |
| `core/queries.lisp` | 2 | Fact/rule query + backward chaining |
| `interface/repl.lisp` | 1–2 | `gp-*` entry points |

## Symbolic representation

Facts are ordinary Lisp lists, e.g. `(power-state interface-01 off)`. Pattern
variables are symbols whose names begin with `?`. The anonymous variable `?`
matches anything and does not bind. Segment variables (`?*x`) are not supported.

Bindings use `*no-bindings*` (empty success) and `*fail*` (failure sentinel).

## Rules & queries

- **Rules** are Horn-style: conjunction of antecedent patterns ⇒ consequent
  fact pattern(s).
- **Forward chaining** (`forward-chain` / `gp-infer`) derives new facts to a
  fixpoint (iteration limit).
- **Backward chaining** (`query` / `gp-query` with `:infer t`) proves a goal
  against facts and rule consequents (depth limit).
- No negation-as-failure, cuts, Prolog I/O, or truth-maintenance.

## Modes (skeleton)

- **READ** — observe and query (default).
- **PLAN** / **SIMULATE** / **EXECUTE** — switchable; engines not attached yet.

## Deliberate non-goals (current)

No MEA, planner, executor, condition-restart policy, persistence, or macOS
calls in `core/`. Remaining scaffold files stay unloaded stubs.

## Dependency policy

ANSI CL + ASDF + UIOP. Tests may use FiveAM via Quicklisp.
