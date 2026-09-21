# n88basic: the interpreter as a container, and the whole pipeline that proves
# it works.
#
# ===========================================================================
# VERSIONS -- every version this pipeline depends on, in one place.
# Change them here and nowhere else.
# ===========================================================================
ARG ALPINE=alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc
ARG OPAM=ocaml/opam:alpine-ocaml-5.2@sha256:c57c07f193801e01f24f8f1c1b8da5bfec1db1058003df0bb558bebf71635de7

ARG DUNE=3.24.2
ARG ALCOTEST=1.9.1
ARG MENHIR=20260209
ARG JSOO=6.4.1

# Only for packaging the VS Code extension (.vsix); nothing else uses node here.
ARG NODE=node:22-alpine@sha256:b6f26b36c8ff49624cfdac716b8ea1138d606df02586a77d364bb5536a634f85

# Pinned by DIGEST, not just tag: `alpine:3.20` moves whenever a patch is cut,
# so a tag alone is a promise nobody keeps. The digest is the image these gates
# were actually proven against.
#
# THE APK PACKAGES BELOW ARE DELIBERATELY NOT PINNED, and that is not an
# oversight. Alpine's repositories are live rather than snapshotted: a branch
# keeps only the current patch of each package, so `bash=5.2.26-r0` builds
# today and fails outright the morning Alpine cuts -r1 -- a pin whose only
# effect is to break the build on a schedule nobody controls. What bounds them
# instead is the OPAM digest -- they are installed in THAT stage, not the
# ALPINE one, so it is that image whose branch fixes them. What resolved is
# recorded in /usr/share/n88basic/VERSIONS inside the image, so drift is
# visible even though it is not forbidden.
#
#   docker build -t n88basic .            everything, then the image
#   docker build --target gates .         everything, without the image
#   docker run --rm -v "$PWD:/work" n88basic prog.bas
#
# WHY THE PIPELINE LIVES HERE. There used to be three descriptions of "what
# must pass" -- .github/workflows/ci.yml, scripts/check-everything.sh and the
# Makefile's test target -- and they had drifted apart: thirteen checks, six,
# and four. Whichever one you ran, you did not know what you had run. So there
# is now one list, it is the `gate-*` stages below, and CI and the Makefile
# both do nothing but build them.
#
# Each gate is a stage that ends by touching /tmp/passed. The `gates` stage
# copies that marker out of every one of them, which is what forces them all
# to be built -- BuildKit skips a stage nothing depends on, so a gate that is
# not copied from is a gate that does not run. Adding a check means adding a
# stage AND a line in `gates`; forget the second and the first never runs,
# which is the one way this arrangement can fool you.
#
# The runtime image copies the gate list in. An image that did not pass cannot
# be built, and `cat /usr/share/n88basic/CHECKS` inside it says what it passed.
#
# They run in parallel and cache independently, so a change to spec/ re-runs
# the spec gates and leaves the OCaml ones alone.

# --- toolchain --------------------------------------------------------------
#
# Everything every gate needs, in one cached layer. python3 is here for the
# specification tooling and for checks that need an implementation this project
# did NOT write -- an inflater for raster/Zlib's output, a rasteriser for its
# SVG. Checking those against our own code would be checking nothing.
FROM $OPAM AS toolchain
ARG DUNE
ARG ALCOTEST
ARG MENHIR
ARG JSOO

# THE EXPENSIVE LAYER GOES FIRST. This compiles the OCaml toolchain from
# source, and it sat AFTER the apk line until adding one system package threw
# it away and rebuilt the lot -- three times in a row. The cheap, volatile list
# must not sit in front of the costly, stable one.
#
# menhir is a build dependency, not a test one: spec/grammar/dune runs it to
# prove the grammar has no conflicts.
RUN opam install -y \
      dune.$DUNE \
      alcotest.$ALCOTEST \
      menhir.$MENHIR \
      js_of_ocaml.$JSOO \
      js_of_ocaml-compiler.$JSOO

USER root
# bash: scripts/check-conformance.sh uses arrays and BASH_SOURCE. git: the
# invariant gate reads the index. nodejs: the JS build and the extension's
# tests. py3-pillow: the SVG geometry check AND the PNG round trip, which read
# back what this project encodes using somebody else's decoder. rsvg-convert:
# the second renderer the SVG output is compared against.
#
# Every one of these was, at some point, absent -- and the check that needed it
# SKIPPED rather than failed. That is why they are installed here instead of
# being probed for: a gate that quietly opts out is worse than no gate.
RUN apk add --no-cache bash git nodejs python3 py3-pillow rsvg-convert

# WORKDIR creates the directory as root even after USER, so the unprivileged
# build cannot write _build into it. Harmless under buildx, fatal under the
# classic builder -- make the ownership explicit rather than depend on which
# builder someone has.
RUN mkdir -p /src && chown opam:opam /src
USER opam
WORKDIR /src


