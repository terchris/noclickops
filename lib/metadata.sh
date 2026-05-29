#!/usr/bin/env bash
# lib/metadata.sh — parse SCRIPT_* metadata from script files; print --help.
#
# Each bin/ script declares (near the top):
#   Core (used by both --help and the docs site):
#     SCRIPT_NAME="<short name>"
#     SCRIPT_DESCRIPTION="<one line>"
#     SCRIPT_USAGE="<one-line usage form>"
#     SCRIPT_EXAMPLE="<one example>"
#     SCRIPT_CATEGORY="<meta|git|deploy|service-lifecycle|inspect>"
#
#   Extended (used by the docs site at noclickops.sovereignsky.no — render
#   richer per-command pages; ignored by show_help to keep CLI output tight):
#     SCRIPT_TAGS="<space-separated keywords>"
#     SCRIPT_DETAILS="<a paragraph: what this actually does>"
#     SCRIPT_AUTH="<auth prerequisites, one line>"
#     SCRIPT_SEE_ALSO="<space-separated command names>"
#     SCRIPT_DEPENDS_ON="<space-separated CLI names>"
#
#   v1.6.6 also adds a single header helper:
#     nco_command_header "<summary>"   — prints
#       "noclickops <SCRIPT_NAME> v<version> — <summary>"
#     Each bin/<cmd>.sh calls this once after arg-parse + pre-flight,
#     so the header appears only when work is about to happen.
#     SCRIPT_FLAGS=(           # bash array: "flag|description" per row
#       "--watch|Watch the pipeline run to completion"
#       "-h,--help|Show this help and exit"
#     )
#     SCRIPT_EXIT_CODES=(      # bash array: "code|meaning" per row
#       "0|Success"
#       "1|Argument error / target not found / az error"
#     )
#
# show_help reads them from the file (via grep) so -h/--help is uniform
# without each script having to re-print its own help block.

[[ -n "${_NCO_METADATA_LOADED:-}" ]] && return 0
_NCO_METADATA_LOADED=1

_meta_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${_NCO_LOGGING_LOADED:-}" ]] && . "$_meta_dir/logging.sh"
[[ -z "${_NCO_VERSION_LOADED:-}" ]] && . "$_meta_dir/version.sh"
unset _meta_dir

# Valid categories — kept here so the lister and individual scripts agree.
_NCO_VALID_CATEGORIES="meta git deploy service-lifecycle inspect"

# nco_command_header <summary>
# Print the standard command header line:
#   noclickops <SCRIPT_NAME> v<version> — <summary>
#
# Each bin/<cmd>.sh calls this once after arg-parsing (and AFTER any
# --help early-exit), so the header announces "what's about to happen"
# only when the command actually runs.
#
# SCRIPT_NAME must already be set (it's at the top of every bin/ script).
nco_command_header() {
  local summary="${1:-}"
  nco_load_version 2>/dev/null || true
  local ver="${NCO_VERSION:-?.?.?}"
  if [ -n "$summary" ]; then
    printf '\n%snoclickops %s v%s%s — %s\n\n' \
      "${_NCO_BOLD:-}" "${SCRIPT_NAME:-?}" "$ver" "${_NCO_NC:-}" "$summary"
  else
    printf '\n%snoclickops %s v%s%s\n\n' \
      "${_NCO_BOLD:-}" "${SCRIPT_NAME:-?}" "$ver" "${_NCO_NC:-}"
  fi
}

valid_category() {
  local cat="$1"
  for valid in $_NCO_VALID_CATEGORIES; do
    [ "$valid" = "$cat" ] && return 0
  done
  return 1
}

# Extract a single SCRIPT_* field. Strips the outermost matching quote pair
# (single or double) if present — values can embed the other quote style
# (e.g. SCRIPT_USAGE='cmd "arg"') without breaking the parser.
#
# Also unescapes \` → ` so SCRIPT_DETAILS / SCRIPT_AUTH strings that contain
# literal backticks (written as `\`` inside the bash double-quoted source —
# the standard bash escape) render as real markdown inline-code on the
# website. Without this, the website sees `\`` and MDX parses `<word>` next
# to it as a JSX tag instead of code.
_extract_field() {
  local file="$1" field="$2" raw
  raw="$(grep -E "^${field}=" "$file" | head -1 | sed -E "s/^${field}=//")"
  case "$raw" in
    \"*\") raw="${raw#\"}"; raw="${raw%\"}" ;;
    \'*\') raw="${raw#\'}"; raw="${raw%\'}" ;;
  esac
  raw="${raw//\\\`/\`}"
  printf '%s' "$raw"
}

# Extract a multi-line heredoc field. Looks for:
#   SCRIPT_FIELD=$(cat <<'EOF'
#   ... lines ...
#   EOF
#   )
# Emits the body verbatim, preserving newlines. Returns empty if the field
# isn't present in heredoc form (single-line values use _extract_field).
_extract_heredoc_field() {
  local file="$1" field="$2"
  # Look for the canonical form: SCRIPT_FIELD=$(cat <<'EOF' ... EOF\n)
  # POSIX awk (no gawk extensions): use sub() to strip + a fixed EOF marker.
  awk -v field="$field" '
    BEGIN { capturing = 0; marker = "" }
    capturing {
      if ($0 == marker) { exit }
      print
      next
    }
    {
      start_pattern = "^" field "=\\$\\(cat <<'\''"
      if ($0 ~ start_pattern) {
        # Extract the marker between single quotes after <<.
        # Strip everything up to and including the opening quote.
        line = $0
        sub(start_pattern, "", line)
        # Now `line` starts with the marker followed by a closing quote.
        sub("'\''.*$", "", line)
        marker = line
        capturing = 1
      }
    }
  ' "$file" 2>/dev/null
}

# Extract a bash array field. Emits each element on its own line so callers
# can iterate via `while read -r line`. Comments and blank lines stripped.
# Surrounding quotes (single OR double) stripped from each element.
_extract_array_field() {
  local file="$1" field="$2"
  awk -v arr="$field" '
    $0 ~ "^" arr "=\\(" {
      capturing = 1
      sub("^" arr "=\\(", "")
      if (/\)$/) { sub(/\)$/, ""); if (length($0)) print; capturing = 0; next }
      if (length($0)) print
      next
    }
    capturing {
      if (/^[[:space:]]*\)/) { capturing = 0; next }
      if (/\)[[:space:]]*$/) { sub(/\)[[:space:]]*$/, ""); if (length($0)) print; capturing = 0; next }
      print
    }
  ' "$file" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -v '^$' \
    | grep -v '^#' \
    | sed -E 's/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/' \
    | sed -e 's/\\`/`/g'
}

