#!/bin/sh
# Install the VS Code extension without packaging it, by copying the
# directory into the editor's extensions folder.
#
# Prefer scripts/package-extension.sh and a .vsix where vsce is available:
# a copied directory has no version metadata, so the editor cannot tell an
# updated copy from a stale one.
set -eu
cd "$(dirname "$0")/.."

dest="${1:-$HOME/.vscode/extensions/n88basic.n88basic-0.1.0}"

dune build editor/vscode/media/n88basic-check.js

rm -rf "$dest"
mkdir -p "$dest"
cp -R editor/vscode/. "$dest/"
rm -rf "$dest/tools" "$dest/media/dune"
mkdir -p "$dest/spec"
cp -f spec/keywords.json spec/clauses.json "$dest/spec/"

echo "installed to $dest"
echo "reload the editor window to pick it up"
