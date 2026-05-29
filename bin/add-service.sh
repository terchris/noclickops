#!/usr/bin/env bash
# bin/add-service.sh — scaffold a new service in the new two-project layout.
#
# v2: the add-service pipeline opens TWO PRs — PR-A in the source repo
# (service code) AND PR-B in IaC/platform-infrastructure (deploy YAML).
# Both must be merged for first-time deploys to succeed. This command
# auto-merges both by default; --no-merge restores fire-and-forget.
#
# Pipeline contract (target-repo's '<AZDO_REPO>-add-service' in v2):
#   parameters:
#     serviceType        - 'containerapps' (only option for now; default)
#     serviceName        - the new service folder name
#     persistent_storage - 'true' | 'false'   (default: false)
#     public_endpoint    - 'true' | 'false'   (default: false — internal-first)
#
# --- noclickops metadata ---
SCRIPT_NAME="add-service"
SCRIPT_DESCRIPTION="Scaffold a new service (Copier pipeline + auto-merge BOTH PRs)."
SCRIPT_USAGE="noclickops add-service <service-name> [--persistent-storage] [--public-endpoint] [--no-merge]"
SCRIPT_EXAMPLE="noclickops add-service backend --public-endpoint"
SCRIPT_CATEGORY="service-lifecycle"
SCRIPT_TAGS="scaffold copier pipeline new-service auto-merge two-pr iac"
SCRIPT_DETAILS="v2: triggers <repo>-add-service in the source project, watches it (~1 min), then auto-merges BOTH downstream PRs — PR-A in the source repo (service code) AND PR-B in IaC/platform-infrastructure (deploy YAML). Without PR-B merged, the first deploy fails with 'pipeline not found'. v1.5.x missed PR-B entirely; v2 closes that gap. --no-merge skips both merges; the user takes ownership of completing them."
SCRIPT_AUTH="az login to the target's ADO tenant; user must be able to vote + complete PRs in both the source project AND IaC."
SCRIPT_DEPENDS_ON="az git"
SCRIPT_SEE_ALSO="status merge-pr clean-sample deploy"
SCRIPT_FLAGS=(
  "--persistent-storage|Provision a persistent volume for the service (default off)."
  "--public-endpoint|Expose via Front Door at <svc>.<dns-zone> (default internal-only)."
  "--no-merge|Trigger the pipeline and return after it succeeds — don't auto-merge either PR."
  "-h, --help|Show this help and exit."
)
SCRIPT_EXIT_CODES=(
  "0|Service scaffolded; both PRs auto-merged (or pipeline succeeded with --no-merge)."
  "1|Pipeline failed, PR-A merge failed, or PR-B didn't appear within the 5 min poll window."
)
# --- end metadata ---

set -euo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_dir/../lib/logging.sh"
. "$_dir/../lib/utilities.sh"
. "$_dir/../lib/paths.sh"
. "$_dir/../lib/metadata.sh"
. "$_dir/../lib/azdo.sh"
. "$_dir/../lib/service-v2.sh"
unset _dir

case "${1:-}" in -h|--help) show_help "$0"; exit 0 ;; esac

service="${1:-}"
[ -n "$service" ] || die "Usage: $SCRIPT_USAGE"
shift

persistent_storage="false"
public_endpoint="false"
no_merge=0

for a in "$@"; do
  case "$a" in
    --persistent-storage) persistent_storage="true" ;;
    --public-endpoint)    public_endpoint="true" ;;
    --no-merge)           no_merge=1 ;;
    -*)  die "Unknown flag: $a (expected --persistent-storage, --public-endpoint, or --no-merge)" ;;
    *)   die "Unexpected positional argument: $a (only the service name is positional)" ;;
  esac
done

