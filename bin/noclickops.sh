#!/usr/bin/env bash
# bin/noclickops.sh — list all noclickops commands, grouped by category.
#
# --- noclickops metadata ---
SCRIPT_NAME="noclickops"
SCRIPT_DESCRIPTION="List all noclickops commands grouped by category."
SCRIPT_USAGE="noclickops [<subcommand> [args...]]"
SCRIPT_EXAMPLE="noclickops"
SCRIPT_CATEGORY="meta"
# --- end metadata ---

set -euo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_dir/../lib/logging.sh"
. "$_dir/../lib/paths.sh"
. "$_dir/../lib/metadata.sh"
unset _dir

case "${1:-}" in
  -h|--help) show_help "$0"; exit 0 ;;
esac

# Section buffers — flat strings, bash 3.2 safe (no associative arrays).
_buf_meta=""
_buf_git=""
_buf_deploy=""
_buf_servicelifecycle=""
_buf_inspect=""

for script in "$BIN_DIR"/*.sh; do
  [ -f "$script" ] || continue
  parse_metadata "$script" 2>/dev/null || continue
  cmd_name="$(basename "$script" .sh)"
  desc="${parsed_description:-(no description)}"
  line="$(printf "  %-15s %s" "$cmd_name" "$desc")"
  case "${parsed_category:-meta}" in
    meta)              _buf_meta+="$line"$'\n' ;;
    git)               _buf_git+="$line"$'\n' ;;
    deploy)            _buf_deploy+="$line"$'\n' ;;
    service-lifecycle) _buf_servicelifecycle+="$line"$'\n' ;;
    inspect)           _buf_inspect+="$line"$'\n' ;;
    *)                 _buf_meta+="$line"$'\n' ;;  # unknown → meta
  esac
done

emit_section() {
  local title="$1" buf="$2"
  [ -z "$buf" ] && return 0
  printf "\n${_NCO_BOLD}%s${_NCO_NC}\n%s" "$title" "$buf"
}

printf "\n${_NCO_BOLD}noclickops${_NCO_NC} — portable script suite for developers\n"
printf "Install: %s\n" "$NOCLICKOPS_DIR"

emit_section "Meta"               "$_buf_meta"
emit_section "Git / pull requests" "$_buf_git"
emit_section "Deployment"         "$_buf_deploy"
emit_section "Service lifecycle"  "$_buf_servicelifecycle"
emit_section "Inspect / observe"  "$_buf_inspect"

cat <<EOF

Run 'noclickops <cmd> --help' for usage details, e.g.:
  noclickops update --help
EOF
