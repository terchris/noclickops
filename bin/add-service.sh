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
SCRIPT_USAGE="noclickops add-service <service-name> [--persistent-storage] [--no-public-endpoint]"
SCRIPT_EXAMPLE="noclickops add-service test-myapp"
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

for a in "$@"; do
  case "$a" in
    --persistent-storage) persistent_storage="true" ;;
    --no-public-endpoint) public_endpoint="false" ;;
    -*)  die "Unknown flag: $a (expected --persistent-storage or --no-public-endpoint)" ;;
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

# Fire-and-forget: add-service typically takes ~1h (provisions infra, runs
# Copier, opens a PR, creates the new CD pipeline). Watching that from a
# terminal is hostile; the user comes back later with 'noclickops status'.
echo ""
echo "This pipeline takes ~1 hour. The shell returns now."
echo ""
echo "Check progress any time:"
echo "  noclickops status $run_id"
echo ""
echo "When the run completes, the pipeline will have opened PR 'Add service $service'."
echo "Then:"
echo "  noclickops merge-pr <pr-id>                          # squash + sync"
echo "  noclickops clean-sample $service                      # (if removing the sample)"
echo "  noclickops sync-lovable <lovable-repo> $service       # (if syncing a Lovable app)"
echo "  noclickops deploy $service test --watch               # deploy to test"
