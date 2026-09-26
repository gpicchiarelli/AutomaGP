# AUTOMA GP

Context-centric **symbolic deliberative automaton** in Common Lisp (SBCL /
macOS). Not a chatbot.

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Spec: [`docs/PROMPT.md`](docs/PROMPT.md) · Architecture:
[`docs/architecture.md`](docs/architecture.md) · Roadmap: [`ROADMAP.md`](ROADMAP.md).

## Status (Phase 11 / v0.11.0)

Phases 1–10 plus an optional **web operator console** over the symbolic core
(PROMPT §18: web is interface only). The REPL remains first-class.

**Not yet:** full autonomous loop (Phase 12).

## Web console

```bash
./scripts/run-web.sh
# → http://127.0.0.1:47391/
```

Or from the REPL:

```lisp
(ql:quickload :automa-gp/web)
(automa-gp/web:start-web)           ; port 47391
;; (automa-gp/web:start-web :port 47391)
(automa-gp/web:web-url)
(automa-gp/web:stop-web)
```

Override port: `AUTOMA_GP_WEB_PORT=47400 ./scripts/run-web.sh`.

The UI inspects/controls context, facts, goals, events, plan, simulate, run,
and explain. All reasoning stays in the Lisp core (`web-api-handle`).

## REPL (primary)

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

(gp-reset)
(gp-load-domain :documents)
(gp-emit '(file-created "document.pdf") :react t :plan t)
(gp-explain)
```

## Domains

| Domain | Demo |
|--------|------|
| software | fetch → compile → test |
| documents | ingest → classify → archive (+ `file-created`) |
| hardware | power-on → connect → configure |
| music | interface → MIDI → session |
| geometry | points → segments → triangle |

## Tests

```bash
./scripts/run-tests.sh
```

## License

BSD-2-Clause. Copyright (c) 2026 Giacomo Picchiarelli.
