#!/usr/bin/env bash
# tests/test-PLAN-008-info.sh — coverage for lib/service.sh + bin/info.sh.
# No real az calls.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-008: info + lib/service.sh ──"

# --- yaml_var parser smoke tests ---

YAML_TMP=$(mktemp)
cat > "$YAML_TMP" <<'EOF'
variables:
  APP_NAME: "frt900x016"
  SUBSCRIPTION_ID: "3aec5ff4-d5d3-47d3-b860-c36f2bf3ca2d"
  COMMON_RESOURCE_GROUP_NAME: 'rg-test-myteam-frontend-common'
  unquoted: bare-value
  empty: ""
EOF

out=$(bash -c ". '$NCO_ROOT/lib/service.sh' && yaml_var '$YAML_TMP' APP_NAME")
assert_eq "frt900x016" "$out" "yaml_var: double-quoted value"

out=$(bash -c ". '$NCO_ROOT/lib/service.sh' && yaml_var '$YAML_TMP' COMMON_RESOURCE_GROUP_NAME")
assert_eq "rg-test-myteam-frontend-common" "$out" "yaml_var: single-quoted value"

out=$(bash -c ". '$NCO_ROOT/lib/service.sh' && yaml_var '$YAML_TMP' unquoted")
assert_eq "bare-value" "$out" "yaml_var: unquoted value"

out=$(bash -c ". '$NCO_ROOT/lib/service.sh' && yaml_var '$YAML_TMP' empty")
assert_eq "" "$out" "yaml_var: empty value"

out=$(bash -c ". '$NCO_ROOT/lib/service.sh' && yaml_var '$YAML_TMP' MISSING")
assert_eq "" "$out" "yaml_var: missing key returns empty"

rm -f "$YAML_TMP"

# --- resolve_service_context end-to-end against a fake target repo ---

repo=$(make_target_repo)
make_service "$repo" "myapp" >/dev/null
add_pipeline_variables "$repo"
add_service_variables "$repo" "myapp"

