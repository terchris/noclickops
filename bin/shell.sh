#!/usr/bin/env bash
# bin/shell.sh — open an interactive shell inside a running container app (v2).
#
# Same v2 discovery chain as bin/logs.sh; the difference is the final az
# call (containerapp exec vs containerapp logs show) and the default entry
# command (/bin/sh).
#
# Gating — dies loudly on any discovery failure. You can't shell into
# "(unavailable)".
#
# --- noclickops metadata ---
SCRIPT_NAME="shell"
SCRIPT_DESCRIPTION="Open an interactive shell in the live container app for a service."
SCRIPT_USAGE="noclickops shell <service> [test|prod] [--command CMD] [--container NAME] [--revision NAME]"
SCRIPT_EXAMPLE="noclickops shell frontend test"
SCRIPT_CATEGORY="inspect"
SCRIPT_TAGS="exec shell container-app interactive sh"
SCRIPT_DETAILS="v2: reads IaC variables (subscription + common RG) from the cross-project IaC repo via ADO REST, discovers the container app via az containerapp list, and exec's az containerapp exec for an interactive /bin/sh session. Override via SVC_APP_NAME_OVERRIDE + SVC_RG_OVERRIDE. --command runs a single command non-interactively; --container picks a non-default container in a multi-container app; --revision picks a non-active revision."
SCRIPT_AUTH="az login + Reader on the IaC-declared subscription."
SCRIPT_DEPENDS_ON="az git"
SCRIPT_SEE_ALSO="info logs deploy"
SCRIPT_FLAGS=(
  "test|Shell into the test environment (default)."
  "prod|Shell into production."
  "--command CMD|Run a single command non-interactively, then exit."
  "--container NAME|Pick a specific container in a multi-container app."
  "--revision NAME|Pick a specific revision (default: currently active)."
  "-h, --help|Show this help and exit."
)
SCRIPT_EXIT_CODES=(
  "0|Shell session exited cleanly (or single command ran successfully)."
  "1|Service / container / revision not found, or access denied."
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

cmd="/bin/sh"
container=""
revision=""

while [ $# -gt 0 ]; do
  case "$1" in
    --command)
      shift
      [ $# -gt 0 ] || die "--command requires a value"
      cmd="$1"
      ;;
    --command=*) cmd="${1#--command=}" ;;
    --container)
      shift
      [ $# -gt 0 ] || die "--container requires a value"
      container="$1"
      ;;
    --container=*) container="${1#--container=}" ;;
    --revision)
      shift
      [ $# -gt 0 ] || die "--revision requires a value"
      revision="$1"
      ;;
    --revision=*) revision="${1#--revision=}" ;;
    *) die "Unknown argument: $1 (expected --command / --container / --revision)" ;;
  esac
  shift
done

[ -n "${TARGET_REPO:-}" ] || die "Not inside a git repository. cd into a repo and re-run."

read_iac_variables "$env"

if [ -z "${NCO_AZ_OVERRIDE:-}" ]; then
  require_cmd az
  az account show >/dev/null 2>&1 || die "Not logged in to Azure. Run: az login"
fi

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

args=(containerapp exec
  --name "$ca_name"
  --resource-group "$ca_rg"
  --subscription "$sub"
  --command "$cmd")
[ -n "$container" ] && args+=(--container "$container")
[ -n "$revision" ]  && args+=(--revision "$revision")

log_info "Container app: $ca_name (env: $env, cmd: $cmd${container:+, container: $container}${revision:+, revision: $revision})"
exec "${NCO_AZ_OVERRIDE:-az}" "${args[@]}"
