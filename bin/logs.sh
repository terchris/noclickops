#!/usr/bin/env bash
# bin/logs.sh — show or stream a service's container-app logs (v2).
#
# Reads IaC variables (subscription + RG context) from the cross-project IaC
# repo via lib/service-v2.sh, then discovers the live container app via
# az containerapp list (or honours SVC_APP_NAME_OVERRIDE + SVC_RG_OVERRIDE),
# and exec's `az containerapp logs show`.
#
# Gating — unlike `info` (which degrades), `logs` dies loudly on any
# discovery failure. There's nothing useful to stream from "(unavailable)".
#
# --- noclickops metadata ---
SCRIPT_NAME="logs"
SCRIPT_DESCRIPTION="Show or stream the container-app logs for a service."
SCRIPT_USAGE="noclickops logs <service> [test|prod] [--follow|-f] [--tail N] [--system]"
SCRIPT_EXAMPLE="noclickops logs frontend test --follow"
SCRIPT_CATEGORY="inspect"
SCRIPT_TAGS="container-app logs tail streaming follow"
SCRIPT_DETAILS="v2: reads IaC variables (subscription + common RG) from the cross-project IaC repo via ADO REST, discovers the container app via az containerapp list, and exec's az containerapp logs show. Override via SVC_APP_NAME_OVERRIDE + SVC_RG_OVERRIDE env vars. --follow keeps the stream open until Ctrl-C; --tail N starts with the last N lines and exits; --system includes platform logs. Gating — any access / discovery failure exits non-zero."
SCRIPT_AUTH="az login + Reader on the IaC-declared subscription."
SCRIPT_DEPENDS_ON="az git"
SCRIPT_SEE_ALSO="info shell deploy"
SCRIPT_FLAGS=(
  "test|Tail the test environment (default)."
  "prod|Tail production."
  "--follow, -f|Stream new logs as they arrive."
  "--tail N|Start with the last N lines, then exit."
  "--system|Include system / platform logs alongside app logs."
  "-h, --help|Show this help and exit."
)
SCRIPT_EXIT_CODES=(
  "0|Logs streamed or printed; --follow ended cleanly."
  "1|Service / container app not found, access denied, or invalid arg."
)
SCRIPT_EXAMPLE_OUTPUT=$(cat <<'EOF'
noclickops logs v1.7.6 — frontend (test, --tail 5)

ℹ Container app: ca-abc100001-frontend (env: test, tail: 5)
2026-05-29T15:45:01.234Z stdout F Listening on port 3000
2026-05-29T15:45:23.567Z stdout F GET /health 200 1.2ms
2026-05-29T15:46:01.892Z stdout F GET /health 200 0.9ms
2026-05-29T15:46:31.123Z stdout F GET / 200 2.4ms
2026-05-29T15:47:01.456Z stdout F GET /health 200 1.1ms

# When you lack Reader on the deployed subscription, logs fails closed
# with a structured probe diagnostic (v1.7.1+):
  ✗ FAILED: discover container app for frontend
  Looked for: ca-abc100001-frontend in RG rg-test-myteam-frontend-common of sub 3aec5ff4-...

  Reason:  You do not have access to subscription "3aec5ff4-...".
  Action:  → Ask your admin for Reader on "3aec5ff4-...", or use PIM to activate eligibility.
           Subscriptions you DO have access to:
             DEV - <team> - <name>  <sub-id>
             ...

  Override (skip discovery): SVC_APP_NAME_OVERRIDE=<name> SVC_RG_OVERRIDE=<rg>
EOF
)
# --- end metadata ---

set -euo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_dir/../lib/logging.sh"
. "$_dir/../lib/utilities.sh"
. "$_dir/../lib/paths.sh"
. "$_dir/../lib/metadata.sh"
. "$_dir/../lib/service-v2.sh"
unset _dir

case "${1:-}" in -h|--help) show_help "$0"; exit 0 ;; esac

service="${1:-}"
[ -n "$service" ] || die "Usage: $SCRIPT_USAGE"
shift

env="test"
case "${1:-}" in
  test|prod) env="$1"; shift ;;
  ''|-*)     ;;
  *)         die "Invalid environment '$1' (expected: test | prod)" ;;
esac

follow=0
system=0
tail=100
while [ $# -gt 0 ]; do
  case "$1" in
    --follow|-f) follow=1 ;;
    --tail)
      shift
      [ $# -gt 0 ] || die "--tail requires a number"
      tail="$1"
      ;;
    --tail=*) tail="${1#--tail=}" ;;
    --system) system=1 ;;
    *) die "Unknown argument: $1 (expected --follow / -f / --tail N / --system)" ;;
  esac
  shift
done

case "$tail" in
  ''|*[!0-9]*) die "--tail must be numeric: '$tail'" ;;
esac

[ -n "${TARGET_REPO:-}" ] || die "Not inside a git repository. cd into a repo and re-run."

_logs_summary="$service ($env, --tail $tail"
[ "$follow" -eq 1 ] && _logs_summary+=", --follow"
[ "$system" -eq 1 ] && _logs_summary+=", --system"
_logs_summary+=")"
nco_command_header "$_logs_summary"
unset _logs_summary

read_iac_variables "$env"

if [ -z "${NCO_AZ_OVERRIDE:-}" ]; then
  require_cmd az
  az account show >/dev/null 2>&1 || die "Not logged in to Azure. Run: az login"
fi

# discover_containerapp returns 1 on failure (after report_discovery_failure
# prints the actionable diagnostic to stderr); set -e + the assignment then
# kills this script with the same exit code.
discover_output=$(discover_containerapp "$service")
ca_name=""; ca_rg=""
while IFS='=' read -r k v; do
  case "$k" in
    name)           ca_name="$v" ;;
    resource_group) ca_rg="$v" ;;
  esac
done <<< "$discover_output"

[ -n "$ca_name" ] || die "discover_containerapp returned no name for '$service'"
[ -n "$ca_rg" ]   || die "discover_containerapp returned no resource group for '$service'"

sub="${IAC_SUBSCRIPTION_ID:-}"
[ -n "$sub" ] || die "IAC_SUBSCRIPTION_ID is empty (check IaC ${env}.yaml)"

args=(containerapp logs show
  --name "$ca_name"
  --resource-group "$ca_rg"
  --subscription "$sub"
  --tail "$tail")
[ "$follow" -eq 1 ] && args+=(--follow)
[ "$system" -eq 1 ] && args+=(--type system)

log_info "Container app: $ca_name (env: $env, tail: $tail$([ "$follow" -eq 1 ] && printf ', follow')$([ "$system" -eq 1 ] && printf ', system'))"
exec "${NCO_AZ_OVERRIDE:-az}" "${args[@]}"
