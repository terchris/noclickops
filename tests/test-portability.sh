#!/usr/bin/env bash
# tests/test-portability.sh — cross-cutting guard: NO hardcoded tenant
# identity (ExampleOrg / FrontendPlatform / JKL900X016) anywhere in
# bin/, lib/, templates/, or shell/. Examples in docstrings should use
# generic placeholders (AcmeCorp / Platform / some-app).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── portability: no hardcoded tenant identity in code/templates ──"

matches=$(grep -E -r 'ExampleOrg|FrontendPlatform|JKL900X016' \
            "$NCO_ROOT/bin" "$NCO_ROOT/lib" "$NCO_ROOT/templates" "$NCO_ROOT/shell" \
            2>/dev/null || true)

if [ -z "$matches" ]; then
  pass "no ExampleOrg/FrontendPlatform/JKL900X016 in bin|lib|templates|shell"
else
  fail "no ExampleOrg/FrontendPlatform/JKL900X016 in bin|lib|templates|shell" "$matches"
fi

# Sanity: tests/ legitimately uses these names as test data (they're real
# inputs for URL derivation). Don't grep those out — that's the whole point.

summary
