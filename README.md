# AUTOMA GP

Context-centric **symbolic deliberative automaton** in Common Lisp (SBCL /
macOS). Not a chatbot.

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Spec: [`docs/PROMPT.md`](docs/PROMPT.md) · Architecture:
[`docs/architecture.md`](docs/architecture.md) · Roadmap: [`ROADMAP.md`](ROADMAP.md).

## Status (Phase 5 / v0.5.0)

Phases 1–4 plus **idiomatic conditions/restarts** on simulate/execute failures,
with a mutable deliberative failure strategy.

**Not yet:** `gp-explain`, memory, macOS adapters, domains, events, web UI.

## Failure handling (REPL)

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

;; Auto-skip failing steps during simulate/run:
(gp-failure-strategy :skip)
(gp-plan :goals '((connection interface-01 computer)))
(gp-simulate)

;; Or handle a single step with restarts:
(handler-bind ((precondition-failure
                (lambda (c) (declare (ignore c)) (invoke-restart :skip))))
  (call-with-gp-restarts
   (lambda () (simulate-operator facts op bindings))
   :operator op :facts-on-skip facts))

;; Irreversible execute: confirm restart
(handler-bind ((confirmation-required
                (lambda (c) (declare (ignore c)) (invoke-restart :confirm))))
  (gp-run))
```

Restarts: `:retry` `:skip` `:abort-execution` `:use-value` `:use-alternative`
`:ask-user` (and `:confirm` for irreversible ops).

## Tests

```bash
./scripts/run-tests.sh
```

## License

BSD-2-Clause. Copyright (c) 2026 Giacomo Picchiarelli.
