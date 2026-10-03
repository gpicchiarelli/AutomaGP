# Contributing to AUTOMA GP

AUTOMA GP è un agente di IA simbolica per il proprio computer: software
libero, senza scopo di lucro, in Common Lisp (SBCL). Contributi in italiano
o in inglese sono benvenuti.

A good change keeps one promise checkable: the system loads, the tests
pass, and the docs describe what the code does today. The master prompt
is [`docs/PROMPT.md`](docs/PROMPT.md); the phases and later increments are
in [`ROADMAP.md`](ROADMAP.md); the detailed behavioural contract is
[`docs/architecture.md`](docs/architecture.md).

## Principles

1. Correctness, then clarity, then testability, then performance.
2. Idiomatic ANSI Common Lisp. Prefer the standard plus UIOP. Check that a
   library exists on Quicklisp before proposing it as a dependency.
3. CLOS where it earns its keep. Simple data stays as lists and structs.
4. Announce a capability only when it is loadable and tested. Name the
   roadmap item when the work is still ahead.
5. A conversational surface, a planner shortcut, or a new operating-system
   adapter needs a roadmap item and tests of its own.

## Setting up

You need SBCL and Quicklisp. Nothing else is installed globally.

```sh
brew install sbcl                      # macOS; on Debian/Ubuntu: apt install sbcl
                                       # FreeBSD: pkg install sbcl bash curl git ca_root_nss
curl -fsSL https://beta.quicklisp.org/quicklisp.lisp -o /tmp/quicklisp.lisp
sbcl --non-interactive --load /tmp/quicklisp.lisp \
     --eval '(quicklisp-quickstart:install)' --eval '(ql:add-to-init-file)'
ln -sfn "$PWD" ~/quicklisp/local-projects/automa-gp
```

The symlink is for your own REPL. `./scripts/run-tests.sh` does not need
it: it registers the checkout it lives in with ASDF, runs the FiveAM
suite, and exits non-zero when a test fails, so a second clone or a git
worktree always tests itself. `make web-test` starts the console on a
loopback port and drives it over TCP; it needs Hunchentoot, which is why it
is a system of its own. `./scripts/run-web.sh` starts the Hunchentoot
console. The macOS Workbench builds with `swift build -c release` inside
`macos/AutomaGPWorkbench` (Xcode 15 or newer, no signing).

## Development loop

1. Load the system in SLIME or SLY with `(ql:quickload :automa-gp)`.
2. Change one component at a time.
3. Add or extend FiveAM tests under `tests/`.
4. Run `./scripts/run-tests.sh`.
5. State the limits of what you changed in the changelog entry and, when
   the behaviour is user-facing, in `docs/architecture.md`.

## Continuous integration

Every push to `main` and every pull request runs on GitHub Actions:

| Workflow | What it checks |
| --- | --- |
| **CI** (`ci.yml`) | `./scripts/run-tests.sh` on Ubuntu and macOS with a fresh SBCL + Quicklisp, plus a FreeBSD 14.x job (`test-freebsd` via `vmactions/freebsd-vm`). |
| **Lint** (`lint.yml`) | markdownlint, yamllint, actionlint, shellcheck on `scripts/*.sh`, and a from-scratch `asdf:load-system` of `automa-gp`, `automa-gp/web`, `automa-gp/tests` that fails on compiler warnings. |
| **macOS Workbench** (`macos-workbench.yml`) | `swift build -c release` of the Workbench, only when `macos/**` changes. |
| **CodeQL** (`codeql.yml`) | Static analysis of the Swift sources and of the workflows themselves. Common Lisp is not supported by CodeQL. |
| **Release** (`release.yml`) | On a `vX.Y.Z` tag: runs the suite, checks the tag against `version.lisp-expr`, and publishes a GitHub Release with the matching `CHANGELOG.md` section plus a source tarball. |

Dependabot opens a grouped pull request each Monday for the actions the
workflows use. Run the same checks locally before pushing:

```sh
./scripts/run-tests.sh
markdownlint-cli2 "**/*.md"            # brew install markdownlint-cli2
yamllint -c .yamllint.yaml .github     # brew install yamllint
actionlint                             # brew install actionlint
shellcheck -S warning scripts/*.sh     # brew install shellcheck
```

## Commits

- Write the subject as a sentence that states what now holds, in the
  present tense, as the git log already does: *"A refused execute leaves
  the mode unchanged."*
- One logical change per commit. Version bump, changelog entry, and the
  code that justifies them belong to the same commit.
- Reference issues in the body (`Closes #12`), not in the subject.
- Do not commit fasl files, snapshots, `.build/`, or anything under
  `~/quicklisp`; `.gitignore` already covers them.

## Releasing

1. Bump `version.lisp` and `version.lisp-expr` together and add the entry
   to `CHANGELOG.md`.
2. Merge to `main` and wait for CI to pass.
3. Tag and push: `git tag v0.146.0 && git push origin v0.146.0`.
   The Release workflow does the rest.

## Style

- Package `automa-gp` holds the public API. Internals stay in the same
  package; a deeper package graph comes only when it is needed.
- Export the REPL and public API only. Keep helpers unexported.
- Facts are readable symbolic lists: `(power-state interface-01 on)`.
- Pattern variables are symbols whose names start with `?`, such as `?x`.

## Pull requests

- One focused change per pull request.
- Bump `version.lisp` and `version.lisp-expr` together, add the matching
  entry at the top of `CHANGELOG.md`, and add the increment to
  `ROADMAP.md`.
- Keep the README faithful. If a sentence there stops being true, change
  the sentence in the same pull request.
- Leave large frameworks and second web stacks out.

## License

By contributing you agree that your contributions are licensed under the
BSD 2-Clause license in [`LICENSE`](LICENSE). Copyright Giacomo
Picchiarelli, 2026.
