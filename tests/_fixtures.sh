# tests/_fixtures.sh — helpers for building fake target repos and source repos.
# Each fixture returns a path on stdout; caller cleans up with `rm -rf`.

[[ -n "${_NCO_FIXTURES_LOADED:-}" ]] && return 0
_NCO_FIXTURES_LOADED=1

# Create a git repo with an ADO-style origin URL (default uses generic AcmeCorp).
# Usage: dir=$(make_target_repo [origin-url])
make_target_repo() {
  local origin="${1:-https://dev.azure.com/AcmeCorp/Platform/_git/some-app}"
  local d
  d=$(mktemp -d)
  git -C "$d" init -q -b main
  git -C "$d" remote add origin "$origin"
  git -C "$d" -c user.email=a@a -c user.name=a commit -q --allow-empty -m initial
  printf '%s' "$d"
}

# Create a service folder with platform scaffolding.
# Usage: svc_dir=$(make_service <target-repo> <service-name>)
make_service() {
  local repo="$1" service="$2"
  local d="$repo/services/$service"
  mkdir -p "$d/.pipelines" "$d/bicep"
  echo "FROM node:20-alpine" > "$d/Dockerfile"
  printf "name: %s\n" "$service" > "$d/service.yaml"
  echo "trigger: none" > "$d/.pipelines/test.yaml"
  echo "// bicep" > "$d/bicep/main.bicep"
  printf '%s' "$d"
}

# Add the unmodified Next.js Copier sample to a service folder.
# Usage: scaffold_nextjs_sample <service-dir>
scaffold_nextjs_sample() {
  local d="$1"
  mkdir -p "$d/app" "$d/components" "$d/public"
  echo "// page" > "$d/app/page.js"
  echo "// THE MARKER" > "$d/components/control-panel.js"   # the safety probe
  echo "<svg/>" > "$d/public/favicon.ico"
  echo '{"name":"sample"}' > "$d/package.json"
  echo '{}' > "$d/package-lock.json"
  echo "export default {}" > "$d/next.config.mjs"
}

# Add the repo-level .pipelines/variables/{common,test,prod}.yaml files,
# mirroring the FRT layout. Usage: add_pipeline_variables <repo>
add_pipeline_variables() {
  local repo="$1"
  mkdir -p "$repo/.pipelines/variables"
  cat > "$repo/.pipelines/variables/common.yaml" <<'EOF'
variables:
  APP_NAME: "frt900x016"
  acrServiceConnection: "myteam-frontend-acr-sp"
  CONTAINER_REGISTRY_NAME: "acrshareduw"
EOF
  cat > "$repo/.pipelines/variables/test.yaml" <<'EOF'
variables:
  ENVIRONMENT: "test"
  SUBSCRIPTION_ID: "3aec5ff4-d5d3-47d3-b860-c36f2bf3ca2d"
  COMMON_RESOURCE_GROUP_NAME: "rg-test-myteam-frontend-common"
EOF
  cat > "$repo/.pipelines/variables/prod.yaml" <<'EOF'
variables:
  ENVIRONMENT: "prod"
  SUBSCRIPTION_ID: ""
  COMMON_RESOURCE_GROUP_NAME: "rg-prod-nrx-frt-common"
EOF
}

# Add the service-level .pipelines/variables/{test,prod}.yaml inside the
# service folder. Usage: add_service_variables <repo> <service>
add_service_variables() {
  local repo="$1" service="$2"
  local d="$repo/services/$service/.pipelines/variables"
  mkdir -p "$d"
  cat > "$d/test.yaml" <<EOF
variables:
  ENABLE_PUBLIC_ENDPOINT: "true"
  PERSISTENT_STORAGE: "false"
  SERVICE_NAME: $service
  SERVICE_PORT: 3000
  SERVICE_CPU: 0.5
  SERVICE_MEMORY: 1Gi
  SERVICE_MIN_REPLICAS: 0
  SERVICE_MAX_REPLICAS: 1
  SERVICE_HEALTH_CHECK_PATH: "/health"
  SERVICE_HEALTH_PROBE_PORT: 3000
  IMAGE_TAG: '\$(Build.BuildNumber)'
EOF
  cat > "$d/prod.yaml" <<EOF
variables:
  ENABLE_PUBLIC_ENDPOINT: "true"
  PERSISTENT_STORAGE: "false"
  SERVICE_NAME: $service
  SERVICE_PORT: 3000
  SERVICE_CPU: 0.5
  SERVICE_MEMORY: 1Gi
  SERVICE_MIN_REPLICAS: 1
  SERVICE_MAX_REPLICAS: 3
  SERVICE_HEALTH_CHECK_PATH: "/health"
  SERVICE_HEALTH_PROBE_PORT: 3000
  IMAGE_TAG: '\$(Build.BuildNumber)'
EOF
}

