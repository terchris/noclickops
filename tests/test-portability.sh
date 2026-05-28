#!/usr/bin/env bash
# tests/test-portability.sh — cross-cutting guards.
#
# Two flavours of hardcoded identity are forbidden in code/templates/shell:
#
#   1. Target-tenant identity (ExampleOrg / FrontendPlatform /
#      JKL900X016): values that belong to ONE specific ADO repo. noclickops
#      derives these from the target's git remote at runtime.
#   2. Hardcoded GitHub account / owner names (terchris): the project
#      may move owners. The repo NAME (noclickops) is fine — it stays
#      the same in a fork — but the OWNER must be derived from
#      $NOCLICKOPS_DIR's origin remote at runtime.
#
# tests/ legitimately uses both kinds of identity as test data — that's
# the whole point; the grep deliberately excludes tests/.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── portability: no hardcoded identity in code/templates ──"

# Guard 1: target-tenant identity.
matches=$(grep -E -r 'ExampleOrg|FrontendPlatform|JKL900X016' \
            "$NCO_ROOT/bin" "$NCO_ROOT/lib" "$NCO_ROOT/templates" "$NCO_ROOT/shell" \
            2>/dev/null || true)
if [ -z "$matches" ]; then
  pass "no target-tenant identity (ExampleOrg/FrontendPlatform/JKL900X016) in bin|lib|templates|shell"
else
  fail "no target-tenant identity in bin|lib|templates|shell" "$matches"
fi

# Guard 2: hardcoded GitHub account / owner name.
# The repo name 'noclickops' is fine — a fork keeps the same project name.
# What we're catching is account-level hardcoding (e.g. 'terchris') so
# ownership transfer or org migration doesn't break the version check
# or other GitHub-facing references.
matches=$(grep -E -r '\bterchris\b' \
            "$NCO_ROOT/bin" "$NCO_ROOT/lib" "$NCO_ROOT/templates" "$NCO_ROOT/shell" \
            2>/dev/null || true)
if [ -z "$matches" ]; then
  pass "no hardcoded GitHub account name (terchris) in bin|lib|templates|shell"
else
  fail "no hardcoded GitHub account name" "$matches"
fi

summary
