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

# 2. --help prints metadata block (v1.2.0: brackets around <run-id> for optional).
out=$("$NCO_ROOT/bin/status.sh" --help 2>&1)
assert_contains "$out" "Category: inspect"            "status --help category"
assert_contains "$out" "noclickops status [<run-id>]" "status --help usage (optional run-id)"

# 3. (v1.2.0) No args = list mode, no longer prints 'Usage:'.
# In the noclickops checkout (a git repo whose origin is GitHub, not ADO),
# the list mode tries derive_azdo_context and dies because the origin
# doesn't look like Azure DevOps. That's the documented error path.
out=$("$NCO_ROOT/bin/status.sh" 2>&1); rc=$?
assert_eq "1" "$rc"                                          "status no args exit 1 (fails at derive_azdo_context in non-ADO repo)"
assert_not_contains "$out" "Usage:"                          "status no args no longer prints 'Usage:' (list mode took over)"
assert_contains "$out" "doesn't look like Azure DevOps"      "status no args reaches derive_azdo_context"

# 4. Non-numeric run-id → rejection pre-az.
out=$("$NCO_ROOT/bin/status.sh" abc 2>&1); rc=$?
assert_eq "1" "$rc"                                "status non-numeric exit 1"
assert_contains "$out" "Run id must be numeric"    "status non-numeric error message"

out=$("$NCO_ROOT/bin/status.sh" 12.3 2>&1); rc=$?
assert_eq "1" "$rc"                                "status decimal-id exit 1"
assert_contains "$out" "Run id must be numeric"    "status decimal-id error message"

out=$("$NCO_ROOT/bin/status.sh" "-5" 2>&1); rc=$?
assert_eq "1" "$rc"                                "status negative-id exit 1"
# The dash makes it match [!0-9] in the numeric guard before any az call.
assert_contains "$out" "Run id must be numeric"    "status negative-id rejection message"

# 5. Outside a git repo → "Not inside a git repository".
out=$(cd /tmp && "$NCO_ROOT/bin/status.sh" 12345 2>&1); rc=$?
assert_eq "1" "$rc"                                  "status outside repo exit 1"
assert_contains "$out" "Not inside a git repository" "status outside repo error"

# 5a. (v1.2.0) status no-args outside any git repo fails with the same
# "Not inside a git repository" message as the run-id variant. (Same
# pre-az validation chain; just confirming list-mode hits it too.)
out=$(cd /tmp && "$NCO_ROOT/bin/status.sh" 2>&1); rc=$?
assert_eq "1" "$rc"                                  "status no args outside repo exit 1"
assert_contains "$out" "Not inside a git repository" "status no args outside repo error"

# 5b. (v1.2.0) Example in --help is the list-mode form (the better
# discovery path). Pinning so we don't accidentally revert.
out=$("$NCO_ROOT/bin/status.sh" --help 2>&1)
assert_contains "$out" "Example:"        "status --help has Example section"
# The example should be just 'noclickops status' (list mode) — no run-id.
case "$out" in
  *"Example:"*"  noclickops status"$'\n'*) pass "status --help example demonstrates list mode" ;;
  *) fail "status --help example demonstrates list mode" "did not match: 'Example:\\n  noclickops status\\n'" ;;
esac

# --- add-service: --watch removed ---

# 6. add-service --help no longer mentions --watch.
out=$("$NCO_ROOT/bin/add-service.sh" --help 2>&1)
assert_not_contains "$out" "--watch" "add-service --help no longer mentions --watch"

# 7. Passing --watch to add-service is now rejected as Unknown flag.
out=$("$NCO_ROOT/bin/add-service.sh" myservice --watch 2>&1); rc=$?
assert_eq "1" "$rc"                       "add-service --watch (removed) exit 1"
assert_contains "$out" "Unknown flag"     "add-service --watch (removed) rejected"

summary
