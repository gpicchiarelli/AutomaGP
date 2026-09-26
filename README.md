# AUTOMA GP

Context-centric **symbolic deliberative automaton** in Common Lisp (SBCL /
macOS). Not a chatbot.

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Spec: [`docs/PROMPT.md`](docs/PROMPT.md) · Architecture:
[`docs/architecture.md`](docs/architecture.md) · Roadmap: [`ROADMAP.md`](ROADMAP.md).

## Status (Phase 12 / v0.12.0)

All twelve roadmap phases are present as a **working core**: context, matching,
MEA planning, simulate/execute, conditions, explain, memory, adapters, domains,
events, thin web console, and a **policy-gated autonomy loop**.

Autonomy defaults to `:SIMULATE` — not unattended OS destruction.

## Autonomy (REPL)

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

(gp-reset)
(gp-load-domain :documents)
(gp-emit '(file-created "document.pdf"))   ; pending event
(gp-policy :authority :simulate)           ; safe default
(gp-autonomous-step)                       ; react → plan → simulate
(gp-last-autonomy)

;; Live mutation only with explicit policy:
(gp-policy :authority :execute :auto-confirm t :adapters nil)
(gp-autonomous-loop :max-steps 4)
```

## Web console

```bash
./scripts/run-web.sh
# → http://127.0.0.1:47391/
```

Operator console includes Autonomy **Step** / **Loop** (authority selectable;
default simulate).

## REPL (primary)

```lisp
(gp-reset)
(gp-load-domain :hardware :seed-demo t)
(gp-plan :goals '((device-configured interface-01)))
(gp-simulate)
(gp-explain)
```

## Tests

```bash
./scripts/run-tests.sh
```

## License

BSD-2-Clause. Copyright (c) 2026 Giacomo Picchiarelli.
