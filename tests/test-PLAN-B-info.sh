#!/usr/bin/env bash
# tests/test-PLAN-B-info.sh — coverage for bin/info.sh (v2).
# All `az` + ADO REST calls go through the v2 stubs. No real cloud access.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-B: bin/info.sh (v2) ──"

# --- Boilerplate negative cases ---

# 1. --help works (renders v2 metadata)
out=$("$NCO_ROOT/bin/info.sh" --help 2>&1)
assert_contains "$out" "Category: inspect"          "phase2: --help shows category"
assert_contains "$out" "noclickops info <service>"  "phase2: --help shows usage"
assert_contains "$out" "config.<env>.yaml"          "phase2: --help describes v2 source"

# 2. No args → usage
out=$("$NCO_ROOT/bin/info.sh" 2>&1); rc=$?
assert_eq "1" "$rc"              "phase2: no args exit 1"
assert_contains "$out" "Usage:"  "phase2: no args shows usage"

# 3. Outside a git repo
out=$(cd /tmp && "$NCO_ROOT/bin/info.sh" frontend 2>&1); rc=$?
assert_eq "1" "$rc"                                   "phase2: outside repo exit 1"
assert_contains "$out" "Not inside a git repository" "phase2: outside repo error"

# 4. Invalid env
src=$(make_v2_source_repo)
make_v2_service "$src" frontend true >/dev/null
out=$(cd "$src" && "$NCO_ROOT/bin/info.sh" frontend staging 2>&1); rc=$?
assert_eq "1" "$rc"                              "phase2: invalid env exit 1"
assert_contains "$out" "env must be"             "phase2: invalid env error"
rm -rf "$src"

# 5. Missing service config
src=$(make_v2_source_repo)
out=$(cd "$src" && "$NCO_ROOT/bin/info.sh" ghost test 2>&1); rc=$?
assert_eq "1" "$rc"                            "phase2: missing service exit 1"
assert_contains "$out" "config.test.yaml not found" "phase2: missing service error"
rm -rf "$src"

# --- Static + Public URL + Live: full fixture wiring ---

setup_full_fixture() {
  # Echoes "src iac az_fixtures" on stdout (space-separated paths).
  local public="${1:-true}"
  local src iac az_fixtures
  src=$(make_v2_source_repo "https://dev.azure.com/AcmeCorp/FrontProj/_git/ABC100001-myservice")
  make_v2_service "$src" frontend "$public" >/dev/null
  iac=$(make_v2_iac_repo ABC ABC100001-myservice)
  az_fixtures=$(mktemp -d)
  # account show — satisfies the az login check in bin/info.sh
  echo '{"id":"3aec5ff4-d5d3-47d3-b860-c36f2bf3ca2d"}' > "$az_fixtures/az_account_show.json"
  printf '%s %s %s' "$src" "$iac" "$az_fixtures"
}

# Common stubs + env wiring; caller exports NCO_TEST_IAC_ROOT + NCO_TEST_AZ_FIXTURES + NCO_AZ_OVERRIDE + NCO_ADO_REST_OVERRIDE.
ado_stub=$(v2_stub_ado_rest_path)
az_stub=$(v2_stub_az_path)

# --- Happy path: public service, live state hits ---

paths=$(setup_full_fixture true)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')

# discover_containerapp step (b): hit in IAC_COMMON_RESOURCE_GROUP_NAME
cat > "$az_fixtures/az_containerapp_list_rg_rg-test-myteam-frontend-common.tsv" <<'EOF'
ca-abc100001-frontend	rg-test-myteam-frontend-common	ca-abc100001-frontend.examplehill-deadbeef12.westeurope.azurecontainerapps.io
EOF
# az containerapp show — provides the detail row
cat > "$az_fixtures/az_containerapp_show_rg_rg-test-myteam-frontend-common_sub_3aec5ff4-d5d3-47d3-b860-c36f2bf3ca2d.tsv" <<'EOF'
Running	ca-abc100001-frontend--rev42	acrshareduw.azurecr.io/abc100001/frontend:latest	1	3
EOF

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  "$NCO_ROOT/bin/info.sh" frontend test 2>&1)

