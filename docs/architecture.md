# Architecture (Phases 1–8)

AUTOMA GP keeps OS/domain details out of the symbolic core. MEA and the planner
never call macOS APIs. Side effects go through **adapters**, only on EXECUTE
when explicitly enabled.

```text
interface/     REPL
    ↓
adapters/      filesystem · processes · macos   ← OS boundary
    ↓
memory/        working · knowledge · episodic · procedural · persistence
    ↓
core/          … mea → planner → conditions → executor
```

## Modes

`READ` → `PLAN` → `SIMULATE` → `EXECUTE`

- **SIMULATE:** symbolic only; never invokes adapters.
- **EXECUTE:** symbolic fact updates always; adapters run only if
  `*invoke-adapters*` / `(gp-run :adapters t)`.

## Adapters (Phase 8 / PROMPT §13)

| Module | Role |
|--------|------|
| `filesystem.lisp` | `file-exists-p`, `directory-files`, read/write helpers |
| `processes.lisp` | `run-program`, `process-running-p` |
| `macos.lisp` | dispatch, `macos-p`, hostname/uname, optional `open` |

Operators may carry:

```lisp
:meta (:external (:adapter :filesystem :op :write-string
                  :args (:path #P"/tmp/x" :content "…")))
```

## Memory (Phase 7) & trace (Phase 6)

Unchanged: multilevel memory + separate persistence; deliberative traces for
`gp-explain`.

## Dependency policy

ANSI CL + ASDF + UIOP. Tests: FiveAM (adapter tests use temp directories only).