# Parse SCRIPT_* fields from a script file.
# Sets globals:
#   Core:     parsed_name, parsed_description, parsed_usage, parsed_example,
#             parsed_category.
#   Extended: parsed_tags, parsed_details, parsed_auth, parsed_see_also,
#             parsed_depends_on (scalars; empty string if missing).
#   Arrays:   parsed_flags, parsed_exit_codes (newline-separated strings —
#             one row per line, "<key>|<value>" format; empty string if
#             missing).
parse_metadata() {
  local file="$1"
  [ -f "$file" ] || { log_error "metadata: file not found: $file"; return 1; }

  parsed_name="$(_extract_field "$file" SCRIPT_NAME)"
  parsed_description="$(_extract_field "$file" SCRIPT_DESCRIPTION)"
  parsed_usage="$(_extract_field "$file" SCRIPT_USAGE)"
  parsed_example="$(_extract_field "$file" SCRIPT_EXAMPLE)"
  parsed_category="$(_extract_field "$file" SCRIPT_CATEGORY)"

  parsed_tags="$(_extract_field "$file" SCRIPT_TAGS)"
  parsed_details="$(_extract_field "$file" SCRIPT_DETAILS)"
  parsed_auth="$(_extract_field "$file" SCRIPT_AUTH)"
  parsed_see_also="$(_extract_field "$file" SCRIPT_SEE_ALSO)"
  parsed_depends_on="$(_extract_field "$file" SCRIPT_DEPENDS_ON)"
  parsed_flags="$(_extract_array_field "$file" SCRIPT_FLAGS)"
  parsed_exit_codes="$(_extract_array_field "$file" SCRIPT_EXIT_CODES)"
  parsed_example_output="$(_extract_heredoc_field "$file" SCRIPT_EXAMPLE_OUTPUT)"
}

# Print --help for the given script based on its metadata.
show_help() {
  local file="$1"
  parse_metadata "$file" || return 1
  nco_load_version 2>/dev/null || true   # populates $NCO_VERSION; tolerant if version.txt missing

  printf 'noclickops v%s — %s\n\n' "${NCO_VERSION:-unknown}" "${parsed_name}"
  printf '%s\n\n' "${parsed_description}"

  # Optional long-form "what this actually does" paragraph.
  if [ -n "${parsed_details:-}" ]; then
    printf '%s\n\n' "$parsed_details"
  fi

  # Category badge + Tags inline.
  printf 'Category: %s\n' "$parsed_category"
  if [ -n "${parsed_tags:-}" ]; then
    printf 'Tags: %s\n' "$parsed_tags"
  fi
  printf '\n'

  printf 'Usage:\n  %s\n\n' "$parsed_usage"

  # Flags table (sourced from SCRIPT_FLAGS — each script's array includes
  # -h, --help, so no need to hardcode it here).
  if [ -n "${parsed_flags:-}" ]; then
    printf 'Flags:\n'
    while IFS='|' read -r _flag _flag_desc; do
      [ -z "$_flag" ] && continue
      printf '  %-22s %s\n' "$_flag" "$_flag_desc"
    done <<< "$parsed_flags"
    printf '\n'
  fi

  printf 'Example:\n  %s\n\n' "$parsed_example"

  if [ -n "${parsed_example_output:-}" ]; then
    printf 'Example output:\n'
    while IFS= read -r _line; do
      printf '  %s\n' "$_line"
    done <<< "$parsed_example_output"
    printf '\n'
  fi

  if [ -n "${parsed_auth:-}" ]; then
    printf 'Auth:\n  %s\n\n' "$parsed_auth"
  fi

  if [ -n "${parsed_depends_on:-}" ]; then
    printf 'Depends on:\n  %s\n\n' "$parsed_depends_on"
  fi

  if [ -n "${parsed_exit_codes:-}" ]; then
    printf 'Exit codes:\n'
    while IFS='|' read -r _code _meaning; do
      [ -z "$_code" ] && continue
      printf '  %-4s %s\n' "$_code" "$_meaning"
    done <<< "$parsed_exit_codes"
    printf '\n'
  fi

  if [ -n "${parsed_see_also:-}" ]; then
    printf 'See also:\n  %s\n' "$parsed_see_also"
  fi
}
