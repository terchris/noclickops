#!/usr/bin/env bash
# tests/test-PLAN-010-shell.sh — coverage for bin/shell.sh. Validation only;
# no real az calls.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-010: shell ──"

# 1. Lister shows shell under Inspect.
out=$("$NCO_ROOT/bin/noclickops.sh" 2>&1)
assert_contains "$out" "shell " "lister shows shell"
# (trailing space disambiguates from 'shell/' references and word-boundary)

# 2. --help.
out=$("$NCO_ROOT/bin/shell.sh" --help 2>&1)
assert_contains "$out" "Category: inspect"                "shell --help category"
assert_contains "$out" "noclickops shell <service>"       "shell --help usage"
assert_contains "$out" "--command"                        "shell --help mentions --command"
assert_contains "$out" "--container"                      "shell --help mentions --container"
assert_contains "$out" "--revision"                       "shell --help mentions --revision"

# 3. No args.
out=$("$NCO_ROOT/bin/shell.sh" 2>&1); rc=$?
assert_eq "1" "$rc"             "shell no args exit 1"
assert_contains "$out" "Usage:" "shell no args shows usage"

# 4. Outside a git repo.
out=$(cd /tmp && "$NCO_ROOT/bin/shell.sh" anything 2>&1); rc=$?
assert_eq "1" "$rc"                                  "shell outside repo exit 1"
assert_contains "$out" "Not inside a git repository" "shell outside repo error"

# Build a fake target repo with the YAML scaffolding.
repo=$(make_target_repo)
make_service "$repo" "myapp" >/dev/null
add_pipeline_variables "$repo"
add_service_variables "$repo" "myapp"

# 5. Unknown service.
out=$(cd "$repo" && "$NCO_ROOT/bin/shell.sh" ghost 2>&1); rc=$?
assert_eq "1" "$rc"                                "shell unknown service exit 1"
assert_contains "$out" "Service 'ghost' not found" "shell unknown service error"

# 6. Invalid env — the arg-parser catches it before resolve_service_context.
out=$(cd "$repo" && "$NCO_ROOT/bin/shell.sh" myapp staging 2>&1); rc=$?
assert_eq "1" "$rc"                          "shell invalid env exit 1"
assert_contains "$out" "Invalid environment" "shell invalid env error"

# 7. Unknown flag.
out=$(cd "$repo" && "$NCO_ROOT/bin/shell.sh" myapp test --bogus 2>&1); rc=$?
assert_eq "1" "$rc"                       "shell unknown flag exit 1"
assert_contains "$out" "Unknown argument" "shell unknown flag error"

# 8. --command without value.
out=$(cd "$repo" && "$NCO_ROOT/bin/shell.sh" myapp test --command 2>&1); rc=$?
assert_eq "1" "$rc"                              "shell --command no value exit 1"
assert_contains "$out" "--command requires a value" "shell --command no value error"

# 9. --container without value.
out=$(cd "$repo" && "$NCO_ROOT/bin/shell.sh" myapp test --container 2>&1); rc=$?
assert_eq "1" "$rc"                                "shell --container no value exit 1"
assert_contains "$out" "--container requires a value" "shell --container no value error"

# 10. --revision without value.
out=$(cd "$repo" && "$NCO_ROOT/bin/shell.sh" myapp test --revision 2>&1); rc=$?
assert_eq "1" "$rc"                                "shell --revision no value exit 1"
assert_contains "$out" "--revision requires a value" "shell --revision no value error"

# 11. Inline forms parse OK (--command=X, --container=Y, --revision=Z).
out=$(cd "$repo" && "$NCO_ROOT/bin/shell.sh" myapp test --command=ls --container=sidecar --revision=rev1 2>&1)
# Any further error is from az not being available / no subscription / etc.,
# never from the arg parser.
case "$out" in
  *"requires a value"*|*"Unknown argument"*)
    fail "shell inline flag forms parse" "got arg-parser error: $out" ;;
  *)
    pass "shell inline flag forms parse (no validation error)" ;;
esac

# 12. Empty SUBSCRIPTION_ID (prod fixture) → fail-closed.
out=$(cd "$repo" && "$NCO_ROOT/bin/shell.sh" myapp prod 2>&1); rc=$?
assert_eq "1" "$rc" "shell empty SUBSCRIPTION_ID exit 1"
case "$out" in
  *"SUBSCRIPTION_ID is empty"*) pass "shell empty SUBSCRIPTION_ID shows empty-id warning" ;;
  *"Not logged in"*)            pass "shell not-logged-in path (alternative)" ;;
  *"Cannot access"*)            pass "shell cannot-access path (alternative)" ;;
  *)                            fail "shell empty SUBSCRIPTION_ID warning" "got: $out" ;;
esac

rm -rf "$repo"

summary
