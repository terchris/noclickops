#!/usr/bin/env bash
# tests/test-PLAN-E-clean-sample.sh — coverage for bin/clean-sample.sh (v2).
# Pure file-manipulation; no az, no REST.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-E: bin/clean-sample.sh (v2) ──"

# --- Negative cases ---

# --help
out=$("$NCO_ROOT/bin/clean-sample.sh" --help 2>&1)
assert_contains "$out" "Category: service-lifecycle" "planE: --help shows category"
assert_contains "$out" "Hello-World stub"            "planE: --help mentions v2 behaviour"

# No args
out=$("$NCO_ROOT/bin/clean-sample.sh" 2>&1); rc=$?
assert_eq "1" "$rc"              "planE: no args exit 1"
assert_contains "$out" "Usage:"  "planE: no args shows usage"

# Outside a git repo
out=$(cd /tmp && "$NCO_ROOT/bin/clean-sample.sh" frontend 2>&1); rc=$?
assert_eq "1" "$rc"                                   "planE: outside repo exit 1"
assert_contains "$out" "Not inside a git repository" "planE: outside repo error"

# Service folder missing
src=$(make_v2_source_repo)
out=$(cd "$src" && "$NCO_ROOT/bin/clean-sample.sh" ghost 2>&1); rc=$?
assert_eq "1" "$rc"                             "planE: missing service exit 1"
assert_contains "$out" "No such service folder" "planE: missing service error"
rm -rf "$src"

# Service exists but no app/
src=$(make_v2_source_repo)
mkdir -p "$src/services/orphan"
out=$(cd "$src" && "$NCO_ROOT/bin/clean-sample.sh" orphan 2>&1); rc=$?
assert_eq "1" "$rc"                       "planE: no app/ exit 1"
assert_contains "$out" "no app/ folder"   "planE: no app/ error names what's missing"
rm -rf "$src"

# --- Happy path: unmodified OIDC template gets stripped ---

src=$(make_v2_source_repo)
make_v2_service "$src" frontend true >/dev/null   # writes the minimal default
scaffold_v2_oidc_sample "$src/services/frontend"  # overwrites with real OIDC template
# Make all files tracked
(cd "$src" && git add -A && git -c user.email=a@a -c user.name=a commit -q -m "scaffold")

# Sanity: marker present before strip
grep -qF "OKTA_CLIENT_SECRET are injected" "$src/services/frontend/app/server.js" \
  && pass "planE: pre-strip — OIDC marker present in fixture" \
  || fail "planE: pre-strip — OIDC marker present in fixture" "fixture broken"

out=$(cd "$src" && "$NCO_ROOT/bin/clean-sample.sh" frontend 2>&1); rc=$?
assert_eq "0" "$rc"                                       "planE: happy path exits 0"
assert_contains "$out" "Replacing the Express+OIDC sample" "planE: happy path prints step header"
assert_contains "$out" "rewrote"                          "planE: happy path prints rewrote markers"

# server.js: marker gone, /health present, no OIDC machinery
case "$(cat "$src/services/frontend/app/server.js")" in
  *"OKTA_CLIENT_SECRET"*) fail "planE: post-strip — OIDC marker should be gone" ;;
  *)                      pass "planE: post-strip — OIDC marker gone" ;;
esac
grep -qF "app.get('/health'" "$src/services/frontend/app/server.js" \
  && pass "planE: post-strip — /health endpoint present" \
  || fail "planE: post-strip — /health endpoint present" "missing"
case "$(cat "$src/services/frontend/app/server.js")" in
  *"openid-client"*) fail "planE: post-strip — openid-client should be gone" ;;
  *)                 pass "planE: post-strip — openid-client gone" ;;
esac

# package.json: only express, no express-session / openid-client
case "$(cat "$src/services/frontend/app/package.json")" in
  *"express-session"*) fail "planE: post-strip — express-session should be gone" ;;
  *)                   pass "planE: post-strip — express-session gone" ;;
esac
case "$(cat "$src/services/frontend/app/package.json")" in
  *"openid-client"*) fail "planE: post-strip — openid-client dep should be gone" ;;
  *)                 pass "planE: post-strip — openid-client dep gone" ;;
esac
grep -qF '"express":' "$src/services/frontend/app/package.json" \
  && pass "planE: post-strip — express dep retained" \
  || fail "planE: post-strip — express dep retained" "missing"

# Both files staged in git
staged=$(cd "$src" && git diff --cached --name-only)
case "$staged" in
  *"services/frontend/app/server.js"*)    pass "planE: server.js staged in git" ;;
  *)                                       fail "planE: server.js staged in git" "got: $staged" ;;
esac
case "$staged" in
  *"services/frontend/app/package.json"*) pass "planE: package.json staged in git" ;;
  *)                                       fail "planE: package.json staged in git" "got: $staged" ;;
esac

# Engineer-owned scaffolding untouched
for f in Dockerfile config.test.yaml config.prod.yaml .pipelines/service.yaml .pipelines/deploy_service.yaml; do
  path="$src/services/frontend/$f"
  [ -f "$path" ] && pass "planE: scaffolding preserved — $f" \
    || fail "planE: scaffolding preserved — $f" "deleted or missing"
done

rm -rf "$src"

# --- Idempotent: running on an already-minimal service exits 0 ---

src=$(make_v2_source_repo)
make_v2_service "$src" frontend true >/dev/null
scaffold_v2_oidc_sample "$src/services/frontend"
(cd "$src" && git add -A && git -c user.email=a@a -c user.name=a commit -q -m "scaffold")

# First strip
(cd "$src" && "$NCO_ROOT/bin/clean-sample.sh" frontend >/dev/null 2>&1)
# Second strip — should be a no-op
out=$(cd "$src" && "$NCO_ROOT/bin/clean-sample.sh" frontend 2>&1); rc=$?
assert_eq "0" "$rc"                              "planE: re-run exits 0 (idempotent)"
assert_contains "$out" "already minimal"         "planE: re-run reports already-minimal"

rm -rf "$src"

# --- Modified-file refusal: substantial custom server.js, no marker → die ---

src=$(make_v2_source_repo)
make_v2_service "$src" frontend true >/dev/null
mkdir -p "$src/services/frontend/app"
# 40-line custom server, no OIDC marker
{
  printf '// Custom server — completely rewritten\n'
  printf 'const express = require("express");\n'
  printf 'const app = express();\n'
  for i in $(seq 1 35); do printf '// custom logic line %d\n' "$i"; done
  printf 'app.listen(3000);\n'
} > "$src/services/frontend/app/server.js"
echo '{"name":"custom","dependencies":{}}' > "$src/services/frontend/app/package.json"

custom_content_before=$(cat "$src/services/frontend/app/server.js")
out=$(cd "$src" && "$NCO_ROOT/bin/clean-sample.sh" frontend 2>&1); rc=$?
assert_eq "1" "$rc"                                "planE: modified file → exit 1"
assert_contains "$out" "doesn't look like the unmodified" "planE: modified file → clear refusal message"
custom_content_after=$(cat "$src/services/frontend/app/server.js")
assert_eq "$custom_content_before" "$custom_content_after" "planE: modified file untouched on refusal"

rm -rf "$src"

summary
