#!/usr/bin/env bash
# bin/info.sh — show config + live container-app state for a service in an env.
#
# Always-printed (no auth required):
#   - Service folder + the APP_NAME / ENVIRONMENT / SUBSCRIPTION_ID /
#     resource-group block derived from .pipelines/variables/.
#   - Service config (port, health-check path, CPU / memory / replicas /
#     public-endpoint) from the service's per-env variables.yaml.
#
# Live state (requires az login + Reader on subscription):
#   - az containerapp list filtered by SVC_NAME in the computed RG.
#   - Status, latest revision, FQDN, current image tag, live min/max replicas.
#   - Fails CLOSED if subscription access is denied — prints a clear message
#     telling the user what to ask for. Static sections still print.
#
# --- noclickops metadata ---
SCRIPT_NAME="info"
SCRIPT_DESCRIPTION="Show service config and live container-app state."
SCRIPT_USAGE="noclickops info <service> [test|prod]"
SCRIPT_EXAMPLE="noclickops info test-holderdeord test"
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
env="${2:-test}"
[ -n "$service" ] || die "Usage: $SCRIPT_USAGE"

[ -n "$TARGET_REPO" ] || die "Not inside a git repository. cd into a repo and re-run."

resolve_service_context "$service" "$env" "$TARGET_REPO"

# --- Static section: env + identity ---

printf "\n${_NCO_BOLD}Service: %s (%s)${_NCO_NC}\n" "$SVC_NAME" "$SVC_ENV"
printf "%s\n" "────────────────────────────────────────"
printf "  Folder:            %s\n" "$SVC_DIR"
printf "  APP_NAME:          %s\n" "${SVC_APP_NAME:-(unset)}"
printf "  ENVIRONMENT:       %s\n" "${SVC_ENVIRONMENT:-(unset)}"
printf "  SUBSCRIPTION_ID:   %s\n" "${SVC_SUBSCRIPTION_ID:-(unset)}"
printf "  Resource group:    %s\n" "${SVC_RESOURCE_GROUP:-(unset)}"
printf "  Common RG:         %s\n" "${SVC_COMMON_RG:-(unset)}"

# --- Static section: service config ---

printf "\n${_NCO_BOLD}Service config:${_NCO_NC}\n"
printf "  Port:              %s\n" "${SVC_PORT:-?}"
printf "  Health check:      %s\n" "${SVC_HEALTH_PATH:-?}"
printf "  CPU:               %s\n" "${SVC_CPU:-?}"
printf "  Memory:            %s\n" "${SVC_MEMORY:-?}"
printf "  Replicas (min):    %s\n" "${SVC_MIN_REPLICAS:-?}"
printf "  Replicas (max):    %s\n" "${SVC_MAX_REPLICAS:-?}"
printf "  Public endpoint:   %s\n" "${SVC_PUBLIC_ENDPOINT:-?}"

# --- Live section: requires az + subscription read ---

printf "\n${_NCO_BOLD}Container app (live):${_NCO_NC}\n"

if ! command -v az >/dev/null 2>&1; then
  printf "  (live state unavailable — 'az' not on PATH)\n"
  exit 0
fi
if ! az account show >/dev/null 2>&1; then
  printf "  (live state unavailable — not logged in to Azure; run 'az login')\n"
  exit 0
fi
if ! try_az_subscription "$SVC_SUBSCRIPTION_ID"; then
  printf "  (live state unavailable — see warnings above)\n"
  exit 0
fi

# Single query → tab-separated values. Empty fields render as empty strings.
raw="$(az containerapp list \
  --subscription "$SVC_SUBSCRIPTION_ID" \
  --resource-group "$SVC_RESOURCE_GROUP" \
  --query "[?contains(name, '$SVC_NAME')] | [0].{name:name, status:properties.runningStatus, revision:properties.latestRevisionName, fqdn:properties.configuration.ingress.fqdn, image:properties.template.containers[0].image, minR:properties.template.scale.minReplicas, maxR:properties.template.scale.maxReplicas}" \
  -o tsv 2>/dev/null || true)"

if [ -z "$raw" ]; then
  log_warn "No container app found in $SVC_RESOURCE_GROUP matching '$SVC_NAME'."
  log_warn "The pipeline may not have deployed yet. Try: noclickops deploy $SVC_NAME $SVC_ENV --watch"
  exit 0
fi

IFS=$'\t' read -r name status revision fqdn image min_r max_r <<< "$raw"

is_set() { case "$1" in ''|'None') return 1 ;; *) return 0 ;; esac; }

is_set "$name"     && printf "  Name:              %s\n" "$name"
is_set "$status"   && printf "  Status:            %s\n" "$status"
is_set "$revision" && printf "  Latest revision:   %s\n" "$revision"
is_set "$fqdn"     && printf "  FQDN:              https://%s\n" "$fqdn"
is_set "$image"    && printf "  Image:             %s\n" "$image"
if is_set "$min_r" || is_set "$max_r"; then
  printf "  Replicas (live):   min=%s, max=%s\n" "${min_r:-?}" "${max_r:-?}"
fi