# ---------------------------------------------------------------------------
# v2 fixtures — new two-project / two-repo layout
# ---------------------------------------------------------------------------

# Make a source repo matching the new ADO layout (FrontendPlatform-style).
# Default origin is generic — tests can override.
# Usage: dir=$(make_v2_source_repo [origin-url])
make_v2_source_repo() {
  local origin="${1:-https://dev.azure.com/AcmeCorp/FrontendPlatform/_git/ABC100001-myservice}"
  local d
  d=$(mktemp -d)
  git -C "$d" init -q -b main
  git -C "$d" remote add origin "$origin"
  mkdir -p "$d/.pipelines" "$d/services"
  printf "trigger: none\n" > "$d/.pipelines/add-service.yaml"
  git -C "$d" -c user.email=a@a -c user.name=a add -A
  git -C "$d" -c user.email=a@a -c user.name=a commit -q -m initial
  printf '%s' "$d"
}

# Add a service folder in the new layout: services/<svc>/{Dockerfile, app/,
# config.test.yaml, config.prod.yaml, .pipelines/{service,deploy_service}.yaml}.
# Usage: svc_dir=$(make_v2_service <source-repo> <service> [public=true|false])
make_v2_service() {
  local repo="$1" svc="$2" public="${3:-true}"
  local d="$repo/services/$svc"
  mkdir -p "$d/app" "$d/.pipelines"
  echo "FROM node:20-alpine" > "$d/Dockerfile"
  echo "console.log('hi')" > "$d/app/index.js"
  printf "trigger: none\n" > "$d/.pipelines/service.yaml"
  printf "trigger: none\n" > "$d/.pipelines/deploy_service.yaml"
  cat > "$d/config.test.yaml" <<EOF
SERVICE_PORT: 3000
SERVICE_CPU: 0.5
SERVICE_MEMORY: 1Gi
SERVICE_MIN_REPLICAS: 0
SERVICE_MAX_REPLICAS: 1
SERVICE_HEALTH_CHECK_PATH: "/health"
SERVICE_HEALTH_PROBE_PORT: 3000
ENABLE_PUBLIC_ENDPOINT: "${public}"
PERSISTENT_STORAGE: "false"
EOF
  cat > "$d/config.prod.yaml" <<EOF
SERVICE_PORT: 3000
SERVICE_CPU: 0.5
SERVICE_MEMORY: 1Gi
SERVICE_MIN_REPLICAS: 1
SERVICE_MAX_REPLICAS: 3
SERVICE_HEALTH_CHECK_PATH: "/health"
SERVICE_HEALTH_PROBE_PORT: 3000
ENABLE_PUBLIC_ENDPOINT: "${public}"
PERSISTENT_STORAGE: "false"
EOF
  printf '%s' "$d"
}

