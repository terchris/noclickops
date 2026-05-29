#!/usr/bin/env bash
# scripts/generate-docs.sh — generate the docs site's metadata-driven files.
#
# Walks bin/*.sh, extracts SCRIPT_* metadata via lib/metadata.sh, and writes:
#   - website/src/data/commands.json     (one row per command)
#   - website/src/data/categories.json   (one row per category)
#   - website/docs/commands.mdx          (per-command reference page)
#   - website/docs/index.md              (README.md with frontmatter + link rewrites)
#
# Modelled on DCT's dev-docs.sh::generate_commands_md() (much slimmer — only
# 12 commands here vs DCT's ~50 tools, so we skip per-item pages and the
# package-array machinery).
#
# Internal repo tooling — Bash-only, no PowerShell sibling. The portability
# guard (tests/test-portability.sh) only scans bin|lib|templates|shell, so
# scripts/ is intentionally out of that surface.
#
# Run before `npm start` / `npm run build`:
#   bash scripts/generate-docs.sh
#
# CI runs this automatically (see .github/workflows/deploy-docs.yml).

set -euo pipefail

# Paths
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_dir/.." && pwd)"
BIN_DIR="$REPO_ROOT/bin"
LIB_DIR="$REPO_ROOT/lib"
WEBSITE_DIR="$REPO_ROOT/website"
DOCS_DIR="$WEBSITE_DIR/docs"
DATA_DIR="$WEBSITE_DIR/src/data"

# Fork-friendliness: same env vars as docusaurus.config.ts.
GITHUB_ORG="${GITHUB_ORG:-terchris}"
GITHUB_REPO="${GITHUB_REPO:-noclickops}"

# shellcheck source=../lib/logging.sh
. "$LIB_DIR/logging.sh"
# shellcheck source=../lib/metadata.sh
. "$LIB_DIR/metadata.sh"

# Canonical category display labels — mirror bin/noclickops.sh lines 90-94.
# Format: id|label|description
_CATEGORY_DEFS="\
meta|Meta|Discovery and self-management — the lister and update commands.
git|Git / pull requests|Open and merge Azure DevOps pull requests from the current branch.
deploy|Deployment|Trigger CD pipelines for one service / environment.
service-lifecycle|Service lifecycle|Scaffold, swap in content, clean placeholders.
inspect|Inspect / observe|Live config, logs, and shells against a running service."

# ──────────────────────────────────────────────────────────────────────────
# Helpers

# Map category id → display label. Echoes the label or empty if not found.
category_label() {
  local id="$1" line
  while IFS='|' read -r cid label _desc; do
    [ "$cid" = "$id" ] && { printf '%s' "$label"; return 0; }
  done <<< "$_CATEGORY_DEFS"
  return 1
}

# Map category id → description.
category_description() {
  local id="$1"
  while IFS='|' read -r cid _label desc; do
    [ "$cid" = "$id" ] && { printf '%s' "$desc"; return 0; }
  done <<< "$_CATEGORY_DEFS"
  return 1
}

# Run `bash <script> --help` and capture stdout+stderr. ANSI-escape-stripped.
script_help_output() {
  local script="$1"
  bash "$script" --help 2>&1 \
    | sed 's/\x1b\[[0-9;]*m//g' \
    || true  # don't die if --help itself exits non-zero
}

# Anchor slug for a category. Mimics Docusaurus's github-slugger so links
# resolve to the H2 auto-anchor. Steps: lowercase, spaces → hyphens, drop
# everything that isn't alphanumeric or hyphen. The slash in "Git / pull
# requests" becomes nothing (dropped), so the surrounding spaces produce
# adjacent hyphens — "git--pull-requests" (double dash, intentional, matches
# Docusaurus's output). Same logic as CommandCategoryCard.anchorFor() in TS.
category_anchor() {
  local label="$1"
  printf '%s' "$label" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/ /-/g; s/[^a-z0-9-]//g'
}

# ──────────────────────────────────────────────────────────────────────────
# Pass 1: parse every bin/*.sh, accumulate flat records.
# Stored in parallel arrays indexed 0..N-1.

