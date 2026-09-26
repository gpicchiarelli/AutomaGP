# AUTOMA GP

**AUTOMA GP** is a context-centric **symbolic deliberative automaton** written
in Common Lisp (target: **SBCL on macOS**).

It is **not** a chatbot. It acquires a **context**, represents it symbolically,
queries knowledge, and (Phase 3) builds plans via Means-Ends Analysis.

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Full master specification: [`docs/PROMPT.md`](docs/PROMPT.md).

## Status (Phase 3)

| Area | Support |
|------|---------|
| Context / state / facts / goals / actions | Phase 1 |
| Matcher / unification / rules / queries | Phase 2 |
| Operators | Abstract; registry; lift from actions |
| MEA | Differences → operator → precondition subgoals |
| Planner | Symbolic plans; does not mutate live context |
| Modes | `:PLAN` set by `gp-plan`; no executor yet |

**Not implemented:** `gp-run`, `gp-simulate`, `gp-explain`, adapters, domains,
events, web UI, HTN/temporal/conditional planning.

See [`ROADMAP.md`](ROADMAP.md) and [`docs/architecture.md`](docs/architecture.md).

## Quick start (SLIME)

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

(gp-reset)
(gp-context :name 'studio-audio)
(gp-add-fact '(device interface-01))
(gp-add-fact '(power-state interface-01 off))
(gp-add-operator
 (make-operator :name 'power-on
                :preconditions '((device ?d) (power-state ?d off))
                :add-list '((power-state ?d on))
                :delete-list '((power-state ?d off))))
(gp-add-operator
 (make-operator :name 'connect
                :preconditions '((device ?d) (power-state ?d on))
                :add-list '((connection ?d computer))))
(gp-plan :goals '((connection interface-01 computer)))
(plan-steps (gp-last-plan))
(plan-success (gp-last-plan)) ; => T
(gp-facts) ; unchanged — planning is symbolic only
```

## REPL surface (Phases 1–3)

| Form | Role |
|------|------|
| `(gp-context …)` / `(gp-facts)` / `(gp-state)` | Context |
| `(gp-add-fact …)` / `(gp-query …)` / `(gp-infer …)` | Knowledge |
| `(gp-add-operator op)` / `(gp-operators)` | Operators |
| `(gp-plan &key goals operators)` | MEA planner |
| `(gp-last-plan)` | Last plan object |
| `(gp-mode)` | Mode skeleton |

Deferred: `gp-run`, `gp-simulate`, `gp-explain`.

## Tests

```bash
./scripts/run-tests.sh
```

## License

BSD-2-Clause. Copyright (c) 2026 Giacomo Picchiarelli. See [`LICENSE`](LICENSE).
