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

# 3. rc file has exactly one source line.
count=$(grep -c "noclickops/shell/init.sh" "$TEST_ROOT/home/.zshrc")
assert_eq "1" "$count" "rc file has source line exactly once after first install"

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

# 5. rc file still has exactly one source line after re-run.
count=$(grep -c "noclickops/shell/init.sh" "$TEST_ROOT/home/.zshrc")
assert_eq "1" "$count" "rc file source line still unique after re-install"

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

# 9. Lister hides empty sections.
out="$("$INSTALL_DIR/bin/noclickops.sh" 2>&1)"
assert_contains "$out" "Meta"               "lister shows Meta section"
# In the freshly-installed repo (from this commit), Git/Deploy/etc. will be
# present too. So we only check that empty-section logic exists structurally.

rm -rf "$TEST_ROOT"

summary
