# n88basic
#
#   make build        the interpreter
#   make test         the suites -- the fast inner loop
#   make ci           EVERY gate, in Docker: the same pipeline CI runs
#   make webconsole   the console in a browser, on localhost (or: make wc)
#   make install      n88 onto your PATH
#   make vsix         package the VS Code extension as n88basic.vsix
#
# The scripts under scripts/ are the same commands and work without make.

PORT ?= 8088

# The project keeps its own opam switch. A caller who has not run
# `eval $(opam env)` still has a usable dune right here, so find it rather
# than failing with "command not found".
DUNE := $(shell command -v dune 2>/dev/null || echo $(CURDIR)/_opam/bin/dune)

.PHONY: build test ci web webconsole wc install vsix extension clean help

help:
	@grep -E '^#   make' Makefile | sed 's/^#   /  /'

build:
	@$(DUNE) build

# The suites, and only the suites. This used to run a hand-picked four of the
# checks under the name "every gate", which is how it came to disagree with CI
# about what that meant. `make ci` is the gate; this is the loop you run while
# you work.
test:
	@$(DUNE) test

# Every check there is, in Docker, from the one list in the Dockerfile. Needs
# no OCaml, no python and no node on this machine.
ci:
	@./scripts/check-everything.sh

# The browser console. `(modes js)` in web/dune makes this optional, so say
# what is missing rather than failing with a dune error about a rule.
web:
	@echo "[1/2] building the console"
	@./scripts/build-web-console.sh

webconsole: web
	@echo "[2/2] serving it"
	@PORT=$(PORT) ./scripts/serve-web-console.sh

wc: webconsole

install:
	@./scripts/install-from-source.sh

# Produces ./n88basic.vsix. Uses vsce if you have it, Docker if you do not.
vsix:
	@./scripts/package-extension.sh

# The old name, kept because the README and the release notes use it.
extension: vsix

clean:
	@$(DUNE) clean
