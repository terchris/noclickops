#!/usr/bin/env bash
# tests/test-PLAN-007a-status.sh — coverage for bin/status.sh + the
# --watch removal from bin/add-service.sh.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-007a: status + add-service fire-and-forget ──"

# --- status ---

# 1. Lister shows status under "Inspect / observe".
out=$("$NCO_ROOT/bin/noclickops.sh" 2>&1)
assert_contains "$out" "Inspect / observe" "lister has 'Inspect / observe' section"
assert_contains "$out" "status"             "lister shows status"

# 2. --help prints metadata block.
out=$("$NCO_ROOT/bin/status.sh" --help 2>&1)
assert_contains "$out" "Category: inspect"        "status --help category"
assert_contains "$out" "noclickops status <run-id>" "status --help usage"

# 3. No args → usage error.
out=$("$NCO_ROOT/bin/status.sh" 2>&1); rc=$?
assert_eq "1" "$rc"             "status no args exit 1"
assert_contains "$out" "Usage:" "status no args shows usage"

# 4. Non-numeric run-id → rejection pre-az.
out=$("$NCO_ROOT/bin/status.sh" abc 2>&1); rc=$?
assert_eq "1" "$rc"                                "status non-numeric exit 1"
assert_contains "$out" "Run id must be numeric"    "status non-numeric error message"

out=$("$NCO_ROOT/bin/status.sh" 12.3 2>&1); rc=$?
assert_eq "1" "$rc"                                "status decimal-id exit 1"
assert_contains "$out" "Run id must be numeric"    "status decimal-id error message"

out=$("$NCO_ROOT/bin/status.sh" "-5" 2>&1); rc=$?
assert_eq "1" "$rc"                                "status negative-id exit 1"
# Negative would be parsed as a flag or rejected by the numeric guard;
# either path is acceptable as long as it doesn't reach az.
case "$out" in
  *"Run id must be numeric"*|*"Usage:"*) pass "status negative-id rejection message" ;;
  *) fail "status negative-id rejection message" "got: $out" ;;
esac

# 5. Outside a git repo → "Not inside a git repository".
out=$(cd /tmp && "$NCO_ROOT/bin/status.sh" 12345 2>&1); rc=$?
assert_eq "1" "$rc"                                  "status outside repo exit 1"
assert_contains "$out" "Not inside a git repository" "status outside repo error"

# --- add-service: --watch removed ---

# 6. add-service --help no longer mentions --watch.
out=$("$NCO_ROOT/bin/add-service.sh" --help 2>&1)
assert_not_contains "$out" "--watch" "add-service --help no longer mentions --watch"

# 7. Passing --watch to add-service is now rejected as Unknown flag.
out=$("$NCO_ROOT/bin/add-service.sh" myservice --watch 2>&1); rc=$?
assert_eq "1" "$rc"                       "add-service --watch (removed) exit 1"
assert_contains "$out" "Unknown flag"     "add-service --watch (removed) rejected"

summary