# Service-name shape validation.
case "$service" in
  -*)            die "Service name '$service' must not start with '-'." ;;
  */*|*\\*)      die "Service name '$service' must not contain path separators." ;;
  *' '*|*$'\t'*) die "Service name '$service' must not contain whitespace." ;;
esac
[ ${#service} -le 50 ] || die "Service name '$service' is too long (max 50 chars)."

[ -n "${TARGET_REPO:-}" ] || die "Not inside a git repository. cd into a repo and re-run."

if [ -d "$TARGET_REPO/services/$service" ]; then
  die "Service folder already exists: $TARGET_REPO/services/$service"
fi

derive_azdo_context "$TARGET_REPO"

# Skip require_az when the az shim is overridden (test mode).
[ -n "${NCO_AZ_OVERRIDE:-}" ] || require_az

iac_project=$(discover_iac_project)

pipeline="$AZDO_REPO-add-service"
log_step "Triggering '$pipeline' to scaffold '$service'"
log_info  "  persistent_storage=$persistent_storage  public_endpoint=$public_endpoint"

run_id=$(trigger_pipeline "$AZDO_PROJECT" "$pipeline" \
  "serviceName=$service" \
  "persistent_storage=$persistent_storage" \
  "public_endpoint=$public_endpoint")

run_url="$AZDO_ORG_URL/$AZDO_PROJECT/_build/results?buildId=$run_id"
log_success "Started run $run_id"
echo "  $run_url"

log_step "Watching pipeline"
if ! watch_run "$AZDO_PROJECT" "$run_id" --timeout-min 10; then
  die "Pipeline failed. See: $run_url"
fi
log_success "Pipeline succeeded."

# --- Fire-and-forget escape hatch ---
if [ "$no_merge" -eq 1 ]; then
  echo ""
  echo "Fire-and-forget mode (--no-merge). The shell returns now."
  echo ""
  echo "Two PRs will appear in the next ~1-5 min:"
  echo "  PR-A (source repo)             — noclickops merge-pr <pr-a-id>"
  echo "  PR-B (IaC/platform-infrastructure) — needs cross-project merge:"
  echo "    az repos pr update --id <pr-b-id> --status completed --squash true --delete-source-branch true \\"
  echo "      --organization '$AZDO_ORG_URL' --project '$iac_project'"
  echo ""
  echo "Without PR-B merged, 'noclickops deploy $service' will fail with 'pipeline not found'."
  exit 0
fi

# --- Default: poll + merge BOTH PRs ---

source_branch="add-service-$service"

# PR-A: poll up to 3 min (downstream automation creates it after pipeline)
log_step "Waiting for PR-A in the source repo (branch: $source_branch)"
pr_a_poll_interval="${NCO_WATCH_INTERVAL:-10}"
pr_a_max_polls=18   # ~3 min default
pr_a_id=""
for _i in $(seq 1 "$pr_a_max_polls"); do
  pr_a_id=$(find_pr_in_project "$AZDO_PROJECT" "$AZDO_REPO" "$source_branch")
  [ -n "$pr_a_id" ] && break
  [ "$pr_a_poll_interval" -gt 0 ] && sleep "$pr_a_poll_interval"
done

if [ -z "$pr_a_id" ]; then
  die "PR-A didn't appear within 3 min. Check: $AZDO_ORG_URL/$AZDO_PROJECT/_git/$AZDO_REPO/pullrequests
The pipeline may have nothing to commit, or downstream automation hasn't fired yet."
fi
log_info "Found PR-A #$pr_a_id"

# Merge PR-A via the v2 cross-project-safe helper (works for source-project too).
if ! merge_pr_in_project "$pr_a_id" "$AZDO_PROJECT" "$AZDO_REPO"; then
  die "Failed to merge PR-A #$pr_a_id.
URL: $AZDO_ORG_URL/$AZDO_PROJECT/_git/$AZDO_REPO/pullrequest/$pr_a_id"
fi

# PR-B: poll up to 5 min (further downstream — IaC automation reacts to PR-A merge)
log_step "Waiting for PR-B in IaC/platform-infrastructure (branch: $source_branch)"
pr_b_timeout_min="${NCO_PR_B_TIMEOUT_MIN:-5}"
pr_b_poll_interval="${NCO_WATCH_INTERVAL:-10}"
pr_b_max_polls=$(( pr_b_timeout_min * 60 / (pr_b_poll_interval > 0 ? pr_b_poll_interval : 1) ))
[ "$pr_b_max_polls" -lt 1 ] && pr_b_max_polls=1
pr_b_id=""
for _i in $(seq 1 "$pr_b_max_polls"); do
  pr_b_id=$(find_pr_in_project "$iac_project" platform-infrastructure "$source_branch")
  [ -n "$pr_b_id" ] && break
  [ "$pr_b_poll_interval" -gt 0 ] && sleep "$pr_b_poll_interval"
done

if [ -z "$pr_b_id" ]; then
  log_error "PR-B didn't appear in $iac_project/platform-infrastructure within ${pr_b_timeout_min} min."
  echo "  PR-A #$pr_a_id is already merged. PR-B is required for first-time deploys."
  echo "  Check: $AZDO_ORG_URL/$iac_project/_git/platform-infrastructure/pullrequests"
  echo "  When PR-B appears, merge it manually, then run: noclickops deploy $service test"
  exit 1
fi
log_info "Found PR-B #$pr_b_id"

if ! merge_pr_in_project "$pr_b_id" "$iac_project" platform-infrastructure; then
  log_error "Failed to merge PR-B #$pr_b_id."
  echo "  PR-A #$pr_a_id is already merged. PR-B URL:"
  echo "  $AZDO_ORG_URL/$iac_project/_git/platform-infrastructure/pullrequest/$pr_b_id"
  echo "  Merge PR-B manually, then run: noclickops deploy $service test"
  exit 1
fi

# Sync local main (skipped in test mode where origin is a stubbed URL).
if [ -z "${NCO_AZ_OVERRIDE:-}" ]; then
  log_step "Syncing local main"
  git -C "$TARGET_REPO" fetch --prune >/dev/null 2>&1 || true
  if git -C "$TARGET_REPO" merge --ff-only origin/main >/dev/null 2>&1; then
    log_success "Local main is in sync with origin/main."
  else
    log_warn "Local main can't fast-forward — it has diverged from origin/main."
  fi
fi

echo ""
log_success "Done. services/$service is on main."
echo "  Source PR #$pr_a_id merged; infrastructure PR #$pr_b_id merged."
echo ""
echo "Next:"
echo "  noclickops clean-sample $service        # optional — strip the OIDC starter"
echo "  noclickops deploy $service test         # first-time deploy (~10 min, watches all 4 pipelines)"
