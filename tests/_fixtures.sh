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
  COMMON_RESOURCE_GROUP_NAME: "rg-prod-myteam-frontend-common"
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
