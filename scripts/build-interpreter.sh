#!/bin/sh
# Build the interpreter and the editor's checker bundle.
#
# Produces:
#   _build/default/bin/main.exe            the n88 interpreter
#   editor/vscode/media/n88basic-check.js  the checker the extension runs
set -eu
cd "$(dirname "$0")/.."
. "$(dirname "$0")/lib/activate-opam-switch.sh"

dune build "$@"
echo "built  $(pwd)/_build/default/bin/main.exe"
