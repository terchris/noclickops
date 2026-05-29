#!/usr/bin/env bash
# tests/test-PLAN-F-add-service.sh — coverage for bin/add-service.sh (v2).
# Stubs all az + ADO REST calls.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-F: bin/add-service.sh (v2) ──"

# --- Negative cases ---

out=$("$NCO_ROOT/bin/add-service.sh" --help 2>&1)
assert_contains "$out" "Category: service-lifecycle" "planF: --help shows category"
assert_contains "$out" "auto-merge BOTH"             "planF: --help mentions two-PR flow"

out=$("$NCO_ROOT/bin/add-service.sh" 2>&1); rc=$?
assert_eq "1" "$rc"              "planF: no args exit 1"
assert_contains "$out" "Usage:"  "planF: no args shows usage"

out=$(cd /tmp && "$NCO_ROOT/bin/add-service.sh" backend 2>&1); rc=$?
assert_eq "1" "$rc"                                   "planF: outside repo exit 1"
assert_contains "$out" "Not inside a git repository" "planF: outside repo error"

# Name validation
src=$(make_v2_source_repo)
for bad_args in "-leading-dash" "with/slash" "with backslash"; do
  out=$(cd "$src" && "$NCO_ROOT/bin/add-service.sh" "$bad_args" 2>&1); rc=$?
  assert_eq "1" "$rc" "planF: rejects bad name '$bad_args'"
done

# Service folder already exists
mkdir -p "$src/services/existing"
out=$(cd "$src" && "$NCO_ROOT/bin/add-service.sh" existing 2>&1); rc=$?
assert_eq "1" "$rc"                                      "planF: existing folder exit 1"
assert_contains "$out" "Service folder already exists"  "planF: existing folder error"
rm -rf "$src"

# --- Fixture setup ---

setup_fixture() {
  local src iac az_fixtures
  src=$(make_v2_source_repo "https://dev.azure.com/AcmeCorp/FrontProj/_git/ABC100001-myservice")
  iac=$(make_v2_iac_repo ABC ABC100001-myservice)
  az_fixtures=$(mktemp -d)
  printf '%s %s %s' "$src" "$iac" "$az_fixtures"
}
ado_stub=$(v2_stub_ado_rest_path)
az_stub=$(v2_stub_az_path)

# Common az fixtures used by all happy-path tests
write_default_az_fixtures() {
  local f="$1"
  # trigger_pipeline → run id
  printf '7777\n' > "$f/az_pipelines_run_proj_FrontProj.tsv"
  # watch_run → succeeded
  printf 'completed\tsucceeded\n' > "$f/az_pipelines_runs_show_proj_FrontProj.tsv"
  # PR-A: list → 4831, set-vote → empty, update → completed, show → completed
  printf '4831\n' > "$f/az_repos_pr_list_proj_FrontProj.tsv"
  printf '' > "$f/az_repos_pr_set-vote_proj_FrontProj.tsv"
  printf 'completed\n' > "$f/az_repos_pr_update_proj_FrontProj.tsv"
  printf 'completed\n' > "$f/az_repos_pr_show_proj_FrontProj.tsv"
  # PR-B in IaC: list → 4832, same flow
  printf '4832\n' > "$f/az_repos_pr_list_proj_IaC.tsv"
  printf '' > "$f/az_repos_pr_set-vote_proj_IaC.tsv"
  printf 'completed\n' > "$f/az_repos_pr_update_proj_IaC.tsv"
  printf 'completed\n' > "$f/az_repos_pr_show_proj_IaC.tsv"
}

# --- Happy path: both PRs auto-merged ---

paths=$(setup_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')
write_default_az_fixtures "$az_fixtures"

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  NCO_WATCH_INTERVAL=0 NCO_WATCH_TIMEOUT_MIN=1 NCO_PR_B_TIMEOUT_MIN=1 \
  "$NCO_ROOT/bin/add-service.sh" backend 2>&1); rc=$?

assert_eq "0" "$rc"                                "planF: happy path exits 0"
assert_contains "$out" "Started run 7777"          "planF: prints pipeline run id"
assert_contains "$out" "Pipeline succeeded"        "planF: pipeline succeeded"
assert_contains "$out" "Found PR-A #4831"          "planF: found PR-A"
assert_contains "$out" "PR #4831 completed"        "planF: PR-A merged"
assert_contains "$out" "Found PR-B #4832"          "planF: found PR-B"
assert_contains "$out" "PR #4832 completed"        "planF: PR-B merged"
assert_contains "$out" "Source PR #4831 merged"    "planF: summary names PR-A"
assert_contains "$out" "infrastructure PR #4832 merged" "planF: summary names PR-B"

rm -rf "$src" "$iac" "$az_fixtures"

# --- --no-merge: exits after pipeline succeeds, no PR calls ---

