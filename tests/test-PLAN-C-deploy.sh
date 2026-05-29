#!/usr/bin/env bash
# tests/test-PLAN-C-deploy.sh — coverage for bin/deploy.sh (v2 multi-pipeline).
# All az + ADO REST calls stubbed.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-C: bin/deploy.sh (v2) ──"

# --- Negative cases ---

# --help
out=$("$NCO_ROOT/bin/deploy.sh" --help 2>&1)
assert_contains "$out" "Category: deploy"          "planC: --help shows category"
assert_contains "$out" "v2 multi-pipeline"         "planC: --help mentions v2 orchestration"

# No args
out=$("$NCO_ROOT/bin/deploy.sh" 2>&1); rc=$?
assert_eq "1" "$rc"              "planC: no args exit 1"
assert_contains "$out" "Usage:"  "planC: no args shows usage"

# Outside a git repo
out=$(cd /tmp && "$NCO_ROOT/bin/deploy.sh" frontend 2>&1); rc=$?
assert_eq "1" "$rc"                                   "planC: outside repo exit 1"
assert_contains "$out" "Not inside a git repository" "planC: outside repo error"

# --- Fixture setup helper ---

setup_full_fixture() {
  local src iac az_fixtures
  src=$(make_v2_source_repo "https://dev.azure.com/AcmeCorp/FrontProj/_git/ABC100001-myservice")
  make_v2_service "$src" frontend true >/dev/null
  iac=$(make_v2_iac_repo ABC ABC100001-myservice)
  az_fixtures=$(mktemp -d)
  printf '%s %s %s' "$src" "$iac" "$az_fixtures"
}
ado_stub=$(v2_stub_ado_rest_path)
az_stub=$(v2_stub_az_path)

# Pipelines list fixtures — used across multiple test cases.
write_pipeline_list_fixtures() {
  local az_fixtures="$1"
  cat > "$az_fixtures/az_pipelines_list_proj_FrontProj.tsv" <<'EOF'
1128	ABC100001-myservice-frontend-build
1129	ABC100001-myservice-frontend-deploy
EOF
  cat > "$az_fixtures/az_pipelines_list_proj_IaC.tsv" <<'EOF'
2003	ABC100001-myservice-frontend-infra-build
2004	ABC100001-myservice-frontend-deploy-test
2005	ABC100001-myservice-frontend-deploy-prod
EOF
}

# --- Subsequent path (deploy-test has prior success) ---

paths=$(setup_full_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')
write_pipeline_list_fixtures "$az_fixtures"

# is_first_time_deploy → subsequent (count = 3)
cat > "$az_fixtures/az_pipelines_runs_list_proj_IaC.tsv" <<'EOF'
3
EOF
# trigger_pipeline returns run id
cat > "$az_fixtures/az_pipelines_run_proj_FrontProj.tsv" <<'EOF'
4521
EOF
# watch_run completes successfully
printf 'completed\tsucceeded\n' > "$az_fixtures/az_pipelines_runs_show_proj_FrontProj.tsv"

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  NCO_WATCH_INTERVAL=0 NCO_WATCH_TIMEOUT_MIN=1 \
  "$NCO_ROOT/bin/deploy.sh" frontend test 2>&1); rc=$?

assert_eq "0" "$rc"                                  "planC: subsequent happy path exits 0"
assert_contains "$out" "subsequent run, resource trigger expected" "planC: subsequent header"
assert_contains "$out" "[1/1]"                       "planC: subsequent shows [1/1] without --watch"
assert_contains "$out" "ABC100001-myservice-frontend-deploy" "planC: subsequent triggers frontend-deploy"
assert_contains "$out" "run 4521"                    "planC: subsequent prints run id"
assert_contains "$out" "succeeded"                   "planC: subsequent watch reports success"
assert_contains "$out" "Deploy complete"             "planC: subsequent prints completion"

rm -rf "$src" "$iac" "$az_fixtures"

# --- Subsequent path with --watch: also polls IaC for auto-triggered run ---

