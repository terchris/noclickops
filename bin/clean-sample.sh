#!/usr/bin/env bash
# bin/clean-sample.sh — replace the Express+OIDC starter template in
# services/<svc>/app/ with a minimal Hello-World Express stub.
#
# v2: targets the new layout's copier-add-service template (Express +
# express-session + openid-client). For services that don't need OIDC,
# this clears the OIDC machinery so the developer can add their real
# code on top of the smallest deployable app.
#
# Engineer-owned scaffolding (Dockerfile, config.<env>.yaml, .pipelines/,
# README.md) is never touched.
#
# --- noclickops metadata ---
SCRIPT_NAME="clean-sample"
SCRIPT_DESCRIPTION="Replace the Express+OIDC sample with a minimal Hello-World stub."
SCRIPT_USAGE="noclickops clean-sample <service>"
SCRIPT_EXAMPLE="noclickops clean-sample frontend"
SCRIPT_CATEGORY="service-lifecycle"
SCRIPT_TAGS="cleanup express oidc minimal placeholder template"
SCRIPT_DETAILS="v2: detects the unmodified copier-add-service template (Express + express-session + openid-client) by content marker in app/server.js, then replaces app/server.js + app/package.json with a minimal Express app that exposes /health on PORT (or 3000). Engineer-owned scaffolding (Dockerfile, config.<env>.yaml, .pipelines/, README.md) is untouched. Idempotent — re-running on an already-minimal service exits 0. Refuses to overwrite a substantially modified app/server.js."
SCRIPT_AUTH="None."
SCRIPT_DEPENDS_ON="bash git"
SCRIPT_SEE_ALSO="add-service deploy"
SCRIPT_FLAGS=(
  "-h, --help|Show this help and exit."
)
SCRIPT_EXIT_CODES=(
  "0|Sample stripped — replacements staged in git. Or already minimal."
  "1|Service folder missing, not a v2-layout service, or app/server.js has been modified."
)
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

[ -n "${TARGET_REPO:-}" ] || die "Not inside a git repository. cd into a repo and re-run."
cd "$TARGET_REPO"

nco_command_header "strip Express+OIDC sample from services/$service/app/"

svc_dir="services/$service"
[ -d "$svc_dir" ] || die "No such service folder: $svc_dir"

app_dir="$svc_dir/app"
server_js="$app_dir/server.js"
package_json="$app_dir/package.json"

[ -d "$app_dir" ] \
  || die "$svc_dir has no app/ folder — does this repo use the new copier-add-service template?"
[ -f "$server_js" ] \
  || die "$server_js missing — does this repo use the new copier-add-service template?"
[ -f "$package_json" ] \
  || die "$package_json missing — does this repo use the new copier-add-service template?"

# Content marker for the unmodified Express+OIDC template. Long enough to be
# unique; short enough to survive minor template edits.
MARKER="OKTA_CLIENT_SECRET are injected from Azure Key Vault at container"

if ! grep -qF "$MARKER" "$server_js"; then
  lines=$(wc -l < "$server_js" | tr -d ' ')
  if [ "$lines" -lt 30 ]; then
    log_success "$server_js is already minimal — nothing to do."
    exit 0
  fi
  die "$server_js doesn't look like the unmodified Express+OIDC template ($lines lines, marker not found).
Refusing to overwrite in case it contains real code. Edit it directly, or remove app/server.js manually if you are sure."
fi

log_step "Replacing the Express+OIDC sample in $svc_dir/app/"

cat > "$server_js" <<'EOF'
const express = require('express');

const app = express();
const port = process.env.PORT || 3000;

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.listen(port, () => {
  console.log(`Listening on port ${port}`);
});
EOF

cat > "$package_json" <<'EOF'
{
  "name": "service",
  "version": "1.0.0",
  "scripts": { "start": "node server.js" },
  "dependencies": { "express": "^4.18.3" }
}
EOF

# Stage the replacements if the files are tracked.
for f in "$server_js" "$package_json"; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    git add "$f"
  fi
done

log_info "rewrote $server_js"
log_info "rewrote $package_json"
echo ""
log_success "Done."
echo "  Kept (engineer-owned): Dockerfile, config.<env>.yaml, .pipelines/, README.md."
echo "  Next: add your real code in $app_dir, then deploy with 'noclickops deploy $service test'."
