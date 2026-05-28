#!/usr/bin/env bash
# bin/logs.sh — show or stream a service's container-app logs.
#
# Resolves service+env via lib/service.sh, finds the container app in the
# computed resource group, and execs `az containerapp logs show`.
#
# Unlike `info` (which is informational and exits 0 even on partial output),
# `logs` is gating — any access failure exits non-zero.
#
# --- noclickops metadata ---
SCRIPT_NAME="logs"
SCRIPT_DESCRIPTION="Show or stream the container-app logs for a service."
SCRIPT_USAGE="noclickops logs <service> [test|prod] [--follow|-f] [--tail N] [--system]"
SCRIPT_EXAMPLE="noclickops logs test-holderdeord test --follow"
SCRIPT_CATEGORY="inspect"
# --- end metadata ---

set -euo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_dir/../lib/logging.sh"
. "$_dir/../lib/utilities.sh"
. "$_dir/../lib/paths.sh"
. "$_dir/../lib/metadata.sh"
. "$_dir/../lib/service.sh"
unset _dir

case "${1:-}" in -h|--help) show_help "$0"; exit 0 ;; esac

service="${1:-}"
[ -n "$service" ] || die "Usage: $SCRIPT_USAGE"
shift

# Second positional, if present and not a flag, MUST be test|prod.
# Catches typos like 'logs myapp staging' with a useful error instead of
# misclassifying the env as an unknown flag.
env="test"
case "${1:-}" in
  test|prod) env="$1"; shift ;;
  ''|-*)     ;;  # no second positional, or it's a flag — env stays default
  *)         die "Invalid environment '$1' (expected: test | prod)" ;;
esac

# Remaining args: flags only.
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

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."

# resolve_service_context dies on unknown service / invalid env / missing yamls.
resolve_service_context "$service" "$env" "$TARGET_REPO"

require_cmd az
az account show >/dev/null 2>&1 || die "Not logged in to Azure. Run: az login"

# Fail-closed on subscription access — logs is gating.
try_az_subscription "$SVC_SUBSCRIPTION_ID" || exit 1

# Locate the container app by SVC_NAME-contains in the computed RG.
app_name="$(az containerapp list \
  --subscription "$SVC_SUBSCRIPTION_ID" \
  --resource-group "$SVC_RESOURCE_GROUP" \
  --query "[?contains(name, '$SVC_NAME')] | [0].name" \
  -o tsv 2>/dev/null || true)"

if [ -z "$app_name" ] || [ "$app_name" = "None" ]; then
  die "No container app found in $SVC_RESOURCE_GROUP matching '$SVC_NAME'.
Has it been deployed yet?  noclickops deploy $SVC_NAME $SVC_ENV --watch"
fi

# Build the az invocation. exec replaces our process so Ctrl-C terminates
# cleanly during --follow without bash trapping the signal.
args=(containerapp logs show
  --name "$app_name"
  --resource-group "$SVC_RESOURCE_GROUP"
  --subscription "$SVC_SUBSCRIPTION_ID"
  --tail "$tail")
[ "$follow" -eq 1 ] && args+=(--follow)
[ "$system" -eq 1 ] && args+=(--type system)

log_info "Container app: $app_name (env: $env, tail: $tail$([ "$follow" -eq 1 ] && printf ', follow')$([ "$system" -eq 1 ] && printf ', system'))"
exec az "${args[@]}"
