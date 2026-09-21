#!/bin/sh
# package-extension-in-docker.sh -- build the .vsix with nothing but Docker.
#
# vsce is an npm tool. Requiring `npm install -g @vscode/vsce` before anyone
# could produce a package put a second global install in the way, which is the
# same objection that moved the web console and the CI gates into stages. The
# Dockerfile owns that problem; this borrows it.
#
# The package lands in ./n88basic.vsix, the same place and name the native
# route produces, so nothing downstream has to know which one ran.
set -eu
cd "$(dirname "$0")/.."

TAG=n88basic-vsix:local
OUT=n88basic.vsix

command -v docker >/dev/null 2>&1 || {
  echo "This packages the extension with Docker, and docker is not on your PATH." >&2
  echo "The other route is:  npm install -g @vscode/vsce  &&  make vsix" >&2
  exit 1
}

echo "  packaging the extension in Docker (no npm needed on this machine)"
echo "  first run installs vsce and takes a minute; later runs are cached"
docker build --target vsix -t "$TAG" .

# `docker build --output` would be tidier but needs buildx, and the classic
# builder is still what many machines have. A stopped container works on both.
cid=$(docker create "$TAG" /bin/true)
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
docker cp "$cid:/n88basic.vsix" "$OUT"

echo
echo "  packaged $(pwd)/$OUT ($(wc -c < "$OUT") bytes)"
echo "  install it with:  code --install-extension $(pwd)/$OUT"
