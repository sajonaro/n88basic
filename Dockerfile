# The n88basic interpreter as a container.
#
# The interpreter binary depends on no external OCaml libraries -- only on
# this repository's own basic/ and raster/ -- so the build stage needs a
# compiler and nothing else, and the runtime stage needs no libraries at all.
#
#   docker build -t n88basic .
#   docker run --rm -v "$PWD:/work" n88basic prog.bas
#
# A program that draws writes its PNG beside the source, so the mounted
# directory is where the output appears.

# --- build ------------------------------------------------------------------
FROM ocaml/opam:alpine-ocaml-5.2 AS build

# WORKDIR creates the directory as root even after USER, so the unprivileged
# build cannot write _build into it. Harmless under buildx, fatal under the
# classic builder -- make the ownership explicit rather than depend on which
# builder someone has.
USER root
RUN mkdir -p /src && chown opam:opam /src
USER opam
WORKDIR /src

# dune is the only build dependency. Installed before the sources are copied
# so that editing a .ml file does not invalidate this layer.
RUN opam install -y dune

# Only what the interpreter binary needs. The editor bundle, the tests and
# the specification tooling are deliberately left out of the image.
COPY --chown=opam:opam dune-project ./
COPY --chown=opam:opam basic/  ./basic/
COPY --chown=opam:opam raster/ ./raster/
COPY --chown=opam:opam bin/    ./bin/

RUN opam exec -- dune build --profile release bin/main.exe

# --- the browser console ------------------------------------------------------
#
# Building the web console needs js_of_ocaml, which is a real toolchain to set
# up for someone who only wants to look at the thing. This stage has it, so
# `make wc` can hand the whole job to Docker and the caller needs nothing but
# Docker. The output is four static files -- there is no server here.
FROM build AS web

USER opam
RUN opam install -y js_of_ocaml js_of_ocaml-compiler
COPY --chown=opam:opam web/  ./web/
COPY --chown=opam:opam test/programs/ ./test/programs/
RUN opam exec -- dune build @web/web

# The built page, and nothing else. Kept as a normal image rather than
# `FROM scratch` with --output, because --output needs buildx and the classic
# builder is still what many machines have: scripts/build-web.sh creates a
# container from this and copies the files out, which works either way.
FROM alpine:3.20 AS web-assets
COPY --from=web /src/_build/default/web/index.html /web/
COPY --from=web /src/_build/default/web/console.css /web/
COPY --from=web /src/_build/default/web/examples.js /web/
COPY --from=web /src/_build/default/web/main.bc.js /web/

# --- runtime ----------------------------------------------------------------
FROM alpine:3.20

LABEL org.opencontainers.image.title="n88basic"
LABEL org.opencontainers.image.description="Interpreter for N88-BASIC(86), the ROM BASIC of the NEC PC-9801"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.source="https://github.com/sajonaro/n88basic"

COPY --from=build /src/_build/default/bin/main.exe /usr/local/bin/n88

# Programs are read from, and PNGs written to, whatever the caller mounts.
WORKDIR /work

ENTRYPOINT ["n88"]
