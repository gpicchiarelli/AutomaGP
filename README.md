# AUTOMA GP

**AUTOMA GP** is a context-centric **symbolic deliberative automaton** in
Common Lisp (SBCL / macOS). Not a chatbot.

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Master spec: [`docs/PROMPT.md`](docs/PROMPT.md). Architecture:
[`docs/architecture.md`](docs/architecture.md). Roadmap: [`ROADMAP.md`](ROADMAP.md).

## Status (Phase 4 / v0.4.0)

Working: context, facts, matcher/unification/rules/queries, operators, MEA
planner, **symbolic simulation & execution** with CURRENT / SIMULATED /
EXPECTED / OBSERVED states.

**Not yet:** macOS adapters, condition restarts, explanation, memory,
domains, events, web UI.

## Quick start (SLIME)

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

(gp-reset)
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
(gp-simulate)   ; mode :SIMULATE — live facts unchanged
(gp-facts)      ; still power-state off
(gp-run)        ; mode :EXECUTE — updates context facts
(gp-facts)      ; connection + power-state on
```

Irreversible / high-risk operators on execute:

```lisp
(gp-run :confirm t)   ; or bind *execution-confirm*
```

## Tests

```bash
./scripts/run-tests.sh
```

## License

BSD-2-Clause. Copyright (c) 2026 Giacomo Picchiarelli.
