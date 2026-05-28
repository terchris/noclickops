#!/usr/bin/env bash
# tests/test-PLAN-005-clean-sample.sh — coverage for bin/clean-sample.sh.
# Pure local; no az.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-005: clean-sample ──"

# 1. Lister + --help.
out=$("$NCO_ROOT/bin/noclickops.sh" 2>&1)
assert_contains "$out" "Service lifecycle" "lister has 'Service lifecycle' section"
assert_contains "$out" "clean-sample"      "lister shows clean-sample"

out=$("$NCO_ROOT/bin/clean-sample.sh" --help 2>&1)
assert_contains "$out" "Category: service-lifecycle" "clean-sample --help category"

# 2. No args.
out=$("$NCO_ROOT/bin/clean-sample.sh" 2>&1); rc=$?
assert_eq "1" "$rc"             "clean-sample no args exit 1"
assert_contains "$out" "Usage:" "clean-sample no args shows usage"

# 3. Outside a git repo.
out=$(cd /tmp && "$NCO_ROOT/bin/clean-sample.sh" foo 2>&1); rc=$?
assert_eq "1" "$rc"                                  "clean-sample outside repo exit 1"
assert_contains "$out" "Not inside a git repository" "clean-sample outside repo error"

# Build a target repo with three services for the safety scenarios.
repo=$(make_target_repo)
svc_intact=$(make_service "$repo" "svc-intact")
scaffold_nextjs_sample "$svc_intact"
svc_clean=$(make_service "$repo" "svc-clean")
svc_realcode=$(make_service "$repo" "svc-realcode")
# Real code in svc-realcode: sample-like files exist but NO control-panel marker.
mkdir -p "$svc_realcode/app" "$svc_realcode/components"
echo "real" > "$svc_realcode/app/page.js"
echo "not the marker" > "$svc_realcode/components/something.js"

# Commit everything in the target repo so we have a mix of tracked/untracked.
git -C "$repo" -c user.email=a@a -c user.name=a add services/svc-intact/Dockerfile \
    services/svc-intact/service.yaml services/svc-intact/.pipelines/ \
    services/svc-intact/package.json services/svc-intact/components/control-panel.js >/dev/null
git -C "$repo" -c user.email=a@a -c user.name=a commit -q -m "scaffold"
# Leave app/, public/, package-lock.json, next.config.mjs UNTRACKED in svc-intact.

# 4. Unknown service.
out=$(cd "$repo" && "$NCO_ROOT/bin/clean-sample.sh" ghost 2>&1); rc=$?
assert_eq "1" "$rc"                             "clean-sample unknown service exit 1"
assert_contains "$out" "No such service folder" "clean-sample unknown shows not-found"

# 5. Already-clean service → exit 0.
out=$(cd "$repo" && "$NCO_ROOT/bin/clean-sample.sh" svc-clean 2>&1); rc=$?
assert_eq "0" "$rc"                        "clean-sample already-clean exit 0"
assert_contains "$out" "already clean"     "clean-sample already-clean message"

# 6. Safety refusal when marker missing.
out=$(cd "$repo" && "$NCO_ROOT/bin/clean-sample.sh" svc-realcode 2>&1); rc=$?
assert_eq "1" "$rc"                             "clean-sample no-marker exit 1"
assert_contains "$out" "Refusing to auto-delete" "clean-sample no-marker refusal message"
# Files left intact.
assert_file_exists "$svc_realcode/app/page.js"         "svc-realcode app/page.js preserved after refusal"
assert_file_exists "$svc_realcode/components/something.js" "svc-realcode components/something.js preserved"
assert_file_exists "$svc_realcode/Dockerfile"          "svc-realcode Dockerfile preserved"

# 7. Intact sample → all 6 sample paths removed; scaffolding preserved.
( cd "$repo" && "$NCO_ROOT/bin/clean-sample.sh" svc-intact >/dev/null 2>&1 )
for p in app components public package.json package-lock.json next.config.mjs; do
  assert_file_absent "$svc_intact/$p" "svc-intact: $p removed"
done
for p in Dockerfile service.yaml .pipelines bicep; do
  assert_file_exists "$svc_intact/$p" "svc-intact: $p preserved"
done

# 8. Tracked files staged as deletions in git.
git_status=$(git -C "$repo" status -s services/svc-intact/)
assert_contains "$git_status" "D  services/svc-intact/components/control-panel.js" \
    "tracked control-panel.js deletion staged"
assert_contains "$git_status" "D  services/svc-intact/package.json" \
    "tracked package.json deletion staged"

rm -rf "$repo"

summary
