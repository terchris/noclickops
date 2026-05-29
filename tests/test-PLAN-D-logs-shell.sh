#!/usr/bin/env bash
# tests/test-PLAN-D-logs-shell.sh — coverage for bin/logs.sh + bin/shell.sh (v2).
#
# Both commands use exec at the end, so they're awkward to test in-process.
# The pattern: set NCO_AZ_OVERRIDE to a stub that prints "AZ_CALL:" + its args
# and exits 0. The bin script exec's the stub instead of az, the stub echoes
# what az would have been called with, and we assert on that.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-D: bin/logs.sh + bin/shell.sh (v2) ──"

# --- Negative cases (each command) ---

for cmd in logs shell; do
  out=$("$NCO_ROOT/bin/$cmd.sh" --help 2>&1)
  assert_contains "$out" "Category: inspect"  "planD: $cmd --help shows category"

  out=$("$NCO_ROOT/bin/$cmd.sh" 2>&1); rc=$?
  assert_eq "1" "$rc"               "planD: $cmd no args exit 1"
  assert_contains "$out" "Usage:"   "planD: $cmd no args shows usage"

  out=$(cd /tmp && "$NCO_ROOT/bin/$cmd.sh" frontend 2>&1); rc=$?
  assert_eq "1" "$rc"                                   "planD: $cmd outside repo exit 1"
  assert_contains "$out" "Not inside a git repository" "planD: $cmd outside repo error"
done

# Invalid env for logs (shell uses identical parsing)
src=$(make_v2_source_repo)
make_v2_service "$src" frontend true >/dev/null
out=$(cd "$src" && "$NCO_ROOT/bin/logs.sh" frontend staging 2>&1); rc=$?
assert_eq "1" "$rc"                          "planD: logs invalid env exit 1"
assert_contains "$out" "Invalid environment" "planD: logs invalid env error"
rm -rf "$src"

# --- Specialised az stub for PLAN-D: dispatches normal queries to fixture
# files, but for the FINAL exec'd "containerapp logs show" or "containerapp
# exec" call it echoes the args so tests can assert on what was passed. ---

write_az_dispatch_stub() {
  local target="$1"
  cat > "$target" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
fixtures="${NCO_TEST_AZ_FIXTURES:?NCO_TEST_AZ_FIXTURES not set}"

# Capture the subcommand chain (first two non-flag args).
sub1="${1:-}"; sub2="${2:-}"

# Final exec'd calls: echo a marker line + the entire argv. Tests grep for it.
case "$sub1 $sub2" in
  "containerapp logs"|"containerapp exec")
    printf 'AZ_CALL:'
    printf ' %q' "$@"
    printf '\n'
    exit 0
    ;;
esac

# All other calls: look up a fixture file as the standard stub does.
args=("$@")
subcmd=""; proj=""; rg=""; sub=""
i=0
while [ $i -lt ${#args[@]} ]; do
  a="${args[$i]}"
  case "$a" in
    --project)            i=$((i+1)); proj="${args[$i]:-}" ;;
    --project=*)          proj="${a#*=}" ;;
    --resource-group|-g)  i=$((i+1)); rg="${args[$i]:-}" ;;
    --resource-group=*)   rg="${a#*=}" ;;
    --subscription)       i=$((i+1)); sub="${args[$i]:-}" ;;
    --subscription=*)     sub="${a#*=}" ;;
    --*|-*)               i=$((i+1)) ;;
    *)                    [ -z "$subcmd" ] && subcmd="$a" || subcmd="${subcmd}_$a" ;;
  esac
  i=$((i+1))
done
key="${subcmd}"
[ -n "$proj" ] && key="${key}_proj_${proj}"
[ -n "$rg" ]   && key="${key}_rg_${rg}"
[ -n "$sub" ]  && key="${key}_sub_${sub}"
for ext in tsv json txt; do
  if [ -f "$fixtures/az_${key}.${ext}" ]; then
    cat "$fixtures/az_${key}.${ext}"
    exit 0
  fi
done
printf 'stub: no fixture for az %s (key=%s)\n' "$*" "$key" >&2
exit 1
STUB
  chmod +x "$target"
}

planD_az_stub="$NCO_ROOT/tests/_stub_planD_az.sh"
write_az_dispatch_stub "$planD_az_stub"

# --- Fixture setup ---

setup_fixture() {
  local src iac az_fixtures
  src=$(make_v2_source_repo "https://dev.azure.com/AcmeCorp/FrontProj/_git/ABC100001-myservice")
  make_v2_service "$src" frontend true >/dev/null
  iac=$(make_v2_iac_repo ABC ABC100001-myservice)
  az_fixtures=$(mktemp -d)
  # Container app discovery hit (step b: common RG)
  cat > "$az_fixtures/az_containerapp_list_rg_rg-test-myteam-frontend-common.tsv" <<'EOF'
ca-abc100001-frontend	rg-test-myteam-frontend-common	ca-abc100001-frontend.fqdn
EOF
  printf '%s %s %s' "$src" "$iac" "$az_fixtures"
}
ado_stub=$(v2_stub_ado_rest_path)

