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
