#!/bin/sh
# build-web.sh -- build the browser console, and say what actually went wrong.
#
# WHY THIS IS A SCRIPT. The Makefile used to run `dune build @web/web
# 2>/dev/null` and, on any failure at all, print "the web console needs
# js_of_ocaml". That message can only say one thing, so it said it when the
# real fault was `dune: command not found` -- sending someone to install a
# library they already had. A diagnostic that cannot be wrong about the cause
# is a diagnostic that is wrong whenever the cause is different.
#
# So: find dune, check the prerequisite that is actually optional, and
# otherwise show the build's own error rather than a guess about it.
set -eu
cd "$(dirname "$0")/.."
. "$(dirname "$0")/lib/activate-opam-switch.sh"

# js_of_ocaml is the one genuinely optional dependency: web/dune marks the
# executable (optional), so a tree without it still builds and tests the
# interpreter. Check it by name instead of inferring it from a failure -- and
# if it is missing, offer Docker rather than a toolchain lecture, because
# someone who only wants to look at the console should not have to install a
# compiler back end to do it.
if ! ocamlfind list 2>/dev/null | grep -q '^js_of_ocaml '; then
  if command -v docker >/dev/null 2>&1; then
    echo "js_of_ocaml is not installed -- building the console in Docker instead."
    exec ./scripts/build-web-console-in-docker.sh
  fi
  echo "The browser console needs js_of_ocaml:" >&2
  echo "    opam install js_of_ocaml js_of_ocaml-compiler" >&2
  echo "or install Docker and this script will build it for you." >&2
  exit 1
fi

# Anything else: let the build speak for itself.
dune build @web/web
node tools/check_web.js

# The console is assembled in ./web-console/ whichever route built it, so
# `make wc` serves one place and nothing has to read out of _build -- which is
# dune's, and is not ours to rummage in or write to.
mkdir -p web-console
for f in index.html console.css examples.js main.bc.js; do
  cp "_build/default/web/$f" "web-console/$f"
done
echo "Console built into web-console/"

# Optional, and says so: comparing a vector rendering against its raster needs
# rsvg-convert and Pillow, which are the only things in this repository's
# tooling that are not either the OCaml switch or the Python standard library.
if python3 -c 'import PIL' 2>/dev/null && command -v rsvg-convert >/dev/null 2>&1; then
  python3 tools/check_svg.py
else
  echo "Skipping the SVG geometry check: it needs rsvg-convert and Pillow."
fi
