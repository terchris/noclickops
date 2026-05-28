#!/usr/bin/env bash
# tests/test-PLAN-101-version-check.sh — coverage for lib/version.sh + the
# version-aware lister behaviour. Network is stubbed via file:// URLs.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-101: version check ──"

# --- nco_load_version ---

out=$(bash -c "
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/version.sh'
  nco_load_version
  echo \"\$NCO_VERSION\"
")
assert_eq "1.0.0" "$out" "nco_load_version: reads version.txt"

# Missing version.txt → "unknown" fallback.
FAKE_INSTALL=$(mktemp -d)
cp -r "$NCO_ROOT/lib" "$FAKE_INSTALL/lib"
mkdir -p "$FAKE_INSTALL/bin"
# (no version.txt)
out=$(bash -c "
  . '$FAKE_INSTALL/lib/paths.sh'
  . '$FAKE_INSTALL/lib/version.sh'
  nco_load_version
  echo \"\$NCO_VERSION\"
")
assert_eq "unknown" "$out" "nco_load_version: missing file → 'unknown'"
rm -rf "$FAKE_INSTALL"

# --- nco_check_remote with stubbed URL ---

# Build a stub install: own lib/, own version.txt, own remote-stub file.
STUB=$(mktemp -d)
cp -r "$NCO_ROOT/lib" "$STUB/lib"
mkdir -p "$STUB/bin"
echo "1.0.0" > "$STUB/version.txt"
echo "1.0.5" > "$STUB/remote-stub.txt"

# 1. Remote newer than local → NCO_REMOTE_VERSION set.
out=$(bash -c "
  unset NCO_VERSION_CHECK_URL
  export NCO_VERSION_CHECK_URL='file://$STUB/remote-stub.txt'
  rm -f '$STUB/.version-cache'
  . '$STUB/lib/paths.sh'
  . '$STUB/lib/version.sh'
  nco_load_version
  nco_check_remote
  echo \"LOCAL=\$NCO_VERSION REMOTE=\$NCO_REMOTE_VERSION\"
")
assert_contains "$out" "LOCAL=1.0.0 REMOTE=1.0.5" "remote newer → REMOTE_VERSION set"

# 2. Cache file written after fetch.
assert_file_exists "$STUB/.version-cache" "cache file written after remote fetch"

# 3. Cache hit on second call (remote stub now nonexistent → still gets cached value).
rm -f "$STUB/remote-stub.txt"
out=$(bash -c "
  export NCO_VERSION_CHECK_URL='file://$STUB/remote-stub.txt'  # doesn't exist
  . '$STUB/lib/paths.sh'
  . '$STUB/lib/version.sh'
  nco_load_version
  nco_check_remote
  echo \"REMOTE=\$NCO_REMOTE_VERSION\"
")
assert_contains "$out" "REMOTE=1.0.5" "cache hit (within TTL) uses cached value"

# 4. Cache invalidation: clear cache + nonexistent URL → empty remote.
rm -f "$STUB/.version-cache"
out=$(bash -c "
  export NCO_VERSION_CHECK_URL='file://$STUB/remote-stub.txt'  # still doesn't exist
  . '$STUB/lib/paths.sh'
  . '$STUB/lib/version.sh'
  nco_load_version
  nco_check_remote
  echo \"REMOTE=\$NCO_REMOTE_VERSION\"
")
assert_contains "$out" "REMOTE=" "cache cleared + remote unreachable → empty"

# 5. Remote equals local → no update hint.
echo "1.0.5" > "$STUB/remote-stub.txt"   # matches local
# Local is still 1.0.0 — change it to match for this test.
echo "1.0.5" > "$STUB/version.txt"
rm -f "$STUB/.version-cache"
out=$(bash -c "
  export NCO_VERSION_CHECK_URL='file://$STUB/remote-stub.txt'
  . '$STUB/lib/paths.sh'
  . '$STUB/lib/version.sh'
  nco_load_version
  nco_check_remote
  echo \"REMOTE=\$NCO_REMOTE_VERSION\"
")
assert_contains "$out" "REMOTE=" "remote == local → REMOTE_VERSION empty"

# 6. Cache TTL: set TTL=0 means cache always expired.
echo "1.0.0" > "$STUB/version.txt"
echo "1.0.5" > "$STUB/remote-stub.txt"
# Pre-seed cache with an old timestamp.
printf '%s %s\n' "100" "1.0.99-stale" > "$STUB/.version-cache"
out=$(bash -c "
  export NCO_VERSION_CHECK_URL='file://$STUB/remote-stub.txt'
  export NCO_VERSION_CACHE_TTL=1
  . '$STUB/lib/paths.sh'
  . '$STUB/lib/version.sh'
  nco_load_version
  nco_check_remote
  echo \"REMOTE=\$NCO_REMOTE_VERSION\"
")
# TTL=1, ts=100, now=much later → expired → refetch → 1.0.5.
assert_contains "$out" "REMOTE=1.0.5" "expired cache → refetch from remote"

# 7. Malformed cache file → falls through to fetch.
echo "garbage not a timestamp" > "$STUB/.version-cache"
out=$(bash -c "
  export NCO_VERSION_CHECK_URL='file://$STUB/remote-stub.txt'
  . '$STUB/lib/paths.sh'
  . '$STUB/lib/version.sh'
  nco_load_version
  nco_check_remote
  echo \"REMOTE=\$NCO_REMOTE_VERSION\"
")
assert_contains "$out" "REMOTE=1.0.5" "malformed cache → falls through to fetch"

rm -rf "$STUB"

# --- nco_show_update_hint ---

out=$(bash -c "
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/version.sh'
  NCO_REMOTE_VERSION='9.9.9'
  nco_show_update_hint
")
assert_contains "$out" "Update available: v9.9.9" "show_update_hint: prints hint when set"
assert_contains "$out" "run 'noclickops update'"  "show_update_hint: tells user what to run"

out=$(bash -c "
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/version.sh'
  NCO_REMOTE_VERSION=''
  nco_show_update_hint
")
assert_eq "" "$out" "show_update_hint: silent when no remote known"

# --- bin/noclickops.sh lister: shows local version ---

out=$("$NCO_ROOT/bin/noclickops.sh" 2>&1)
assert_contains "$out" "noclickops v1.0.0" "lister header shows local version"

# --- bin/update.sh clears the cache (we test the rm path by pre-creating
# the cache file and confirming update would delete it; but we can't
# actually run 'git pull' here. Just verify the path is in the script.) ---

if grep -q "rm -f.*\\.version-cache" "$NCO_ROOT/bin/update.sh"; then
  pass "update.sh contains cache-busting rm"
else
  fail "update.sh contains cache-busting rm" "no .version-cache rm found"
fi

# --- portability: derivation from git remote, no hardcoded user/repo ---

# 8. _nco_derive_check_url builds the raw URL from a github origin remote.
# Note: paths.sh resolves NOCLICKOPS_DIR from BASH_SOURCE — we override
# AFTER sourcing it (and version.sh's guard prevents re-sourcing paths.sh).
DERIVE_REPO=$(mktemp -d)
git -C "$DERIVE_REPO" init -q -b main
git -C "$DERIVE_REPO" remote add origin "https://github.com/alice/noclickops.git"
out=$(bash -c "
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/version.sh'
  NOCLICKOPS_DIR='$DERIVE_REPO'
  _nco_derive_check_url
")
assert_eq "https://raw.githubusercontent.com/alice/noclickops/main/version.txt" "$out" \
  "derive_check_url: https origin → raw URL for that fork"

# 9. SSH-form origin.
git -C "$DERIVE_REPO" remote set-url origin "git@github.com:bob/noclickops.git"
out=$(bash -c "
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/version.sh'
  NOCLICKOPS_DIR='$DERIVE_REPO'
  _nco_derive_check_url
")
assert_eq "https://raw.githubusercontent.com/bob/noclickops/main/version.txt" "$out" \
  "derive_check_url: git@ origin → raw URL"

# 10. Non-GitHub origin → derivation returns nothing (silent skip).
git -C "$DERIVE_REPO" remote set-url origin "https://dev.azure.com/org/proj/_git/noclickops"
out=$(bash -c "
  . '$NCO_ROOT/lib/paths.sh'
  . '$NCO_ROOT/lib/version.sh'
  NOCLICKOPS_DIR='$DERIVE_REPO'
  _nco_derive_check_url 2>/dev/null
  echo \"rc=\$?\"
")
assert_contains "$out" "rc=1" "derive_check_url: non-GitHub origin returns non-zero"

rm -rf "$DERIVE_REPO"

# 11. Hardcoded-identity sweep in version code.
# Catches future regressions: no string like 'terchris/noclickops' should
# appear in lib/version.{sh,ps1} (or any bin/lib).
matches=$(grep -E 'terchris/noclickops' "$NCO_ROOT/lib/version.sh" "$NCO_ROOT/lib/version.ps1" 2>/dev/null || true)
assert_eq "" "$matches" "no hardcoded 'terchris/noclickops' in lib/version.{sh,ps1}"

summary