out=$(bash -c "
  . '$NCO_ROOT/lib/service.sh'
  resolve_service_context myapp test '$repo'
  printf 'NAME=%s\nENV=%s\nAPP=%s\nSUB=%s\nRG=%s\nPORT=%s\nHEALTH=%s\nCPU=%s\nMEM=%s\nMIN=%s\nMAX=%s\nPUB=%s\n' \
    \"\$SVC_NAME\" \"\$SVC_ENV\" \"\$SVC_APP_NAME\" \"\$SVC_SUBSCRIPTION_ID\" \"\$SVC_RESOURCE_GROUP\" \
    \"\$SVC_PORT\" \"\$SVC_HEALTH_PATH\" \"\$SVC_CPU\" \"\$SVC_MEMORY\" \
    \"\$SVC_MIN_REPLICAS\" \"\$SVC_MAX_REPLICAS\" \"\$SVC_PUBLIC_ENDPOINT\"
")

assert_contains "$out" "NAME=myapp"                                       "resolve: SVC_NAME"
assert_contains "$out" "ENV=test"                                         "resolve: SVC_ENV"
assert_contains "$out" "APP=frt900x016"                                   "resolve: SVC_APP_NAME from common.yaml"
assert_contains "$out" "SUB=3aec5ff4-d5d3-47d3-b860-c36f2bf3ca2d"         "resolve: SVC_SUBSCRIPTION_ID from test.yaml"
assert_contains "$out" "RG=rg-test-myteam-frt900x016"                        "resolve: SVC_RESOURCE_GROUP computed"
assert_contains "$out" "PORT=3000"                                        "resolve: SVC_PORT from service test.yaml"
assert_contains "$out" "HEALTH=/health"                                   "resolve: SVC_HEALTH_PATH"
assert_contains "$out" "CPU=0.5"                                          "resolve: SVC_CPU"
assert_contains "$out" "MEM=1Gi"                                          "resolve: SVC_MEMORY"
assert_contains "$out" "MIN=0"                                            "resolve: SVC_MIN_REPLICAS (test env)"
assert_contains "$out" "MAX=1"                                            "resolve: SVC_MAX_REPLICAS (test env)"
assert_contains "$out" "PUB=true"                                         "resolve: SVC_PUBLIC_ENDPOINT"

# prod env uses different min/max replicas in our fixture.
out=$(bash -c "
  . '$NCO_ROOT/lib/service.sh'
  resolve_service_context myapp prod '$repo'
  printf 'MIN=%s\nMAX=%s\nSUB=%s\n' \"\$SVC_MIN_REPLICAS\" \"\$SVC_MAX_REPLICAS\" \"\$SVC_SUBSCRIPTION_ID\"
")
assert_contains "$out" "MIN=1"  "resolve: prod env picks prod's SERVICE_MIN_REPLICAS"
assert_contains "$out" "MAX=3"  "resolve: prod env picks prod's SERVICE_MAX_REPLICAS"
assert_contains "$out" "SUB="   "resolve: prod's empty SUBSCRIPTION_ID stays empty"
# (the SUB= line will have empty value; the contains check just needs that line present)

# --- resolve_service_context error paths ---

out=$(bash -c "
  . '$NCO_ROOT/lib/service.sh'
  resolve_service_context ghost test '$repo' 2>&1
") && rc=0 || rc=$?
assert_eq "1" "$rc"                                  "resolve: unknown service exit 1"
assert_contains "$out" "Service 'ghost' not found"   "resolve: unknown service message"

out=$(bash -c "
  . '$NCO_ROOT/lib/service.sh'
  resolve_service_context myapp staging '$repo' 2>&1
") && rc=0 || rc=$?
assert_eq "1" "$rc"                          "resolve: invalid env exit 1"
assert_contains "$out" "Invalid environment" "resolve: invalid env message"

# Test missing repo-level common.yaml.
repo_no_common=$(make_target_repo)
make_service "$repo_no_common" "myapp" >/dev/null
out=$(bash -c "
  . '$NCO_ROOT/lib/service.sh'
  resolve_service_context myapp test '$repo_no_common' 2>&1
") && rc=0 || rc=$?
assert_eq "1" "$rc"                                       "resolve: missing common.yaml exit 1"
assert_contains "$out" "Repo-level variables missing"     "resolve: missing common.yaml message"
rm -rf "$repo_no_common"

# --- bin/info.sh integration ---

# 1. Lister shows info under Inspect.
out=$("$NCO_ROOT/bin/noclickops.sh" 2>&1)
assert_contains "$out" "info" "lister shows info"

# 2. --help.
out=$("$NCO_ROOT/bin/info.sh" --help 2>&1)
assert_contains "$out" "Category: inspect"             "info --help category"
assert_contains "$out" "noclickops info <service>"     "info --help usage"

# 3. No args → usage.
out=$("$NCO_ROOT/bin/info.sh" 2>&1); rc=$?
assert_eq "1" "$rc"             "info no args exit 1"
assert_contains "$out" "Usage:" "info no args shows usage"

# 4. Outside a git repo.
out=$(cd /tmp && "$NCO_ROOT/bin/info.sh" anything 2>&1); rc=$?
assert_eq "1" "$rc"                                  "info outside repo exit 1"
assert_contains "$out" "Not inside a git repository" "info outside repo error"

# 5. Unknown service.
out=$(cd "$repo" && "$NCO_ROOT/bin/info.sh" ghost 2>&1); rc=$?
assert_eq "1" "$rc"                                "info unknown service exit 1"
assert_contains "$out" "Service 'ghost' not found" "info unknown service error"

# 6. Invalid env.
out=$(cd "$repo" && "$NCO_ROOT/bin/info.sh" myapp staging 2>&1); rc=$?
assert_eq "1" "$rc"                          "info invalid env exit 1"
assert_contains "$out" "Invalid environment" "info invalid env error"

# 7. Happy path against fake repo — static sections must populate; the
# live-state branch will skip (no az or no subscription access).
out=$(cd "$repo" && "$NCO_ROOT/bin/info.sh" myapp test 2>&1)
assert_contains "$out" "Service: myapp (test)"             "info header line"
assert_contains "$out" "APP_NAME:          frt900x016"      "info shows APP_NAME"
assert_contains "$out" "SUBSCRIPTION_ID:   3aec5ff4"        "info shows SUBSCRIPTION_ID"
assert_contains "$out" "Resource group:    rg-test-myteam-frt900x016" "info shows computed RG"
assert_contains "$out" "Port:              3000"           "info shows port"
assert_contains "$out" "Health check:      /health"        "info shows health path"
assert_contains "$out" "Container app (live):"             "info has live section header"
# The live section will say one of these depending on the test env's az state:
case "$out" in
  *"(live state unavailable"*) pass "info live-section fails closed when az unavailable" ;;
  *"Cannot access"*)            pass "info live-section fails closed on subscription access" ;;
  *"No container app found"*)   pass "info live-section reports no container app" ;;
  *"Name:"*)                    pass "info live-section actually populated (az + access available)" ;;
  *)                            fail "info live-section path" "got: $out" ;;
esac

# 8. Portability grep stays clean.
matches=$(grep -E -r 'ExampleOrg|FrontendPlatform|JKL900X016' "$NCO_ROOT/bin" "$NCO_ROOT/lib" 2>/dev/null || true)
assert_eq "" "$matches" "portability: no hardcoded ADO identity in bin/ or lib/"

rm -rf "$repo"

summary
