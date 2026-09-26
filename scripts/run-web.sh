#!/usr/bin/env bash
# Start the AUTOMA GP operator console (Hunchentoot).
# Default: http://127.0.0.1:47391/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
PORT="${AUTOMA_GP_WEB_PORT:-47391}"

if ! command -v sbcl >/dev/null 2>&1; then
  echo "SBCL not found on PATH" >&2
  exit 1
fi

QL_SETUP="${HOME}/quicklisp/setup.lisp"
if [[ ! -f "$QL_SETUP" ]]; then
  echo "Quicklisp not found at $QL_SETUP" >&2
  exit 1
fi

mkdir -p "${HOME}/quicklisp/local-projects"
ln -sfn "$ROOT" "${HOME}/quicklisp/local-projects/automa-gp"

exec sbcl --noinform --load "$QL_SETUP" --eval "(ql:quickload :automa-gp/web :silent t)" --eval "(automa-gp/web:start-web :port ${PORT})" --eval "(format t \"~&Serving until Ctrl-C. URL: ~A~%\" (automa-gp/web:web-url))" --eval "(handler-case (loop (sleep 3600)) (sb-sys:interactive-interrupt () (automa-gp/web:stop-web) (uiop:quit 0)))"
