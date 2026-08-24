#!/bin/sh
# Package the VS Code extension as a .vsix.
#
# The extension needs the spec data and the checker bundle alongside it, so
# this builds the bundle, stages the data, and packages the result.
#
# Requires @vscode/vsce:  npm install -g @vscode/vsce
set -eu
cd "$(dirname "$0")/.."

if ! command -v vsce >/dev/null 2>&1; then
  echo "vsce not found. Install it with:  npm install -g @vscode/vsce" >&2
  exit 1
fi

echo "building the checker bundle..."
dune build editor/vscode/media/n88basic-check.js

# The extension reads keywords and clauses at run time for hover and
# completion, so they ship inside the package rather than being read from a
# checkout that will not exist on the installing machine.
echo "staging spec data..."
mkdir -p editor/vscode/spec
cp -f spec/keywords.json spec/clauses.json editor/vscode/spec/

cd editor/vscode
vsce package --out ../../n88basic.vsix
cd ../..

echo
echo "packaged n88basic.vsix"
echo "install it with:  code --install-extension n88basic.vsix"
