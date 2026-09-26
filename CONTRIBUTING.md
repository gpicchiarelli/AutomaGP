# Contribuire a AUTOMA GP

AUTOMA GP è un agente di IA simbolica per il proprio computer: software
libero, senza scopo di lucro, in Common Lisp (SBCL). Contributi in italiano
o in inglese sono benvenuti.

A good change keeps that promise checkable. The system loads, the tests pass,
and the docs stay faithful to what the code can do. The master prompt is
`docs/PROMPT.md`. The phases are `ROADMAP.md`.

## Principles

1. **Correctness → clarity → testability → performance** — in that order.
2. Idiomatic ANSI Common Lisp. Prefer standard CL + UIOP. Do not invent
   Quicklisp libraries; verify availability before proposing a dependency.
3. CLOS only where it earns its keep; simple data stays as lists/structs.
4. Never claim unimplemented capabilities. Name the roadmap phase when the
   work is still ahead.
5. Do not add a conversational product surface, a planner shortcut, or an
   operating-system adapter unless you are advancing that roadmap phase
   with tests.

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