# --- Logs happy path ---

paths=$(setup_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$planD_az_stub" \
  "$NCO_ROOT/bin/logs.sh" frontend test 2>&1); rc=$?

assert_eq "0" "$rc"                                "planD: logs happy path exits 0"
assert_contains "$out" "Container app: ca-abc100001-frontend" "planD: logs prints container-app name"
assert_contains "$out" "AZ_CALL:"                  "planD: logs exec'd the stub"
assert_contains "$out" "containerapp logs show"    "planD: logs exec'd containerapp logs show"
assert_contains "$out" "--name ca-abc100001-frontend" "planD: logs passed correct --name"
assert_contains "$out" "--resource-group rg-test-myteam-frontend-common" "planD: logs passed correct --resource-group"
assert_contains "$out" "--subscription 3aec5ff4"   "planD: logs passed --subscription from IAC vars"
assert_contains "$out" "--tail 100"                "planD: logs default --tail 100"

# Flag pass-through: --follow --tail 50 --system
out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$planD_az_stub" \
  "$NCO_ROOT/bin/logs.sh" frontend test --follow --tail 50 --system 2>&1)
assert_contains "$out" "--tail 50"   "planD: logs passes --tail 50"
assert_contains "$out" "--follow"    "planD: logs passes --follow"
assert_contains "$out" "--type system" "planD: logs maps --system to --type system"

rm -rf "$src" "$iac" "$az_fixtures"

# --- Shell happy path ---

paths=$(setup_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$planD_az_stub" \
  "$NCO_ROOT/bin/shell.sh" frontend test 2>&1); rc=$?

assert_eq "0" "$rc"                                "planD: shell happy path exits 0"
assert_contains "$out" "containerapp exec"         "planD: shell exec'd containerapp exec"
assert_contains "$out" "--name ca-abc100001-frontend" "planD: shell passed --name"
assert_contains "$out" "--command /bin/sh"         "planD: shell default --command /bin/sh"

# Flag pass-through: --command /bin/bash --container web
out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$planD_az_stub" \
  "$NCO_ROOT/bin/shell.sh" frontend test --command /bin/bash --container web 2>&1)
assert_contains "$out" "--command /bin/bash" "planD: shell passes --command override"
assert_contains "$out" "--container web"     "planD: shell passes --container"

rm -rf "$src" "$iac" "$az_fixtures"

# --- Gating: discover_containerapp fails → both commands die ---

paths=$(setup_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')
# Empty containerapp list in both common RG AND sub-wide
cat > "$az_fixtures/az_containerapp_list_rg_rg-test-myteam-frontend-common.tsv" </dev/null
cat > "$az_fixtures/az_containerapp_list_sub_3aec5ff4-d5d3-47d3-b860-c36f2bf3ca2d.tsv" </dev/null

for cmd in logs shell; do
  out=$(cd "$src" && \
    NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
    NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$planD_az_stub" \
    "$NCO_ROOT/bin/$cmd.sh" frontend test 2>&1); rc=$?
  assert_eq "1" "$rc"                              "planD: $cmd gates on discovery failure (exit 1)"
  assert_contains "$out" "SVC_APP_NAME_OVERRIDE"  "planD: $cmd error names the override env var"
  case "$out" in
    *"AZ_CALL:"*) fail "planD: $cmd should NOT have exec'd az on discovery failure" "got: $out" ;;
    *)            pass "planD: $cmd did not exec az when discovery failed" ;;
  esac
done

rm -rf "$src" "$iac" "$az_fixtures"

# --- Override path: SVC_APP_NAME_OVERRIDE + SVC_RG_OVERRIDE skips list call ---

paths=$(setup_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')
# No containerapp list fixtures present — if the script tries one it fails.

for cmd in logs shell; do
  out=$(cd "$src" && \
    NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
    NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$planD_az_stub" \
    SVC_APP_NAME_OVERRIDE=ca-custom-name SVC_RG_OVERRIDE=rg-custom \
    "$NCO_ROOT/bin/$cmd.sh" frontend test 2>&1); rc=$?
  assert_eq "0" "$rc"                                  "planD: $cmd override path exit 0"
  assert_contains "$out" "--name ca-custom-name"      "planD: $cmd override path uses override name"
  assert_contains "$out" "--resource-group rg-custom" "planD: $cmd override path uses override RG"
  case "$out" in
    *"no fixture for az"*) fail "planD: $cmd override path attempted a list call" "got: $out" ;;
    *)                     pass "planD: $cmd override path skipped containerapp list" ;;
  esac
done

rm -rf "$src" "$iac" "$az_fixtures"
rm -f "$planD_az_stub"

summary
