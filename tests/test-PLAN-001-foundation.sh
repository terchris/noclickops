#!/usr/bin/env bash
# tests/test-PLAN-001-foundation.sh — coverage for bin/noclickops + bin/update +
# lib/{logging,utilities,paths,metadata}.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-001: foundation ──"

# 1. Lister includes noclickops + update (the two scripts PLAN-001 shipped).
out=$("$NCO_ROOT/bin/noclickops.sh" 2>&1)
assert_contains "$out" "noclickops"     "lister includes 'noclickops'"
assert_contains "$out" "update"         "lister includes 'update'"
assert_contains "$out" "Meta"           "lister has 'Meta' section header"

# 2. --help prints metadata-driven block.
out=$("$NCO_ROOT/bin/noclickops.sh" --help 2>&1)
assert_contains "$out" "Usage:"         "noclickops --help has Usage section"
assert_contains "$out" "Category: meta" "noclickops --help shows category"
assert_contains "$out" "Flags:"         "noclickops --help has Flags section"

out=$("$NCO_ROOT/bin/update.sh" --help 2>&1)
assert_contains "$out" "Pull the latest" "update --help shows description"
assert_contains "$out" "Usage:"          "update --help has Usage section"

# 3. update.sh fails fast when install dir isn't a git checkout.
NONGIT=$(mktemp -d)
mkdir -p "$NONGIT/lib" "$NONGIT/bin"
cp "$NCO_ROOT/lib/"*.sh "$NONGIT/lib/"
cp "$NCO_ROOT/bin/update.sh" "$NONGIT/bin/"
chmod +x "$NONGIT/bin/update.sh"
out=$("$NONGIT/bin/update.sh" 2>&1); rc=$?
assert_eq "1" "$rc" "update.sh exit 1 on non-git install dir"
assert_contains "$out" "not a git checkout" "update.sh error mentions non-git"
rm -rf "$NONGIT"

# 4. TARGET_REPO resolution.
out=$(cd /tmp && bash -c ". '$NCO_ROOT/lib/paths.sh' && echo \"TR=\${TARGET_REPO:-}\"")
assert_eq "TR=" "$out" "TARGET_REPO empty outside any git repo"

out=$(cd "$NCO_ROOT" && bash -c ". '$NCO_ROOT/lib/paths.sh' && echo \"TR=\$TARGET_REPO\"")
assert_eq "TR=$NCO_ROOT" "$out" "TARGET_REPO matches repo root inside repo"

# 5. NOCLICKOPS_DIR resolution via paths.sh.
out=$(bash -c ". '$NCO_ROOT/lib/paths.sh' && echo \"NCO=\$NOCLICKOPS_DIR\"")
assert_eq "NCO=$NCO_ROOT" "$out" "NOCLICKOPS_DIR resolves to repo root"

# 6. Sourcing-guards prevent double-init.
out=$(bash -c "
  . '$NCO_ROOT/lib/logging.sh'
  . '$NCO_ROOT/lib/logging.sh'
  . '$NCO_ROOT/lib/logging.sh'
  log_success 'sourced thrice'
")
assert_contains "$out" "sourced thrice" "triple-sourced logging.sh still functional"

# 7. Metadata parser handles plain double-quoted values.
out=$(bash -c "
  . '$NCO_ROOT/lib/metadata.sh'
  parse_metadata '$NCO_ROOT/bin/update.sh'
  printf '%s\n' \"\$parsed_name\"
")
assert_eq "update" "$out" "parse_metadata extracts SCRIPT_NAME from update.sh"

summary
