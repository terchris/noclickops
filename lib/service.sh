#!/usr/bin/env bash
# lib/service.sh — per-service + per-env context resolution for FRT-shaped
# repos. Reads three YAML files to populate a set of SVC_* globals that
# bin/info / bin/logs / bin/shell all share.
#
# YAML layout (FRT convention, verified against the reference FRT-shaped
# repo's .pipelines/cd.yaml + .pipelines/variables/*.yaml):
#
#   <repo>/.pipelines/variables/common.yaml          — APP_NAME, registry, ...
#   <repo>/.pipelines/variables/<env>.yaml           — SUBSCRIPTION_ID, ENVIRONMENT, ...
#   <repo>/services/<svc>/.pipelines/variables/<env>.yaml  — SERVICE_PORT, SERVICE_HEALTH_CHECK_PATH, ...
#
# Resource-group convention (from cd.yaml): rg-<env>-nrx-<APP_NAME>.

[[ -n "${_NCO_SERVICE_LOADED:-}" ]] && return 0
_NCO_SERVICE_LOADED=1

_svc_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${_NCO_LOGGING_LOADED:-}"   ]] && . "$_svc_dir/logging.sh"
[[ -z "${_NCO_UTILITIES_LOADED:-}" ]] && . "$_svc_dir/utilities.sh"
unset _svc_dir

# Extract `key: value` from a simple YAML file. Handles plain values,
# double-quoted, and single-quoted; returns empty on missing key.
# These FRT variable YAMLs are flat — no nested keys, no anchors, no
# multiline strings — so this minimal parser is enough. Don't reuse it
# on real YAML.
yaml_var() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  grep -E "^[[:space:]]*${key}:[[:space:]]" "$file" 2>/dev/null \
    | head -1 \
    | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//" \
    | sed -E 's/^"(.*)"[[:space:]]*$/\1/' \
    | sed -E "s/^'(.*)'[[:space:]]*$/\1/" \
    | sed -E 's/[[:space:]]+$//'
}

# Resolve the service+env context. Dies on missing files or invalid env.
# Sets SVC_NAME, SVC_DIR, SVC_ENV, SVC_APP_NAME, SVC_SUBSCRIPTION_ID,
# SVC_ENVIRONMENT, SVC_COMMON_RG, SVC_RESOURCE_GROUP, SVC_PORT,
# SVC_HEALTH_PATH, SVC_PUBLIC_ENDPOINT, SVC_CPU, SVC_MEMORY,
# SVC_MIN_REPLICAS, SVC_MAX_REPLICAS.
resolve_service_context() {
  local service="${1:-}" env="${2:-test}" repo="${3:-${TARGET_REPO:-}}"
  [ -n "$service" ] || die "resolve_service_context: needs service name"
  [ -n "$repo" ]    || die "resolve_service_context: needs target repo path"
  case "$env" in
    test|prod) ;;
    *) die "Invalid environment '$env' (expected: test | prod)" ;;
  esac

  local svc_dir="$repo/services/$service"
  [ -d "$svc_dir" ] || die "Service '$service' not found at $svc_dir."

  local common_yaml="$repo/.pipelines/variables/common.yaml"
  local env_yaml="$repo/.pipelines/variables/$env.yaml"
  local svc_env_yaml="$svc_dir/.pipelines/variables/$env.yaml"

  [ -f "$common_yaml" ]  || die "Repo-level variables missing: $common_yaml"
  [ -f "$env_yaml" ]     || die "Env variables missing: $env_yaml"
  [ -f "$svc_env_yaml" ] || die "Service env variables missing: $svc_env_yaml"

  SVC_NAME="$service"
  SVC_DIR="$svc_dir"
  SVC_ENV="$env"

  SVC_APP_NAME="$(yaml_var "$common_yaml" APP_NAME)"
  SVC_SUBSCRIPTION_ID="$(yaml_var "$env_yaml" SUBSCRIPTION_ID)"
  SVC_ENVIRONMENT="$(yaml_var "$env_yaml" ENVIRONMENT)"
  SVC_COMMON_RG="$(yaml_var "$env_yaml" COMMON_RESOURCE_GROUP_NAME)"

  SVC_PORT="$(yaml_var "$svc_env_yaml" SERVICE_PORT)"
  SVC_HEALTH_PATH="$(yaml_var "$svc_env_yaml" SERVICE_HEALTH_CHECK_PATH)"
  SVC_PUBLIC_ENDPOINT="$(yaml_var "$svc_env_yaml" ENABLE_PUBLIC_ENDPOINT)"
  SVC_CPU="$(yaml_var "$svc_env_yaml" SERVICE_CPU)"
  SVC_MEMORY="$(yaml_var "$svc_env_yaml" SERVICE_MEMORY)"
  SVC_MIN_REPLICAS="$(yaml_var "$svc_env_yaml" SERVICE_MIN_REPLICAS)"
  SVC_MAX_REPLICAS="$(yaml_var "$svc_env_yaml" SERVICE_MAX_REPLICAS)"

  if [ -n "$SVC_APP_NAME" ]; then
    SVC_RESOURCE_GROUP="rg-${env}-nrx-${SVC_APP_NAME}"
  else
    SVC_RESOURCE_GROUP=""
  fi
}

# Try to switch the active az account to the service's subscription.
# Returns 0 on success; on failure, prints fail-closed diagnostics and
# returns 1 — caller decides whether to abort or skip live state.
#
# Shared by info / logs / shell so the messaging is consistent.
try_az_subscription() {
  local subscription_id="${1:-}"
  if [ -z "$subscription_id" ]; then
    log_warn "SUBSCRIPTION_ID is empty in this environment's variables file."
    return 1
  fi
  if ! az account set --subscription "$subscription_id" 2>/dev/null; then
    log_warn "Cannot access Azure subscription '$subscription_id'."
    log_warn "  You need 'Reader' (or higher) on this subscription to see live Azure state."
    log_warn "  Ask your team admin to grant Reader on subscription $subscription_id."
    return 1
  fi
  return 0
}
