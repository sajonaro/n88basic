# n88basic
#
#   make build        the interpreter
#   make test         every gate: suites, conformance, spec, invariants
#   make webconsole   the console in a browser, on localhost (or: make wc)
#   make install      n88 onto your PATH
#   make extension    package the VS Code extension
#
# The scripts under scripts/ are the same commands and work without make.

PORT ?= 8088

.PHONY: build test web webconsole wc install extension clean help

help:
	@grep -E '^#   make' Makefile | sed 's/^#   /  /'

build:
	@dune build

test:
	@dune test
	@./scripts/conform.sh "$(CURDIR)/_build/default/bin/main.exe"
	@python3 tools/check_spec.py >/dev/null && echo "spec gates ok"
	@sh scripts/check-invariants.sh

# The browser console. `(modes js)` in web/dune makes this optional, so say
# what is missing rather than failing with a dune error about a rule.
web:
	@dune build @web/web 2>/dev/null || { \
	  echo "The web console needs js_of_ocaml:"; \
	  echo "    opam install js_of_ocaml js_of_ocaml-compiler"; \
	  exit 1; }
	@node tools/check_web.js
	@python3 tools/check_svg.py

webconsole: web
	@echo ""
	@echo "  n88basic console at http://localhost:$(PORT)/   (ctrl-c stops it)"
	@echo ""
	@cd _build/default/web && python3 -m http.server $(PORT) --bind 127.0.0.1 2>/dev/null

wc: webconsole

install:
	@./scripts/install.sh

extension:
	@./scripts/package-extension.sh

clean:
	@dune clean
