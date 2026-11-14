#!/usr/bin/env bash
# Builds pep-complexity and runs the package's tests: the [Test] functions
# in tests/, with pepper test. tool_test.pep runs the built tool, found on
# the PATH.
#
# Usage: tests/run.sh [path/to/pepper]   (default: pepper on PATH)
set -euxo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pepper="${1:-pepper}"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# Fetches the dependencies too, which the tests' build reads through the
# project's `include`.
cd "$root"
"$pepper" build -o "$build/bin/pep-complexity"
export PATH="$build/bin:$PATH"

# The package is the module `complexity`: a folder of that name on the
# import path. A copy of its sources, not a link, which Windows may not
# make, and which would also bring along .pep/deps.
mkdir -p "$build/packages/complexity"
cp "$root"/*.pep "$build/packages/complexity/"
"$pepper" test -I "$build/packages" tests