paths=$(setup_full_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')
write_pipeline_list_fixtures "$az_fixtures"
cat > "$az_fixtures/az_pipelines_runs_list_proj_IaC.tsv" <<'EOF'
3
EOF
cat > "$az_fixtures/az_pipelines_run_proj_FrontProj.tsv" <<'EOF'
4521
EOF
printf 'completed\tsucceeded\n' > "$az_fixtures/az_pipelines_runs_show_proj_FrontProj.tsv"
printf 'completed\tsucceeded\n' > "$az_fixtures/az_pipelines_runs_show_proj_IaC.tsv"

# Override pipelines_runs_list_proj_IaC for the --watch polling: when the
# function queries [?reason=='resourceTrigger'] | [0].id, return the run id
# directly via a separate fixture.
# (Same fixture key, since stub doesn't distinguish by --query; need to swap
# content before the second call.)
# Workaround: the `--top 5` query for resource trigger doesn't get a separate
# stub key, but the response can serve both. Provide a fixture whose first
# line is the count (used by is_first_time_deploy) AND can parse as a run id.
# Actually -- the simpler fix: separate fixtures by overwriting between calls
# isn't feasible. Restructure to use NCO_TEST_AZ_KEY override.
# For now, set the fixture to "8932" (a run id) and accept that
# is_first_time_deploy sees "8932" which becomes count=8932 >= 1 → subsequent.
cat > "$az_fixtures/az_pipelines_runs_list_proj_IaC.tsv" <<'EOF'
8932
EOF

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  NCO_WATCH_INTERVAL=0 NCO_WATCH_TIMEOUT_MIN=1 \
  "$NCO_ROOT/bin/deploy.sh" frontend test --watch 2>&1); rc=$?

assert_eq "0" "$rc"                              "planC: subsequent --watch exits 0"
assert_contains "$out" "[1/2]"                   "planC: --watch shows [1/2]"
assert_contains "$out" "[2/2]"                   "planC: --watch shows [2/2] for IaC"
assert_contains "$out" "ABC100001-myservice-frontend-deploy-test" "planC: --watch references IaC deploy-test"

rm -rf "$src" "$iac" "$az_fixtures"

# --- First-time path (deploy-test has zero prior successes) ---

paths=$(setup_full_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')
write_pipeline_list_fixtures "$az_fixtures"
cat > "$az_fixtures/az_pipelines_runs_list_proj_IaC.tsv" <<'EOF'
0
EOF
# Pipeline triggers for both projects
cat > "$az_fixtures/az_pipelines_run_proj_FrontProj.tsv" <<'EOF'
4521
EOF
cat > "$az_fixtures/az_pipelines_run_proj_IaC.tsv" <<'EOF'
8932
EOF
# Watch fixtures (same key for both projects, different content per project)
printf 'completed\tsucceeded\n' > "$az_fixtures/az_pipelines_runs_show_proj_FrontProj.tsv"
printf 'completed\tsucceeded\n' > "$az_fixtures/az_pipelines_runs_show_proj_IaC.tsv"

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  NCO_WATCH_INTERVAL=0 NCO_WATCH_TIMEOUT_MIN=1 \
  "$NCO_ROOT/bin/deploy.sh" frontend test 2>&1); rc=$?

assert_eq "0" "$rc"                                "planC: first-time happy path exits 0"
assert_contains "$out" "FIRST-TIME — full chain"   "planC: first-time header"
assert_contains "$out" "[1/4]"                     "planC: first-time shows step 1/4"
assert_contains "$out" "[2/4]"                     "planC: first-time shows step 2/4"
assert_contains "$out" "[3/4]"                     "planC: first-time shows step 3/4"
assert_contains "$out" "[4/4]"                     "planC: first-time shows step 4/4"
assert_contains "$out" "frontend-build"            "planC: first-time triggers build"
assert_contains "$out" "frontend-infra-build"      "planC: first-time triggers infra-build"
assert_contains "$out" "frontend-deploy-test"      "planC: first-time triggers deploy-test"
assert_contains "$out" "Deploy complete"           "planC: first-time prints summary"
assert_contains "$out" "Container app: ca-abc100001-frontend" "planC: first-time prints derived container app"
assert_contains "$out" "Public URL:    https://frontend.example.cloud" "planC: first-time prints public URL"
assert_contains "$out" "Front Door + cert ~30-90 min" "planC: first-time prints --watch-live hint"

