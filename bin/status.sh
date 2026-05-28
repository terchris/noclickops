#!/usr/bin/env bash
# bin/status.sh — show the status of an Azure DevOps pipeline run.
#
# Generic: works for any pipeline run id in the target repo's project,
# not just add-service. Useful for the fire-and-forget pattern in
# `noclickops add-service` (PLAN-007a) where the pipeline takes ~1h and
# `--watch` would be hostile.
#
# --- noclickops metadata ---
SCRIPT_NAME="status"
SCRIPT_DESCRIPTION="Show the status of an Azure DevOps pipeline run."
SCRIPT_USAGE="noclickops status <run-id>"
SCRIPT_EXAMPLE="noclickops status 12345"
SCRIPT_CATEGORY="inspect"
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
[ -n "$run_id" ] || die "Usage: $SCRIPT_USAGE"

# ADO run ids are positive integers. Validate locally so we don't waste an
# az roundtrip on a typo.
case "$run_id" in
  ''|*[!0-9]*) die "Run id must be numeric: '$run_id'" ;;
esac

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."

derive_azdo_context "$TARGET_REPO"
require_az

# Pull all the fields in one call; -o tsv emits tab-separated values, with
# null fields rendered as empty strings (or "None" on some az versions —
# we filter both below).
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
