#!/usr/bin/env bash
# tests/test-PLAN-003-pr-and-merge.sh — coverage for lib/azdo.sh +
# bin/create-pr.sh + bin/merge-pr.sh. No real az calls; pre-az validation
# and URL derivation only.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
. "$SCRIPT_DIR/_fixtures.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-003: create-pr + merge-pr ──"

# 1. Lister shows the Git / pull requests section.
out=$("$NCO_ROOT/bin/noclickops.sh" 2>&1)
assert_contains "$out" "Git / pull requests" "lister has 'Git / pull requests' section"
assert_contains "$out" "create-pr"           "lister shows create-pr"
assert_contains "$out" "merge-pr"            "lister shows merge-pr"

# 2. --help with embedded quotes parses cleanly.
out=$("$NCO_ROOT/bin/create-pr.sh" --help 2>&1)
assert_contains "$out" 'noclickops create-pr "<title>"' "create-pr --help shows quoted usage"
assert_contains "$out" "Category: git"                 "create-pr --help shows category"

out=$("$NCO_ROOT/bin/merge-pr.sh" --help 2>&1)
assert_contains "$out" "noclickops merge-pr <pr-id>" "merge-pr --help shows usage"

# 3. Missing-arg errors fire before any az lookup.
out=$("$NCO_ROOT/bin/create-pr.sh" 2>&1); rc=$?
assert_eq "1" "$rc"                         "create-pr no args exit 1"
assert_contains "$out" "Usage:"             "create-pr no args shows usage"

out=$("$NCO_ROOT/bin/merge-pr.sh" 2>&1); rc=$?
assert_eq "1" "$rc"                         "merge-pr no args exit 1"
assert_contains "$out" "Usage:"             "merge-pr no args shows usage"

# 4. URL derivation across 5 URL forms.
derive() {
  local origin="$1"
  local d
  d=$(make_target_repo "$origin")
  # Need to remove the dummy origin and re-add (make_target_repo adds the
  # default). For non-default URLs we need to set it explicitly.
  git -C "$d" remote remove origin
  git -C "$d" remote add origin "$origin"
  bash -c "
    . '$NCO_ROOT/lib/azdo.sh'
    derive_azdo_context '$d'
    printf '%s|%s|%s\n' \"\$AZDO_ORG\" \"\$AZDO_PROJECT\" \"\$AZDO_REPO\"
  "
  rm -rf "$d"
}

out=$(derive "https://dev.azure.com/ExampleOrg/FrontendPlatform/_git/JKL900X016-NerdMeet")
assert_eq "ExampleOrg|FrontendPlatform|JKL900X016-NerdMeet" "$out" "URL form: https plain"

out=$(derive "https://terje@dev.azure.com/ExampleOrg/FrontendPlatform/_git/JKL900X016-NerdMeet")
assert_eq "ExampleOrg|FrontendPlatform|JKL900X016-NerdMeet" "$out" "URL form: https with user@"

out=$(derive "https://dev.azure.com/ExampleOrg/FrontendPlatform/_git/JKL900X016-NerdMeet.git")
assert_eq "ExampleOrg|FrontendPlatform|JKL900X016-NerdMeet" "$out" "URL form: https with .git suffix"

out=$(derive "git@ssh.dev.azure.com:v3/ExampleOrg/FrontendPlatform/JKL900X016-NerdMeet")
assert_eq "ExampleOrg|FrontendPlatform|JKL900X016-NerdMeet" "$out" "URL form: ssh"

out=$(derive "https://dev.azure.com/AcmeCorp/Platform/_git/some-app")
assert_eq "AcmeCorp|Platform|some-app" "$out" "URL form: different org"

# 5. Non-ADO URL is rejected with a clear error.
d=$(make_target_repo "https://github.com/some/repo")
out=$(bash -c "
  . '$NCO_ROOT/lib/azdo.sh'
  derive_azdo_context '$d' 2>&1
")
assert_contains "$out" "doesn't look like Azure DevOps" "GitHub URL rejected with documented error"
rm -rf "$d"

# 6. "on main" guard fires before any az call.
d=$(make_target_repo "https://dev.azure.com/AcmeCorp/Platform/_git/some-app")
out=$(cd "$d" && "$NCO_ROOT/bin/create-pr.sh" "test title" 2>&1); rc=$?
assert_eq "1" "$rc" "create-pr on main exit 1"
assert_contains "$out" "You are on main" "create-pr on main shows feature-branch hint"
rm -rf "$d"

summary
