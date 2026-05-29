#!/usr/bin/env bash
# bin/info.sh — show config + live container-app state for a service in an env.
#
# v2: targets the new two-project / two-repo layout via lib/service-v2.sh.
#
# Always-printed (no Azure access required):
#   - Service + env header.
#   - IaC repo section: APP_NAME, APPLICATION_NAME, TEAM_NAME, SUBSCRIPTION_ID,
#     COMMON_RG, CONTAINER_REGISTRY_NAME, DNS_ZONE_NAME — all from the IaC
#     repo's environments/<TEAM>/<repo>/.../variables/{common,<env>}.yaml.
#   - Service config section: port, health check, CPU, memory, replicas,
#     public-endpoint, persistent-storage — from services/<svc>/config.<env>.yaml
#     in the source repo.
#   - Public URL line: shown only when ENABLE_PUBLIC_ENDPOINT=true.
#
# Live section (requires az login + Reader on the IaC-declared subscription):
#   - Container-app name + RG, discovered via discover_containerapp.
#   - Status / revision / image / replicas, via az containerapp show.
#   - Internal FQDN.
#
# Degrades gracefully: if discover_containerapp comes up empty (no Reader,
# app not deployed yet, naming overrides needed), live section prints a
# single "unavailable" message and the script exits 0. Static sections
# always print in full first.
#
# --- noclickops metadata ---
SCRIPT_NAME="info"
SCRIPT_DESCRIPTION="Show service config and live container-app state."
SCRIPT_USAGE="noclickops info <service> [test|prod]"
SCRIPT_EXAMPLE="noclickops info frontend test"
SCRIPT_CATEGORY="inspect"
SCRIPT_TAGS="config container-app subscription read inspect"
SCRIPT_DETAILS="v2: reads per-service config from services/<svc>/config.<env>.yaml (source repo) and IaC variables from environments/<TEAM>/<repo>/infrastructure/.pipelines/variables/ (IaC platform-infrastructure repo, via ADO REST). Container-app name + RG are discovered via az containerapp list (the actual deployed names, not a hardcoded pattern). Public URL is printed for services with ENABLE_PUBLIC_ENDPOINT=true. Static sections always print; live section degrades to a clear 'unavailable' line when Azure access is missing or naming overrides are required."
SCRIPT_AUTH="az login (target's ADO tenant) for IaC variables; Reader on the IaC-declared subscription for the live container-app section."
SCRIPT_DEPENDS_ON="az git"
SCRIPT_SEE_ALSO="logs shell deploy"
SCRIPT_FLAGS=(
  "test|Inspect the test environment (default)."
  "prod|Inspect production."
  "-h, --help|Show this help and exit."
)
SCRIPT_EXIT_CODES=(
  "0|Info shown — fully or partially (with explanatory message on partial)."
  "1|Service config / IaC variables missing, invalid env, or az error not related to access."
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
env="${2:-test}"
[ -n "$service" ] || die "Usage: $SCRIPT_USAGE"
case "$env" in test|prod) ;; *) die "env must be 'test' or 'prod' (got '$env')" ;; esac

[ -n "${TARGET_REPO:-}" ] || die "Not inside a git repository. cd into a repo and re-run."

read_service_config "$service" "$env"
read_iac_variables  "$env"

# --- Static section: header ---

printf "\n${_NCO_BOLD}Service: %s (%s)${_NCO_NC}\n" "$service" "$env"
printf "%s\n" "────────────────────────────────────────"
printf "  Folder:             %s/services/%s\n" "$TARGET_REPO" "$service"

# --- Static section: IaC repo ---

printf "\n${_NCO_BOLD}IaC repo (engineer-owned):${_NCO_NC}\n"
printf "  App name (IaC):     %s\n" "${IAC_APP_NAME:-(unset)}"
printf "  Application name:   %s\n" "${IAC_APPLICATION_NAME:-(unset)}"
printf "  Team:               %s\n" "${IAC_TEAM_NAME:-(unset)}"
printf "  Subscription:       %s\n" "${IAC_SUBSCRIPTION_ID:-(unset)}"
printf "  Common RG:          %s\n" "${IAC_COMMON_RESOURCE_GROUP_NAME:-(unset)}"
printf "  Container registry: %s\n" "${IAC_CONTAINER_REGISTRY_NAME:-(unset)}"
printf "  DNS zone:           %s\n" "${IAC_DNS_ZONE_NAME:-(unset)}"

# --- Static section: service config ---

