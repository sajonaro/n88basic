#!/bin/sh
# Build the interpreter and the editor's checker bundle.
#
# Produces:
#   _build/default/bin/main.exe            the n88 interpreter
#   editor/vscode/media/n88basic-check.js  the checker the extension runs
set -eu
cd "$(dirname "$0")/.."

if ! command -v dune >/dev/null 2>&1; then
  echo "dune not found. If this project has a local opam switch, run:" >&2
  echo "    eval \$(opam env --switch=. --set-switch)" >&2
  exit 1
fi

dune build "$@"
echo "built  $(pwd)/_build/default/bin/main.exe"
