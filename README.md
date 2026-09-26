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

## Status (Phase 2)

Working and tested:

| Area | Support |
|------|---------|
| Context | create, query, modify, clone, compare; parent/child hierarchy |
| State | explicit fact-set snapshot of a context |
| Facts | symbolic lists; `fact-p`; `find-facts` via Phase-2 matcher |
| Matcher | `match` / `match-all` / substitution; anonymous `?` |
| Unification | `unify` with occur-check |
| Rules | Horn-style on context; forward chaining |
| Queries | `gp-query` (facts or backward chain); `gp-infer` |
| Goals / Actions | Phase 1 model unchanged |
| Modes | skeleton: `READ` / `PLAN` / `SIMULATE` / `EXECUTE` (switching only) |

**Not implemented yet:** MEA, planner, executor, simulation, negation/cuts,
segment variables, TMS, condition restarts, explanation, memory, persistence,
macOS/domain adapters, events, web UI.

See [`ROADMAP.md`](ROADMAP.md) and [`docs/architecture.md`](docs/architecture.md).

## Requirements

- SBCL (tested with 2.x)
- ASDF (bundled with SBCL)
- Quicklisp (for FiveAM tests; core uses only CL + UIOP)

## Quick start (SLIME / SLY)

1. Symlink or clone this tree into `~/quicklisp/local-projects/automa-gp`.
2. In Emacs with SLIME connected to SBCL:

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

(gp-reset)
(gp-context :name 'studio-audio)
(gp-add-fact '(device interface-01))
(gp-add-fact '(power-state interface-01 on))
(gp-add-rule (make-rule :name 'powered-when-on
                        :if '((device ?d) (power-state ?d on))
                        :then '(powered ?d)))
(gp-query '(powered ?x))
(gp-infer :assert t)
(gp-facts)
```

## REPL surface

| Form | Role |
|------|------|
| `(gp-context &key name)` | Show or create/select current context |
| `(gp-state)` | Current state snapshot |
| `(gp-facts)` | Facts in current context |
| `(gp-goals)` / `(gp-actions)` / `(gp-rules)` | Registries |
| `(gp-add-fact fact)` / `(gp-remove-fact fact)` | Assert / retract |
| `(gp-add-goal goal)` | Add a goal |
| `(gp-add-rule rule)` / `(gp-remove-rule name)` | Rule registry |
| `(gp-query pattern &key (infer t))` | Query facts / rules |
| `(gp-infer &key assert limit)` | Forward-chain; optional assert |
| `(gp-mode &optional mode)` | Get/set mode skeleton |
| `(gp-reset)` | Fresh empty context |

Deferred (signal “not yet implemented”): `gp-plan`, `gp-explain`, `gp-run`,
`gp-simulate`.

## Tests

```bash
./scripts/run-tests.sh
```

## License

BSD-2-Clause. Copyright (c) 2026 Giacomo Picchiarelli. See [`LICENSE`](LICENSE).
