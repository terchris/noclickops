#!/usr/bin/env bash
# lib/logging.sh — colored output helpers for noclickops.
#
# Source from a bin/ script; then call log_info / log_success / log_warn /
# log_error / log_step with a message. Colors auto-disable when stdout is
# not a TTY.

[[ -n "${_NCO_LOGGING_LOADED:-}" ]] && return 0
_NCO_LOGGING_LOADED=1

if [ -t 1 ]; then
  _NCO_BLUE='\033[0;34m'
  _NCO_GREEN='\033[0;32m'
  _NCO_YELLOW='\033[0;33m'
  _NCO_RED='\033[0;31m'
  _NCO_BOLD='\033[1m'
  _NCO_NC='\033[0m'
else
  _NCO_BLUE=''; _NCO_GREEN=''; _NCO_YELLOW=''; _NCO_RED=''; _NCO_BOLD=''; _NCO_NC=''
fi

log_info()    { printf "${_NCO_BLUE}ℹ${_NCO_NC} %s\n" "$*"; }
log_success() { printf "${_NCO_GREEN}✓${_NCO_NC} %s\n" "$*"; }
log_warn()    { printf "${_NCO_YELLOW}⚠${_NCO_NC} %s\n" "$*" >&2; }
log_error()   { printf "${_NCO_RED}✗${_NCO_NC} %s\n" "$*" >&2; }
log_step()    { printf "\n${_NCO_BOLD}==> %s${_NCO_NC}\n" "$*"; }
