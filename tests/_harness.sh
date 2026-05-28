# tests/_harness.sh — shared test helpers.
#
# Sourced by each test-*.sh. Provides pass/fail accumulators, assertion
# helpers, and a `summary` function that returns 1 on any failure.
#
# Each test file boilerplate:
#   #!/usr/bin/env bash
#   set -uo pipefail   # NOT -e: we want assertions to keep running after a fail
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "$SCRIPT_DIR/_harness.sh"
#   . "$SCRIPT_DIR/_fixtures.sh"
#   NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
#
#   echo "── <PLAN name> ──"
#   # ... assertions ...
#   summary

[[ -n "${_NCO_HARNESS_LOADED:-}" ]] && return 0
_NCO_HARNESS_LOADED=1

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
FAILURES=()

if [ -t 1 ]; then
  _T_RED='\033[0;31m'; _T_GREEN='\033[0;32m'; _T_YELLOW='\033[0;33m'; _T_NC='\033[0m'
else
  _T_RED=''; _T_GREEN=''; _T_YELLOW=''; _T_NC=''
fi

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${_T_GREEN}✓${_T_NC} %s\n" "$1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  local name="$1" details="${2:-}"
  FAILURES+=("$name")
  printf "${_T_RED}✗${_T_NC} %s\n" "$name" >&2
  [ -n "$details" ] && printf "    %s\n" "$details" >&2
}

skip() {
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  printf "${_T_YELLOW}-${_T_NC} %s (skipped: %s)\n" "$1" "${2:-no reason given}"
}

assert_eq() {
  local expected="$1" actual="$2" name="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$name"
  else
    fail "$name" "expected: $(printf '%q' "$expected") | actual: $(printf '%q' "$actual")"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" name="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    pass "$name"
  else
    fail "$name" "did not contain: $needle"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" name="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    fail "$name" "unexpectedly contained: $needle"
  else
    pass "$name"
  fi
}

assert_file_exists() {
  local path="$1" name="$2"
  if [ -e "$path" ]; then pass "$name"; else fail "$name" "missing: $path"; fi
}

assert_file_absent() {
  local path="$1" name="$2"
  if [ ! -e "$path" ]; then pass "$name"; else fail "$name" "unexpectedly present: $path"; fi
}

# Usage: assert_exit_zero "test name" -- cmd args...
assert_exit_zero() {
  local name="$1"; shift
  [ "${1:-}" = "--" ] && shift
  local output rc=0
  output="$("$@" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$name"
  else
    fail "$name" "exit $rc; output: $(printf '%s' "$output" | head -3 | tr '\n' '|')"
  fi
}

# Usage: assert_exit_nonzero "test name" -- cmd args...
assert_exit_nonzero() {
  local name="$1"; shift
  [ "${1:-}" = "--" ] && shift
  local output rc=0
  output="$("$@" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "$name"
  else
    fail "$name" "expected non-zero exit; got 0; output: $(printf '%s' "$output" | head -3 | tr '\n' '|')"
  fi
}

summary() {
  echo ""
  echo "─────────────────────────────────────────"
  printf "Passed: %d  |  Failed: %d  |  Skipped: %d\n" \
    "$TESTS_PASSED" "$TESTS_FAILED" "$TESTS_SKIPPED"
  # CI-parseable marker — run-all.sh's tee-and-grep picks this up.
  printf "##NCO_TEST_COUNTS p=%d f=%d s=%d##\n" \
    "$TESTS_PASSED" "$TESTS_FAILED" "$TESTS_SKIPPED"
  if [ "$TESTS_FAILED" -gt 0 ]; then
    echo ""
    echo "Failing tests:"
    for name in "${FAILURES[@]}"; do
      printf "  ${_T_RED}✗${_T_NC} %s\n" "$name"
    done
    return 1
  fi
  return 0
}
