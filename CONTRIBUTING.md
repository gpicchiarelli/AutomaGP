# Contributing to AUTOMA GP

AUTOMA GP is a **context-centric symbolic deliberative automaton** in Common
Lisp (SBCL / macOS). It is not a chatbot. Contributions should respect the
master prompt in `docs/PROMPT.md` and the incremental phases in `ROADMAP.md`.

## Principles

1. **Correctness → clarity → testability → performance** — in that order.
2. Idiomatic ANSI Common Lisp. Prefer standard CL + UIOP. Do not invent
   Quicklisp libraries; verify availability before proposing a dependency.
3. CLOS only where it earns its keep; simple data stays as lists/structs.
4. Never claim unimplemented capabilities. Mark Phase 2+ work explicitly.
5. No chatbot UI, no premature planner/MEA/web adapter work unless you are
   advancing the matching roadmap phase with tests.

## Development loop

1. Load in SLIME / SLY (see README).
2. Change one significant component.
3. Add or extend FiveAM tests under `tests/`.
4. Run `./scripts/run-tests.sh` (or the REPL recipe in the README).
5. Document limits of what you changed.

## Style

- Package `automa-gp` for public Phase 1 API; keep internals in the same
  package for now (no deep package graph until needed).
- Export only the REPL / public API; keep helpers unexported when possible.
- Prefer readable symbolic lists for facts: `(power-state interface-01 on)`.
- Variables in patterns use symbols whose names start with `?` (e.g. `?x`).

## Pull requests

- One focused change per PR when possible.
- Update `CHANGELOG.md` under `[Unreleased]` or the next version section.
- Do not add large unused frameworks or web stacks.

## License

By contributing you agree that your contributions are licensed under the
BSD-2-Clause license in `LICENSE` (Copyright Giacomo Picchiarelli, 2026).
