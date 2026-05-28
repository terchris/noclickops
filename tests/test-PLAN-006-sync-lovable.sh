#!/usr/bin/env bash
# tests/test-PLAN-006-sync-lovable.sh — end-to-end coverage for sync-lovable.
# Uses a fake Lovable source + bare remote and a fake target service folder.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-006: sync-lovable ──"

# 1. Lister + --help.
out=$("$NCO_ROOT/bin/noclickops.sh" 2>&1)
assert_contains "$out" "sync-lovable" "lister shows sync-lovable"

out=$("$NCO_ROOT/bin/sync-lovable.sh" --help 2>&1)
assert_contains "$out" "Lovable Vite/React/PWA" "sync-lovable --help description"

# 2. No args.
out=$("$NCO_ROOT/bin/sync-lovable.sh" 2>&1); rc=$?
assert_eq "1" "$rc"             "sync-lovable no args exit 1"
assert_contains "$out" "Usage:" "sync-lovable no args usage"

# 3. Source not a git repo.
out=$("$NCO_ROOT/bin/sync-lovable.sh" /tmp test-foo 2>&1); rc=$?
assert_eq "1" "$rc"                       "sync-lovable non-git source exit 1"
assert_contains "$out" "Not a git repo"   "sync-lovable non-git source error"

# Build a fake target repo with a scaffolded service.
repo=$(make_target_repo)
svc=$(make_service "$repo" "test-myapp")
echo "old dockerfile content" > "$svc/Dockerfile"   # will be overwritten by template

# 4. Source missing package.json.
nopj=$(mktemp -d)
git -C "$nopj" init -q -b main
out=$(cd "$repo" && "$NCO_ROOT/bin/sync-lovable.sh" "$nopj" test-myapp 2>&1); rc=$?
assert_eq "1" "$rc"                                       "sync-lovable no package.json exit 1"
assert_contains "$out" "not a Lovable repo (no package.json" "sync-lovable no package.json error"
rm -rf "$nopj"

# 5. Source has package.json but no lovable-tagger.
notlov=$(mktemp -d)
git -C "$notlov" init -q -b main
echo '{"name":"plain"}' > "$notlov/package.json"
git -C "$notlov" -c user.email=a@a -c user.name=a add -A
git -C "$notlov" -c user.email=a@a -c user.name=a commit -q -m x
out=$(cd "$repo" && "$NCO_ROOT/bin/sync-lovable.sh" "$notlov" test-myapp 2>&1); rc=$?
assert_eq "1" "$rc"                                                "sync-lovable no lovable-tagger exit 1"
assert_contains "$out" "no 'lovable-tagger' in"                    "sync-lovable no lovable-tagger error"
rm -rf "$notlov"

# 6. Unknown service folder.
out=$(cd "$repo" && "$NCO_ROOT/bin/sync-lovable.sh" /tmp ghost 2>&1); rc=$?
# Order of checks: src.git first; then service folder. Here /tmp isn't a git
# repo so we hit the source-validation error, not the service one. Use a real
# Lovable source for the service-not-found path:
src=$(make_lovable_source)
out=$(cd "$repo" && "$NCO_ROOT/bin/sync-lovable.sh" "$src" ghost 2>&1); rc=$?
assert_eq "1" "$rc"                              "sync-lovable unknown service exit 1"
assert_contains "$out" "No such service folder" "sync-lovable unknown service error"

# 7. Full end-to-end sync.
out=$(cd "$repo" && "$NCO_ROOT/bin/sync-lovable.sh" "$src" test-myapp 2>&1); rc=$?
assert_eq "0" "$rc" "sync-lovable end-to-end exit 0"

# Source files mirrored.
for f in src/App.tsx public/parties/ap.svg index.html package.json package-lock.json README.md .env; do
  assert_file_exists "$svc/$f" "mirror copied: $f"
done

# Excluded paths NOT copied.
assert_file_absent "$svc/node_modules" "mirror excluded: node_modules"
assert_file_absent "$svc/.git"          "mirror excluded: .git"

# Platform scaffolding preserved.
for f in service.yaml .pipelines bicep; do
  assert_file_exists "$svc/$f" "scaffolding preserved: $f"
done

# Dockerfile overwritten by the template (not the original "old dockerfile content").
dockerfile_head=$(head -1 "$svc/Dockerfile")
assert_contains "$dockerfile_head" "Lovable Vite/PWA" "Dockerfile rendered from template, not source's"

# nginx.conf has the /parties SPA fix.
nginx_content=$(cat "$svc/nginx.conf")
assert_contains "$nginx_content" 'try_files $uri /index.html' "nginx.conf has SPA fallback"
assert_not_contains "$nginx_content" 'try_files $uri $uri/' "nginx.conf does NOT have \$uri/ (avoids 301 on /parties)"

# health.json has the correct shape.
health=$(cat "$svc/health.json")
assert_contains "$health" '"status": "ok"' "health.json status: ok"
assert_contains "$health" '"source"'       "health.json has source object"
assert_contains "$health" '"repo": "file://' "health.json has repo URL"
assert_contains "$health" '"commit":'      "health.json has commit field"
assert_contains "$health" '"commit_date":' "health.json has commit_date field"

# Validate it's parseable JSON with the right shape (use python3, which is
# available on every reasonable CI runner).
if command -v python3 >/dev/null 2>&1; then
  python3 -c "
import json, sys
with open('$svc/health.json') as f:
    h = json.load(f)
assert h['status'] == 'ok'
assert 'source' in h
assert 'repo' in h['source']
assert len(h['source']['commit']) == 7, f'commit not 7 chars: {h[\"source\"][\"commit\"]}'
assert 'T' in h['source']['commit_date'], f'commit_date not ISO 8601: {h[\"source\"][\"commit_date\"]}'
" 2>&1
  if [ $? -eq 0 ]; then pass "health.json valid JSON with correct shape"; else fail "health.json valid JSON with correct shape"; fi
else
  skip "health.json JSON-shape check" "python3 not available"
fi

# 8. Re-run is idempotent.
out=$(cd "$repo" && "$NCO_ROOT/bin/sync-lovable.sh" "$src" test-myapp 2>&1); rc=$?
assert_eq "0" "$rc" "sync-lovable re-run exit 0"
assert_contains "$out" "Already up to date" "sync-lovable re-run is idempotent"

# 9. Dirty source warning surfaces.
echo "// uncommitted change" >> "$src/src/App.tsx"
out=$(cd "$repo" && "$NCO_ROOT/bin/sync-lovable.sh" "$src" test-myapp 2>&1)
assert_contains "$out" "uncommitted changes" "dirty source tree triggers warning"

rm -rf "$(dirname "$src")" "$repo"

summary
