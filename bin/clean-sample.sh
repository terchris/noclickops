#!/usr/bin/env bash
# bin/clean-sample.sh — strip the Next.js Copier sample app from a service,
# keeping the platform scaffolding (Dockerfile, service.yaml, .pipelines/,
# bicep/). Stages the deletions in git.
#
# v1 scope: targets the Next.js sample only. Other templates will need
# their own clean-<name> or a config-driven approach.
#
# --- noclickops metadata ---
SCRIPT_NAME="clean-sample"
SCRIPT_DESCRIPTION="Remove the Next.js sample app from a service folder."
SCRIPT_USAGE="noclickops clean-sample <service>"
SCRIPT_EXAMPLE="noclickops clean-sample test-myapp"
SCRIPT_CATEGORY="service-lifecycle"
# --- end metadata ---

set -euo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_dir/../lib/logging.sh"
. "$_dir/../lib/utilities.sh"
. "$_dir/../lib/paths.sh"
. "$_dir/../lib/metadata.sh"
unset _dir

case "${1:-}" in -h|--help) show_help "$0"; exit 0 ;; esac

service="${1:-}"
[ -n "$service" ] || die "Usage: $SCRIPT_USAGE"

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."
cd "$TARGET_REPO"

dir="services/$service"
[ -d "$dir" ] || die "No such service folder: $dir"

# The files/dirs that ARE the sample (everything platform scaffolding is NOT).
sample=(app components public package.json package-lock.json next.config.mjs)

# Safety marker: components/control-panel.js is unique to the unmodified
# Copier sample. Real code won't have it. If it's missing AND sample files
# exist, refuse — we'd risk deleting real work.
if [ ! -f "$dir/components/control-panel.js" ]; then
  any=0
  for p in "${sample[@]}"; do
    [ -e "$dir/$p" ] && any=1
  done
  if [ "$any" -eq 0 ]; then
    log_success "$dir is already clean (no sample app present)."
    exit 0
  fi
  die "$dir doesn't look like the unmodified Next.js sample (missing components/control-panel.js).
Refusing to auto-delete in case it contains real code. Remove files manually if you are sure."
fi

log_step "Removing the Next.js sample app from $dir"
for p in "${sample[@]}"; do
  target="$dir/$p"
  [ -e "$target" ] || continue
  if git ls-files --error-unmatch "$target" >/dev/null 2>&1; then
    git rm -rq "$target"        # tracked → stage the deletion
  else
    rm -rf "$target"            # untracked → just delete
  fi
  log_info "removed $p"
done

echo ""
log_success "Done."
echo "  Kept platform scaffolding: Dockerfile, service.yaml, .pipelines/, bicep/, README.md."
echo "  Next: add the real app, adapt the Dockerfile, ensure /health + SERVICE_PORT, then deploy."
