#!/bin/sh
# Package the VS Code extension as a .vsix.
#
# The extension needs the spec data and the checker bundle alongside it, so
# this builds the bundle, stages the data, and packages the result.
#
# Requires @vscode/vsce:  npm install -g @vscode/vsce
set -eu
cd "$(dirname "$0")/.."
. "$(dirname "$0")/lib/activate-opam-switch.sh"

# vsce is the one genuinely optional dependency here. If it is missing, hand
# the job to Docker rather than to a global npm install -- someone who wants a
# .vsix should not have to install a publishing tool to get one.
if ! command -v vsce >/dev/null 2>&1; then
  if command -v docker >/dev/null 2>&1; then
    echo "vsce is not installed -- packaging in Docker instead."
    exec ./scripts/package-extension-in-docker.sh
  fi
  echo "Packaging the extension needs either vsce or Docker:" >&2
  echo "    npm install -g @vscode/vsce" >&2
  echo "or install Docker and this script will do it for you." >&2
  exit 1
fi

# A full `dune build`, not just this one target: the bundle's rule is
# (mode promote), and the committed copy is refreshed only by a build that
# actually runs it. It had gone stale once already, shipping the extension a
# checker older than the one the browser console used.
echo "  building the checker bundle..."
dune build

# The extension reads keywords and clauses at run time for hover and
# completion, so they ship inside the package rather than being read from a
# checkout that will not exist on the installing machine.
echo "  staging spec data..."
mkdir -p editor/vscode/spec
cp -f spec/keywords.json spec/clauses.json editor/vscode/spec/

cd editor/vscode
vsce package --out ../../n88basic.vsix
cd ../..

echo
echo "  packaged n88basic.vsix ($(wc -c < n88basic.vsix) bytes)"
echo "  install it with:  code --install-extension n88basic.vsix"
