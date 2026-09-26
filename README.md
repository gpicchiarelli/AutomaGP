# AUTOMA GP

**AUTOMA GP** is a context-centric **symbolic deliberative automaton** written
in Common Lisp (target: **SBCL on macOS**).

It is **not** a chatbot, a script bag, or a conversational assistant. It is an
operational symbolic environment that acquires a **context**, represents it,
inspects state and goals, and (over later phases) reasons, plans, acts, and
updates that context.

Conceptual cycle:

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Primary references: Peter Norvig, *Paradigms of Artificial Intelligence
Programming*; Lisp symbolic systems; GPS / Means-Ends Analysis. The full
master specification lives in [`docs/PROMPT.md`](docs/PROMPT.md).

## Status (Phase 1)

Working and tested:

| Area | Support |
|------|---------|
| Context | create, query, modify, clone, compare; parent/child hierarchy |
| State | explicit fact-set snapshot of a context |
| Facts | symbolic lists; `fact-p`; `find-facts` with simple `?x` variables |
| Goals | add / remove / list / active goals |
| Actions | name, params, preconditions, effects, cost, risk, reversible, adapter, authorization |
| Modes | skeleton: `READ` / `PLAN` / `SIMULATE` / `EXECUTE` (switching only) |
| REPL | Phase-1 commands below |

**Not implemented yet** (honest stubs / deferred): pattern matching engine,
unification, rules, MEA, planner, executor, condition restarts, explanation,
memory, persistence, macOS/domain adapters, events, web UI.

See [`ROADMAP.md`](ROADMAP.md) and [`docs/architecture.md`](docs/architecture.md).

## Requirements

- SBCL (tested with 2.x)
- ASDF (bundled with SBCL)
- Quicklisp (for FiveAM tests; core Phase 1 uses only CL + UIOP)

## Quick start (SLIME / SLY)

1. Symlink or clone this tree into `~/quicklisp/local-projects/automa-gp`.
2. In Emacs with SLIME connected to SBCL:

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

(gp-reset)
(gp-context :name 'studio-audio)
(gp-add-fact '(device interface-01))
(gp-add-fact '(power-state interface-01 off))
(gp-facts)
(gp-add-goal 'audio-system-ready)
(gp-state)
(gp-mode) ; => :READ
```

Without Quicklisp path registration:

```lisp
(require :asdf)
(asdf:load-asd "/absolute/path/to/AutomaGP/automa-gp.asd")
(asdf:load-system :automa-gp)
```

## REPL surface (Phase 1)

| Form | Role |
|------|------|
| `(gp-context &key name)` | Show or create/select current context |
| `(gp-state)` | Current state snapshot |
| `(gp-facts)` | Facts in current context |
| `(gp-goals)` | Goals in current context |
| `(gp-actions)` | Registered actions |
| `(gp-add-fact fact)` | Assert a fact |
| `(gp-remove-fact fact)` | Retract a fact |
| `(gp-add-goal goal)` | Add a goal |
| `(gp-mode &optional mode)` | Get/set `:READ` `:PLAN` `:SIMULATE` `:EXECUTE` |
| `(gp-reset)` | Clear session to a fresh empty context |

Deferred (signal “not yet implemented”): `gp-rules`, `gp-plan`, `gp-explain`,
`gp-run`, `gp-simulate`, `gp-query`.

## Tests

```bash
./scripts/run-tests.sh
```

Or from a REPL after Quicklisp is available:

```lisp
(ql:quickload :automa-gp/tests)
(asdf:test-system :automa-gp)
```

## License

BSD-2-Clause. Copyright (c) 2026 Giacomo Picchiarelli. See [`LICENSE`](LICENSE).
