#!/usr/bin/env bash
# tests/test-PLAN-004-deploy.sh — coverage for bin/deploy.sh.
# All assertions exercise pre-az validation; no real az calls.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-004: deploy ──"

# 1. Lister shows Deployment section.
out=$("$NCO_ROOT/bin/noclickops.sh" 2>&1)
assert_contains "$out" "Deployment" "lister has 'Deployment' section"
assert_contains "$out" "deploy"     "lister shows deploy"

# 2. --help.
out=$("$NCO_ROOT/bin/deploy.sh" --help 2>&1)
assert_contains "$out" "Category: deploy"               "deploy --help shows category"
assert_contains "$out" "deploy <service> [test|prod]"   "deploy --help shows usage"

# 3. No args → usage error.
out=$("$NCO_ROOT/bin/deploy.sh" 2>&1); rc=$?
assert_eq "1" "$rc"             "deploy no args exit 1"
assert_contains "$out" "Usage:" "deploy no args shows usage"

# Build a target repo + a service folder for the rest.
repo=$(make_target_repo)
make_service "$repo" "myservice" >/dev/null

# 4. Unknown flag → error before az.
out=$(cd "$repo" && "$NCO_ROOT/bin/deploy.sh" myservice --foo 2>&1); rc=$?
assert_eq "1" "$rc"                             "deploy unknown flag exit 1"
assert_contains "$out" "Unknown argument"       "deploy unknown flag shows error"

# 5. Unknown service → "Available services:" listing.
make_service "$repo" "svc-b" >/dev/null
make_service "$repo" "svc-c" >/dev/null
out=$(cd "$repo" && "$NCO_ROOT/bin/deploy.sh" ghost 2>&1); rc=$?
assert_eq "1" "$rc"                              "deploy unknown service exit 1"
assert_contains "$out" "Available services:"    "deploy unknown service lists available"
assert_contains "$out" "myservice"               "list includes myservice"
assert_contains "$out" "svc-b"                   "list includes svc-b"

rm -rf "$repo"

# 6. Target repo with no services/ directory.
repo2=$(make_target_repo)
out=$(cd "$repo2" && "$NCO_ROOT/bin/deploy.sh" anything 2>&1); rc=$?
assert_eq "1" "$rc"                                       "deploy no services/ exit 1"
assert_contains "$out" "has no 'services/' directory"     "deploy reports missing services/"
rm -rf "$repo2"

# 7. Outside a git repo → clear error.
out=$(cd /tmp && "$NCO_ROOT/bin/deploy.sh" anything 2>&1); rc=$?
assert_eq "1" "$rc"                                  "deploy outside repo exit 1"
assert_contains "$out" "Not inside a git repository" "deploy outside repo shows error"

# 8. Pipeline name composition from derived AZDO_REPO.
repo3=$(make_target_repo "https://dev.azure.com/AcmeCorp/Platform/_git/some-app")
make_service "$repo3" "myservice" >/dev/null
out=$(bash -c "
  . '$NCO_ROOT/lib/azdo.sh'
  derive_azdo_context '$repo3'
  printf '%s-%s-CD\n' \"\$AZDO_REPO\" myservice
")
assert_eq "some-app-myservice-CD" "$out" "pipeline name = AZDO_REPO-service-CD"
rm -rf "$repo3"

summary
