# FAQ

Answers are taken from the code as it is today. Function names refer to
the `automa-gp` package; file paths are relative to the repository root.

## What do I need to install?

SBCL and Quicklisp. On macOS `brew install sbcl`; on Debian or Ubuntu
`apt install sbcl`. Install Quicklisp with the
[official installer](https://www.quicklisp.org/beta/). The scripts in
`scripts/` load the checkout they live in and change nothing outside it.
For `(ql:quickload :automa-gp)` from your own REPL, link the checkout once
with `ln -sfn "$PWD" ~/quicklisp/local-projects/automa-gp`. Nothing is
installed globally. `make test` and `make load` wrap the same steps;
`Dockerfile` and `.devcontainer/` give the same environment in a container.

## How do I run the tests?

`./scripts/run-tests.sh`, or `make test`. It loads `automa-gp/tests`
through Quicklisp and exits non-zero when a FiveAM check fails. From a
REPL, `(asdf:test-system :automa-gp)` runs the same suite.

## What is the difference between `gp-simulate` and `gp-run`?

`gp-simulate` sets the context mode to `:simulate` and applies the plan to
a copy of the facts. The live context is untouched and adapters are never
called. `gp-run` sets the mode to `:execute` and applies the effects to
the live facts. Both record an episode by default. Only `gp-run` updates
the score of a procedure reused from the archive. Irreversible or
high-risk operators stop `gp-run` unless it is called with `:confirm t`
or the function in `*execution-confirm*` allows them.

## Can a plan touch my computer?

Not by default. `gp-run` changes symbolic facts only. Three things must
hold before an adapter runs: the operator carries an `:external` spec in
its meta, the execute asks for adapters, and the facts still support the
action at execute time. Adapters are requested with
`(gp-run :adapters t)` for one execute, with `(gp-adapters t)` for the
session, or with `(gp-policy :adapters t)` inside an autonomous cycle.
`plan-external-actions` lists what a plan would hand to an adapter before
anything runs; an execute refuses before any fact changes when those
actions no longer ground the same way or the facts no longer support
them. Simulation never reaches an adapter.

## What is persisted, and where?

Two things, both as readable s-expressions in `.agp` files (AutomaGP).

- The procedure archive is written to `~/.automa-gp/procedure-archive.agp`
  when `gp-remember-procedure` stores a plan or a score changes, and it is
  read back the first time the archive is consulted. An older
  `procedure-archive.sexp` in the same directory is still loaded if the
  `.agp` file is missing. `*procedure-archive-path*`,
  `*procedure-archive-autosave*` and `*procedure-archive-autoload*` in
  `memory/procedural.lisp` control this.
- A snapshot bundle is written only when you ask for it: `(gp-save path)`
  stores the current context plus knowledge, episodic, and procedural
  memory; `(gp-load path)` restores it. Paths without a type get `.agp`.
  An explicit path (including a legacy `.sexp`) still opens as given.
  `gp-save-context` and `gp-load-context` handle the context alone.

Nothing else is written outside the repository. `gp-reset` keeps
knowledge and procedural memory, and `gp-clear-memory` drops them from
the session only; the archive file stays on disk.

## Which port does the web console use, and is it reachable from outside?

`./scripts/run-web.sh` starts Hunchentoot on `http://127.0.0.1:47391/`.
Set `AUTOMA_GP_WEB_PORT` to change the port, or call
`(automa-gp/web:start-web :port N)` from a REPL. The server binds
`127.0.0.1` and has no authentication; it is meant for the same machine.

## Does it run on Linux or FreeBSD?

The core, the tests, and the web console do. CI runs the suite on Ubuntu,
macOS, and FreeBSD 14.x. The `macos` adapter (`open`, `hostname`,
`uname`), the Terminal.app screen look through `osascript`, and the
Swift Workbench need a Mac.

## How do I build the macOS Workbench?

`make workbench`, or `cd macos/AutomaGPWorkbench && swift build -c release`.
It is a SwiftPM app for macOS 13 or later and needs the Xcode command line
tools. Start the web console first: the Workbench talks to
`http://127.0.0.1:47391/`.

## Which version am I running?

`automa-gp:*version*` in the REPL. The same string sits in
`version.lisp-expr`, which ASDF reads for the system version. One entry
per version is in [`CHANGELOG.md`](../CHANGELOG.md).
