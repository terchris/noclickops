#!/usr/bin/env bash
# lib/utilities.sh — shared helpers for noclickops bin/ scripts.

[[ -n "${_NCO_UTILITIES_LOADED:-}" ]] && return 0
_NCO_UTILITIES_LOADED=1

# Ensure logging is available — utilities depends on log_error.
_util_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${_NCO_LOGGING_LOADED:-}" ]] && . "$_util_dir/logging.sh"
unset _util_dir

# Print error and exit 1.
die() {
  log_error "$*"
  exit 1
}

# Require a command on PATH; die with a hint if missing.
require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found on PATH. Install it first."
}
