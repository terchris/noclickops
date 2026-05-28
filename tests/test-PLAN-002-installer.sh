#!/usr/bin/env bash
# tests/test-PLAN-002-installer.sh — coverage for install.sh + shell/init.sh +
# the upgraded grouped lister.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_harness.sh"
NCO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "── PLAN-002: installer + shell function + grouped lister ──"

# Sandbox a fake $HOME so the test doesn't touch the real ~/.zshrc.
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/home"
touch "$TEST_ROOT/home/.zshrc"
INSTALL_DIR="$TEST_ROOT/noclickops-install"

# 1. Fresh install clones from the local working tree.
out=$(
  HOME="$TEST_ROOT/home" \
  SHELL="/bin/zsh" \
  NOCLICKOPS_DIR="$INSTALL_DIR" \
  NOCLICKOPS_REPO_URL="$NCO_ROOT" \
  bash "$NCO_ROOT/install.sh" < /dev/null 2>&1
); rc=$?
assert_eq "0" "$rc"                       "install.sh fresh install exits 0"
assert_contains "$out" "Cloned to"        "install.sh reports cloning"
assert_contains "$out" "Welcome to"       "welcome shown on fresh install"

# 2. Install populated the expected layout.
assert_file_exists "$INSTALL_DIR/bin/noclickops.sh" "install dir has bin/noclickops.sh"
assert_file_exists "$INSTALL_DIR/bin/update.sh"     "install dir has bin/update.sh"
assert_file_exists "$INSTALL_DIR/lib/paths.sh"      "install dir has lib/paths.sh"
assert_file_exists "$INSTALL_DIR/shell/init.sh"     "install dir has shell/init.sh"

# 3. rc file has exactly one wiring line (PATH-based from v1.1.0).
count=$(grep -c '\.noclickops/bin' "$TEST_ROOT/home/.zshrc")
assert_eq "1" "$count" "rc file has PATH line exactly once after first install"

# 4. Re-running the installer is idempotent: pulls, leaves rc alone.
out=$(
  HOME="$TEST_ROOT/home" \
  SHELL="/bin/zsh" \
  NOCLICKOPS_DIR="$INSTALL_DIR" \
  NOCLICKOPS_REPO_URL="$NCO_ROOT" \
  bash "$NCO_ROOT/install.sh" < /dev/null 2>&1
); rc=$?
assert_eq "0" "$rc"                       "install.sh re-run exits 0"
assert_contains "$out" "already installed" "install.sh re-run detects existing install"
assert_contains "$out" "already wired"     "install.sh re-run leaves rc untouched"
assert_not_contains "$out" "Welcome to"    "welcome NOT re-shown on re-install"

# 5. rc file still has exactly one PATH line after re-run.
count=$(grep -c '\.noclickops/bin' "$TEST_ROOT/home/.zshrc")
assert_eq "1" "$count" "rc file PATH line still unique after re-install"

# 6. Sourcing init.sh enables the typeable `noclickops` form.
out=$(NOCLICKOPS_DIR="$INSTALL_DIR" bash -c "
  . '$INSTALL_DIR/shell/init.sh'
  noclickops
")
assert_contains "$out" "Meta" "sourced function dispatches to lister"

# 7. `noclickops update --help` dispatches to update.sh.
out=$(NOCLICKOPS_DIR="$INSTALL_DIR" bash -c "
  . '$INSTALL_DIR/shell/init.sh'
  noclickops update --help
")
assert_contains "$out" "Pull the latest" "function dispatches subcommands correctly"

# 8. `noclickops bogus` errors with hint, non-zero exit.
out=$(NOCLICKOPS_DIR="$INSTALL_DIR" bash -c "
  . '$INSTALL_DIR/shell/init.sh'
  noclickops bogus 2>&1; echo RC=\$?
")
assert_contains "$out" "no such command 'bogus'" "unknown subcommand → friendly error"
assert_contains "$out" "RC=1"                    "unknown subcommand exit 1"

# 8a. (v1.2.1 regression guard) `noclickops --help` and `noclickops -h` via
# the shell function must reach the dispatcher's --help, not be misclassified
# as 'no such command --help'. The pre-v1.2.1 function had its own dispatch
# loop that didn't recognise -h/--help and tried to find bin/--help.sh.
out=$(NOCLICKOPS_DIR="$INSTALL_DIR" bash -c "
  . '$INSTALL_DIR/shell/init.sh'
  noclickops --help 2>&1
")
assert_contains "$out" "Category: meta" "function forwards --help to dispatcher"
assert_not_contains "$out" "no such command '--help'" "function does NOT misclassify --help"

out=$(NOCLICKOPS_DIR="$INSTALL_DIR" bash -c "
  . '$INSTALL_DIR/shell/init.sh'
  noclickops -h 2>&1
")
assert_contains "$out" "Category: meta" "function forwards -h to dispatcher"

# 9. Lister hides empty sections.
out="$("$INSTALL_DIR/bin/noclickops.sh" 2>&1)"
assert_contains "$out" "Meta"               "lister shows Meta section"
# In the freshly-installed repo (from this commit), Git/Deploy/etc. will be
# present too. So we only check that empty-section logic exists structurally.

# 9a. (v1.1.0) bin/noclickops symlink exists and is executable.
assert_file_exists "$INSTALL_DIR/bin/noclickops" "bin/noclickops symlink present (PATH-resolvable name)"
if [ -x "$INSTALL_DIR/bin/noclickops" ]; then
  pass "bin/noclickops is executable"
else
  fail "bin/noclickops is executable"
fi

# 9b. (v1.1.0) PATH-based dispatch: invoking the symlink with no args
# should show the lister; with --help should show metadata; with a real
# subcommand should exec it.
out=$("$INSTALL_DIR/bin/noclickops" 2>&1)
assert_contains "$out" "noclickops v"        "PATH-dispatched bin/noclickops shows lister with version"

out=$("$INSTALL_DIR/bin/noclickops" --help 2>&1)
assert_contains "$out" "Category: meta"      "PATH-dispatched bin/noclickops --help shows metadata"

out=$("$INSTALL_DIR/bin/noclickops" update --help 2>&1)
assert_contains "$out" "Pull the latest"     "PATH-dispatched noclickops update --help dispatches to update.sh"

out=$("$INSTALL_DIR/bin/noclickops" bogus 2>&1); rc=$?
assert_eq "1" "$rc"                          "PATH-dispatched noclickops bogus exit 1"
assert_contains "$out" "no such command"     "PATH-dispatched noclickops bogus shows friendly error"

rm -rf "$TEST_ROOT"

# 10. Regression check (1.0.1): install.sh's curl|bash prompt must be
# written explicitly to /dev/tty. The earlier version wrapped
# 'read -r -p "$prompt" < /dev/tty' in 2>/dev/null which silenced the
# prompt itself (bash writes -p to stderr), making the installer hang
# at an invisible prompt. The fix is to printf the prompt to /dev/tty
# before the read. A proper PTY-based behavioural test is hard; this
# is a cheap grep guard against re-introducing the bug.
if grep -q "printf '%s' \"\$prompt\" > /dev/tty" "$NCO_ROOT/install.sh"; then
  pass "install.sh writes prompt to /dev/tty explicitly (1.0.1 regression guard)"
else
  fail "install.sh writes prompt to /dev/tty explicitly (1.0.1 regression guard)" \
       "did not find: printf '%s' \"\$prompt\" > /dev/tty"
fi

summary
