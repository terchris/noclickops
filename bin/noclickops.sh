#!/usr/bin/env bash
# bin/noclickops.sh — list all noclickops commands (PLAN-001 stub).
#
# PLAN-001 ships a flat listing. PLAN-002 replaces this stub with
# category-grouped output and full first-run UX.
#
# --- noclickops metadata ---
SCRIPT_NAME="noclickops"
SCRIPT_DESCRIPTION="List all noclickops commands and their descriptions."
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

printf "\n${_NCO_BOLD}noclickops${_NCO_NC} — portable script suite for developers\n"
printf "Install: %s\n\n" "$NOCLICKOPS_DIR"
printf "Available commands:\n\n"

for script in "$BIN_DIR"/*.sh; do
  [ -f "$script" ] || continue
  cmd_name="$(basename "$script" .sh)"
  parse_metadata "$script" 2>/dev/null || continue
  printf "  %-15s %s\n" "$cmd_name" "${parsed_description:-(no description)}"
done

cat <<EOF

Run with --help on any command for usage details, e.g.:
  $BIN_DIR/update.sh --help

NOTE: PLAN-001 ships this foundation. PLAN-002 adds:
  - one-line install
  - typeable 'noclickops <subcommand>' form via shell function
  - category-grouped listing
EOF
