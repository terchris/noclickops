#!/usr/bin/env bash
# tests/test-portability.sh — cross-cutting guards.
#
# Two flavours of hardcoded identity are forbidden in code/templates/shell:
#
#   1. Target-tenant identity (ExampleOrg / FrontendPlatform /
#      JKL900X016): values that belong to ONE specific ADO repo. noclickops
#      derives these from the target's git remote at runtime.
#   2. noclickops-own-repo identity (terchris/noclickops): the upstream
#      "where do we fetch updates from" identity. noclickops derives this
#      from its OWN install dir's git remote — a fork at alice/noclickops
#      checks alice's main, not the original maintainer's.
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

# Guard 2: noclickops-own-repo identity.
matches=$(grep -E -r 'terchris/noclickops|helpers-no/noclickops' \
            "$NCO_ROOT/bin" "$NCO_ROOT/lib" "$NCO_ROOT/templates" "$NCO_ROOT/shell" \
            2>/dev/null || true)
if [ -z "$matches" ]; then
  pass "no hardcoded noclickops-own-repo identity (terchris/noclickops) in bin|lib|templates|shell"
else
  fail "no hardcoded noclickops-own-repo identity" "$matches"
fi

summary
