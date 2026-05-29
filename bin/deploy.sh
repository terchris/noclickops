#!/usr/bin/env bash
# bin/deploy.sh — multi-pipeline deploy orchestration for v2.
#
# v1 triggered a single "<repo>-<svc>-CD" pipeline. The new layout splits
# the work across five pipelines in two ADO projects:
#
#     <source-project>/<repo>-<svc>-build         publishes the deploy-package
#     <source-project>/<repo>-<svc>-deploy        publishes deployment-package-<env>
#     ↓ resource trigger (auto, after first successful IaC deploy-test run)
#   IaC/<repo>-<svc>-infra-build                pushes image to ACR (first time only)
#   IaC/<repo>-<svc>-deploy-test                ARM deploys the container app
#
# Subsequent deploys only trigger the source project pipelines explicitly;
# the resource trigger fires IaC's deploy-test automatically. First-time
# deploys (no prior successful deploy-test) explicitly run all four in
# sequence — the ADO quirk is that resource triggers on freshly-registered
# pipelines don't activate until the pipeline has run once manually.
#
# --- noclickops metadata ---
SCRIPT_NAME="deploy"
SCRIPT_DESCRIPTION="Deploy a service to test or prod (v2 multi-pipeline orchestration)."
SCRIPT_USAGE="noclickops deploy <service> [test|prod] [--watch]"
SCRIPT_EXAMPLE="noclickops deploy frontend test --watch"
SCRIPT_CATEGORY="deploy"
SCRIPT_TAGS="cd pipeline azure-devops container-app deployment release"
SCRIPT_DETAILS="v2: orchestrates 2 or 4 pipelines across the source project + IaC depending on whether this is a first-time or subsequent deploy. Detection: queries IaC for prior successful <repo>-<svc>-deploy-test runs. Subsequent path triggers the source project's <repo>-<svc>-deploy and exits (with --watch, also follows the auto-triggered IaC deploy-test). First-time path runs build → deploy → infra-build → deploy-test in sequence with fail-fast and prints a summary including the Public URL for services with ENABLE_PUBLIC_ENDPOINT=true."
SCRIPT_AUTH="az login to the target's ADO tenant; user identity must have permission to run pipelines in both the source project and the IaC project."
SCRIPT_DEPENDS_ON="az git"
SCRIPT_SEE_ALSO="status info logs add-service"
SCRIPT_FLAGS=(
  "test|Deploy to the test environment (default)."
  "prod|Deploy to production."
  "--watch|For subsequent deploys, also poll + watch the IaC deploy-test run (auto-triggered by the source project deploy). First-time deploys always watch (chain requires it)."
  "-h, --help|Show this help and exit."
)
SCRIPT_EXIT_CODES=(
  "0|All pipelines in the chain succeeded (or, for subsequent without --watch, the source project deploy succeeded)."
  "1|Service config missing, pipeline missing (PR-A or PR-B not merged), pipeline failed, or az error."
)
# --- end metadata ---

set -euo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_dir/../lib/logging.sh"
. "$_dir/../lib/utilities.sh"
. "$_dir/../lib/paths.sh"
. "$_dir/../lib/metadata.sh"
. "$_dir/../lib/service-v2.sh"
unset _dir

case "${1:-}" in -h|--help) show_help "$0"; exit 0 ;; esac

service="${1:-}"
[ -n "$service" ] || die "Usage: $SCRIPT_USAGE"
shift

env="test"
watch=0
for a in "$@"; do
  case "$a" in
    test|prod) env="$a" ;;
    --watch)   watch=1 ;;
    *) die "Unknown argument: $a (expected test|prod or --watch)" ;;
  esac
done

[ -n "${TARGET_REPO:-}" ] || die "Not inside a git repository. cd into a repo and re-run."

nco_command_header "$service → $env"

# Load context. read_iac_variables gives us subscription / DNS zone for the
# summary line; read_service_config tells us whether the service is public.
read_service_config "$service" "$env"
read_iac_variables  "$env"

derive_azdo_context "$TARGET_REPO"

# Discover all five pipeline IDs in one pass.
pipelines_lines=$(discover_pipelines "$service")
frontend_build_id=""; frontend_deploy_id=""
iac_infra_build_id=""; iac_deploy_test_id=""; iac_deploy_prod_id=""
while IFS='=' read -r role id; do
  case "$role" in
    frontend_build)   frontend_build_id="$id" ;;
    frontend_deploy)  frontend_deploy_id="$id" ;;
    iac_infra_build)  iac_infra_build_id="$id" ;;
    iac_deploy_test)  iac_deploy_test_id="$id" ;;
    iac_deploy_prod)  iac_deploy_prod_id="$id" ;;
  esac
done <<< "$pipelines_lines"

iac_project=$(discover_iac_project)
repo="$AZDO_REPO"

iac_deploy_name="${repo}-${service}-deploy-${env}"
frontend_deploy_name="${repo}-${service}-deploy"
frontend_build_name="${repo}-${service}-build"
iac_infra_build_name="${repo}-${service}-infra-build"

case "$env" in
  test) iac_deploy_id="$iac_deploy_test_id" ;;
  prod) iac_deploy_id="$iac_deploy_prod_id" ;;
esac

# --- Detection ---

