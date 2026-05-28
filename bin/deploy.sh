#!/usr/bin/env bash
# bin/deploy.sh — trigger a service's CD pipeline.
#
# Pipeline name convention (v1): "<AZDO_REPO>-<service>-CD".
# Branch ref: always refs/heads/main (the target environment is selected via
# the 'targetEnvironment' pipeline parameter, not the source ref).
#
# --- noclickops metadata ---
SCRIPT_NAME="deploy"
SCRIPT_DESCRIPTION="Trigger a service's CD pipeline (test or prod)."
SCRIPT_USAGE="noclickops deploy <service> [test|prod] [--watch]"
SCRIPT_EXAMPLE="noclickops deploy test-holderdeord test --watch"
SCRIPT_CATEGORY="deploy"
# --- end metadata ---

set -euo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_dir/../lib/logging.sh"
. "$_dir/../lib/utilities.sh"
. "$_dir/../lib/paths.sh"
. "$_dir/../lib/metadata.sh"
. "$_dir/../lib/azdo.sh"
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

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."

# Validate the service folder exists in the target repo. Catches typos before
# any az call. Assumes the FRT-shaped 'services/<name>/' layout — see PLAN-004
# for the v1 scoping note.
if [ ! -d "$TARGET_REPO/services/$service" ]; then
  if [ -d "$TARGET_REPO/services" ]; then
    available="$(ls -1 "$TARGET_REPO/services" 2>/dev/null | sed 's/^/  /')"
    die "Service '$service' not found at $TARGET_REPO/services/$service.
Available services:
$available"
  else
    die "Service '$service' not found and $TARGET_REPO has no 'services/' directory."
  fi
fi

derive_azdo_context "$TARGET_REPO"
require_az

pipeline="$AZDO_REPO-$service-CD"
log_step "Deploying '$service' to '$env'  (pipeline: $pipeline)"

run_id="$(az pipelines run --name "$pipeline" --branch refs/heads/main \
  --parameters "targetEnvironment=$env" --query id -o tsv)"

run_url="$AZDO_ORG_URL/$AZDO_PROJECT/_build/results?buildId=$run_id"
log_success "Started run $run_id"
echo "  $run_url"

if [ "$watch" -eq 1 ]; then
  log_info "Watching (Ctrl-C to stop watching; the run keeps going)..."
  # 90 * 20s = 30 min max wait.
  for _ in $(seq 1 90); do
    st="$(az pipelines runs show --id "$run_id" --query status -o tsv)"
    if [ "$st" = "completed" ]; then
      res="$(az pipelines runs show --id "$run_id" --query result -o tsv)"
      if [ "$res" = "succeeded" ]; then
        log_success "Deploy succeeded (run $run_id)."
        exit 0
      else
        die "Deploy finished with result '$res'. See: $run_url"
      fi
    fi
    sleep 20
  done
  log_warn "Timed out after 30min watching run $run_id. The run keeps going; check: $run_url"
fi
