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

USER opam
WORKDIR /src

# dune is the only build dependency. Installed before the sources are copied
# so that editing a .ml file does not invalidate this layer.
RUN opam install -y dune

# Only what the interpreter binary needs. The editor bundle, the tests and
# the specification tooling are deliberately left out of the image.
COPY --chown=opam:opam dune-project dune ./
COPY --chown=opam:opam basic/  ./basic/
COPY --chown=opam:opam raster/ ./raster/
COPY --chown=opam:opam bin/    ./bin/

RUN opam exec -- dune build --profile static bin/main.exe

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
