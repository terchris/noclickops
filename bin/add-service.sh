#!/usr/bin/env bash
# bin/add-service.sh — trigger the Copier-based add-service pipeline, watch
# it to completion, and merge the resulting scaffold PR.
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
# v1.3.0 (PLAN-102): observed runs are ~1 minute, not the ~1 hour PLAN-007a
# assumed. With a fast pipeline, the default is now watch + auto-merge.
# --no-merge restores PLAN-007a's fire-and-forget for callers that want it.
#
# --- noclickops metadata ---
SCRIPT_NAME="add-service"
SCRIPT_DESCRIPTION="Scaffold a new service (Copier pipeline + auto-merge the PR)."
SCRIPT_USAGE="noclickops add-service <service-name> [--persistent-storage] [--no-public-endpoint] [--no-merge]"
SCRIPT_EXAMPLE="noclickops add-service test-myapp --persistent-storage"
SCRIPT_CATEGORY="service-lifecycle"
SCRIPT_TAGS="scaffold copier pipeline new-service auto-merge"
SCRIPT_DETAILS="Triggers the Copier-based \`<AZDO_REPO>-add-service\` pipeline, watches it to completion (~1 min), finds the scaffold PR by source branch (\`add-service-<name>\`), and squash-merges it. --no-merge restores PLAN-007a's fire-and-forget behaviour for callers that want it."
SCRIPT_AUTH="az login to the target's ADO tenant."
SCRIPT_DEPENDS_ON="az git"
SCRIPT_SEE_ALSO="status merge-pr clean-sample sync-lovable"
SCRIPT_FLAGS=(
  "--persistent-storage|Provision a persistent volume for the service."
  "--no-public-endpoint|Internal-only; don't expose via ingress."
  "--no-merge|Trigger the pipeline and return immediately — don't watch or merge."
  "-h, --help|Show this help and exit."
)
SCRIPT_EXIT_CODES=(
  "0|Service scaffolded and PR merged to main."
  "1|Pipeline failed, timed out (10 min cap), or merge blocked by policy."
)
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
no_merge=0

for a in "$@"; do
  case "$a" in
    --persistent-storage) persistent_storage="true" ;;
    --no-public-endpoint) public_endpoint="false" ;;
    --no-merge)           no_merge=1 ;;
    -*)  die "Unknown flag: $a (expected --persistent-storage, --no-public-endpoint, or --no-merge)" ;;
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

# --- Fire-and-forget escape hatch (PLAN-007a behavior) ---
if [ "$no_merge" -eq 1 ]; then
  echo ""
  echo "Fire-and-forget mode (--no-merge). The shell returns now."
  echo ""
  echo "Check progress any time:"
  echo "  noclickops status $run_id"
  echo ""
  echo "When the run completes, the pipeline will have opened PR 'Add service $service'."
  echo "Then merge it manually:"
  echo "  noclickops merge-pr <pr-id>"
  exit 0
fi

# --- Watch the pipeline (default) ---
log_step "Watching pipeline (poll every 5s, 10 min cap)"
# 10 min = 120 iterations × 5s. Typical runs are ~1 min; this is insurance
# against package-install slowdowns and the like.
st=""
for _ in $(seq 1 120); do
  st="$(az pipelines runs show --id "$run_id" --query status -o tsv 2>/dev/null || echo "")"
  if [ "$st" = "completed" ]; then
    break
  fi
  sleep 5
done

if [ "$st" != "completed" ]; then
  log_warn "Pipeline didn't complete within 10 minutes (status: $st). It keeps running."
  echo "  Re-attach later: noclickops status $run_id"
  echo "  Then merge the PR it opens: noclickops merge-pr <pr-id>"
  exit 1
fi

result="$(az pipelines runs show --id "$run_id" --query result -o tsv)"
if [ "$result" != "succeeded" ]; then
  die "Pipeline finished with result '$result'. See: $run_url"
fi
log_success "Pipeline succeeded (run $run_id)."

# --- Find the scaffold PR ---
# The pipeline yaml hard-codes 'branchName: add-service-<serviceName>', so
# the source branch is deterministic.
log_step "Looking up the scaffold PR (source: add-service-$service)"
pr_id="$(az repos pr list --status active \
  --query "[?sourceRefName=='refs/heads/add-service-$service'] | [0].pullRequestId" \
  -o tsv 2>/dev/null || true)"

if [ -z "$pr_id" ] || [ "$pr_id" = "None" ]; then
  log_warn "No active PR found for branch add-service-$service."
  log_warn "Either Copier had nothing to commit, or the PR was completed/abandoned out-of-band."
  log_warn "Check the pipeline log:  $run_url"
  exit 0
fi
log_info "Found PR #$pr_id"

# --- Squash-merge via shared helper ---
if ! squash_complete_pr "$pr_id"; then
  log_error "Failed to merge PR #$pr_id."
  echo "  PR URL: $AZDO_ORG_URL/$AZDO_PROJECT/_git/$AZDO_REPO/pullrequest/$pr_id"
  exit 1
fi

# --- Sync local main ---
log_step "Syncing local main"
# add-service is normally run from main (we never branched). Fetch + ff.
git -C "$TARGET_REPO" fetch --prune
if git -C "$TARGET_REPO" merge --ff-only origin/main >/dev/null 2>&1; then
  log_success "Local main is in sync with origin/main."
else
  log_warn "Local main can't fast-forward — it has diverged from origin/main."
  echo "  If local main has nothing worth keeping:  git reset --hard origin/main"
fi

echo ""
log_success "Done. services/$service is on main."
echo ""
echo "Next steps:"
echo "  noclickops clean-sample $service                # strip the Next.js placeholder"
echo "  noclickops sync-lovable <lovable-repo> $service # (if syncing a Lovable app)"
echo "  noclickops deploy $service test --watch         # deploy to test"
