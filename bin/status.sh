#!/usr/bin/env bash
# bin/status.sh — show the status of an Azure DevOps pipeline run, OR list
# recent runs in the current target repo's pipelines.
#
# Two modes:
#   noclickops status                  → list recent runs in the target repo
#   noclickops status <run-id>         → show details for one run
#
# Designed for the fire-and-forget pattern in `noclickops add-service`
# (PLAN-007a) where the pipeline takes ~1h. The list mode (v1.2.0) lets
# you discover run ids without needing to remember them.
#
# --- noclickops metadata ---
SCRIPT_NAME="status"
SCRIPT_DESCRIPTION="List recent pipeline runs, or show details for one run id."
SCRIPT_USAGE="noclickops status [<run-id>]"
SCRIPT_EXAMPLE="noclickops status"
SCRIPT_CATEGORY="inspect"
SCRIPT_TAGS="pipeline-run azure-devops watch poll list"
SCRIPT_DETAILS="Without arguments, lists the 20 most recent pipeline runs in the target repo (id, name, status, result, time). With a run id, shows that one run's status, the queue/start/finish times, and the URL. Designed for the fire-and-forget pattern in add-service (PLAN-007a) where the pipeline takes ~1 hour — the list mode lets you discover run ids without remembering them."
SCRIPT_AUTH="az login to the target's ADO tenant."
SCRIPT_DEPENDS_ON="az git"
SCRIPT_SEE_ALSO="deploy add-service"
SCRIPT_FLAGS=(
  "-h, --help|Show this help and exit."
)
SCRIPT_EXIT_CODES=(
  "0|Status or list shown."
  "1|Run id not found, not in target repo, or az error."
)
# --- end metadata ---

set -euo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_dir/../lib/logging.sh"
. "$_dir/../lib/utilities.sh"
. "$_dir/../lib/paths.sh"
. "$_dir/../lib/metadata.sh"
. "$_dir/../lib/azdo.sh"
unset _dir

case "${1:-}" in -h|--help) show_help "$0"; exit 0 ;; esac

run_id="${1:-}"

# Validate numeric IF a run-id was given. No arg → list mode.
if [ -n "$run_id" ]; then
  case "$run_id" in
    *[!0-9]*) die "Run id must be numeric: '$run_id'" ;;
  esac
fi

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."

derive_azdo_context "$TARGET_REPO"
require_az

# --- List mode (no run-id given) ---
if [ -z "$run_id" ]; then
  log_step "Recent runs in $AZDO_REPO (last 20)"
  # az's default `-o table` shows Run ID + Pipeline Name + Status + Result +
  # other columns. We pull --top 50 and filter to this repo's pipelines via
  # grep — using az's own table layout (which keeps the Run ID column
  # reliably) is simpler than fighting JMESPath + table-rendering quirks.
  table="$(az pipelines runs list --top 50 -o table 2>/dev/null || true)"
  if [ -z "$table" ]; then
    die "az pipelines runs list returned nothing — check 'az login' and the azure-devops extension."
  fi

  # Print the header (lines 1-2) then up to 20 filtered rows.
  printf '%s\n' "$table" | head -2
  printf '%s\n' "$table" | tail -n +3 | grep -F "$AZDO_REPO-" | head -20 || true

  echo ""
  log_info "Show details with: noclickops status <run-id>"
  exit 0
fi

# --- Detail mode (one run-id) ---

raw="$(az pipelines runs show --id "$run_id" \
  --query "{name:definition.name, status:status, result:result, started:startTime, finished:finishTime}" \
  -o tsv)"
IFS=$'\t' read -r pipeline status result started finished <<< "$raw"

run_url="$AZDO_ORG_URL/$AZDO_PROJECT/_build/results?buildId=$run_id"

is_set() {
  case "$1" in ''|'None') return 1 ;; *) return 0 ;; esac
}

printf "\nRun %s\n" "$run_id"
printf "  Pipeline:  %s\n" "$pipeline"
printf "  Status:    %s\n" "$status"
is_set "$result"   && printf "  Result:    %s\n" "$result"
is_set "$started"  && printf "  Started:   %s\n" "$started"
is_set "$finished" && printf "  Finished:  %s\n" "$finished"
printf "  URL:       %s\n" "$run_url"

# Exit 0 if the status check itself succeeded — regardless of the pipeline's
# result. Callers grep the output (e.g. for 'Result: succeeded') if they
# want to gate downstream work on the pipeline outcome.
exit 0
