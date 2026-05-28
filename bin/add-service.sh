#!/usr/bin/env bash
# bin/add-service.sh — trigger the Copier-based add-service pipeline.
#
# Pipeline contract (target-repo's '<AZDO_REPO>-add-service'):
#   parameters:
#     serviceName        - the new service folder name (becomes subdomain
#                          if public_endpoint=true)
#     persistent_storage - 'true' | 'false'   (default: false)
#     public_endpoint    - 'true' | 'false'   (default: true)
#
# The pipeline runs Copier, creates branch 'add-service-<name>', opens a PR
# to main, and registers the new '<AZDO_REPO>-<name>-CD' pipeline.
#
# --- noclickops metadata ---
SCRIPT_NAME="add-service"
SCRIPT_DESCRIPTION="Trigger the add-service pipeline to scaffold a new service."
SCRIPT_USAGE="noclickops add-service <service-name> [--persistent-storage] [--no-public-endpoint] [--watch]"
SCRIPT_EXAMPLE="noclickops add-service test-myapp --watch"
SCRIPT_CATEGORY="service-lifecycle"
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

# Defaults match the pipeline's own defaults — callers only specify what
# they want different.
persistent_storage="false"
public_endpoint="true"
watch=0

for a in "$@"; do
  case "$a" in
    --persistent-storage) persistent_storage="true" ;;
    --no-public-endpoint) public_endpoint="false" ;;
    --watch)              watch=1 ;;
    -*)  die "Unknown flag: $a (expected --persistent-storage, --no-public-endpoint, or --watch)" ;;
    *)   die "Unexpected positional argument: $a (only the service name is positional)" ;;
  esac
done

# Service-name shape validation — cheap local checks; the pipeline does the
# authoritative validation.
case "$service" in
  -*)   die "Service name '$service' must not start with '-'." ;;
  */*|*\\*) die "Service name '$service' must not contain path separators." ;;
  *' '*|*$'\t'*) die "Service name '$service' must not contain whitespace." ;;
esac
[ ${#service} -le 50 ] || die "Service name '$service' is too long (max 50 chars)."

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."

# Refuse if the service folder already exists — saves a doomed pipeline run.
if [ -d "$TARGET_REPO/services/$service" ]; then
  die "Service folder already exists: $TARGET_REPO/services/$service
If you meant to update it instead of create, use 'noclickops sync-lovable' or your editor."
fi

derive_azdo_context "$TARGET_REPO"
require_az

pipeline="$AZDO_REPO-add-service"
log_step "Triggering '$pipeline' to scaffold '$service'"
log_info  "  persistent_storage=$persistent_storage  public_endpoint=$public_endpoint"

run_id="$(az pipelines run --name "$pipeline" --branch refs/heads/main \
  --parameters \
    "serviceName=$service" \
    "persistent_storage=$persistent_storage" \
    "public_endpoint=$public_endpoint" \
  --query id -o tsv)"

run_url="$AZDO_ORG_URL/$AZDO_PROJECT/_build/results?buildId=$run_id"
log_success "Started run $run_id"
echo "  $run_url"

if [ "$watch" -eq 1 ]; then
  log_info "Watching (Ctrl-C to stop watching; the run keeps going)..."
  for _ in $(seq 1 90); do
    st="$(az pipelines runs show --id "$run_id" --query status -o tsv)"
    if [ "$st" = "completed" ]; then
      res="$(az pipelines runs show --id "$run_id" --query result -o tsv)"
      if [ "$res" = "succeeded" ]; then
        log_success "add-service pipeline succeeded."
        echo ""
        echo "Next steps:"
        echo "  1. The pipeline opened a PR titled 'Add service $service'."
        echo "  2. Review the diff, then complete with:  noclickops merge-pr <id>"
        echo "  3. After merge, customise the service: 'noclickops clean-sample $service'"
        echo "     and/or 'noclickops sync-lovable <lovable-repo> $service'."
        echo "  4. Deploy with:  noclickops deploy $service test --watch"
        exit 0
      else
        die "add-service finished with result '$res'. See: $run_url"
      fi
    fi
    sleep 20
  done
  log_warn "Timed out after 30min watching run $run_id. The run keeps going; check: $run_url"
else
  echo ""
  echo "Next steps:"
  echo "  1. Wait for the pipeline to finish (or re-run with --watch)."
  echo "  2. It opens PR 'Add service $service' on completion — merge with:"
  echo "       noclickops merge-pr <id>"
  echo "  3. Customise the service and deploy."
fi
