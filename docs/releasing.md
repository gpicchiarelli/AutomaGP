# Releasing

One version per increment. The number lives in two files that are kept
in step, `version.lisp` and `version.lisp-expr`, and every version has an
entry in `CHANGELOG.md`. The git history shows this rhythm: each commit
that changes behaviour bumps the version and adds the changelog entry in
the same commit.

## Steps

1. Bump `version.lisp` and `version.lisp-expr` to the same `X.Y.Z`.
2. Add the entry at the top of `CHANGELOG.md` as
   `## [X.Y.Z] — YYYY-MM-DD` with `### Added`, `### Changed`, or
   `### Fixed` subsections. State what now holds and what still does not.
3. Add the increment to `ROADMAP.md` when it is more than a fix.
4. Update `CITATION.cff` (`version` and `date-released`).
5. Run `make test` and `make lint`. Commit with the code that justifies
   the bump.
6. Merge to `main` and wait for the CI, Lint, and CodeQL workflows.
7. Tag and push:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

## What the Release workflow does

`.github/workflows/release.yml` runs on any `v*` tag:

- runs `./scripts/run-tests.sh` on Ubuntu first;
- fails when `vX.Y.Z` does not equal the string in `version.lisp-expr`;
- extracts the matching `## [X.Y.Z]` section of `CHANGELOG.md`;
- adds GitHub's generated notes from merged pull requests;
- builds `automa-gp-X.Y.Z.tar.gz` with `git archive` and a `.sha256`
  beside it;
- creates the release `AUTOMA GP X.Y.Z`, or updates it when the tag was
  re-pushed.

Nothing is published to Quicklisp or any package index; the GitHub
Release and the tag are the artefacts.

## Version numbers

The project is pre-1.0. Every release so far, from 0.1.0 to the current
one, has advanced the minor number and left the patch at zero: one
tested increment, one version. A change to the public API or to a
persisted format is labelled `breaking-change` on its pull request and
is called out in the changelog entry.
