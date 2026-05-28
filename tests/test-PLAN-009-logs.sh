#!/usr/bin/env bash
# tests/test-PLAN-009-logs.sh — coverage for bin/logs.sh. Validation only;
# no real az calls.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-009: logs ──"

# 1. Lister shows logs under Inspect.
out=$("$NCO_ROOT/bin/noclickops.sh" 2>&1)
assert_contains "$out" "logs " "lister shows logs"
# (the trailing space helps disambiguate from 'lovable' etc; metadata prints
# 'logs            Show or stream...' so 'logs ' matches)

# 2. --help.
out=$("$NCO_ROOT/bin/logs.sh" --help 2>&1)
assert_contains "$out" "Category: inspect"                            "logs --help category"
assert_contains "$out" "noclickops logs <service> [test|prod]"        "logs --help usage"
assert_contains "$out" "--follow"                                     "logs --help mentions --follow"
assert_contains "$out" "--tail"                                       "logs --help mentions --tail"
assert_contains "$out" "--system"                                     "logs --help mentions --system"

# 3. No args.
out=$("$NCO_ROOT/bin/logs.sh" 2>&1); rc=$?
assert_eq "1" "$rc"             "logs no args exit 1"
assert_contains "$out" "Usage:" "logs no args shows usage"

# 4. Outside a git repo.
out=$(cd /tmp && "$NCO_ROOT/bin/logs.sh" anything 2>&1); rc=$?
assert_eq "1" "$rc"                                  "logs outside repo exit 1"
assert_contains "$out" "Not inside a git repository" "logs outside repo error"

# Build a fake target repo with the YAML scaffolding info needs.
repo=$(make_target_repo)
make_service "$repo" "myapp" >/dev/null
add_pipeline_variables "$repo"
add_service_variables "$repo" "myapp"

# 5. Unknown service.
out=$(cd "$repo" && "$NCO_ROOT/bin/logs.sh" ghost 2>&1); rc=$?
assert_eq "1" "$rc"                                "logs unknown service exit 1"
assert_contains "$out" "Service 'ghost' not found" "logs unknown service error"

# 6. Invalid env (resolve_service_context catches this).
out=$(cd "$repo" && "$NCO_ROOT/bin/logs.sh" myapp staging 2>&1); rc=$?
assert_eq "1" "$rc"                          "logs invalid env exit 1"
assert_contains "$out" "Invalid environment" "logs invalid env error"

# 7. Unknown flag.
out=$(cd "$repo" && "$NCO_ROOT/bin/logs.sh" myapp test --bogus 2>&1); rc=$?
assert_eq "1" "$rc"                       "logs unknown flag exit 1"
assert_contains "$out" "Unknown argument" "logs unknown flag error"

# 8. --tail without a value.
out=$(cd "$repo" && "$NCO_ROOT/bin/logs.sh" myapp test --tail 2>&1); rc=$?
assert_eq "1" "$rc"                            "logs --tail no value exit 1"
assert_contains "$out" "--tail requires a number" "logs --tail no value error"

# 9. --tail with a non-numeric value.
out=$(cd "$repo" && "$NCO_ROOT/bin/logs.sh" myapp test --tail foo 2>&1); rc=$?
assert_eq "1" "$rc"                                  "logs --tail non-numeric exit 1"
assert_contains "$out" "--tail must be numeric"      "logs --tail non-numeric error"

# 10. --tail=N inline form parses OK (would proceed to az; we just need to
# confirm it doesn't error on parsing — exit code depends on az being
# unavailable, which is fine for this assertion).
out=$(cd "$repo" && "$NCO_ROOT/bin/logs.sh" myapp test --tail=50 2>&1); rc=$?
# Either passes validation and fails later (no az / no subscription), or
# az is present + subscription accessible + container missing. Any of
# those is acceptable — we just need to make sure it didn't fail on
# arg validation.
case "$out" in
  *"--tail"*) fail "logs --tail=N inline parses" "got tail-validation error: $out" ;;
  *)          pass "logs --tail=N inline parses (no validation error)" ;;
esac

# 11. logs against env with empty SUBSCRIPTION_ID (the FRT prod yaml's
# current state) fails closed with the Reader-role hint.
out=$(cd "$repo" && "$NCO_ROOT/bin/logs.sh" myapp prod 2>&1); rc=$?
# The prod fixture leaves SUBSCRIPTION_ID empty. try_az_subscription should
# warn + return 1, and logs should exit 1.
assert_eq "1" "$rc"                                          "logs empty SUBSCRIPTION_ID exit 1"
case "$out" in
  *"SUBSCRIPTION_ID is empty"*)  pass "logs empty SUBSCRIPTION_ID shows empty-id warning" ;;
  *"Not logged in"*)              pass "logs not-logged-in path (alternative)" ;;
  *"Cannot access"*)              pass "logs cannot-access path (alternative)" ;;
  *)                              fail "logs empty SUBSCRIPTION_ID warning" "got: $out" ;;
esac

rm -rf "$repo"

summary
