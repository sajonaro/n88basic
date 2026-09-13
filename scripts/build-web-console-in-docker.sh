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

echo "  no js_of_ocaml here, so Docker builds it (first run compiles a toolchain"
echo "  and takes a few minutes; later runs are cached and quick)"
docker build --target web-assets -t "$TAG" .

# `docker build --output` would be tidier but needs buildx, and the classic
# builder is still what many machines have. A stopped container works on both.
cid=$(docker create "$TAG" /bin/true)
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
mkdir -p "$OUT"
for f in index.html console.css examples.js main.bc.js n88basic-check.js; do
  docker cp "$cid:/web/$f" "$OUT/$f"
done

# This list, the one in build-web-console.sh, and web/dune's alias are three
# spellings of one set. They have now drifted twice -- n88basic-check.js was
# added to the alias and to neither copier, so BOTH routes shipped a console
# with no diagnostics and nothing failed, because a page loads fine without a
# script it never calls. Ask the page what it needs instead of trusting a list.
missing=""
for f in $(sed -n 's/.*<\(script\|link\)[^>]*\(src\|href\)="\([^"]*\)".*/\3/p' "$OUT/index.html"); do
  case "$f" in http*|//*) continue ;; esac
  [ -f "$OUT/$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
  echo "index.html asks for files this build did not produce:$missing" >&2
  echo "Add them to the loop in $0 and to the web-assets stage in Dockerfile." >&2
  exit 1
fi

echo "Console built into $OUT:"
ls -l "$OUT" | awk 'NR>1 {printf "  %-16s %8s bytes\n", $NF, $5}'
