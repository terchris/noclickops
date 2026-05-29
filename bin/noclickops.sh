#!/usr/bin/env bash
# bin/noclickops.sh — dispatcher AND lister.
#
# Two modes:
#   noclickops                    → list all available commands (lister)
#   noclickops <cmd> [args...]    → exec bin/<cmd>.sh with the remaining args
#   noclickops -h | --help        → show this script's metadata help
#
# A sibling `bin/noclickops` symlink (no .sh) points here, so PATH-resolved
# invocation (with `~/.noclickops/bin` in PATH — install.sh wires that in)
# works from any shell context, interactive or not. The legacy
# shell-function-based dispatcher in `shell/init.sh` is kept for installs
# that already source it from rc; new installs use PATH only.
#
# --- noclickops metadata ---
SCRIPT_NAME="noclickops"
SCRIPT_DESCRIPTION="List all noclickops commands, or dispatch to a subcommand."
SCRIPT_USAGE="noclickops [<subcommand> [args...]]"
SCRIPT_EXAMPLE="noclickops merge-pr 4810"
SCRIPT_CATEGORY="meta"
SCRIPT_TAGS="lister dispatcher discovery inventory"
SCRIPT_DETAILS="Without arguments, prints every available noclickops command grouped by category, with the current install version and a hint when a newer release is on GitHub. With a subcommand and arguments, execs the matching \`bin/<cmd>.sh\` so signals (Ctrl-C) reach the subcommand directly."
SCRIPT_AUTH="None (local lister); subcommands have their own auth requirements."
SCRIPT_DEPENDS_ON="bash"
SCRIPT_SEE_ALSO="update"
SCRIPT_FLAGS=(
  "-h, --help|Show this help and exit."
)
SCRIPT_EXIT_CODES=(
  "0|Success — listed or dispatched."
  "1|Unknown subcommand (the named \`bin/<cmd>.sh\` doesn't exist)."
)
# --- end metadata ---

set -euo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_dir/../lib/logging.sh"
. "$_dir/../lib/paths.sh"
. "$_dir/../lib/metadata.sh"
. "$_dir/../lib/version.sh"
unset _dir

# --- arg handling ---
# --help wins. Then if a subcommand was given, dispatch. Otherwise fall
# through to lister mode.

case "${1:-}" in
  -h|--help) show_help "$0"; exit 0 ;;
esac

if [ "${1:-}" != "" ]; then
  cmd="$1"
  shift
  script="$BIN_DIR/$cmd.sh"
  if [ ! -x "$script" ]; then
    log_error "no such command '$cmd' (try: noclickops)"
    exit 1
  fi
  # exec so signals (Ctrl-C, SIGTERM) reach the subcommand directly without
  # bash trapping them — important for --follow and interactive shell.
  exec "$script" "$@"
fi

# --- lister mode (no subcommand given) ---

nco_load_version
nco_check_remote   # silently no-ops on cache miss + network failure

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

printf "\n${_NCO_BOLD}noclickops${_NCO_NC} v%s — portable script suite for developers\n" "$NCO_VERSION"
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

nco_show_update_hint
