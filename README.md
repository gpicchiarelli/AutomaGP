# AUTOMA GP

Context-centric **symbolic deliberative automaton** in Common Lisp (SBCL /
macOS). Not a chatbot.

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Spec: [`docs/PROMPT.md`](docs/PROMPT.md) · Architecture:
[`docs/architecture.md`](docs/architecture.md) · Roadmap: [`ROADMAP.md`](ROADMAP.md).

## Status (Phase 9 / v0.9.0)

Phases 1–8 plus **domain packs** that register knowledge and operators without
changing the MEA/planner core.

**Not yet:** event system, web UI, full autonomy loop.

## Domain packs (REPL)

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

(gp-reset)
(gp-load-domain :software)
(automa-gp/domain/software:software-demo-plan (gp-context) :project 'myapp)
;; or:
(gp-add-fact '(project myapp))
(gp-plan :goals '((tests-ok myapp)))
(gp-simulate)

;; Documents (pipeline-shaped):
(gp-reset)
(automa-gp/domain/documents:documents-demo-plan
 (gp-context) :source "note.txt" :class 'memo)

;; Hardware / music / geometry:
(automa-gp/domain/hardware:hardware-demo-plan (gp-context))
(automa-gp/domain/music:music-demo-plan (gp-context))
(automa-gp/domain/geometry:geometry-demo-plan (gp-context))

(gp-domains)   ; => (SOFTWARE) etc.
```

| Domain | Demo goal chain |
|--------|-----------------|
| software | fetch → compile → test |
| documents | ingest → classify → archive |
| hardware | power-on → connect → configure |
| music | power interface → MIDI route → session |
| geometry | define points → segments → triangle |

## Adapters

EXECUTE is symbolic by default. `(gp-run :adapters t)` runs `:external` specs
(e.g. software `compile-project` → `true`, documents archive → temp file write).

## Tests

```bash
./scripts/run-tests.sh
```

## License

BSD-2-Clause. Copyright (c) 2026 Giacomo Picchiarelli.
