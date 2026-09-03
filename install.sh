#!/bin/sh
# Install or upgrade n88, the N88-BASIC(86) interpreter.
#
#   curl -fsSL https://raw.githubusercontent.com/sajonaro/n88basic/main/install.sh | sh
#
# Run it again to upgrade. THAT IS THE POINT: the same command every time, so
# there is nothing separate to remember and nothing to document as "upgrading".
# It prints what it replaced -- "0.1.3 -> 0.1.4" -- because a version that
# changed silently is the problem this exists to solve. Upgrading was never
# hard; noticing you needed to was.
#
#   PREFIX=/usr/local sh install.sh     install somewhere else
#   VERSION=v0.1.3    sh install.sh     pin a specific release
#
# It never runs itself on a schedule and never upgrades anything but n88.
set -eu

REPO="sajonaro/n88basic"
ASSET="n88-linux-x86_64"
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"
VERSION="${VERSION:-latest}"

case "$(uname -s)" in
  Linux) ;;
  *)
    echo "This installer has a Linux build only ($(uname -s) detected)." >&2
    echo "Build from source, or use the container:" >&2
    echo "  docker run --rm -v \"\$PWD:/work\" ghcr.io/$REPO prog.bas" >&2
    exit 1
    ;;
esac

command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }

# What is already at the path we are about to overwrite -- NOT whatever `n88`
# resolves to on PATH, which may be a different install entirely. The closing
# line exists to be believed, so it has to name the file it replaced.
before=""
if [ -x "$BINDIR/n88" ]; then
  before="$("$BINDIR/n88" --version 2>/dev/null || echo unknown)"
fi

if [ "$VERSION" = latest ]; then
  url="https://github.com/$REPO/releases/latest/download/$ASSET"
else
  url="https://github.com/$REPO/releases/download/$VERSION/$ASSET"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Fetching $url"
curl -fsSL -o "$tmp/n88" "$url"
chmod +x "$tmp/n88"

# Check it runs BEFORE replacing anything. A download that arrived truncated,
# or an asset for the wrong libc, must not become the n88 on someone's PATH.
after="$("$tmp/n88" --version)" || { echo "The downloaded binary does not run." >&2; exit 1; }

mkdir -p "$BINDIR"
mv "$tmp/n88" "$BINDIR/n88"

if [ -z "$before" ]; then
  echo "Installed n88 $after to $BINDIR/n88"
elif [ "$before" = "$after" ]; then
  echo "n88 $after was already current ($BINDIR/n88)"
else
  echo "n88 $before -> $after ($BINDIR/n88)"
fi

case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) echo "Note: $BINDIR is not on your PATH." ;;
esac
