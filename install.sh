#!/usr/bin/env bash
# install.sh — noclickops one-time installer.
#
# Two ways to run:
#
#   1) curl -fsSL https://raw.githubusercontent.com/terchris/noclickops/main/install.sh | bash
#   2) ~/.noclickops/install.sh            (re-run after manual clone)
#
# Behaviours:
#   - Idempotent: if $NOCLICKOPS_DIR/.git exists, pulls instead of cloning.
#   - Adds a single source line to your shell rc; checks before appending so
#     repeated runs don't duplicate it.
#   - Reads prompts from /dev/tty so `curl | bash` is still interactive.
#
# Env overrides (for testing / forks):
#   NOCLICKOPS_DIR        default: $HOME/.noclickops
#   NOCLICKOPS_REPO_URL   default: https://github.com/terchris/noclickops.git

set -euo pipefail

# Inline minimal logging — lib/logging.sh isn't on disk yet on first install.
if [ -t 1 ]; then
  _C_BLUE='\033[0;34m'; _C_GREEN='\033[0;32m'; _C_YELLOW='\033[0;33m'
  _C_RED='\033[0;31m';  _C_BOLD='\033[1m';     _C_NC='\033[0m'
else
  _C_BLUE=''; _C_GREEN=''; _C_YELLOW=''; _C_RED=''; _C_BOLD=''; _C_NC=''
fi
info()    { printf "${_C_BLUE}ℹ${_C_NC} %s\n" "$*"; }
ok()      { printf "${_C_GREEN}✓${_C_NC} %s\n" "$*"; }
warn()    { printf "${_C_YELLOW}⚠${_C_NC} %s\n" "$*" >&2; }
err()     { printf "${_C_RED}✗${_C_NC} %s\n" "$*" >&2; }
step()    { printf "\n${_C_BOLD}==> %s${_C_NC}\n" "$*"; }
die()     { err "$*"; exit 1; }

# Prompt with default; reads /dev/tty when stdin is not a TTY (curl | bash).
# Falls back to default if no controlling terminal exists (CI, non-interactive
# pipes).
#
# Subtlety: `read -p` writes its prompt to stderr. Earlier versions of this
# function wrapped the read in `2>/dev/null` to suppress noisy
# "Device not configured" errors in headless environments — but that wrap
# also silenced the prompt itself, leaving the user staring at a blocked
# shell with no visible "Append now? [Y/n]" line. Now we write the prompt
# explicitly to /dev/tty (which fails-soft if /dev/tty is unwritable) and
# wrap only the read in 2>/dev/null.
ask_yes_no() {
  local prompt="$1" default="${2:-y}" answer=""
  if [ -t 0 ]; then
    read -r -p "$prompt" answer || true
  elif [ -e /dev/tty ]; then
    printf '%s' "$prompt" > /dev/tty 2>/dev/null || true
    { read -r answer < /dev/tty; } 2>/dev/null || true
  else
    answer="$default"
  fi
  answer="${answer:-$default}"
  case "$answer" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# --- Setup ----------------------------------------------------------------

NOCLICKOPS_DIR="${NOCLICKOPS_DIR:-$HOME/.noclickops}"
NOCLICKOPS_REPO_URL="${NOCLICKOPS_REPO_URL:-https://github.com/terchris/noclickops.git}"

command -v git >/dev/null 2>&1 || die "'git' not found on PATH. Install git first."

# --- Clone or pull --------------------------------------------------------

FRESH_INSTALL=0
if [ -d "$NOCLICKOPS_DIR/.git" ]; then
  step "noclickops already installed at $NOCLICKOPS_DIR — pulling latest"
  if ! git -C "$NOCLICKOPS_DIR" pull --ff-only; then
    die "git pull failed in $NOCLICKOPS_DIR — resolve manually, then re-run."
  fi
  ok "noclickops up to date."
elif [ -e "$NOCLICKOPS_DIR" ]; then
  die "$NOCLICKOPS_DIR exists but is not a git checkout. Move it aside and re-run."
else
  step "Installing noclickops to $NOCLICKOPS_DIR"
  info "Source: $NOCLICKOPS_REPO_URL"
  if ! git clone "$NOCLICKOPS_REPO_URL" "$NOCLICKOPS_DIR"; then
    die "git clone failed."
  fi
  ok "Cloned to $NOCLICKOPS_DIR."
  FRESH_INSTALL=1
fi

# --- Detect rc file -------------------------------------------------------

RC_FILE=""
RC_SHELL=""
case "${SHELL:-}" in
  */zsh)  RC_FILE="$HOME/.zshrc"  ; RC_SHELL="zsh"  ;;
  */bash) RC_FILE="$HOME/.bashrc" ; RC_SHELL="bash" ;;
  *)
    # Fall back to whichever exists; prefer zsh on macOS.
    if [ -f "$HOME/.zshrc" ]; then
      RC_FILE="$HOME/.zshrc"; RC_SHELL="zsh"
    else
      RC_FILE="$HOME/.bashrc"; RC_SHELL="bash"
    fi
    ;;
esac

SOURCE_LINE='[ -f "$HOME/.noclickops/shell/init.sh" ] && . "$HOME/.noclickops/shell/init.sh"'

# --- Wire into rc file (idempotent) ---------------------------------------

step "Wiring 'noclickops' into your shell ($RC_SHELL → $RC_FILE)"

# Use a fixed grep marker so we detect prior installs even if user edited
# their copy of the source line.
ALREADY_INSTALLED=0
if [ -f "$RC_FILE" ] && grep -q ".noclickops/shell/init.sh" "$RC_FILE" 2>/dev/null; then
  ALREADY_INSTALLED=1
fi

if [ "$ALREADY_INSTALLED" -eq 1 ]; then
  ok "Shell function is already wired into $RC_FILE — leaving it alone."
else
  info "Will append to $RC_FILE:"
  printf "    %s\n" "$SOURCE_LINE"
  if ask_yes_no "Append now? [Y/n] " "y"; then
    {
      printf "\n# noclickops — typeable shell function (installed %s)\n" "$(date +%Y-%m-%d)"
      printf "%s\n" "$SOURCE_LINE"
    } >> "$RC_FILE"
    ok "Appended."
  else
    warn "Skipped. Paste this line into $RC_FILE manually when ready:"
    printf "    %s\n" "$SOURCE_LINE"
  fi
fi

# --- Welcome + next steps -------------------------------------------------

# Show full welcome only on first install; keep the re-run path quiet.
if [ "$FRESH_INSTALL" -eq 1 ] && [ -f "$NOCLICKOPS_DIR/templates/welcome.txt" ]; then
  echo ""
  cat "$NOCLICKOPS_DIR/templates/welcome.txt"
fi

echo ""
ok "Done. Restart your shell or run:  source $RC_FILE"
