#!/usr/bin/env bash
# Run the AUTOMA GP test suite with SBCL + Quicklisp.
# The checkout this script lives in is the one under test.
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
  echo "Install Quicklisp first; see CONTRIBUTING.md." >&2
  exit 1
fi

exec sbcl --non-interactive --load "$QL_SETUP" --load "$ROOT/scripts/run-tests.lisp"
