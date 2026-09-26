# AUTOMA GP

Context-centric **symbolic deliberative automaton** in Common Lisp (SBCL /
macOS). Not a chatbot.

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Spec: [`docs/PROMPT.md`](docs/PROMPT.md) · Architecture:
[`docs/architecture.md`](docs/architecture.md) · Roadmap: [`ROADMAP.md`](ROADMAP.md).

## Status (Phase 10 / v0.10.0)

Phases 1–9 plus a **context-bound event system**: emit events, match
reactions, add goals, optionally plan — alongside ordinary goal-directed
`gp-plan`.

**Not yet:** web UI, OS file watchers, full autonomy loop.

## Events (REPL)

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

(gp-reset)
(gp-load-domain :documents)

;; PROMPT §16 shape: file-created → classify goal → plan
(gp-emit '(file-created "document.pdf") :react t :plan t)
(gp-last-plan)
(gp-events)
(gp-last-reaction)

;; Or stepwise:
(gp-emit '(file-created "note.pdf"))
(gp-react :plan t)

;; Goal-directed still works without events:
(gp-reset)
(gp-load-domain :hardware :seed-demo t)
(gp-plan :goals '((device-configured interface-01)))
```

## Domain packs

| Domain | Demo goal chain |
|--------|-----------------|
| software | fetch → compile → test |
| documents | ingest → classify → archive (+ `file-created` reaction) |
| hardware | power-on → connect → configure |
| music | power interface → MIDI route → session |
| geometry | define points → segments → triangle |

```lisp
(gp-load-domain :software)
(automa-gp/domain/software:software-demo-plan (gp-context) :project 'myapp)
```

## Adapters

EXECUTE is symbolic by default. `(gp-run :adapters t)` runs `:external` specs.

## Tests

```bash
./scripts/run-tests.sh
```

## License

BSD-2-Clause. Copyright (c) 2026 Giacomo Picchiarelli.
