#!/usr/bin/env bash
# bin/update.sh — pull the latest noclickops from origin.
#
# Sparse-checkout interaction (v1.5.1+): `git pull --ff-only` is
# sparse-checkout-aware — it pulls all refs into .git/ but only materializes
# files listed in the active sparse set (bin/ lib/ templates/ by default).
# Nothing to do here; the slim install behaviour is set up entirely in
# install.sh. To change the sparse set on an existing install, re-run
# install.sh or use `git -C ~/.noclickops sparse-checkout` directly.
#
# --- noclickops metadata ---
SCRIPT_NAME="update"
SCRIPT_DESCRIPTION="Pull the latest noclickops from origin (fast-forward only)."
SCRIPT_USAGE="noclickops update"
SCRIPT_EXAMPLE="noclickops update"
SCRIPT_CATEGORY="meta"
SCRIPT_TAGS="self-update git-pull upgrade version"
SCRIPT_DETAILS="Runs git pull --ff-only inside the install directory (~/.noclickops by default). Refreshes the cached version check so the lister stops nagging once you're up to date."
SCRIPT_AUTH="None."
SCRIPT_DEPENDS_ON="bash git"
SCRIPT_SEE_ALSO="noclickops"
SCRIPT_FLAGS=(
  "-h, --help|Show this help and exit."
)
SCRIPT_EXIT_CODES=(
  "0|Already up to date, or pulled cleanly."
  "1|Pull failed (e.g. unmerged local changes in the install dir)."
)
SCRIPT_EXAMPLE_OUTPUT=$(cat <<'EOF'
noclickops update v1.7.0 — pull latest noclickops

==> Updating noclickops at /Users/.../.noclickops
Updating fa1b3c..7e8d9a
Fast-forward
 version.txt | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
✓ noclickops is up to date.
EOF
)
# --- end metadata ---

set -euo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_dir/../lib/logging.sh"
. "$_dir/../lib/utilities.sh"
. "$_dir/../lib/paths.sh"
. "$_dir/../lib/metadata.sh"
unset _dir

case "${1:-}" in
  -h|--help) show_help "$0"; exit 0 ;;
esac

require_cmd git

nco_command_header "pull latest noclickops"

log_step "Updating noclickops at $NOCLICKOPS_DIR"

# Refuse to operate if the install dir isn't a git checkout — PLAN-002's
# installer is responsible for cloning; we just pull.
if [ ! -d "$NOCLICKOPS_DIR/.git" ]; then
  die "$NOCLICKOPS_DIR is not a git checkout. Re-install via PLAN-002's installer."
fi

if ! git -C "$NOCLICKOPS_DIR" pull --ff-only 2>/dev/null; then
  # Diagnose the divergence + give targeted recovery commands.
  _ahead=$(git -C "$NOCLICKOPS_DIR" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
  _behind=$(git -C "$NOCLICKOPS_DIR" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
  _dirty=$(git -C "$NOCLICKOPS_DIR" status --porcelain 2>/dev/null | head -1)

  printf '\n  ✗ FAILED: noclickops update — local install diverged from origin/main\n\n' >&2
  if [ -n "$_dirty" ]; then
    printf '  Reason:  %s has uncommitted changes (or unsupported state).\n' "$NOCLICKOPS_DIR" >&2
  elif [ "$_ahead" -gt 0 ]; then
    printf '  Reason:  Local install has %s commit(s) not on origin/main.\n' "$_ahead" >&2
  else
    printf '  Reason:  git pull --ff-only failed (sparse-checkout / shallow boundary issue?).\n' >&2
  fi
  printf '\n' >&2
  printf '  Action:  Pick ONE:\n' >&2
  printf '\n' >&2
  printf '    a) Reset to origin (recommended; this dir is install-only, edits don'"'"'t belong here):\n' >&2
  printf '         git -C %s fetch origin\n' "$NOCLICKOPS_DIR" >&2
  printf '         git -C %s reset --hard origin/main\n' "$NOCLICKOPS_DIR" >&2
  printf '\n' >&2
  # Derive the install URL from the install dir's actual git remote so this
  # works for forks too (portability test forbids hardcoded owner names).
  _origin=$(git -C "$NOCLICKOPS_DIR" remote get-url origin 2>/dev/null || true)
  _install_url=""
  if [[ "$_origin" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    _install_url="https://raw.githubusercontent.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/main/install.sh"
  fi
  printf '    b) Wipe + reinstall (always safe):\n' >&2
  printf '         rm -rf %s && \\\n' "$NOCLICKOPS_DIR" >&2
  if [ -n "$_install_url" ]; then
    printf '         curl -fsSL %s | bash\n' "$_install_url" >&2
  else
    printf '         # then re-run the install command from your team docs\n' >&2
  fi
  printf '\n' >&2
  printf '    c) If you have edits worth keeping (rare for an install dir):\n' >&2
  printf '         cd %s && git status   # inspect manually\n' "$NOCLICKOPS_DIR" >&2
  printf '\n' >&2
  exit 1
fi

# Bust the version cache so the next lister call doesn't show a stale
# "Update available" hint based on a pre-pull remote check.
rm -f "$NOCLICKOPS_DIR/.version-cache" 2>/dev/null || true

log_success "noclickops is up to date."
