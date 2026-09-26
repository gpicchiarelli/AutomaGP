# AUTOMA GP

Context-centric **symbolic deliberative automaton** in Common Lisp (SBCL /
macOS). Not a chatbot.

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Spec: [`docs/PROMPT.md`](docs/PROMPT.md) · Architecture:
[`docs/architecture.md`](docs/architecture.md) · Roadmap: [`ROADMAP.md`](ROADMAP.md).

## Status (Phase 6 / v0.6.0)

Phases 1–5 plus a **deliberative trace** recorded during MEA / plan / simulate /
execute, and honest `gp-explain` that formats that record (no invented
narratives).

**Not yet:** durable memory/persistence, macOS adapters, domains, events, web UI.

## Explanation (REPL)

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

(gp-plan :goals '((connection interface-01 computer)))
(gp-explain :plan)          ; trace attached to the plan
(gp-simulate)
(gp-explain)                ; last finished trace (simulate)
(gp-explain :execution)     ; trace on last execution-result
(gp-last-trace)             ; raw deliberative-trace object
```

## Workbench examples

Italian walkthrough of a symbolic “tavolo di lavoro” (plan → simulate → run):
[`docs/tavolo-di-lavoro.md`](docs/tavolo-di-lavoro.md) ·
[`examples/tavolo-di-lavoro.lisp`](examples/tavolo-di-lavoro.lisp).

Universal **Dynamic Context Pipeline** (Acquisition → Analysis → Output → Delivery):
[`docs/framework-pipeline-contesto.md`](docs/framework-pipeline-contesto.md) ·
[`examples/framework-pipeline-contesto.lisp`](examples/framework-pipeline-contesto.lisp).

```lisp
(ql:quickload :automa-gp)
(load "examples/tavolo-di-lavoro.lisp")
(gp-explain :plan)

;; Or the generalized operator set (github → manager PDF):
(load "examples/framework-pipeline-contesto.lisp")
(gp-explain :plan)
```

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
