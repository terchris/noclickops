#!/usr/bin/env bash
# tests/run-all.sh — discover and run every test-*.sh.
# Exit 0 if all pass, 1 if any failed. CI contract.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -t 1 ]; then
  _R_RED='\033[0;31m'; _R_GREEN='\033[0;32m'; _R_YELLOW='\033[0;33m'
  _R_BOLD='\033[1m'; _R_NC='\033[0m'
else
  _R_RED=''; _R_GREEN=''; _R_YELLOW=''; _R_BOLD=''; _R_NC=''
fi

total_passed=0
total_failed=0
total_skipped=0
failed_files=()

tmp_out=$(mktemp)
trap "rm -f '$tmp_out'" EXIT

for f in "$SCRIPT_DIR"/test-*.sh; do
  [ -f "$f" ] || continue
  rel="${f#$SCRIPT_DIR/}"
  printf "\n${_R_BOLD}════════════════════════════════════════════════${_R_NC}\n"
  printf "${_R_BOLD}  %s${_R_NC}\n" "$rel"
  printf "${_R_BOLD}════════════════════════════════════════════════${_R_NC}\n"

  # Run the test file once; tee its output for both visibility and parsing.
  # pipefail + PIPESTATUS preserves the test's own exit code.
  set +e
  bash "$f" 2>&1 | tee "$tmp_out"
  file_rc=${PIPESTATUS[0]}
  set -e

  marker=$(grep -E '^##NCO_TEST_COUNTS' "$tmp_out" | tail -1 || true)
  if [ -n "$marker" ]; then
    p=$(printf '%s' "$marker"  | sed -E 's/.*p=([0-9]+).*/\1/')
    fl=$(printf '%s' "$marker" | sed -E 's/.*f=([0-9]+).*/\1/')
    s=$(printf '%s' "$marker"  | sed -E 's/.*s=([0-9]+).*/\1/')
    total_passed=$((total_passed + p))
    total_failed=$((total_failed + fl))
    total_skipped=$((total_skipped + s))
  fi

  if [ "$file_rc" -eq 0 ]; then
    printf "\n${_R_GREEN}▶ %s PASSED${_R_NC}\n" "$rel"
  else
    printf "\n${_R_RED}▶ %s FAILED${_R_NC}\n" "$rel"
    failed_files+=("$rel")
  fi
done

printf "\n${_R_BOLD}════════════════════════════════════════════════${_R_NC}\n"
printf "${_R_BOLD}  TOTAL${_R_NC}\n"
printf "${_R_BOLD}════════════════════════════════════════════════${_R_NC}\n"
printf "${_R_GREEN}  Passed:  %d${_R_NC}\n" "$total_passed"
if [ "$total_failed" -gt 0 ]; then
  printf "${_R_RED}  Failed:  %d${_R_NC}\n" "$total_failed"
else
  printf "  Failed:  0\n"
fi
printf "${_R_YELLOW}  Skipped: %d${_R_NC}\n" "$total_skipped"

if [ "${#failed_files[@]}" -gt 0 ]; then
  echo ""
  printf "${_R_RED}Failed files:${_R_NC}\n"
  for ff in "${failed_files[@]}"; do
    printf "  ${_R_RED}✗${_R_NC} %s\n" "$ff"
  done
  exit 1
fi

exit 0
