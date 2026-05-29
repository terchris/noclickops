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
SCRIPT_EXAMPLE_OUTPUT=$(cat <<'EOF'
noclickops create-pr v1.7.0 — 'smoke: minimal Express stub in smk1' (smoke/clean-smk1 → main) in ABC100001-myservice

==> Creating PR 'smoke: minimal Express stub in smk1' (smoke/clean-smk1 → main) in ABC100001-myservice
✓ Created PR #4842
  https://dev.azure.com/<org>/.../pullrequest/4842

ℹ Next: noclickops merge-pr 4842
EOF
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

_create_pr_err=$(mktemp)
pr_id="$(az repos pr create --repository "$AZDO_REPO" \
  --source-branch "$branch" --target-branch main \
  --title "$title" --description "$desc" \
  --query pullRequestId -o tsv 2>"$_create_pr_err")"
_create_pr_rc=$?

if [ "$_create_pr_rc" -ne 0 ] || [ -z "$pr_id" ]; then
  _err=$(cat "$_create_pr_err" 2>/dev/null)
  rm -f "$_create_pr_err"
  printf '\n  ✗ FAILED to create PR in %s\n' "$AZDO_REPO" >&2
  case "$_err" in
    *"TF401179"*|*"already exists"*)
      # Try to find the existing PR id so we can suggest merge-pr directly.
      _existing=$(az repos pr list --repository "$AZDO_REPO" --status active \
        --query "[?sourceRefName=='refs/heads/$branch'] | [0].pullRequestId" \
        -o tsv 2>/dev/null | head -1)
      printf '  Reason:  An active PR for branch %s already exists.\n' "$branch" >&2
      if [ -n "$_existing" ] && [ "$_existing" != "None" ]; then
        printf '  Action:  → Merge the existing PR instead:\n               noclickops merge-pr %s\n' "$_existing" >&2
      else
        printf '  Action:  → Visit the repo PR list and merge or abandon the existing PR.\n' >&2
      fi
      ;;
    *"TF401028"*|*"does not exist"*"refs/heads"*)
      printf '  Reason:  The source branch isn'"'"'t on the remote.\n' >&2
      printf '  Action:  → Push the branch first:\n               git push -u origin %s\n' "$branch" >&2
      ;;
    *"Source branch and target branch are the same"*)
      printf '  Reason:  Source and target are both '"'"'main'"'"'.\n' >&2
      printf '  Action:  → Create a feature branch first:\n               git checkout -b feature/<name>\n' >&2
      ;;
    *"Permission denied"*|*"Forbidden"*)
      printf '  Reason:  You don'"'"'t have permission to create PRs in this repo.\n' >&2
      printf '  Action:  → Ask your admin for Contributor / PR-create permission on %s.\n' "$AZDO_REPO" >&2
      ;;
    *)
      printf '  Reason:  %s\n' "${_err:-az returned no error message}" >&2
      printf '  Action:  → See the ADO web UI for the repo and try creating the PR manually.\n' >&2
      ;;
  esac
  printf '\n' >&2
  exit 1
fi
rm -f "$_create_pr_err"

log_success "Created PR #$pr_id"
echo "  $AZDO_ORG_URL/$AZDO_PROJECT/_git/$AZDO_REPO/pullrequest/$pr_id"
echo ""
log_info "Next: noclickops merge-pr $pr_id"