# --- the shipped binary -----------------------------------------------------
#
# Only what the interpreter needs, so editing a test or the spec does not
# rebuild it.
FROM toolchain AS build
COPY --chown=opam:opam dune-project n88basic.opam ./
COPY --chown=opam:opam basic/  ./basic/
COPY --chown=opam:opam raster/ ./raster/
COPY --chown=opam:opam bin/    ./bin/
RUN opam exec -- dune build --profile release bin/main.exe

# --- everything, built once for the gates to share --------------------------
FROM toolchain AS built
COPY --chown=opam:opam dune-project n88basic.opam ./
COPY --chown=opam:opam basic/   ./basic/
COPY --chown=opam:opam raster/  ./raster/
COPY --chown=opam:opam bin/     ./bin/
COPY --chown=opam:opam web/     ./web/
COPY --chown=opam:opam editor/  ./editor/
COPY --chown=opam:opam test/    ./test/
COPY --chown=opam:opam tools/   ./tools/
COPY --chown=opam:opam scripts/ ./scripts/
COPY --chown=opam:opam spec/    ./spec/
RUN opam exec -- dune build

# What this build actually resolved to. The apk versions are not pinned (see
# the top of this file), so this is how they stay visible: it ships in the
# image next to the gate list. `|| true` throughout -- a version RECORD must
# never be the reason a build fails.
RUN { \
      echo "# what this build resolved to. pins are at the top of the Dockerfile."; \
      echo "builder-alpine  $(cat /etc/alpine-release 2>/dev/null || echo unknown)"; \
      echo "ocaml           $(opam exec -- ocamlc -version 2>/dev/null || echo unknown)"; \
      opam list --installed --short --columns=name,version \
        dune alcotest menhir js_of_ocaml js_of_ocaml-compiler 2>/dev/null; \
      apk list -I bash git nodejs python3 py3-pillow rsvg-convert 2>/dev/null \
        | awk '{print $1}' | sort; \
    } > /tmp/VERSIONS 2>/dev/null || true; cat /tmp/VERSIONS || true

# --- the gates --------------------------------------------------------------

FROM built AS gate-suites
RUN opam exec -- dune test && touch /tmp/passed

# dune test links the library and runs the cases in process. This runs the same
# corpus through the built EXECUTABLE, which is the only way the CLI's own
# layer -- argument handling, the stdout/stderr split, buffering -- is ever
# vetted against the spec.
FROM built AS gate-conformance
RUN bash scripts/check-conformance.sh /src/_build/default/bin/main.exe && touch /tmp/passed

# raster/Zlib writes zlib streams and has no decompressor, so a round trip
# through an inflater this project did not write is the only check there is.
FROM built AS gate-deflate
RUN python3 tools/check_deflate.py && touch /tmp/passed

# The SVG renderer is a second renderer over the same display list. This
# rasterises its output with rsvg-convert and compares where the ink landed.
FROM built AS gate-svg
RUN python3 tools/check_svg.py && touch /tmp/passed

# The browser build is a second HOST over the same libraries: the whole corpus
# again, through JavaScript, drawings compared byte for byte.
FROM built AS gate-web
RUN opam exec -- dune build @web/web && node tools/check_web.js && touch /tmp/passed

# The extension's pure logic under plain node, plus checks that a real n88
# accepts what the extension sends it. N88 points at the build so the second
# half actually runs -- without it those checks skip.
FROM built AS gate-extension
# `|| exit 1` rather than `set -e`, and that is not belt and braces. A compound
# command on the left of `&&` runs with errexit SUPPRESSED, so
# `for ...; done && touch /tmp/passed` takes its status from the LAST iteration
# alone: a failure in any earlier one is swallowed and the marker is written.
# This gate did exactly that -- it printed "manifest FAILED", carried on, and
# the build ended with "gates passed" and exit 0. A gate that cannot fail is
# worse than no gate, because it is believed.
RUN for t in editor/vscode/tools/test-*.js; do \
      echo "--- $t"; \
      N88=/src/_build/default/bin/main.exe node "$t" || exit 1; \
    done; \
    touch /tmp/passed

# Every clause cites a manual page, every implemented clause carries a
# conformance case, and the example programs still produce what they claim.
FROM built AS gate-spec
RUN python3 tools/check_spec.py \
 && python3 tools/coverage.py \
 && python3 tools/citation_coverage.py \
 && python3 tools/run_programs.py \
 && touch /tmp/passed

FROM built AS gate-release-rule
RUN python3 tools/test_check_version_bump.py && touch /tmp/passed

# The one defect class no fixture can see: a prompt that arrives after the
# answer. Capturing stdout is exactly the case where full buffering is
# correct, so this measures timing rather than bytes.
FROM built AS gate-flush
RUN sh tools/check_interactive_flush.sh && touch /tmp/passed

