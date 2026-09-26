# AUTOMA GP

Context-centric **symbolic deliberative automaton** in Common Lisp (SBCL /
macOS). Not a chatbot.

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Spec: [`docs/PROMPT.md`](docs/PROMPT.md) · Architecture:
[`docs/architecture.md`](docs/architecture.md) · Roadmap: [`ROADMAP.md`](ROADMAP.md).

## Status (Phase 8 / v0.8.0)

Phases 1–7 plus **OS adapters** (filesystem / processes / macOS) kept outside
the symbolic core. EXECUTE is symbolic by default; opt in with `:adapters t`.

**Not yet:** domain packs, events, web UI.

## Adapters (REPL)

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

;; Abstract primitives (UIOP-backed) — usable directly for inspection:
(file-exists-p "/tmp")
(directory-files "/tmp" "*.txt")
(run-program '("echo" "hi") :output :string)
(process-running-p (uiop:getpid))

;; Bind an operator to a real side effect via :EXTERNAL meta:
(gp-add-fact '(path-ready marker))
(gp-add-operator
 (make-operator
  :name 'write-marker
  :preconditions '((path-ready ?name))
  :add-list '((file-created ?name))
  :meta (list :external
              (list :adapter :filesystem
                    :op :write-string
                    :args (list :path "/tmp/automa-gp-marker.txt"
                                :content "ok")))))
(gp-plan :goals '((file-created marker)))
(gp-simulate)              ; never touches the filesystem
(gp-run :adapters t)       ; may write the file
```

## Memory & explanation

```lisp
(gp-remember-procedure :name 'connect-interface)
(gp-save "/tmp/studio.agp")
(gp-explain :plan)
```

## Workbench examples

- [`docs/tavolo-di-lavoro.md`](docs/tavolo-di-lavoro.md)
- [`docs/framework-pipeline-contesto.md`](docs/framework-pipeline-contesto.md)

## Tests

```bash
./scripts/run-tests.sh
```

## License

BSD-2-Clause. Copyright (c) 2026 Giacomo Picchiarelli.
