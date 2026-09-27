# AUTOMA GP

Context-centric **symbolic deliberative automaton** in Common Lisp (SBCL /
macOS). Not a chatbot.

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Spec: [`docs/PROMPT.md`](docs/PROMPT.md) · Architecture:
[`docs/architecture.md`](docs/architecture.md) · Roadmap: [`ROADMAP.md`](ROADMAP.md).

## Status (v0.91.0)

Working core through phase 12, plus a **persistent procedure archive**.
`gp-plan` reuses a stored procedure whose goals include the request. An
exact match comes first; extra goals of a larger procedure are applied
when its steps still work. Otherwise procedures that each achieve part of
the request are combined: no extra goals first, then procedures that also
achieve something else. Steps whose extra goals cannot be restored are
left aside. A search fills anything left. If a
precondition is missing, stored procedures
that achieve some of those facts restore it. A full cover comes first,
then procedures with no extra goals, then procedures that also achieve
something else. Steps whose extra goals cannot be restored are left aside.
A search fills anything left. That repair may itself reuse a stored
procedure, sixty-one levels deep. The stored steps then continue. A live
`gp-run` updates the score.

Autonomy defaults to `:SIMULATE`.

## Procedure archive (REPL)

```lisp
(gp-remember-procedure :name 'connect-iface)  ; also saves the archive
(gp-archive)                                  ; highest score first
(gp-plan :goals '((connection interface-01 computer))) ; archive, then MEA
(gp-run)                                      ; live result updates the score
(gp-score-procedure 'connect-iface :success t) ; manual score, still available
```

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