# The tripwires -- basic/ doing I/O, a manual scan tracked by git, a local path
# in the sources -- read the git index, so this stage is the one that gets the
# repository. It copies the whole context, so it is also the only stage whose
# cache a commit invalidates.
FROM built AS gate-invariants
COPY --chown=opam:opam . /src/
RUN sh scripts/check-invariants.sh && touch /tmp/passed

# --- the gate list ----------------------------------------------------------
#
# Every gate above must appear here or it is never built. This stage IS the
# definition of "checked".
FROM $ALPINE AS gates
COPY --from=gate-suites       /tmp/passed /passed/suites
COPY --from=gate-conformance  /tmp/passed /passed/conformance
COPY --from=gate-deflate      /tmp/passed /passed/deflate
COPY --from=gate-svg          /tmp/passed /passed/svg
COPY --from=gate-web          /tmp/passed /passed/web
COPY --from=gate-extension    /tmp/passed /passed/extension
COPY --from=gate-spec         /tmp/passed /passed/spec
COPY --from=gate-release-rule /tmp/passed /passed/release-rule
COPY --from=gate-flush        /tmp/passed /passed/flush
COPY --from=gate-invariants   /tmp/passed /passed/invariants
COPY --from=built /tmp/VERSIONS /VERSIONS
RUN ls /passed > /CHECKS && echo "gates passed:" && cat /CHECKS && \
    echo "built with:" && cat /VERSIONS

# --- the browser console ------------------------------------------------------
#
# Building the console needs js_of_ocaml, which is a real toolchain to set up
# for someone who only wants to look at the thing. This stage has it, so
# `make wc` can hand the whole job to Docker and the caller needs nothing but
# Docker. Deliberately NOT behind the gates: the whole point is to be quick for
# someone who only wants to see the page. gate-web is what vouches for it.
FROM built AS web
RUN opam exec -- dune build @web/web

# The built page and nothing else. A normal image rather than `FROM scratch`
# with --output, because --output needs buildx and the classic builder is still
# what many machines have.
#
# This list and web/dune's web alias are the same set spelled twice, and they
# have drifted before -- n88basic-check.js was added to one and not the other,
# and the console shipped without its checker.
FROM $ALPINE AS web-assets
COPY --from=web /src/_build/default/web/index.html        /web/
COPY --from=web /src/_build/default/web/console.css       /web/
COPY --from=web /src/_build/default/web/examples.js       /web/
COPY --from=web /src/_build/default/web/main.bc.js        /web/
COPY --from=web /src/_build/default/web/n88basic-check.js /web/

# --- the VS Code extension, packaged --------------------------------------
#
# `vsce` is an npm tool, and requiring `npm install -g @vscode/vsce` to get a
# .vsix put a second global install between someone and a build. It lives in a
# stage instead, so `make vsix` needs Docker and nothing else.
#
# A plain `dune build` here is what regenerates editor/vscode/media/
# n88basic-check.js: its rule is (mode promote), so the committed copy is only
# refreshed by a full build. It had already gone stale once -- the extension
# was shipping a checker without the token export the console had gained.
FROM built AS vsix-build
RUN opam exec -- dune build
# The extension reads keywords and clauses at RUN time for hover and
# completion, so they travel inside the package rather than being read from a
# checkout that will not exist on the installing machine.
RUN mkdir -p editor/vscode/spec \
 && cp -f spec/keywords.json spec/clauses.json editor/vscode/spec/

FROM $NODE AS vsix
ARG NODE
RUN npm install -g @vscode/vsce
COPY --from=vsix-build /src/editor/vscode /ext
WORKDIR /ext
# NOT --no-dependencies, which sounds right and is wrong: the vendored tree is
# committed, so nothing needs resolving -- but that flag makes vsce drop
# node_modules from the PACKAGE as well. It produced a 34-file .vsix against
# the native route's 410, with vscode-languageclient absent, which is the
# feature .vscodeignore exists to protect. Caught by diffing the two packages.
#
# --allow-missing-repository matches what .github/workflows/release.yml runs;
# the two must produce the same package or this route is not a rehearsal of
# the one that ships.
RUN vsce package --allow-missing-repository --out /n88basic.vsix \
 && ls -l /n88basic.vsix

# --- runtime ----------------------------------------------------------------
#
# The default target, so a plain `docker build .` runs every gate first. The
# image cannot be produced from a tree that failed one.
FROM $ALPINE AS runtime

LABEL org.opencontainers.image.title="n88basic"
LABEL org.opencontainers.image.description="Interpreter for N88-BASIC(86), the ROM BASIC of the NEC PC-9801"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.source="https://github.com/sajonaro/n88basic"

COPY --from=gates /CHECKS   /usr/share/n88basic/CHECKS
COPY --from=gates /VERSIONS /usr/share/n88basic/VERSIONS
COPY --from=build /src/_build/default/bin/main.exe /usr/local/bin/n88

# Programs are read from, and PNGs written to, whatever the caller mounts.
WORKDIR /work

ENTRYPOINT ["n88"]