declare -a CMD_NAMES CMD_DESCS CMD_USAGES CMD_EXAMPLES CMD_CATS CMD_FILES \
           CMD_TAGS CMD_DETAILS CMD_AUTH CMD_SEE_ALSO CMD_DEPENDS_ON \
           CMD_FLAGS CMD_EXIT_CODES CMD_EXAMPLE_OUTPUTS

parse_all_commands() {
  log_info "Parsing bin/*.sh metadata..."
  local script
  for script in "$BIN_DIR"/*.sh; do
    [ -f "$script" ] || continue
    # Reset parsed_* globals so leftovers from prior iteration don't bleed in.
    # (No subshell isolation — array fields contain embedded newlines that the
    # previous printf/IFS-read pattern couldn't carry across the subshell boundary.)
    parsed_name=""; parsed_description=""; parsed_usage=""; parsed_example=""
    parsed_category=""; parsed_tags=""; parsed_details=""; parsed_auth=""
    parsed_see_also=""; parsed_depends_on=""; parsed_flags=""; parsed_exit_codes=""
    parsed_example_output=""

    parse_metadata "$script" >/dev/null || continue

    CMD_NAMES+=("$parsed_name")
    CMD_DESCS+=("$parsed_description")
    CMD_USAGES+=("$parsed_usage")
    CMD_EXAMPLES+=("$parsed_example")
    CMD_CATS+=("$parsed_category")
    CMD_FILES+=("$script")
    CMD_TAGS+=("$parsed_tags")
    CMD_DETAILS+=("$parsed_details")
    CMD_AUTH+=("$parsed_auth")
    CMD_SEE_ALSO+=("$parsed_see_also")
    CMD_DEPENDS_ON+=("$parsed_depends_on")
    CMD_FLAGS+=("$parsed_flags")
    CMD_EXIT_CODES+=("$parsed_exit_codes")
    CMD_EXAMPLE_OUTPUTS+=("$parsed_example_output")
  done
  log_info "  Parsed ${#CMD_NAMES[@]} commands."
}

# ──────────────────────────────────────────────────────────────────────────
# Emit website/src/data/commands.json

emit_commands_json() {
  log_info "Writing $DATA_DIR/commands.json..."
  mkdir -p "$DATA_DIR"
  local i
  local out="["
  for i in "${!CMD_NAMES[@]}"; do
    [ $i -gt 0 ] && out+=","
    # Build arrays for flags/exit-codes/see-also/depends-on so JSON consumers
    # (React components) can iterate cleanly without re-splitting strings.
    local flags_json exit_json see_also_json depends_json tags_json
    flags_json="$(_lines_to_json_kv "${CMD_FLAGS[$i]}")"
    exit_json="$(_lines_to_json_kv "${CMD_EXIT_CODES[$i]}")"
    see_also_json="$(_space_to_json_array "${CMD_SEE_ALSO[$i]}")"
    depends_json="$(_space_to_json_array "${CMD_DEPENDS_ON[$i]}")"
    tags_json="$(_space_to_json_array "${CMD_TAGS[$i]}")"

    out+=$(jq -n \
      --arg name        "${CMD_NAMES[$i]}" \
      --arg description "${CMD_DESCS[$i]}" \
      --arg usage       "${CMD_USAGES[$i]}" \
      --arg example     "${CMD_EXAMPLES[$i]}" \
      --arg category    "${CMD_CATS[$i]}" \
      --arg details     "${CMD_DETAILS[$i]}" \
      --arg auth        "${CMD_AUTH[$i]}" \
      --argjson tags      "$tags_json" \
      --argjson seeAlso   "$see_also_json" \
      --argjson dependsOn "$depends_json" \
      --argjson flags     "$flags_json" \
      --argjson exitCodes "$exit_json" \
      '{name:$name, description:$description, category:$category, tags:$tags,
        details:$details, usage:$usage, example:$example, auth:$auth,
        dependsOn:$dependsOn, flags:$flags, exitCodes:$exitCodes,
        seeAlso:$seeAlso}')
  done
  out+="]"
  printf '%s\n' "$out" | jq '.' > "$DATA_DIR/commands.json"
  log_info "  Wrote ${#CMD_NAMES[@]} command rows."
}

# Helper: convert space-separated string → JSON array of strings.
_space_to_json_array() {
  local s="$1"
  if [ -z "$s" ]; then printf '[]'; return; fi
  printf '%s' "$s" | tr -s ' ' '\n' | jq -R . | jq -s .
}

# Helper: convert newline-separated "key|value" lines → JSON array of {key, value}.
_lines_to_json_kv() {
  local s="$1"
  if [ -z "$s" ]; then printf '[]'; return; fi
  printf '%s\n' "$s" \
    | grep -v '^$' \
    | jq -R 'split("|") | {key: .[0], value: (.[1:] | join("|"))}' \
    | jq -s .
}

# Emit website/src/data/categories.json
emit_categories_json() {
  log_info "Writing $DATA_DIR/categories.json..."
  mkdir -p "$DATA_DIR"
  local out="["
  local first=1 cid label desc count
  while IFS='|' read -r cid label desc; do
    count=0
    local c
    for c in "${CMD_CATS[@]}"; do
      [ "$c" = "$cid" ] && count=$((count + 1))
    done
    [ $first -eq 1 ] && first=0 || out+=","
    out+=$(jq -n \
      --arg id "$cid" \
      --arg label "$label" \
      --arg description "$desc" \
      --argjson count "$count" \
      '{id: $id, label: $label, description: $description, count: $count}')
  done <<< "$_CATEGORY_DEFS"
  out+="]"
  printf '%s\n' "$out" | jq '.' > "$DATA_DIR/categories.json"
  log_info "  Wrote 5 category rows."
}

# ──────────────────────────────────────────────────────────────────────────
# Emit website/docs/commands/ — one landing page + one page per command.
#
# Layout:
#   docs/commands/index.mdx     → /docs/commands (landing: CategoryGrid + lists)
#   docs/commands/<name>.mdx    → /docs/commands/<name> (per-command reference)
#   docs/commands/_category_.json (sidebar label for the auto-generated section)

emit_commands_category_json() {
  # No-op now that the sidebar for /docs/commands is built manually in
  # sidebars.ts (see "Commands" section there). The Docusaurus auto-sidebar
  # ignores docs/commands/ entirely because sidebars.ts excludes it.
  return 0
}

emit_commands_landing() {
  local out="$DOCS_DIR/commands/index.mdx"
  log_info "Writing $out..."
  mkdir -p "$DOCS_DIR/commands"

  {
    cat <<'EOF'
---
title: Commands
sidebar_label: Overview
sidebar_position: 0
---

import CommandCategoryGrid from '@site/src/components/CommandCategoryGrid';

# Commands

Every noclickops command, grouped by category. Click a category card to jump to its section, or open a command for its full reference.

<CommandCategoryGrid />

EOF

    # One H2 per category, with bullet list of command links.
    # Links are FLAT: ./<cmd-name>. Grouping is done by sidebars.ts at build time.
    local cid label desc
    while IFS='|' read -r cid label desc; do
      local has=0 i
      for i in "${!CMD_CATS[@]}"; do
        [ "${CMD_CATS[$i]}" = "$cid" ] && has=1 && break
      done
      [ "$has" = 0 ] && continue

      printf '## %s\n\n' "$label"
      printf '%s\n\n' "$desc"

      for i in "${!CMD_CATS[@]}"; do
        [ "${CMD_CATS[$i]}" = "$cid" ] || continue
        local name="${CMD_NAMES[$i]}" cmd_desc="${CMD_DESCS[$i]}"
        printf -- '- [`%s`](./%s) — %s\n' "$name" "$name" "$cmd_desc"
      done
      printf '\n'
    done <<< "$_CATEGORY_DEFS"
  } > "$out"

  log_info "  Wrote $(wc -l < "$out") lines."
}

emit_command_pages() {
  log_info "Writing per-command pages to $DOCS_DIR/commands/..."
  mkdir -p "$DOCS_DIR/commands"

  local i count=0
  for i in "${!CMD_NAMES[@]}"; do
    local name="${CMD_NAMES[$i]}" \
          cmd_desc="${CMD_DESCS[$i]}" \
          cmd_usage="${CMD_USAGES[$i]}" \
          cmd_example="${CMD_EXAMPLES[$i]}" \
          cat_id="${CMD_CATS[$i]}" \
          tags="${CMD_TAGS[$i]}" \
          details="${CMD_DETAILS[$i]}" \
          auth="${CMD_AUTH[$i]}" \
          see_also="${CMD_SEE_ALSO[$i]}" \
          depends_on="${CMD_DEPENDS_ON[$i]}" \
          flags="${CMD_FLAGS[$i]}" \
          exit_codes="${CMD_EXIT_CODES[$i]}" \
          example_output="${CMD_EXAMPLE_OUTPUTS[$i]}" \
          file="${CMD_FILES[$i]}"
    local cat_label
    cat_label="$(category_label "$cat_id")"
    local help
    help="$(script_help_output "$file")"
    local page="$DOCS_DIR/commands/$name.mdx"

    {
      # Frontmatter + H1 + one-line description.
      cat <<EOF
---
title: $name
sidebar_label: $name
description: $cmd_desc
---

# \`$name\`

$cmd_desc
EOF

      # Optional long-form details paragraph. Escape bare `<word>` patterns
      # so MDX doesn't try to parse placeholder text like `<svc>` as a JSX tag.
      if [ -n "$details" ]; then
        local details_safe
        details_safe=$(printf '%s' "$details" | sed -E 's/<([A-Za-z][A-Za-z0-9_-]*)>/\&lt;\1\&gt;/g')
        printf '\n%s\n' "$details_safe"
      fi

      # Category + tags badge row.
      printf '\n**Category:** [%s](./#%s)' "$cat_label" "$(category_anchor "$cat_label")"
      if [ -n "$tags" ]; then
        local tag tag_html=""
        for tag in $tags; do
          tag_html+=" \`$tag\`"
        done
        printf '  \n**Tags:**%s' "$tag_html"
      fi
      printf '\n\n'

      # Usage.
      printf '## Usage\n\n```bash\n%s\n```\n\n' "$cmd_usage"

      # Flags table (optional).
      if [ -n "$flags" ]; then
        printf '## Flags\n\n| Flag | Description |\n|---|---|\n'
        while IFS='|' read -r flag flag_desc; do
          [ -n "$flag" ] || continue
          # MDX-safe: backtick bare angle-bracket placeholders in the description.
          flag_desc=$(printf '%s' "$flag_desc" | sed -E 's/<([A-Za-z][A-Za-z0-9_-]*)>/\&lt;\1\&gt;/g')
          printf '| `%s` | %s |\n' "$flag" "$flag_desc"
        done <<< "$flags"
        printf '\n'
      fi

      # Example.
      printf '## Example\n\n```bash\n%s\n```\n\n' "$cmd_example"

      # Example output (optional — captured during smoke tests, redacted via
      # terchris/redaction-map.md). Rendered as fenced text so the page shows
      # the user what a successful run actually looks like.
      if [ -n "$example_output" ]; then
        printf '## Example output\n\n```text\n%s\n```\n\n' "$example_output"
      fi

      # Auth (optional). Same MDX-safe placeholder escape.
      if [ -n "$auth" ]; then
        local auth_safe
        auth_safe=$(printf '%s' "$auth" | sed -E 's/<([A-Za-z][A-Za-z0-9_-]*)>/\&lt;\1\&gt;/g')
        printf '## Auth\n\n%s\n\n' "$auth_safe"
      fi

      # Depends on (optional).
      if [ -n "$depends_on" ]; then
        printf '## Depends on\n\n'
        local dep
        for dep in $depends_on; do
          printf -- '- `%s`\n' "$dep"
        done
        printf '\n'
      fi

      # Exit codes table (optional).
      if [ -n "$exit_codes" ]; then
        printf '## Exit codes\n\n| Code | Meaning |\n|---|---|\n'
        while IFS='|' read -r code meaning; do
          [ -n "$code" ] || continue
          meaning=$(printf '%s' "$meaning" | sed -E 's/<([A-Za-z][A-Za-z0-9_-]*)>/\&lt;\1\&gt;/g')
          printf '| `%s` | %s |\n' "$code" "$meaning"
        done <<< "$exit_codes"
        printf '\n'
      fi

      # See also (optional).
      if [ -n "$see_also" ]; then
        printf '## See also\n\n'
        local other
        for other in $see_also; do
          printf -- '- [`%s`](./%s)\n' "$other" "$other"
        done
        printf '\n'
      fi

      # Full --help collapsible.
      printf '## Full `--help` output\n\n<details>\n<summary>Show full --help</summary>\n\n```text\n%s\n```\n\n</details>\n' "$help"

    } > "$page"
    count=$((count + 1))
  done

  log_info "  Wrote $count per-command pages."
}

# ──────────────────────────────────────────────────────────────────────────
# Emit website/docs/index.md (rewritten README.md)

emit_index_md() {
  local readme="$REPO_ROOT/README.md"
  local out="$DOCS_DIR/index.md"
  log_info "Writing $out from README.md..."

  local gh_base="https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/blob/main"

  {
    cat <<EOF
---
title: noclickops
slug: /
sidebar_position: 1
---

EOF
    # Pipeline of in-place link rewrites. Order matters — broader patterns last.
    sed \
      -e "s#\](CLAUDE.md)#](${gh_base}/CLAUDE.md)#g" \
      -e "s#\](AGENTS.md)#](${gh_base}/AGENTS.md)#g" \
      -e "s#\](LICENSE)#](${gh_base}/LICENSE)#g" \
      -e "s#\](website/docs/ai-developer/#](/docs/ai-developer/#g" \
      "$readme"
  } > "$out"

  log_info "  Wrote $(wc -l < "$out") lines."
}

# ──────────────────────────────────────────────────────────────────────────
# Smoke checks

smoke_checks() {
  log_info "Running smoke checks..."
  local errors=0

  # 1. Count match — bin/*.sh vs commands.json vs per-command pages.
  local bin_count="${#CMD_NAMES[@]}"
  local json_count page_count
  json_count=$(jq 'length' "$DATA_DIR/commands.json")
  # Per-command pages live alongside index.mdx in the same folder (flat).
  page_count=$(find "$DOCS_DIR/commands" -maxdepth 1 -name '*.mdx' ! -name 'index.mdx' | wc -l | tr -d ' ')
  if [ "$bin_count" != "$json_count" ]; then
    log_error "  count mismatch: bin/=$bin_count, commands.json=$json_count"
    errors=$((errors + 1))
  fi
  if [ "$bin_count" != "$page_count" ]; then
    log_error "  count mismatch: bin/=$bin_count, per-command pages=$page_count"
    errors=$((errors + 1))
  fi

  # 2. README link rewriter coverage.
  if grep -E '\]\(website/' "$DOCS_DIR/index.md" >/dev/null 2>&1; then
    log_error "  index.md still has ](website/...) links — rewriter missed something:"
    grep -nE '\]\(website/' "$DOCS_DIR/index.md" >&2
    errors=$((errors + 1))
  fi

  # 3. Every category in CMD_CATS is in _NCO_VALID_CATEGORIES.
  local cat
  for cat in "${CMD_CATS[@]}"; do
    if ! valid_category "$cat"; then
      log_error "  invalid SCRIPT_CATEGORY value: '$cat'"
      errors=$((errors + 1))
    fi
  done

  if [ "$errors" -gt 0 ]; then
    log_error "$errors smoke check(s) failed."
    return 1
  fi
  log_info "  All smoke checks passed."
}

# ──────────────────────────────────────────────────────────────────────────
# Main

main() {
  command -v jq >/dev/null || die "jq is required (install: brew install jq / apt-get install jq)"

  parse_all_commands
  emit_commands_json
  emit_categories_json
  emit_commands_category_json
  emit_commands_landing
  emit_command_pages
  emit_index_md
  smoke_checks
  log_info "Done."
}

main "$@"
