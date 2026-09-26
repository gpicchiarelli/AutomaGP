# AUTOMA GP

Context-centric **symbolic deliberative automaton** in Common Lisp (SBCL /
macOS). Not a chatbot.

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Spec: [`docs/PROMPT.md`](docs/PROMPT.md) · Architecture:
[`docs/architecture.md`](docs/architecture.md) · Roadmap: [`ROADMAP.md`](ROADMAP.md).

## Status (Phase 7 / v0.7.0)

Phases 1–6 plus **multilevel memory** (working / knowledge / episodic /
procedural) and a separate **persistence** service for symbolic snapshots.

**Not yet:** macOS adapters, domains, events, web UI.

## Memory & persistence (REPL)

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

(gp-plan :goals '((connection interface-01 computer)))
(gp-remember-procedure :name 'connect-iface)
(gp-episodes)                 ; plan/simulate/execute history
(gp-save "/tmp/studio.agp")   ; snapshot: context + memory
(gp-reset)
(gp-load "/tmp/studio.agp")   ; restore session pieces
```

## Explanation (REPL)

```lisp
(gp-plan :goals '((connection interface-01 computer)))
(gp-explain :plan)
(gp-simulate)
(gp-explain)
```

## Workbench examples

Italian walkthrough of a symbolic “tavolo di lavoro” (plan → simulate → run):
[`docs/tavolo-di-lavoro.md`](docs/tavolo-di-lavoro.md) ·
[`examples/tavolo-di-lavoro.lisp`](examples/tavolo-di-lavoro.lisp).

Universal **Dynamic Context Pipeline** (Acquisition → Analysis → Output → Delivery):
[`docs/framework-pipeline-contesto.md`](docs/framework-pipeline-contesto.md) ·
[`examples/framework-pipeline-contesto.lisp`](examples/framework-pipeline-contesto.lisp).

## Failure handling (REPL)

```lisp
(gp-failure-strategy :skip)
(gp-plan :goals '((connection interface-01 computer)))
(gp-simulate)
```

Restarts: `:retry` `:skip` `:abort-execution` `:use-value` `:use-alternative`
`:ask-user` (and `:confirm` for irreversible ops).

## Tests

```bash
./scripts/run-tests.sh
```

## License

BSD-2-Clause. Copyright (c) 2026 Giacomo Picchiarelli.