rm -rf "$src" "$iac" "$az_fixtures"

# --- First-time partial failure: step 2 fails → no further triggers ---

paths=$(setup_full_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')
write_pipeline_list_fixtures "$az_fixtures"
cat > "$az_fixtures/az_pipelines_runs_list_proj_IaC.tsv" <<'EOF'
0
EOF
cat > "$az_fixtures/az_pipelines_run_proj_FrontProj.tsv" <<'EOF'
4521
EOF
printf 'completed\tfailed\n' > "$az_fixtures/az_pipelines_runs_show_proj_FrontProj.tsv"

# NOTE: we don't write az_pipelines_run_proj_IaC.tsv. If step 3 fires, trigger_pipeline
# will die because the stub has no fixture. The test passes iff step 2 fails fast.

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  NCO_WATCH_INTERVAL=0 NCO_WATCH_TIMEOUT_MIN=1 \
  "$NCO_ROOT/bin/deploy.sh" frontend test 2>&1); rc=$?

assert_eq "1" "$rc"                            "planC: first-time partial failure exits 1"
assert_contains "$out" "step 1/4 (build)"      "planC: failure message names step 1 (first failed step)"
case "$out" in
  *"[3/4]"*) fail "planC: pipeline 3 was triggered after step 1 failed" "got: $out" ;;
  *)         pass "planC: failure short-circuits — step 3 not triggered" ;;
esac

rm -rf "$src" "$iac" "$az_fixtures"

# --- Missing pipeline: PR-A not merged (no FrontendPlatform pipelines) ---

paths=$(setup_full_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')
# Empty FrontendPlatform list — pipelines missing
cat > "$az_fixtures/az_pipelines_list_proj_FrontProj.tsv" <<'EOF'
EOF
cat > "$az_fixtures/az_pipelines_list_proj_IaC.tsv" <<'EOF'
2003	ABC100001-myservice-frontend-infra-build
2004	ABC100001-myservice-frontend-deploy-test
EOF
cat > "$az_fixtures/az_pipelines_runs_list_proj_IaC.tsv" <<'EOF'
0
EOF

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  NCO_WATCH_INTERVAL=0 NCO_WATCH_TIMEOUT_MIN=1 \
  "$NCO_ROOT/bin/deploy.sh" frontend test 2>&1); rc=$?

assert_eq "1" "$rc"                              "planC: missing FrontendPlatform pipeline exit 1"
assert_contains "$out" "PR-A"                    "planC: missing pipeline error names PR-A"
assert_contains "$out" "frontend-build"          "planC: missing pipeline error names the missing pipeline"

rm -rf "$src" "$iac" "$az_fixtures"

# --- Missing pipeline: PR-B not merged (no IaC pipelines) ---

paths=$(setup_full_fixture)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')
cat > "$az_fixtures/az_pipelines_list_proj_FrontProj.tsv" <<'EOF'
1128	ABC100001-myservice-frontend-build
1129	ABC100001-myservice-frontend-deploy
EOF
cat > "$az_fixtures/az_pipelines_list_proj_IaC.tsv" <<'EOF'
EOF
cat > "$az_fixtures/az_pipelines_runs_list_proj_IaC.tsv" <<'EOF'
0
EOF

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  NCO_WATCH_INTERVAL=0 NCO_WATCH_TIMEOUT_MIN=1 \
  "$NCO_ROOT/bin/deploy.sh" frontend test 2>&1); rc=$?

assert_eq "1" "$rc"                              "planC: missing IaC pipeline exit 1"
assert_contains "$out" "PR-B"                    "planC: missing IaC pipeline error names PR-B"
assert_contains "$out" "platform-infrastructure" "planC: missing IaC pipeline error names the IaC repo"

rm -rf "$src" "$iac" "$az_fixtures"

summary
