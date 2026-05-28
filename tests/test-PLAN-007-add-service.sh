#!/usr/bin/env bash
# tests/test-PLAN-007-add-service.sh — coverage for bin/add-service.sh.
# All assertions exercise pre-az validation; no real pipeline triggers.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-007: add-service ──"

# 1. Lister shows add-service under Service lifecycle.
out=$("$NCO_ROOT/bin/noclickops.sh" 2>&1)
assert_contains "$out" "add-service" "lister shows add-service"

# 2. --help.
out=$("$NCO_ROOT/bin/add-service.sh" --help 2>&1)
assert_contains "$out" "Category: service-lifecycle" "add-service --help category"
assert_contains "$out" "--persistent-storage"        "add-service --help shows persistent-storage flag"
assert_contains "$out" "--no-public-endpoint"        "add-service --help shows no-public-endpoint flag"

# 3. No args.
out=$("$NCO_ROOT/bin/add-service.sh" 2>&1); rc=$?
assert_eq "1" "$rc"             "add-service no args exit 1"
assert_contains "$out" "Usage:" "add-service no args shows usage"

# 4. Unknown flag.
out=$("$NCO_ROOT/bin/add-service.sh" myservice --bogus 2>&1); rc=$?
assert_eq "1" "$rc"                       "add-service unknown flag exit 1"
assert_contains "$out" "Unknown flag"     "add-service unknown flag error"

# 5. Extra positional argument rejected.
out=$("$NCO_ROOT/bin/add-service.sh" myservice extra-arg 2>&1); rc=$?
assert_eq "1" "$rc"                                "add-service extra positional exit 1"
assert_contains "$out" "Unexpected positional"     "add-service extra positional error"

# 6. Name-shape validation: leading dash.
out=$("$NCO_ROOT/bin/add-service.sh" -- 2>&1); rc=$?
# Actually -- might be eaten by bash arg parsing; use --watch which is a valid
# flag but appears first to test that no positional was given.
out=$("$NCO_ROOT/bin/add-service.sh" "-leadingdash" 2>&1); rc=$?
assert_eq "1" "$rc"                                       "add-service leading-dash name exit 1"
# Could be caught as 'Unknown flag' or 'must not start' — both are valid.
case "$out" in
  *"must not start with"*|*"Unknown flag"*) pass "add-service leading-dash rejection message" ;;
  *) fail "add-service leading-dash rejection message" "got: $out" ;;
esac

# 7. Name-shape validation: path separator.
out=$("$NCO_ROOT/bin/add-service.sh" "bad/name" 2>&1); rc=$?
assert_eq "1" "$rc"                                    "add-service slash-in-name exit 1"
assert_contains "$out" "must not contain path separators" "add-service slash-in-name error"

# 8. Name-shape validation: whitespace.
out=$("$NCO_ROOT/bin/add-service.sh" "bad name" 2>&1); rc=$?
assert_eq "1" "$rc"                                  "add-service whitespace exit 1"
assert_contains "$out" "must not contain whitespace" "add-service whitespace error"

# 9. Outside a git repo.
out=$(cd /tmp && "$NCO_ROOT/bin/add-service.sh" myservice 2>&1); rc=$?
assert_eq "1" "$rc"                                   "add-service outside repo exit 1"
assert_contains "$out" "Not inside a git repository"  "add-service outside repo error"

# 10. Existing service folder → refusal.
repo=$(make_target_repo)
make_service "$repo" "existing" >/dev/null
out=$(cd "$repo" && "$NCO_ROOT/bin/add-service.sh" existing 2>&1); rc=$?
assert_eq "1" "$rc"                                "add-service duplicate folder exit 1"
assert_contains "$out" "already exists"            "add-service duplicate folder error"
rm -rf "$repo"

# 11. Pipeline name composition: <AZDO_REPO>-add-service
# (independent of service name, unlike deploy).
repo=$(make_target_repo "https://dev.azure.com/AcmeCorp/Platform/_git/some-app")
out=$(bash -c "
  . '$NCO_ROOT/lib/azdo.sh'
  derive_azdo_context '$repo'
  printf '%s-add-service\n' \"\$AZDO_REPO\"
")
assert_eq "some-app-add-service" "$out" "pipeline name = AZDO_REPO-add-service"
rm -rf "$repo"

summary
