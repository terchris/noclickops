#!/usr/bin/env bash
# bin/sync-lovable.sh — sync a Lovable (Vite/React/PWA) repo into a service
# folder and leave it deployable. Safe to re-run: pulls upstream changes,
# re-renders templates, regenerates health.json.
#
# Five-step flow:
#   1. Validate args + Lovable signature + capture source origin URL.
#   2. git pull --ff-only in the source repo.
#   3. Post-pull guards (npm lockfile, dirty-tree warning).
#   4. rsync the frontend into services/<service>/ with --delete, excluding
#      node_modules / .git / dist / .lovable / etc. AND the noclickops-managed
#      files (Dockerfile, nginx.conf, health.json, service.yaml, .pipelines/,
#      bicep/) so the mirror never clobbers them.
#   5. Render templates/lovable/{Dockerfile,nginx.conf} into the service folder;
#      generate health.json with the source repo URL + short SHA + commit date.
#
# --- noclickops metadata ---
SCRIPT_NAME="sync-lovable"
SCRIPT_DESCRIPTION="Sync a Lovable Vite/React/PWA repo into a service folder."
SCRIPT_USAGE="noclickops sync-lovable <lovable-repo-path> <service>"
SCRIPT_EXAMPLE="noclickops sync-lovable ~/learn/helpers/holderdeord test-holderdeord"
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

src="${1:-}"
service="${2:-}"
[ -n "$src" ] && [ -n "$service" ] || die "Usage: $SCRIPT_USAGE"

# ----- 1. Validate + Lovable signature + origin URL -----

[ -d "$src/.git" ] || die "Not a git repo: $src"
require_cmd rsync

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."
cd "$TARGET_REPO"

dest="services/$service"
[ -d "$dest" ] || die "No such service folder: $dest"
[ -f "$dest/service.yaml" ] || die "$dest has no service.yaml — is it a real service folder?"

# Lovable signature: fail closed on anything that isn't the known shape.
[ -f "$src/package.json" ] \
  || die "not a Lovable repo (no package.json in $src) — investigate its setup before adding sync-lovable support."
grep -q '"lovable-tagger"' "$src/package.json" \
  || die "not a Lovable repo (no 'lovable-tagger' in $src/package.json) — investigate its setup before adding sync-lovable support."

# Origin URL — needed for health.json later.
src_origin="$(git -C "$src" remote get-url origin 2>/dev/null || true)"
[ -n "$src_origin" ] \
  || die "source repo has no 'origin' remote; can't record source URL in health.json — set a remote or run sync-lovable from a clone."

# ----- 2. Pull the source -----

log_step "Pulling latest in Lovable repo: $src"
git -C "$src" pull --ff-only || die "git pull failed in $src — resolve it there, then re-run."

# ----- 3. Post-pull guards -----

[ -f "$src/package-lock.json" ] \
  || die "no 'package-lock.json' in $src; v1 builds with npm — investigate before re-syncing."

if ! git -C "$src" diff --quiet || ! git -C "$src" diff --cached --quiet; then
  log_warn "source repo has uncommitted changes; the bundle will include them, but health.json's commit only records HEAD — your deployed code will differ from what /health claims."
fi

# ----- 4. Mirror the frontend -----

log_step "Syncing the Lovable frontend into $dest (preserving platform scaffolding)"
# Excluded paths are skipped on copy AND protected from --delete on the receiver.
# Anchored (/foo) = top-level only; unanchored = any depth.
# /README.md is NOT excluded — the Lovable README mirrors through.
# /nginx.conf and /health.json are excluded so the mirror doesn't delete the files
# this script generates in step 5.
rsync -a --delete --itemize-changes \
  --exclude='node_modules' --exclude='.git' --exclude='dist' --exclude='dist-ssr' \
  --exclude='/.github' --exclude='/supabase' --exclude='/scripts' --exclude='/.lovable' \
  --exclude='/bun.lock' --exclude='/bun.lockb' \
  --exclude='/Dockerfile' --exclude='/service.yaml' --exclude='/.pipelines' --exclude='/bicep' \
  --exclude='/nginx.conf' --exclude='/health.json' \
  "$src"/ "$dest"/

# Safety check after the mirror: the platform scaffolding must still be there.
for f in Dockerfile service.yaml .pipelines bicep; do
  [ -e "$dest/$f" ] || die "Platform scaffolding '$f' went missing from $dest — aborting. Check git status."
done

# ----- 5. Render templates + generate health.json -----

template_dir="$TEMPLATES_DIR/lovable"
log_step "Rendering templates from $template_dir"
for f in Dockerfile nginx.conf; do
  [ -f "$template_dir/$f" ] || die "template missing: $template_dir/$f — reinstall noclickops or run 'noclickops update'."
  cp "$template_dir/$f" "$dest/$f"
  log_info "rendered $f"
done

src_url="${src_origin%.git}"
src_short="$(git -C "$src" rev-parse --short HEAD)"
src_date="$(git -C "$src" log -1 --format=%cI HEAD)"

log_step "Writing $dest/health.json (commit $src_short, $src_date)"
cat > "$dest/health.json" <<EOF
{
  "status": "ok",
  "source": {
    "repo": "$src_url",
    "commit": "$src_short",
    "commit_date": "$src_date"
  }
}
EOF

echo ""
log_success "Done. $dest is ready to deploy."
echo "  Note: .env (VITE_* build-time vars) is included — Supabase anon keys are public-safe by design."
echo "  Review with:  git status $dest"
echo "  After PR merge, deploy with:  noclickops deploy $service test --watch"
