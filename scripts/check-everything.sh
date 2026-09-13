#!/bin/sh
# check-everything.sh -- run every gate there is.
#
# ONE command, and it is the same one CI runs and the same one a release runs:
# the gate-* stages in the Dockerfile. This script used to be its own list of
# checks, .github/workflows/ci.yml was another, and the Makefile's test target
# was a third -- six, thirteen and four, all called "everything". Whichever you
# ran, you did not know what you had run. The Dockerfile is the list now, and
# this is a way to type it.
#
#   scripts/check-everything.sh          every gate
#   make ci                              the same thing
#
# Needs nothing but Docker: the toolchain, node, python and the rasteriser all
# live in the image.
set -eu
cd "$(dirname "$0")/.."

if ! command -v docker >/dev/null 2>&1; then
  echo "Every gate runs in Docker, and docker is not on your PATH." >&2
  echo "For the fast inner loop without it: make test (the suites only)." >&2
  exit 1
fi

# --progress=plain because the default renderer collapses each stage to a
# spinner, and the output of these checks IS the point -- how many conformance
# cases matched, which clauses are uncited. A gate you cannot read the result
# of is a gate you are trusting rather than checking.
exec docker build --target gates --progress=plain -t n88basic-gates .
