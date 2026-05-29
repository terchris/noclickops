#!/usr/bin/env bash
# bin/create-pr.sh — open an Azure DevOps PR from the current branch to main.
#
# --- noclickops metadata ---
SCRIPT_NAME="create-pr"
SCRIPT_DESCRIPTION="Open an Azure DevOps PR from the current branch to main."
SCRIPT_USAGE='noclickops create-pr "<title>" ["<description>"]'
SCRIPT_EXAMPLE='noclickops create-pr "feat: add login flow"'
SCRIPT_CATEGORY="git"
SCRIPT_TAGS="pull-request pr azure-devops branch push review"
SCRIPT_DETAILS="Opens an Azure DevOps PR from the current git branch to main. Auto-pushes the branch (sets upstream) if it has no tracking ref yet. Title is required; description defaults to the title. Refuses to run on main."
SCRIPT_AUTH="az login to the target's ADO tenant; first run also installs the azure-devops extension automatically."
SCRIPT_DEPENDS_ON="az git"
SCRIPT_SEE_ALSO="merge-pr"
SCRIPT_FLAGS=(
  "-h, --help|Show this help and exit."
)
SCRIPT_EXIT_CODES=(
  "0|PR opened — prints the PR id and URL."
  "1|Not in a git repo, on main branch, missing title, or az/git error."
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

title="${1:-}"
[ -n "$title" ] || die "Usage: $SCRIPT_USAGE"
desc="${2:-$title}"

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."
cd "$TARGET_REPO"

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" != "main" ] || die "You are on main. Create a feature branch first:
  git checkout -b feature/<name>"

derive_azdo_context "$TARGET_REPO"
require_az

# Source lib/service-v2.sh for nco_git (ADO-authed via az token).
. "$(dirname "${BASH_SOURCE[0]}")/../lib/service-v2.sh"

nco_command_header "'$title' ($branch → main) in $AZDO_REPO"

# Push + set upstream if the branch has no tracking ref yet.
if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  log_info "Pushing $branch to origin (setting upstream)..."
  nco_git push -u origin "$branch"
fi

log_step "Creating PR '$title' ($branch → main) in $AZDO_REPO"

pr_id="$(az repos pr create --repository "$AZDO_REPO" \
  --source-branch "$branch" --target-branch main \
  --title "$title" --description "$desc" \
  --query pullRequestId -o tsv)"

log_success "Created PR #$pr_id"
echo "  $AZDO_ORG_URL/$AZDO_PROJECT/_git/$AZDO_REPO/pullrequest/$pr_id"
echo ""
log_info "Next: noclickops merge-pr $pr_id"