printf "\n${_NCO_BOLD}Service config:${_NCO_NC}\n"
printf "  Port:               %s\n" "${SVC_CFG_SERVICE_PORT:-(unset)}"
printf "  Health check:       %s\n" "${SVC_CFG_SERVICE_HEALTH_CHECK_PATH:-(unset)}"
printf "  CPU:                %s\n" "${SVC_CFG_SERVICE_CPU:-(unset)}"
printf "  Memory:             %s\n" "${SVC_CFG_SERVICE_MEMORY:-(unset)}"
printf "  Replicas (min):     %s\n" "${SVC_CFG_SERVICE_MIN_REPLICAS:-(unset)}"
printf "  Replicas (max):     %s\n" "${SVC_CFG_SERVICE_MAX_REPLICAS:-(unset)}"
printf "  Public endpoint:    %s\n" "${SVC_CFG_ENABLE_PUBLIC_ENDPOINT:-(unset)}"
printf "  Persistent storage: %s\n" "${SVC_CFG_PERSISTENT_STORAGE:-(unset)}"

# --- Public URL (only when public) ---

if [ "${SVC_CFG_ENABLE_PUBLIC_ENDPOINT:-}" = "true" ]; then
  public_host=$(public_url_for "$service" "$env" 2>/dev/null || true)
  if [ -n "$public_host" ]; then
    printf "  Public URL:         https://%s\n" "$public_host"
  fi
fi

# --- Live section: container-app state ---

printf "\n${_NCO_BOLD}Live state (Azure):${_NCO_NC}\n"

if [ -z "${NCO_AZ_OVERRIDE:-}" ] && ! command -v az >/dev/null 2>&1; then
  printf "  (live state unavailable — 'az' not on PATH)\n"
  exit 0
fi
if ! _nco_az account show >/dev/null 2>&1; then
  printf "  (live state unavailable — not logged in to Azure; run 'az login')\n"
  exit 0
fi

# discover_containerapp dies on full failure; we want degradation here.
discover_output=$(discover_containerapp "$service" 2>/dev/null) || discover_output=""

if [ -z "$discover_output" ]; then
  printf "  (live state unavailable — set SVC_APP_NAME_OVERRIDE and SVC_RG_OVERRIDE to override,\n"
  printf "   or check 'az login' and that you have Reader on subscription %s)\n" "${IAC_SUBSCRIPTION_ID:-<unknown>}"
  exit 0
fi

# Parse the name/rg/fqdn lines.
ca_name=""; ca_rg=""; ca_fqdn=""
while IFS='=' read -r k v; do
  case "$k" in
    name)           ca_name="$v" ;;
    resource_group) ca_rg="$v" ;;
    fqdn)           ca_fqdn="$v" ;;
  esac
done <<< "$discover_output"

printf "  Container app:      %s\n" "${ca_name:-(unset)}"
printf "  Resource group:     %s\n" "${ca_rg:-(unset)}"
[ -n "$ca_fqdn" ] && printf "  Internal FQDN:      %s\n" "$ca_fqdn"

# Detail query — single TSV row.
sub="${IAC_SUBSCRIPTION_ID:-}"
if [ -z "$ca_name" ] || [ -z "$ca_rg" ] || [ -z "$sub" ]; then
  printf "  (detailed state unavailable — missing name/rg/subscription)\n"
  exit 0
fi

raw=$(_nco_az containerapp show \
  --subscription "$sub" \
  -n "$ca_name" -g "$ca_rg" \
  --query "{status:properties.runningStatus, revision:properties.latestRevisionName, image:properties.template.containers[0].image, minR:properties.template.scale.minReplicas, maxR:properties.template.scale.maxReplicas}" \
  -o tsv 2>/dev/null || true)

if [ -z "$raw" ]; then
  printf "  (detailed state unavailable — 'az containerapp show' failed; check Reader role)\n"
  exit 0
fi

IFS=$'\t' read -r status revision image min_r max_r <<< "$raw"

is_set() { case "$1" in ''|'None') return 1 ;; *) return 0 ;; esac; }

is_set "$status"   && printf "  Status:             %s\n" "$status"
is_set "$revision" && printf "  Latest revision:    %s\n" "$revision"
is_set "$image"    && printf "  Image:              %s\n" "$image"
if is_set "$min_r" || is_set "$max_r"; then
  printf "  Replicas (live):    min=%s, max=%s\n" "${min_r:-?}" "${max_r:-?}"
fi
