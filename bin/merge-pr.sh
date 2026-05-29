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
SCRIPT_TAGS="merge squash pull-request pr azure-devops cleanup"
SCRIPT_DETAILS="Squash-completes an Azure DevOps PR by id (the only merge type the target repos allow). Polls until the PR shows completed, deletes the source branch, then syncs local main (git fetch + git merge --ff-only) and deletes the matching local feature branch if any."
SCRIPT_AUTH="az login to the target's ADO tenant."
SCRIPT_DEPENDS_ON="az git"
SCRIPT_SEE_ALSO="create-pr add-service"
SCRIPT_FLAGS=(
  "-h, --help|Show this help and exit."
)
SCRIPT_EXIT_CODES=(
  "0|Merged — local main aligned to origin/main."
  "1|PR not found, blocked by branch policy, or az/git error."
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

pr_id="${1:-}"
[ -n "$pr_id" ] || die "Usage: $SCRIPT_USAGE"

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."
cd "$TARGET_REPO"

derive_azdo_context "$TARGET_REPO"
require_az

# Source the v2 lib so `nco_git` is available for ADO-authed git operations.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/service-v2.sh"

nco_command_header "PR #$pr_id in $AZDO_REPO"

# Shared squash-complete + wait logic (since v1.3.0 — same helper used by
# bin/add-service.sh's auto-merge path).
squash_complete_pr "$pr_id" || exit 1

# Sync local main; delete the local feature branch on clean ff.
feature="$(git rev-parse --abbrev-ref HEAD)"
log_step "Syncing local main and cleaning up"
git checkout main
if ! nco_git fetch --prune >/dev/null 2>&1; then
  log_warn "git fetch failed — local main NOT synced. The PR is merged on ADO."
  log_warn "Run 'noclickops update' to refresh credentials, then 'git pull' manually."
elif nco_git merge --ff-only origin/main >/dev/null 2>&1; then
  if [ "$feature" != "main" ]; then
    git branch -D "$feature" >/dev/null 2>&1 && log_success "Deleted local branch $feature"
  fi
  log_success "Local main synced with origin/main."
else
  log_warn "Local main diverged from origin/main and can't fast-forward."
  echo "  Local main likely has unpushed commits."
  echo "  If local main has nothing worth keeping:  git reset --hard origin/main"
fi
