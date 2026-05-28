#!/usr/bin/env bash
# bin/update.sh — pull the latest noclickops from origin.
#
# --- noclickops metadata ---
SCRIPT_NAME="update"
SCRIPT_DESCRIPTION="Pull the latest noclickops from origin (fast-forward only)."
SCRIPT_USAGE="noclickops update"
SCRIPT_EXAMPLE="noclickops update"
SCRIPT_CATEGORY="meta"
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

log_step "Updating noclickops at $NOCLICKOPS_DIR"

# Refuse to operate if the install dir isn't a git checkout — PLAN-002's
# installer is responsible for cloning; we just pull.
if [ ! -d "$NOCLICKOPS_DIR/.git" ]; then
  die "$NOCLICKOPS_DIR is not a git checkout. Re-install via PLAN-002's installer."
fi

if ! git -C "$NOCLICKOPS_DIR" pull --ff-only; then
  die "git pull failed in $NOCLICKOPS_DIR — resolve manually, then re-run."
fi

# Bust the version cache so the next lister call doesn't show a stale
# "Update available" hint based on a pre-pull remote check.
rm -f "$NOCLICKOPS_DIR/.version-cache" 2>/dev/null || true

log_success "noclickops is up to date."