# Overwrite a v2 service's app/{server.js,package.json} with the unmodified
# Express+OIDC template content (matching what copier-add-service produces).
# Used by PLAN-E tests; carries the content marker that bin/clean-sample.sh
# greps for.
# Usage: scaffold_v2_oidc_sample <service-dir>
scaffold_v2_oidc_sample() {
  local d="$1"
  mkdir -p "$d/app"
  cat > "$d/app/server.js" <<'EOF'
const express = require('express');
const session = require('express-session');
const { Issuer, generators } = require('openid-client');

const app = express();
const port = process.env.PORT || 3000;

// OKTA_ISSUER and APP_BASE_URL are set as plain env vars in config.{env}.yaml.
// OKTA_CLIENT_ID and OKTA_CLIENT_SECRET are injected from Azure Key Vault at container
// startup via the Container App's system-assigned managed identity — never stored in config files.
const OKTA_ISSUER  = process.env.OKTA_ISSUER  || '';
const CALLBACK_URL = process.env.APP_BASE_URL  || `http://localhost:${port}`;

app.use(session({
  secret: process.env.SESSION_SECRET || 'dev-only-secret-change-in-production',
  resave: false,
  saveUninitialized: false,
  cookie: { secure: false, httpOnly: true, maxAge: 60 * 60 * 1000 },
}));

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

let client;
(async () => {
  if (OKTA_ISSUER) {
    const issuer = await Issuer.discover(OKTA_ISSUER);
    client = new issuer.Client({
      client_id: process.env.OKTA_CLIENT_ID,
      client_secret: process.env.OKTA_CLIENT_SECRET,
      redirect_uris: [`${CALLBACK_URL}/callback`],
      response_types: ['code'],
    });
  }
})();

app.listen(port, () => {
  console.log(`Listening on port ${port}`);
});
EOF
  cat > "$d/app/package.json" <<'EOF'
{
  "name": "service",
  "version": "1.0.0",
  "scripts": { "start": "node server.js" },
  "dependencies": {
    "express": "^4.18.3",
    "express-session": "^1.18.0",
    "openid-client": "^4.9.1"
  }
}
EOF
}

# Build a fake IaC repo layout on disk, populated with platform variables
# for a given source repo + service. Returns the IaC repo root dir.
# Usage: iac_root=$(make_v2_iac_repo <team> <source-repo-name>)
make_v2_iac_repo() {
  local team="$1" source_repo="$2"
  local d vars_dir
  d=$(mktemp -d)
  vars_dir="$d/environments/$team/$source_repo/infrastructure/.pipelines/variables"
  mkdir -p "$vars_dir"
  cat > "$vars_dir/common.yaml" <<'EOF'
APP_NAME: "abc100001"
APPLICATION_NAME: "myservice"
CONTAINER_REGISTRY_NAME: "acrshareduw"
REPO_NAME: "ABC100001-myservice"
TEAM_NAME: "ABC"
IAC_PROJECT: "IaC"
IAC_REPO: "platform-infrastructure"
EOF
  cat > "$vars_dir/test.yaml" <<'EOF'
ENVIRONMENT: "test"
SUBSCRIPTION_ID: "3aec5ff4-d5d3-47d3-b860-c36f2bf3ca2d"
COMMON_RESOURCE_GROUP_NAME: "rg-test-myteam-frontend-common"
DNS_ZONE_NAME: "example.cloud"
KEY_VAULT_NAME: "kv-test-myteam-shared"
EOF
  cat > "$vars_dir/prod.yaml" <<'EOF'
ENVIRONMENT: "prod"
SUBSCRIPTION_ID: "00000000-0000-0000-0000-000000000000"
COMMON_RESOURCE_GROUP_NAME: "rg-prod-myteam-frontend-common"
DNS_ZONE_NAME: "example.cloud"
KEY_VAULT_NAME: "kv-prod-myteam-shared"
EOF
  printf '%s' "$d"
}

