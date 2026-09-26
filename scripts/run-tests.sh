#!/usr/bin/env bash
# Run the AUTOMA GP test suite with SBCL + Quicklisp.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

if ! command -v sbcl >/dev/null 2>&1; then
  echo "SBCL not found on PATH" >&2
  exit 1
fi

QL_SETUP="${HOME}/quicklisp/setup.lisp"
if [[ ! -f "$QL_SETUP" ]]; then
  echo "Quicklisp not found at $QL_SETUP" >&2
  echo "Install Quicklisp, then symlink this repo into ~/quicklisp/local-projects/" >&2
  exit 1
fi

# Ensure local-projects sees this tree
mkdir -p "${HOME}/quicklisp/local-projects"
ln -sfn "$ROOT" "${HOME}/quicklisp/local-projects/automa-gp"

exec sbcl --non-interactive --load "$ROOT/scripts/run-tests.lisp"
