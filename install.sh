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
#
# Slim install (v1.5.1+, shallow as of v1.5.2, non-cone strict in v1.5.4):
#   The installer does two things on top of a normal clone to keep user
#   installs tiny:
#     1. `git clone --depth=1` — shallow clone; just the tip of main, no
#        history. Total .git/ size ~150 KB instead of ~1 MB+.
#     2. Non-cone `git sparse-checkout set /bin/ /lib/ /templates/
#        /shell/ /version.txt` — only what noclickops needs at runtime.
#        Root-level files (README, LICENSE, AGENTS.md, CLAUDE.md,
#        installer scripts) and dev-only folders (website/, tests/,
#        scripts/, .github/) stay in .git/ but never appear on disk.
#   `noclickops update` (bin/update.sh) uses `git pull --ff-only` which
#   maintains both the shallow boundary and the sparse set, so the install
#   stays small over time.
#   Contributors who need the full tree (to edit website/, tests/, etc.)
#   should `git clone` the repo directly rather than going through this
#   installer. The installer itself can be re-run via curl-piped-to-bash
#   any time — its script content is not in the slim install on purpose.

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

# --- Sparse-checkout: only check out what users run from ------------------
#
# Non-cone sparse-checkout. The working tree contains ONLY the folders
# (bin/, lib/, templates/, shell/) and the single file (version.txt) that
# noclickops needs at runtime. Everything else — root-level docs
# (README, LICENSE, AGENTS.md, CLAUDE.md), installer scripts, the docs
# website, tests, CI, plans — stays in .git/ but never materializes on
# disk. Idempotent: safe to call on a fresh clone OR on an existing full
# clone (git removes the now-excluded files).
#
# Cone mode was used in v1.5.1–v1.5.3 but it always keeps root-level
# files. Switched to non-cone in v1.5.4 to enforce the "only what's
# needed at runtime" principle. Non-cone has known performance cliffs on
# huge repos but is fine for noclickops's size.
slim_checkout() {
  if ! git -C "$NOCLICKOPS_DIR" sparse-checkout init --no-cone 2>/dev/null; then
    warn "sparse-checkout init failed (git too old? need 2.25+). Skipping slim layout."
    return 0
  fi
  # Non-cone patterns: leading slash anchors to repo root; trailing slash
  # restricts to a directory. The /version.txt entry is a single file.
  git -C "$NOCLICKOPS_DIR" sparse-checkout set \
    '/bin/' '/lib/' '/templates/' '/shell/' '/version.txt'
}

# --- Clone or pull --------------------------------------------------------

FRESH_INSTALL=0
if [ -d "$NOCLICKOPS_DIR/.git" ]; then
  step "noclickops already installed at $NOCLICKOPS_DIR — pulling latest"
  if ! git -C "$NOCLICKOPS_DIR" pull --ff-only; then
    die "git pull failed in $NOCLICKOPS_DIR — resolve manually, then re-run."
  fi
  ok "noclickops up to date."

  # Slim an existing pre-v1.5.1 full install if sparse-checkout isn't on yet.
  if [ "$(git -C "$NOCLICKOPS_DIR" config --get core.sparseCheckout 2>/dev/null)" != "true" ]; then
    info "Slimming install — restricting working tree to bin/ lib/ templates/ shell/ only."
    info "(Full repo history still in .git/; contributors who want the full tree can run"
    info " 'git -C $NOCLICKOPS_DIR sparse-checkout disable' to restore it.)"
    slim_checkout
    ok "Install slimmed."
  fi
elif [ -e "$NOCLICKOPS_DIR" ]; then
  die "$NOCLICKOPS_DIR exists but is not a git checkout. Move it aside and re-run."
else
  step "Installing noclickops to $NOCLICKOPS_DIR"
  info "Source: $NOCLICKOPS_REPO_URL"
  # Shallow clone (--depth=1) — users don't browse history, and `git pull
  # --ff-only` (what bin/update.sh runs) maintains the shallow boundary
  # over time, so .git/ stays small forever. Total fresh install ends up
  # around 350 KB (sparse working tree + shallow .git).
  if ! git clone --depth=1 "$NOCLICKOPS_REPO_URL" "$NOCLICKOPS_DIR"; then
    die "git clone failed."
  fi
  ok "Cloned to $NOCLICKOPS_DIR."

  # Slim the fresh clone to the runtime-only path set.
  slim_checkout
  ok "Slim layout applied (bin/ lib/ templates/ shell/ only)."

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

# From v1.1.0: PATH-add is the primary mechanism. Resolves `noclickops`
# from any shell context (interactive or not) — scripts, cron, CI, my
# AI tool, etc. The legacy shell-function source line stays supported
# for existing installs (the function continues to work), but new
# installs only need the PATH line.
PATH_LINE='[ -d "$HOME/.noclickops/bin" ] && case ":$PATH:" in *:"$HOME/.noclickops/bin":*) ;; *) export PATH="$HOME/.noclickops/bin:$PATH" ;; esac'

# --- Wire into rc file (idempotent) ---------------------------------------

step "Wiring 'noclickops' into your shell ($RC_SHELL → $RC_FILE)"

# Detect any prior wiring — either the v1.0.x source-line OR the v1.1.x
# PATH-line. Either is enough; don't double-wire.
ALREADY_INSTALLED=0
if [ -f "$RC_FILE" ] && grep -qE '\.noclickops/(bin|shell/init\.sh)' "$RC_FILE" 2>/dev/null; then
  ALREADY_INSTALLED=1
fi

if [ "$ALREADY_INSTALLED" -eq 1 ]; then
  ok "noclickops is already wired into $RC_FILE — leaving it alone."
  ok "If you upgraded from v1.0.x and want PATH-based resolution in non-interactive"
  ok "shells too, add this line to $RC_FILE:"
  printf "    %s\n" "$PATH_LINE"
else
  info "Will append to $RC_FILE:"
  printf "    %s\n" "$PATH_LINE"
  if ask_yes_no "Append now? [Y/n] " "y"; then
    {
      printf "\n# noclickops — put bin on PATH (installed %s)\n" "$(date +%Y-%m-%d)"
      printf "%s\n" "$PATH_LINE"
    } >> "$RC_FILE"
    ok "Appended."
  else
    warn "Skipped. Paste this line into $RC_FILE manually when ready:"
    printf "    %s\n" "$PATH_LINE"
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
