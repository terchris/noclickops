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

# Anchor slug for a category. Matches Docusaurus's auto-anchor for H2 headings
# (lowercased, spaces+slashes → hyphens, drop other punctuation).
category_anchor() {
  local label="$1"
  printf '%s' "$label" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/ \/ /-/g; s/ /-/g; s/[^a-z0-9-]//g'
}

# ──────────────────────────────────────────────────────────────────────────
# Pass 1: parse every bin/*.sh, accumulate flat records.
# Stored in parallel arrays indexed 0..N-1.

declare -a CMD_NAMES CMD_DESCS CMD_USAGES CMD_EXAMPLES CMD_CATS CMD_FILES

parse_all_commands() {
  log_info "Parsing bin/*.sh metadata..."
  local script
  for script in "$BIN_DIR"/*.sh; do
    [ -f "$script" ] || continue
    # Subshell isolates parse_metadata's globals between iterations.
    local row
    row=$(
      parse_metadata "$script" >/dev/null
      # tab-separated: name\tdesc\tusage\texample\tcategory
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$parsed_name" \
        "$parsed_description" \
        "$parsed_usage" \
        "$parsed_example" \
        "$parsed_category"
    )
    IFS=$'\t' read -r name desc usage example cat <<< "$row"
    CMD_NAMES+=("$name")
    CMD_DESCS+=("$desc")
    CMD_USAGES+=("$usage")
    CMD_EXAMPLES+=("$example")
    CMD_CATS+=("$cat")
    CMD_FILES+=("$script")
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
    out+=$(jq -n \
      --arg name "${CMD_NAMES[$i]}" \
      --arg description "${CMD_DESCS[$i]}" \
      --arg usage "${CMD_USAGES[$i]}" \
      --arg example "${CMD_EXAMPLES[$i]}" \
      --arg category "${CMD_CATS[$i]}" \
      '{name: $name, description: $description, usage: $usage, example: $example, category: $category}')
  done
  out+="]"
  printf '%s\n' "$out" | jq '.' > "$DATA_DIR/commands.json"
  log_info "  Wrote ${#CMD_NAMES[@]} command rows."
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
# Emit website/docs/commands.mdx

emit_commands_mdx() {
  local out="$DOCS_DIR/commands.mdx"
  log_info "Writing $out..."
  mkdir -p "$DOCS_DIR"

  {
    cat <<'EOF'
---
title: Commands
sidebar_position: 2
---

import CommandCategoryGrid from '@site/src/components/CommandCategoryGrid';

# Commands

Every noclickops command, grouped by category. Click a category card to jump to its section, or scan the full reference below.

<CommandCategoryGrid />

EOF

    # One H2 per category, in canonical order.
    local cid label desc
    while IFS='|' read -r cid label desc; do
      # Skip empty categories (defensive).
      local has=0 i
      for i in "${!CMD_CATS[@]}"; do
        [ "${CMD_CATS[$i]}" = "$cid" ] && has=1 && break
      done
      [ "$has" = 0 ] && continue

      printf '## %s\n\n' "$label"
      printf '%s\n\n' "$desc"

      for i in "${!CMD_CATS[@]}"; do
        [ "${CMD_CATS[$i]}" = "$cid" ] || continue
        local name="${CMD_NAMES[$i]}" \
              cmd_desc="${CMD_DESCS[$i]}" \
              cmd_usage="${CMD_USAGES[$i]}" \
              cmd_example="${CMD_EXAMPLES[$i]}" \
              file="${CMD_FILES[$i]}"

        printf '### %s\n\n' "$name"
        printf '%s\n\n' "$cmd_desc"
        printf '**Usage:**\n\n```bash\n%s\n```\n\n' "$cmd_usage"
        printf '**Example:**\n\n```bash\n%s\n```\n\n' "$cmd_example"

        # Collapsible --help block.
        local help
        help="$(script_help_output "$file")"
        printf '<details>\n<summary>Full --help</summary>\n\n```text\n%s\n```\n\n</details>\n\n' "$help"
      done
    done <<< "$_CATEGORY_DEFS"
  } > "$out"

  log_info "  Wrote $(wc -l < "$out") lines."
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

  # 1. Count match.
  local bin_count="${#CMD_NAMES[@]}"
  local json_count
  json_count=$(jq 'length' "$DATA_DIR/commands.json")
  if [ "$bin_count" != "$json_count" ]; then
    log_error "  count mismatch: bin/=$bin_count, commands.json=$json_count"
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
  emit_commands_mdx
  emit_index_md
  smoke_checks
  log_info "Done. Generated 4 files."
}

main "$@"
