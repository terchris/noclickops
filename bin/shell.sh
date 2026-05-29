#!/usr/bin/env bash
# bin/shell.sh — open an interactive shell inside a running container app.
#
# Same lib/service.sh chain as bin/logs.sh; the difference is the final
# az call (containerapp exec vs containerapp logs show) and the default
# entry command.
#
# --- noclickops metadata ---
SCRIPT_NAME="shell"
SCRIPT_DESCRIPTION="Open an interactive shell in the live container app for a service."
SCRIPT_USAGE="noclickops shell <service> [test|prod] [--command CMD] [--container NAME] [--revision NAME]"
SCRIPT_EXAMPLE="noclickops shell test-holderdeord test"
SCRIPT_CATEGORY="inspect"
SCRIPT_TAGS="exec shell container-app interactive sh"
SCRIPT_DETAILS="Opens an interactive /bin/sh inside the running container of a deployed service via az containerapp exec. Use --command to run a single command non-interactively. --container picks a non-default container in a multi-container app; --revision picks a non-active revision."
SCRIPT_AUTH="az login + Reader on the subscription in \`.pipelines/variables/<env>.yaml\`."
SCRIPT_DEPENDS_ON="az"
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
. "$_dir/../lib/service.sh"
unset _dir

case "${1:-}" in -h|--help) show_help "$0"; exit 0 ;; esac

service="${1:-}"
[ -n "$service" ] || die "Usage: $SCRIPT_USAGE"
shift

# Second positional, if present and not a flag, MUST be test|prod.
env="test"
case "${1:-}" in
  test|prod) env="$1"; shift ;;
  ''|-*)     ;;  # absent or it's a flag
  *)         die "Invalid environment '$1' (expected: test | prod)" ;;
esac

# Defaults: /bin/sh works in nginx:alpine (the Lovable Dockerfile base);
# 'bash' isn't installed in plain alpine.
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

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."

resolve_service_context "$service" "$env" "$TARGET_REPO"

require_cmd az
az account show >/dev/null 2>&1 || die "Not logged in to Azure. Run: az login"

try_az_subscription "$SVC_SUBSCRIPTION_ID" || exit 1

app_name="$(az containerapp list \
  --subscription "$SVC_SUBSCRIPTION_ID" \
  --resource-group "$SVC_RESOURCE_GROUP" \
  --query "[?contains(name, '$SVC_NAME')] | [0].name" \
  -o tsv 2>/dev/null || true)"

if [ -z "$app_name" ] || [ "$app_name" = "None" ]; then
  die "No container app found in $SVC_RESOURCE_GROUP matching '$SVC_NAME'.
Has it been deployed yet?  noclickops deploy $SVC_NAME $SVC_ENV --watch"
fi

# Build the az invocation. exec replaces our process so stdin/stdout are
# wired straight to az — needed for interactive shell + clean Ctrl-D/Ctrl-C.
args=(containerapp exec
  --name "$app_name"
  --resource-group "$SVC_RESOURCE_GROUP"
  --subscription "$SVC_SUBSCRIPTION_ID"
  --command "$cmd")
[ -n "$container" ] && args+=(--container "$container")
[ -n "$revision" ]  && args+=(--revision "$revision")

log_info "Container app: $app_name (env: $env, cmd: $cmd${container:+, container: $container}${revision:+, revision: $revision})"
exec az "${args[@]}"
