#!/usr/bin/env bash
# bin/status.sh — show the status of an Azure DevOps pipeline run, OR list
# recent runs in the current target repo's pipelines.
#
# Modes:
#   noclickops status                       → list recent runs in the target repo
#   noclickops status <run-id>              → show details for one run
#   noclickops status <service> [<env>]     → list recent runs filtered to a service
#
# Designed for the fire-and-forget pattern in `noclickops add-service`
# (PLAN-007a) where the pipeline takes ~1h. The list mode (v1.2.0) lets
# you discover run ids without needing to remember them.
#
# --- noclickops metadata ---
SCRIPT_NAME="status"
SCRIPT_DESCRIPTION="List recent pipeline runs (optionally filtered to a service), or show details for one run id."
SCRIPT_USAGE="noclickops status [<run-id> | <service> [<env>]]"
SCRIPT_EXAMPLE="noclickops status smk1 test"
SCRIPT_CATEGORY="inspect"
SCRIPT_TAGS="pipeline-run azure-devops watch poll list"
SCRIPT_DETAILS="Without arguments, lists the 20 most recent pipeline runs in the target repo (id, result, name, queued time). With a numeric run id, shows that one run's status, queue/start/finish times, and the URL. With a service name (and optional env), lists only runs for that service's pipelines — for an env-specific filter (test|prod), runs of the opposite env's IaC deploy pipeline are excluded."
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
SCRIPT_EXAMPLE_OUTPUT=$(cat <<'EOF'
noclickops status v1.7.4 — recent runs for smk1 (test) in ABC100001-myservice

==> Recent runs in ABC100001-myservice (last 20)
ID        Result     Pipeline                                            Queued
--------  ---------  --------------------------------------------------  ----------------
28536     succeeded  ABC100001-myservice-smk1-deploy-test                2026-05-29 15:35
28535     succeeded  ABC100001-myservice-smk1-infra-build                2026-05-29 15:33
28534     succeeded  ABC100001-myservice-smk1-deploy                     2026-05-29 15:32
28533     succeeded  ABC100001-myservice-smk1-build                      2026-05-29 15:30

ℹ Show details with: noclickops status <run-id>
EOF
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

# Parse args. Three modes:
#   (no args)               → list mode, no filter
#   <numeric>               → detail mode for that run-id
#   <non-numeric> [<env>]   → list mode filtered to that service (and optionally env)
arg1="${1:-}"
arg2="${2:-}"

run_id=""
svc_filter=""
env_filter=""

if [ -n "$arg1" ]; then
  case "$arg1" in
    *[!0-9]*)
      # non-numeric → treat as service name
      svc_filter="$arg1"
      if [ -n "$arg2" ]; then
        case "$arg2" in
          test|prod) env_filter="$arg2" ;;
          *) die "Unknown env: '$arg2' (expected test|prod). Usage: $SCRIPT_USAGE" ;;
        esac
      fi
      ;;
    *)
      # numeric → run-id
      [ -z "$arg2" ] || die "Run-id mode takes no second argument. Usage: $SCRIPT_USAGE"
      run_id="$arg1"
      ;;
  esac
fi

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."

derive_azdo_context "$TARGET_REPO"
require_az

if [ -n "$run_id" ]; then
  nco_command_header "run $run_id in $AZDO_REPO"
elif [ -n "$svc_filter" ] && [ -n "$env_filter" ]; then
  nco_command_header "recent runs for $svc_filter ($env_filter) in $AZDO_REPO"
elif [ -n "$svc_filter" ]; then
  nco_command_header "recent runs for $svc_filter in $AZDO_REPO"
else
  nco_command_header "recent runs in $AZDO_REPO"
fi

# --- List mode (no run-id) ---
if [ -z "$run_id" ]; then
  log_step "Recent runs in $AZDO_REPO (last 20)"

  # Project only the columns worth scanning: ID / Result / Pipeline / Queued.
  # Status, Source Branch, Reason, Number are dropped — they almost never
  # vary across rows in this view (filter is already 'completed' by virtue
  # of recency + grep against repo prefix).
  table="$(az pipelines runs list --top 50 -o table \
    --query "[].{ID:id, Result:result, Pipeline:definition.name, Queued:queueTime}" \
    2>/dev/null || true)"
  if [ -z "$table" ]; then
    die "az pipelines runs list returned nothing — check 'az login' and the azure-devops extension."
  fi

  # Compress queueTime to 'YYYY-MM-DD HH:MM'. az emits either '…SS.ffffffZ'
  # or '…SS.ffffff+00:00' depending on tenant config; both end the row so
  # strip everything after the minutes (Queued is the last column).
  trim_time='s/T([0-9]{2}:[0-9]{2}).*$/ \1/'

  # Filter prefix: repo (always) + optional service.
  filter_pat="$AZDO_REPO-"
  [ -n "$svc_filter" ] && filter_pat="$AZDO_REPO-${svc_filter}-"

  printf '%s\n' "$table" | head -2 | sed -E "$trim_time"

  rows=$(printf '%s\n' "$table" | tail -n +3 | grep -F "$filter_pat" || true)
  # For env-specific filter, exclude opposite-env IaC deploy pipeline rows.
  if [ "$env_filter" = "test" ]; then
    rows=$(printf '%s\n' "$rows" | grep -v -- 'deploy-prod' || true)
  elif [ "$env_filter" = "prod" ]; then
    rows=$(printf '%s\n' "$rows" | grep -v -- 'deploy-test' || true)
  fi

  if [ -z "$rows" ]; then
    echo ""
    if [ -n "$svc_filter" ]; then
      log_info "No recent runs found for '$svc_filter'${env_filter:+ ($env_filter)} in last 50."
      log_info "Try 'noclickops status' to see all recent runs."
    else
      log_info "No recent runs found in $AZDO_REPO."
    fi
    exit 0
  fi

  printf '%s\n' "$rows" | head -20 | sed -E "$trim_time"

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