# Stub that maps ADO REST URLs to files on disk. Used by tests via
# NCO_ADO_REST_OVERRIDE. Expects $NCO_TEST_IAC_ROOT to point at a make_v2_iac_repo
# output, and parses the `path=` query param to map to a file inside it.
#
# Usage in a test:
#   export NCO_TEST_IAC_ROOT=$iac_root
#   export NCO_ADO_REST_OVERRIDE=$NCO_ROOT/tests/_stub_ado_rest.sh
v2_stub_ado_rest_path() {
  # Returns the path to the helper stub file. Always rewrites so updates to
  # the embedded stub source here take effect on the next test run.
  local stub="${NCO_ROOT:?}/tests/_stub_ado_rest.sh"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
# Test stub for NCO_ADO_REST_OVERRIDE.
# Looks at the request URL, finds the `path=` query param, and prints the
# contents of the corresponding file inside $NCO_TEST_IAC_ROOT.
set -uo pipefail
url="$1"
path=$(printf '%s' "$url" | sed -nE 's/.*[?&]path=([^&]+).*/\1/p')
[ -z "$path" ] && { printf 'stub: no path= in URL\n' >&2; exit 1; }
# URL-decode + strip leading /
path=${path//%2F/\/}; path=${path#/}
file="${NCO_TEST_IAC_ROOT:?NCO_TEST_IAC_ROOT not set}/$path"
[ -f "$file" ] || { printf 'stub: no such file: %s\n' "$file" >&2; exit 1; }
cat "$file"
STUB
  chmod +x "$stub"
  printf '%s' "$stub"
}

# Stub for NCO_AZ_OVERRIDE. Reads $NCO_TEST_AZ_FIXTURES (a dir) and dispatches
# `az foo bar baz [--project X]` to az_foo_bar_baz[_proj_X].{tsv,json,txt}.
# NCO_TEST_AZ_KEY overrides the auto-derived key.
v2_stub_az_path() {
  # Always rewrites — see v2_stub_ado_rest_path note above.
  local stub="${NCO_ROOT:?}/tests/_stub_az.sh"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
fixtures="${NCO_TEST_AZ_FIXTURES:?NCO_TEST_AZ_FIXTURES not set}"
args=("$@")
subcmd=""
proj=""; rg=""; sub=""
i=0
while [ $i -lt ${#args[@]} ]; do
  a="${args[$i]}"
  case "$a" in
    --project)            i=$((i+1)); proj="${args[$i]:-}" ;;
    --project=*)          proj="${a#*=}" ;;
    --resource-group|-g)  i=$((i+1)); rg="${args[$i]:-}" ;;
    --resource-group=*)   rg="${a#*=}" ;;
    --subscription)       i=$((i+1)); sub="${args[$i]:-}" ;;
    --subscription=*)     sub="${a#*=}" ;;
    --*|-*)               i=$((i+1)) ;;
    *)                    [ -z "$subcmd" ] && subcmd="$a" || subcmd="${subcmd}_$a" ;;
  esac
  i=$((i+1))
done
key="${subcmd}"
[ -n "$proj" ] && key="${key}_proj_${proj}"
[ -n "$rg" ]   && key="${key}_rg_${rg}"
[ -n "$sub" ]  && key="${key}_sub_${sub}"
key="${NCO_TEST_AZ_KEY:-$key}"
for ext in tsv json txt; do
  if [ -f "$fixtures/az_${key}.${ext}" ]; then
    cat "$fixtures/az_${key}.${ext}"
    exit 0
  fi
done
printf 'stub: no fixture for az %s (key=%s)\n' "$*" "$key" >&2
exit 1
STUB
  chmod +x "$stub"
  printf '%s' "$stub"
}

# Create a fake Lovable source repo with a bare remote alongside.
# Usage: src=$(make_lovable_source)
# Cleanup: rm -rf "$(dirname "$src")"   # parent dir also holds the bare remote
make_lovable_source() {
  local tmp src bare
  tmp=$(mktemp -d)
  src="$tmp/lovable-fake"
  bare="$tmp/lovable.git"
  mkdir -p "$src/src" "$src/public/parties" "$src/node_modules/junk"
  echo "<html></html>" > "$src/index.html"
  echo "console.log('app')" > "$src/src/App.tsx"
  echo "<svg/>" > "$src/public/parties/ap.svg"
  echo "trash" > "$src/node_modules/junk/x.js"
  cat > "$src/package.json" <<'EOF'
{
  "name": "fake-lovable",
  "devDependencies": { "lovable-tagger": "1.2.3" }
}
EOF
  echo '{"name":"fake-lovable","lockfileVersion":3}' > "$src/package-lock.json"
  echo "VITE_API=https://api.example.com" > "$src/.env"
  echo "# Lovable" > "$src/README.md"
  git -C "$src" init -q -b main
  git -C "$src" -c user.email=a@a -c user.name=a add -A
  git -C "$src" -c user.email=a@a -c user.name=a commit -q -m initial
  git init --bare -q "$bare"
  git -C "$src" remote add origin "file://$bare"
  git -C "$src" push -q -u origin main
  printf '%s' "$src"
}
