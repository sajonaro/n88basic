#!/bin/sh
# build-web-docker.sh -- build the browser console with nothing but Docker.
#
# The console needs js_of_ocaml, which is a real toolchain to set up for
# someone who only wants to look at the thing. The Dockerfile has a stage that
# owns that problem, so this borrows it: build the stage, copy the four static
# files out, done. No OCaml on the host, no opam switch, no compiler back end.
#
# Files land in ./web-console/, NOT in _build. Writing into _build looked
# convenient and corrupts dune: that directory is dune's, it tracks the digest
# of everything in it, and it generates bundle.mli and main.mli there. Dropping
# files in with `docker cp` left dune hunting for web/main.mli in the SOURCE
# tree, where it has never existed, and the only recovery was `dune clean`.
set -eu
cd "$(dirname "$0")/.."

TAG=n88basic-web-assets:local
OUT=web-console

echo "Building the console in Docker (no OCaml needed on this machine)..."
docker build --target web-assets -t "$TAG" .

# `docker build --output` would be tidier but needs buildx, and the classic
# builder is still what many machines have. A stopped container works on both.
cid=$(docker create "$TAG" /bin/true)
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
mkdir -p "$OUT"
for f in index.html console.css examples.js main.bc.js; do
  docker cp "$cid:/web/$f" "$OUT/$f"
done

echo "Console built into $OUT:"
ls -l "$OUT" | awk 'NR>1 {printf "  %-16s %8s bytes\n", $NF, $5}'
