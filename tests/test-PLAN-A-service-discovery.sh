#!/usr/bin/env bash
# tests/test-PLAN-A-service-discovery.sh — coverage for lib/service-v2.sh.
# All `az` and ADO-REST calls are stubbed; no real Azure access required.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-A: lib/service-v2.sh ──"

# --- Phase 1: module loads, public functions exist (stubs at this point) ---

out=$(bash -c ". '$NCO_ROOT/lib/service-v2.sh' && declare -F read_service_config" 2>&1)
assert_contains "$out" "read_service_config" "phase1: read_service_config defined"

for fn in read_iac_variables discover_iac_project discover_pipelines \
          discover_containerapp derive_containerapp_name public_url_for \
          yaml_var _nco_az _nco_ado_rest_get; do
  out=$(bash -c ". '$NCO_ROOT/lib/service-v2.sh' && declare -F $fn" 2>&1)
  assert_contains "$out" "$fn" "phase1: $fn defined"
done

# Idempotent loader
out=$(bash -c ". '$NCO_ROOT/lib/service-v2.sh' && . '$NCO_ROOT/lib/service-v2.sh' && echo ok" 2>&1)
assert_eq "ok" "$out" "phase1: double-source is a no-op"

# yaml_var smoke (parser lifted from v1, same semantics)
YAML_TMP=$(mktemp)
cat > "$YAML_TMP" <<'EOF'
APP_NAME: "abc100001"
COMMON_RG: 'rg-test-myteam-frontend-common'
DNS_ZONE_NAME: example.cloud
EMPTY: ""
EOF
out=$(bash -c ". '$NCO_ROOT/lib/service-v2.sh' && yaml_var '$YAML_TMP' APP_NAME")
assert_eq "abc100001" "$out" "phase1: yaml_var double-quoted"
out=$(bash -c ". '$NCO_ROOT/lib/service-v2.sh' && yaml_var '$YAML_TMP' COMMON_RG")
assert_eq "rg-test-myteam-frontend-common" "$out" "phase1: yaml_var single-quoted"
out=$(bash -c ". '$NCO_ROOT/lib/service-v2.sh' && yaml_var '$YAML_TMP' DNS_ZONE_NAME")
assert_eq "example.cloud" "$out" "phase1: yaml_var unquoted"
out=$(bash -c ". '$NCO_ROOT/lib/service-v2.sh' && yaml_var '$YAML_TMP' EMPTY")
assert_eq "" "$out" "phase1: yaml_var empty string"
out=$(bash -c ". '$NCO_ROOT/lib/service-v2.sh' && yaml_var '$YAML_TMP' MISSING")
assert_eq "" "$out" "phase1: yaml_var missing key returns empty"
rm -f "$YAML_TMP"

# v2 fixtures construct the expected shapes
src=$(make_v2_source_repo)
svc_dir=$(make_v2_service "$src" frontend)
[ -f "$svc_dir/config.test.yaml" ] && pass "phase1: make_v2_service writes config.test.yaml" \
  || fail "phase1: make_v2_service writes config.test.yaml" "missing $svc_dir/config.test.yaml"
[ -f "$svc_dir/config.prod.yaml" ] && pass "phase1: make_v2_service writes config.prod.yaml" \
  || fail "phase1: make_v2_service writes config.prod.yaml" "missing"
[ -f "$src/.pipelines/add-service.yaml" ] && pass "phase1: source repo has add-service.yaml" \
  || fail "phase1: source repo has add-service.yaml" "missing"
rm -rf "$src"

iac=$(make_v2_iac_repo ABC ABC100001-myservice)
[ -f "$iac/environments/ABC/ABC100001-myservice/infrastructure/.pipelines/variables/common.yaml" ] \
  && pass "phase1: make_v2_iac_repo writes common.yaml at expected path" \
  || fail "phase1: make_v2_iac_repo writes common.yaml" "wrong path"
[ -f "$iac/environments/ABC/ABC100001-myservice/infrastructure/.pipelines/variables/test.yaml" ] \
  && pass "phase1: make_v2_iac_repo writes test.yaml" \
  || fail "phase1: make_v2_iac_repo writes test.yaml" "missing"
rm -rf "$iac"

# --- Phase 2: read_service_config ---

src=$(make_v2_source_repo)
make_v2_service "$src" frontend true >/dev/null

