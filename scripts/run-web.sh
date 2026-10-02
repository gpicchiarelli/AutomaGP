#!/usr/bin/env bash
# Start the AUTOMA GP operator console (Hunchentoot).
# Default: http://127.0.0.1:47391/ — set AUTOMA_GP_WEB_PORT to change the port.
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

# --non-interactive: a failure to load or start ends the process with a
# non-zero status instead of waiting in the debugger for input.
exec sbcl --noinform --non-interactive --load "$QL_SETUP" --load "$ROOT/scripts/run-web.lisp"
