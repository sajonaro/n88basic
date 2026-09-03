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
#   sh install.sh --uninstall           remove it again
#
# It never runs itself on a schedule and never upgrades anything but n88.
#
# ON UNINSTALLING. n88 leaves no hidden state -- no ~/.config, no cache, no
# state directory -- so removing it is removing files you can see. But the
# binary is not the only thing a user ends up with: there is usually a VSCode
# extension, sometimes container images, sometimes an editor setting. This
# script removes what IT placed and REPORTS the rest with the exact command
# for each, because an uninstaller that silently removed one of six artifacts
# would read as "uninstalled" and leave an extension driving a missing
# interpreter -- which is the confusing failure the version check exists to
# prevent.
set -eu

REPO="sajonaro/n88basic"
ASSET="n88-linux-x86_64"
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"
VERSION="${VERSION:-latest}"
UNINSTALL=no
ASSUME_YES=no
for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=yes ;;
    -y|--yes)    ASSUME_YES=yes ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# What else is on this machine that came with n88. Read-only: it looks, and
# prints commands for the user to run, and does not run them.
report_the_rest() {
  echo
  echo "n88 also usually comes with things this script did not place:"
  if command -v code >/dev/null 2>&1; then
    code --list-extensions 2>/dev/null | grep -i n88basic | while read -r ext; do
      echo "  extension $ext"
      echo "    code --uninstall-extension $ext"
    done
  else
    echo "  a VSCode extension, if you installed one:"
    echo "    code --uninstall-extension n88basic.n88basic"
  fi
  if command -v docker >/dev/null 2>&1; then
    imgs=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep n88basic || true)
    if [ -n "$imgs" ]; then
      echo "  container images:"
      echo "$imgs" | sed 's/^/    /'
      echo "    docker rmi $(echo "$imgs" | tr '\n' ' ')"
    fi
  fi
  echo "  a \"remote.extensionKind\" override in VSCode settings.json, if you added"
  echo "  one as a workaround before v0.1.4 -- delete the \"n88basic.n88basic\" key."
  echo
  echo "There is nothing else: n88 writes no config, cache or state directory."
}

if [ "$UNINSTALL" = yes ]; then
  target="$BINDIR/n88"
  if [ ! -e "$target" ]; then
    echo "No n88 at $target."
    other=$(command -v n88 2>/dev/null || true)
    [ -n "$other" ] && echo "There is one at $other -- rerun with PREFIX set to its prefix."
    report_the_rest
    exit 0
  fi
  case "$target" in
    */_opam/*|*/.opam/*)
      echo "$target is inside an opam switch. Removing it would corrupt opam's view." >&2
      echo "Use:  opam remove n88basic" >&2
      exit 1 ;;
  esac
  echo "Will remove: $target ($("$target" --version 2>/dev/null || echo unknown))"
  if [ "$ASSUME_YES" != yes ]; then
    printf "Proceed? [y/N] "
    read -r reply </dev/tty || reply=n
    case "$reply" in y|Y|yes|YES) ;; *) echo "Cancelled."; exit 1 ;; esac
  fi
  rm -f "$target"
  echo "Removed $target"
  report_the_rest
  exit 0
fi

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