# Happy path
out=$(bash -c "
  cd '$src'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  read_service_config frontend test
  printf 'PORT=%s\n' \"\$SVC_CFG_SERVICE_PORT\"
  printf 'CPU=%s\n' \"\$SVC_CFG_SERVICE_CPU\"
  printf 'HEALTH=%s\n' \"\$SVC_CFG_SERVICE_HEALTH_CHECK_PATH\"
  printf 'PUBLIC=%s\n' \"\$SVC_CFG_ENABLE_PUBLIC_ENDPOINT\"
  printf 'LOADED=%s\n' \"\$SVC_CFG__LOADED\"
" 2>&1)
assert_contains "$out" "PORT=3000"        "phase2: read_service_config exports SERVICE_PORT"
assert_contains "$out" "CPU=0.5"          "phase2: read_service_config exports SERVICE_CPU"
assert_contains "$out" "HEALTH=/health"   "phase2: read_service_config strips quotes"
assert_contains "$out" "PUBLIC=true"      "phase2: read_service_config exports ENABLE_PUBLIC_ENDPOINT"
assert_contains "$out" "LOADED=1"         "phase2: SVC_CFG__LOADED sentinel set"

# Prod env reads a different file
out=$(bash -c "
  cd '$src'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  read_service_config frontend prod
  printf 'MIN=%s\n' \"\$SVC_CFG_SERVICE_MIN_REPLICAS\"
" 2>&1)
assert_contains "$out" "MIN=1" "phase2: read_service_config reads prod.yaml correctly"

# Missing service errors clearly
out=$(bash -c "
  cd '$src'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  read_service_config nonexistent test
" 2>&1) && rc=0 || rc=$?
assert_eq "1" "$rc" "phase2: missing service returns non-zero"
assert_contains "$out" "config.test.yaml not found" "phase2: error names the missing file"

# Re-call wipes previous SVC_CFG_*
make_v2_service "$src" backend false >/dev/null
out=$(bash -c "
  cd '$src'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  read_service_config frontend test
  read_service_config backend test
  printf 'PUBLIC=%s\n' \"\$SVC_CFG_ENABLE_PUBLIC_ENDPOINT\"
" 2>&1)
assert_contains "$out" "PUBLIC=false" "phase2: re-call switches to new service config"

rm -rf "$src"

# --- Phase 2: read_iac_variables ---

src=$(make_v2_source_repo "https://dev.azure.com/AcmeCorp/SourceProj/_git/ABC100001-myservice")
iac=$(make_v2_iac_repo ABC ABC100001-myservice)
stub=$(v2_stub_ado_rest_path)

# Happy path: test env
out=$(bash -c "
  cd '$src'
  export NCO_TEST_IAC_ROOT='$iac'
  export NCO_ADO_REST_OVERRIDE='$stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  read_iac_variables test
  printf 'APP=%s\n'         \"\$IAC_APP_NAME\"
  printf 'TEAM=%s\n'        \"\$IAC_TEAM_NAME\"
  printf 'PROJECT=%s\n'     \"\$IAC_IAC_PROJECT\"
  printf 'SUB=%s\n'         \"\$IAC_SUBSCRIPTION_ID\"
  printf 'COMMON_RG=%s\n'   \"\$IAC_COMMON_RESOURCE_GROUP_NAME\"
  printf 'DNS=%s\n'         \"\$IAC_DNS_ZONE_NAME\"
  printf 'LOADED=%s\n'      \"\$IAC__LOADED\"
" 2>&1)
assert_contains "$out" "APP=abc100001"                                "phase2: IAC_APP_NAME from common.yaml"
assert_contains "$out" "TEAM=ABC"                                     "phase2: IAC_TEAM_NAME from common.yaml"
assert_contains "$out" "PROJECT=IaC"                                  "phase2: IAC_IAC_PROJECT from common.yaml"
assert_contains "$out" "SUB=3aec5ff4-d5d3-47d3-b860-c36f2bf3ca2d"     "phase2: IAC_SUBSCRIPTION_ID from test.yaml"
assert_contains "$out" "COMMON_RG=rg-test-myteam-frontend-common"     "phase2: IAC_COMMON_RESOURCE_GROUP_NAME from test.yaml"
assert_contains "$out" "DNS=example.cloud"                            "phase2: IAC_DNS_ZONE_NAME from test.yaml"
assert_contains "$out" "LOADED=1"                                     "phase2: IAC__LOADED sentinel set"

# Prod env reads the other file
out=$(bash -c "
  cd '$src'
  export NCO_TEST_IAC_ROOT='$iac'
  export NCO_ADO_REST_OVERRIDE='$stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  read_iac_variables prod
  printf 'COMMON_RG=%s\n' \"\$IAC_COMMON_RESOURCE_GROUP_NAME\"
  printf 'KV=%s\n'        \"\$IAC_KEY_VAULT_NAME\"
" 2>&1)
assert_contains "$out" "COMMON_RG=rg-prod-myteam-frontend-common" "phase2: read_iac_variables(prod) picks prod.yaml"
assert_contains "$out" "KV=kv-prod-myteam-shared"                 "phase2: read_iac_variables(prod) picks prod KV"

# Missing env file errors
out=$(bash -c "
  cd '$src'
  export NCO_TEST_IAC_ROOT='$iac'
  export NCO_ADO_REST_OVERRIDE='$stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  read_iac_variables staging
" 2>&1) && rc=0 || rc=$?
assert_eq "1" "$rc" "phase2: missing env file returns non-zero"
assert_contains "$out" "staging.yaml" "phase2: error names the missing env"

rm -rf "$src" "$iac"

# --- Phase 3: discover_iac_project ---

# Default (no overrides, no IAC vars loaded) → "IaC"
out=$(bash -c "
  unset NOCLICKOPS_IAC_PROJECT IAC_IAC_PROJECT
  . '$NCO_ROOT/lib/service-v2.sh'
  discover_iac_project
")
assert_eq "IaC" "$out" "phase3: discover_iac_project defaults to IaC"

# NOCLICKOPS_IAC_PROJECT env override wins
out=$(bash -c "
  export NOCLICKOPS_IAC_PROJECT=CustomIaC
  . '$NCO_ROOT/lib/service-v2.sh'
  discover_iac_project
")
assert_eq "CustomIaC" "$out" "phase3: NOCLICKOPS_IAC_PROJECT env wins"

# IAC_IAC_PROJECT (from common.yaml) used when no env override
out=$(bash -c "
  unset NOCLICKOPS_IAC_PROJECT
  export IAC_IAC_PROJECT=FromYaml
  . '$NCO_ROOT/lib/service-v2.sh'
  discover_iac_project
")
assert_eq "FromYaml" "$out" "phase3: IAC_IAC_PROJECT from common.yaml used as fallback"

# --- Phase 3: discover_pipelines ---

src=$(make_v2_source_repo "https://dev.azure.com/AcmeCorp/FrontProj/_git/ABC100001-myservice")
az_fixtures=$(mktemp -d)
az_stub=$(v2_stub_az_path)

# FrontendPlatform project lists 4 pipelines (add-service + frontend build/deploy + an unrelated one)
cat > "$az_fixtures/az_pipelines_list_proj_FrontProj.tsv" <<'EOF'
1125	ABC100001-myservice-add-service
1128	ABC100001-myservice-frontend-build
1129	ABC100001-myservice-frontend-deploy
1130	ABC100001-myservice-other-service-build
EOF
# IaC project lists 5 pipelines: CD, infra-add-service, infra-build, deploy-test, deploy-prod
cat > "$az_fixtures/az_pipelines_list_proj_IaC.tsv" <<'EOF'
2001	ABC100001-myservice-CD
2002	ABC100001-myservice-infra-add-service
2003	ABC100001-myservice-frontend-infra-build
2004	ABC100001-myservice-frontend-deploy-test
2005	ABC100001-myservice-frontend-deploy-prod
EOF

out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  discover_pipelines frontend
" 2>&1)
assert_contains "$out" "frontend_build=1128"  "phase3: discover_pipelines finds frontend_build"
assert_contains "$out" "frontend_deploy=1129" "phase3: discover_pipelines finds frontend_deploy"
assert_contains "$out" "iac_infra_build=2003" "phase3: discover_pipelines finds iac_infra_build"
assert_contains "$out" "iac_deploy_test=2004" "phase3: discover_pipelines finds iac_deploy_test"
assert_contains "$out" "iac_deploy_prod=2005" "phase3: discover_pipelines finds iac_deploy_prod"

# Pipelines that don't exist → empty value (not absent line)
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  discover_pipelines nonexistent
" 2>&1)
assert_contains "$out" "frontend_build=" "phase3: missing pipeline yields empty value"
assert_contains "$out" "iac_deploy_test=" "phase3: missing IaC pipeline yields empty value"

# NOCLICKOPS_IAC_PROJECT override is honored (queries CustomIaC, not IaC)
cat > "$az_fixtures/az_pipelines_list_proj_CustomIaC.tsv" <<'EOF'
9999	ABC100001-myservice-frontend-deploy-test
EOF
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  export NOCLICKOPS_IAC_PROJECT=CustomIaC
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  discover_pipelines frontend
" 2>&1)
assert_contains "$out" "iac_deploy_test=9999" "phase3: NOCLICKOPS_IAC_PROJECT redirects IaC queries"

rm -rf "$src" "$az_fixtures"

# --- Phase 4: derive_containerapp_name (pure) ---

src=$(make_v2_source_repo "https://dev.azure.com/AcmeCorp/FrontProj/_git/ABC100001-myservice")
out=$(bash -c "
  cd '$src'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  derive_containerapp_name frontend
" 2>&1)
assert_eq "ca-abc100001-frontend" "$out" "phase4: derive_containerapp_name lowercases prefix"

# Uppercase repo also normalises
src2=$(make_v2_source_repo "https://dev.azure.com/AcmeCorp/FrontProj/_git/XYZ900-Service")
out=$(bash -c "
  cd '$src2'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  derive_containerapp_name backend
" 2>&1)
assert_eq "ca-xyz900-backend" "$out" "phase4: derive_containerapp_name handles uppercase prefix"
rm -rf "$src2"

# --- Phase 4: discover_containerapp ---

az_fixtures=$(mktemp -d)
az_stub=$(v2_stub_az_path)

# Override path: SVC_APP_NAME_OVERRIDE + SVC_RG_OVERRIDE wins, no az calls needed
out=$(bash -c "
  cd '$src'
  export SVC_APP_NAME_OVERRIDE=ca-custom-name
  export SVC_RG_OVERRIDE=rg-custom
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  discover_containerapp frontend
" 2>&1)
assert_contains "$out" "name=ca-custom-name"      "phase4: override path returns override name"
assert_contains "$out" "resource_group=rg-custom" "phase4: override path returns override RG"

# (b) common-RG hit
cat > "$az_fixtures/az_containerapp_list_rg_rg-test-myteam-frontend-common.tsv" <<'EOF'
ca-abc100001-frontend	rg-test-myteam-frontend-common	ca-abc100001-frontend.examplehill-deadbeef12.westeurope.azurecontainerapps.io
EOF
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  export IAC__LOADED=1
  export IAC_COMMON_RESOURCE_GROUP_NAME=rg-test-myteam-frontend-common
  export IAC_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  discover_containerapp frontend
" 2>&1)
assert_contains "$out" "name=ca-abc100001-frontend"                   "phase4: (b) finds app in common RG"
assert_contains "$out" "resource_group=rg-test-myteam-frontend-common" "phase4: (b) emits RG from result"
assert_contains "$out" "fqdn=ca-abc100001-frontend.examplehill"        "phase4: (b) emits FQDN"

# (c) subscription-wide fallback: empty result in (b), hit in (c)
cat > "$az_fixtures/az_containerapp_list_rg_rg-empty.tsv" <<'EOF'
EOF
cat > "$az_fixtures/az_containerapp_list_sub_aaaa-1111-2222.tsv" <<'EOF'
ca-abc100001-frontend	rg-test-myteam-svc	ca-abc100001-frontend.examplehill-deadbeef12.westeurope.azurecontainerapps.io
EOF
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  export IAC__LOADED=1
  export IAC_COMMON_RESOURCE_GROUP_NAME=rg-empty
  export IAC_SUBSCRIPTION_ID=aaaa-1111-2222
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  discover_containerapp frontend
" 2>&1)
assert_contains "$out" "name=ca-abc100001-frontend" "phase4: (c) subscription-wide fallback fires after (b) empty"
assert_contains "$out" "resource_group=rg-test-myteam-svc" "phase4: (c) returns subscription-discovered RG"

# All paths fail: clear error naming override env vars
cat > "$az_fixtures/az_containerapp_list_rg_rg-none.tsv" <<'EOF'
EOF
cat > "$az_fixtures/az_containerapp_list_sub_bbbb-3333.tsv" <<'EOF'
EOF
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  export IAC__LOADED=1
  export IAC_COMMON_RESOURCE_GROUP_NAME=rg-none
  export IAC_SUBSCRIPTION_ID=bbbb-3333
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  discover_containerapp frontend
" 2>&1) && rc=0 || rc=$?
assert_eq "1" "$rc" "phase4: all-paths-fail returns non-zero"
assert_contains "$out" "SVC_APP_NAME_OVERRIDE" "phase4: failure message names override env var"

# IAC not loaded → clear error
out=$(bash -c "
  cd '$src'
  unset IAC__LOADED SVC_APP_NAME_OVERRIDE SVC_RG_OVERRIDE
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  discover_containerapp frontend
" 2>&1) && rc=0 || rc=$?
assert_eq "1" "$rc" "phase4: no-iac no-override fails"
assert_contains "$out" "read_iac_variables to run first" "phase4: failure points to prereq"

rm -rf "$az_fixtures"

# --- Phase 4: public_url_for ---

make_v2_service "$src" frontend true >/dev/null     # ENABLE_PUBLIC_ENDPOINT=true
make_v2_service "$src" backend false >/dev/null     # ENABLE_PUBLIC_ENDPOINT=false
iac=$(make_v2_iac_repo ABC ABC100001-myservice)
stub=$(v2_stub_ado_rest_path)

# Public service → returns <svc>.<dns>
out=$(bash -c "
  cd '$src'
  export NCO_TEST_IAC_ROOT='$iac'
  export NCO_ADO_REST_OVERRIDE='$stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  read_service_config frontend test
  read_iac_variables test
  public_url_for frontend test
" 2>&1)
assert_eq "frontend.example.cloud" "$out" "phase4: public_url_for returns <svc>.<dns> when public"

# Private service → empty stdout
out=$(bash -c "
  cd '$src'
  export NCO_TEST_IAC_ROOT='$iac'
  export NCO_ADO_REST_OVERRIDE='$stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  read_service_config backend test
  read_iac_variables test
  public_url_for backend test
" 2>&1)
assert_eq "" "$out" "phase4: public_url_for empty when ENABLE_PUBLIC_ENDPOINT != true"

# Missing prereqs → die
out=$(bash -c "
  cd '$src'
  unset SVC_CFG__LOADED IAC__LOADED
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  public_url_for frontend test
" 2>&1) && rc=0 || rc=$?
assert_eq "1" "$rc" "phase4: public_url_for without read_service_config dies"

rm -rf "$src" "$iac"

# --- Phase 1 (PLAN-C): _v2_pipeline_succeeded_count + is_first_time_deploy ---

src=$(make_v2_source_repo "https://dev.azure.com/AcmeCorp/FrontProj/_git/ABC100001-myservice")
az_fixtures=$(mktemp -d)
az_stub=$(v2_stub_az_path)

# IaC project lists — defines which deploy-test pipelines exist
cat > "$az_fixtures/az_pipelines_list_proj_IaC.tsv" <<'EOF'
2004	ABC100001-myservice-frontend-deploy-test
2005	ABC100001-myservice-frontend-deploy-prod
EOF

# Path A: deploy-test has zero successful runs → first-time
cat > "$az_fixtures/az_pipelines_runs_list_proj_IaC.tsv" <<'EOF'
0
EOF
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  is_first_time_deploy frontend && echo FIRST || echo SUBSEQUENT
" 2>&1)
assert_eq "FIRST" "$out" "planC-phase1: zero prior succeeded → first-time"

# Path B: ≥1 prior succeeded → subsequent
cat > "$az_fixtures/az_pipelines_runs_list_proj_IaC.tsv" <<'EOF'
3
EOF
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  is_first_time_deploy frontend && echo FIRST || echo SUBSEQUENT
" 2>&1)
assert_eq "SUBSEQUENT" "$out" "planC-phase1: prior successes → subsequent"

# Path C: deploy-test pipeline doesn't exist in IaC at all → first-time (empty id)
cat > "$az_fixtures/az_pipelines_list_proj_IaC.tsv" <<'EOF'
EOF
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  is_first_time_deploy frontend && echo FIRST || echo SUBSEQUENT
" 2>&1)
assert_eq "FIRST" "$out" "planC-phase1: missing deploy-test pipeline → first-time"

# _v2_pipeline_succeeded_count helper directly: empty pipeline id → 0
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  . '$NCO_ROOT/lib/azdo.sh' && derive_azdo_context '$src'
  _v2_pipeline_succeeded_count IaC ''
")
assert_eq "0" "$out" "planC-phase1: succeeded_count with empty pipeline id returns 0"

rm -rf "$src" "$az_fixtures"

# --- Phase 2 (PLAN-C): trigger_pipeline + watch_run ---

src=$(make_v2_source_repo "https://dev.azure.com/AcmeCorp/FrontProj/_git/ABC100001-myservice")
az_fixtures=$(mktemp -d)
az_stub=$(v2_stub_az_path)

# trigger_pipeline: az pipelines run returns a run id
cat > "$az_fixtures/az_pipelines_run_proj_FrontProj.tsv" <<'EOF'
4521
EOF
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  . '$NCO_ROOT/lib/azdo.sh' && derive_azdo_context '$src'
  trigger_pipeline FrontProj ABC100001-myservice-frontend-deploy
" 2>&1)
assert_eq "4521" "$out" "planC-phase2: trigger_pipeline echoes the run id"

# trigger_pipeline with parameters: stub returns same id; just verify no error
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  . '$NCO_ROOT/lib/azdo.sh' && derive_azdo_context '$src'
  trigger_pipeline FrontProj ABC100001-myservice-frontend-deploy targetEnvironment=test
" 2>&1)
assert_eq "4521" "$out" "planC-phase2: trigger_pipeline with parameters"

# trigger_pipeline empty id from az → die
rm -f "$az_fixtures/az_pipelines_run_proj_FrontProj.tsv"
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  . '$NCO_ROOT/lib/azdo.sh' && derive_azdo_context '$src'
  trigger_pipeline FrontProj ABC100001-myservice-frontend-deploy
" 2>&1) && rc=0 || rc=$?
assert_eq "1" "$rc"                              "planC-phase2: trigger_pipeline dies on az failure"
assert_contains "$out" "failed to start pipeline" "planC-phase2: trigger_pipeline error message"

# watch_run happy path: stub returns "completed\tsucceeded"
printf 'completed\tsucceeded\n' > "$az_fixtures/az_pipelines_runs_show_proj_IaC.tsv"
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  export NCO_WATCH_INTERVAL=0
  export NCO_WATCH_TIMEOUT_MIN=1
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  . '$NCO_ROOT/lib/azdo.sh' && derive_azdo_context '$src'
  watch_run IaC 8932
" 2>&1) && rc=0 || rc=$?
assert_eq "0" "$rc"                       "planC-phase2: watch_run succeeded → exit 0"
assert_contains "$out" "succeeded"        "planC-phase2: watch_run prints 'succeeded' summary"

# watch_run failure path
printf 'completed\tfailed\n' > "$az_fixtures/az_pipelines_runs_show_proj_IaC.tsv"
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  export NCO_WATCH_INTERVAL=0
  export NCO_WATCH_TIMEOUT_MIN=1
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  . '$NCO_ROOT/lib/azdo.sh' && derive_azdo_context '$src'
  watch_run IaC 8932
" 2>&1) && rc=0 || rc=$?
assert_eq "1" "$rc"                    "planC-phase2: watch_run failed → exit 1"
assert_contains "$out" "failed"        "planC-phase2: watch_run prints 'failed' summary"

# watch_run timeout: stub returns "inProgress\t" forever
printf 'inProgress\t\n' > "$az_fixtures/az_pipelines_runs_show_proj_IaC.tsv"
out=$(bash -c "
  cd '$src'
  export NCO_TEST_AZ_FIXTURES='$az_fixtures'
  export NCO_AZ_OVERRIDE='$az_stub'
  export NCO_WATCH_INTERVAL=0
  export NCO_WATCH_TIMEOUT_MIN=1
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/service-v2.sh'
  . '$NCO_ROOT/lib/azdo.sh' && derive_azdo_context '$src'
  watch_run IaC 8932
" 2>&1) && rc=0 || rc=$?
assert_eq "1" "$rc"                       "planC-phase2: watch_run timeout → exit 1"
assert_contains "$out" "timed out"        "planC-phase2: watch_run prints 'timed out'"

rm -rf "$src" "$az_fixtures"

summary
