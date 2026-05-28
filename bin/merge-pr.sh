#!/usr/bin/env bash
# bin/merge-pr.sh — squash-complete an Azure DevOps PR, sync local main,
# delete the local feature branch.
#
# --- noclickops metadata ---
SCRIPT_NAME="merge-pr"
SCRIPT_DESCRIPTION="Squash-complete a PR, sync local main, delete the feature branch."
SCRIPT_USAGE="noclickops merge-pr <pr-id>"
SCRIPT_EXAMPLE="noclickops merge-pr 4779"
SCRIPT_CATEGORY="git"
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

pr_id="${1:-}"
[ -n "$pr_id" ] || die "Usage: $SCRIPT_USAGE"

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."
cd "$TARGET_REPO"

derive_azdo_context "$TARGET_REPO"
require_az

log_step "Completing PR #$pr_id (squash, delete source branch)"
# Squash is required by the target repo's branch policy in v1's ADO setup;
# the API default of 'no-fast-forward' would fail policy.
az repos pr update --id "$pr_id" --status completed \
    --squash true --delete-source-branch true \
    --query status -o tsv >/dev/null

# PR completion is async — poll for up to ~2 minutes.
log_info "Waiting for completion..."
st=""
for _ in $(seq 1 30); do
  st="$(az repos pr show --id "$pr_id" --query status -o tsv)"
  [ "$st" = "completed" ] && break
  [ "$st" = "abandoned" ] && die "PR #$pr_id was abandoned."
  sleep 4
done
[ "$st" = "completed" ] || die "PR #$pr_id did not complete (status: $st). Check branch policies."
log_success "PR #$pr_id completed."

# Sync local main; delete the local feature branch on clean ff.
feature="$(git rev-parse --abbrev-ref HEAD)"
log_step "Syncing local main and cleaning up"
git checkout main
git fetch --prune
if git merge --ff-only origin/main >/dev/null 2>&1; then
  if [ "$feature" != "main" ]; then
    git branch -D "$feature" >/dev/null 2>&1 && log_success "Deleted local branch $feature"
  fi
  log_success "Local main is in sync with origin/main."
else
  log_warn "Local main diverged from origin/main and can't fast-forward."
  echo "  Local main likely has unpushed commits."
  echo "  If local main has nothing worth keeping:  git reset --hard origin/main"
fi
