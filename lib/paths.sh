#!/usr/bin/env bash
# lib/paths.sh — well-known paths for noclickops.
#
# NOCLICKOPS_DIR resolves to the install root (parent of this lib/),
# regardless of how the calling bin/ script was invoked or symlinked.

[[ -n "${_NCO_PATHS_LOADED:-}" ]] && return 0
_NCO_PATHS_LOADED=1

NOCLICKOPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$NOCLICKOPS_DIR/bin"
LIB_DIR="$NOCLICKOPS_DIR/lib"
TEMPLATES_DIR="$NOCLICKOPS_DIR/templates"

# Target repo = the git repo enclosing pwd. Empty when pwd isn't in a repo.
# Scripts that need it must check non-empty themselves.
TARGET_REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
