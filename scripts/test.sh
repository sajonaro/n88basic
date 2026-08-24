#!/bin/sh
# Everything that can fail: unit tests, conformance cases, the spec gates,
# and the example programs.
set -eu
cd "$(dirname "$0")/.."

dune test
sh scripts/check-invariants.sh
python3 tools/check_spec.py
python3 tools/coverage.py
python3 tools/citation_coverage.py
python3 tools/run_programs.py
