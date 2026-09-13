#!/bin/sh
# Install the interpreter as `n88` on the PATH.
#
#   scripts/install-from-source.sh              installs to ~/.local/bin
#   scripts/install-from-source.sh /usr/local   installs to /usr/local/bin
set -eu
cd "$(dirname "$0")/.."
. "$(dirname "$0")/lib/activate-opam-switch.sh"

prefix="${1:-$HOME/.local}"
bindir="$prefix/bin"

dune build --profile release bin/main.exe
mkdir -p "$bindir"
cp -f _build/default/bin/main.exe "$bindir/n88"
chmod +x "$bindir/n88"

echo "installed $bindir/n88"
case ":$PATH:" in
  *":$bindir:"*) ;;
  *) echo "note: $bindir is not on your PATH" >&2 ;;
esac