paths=$(setup_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')
# Only need pipeline fixtures for --no-merge path
printf '7777\n' > "$az_fixtures/az_pipelines_run_proj_FrontProj.tsv"
printf 'completed\tsucceeded\n' > "$az_fixtures/az_pipelines_runs_show_proj_FrontProj.tsv"
# If add-service attempts ANY repos pr call, stub will fail (no fixture)

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  NCO_WATCH_INTERVAL=0 NCO_WATCH_TIMEOUT_MIN=1 \
  "$NCO_ROOT/bin/add-service.sh" backend --no-merge 2>&1); rc=$?

assert_eq "0" "$rc"                                  "planF: --no-merge exit 0"
assert_contains "$out" "Fire-and-forget mode"        "planF: --no-merge prints fire-and-forget banner"
assert_contains "$out" "noclickops merge-pr"         "planF: --no-merge mentions merge-pr for PR-A"
assert_contains "$out" "az repos pr update"          "planF: --no-merge shows az command for PR-B"
case "$out" in
  *"Found PR-A"*) fail "planF: --no-merge should not have searched for PRs" "got: $out" ;;
  *)              pass "planF: --no-merge skipped PR discovery" ;;
esac

rm -rf "$src" "$iac" "$az_fixtures"

# --- PR-A merged, PR-B times out ---

paths=$(setup_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')
write_default_az_fixtures "$az_fixtures"
# Override PR-B list to return empty
printf '' > "$az_fixtures/az_repos_pr_list_proj_IaC.tsv"

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  NCO_WATCH_INTERVAL=0 NCO_WATCH_TIMEOUT_MIN=1 NCO_PR_B_TIMEOUT_MIN=1 \
  "$NCO_ROOT/bin/add-service.sh" backend 2>&1); rc=$?

assert_eq "1" "$rc"                                          "planF: PR-B timeout → exit 1"
assert_contains "$out" "PR #4831 completed"                  "planF: PR-A still merged when PR-B times out"
assert_contains "$out" "PR-B didn't appear"                  "planF: PR-B timeout message"
assert_contains "$out" "PR-A #4831 is already merged"        "planF: error states PR-A already merged"
assert_contains "$out" "deploy backend"                      "planF: error suggests deploy after manual merge"

rm -rf "$src" "$iac" "$az_fixtures"

# --- Flag pass-through: --public-endpoint + --persistent-storage ---

# Verify the flags reach trigger_pipeline. Since the az stub doesn't echo args
# (only returns fixture content), we use a special az stub that records args.

write_arg_capturing_stub() {
  local target="$1" fixtures_dir="$2"
  cat > "$target" <<STUB
#!/usr/bin/env bash
set -uo pipefail
# Tee args into a file the test can inspect
printf '%s\n' "\$*" >> "${fixtures_dir}/_calls.log"
# Then dispatch like the standard stub
$(cat "$NCO_ROOT/tests/_stub_az.sh" | tail -n +2)
STUB
  chmod +x "$target"
}

paths=$(setup_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')
write_default_az_fixtures "$az_fixtures"
arg_stub="$NCO_ROOT/tests/_stub_planF_az.sh"
write_arg_capturing_stub "$arg_stub" "$az_fixtures"

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$arg_stub" \
  NCO_WATCH_INTERVAL=0 NCO_WATCH_TIMEOUT_MIN=1 NCO_PR_B_TIMEOUT_MIN=1 \
  "$NCO_ROOT/bin/add-service.sh" backend --public-endpoint --persistent-storage 2>&1); rc=$?

assert_eq "0" "$rc" "planF: flag-passthrough happy path exit 0"
calls=$(cat "$az_fixtures/_calls.log")
case "$calls" in
  *"public_endpoint=true"*)    pass "planF: --public-endpoint → public_endpoint=true passed to pipeline" ;;
  *)                            fail "planF: --public-endpoint not passed" "calls: $calls" ;;
esac
case "$calls" in
  *"persistent_storage=true"*) pass "planF: --persistent-storage → persistent_storage=true passed to pipeline" ;;
  *)                            fail "planF: --persistent-storage not passed" "calls: $calls" ;;
esac

# Verify default (no flag) sets both to false
rm -f "$az_fixtures/_calls.log"
out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$arg_stub" \
  NCO_WATCH_INTERVAL=0 NCO_WATCH_TIMEOUT_MIN=1 NCO_PR_B_TIMEOUT_MIN=1 \
  "$NCO_ROOT/bin/add-service.sh" frontend2 2>&1); rc=$?

assert_eq "0" "$rc" "planF: no flags happy path exit 0"
calls=$(cat "$az_fixtures/_calls.log")
case "$calls" in
  *"public_endpoint=false"*)    pass "planF: default → public_endpoint=false" ;;
  *)                             fail "planF: default public_endpoint" "calls: $calls" ;;
esac
case "$calls" in
  *"persistent_storage=false"*) pass "planF: default → persistent_storage=false" ;;
  *)                             fail "planF: default persistent_storage" "calls: $calls" ;;
esac

rm -f "$arg_stub"
rm -rf "$src" "$iac" "$az_fixtures"

summary
