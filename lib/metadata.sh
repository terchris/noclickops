#!/usr/bin/env bash
# lib/metadata.sh — parse SCRIPT_* metadata from script files; print --help.
#
# Each bin/ script declares (near the top):
#   SCRIPT_NAME="<short name>"
#   SCRIPT_DESCRIPTION="<one line>"
#   SCRIPT_USAGE="<one-line usage form>"
#   SCRIPT_EXAMPLE="<one example>"
#   SCRIPT_CATEGORY="<meta|git|deploy|service-lifecycle|inspect>"
#
# show_help reads them from the file (via grep) so -h/--help is uniform
# without each script having to re-print its own help block.

[[ -n "${_NCO_METADATA_LOADED:-}" ]] && return 0
_NCO_METADATA_LOADED=1

_meta_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${_NCO_LOGGING_LOADED:-}" ]] && . "$_meta_dir/logging.sh"
unset _meta_dir

# Valid categories — kept here so the lister and individual scripts agree.
_NCO_VALID_CATEGORIES="meta git deploy service-lifecycle inspect"

valid_category() {
  local cat="$1"
  for valid in $_NCO_VALID_CATEGORIES; do
    [ "$valid" = "$cat" ] && return 0
  done
  return 1
}

# Parse SCRIPT_* fields from a script file.
# Sets: parsed_name, parsed_description, parsed_usage, parsed_example, parsed_category.
parse_metadata() {
  local file="$1"
  [ -f "$file" ] || { log_error "metadata: file not found: $file"; return 1; }

  # shellcheck disable=SC2155
  parsed_name="$(grep -E '^SCRIPT_NAME=' "$file" | head -1 | sed -E 's/^SCRIPT_NAME="?([^"]*)"?.*$/\1/')"
  parsed_description="$(grep -E '^SCRIPT_DESCRIPTION=' "$file" | head -1 | sed -E 's/^SCRIPT_DESCRIPTION="?([^"]*)"?.*$/\1/')"
  parsed_usage="$(grep -E '^SCRIPT_USAGE=' "$file" | head -1 | sed -E 's/^SCRIPT_USAGE="?([^"]*)"?.*$/\1/')"
  parsed_example="$(grep -E '^SCRIPT_EXAMPLE=' "$file" | head -1 | sed -E 's/^SCRIPT_EXAMPLE="?([^"]*)"?.*$/\1/')"
  parsed_category="$(grep -E '^SCRIPT_CATEGORY=' "$file" | head -1 | sed -E 's/^SCRIPT_CATEGORY="?([^"]*)"?.*$/\1/')"
}

# Print --help for the given script based on its metadata.
show_help() {
  local file="$1"
  parse_metadata "$file" || return 1
  cat <<EOF
${parsed_name} — ${parsed_description}

Usage:
  ${parsed_usage}

Example:
  ${parsed_example}

Category: ${parsed_category}
Flags:
  -h, --help    Show this help and exit.
EOF
}