assert_contains "$out" "Service: frontend (test)"            "phase2: header line"
assert_contains "$out" "App name (IaC):     abc100001"       "phase2: IAC_APP_NAME line"
assert_contains "$out" "Application name:   myservice"       "phase2: IAC_APPLICATION_NAME line"
assert_contains "$out" "Team:               ABC"             "phase2: IAC_TEAM_NAME line"
assert_contains "$out" "Subscription:       3aec5ff4"        "phase2: IAC_SUBSCRIPTION_ID line"
assert_contains "$out" "Common RG:          rg-test-myteam-frontend-common" "phase2: COMMON_RG line"
assert_contains "$out" "Container registry: acrshareduw"     "phase2: registry line"
assert_contains "$out" "DNS zone:           example.cloud"   "phase2: DNS zone line"
assert_contains "$out" "Port:               3000"            "phase2: SERVICE_PORT line"
assert_contains "$out" "Health check:       /health"         "phase2: SERVICE_HEALTH_CHECK_PATH line"
assert_contains "$out" "CPU:                0.5"             "phase2: SERVICE_CPU line"
assert_contains "$out" "Memory:             1Gi"             "phase2: SERVICE_MEMORY line"
assert_contains "$out" "Public endpoint:    true"            "phase2: public-endpoint line"
assert_contains "$out" "Public URL:         https://frontend.example.cloud" "phase2: public URL line (public)"
assert_contains "$out" "Container app:      ca-abc100001-frontend" "phase2: live name line"
assert_contains "$out" "Resource group:     rg-test-myteam-frontend-common" "phase2: live RG line"
assert_contains "$out" "Internal FQDN:      ca-abc100001-frontend.examplehill" "phase2: live FQDN line"
assert_contains "$out" "Status:             Running"         "phase2: live status line"
assert_contains "$out" "Latest revision:    ca-abc100001-frontend--rev42" "phase2: live revision line"
assert_contains "$out" "Image:              acrshareduw.azurecr.io" "phase2: live image line"
assert_contains "$out" "Replicas (live):    min=1, max=3"    "phase2: live replicas line"

rm -rf "$src" "$iac" "$az_fixtures"

# --- Public URL omitted for private service ---

paths=$(setup_full_fixture false)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  "$NCO_ROOT/bin/info.sh" frontend test 2>&1)

assert_contains "$out" "Public endpoint:    false" "phase2: private shows public-endpoint=false"
case "$out" in
  *"Public URL:"*) fail "phase2: private service must NOT print Public URL line" "got: $out" ;;
  *)               pass "phase2: private service omits Public URL line" ;;
esac

rm -rf "$src" "$iac" "$az_fixtures"

# --- Live section degrades when discover_containerapp returns empty ---

paths=$(setup_full_fixture true)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')

# No matching app in common RG, no matching app in subscription-wide list:
cat > "$az_fixtures/az_containerapp_list_rg_rg-test-myteam-frontend-common.tsv" <<'EOF'
EOF
cat > "$az_fixtures/az_containerapp_list_sub_3aec5ff4-d5d3-47d3-b860-c36f2bf3ca2d.tsv" <<'EOF'
EOF

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  "$NCO_ROOT/bin/info.sh" frontend test 2>&1); rc=$?

assert_eq "0" "$rc" "phase2: degradation path exits 0"
assert_contains "$out" "App name (IaC):     abc100001"       "phase2: static section still printed on degradation"
assert_contains "$out" "Port:               3000"            "phase2: service config still printed on degradation"
assert_contains "$out" "(live state unavailable"             "phase2: live section prints unavailable message"
assert_contains "$out" "SVC_APP_NAME_OVERRIDE"               "phase2: degradation message names override env var"

rm -rf "$src" "$iac" "$az_fixtures"

# --- Override path: SVC_APP_NAME_OVERRIDE + SVC_RG_OVERRIDE skips list call ---

paths=$(setup_full_fixture true)
src=$(echo "$paths" | awk '{print $1}')
iac=$(echo "$paths" | awk '{print $2}')
az_fixtures=$(echo "$paths" | awk '{print $3}')

# Note: NO containerapp list fixtures present. If the script attempts a list call,
# the stub will fail and we'll see a missing-fixture error in $out.
# az containerapp show against the overridden name+rg:
cat > "$az_fixtures/az_containerapp_show_rg_rg-override_sub_3aec5ff4-d5d3-47d3-b860-c36f2bf3ca2d.tsv" <<'EOF'
Running	ca-custom--rev1	acrshareduw.azurecr.io/custom:abc	2	5
EOF

out=$(cd "$src" && \
  NCO_TEST_IAC_ROOT="$iac" NCO_ADO_REST_OVERRIDE="$ado_stub" \
  NCO_TEST_AZ_FIXTURES="$az_fixtures" NCO_AZ_OVERRIDE="$az_stub" \
  SVC_APP_NAME_OVERRIDE=ca-custom SVC_RG_OVERRIDE=rg-override \
  "$NCO_ROOT/bin/info.sh" frontend test 2>&1)

assert_contains "$out" "Container app:      ca-custom"     "phase2: override path uses override name"
assert_contains "$out" "Resource group:     rg-override"   "phase2: override path uses override RG"
assert_contains "$out" "Latest revision:    ca-custom--rev1" "phase2: override path still queries show for details"
case "$out" in
  *"no fixture for az"*) fail "phase2: override path attempted a list call (should be skipped)" "got: $out" ;;
  *)                     pass "phase2: override path skipped containerapp list" ;;
esac

rm -rf "$src" "$iac" "$az_fixtures"

summary