if is_first_time_deploy "$service"; then
  # ===== FIRST-TIME PATH =====
  [ -n "$frontend_build_id" ] \
    || die "Pipeline '$frontend_build_name' not found in $AZDO_PROJECT. Has 'add-service' PR-A (source repo) merged?"
  [ -n "$frontend_deploy_id" ] \
    || die "Pipeline '$frontend_deploy_name' not found in $AZDO_PROJECT. Has 'add-service' PR-A (source repo) merged?"
  [ -n "$iac_infra_build_id" ] \
    || die "Pipeline '$iac_infra_build_name' not found in $iac_project. Has 'add-service' PR-B (platform-infrastructure) merged?"
  [ -n "$iac_deploy_id" ] \
    || die "Pipeline '$iac_deploy_name' not found in $iac_project. Has 'add-service' PR-B (platform-infrastructure) merged?"

  log_step "Deploying '$service' → '$env' (FIRST-TIME — full chain, ~10 min)"

  printf "  [1/4] %s/%s   run " "$AZDO_PROJECT" "$frontend_build_name"
  run_id=$(trigger_pipeline "$AZDO_PROJECT" "$frontend_build_name" "targetEnvironment=$env")
  printf "%s … " "$run_id"
  if ! watch_run "$AZDO_PROJECT" "$run_id"; then
    die "Deploy failed at step 1/4 (build). See: $AZDO_ORG_URL/$AZDO_PROJECT/_build/results?buildId=$run_id"
  fi

  printf "  [2/4] %s/%s  run " "$AZDO_PROJECT" "$frontend_deploy_name"
  run_id=$(trigger_pipeline "$AZDO_PROJECT" "$frontend_deploy_name" "targetEnvironment=$env")
  printf "%s … " "$run_id"
  if ! watch_run "$AZDO_PROJECT" "$run_id"; then
    die "Deploy failed at step 2/4 (deploy). See: $AZDO_ORG_URL/$AZDO_PROJECT/_build/results?buildId=$run_id"
  fi

  printf "  [3/4] %s/%s   run " "$iac_project" "$iac_infra_build_name"
  run_id=$(trigger_pipeline "$iac_project" "$iac_infra_build_name")
  printf "%s … " "$run_id"
  if ! watch_run "$iac_project" "$run_id"; then
    die "Deploy failed at step 3/4 (infra-build). See: $AZDO_ORG_URL/$iac_project/_build/results?buildId=$run_id"
  fi

  printf "  [4/4] %s/%s   run " "$iac_project" "$iac_deploy_name"
  run_id=$(trigger_pipeline "$iac_project" "$iac_deploy_name")
  printf "%s … " "$run_id"
  if ! watch_run "$iac_project" "$run_id"; then
    die "Deploy failed at step 4/4 (deploy-${env}). See: $AZDO_ORG_URL/$iac_project/_build/results?buildId=$run_id"
  fi

  ca_name=$(derive_containerapp_name "$service")
  printf "\n${_NCO_BOLD}Deploy complete.${_NCO_NC}\n"
  printf "  Container app: %s (%s)\n" "$ca_name" "${IAC_COMMON_RESOURCE_GROUP_NAME:-<unknown>}"
  if [ "${SVC_CFG_ENABLE_PUBLIC_ENDPOINT:-}" = "true" ]; then
    public_host=$(public_url_for "$service" "$env" 2>/dev/null || true)
    if [ -n "$public_host" ]; then
      printf "  Public URL:    https://%s\n" "$public_host"
      printf "                 (first-time public endpoint — Front Door + cert ~30-90 min; run with --watch-live to follow)\n"
    fi
  else
    printf "  (no public endpoint configured for this service)\n"
  fi
  exit 0
fi

# ===== SUBSEQUENT PATH =====

[ -n "$frontend_deploy_id" ] \
  || die "Pipeline '$frontend_deploy_name' not found in $AZDO_PROJECT. Has 'add-service' PR-A (source repo) merged?"

log_step "Deploying '$service' → '$env' (subsequent run, resource trigger expected)"

if [ "$watch" -eq 1 ]; then
  printf "  [1/2] %s/%s  run " "$AZDO_PROJECT" "$frontend_deploy_name"
else
  printf "  [1/1] %s/%s  run " "$AZDO_PROJECT" "$frontend_deploy_name"
fi
run_id=$(trigger_pipeline "$AZDO_PROJECT" "$frontend_deploy_name" "targetEnvironment=$env")
printf "%s … " "$run_id"
if ! watch_run "$AZDO_PROJECT" "$run_id"; then
  die "Deploy failed at the source project/$frontend_deploy_name. See: $AZDO_ORG_URL/$AZDO_PROJECT/_build/results?buildId=$run_id"
fi

if [ "$watch" -eq 1 ]; then
  [ -n "$iac_deploy_id" ] \
    || die "Cannot follow IaC deploy-${env}: pipeline '$iac_deploy_name' not found in $iac_project."
  printf "  [2/2] %s/%s   waiting for auto-trigger" "$iac_project" "$iac_deploy_name"

  # Poll IaC for a recent run of $iac_deploy_id triggered by the resource
  # trigger (not a PR). Wait up to 60s for it to appear.
  iac_run_id=""
  for _i in 1 2 3 4 5 6; do
    iac_run_id=$(_nco_az pipelines runs list \
      --organization "$AZDO_ORG_URL" --project "$iac_project" \
      --pipeline-ids "$iac_deploy_id" --top 5 \
      --query "[?reason=='resourceTrigger'] | [0].id" \
      -o tsv 2>/dev/null | head -1)
    if [ -n "$iac_run_id" ] && [ "$iac_run_id" != "null" ]; then
      break
    fi
    printf "."
    sleep 10
  done

  if [ -z "$iac_run_id" ] || [ "$iac_run_id" = "null" ]; then
    printf "\n  (no IaC deploy-${env} run appeared within 60s — check $AZDO_ORG_URL/$iac_project)\n"
    exit 0
  fi

  printf " run %s … " "$iac_run_id"
  if ! watch_run "$iac_project" "$iac_run_id"; then
    die "IaC deploy-${env} failed. See: $AZDO_ORG_URL/$iac_project/_build/results?buildId=$iac_run_id"
  fi
fi

log_success "Deploy complete."
