#!/usr/bin/env bash
# lib/service-v2.sh — discovery library for noclickops v2.
#
# Targets the new two-project / two-repo layout (see
# website/docs/ai-developer/plans/backlog/INVESTIGATE-new-target-structure.md):
#
#   <source-project> / <repo>          — service code, build/deploy pipelines
#     services/<svc>/
#       config.<env>.yaml              — per-service config (read by read_service_config)
#       .pipelines/{service,deploy_service}.yaml
#
#   <iac-project> / platform-infrastructure  — engineer-owned deployer
#     environments/<TEAM>/<repo>/infrastructure/.pipelines/variables/
#       common.yaml                    — IAC_* repo-level vars (read by read_iac_variables)
#       <env>.yaml                     — IAC_* per-env vars
#
# Design principle: discover what exists, never hardcode customer conventions.
# No tenant prefix (e.g. v1's hardcoded `nrx`) appears in this file.
#
# Loaded alongside v1's lib/service.sh during the v2 transition. Each
# command's PLAN (B/C/D/E/F) switches its bin/<cmd>.sh from v1 to v2.

[[ -n "${_NCO_SERVICE_V2_LOADED:-}" ]] && return 0
_NCO_SERVICE_V2_LOADED=1

_svc_v2_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${_NCO_LOGGING_LOADED:-}"   ]] && . "$_svc_v2_dir/logging.sh"
[[ -z "${_NCO_UTILITIES_LOADED:-}" ]] && . "$_svc_v2_dir/utilities.sh"
[[ -z "${_NCO_AZDO_LOADED:-}"      ]] && . "$_svc_v2_dir/azdo.sh"
unset _svc_v2_dir

# ---------------------------------------------------------------------------
# az + ADO REST shims (testable)
# ---------------------------------------------------------------------------

# Wraps `az`. Tests set NCO_AZ_OVERRIDE to a stub that prints canned JSON.
_nco_az() {
  if [ -n "${NCO_AZ_OVERRIDE:-}" ]; then
    "$NCO_AZ_OVERRIDE" "$@"
  else
    az "$@"
  fi
}

# Wraps a GET against the ADO REST API. Args: <url>.
# Tests set NCO_ADO_REST_OVERRIDE to a stub that maps URL → local file content.
_nco_ado_rest_get() {
  local url="$1"
  if [ -n "${NCO_ADO_REST_OVERRIDE:-}" ]; then
    "$NCO_ADO_REST_OVERRIDE" "$url"
  else
    local token
    token=$(_nco_az account get-access-token \
      --resource "${NCO_ADO_APP_ID:-499b84ac-1321-427f-aa17-267ca6975798}" \
      --query accessToken -o tsv 2>/dev/null) || return 1
    curl -fsS -u ":$token" "$url"
  fi
}

# ---------------------------------------------------------------------------
# YAML helpers
# ---------------------------------------------------------------------------

# Extract `key: value` from a flat YAML file. Handles plain, double-quoted,
# single-quoted values. Returns empty on missing key. Same parser as v1 —
# the new layout's YAML files are equally flat (no nesting, no anchors).
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

# Iterate flat KEY: value pairs in a file, calling _emit_var KEY VALUE for each.
# Skips comments and blank lines.
_yaml_each() {
  local file="$1" callback="$2"
  [ -f "$file" ] || return 0
  local line key val
  while IFS= read -r line; do
    case "$line" in ''|'#'*|*[!\ ]*':'*) ;; *) continue ;; esac
    [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    val="${val%\"}"; val="${val#\"}"
    val="${val%\'}"; val="${val#\'}"
    val="${val%"${val##*[![:space:]]}"}"
    "$callback" "$key" "$val"
  done < "$file"
}

# ---------------------------------------------------------------------------
# Public API — stubs filled in by subsequent phases
# ---------------------------------------------------------------------------

# Parse a YAML body and export each `KEY: value` line as <prefix><KEY>=<value>.
# Body is read from stdin. Skips comments / blank lines. Strips surrounding
# quotes and trailing whitespace.
_v2_parse_and_export() {
  local prefix="$1" line key val
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    # Strip wrapping quotes (single OR double)
    if [[ "$val" =~ ^\"(.*)\"[[:space:]]*$ ]]; then val="${BASH_REMATCH[1]}"
    elif [[ "$val" =~ ^\'(.*)\'[[:space:]]*$ ]]; then val="${BASH_REMATCH[1]}"
    fi
    # Trim trailing whitespace
    val="${val%"${val##*[![:space:]]}"}"
    export "${prefix}${key}=${val}"
  done
}

# read_service_config <svc> <env>
# Reads services/<svc>/config.<env>.yaml from the target repo (the git repo
# enclosing pwd). Exports SVC_CFG_<KEY>=<value> for every flat key found.
# Sets SVC_CFG__LOADED=1.
#
# Dies on missing file with a clear message.
read_service_config() {
  local svc="${1:-}" env="${2:-}"
  [ -n "$svc" ] && [ -n "$env" ] \
    || die "read_service_config: usage: read_service_config <svc> <env>"

  local target="${TARGET_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  [ -n "$target" ] \
    || die "read_service_config: not inside a git repo (cd into your target repo first)"

  local file="$target/services/$svc/config.$env.yaml"
  [ -f "$file" ] \
    || die "read_service_config: $file not found. Is the service / env correct?"

  # Wipe any prior SVC_CFG_* state so a re-call doesn't leak stale keys.
  local v
  for v in $(compgen -v | grep '^SVC_CFG_' || true); do
    unset "$v"
  done

  _v2_parse_and_export "SVC_CFG_" < "$file"
  export SVC_CFG__LOADED=1
}

# read_iac_variables <env>
# Reads common.yaml + <env>.yaml from the IaC repo at:
#   <IAC_PROJECT>/_git/<IAC_REPO>/environments/<TEAM>/<source-repo>/infrastructure/.pipelines/variables/
# via the ADO REST items endpoint. Exports IAC_<KEY>=<value>. Sets IAC__LOADED=1.
#
# <TEAM> = first dash-segment of the source repo name (upper-cased).
# IAC_PROJECT defaults to "IaC"; honors $NOCLICKOPS_IAC_PROJECT.
# IAC_REPO defaults to "platform-infrastructure"; honors $NOCLICKOPS_IAC_REPO.
read_iac_variables() {
  local env="${1:-}"
  [ -n "$env" ] || die "read_iac_variables: usage: read_iac_variables <env>"

  local target="${TARGET_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  [ -n "$target" ] \
    || die "read_iac_variables: not inside a git repo (cd into your target repo first)"

  derive_azdo_context "$target"

  local iac_project="${NOCLICKOPS_IAC_PROJECT:-IaC}"
  local iac_repo="${NOCLICKOPS_IAC_REPO:-platform-infrastructure}"
  # <TEAM> = leading alphabetic prefix of the first dash-segment of the repo
  # name, upper-cased. E.g. ABC100001-myservice -> ABC; tch900001-foo -> TCH.
  local team_seg team
  team_seg="${AZDO_REPO%%-*}"
  team="${team_seg%%[0-9]*}"
  team="$(printf '%s' "$team" | tr '[:lower:]' '[:upper:]')"
  [ -n "$team" ] \
    || die "read_iac_variables: cannot derive TEAM prefix from repo name '$AZDO_REPO' (expected alphabetic prefix on first dash-segment)"

  local base_path="/environments/${team}/${AZDO_REPO}/infrastructure/.pipelines/variables"
  local url_common="${AZDO_ORG_URL}/${iac_project}/_apis/git/repositories/${iac_repo}/items?path=${base_path}/common.yaml&api-version=7.0"
  local url_env="${AZDO_ORG_URL}/${iac_project}/_apis/git/repositories/${iac_repo}/items?path=${base_path}/${env}.yaml&api-version=7.0"

  # Wipe any prior IAC_* state.
  local v
  for v in $(compgen -v | grep '^IAC_' || true); do
    unset "$v"
  done

  local content
  content=$(_nco_ado_rest_get "$url_common") \
    || die "read_iac_variables: failed to GET common.yaml from $url_common"
  _v2_parse_and_export "IAC_" <<< "$content"

  content=$(_nco_ado_rest_get "$url_env") \
    || die "read_iac_variables: failed to GET ${env}.yaml from $url_env"
  _v2_parse_and_export "IAC_" <<< "$content"

  export IAC__LOADED=1
}

# discover_iac_project
# Returns the IaC project name to use for cross-project pipeline queries.
# Precedence: $NOCLICKOPS_IAC_PROJECT > IAC_IAC_PROJECT (from common.yaml) > "IaC".
discover_iac_project() {
  if [ -n "${NOCLICKOPS_IAC_PROJECT:-}" ]; then
    printf '%s' "$NOCLICKOPS_IAC_PROJECT"
  elif [ -n "${IAC_IAC_PROJECT:-}" ]; then
    printf '%s' "$IAC_IAC_PROJECT"
  else
    printf 'IaC'
  fi
}

# Internal: look up a pipeline id by exact name in TSV "<id>\t<name>" data.
_v2_lookup_pipeline_id() {
  local data="$1" name="$2"
  awk -F'\t' -v n="$name" '$2==n {print $1; exit}' <<< "$data"
}

# trigger_pipeline <project> <pipeline-name> [param1=value1 ...]
# Wraps `az pipelines run`. Always targets refs/heads/main (the env is selected
# via the targetEnvironment parameter, not the source branch). Echoes the new
# run id on stdout. Dies on failure.
trigger_pipeline() {
  local project="${1:-}" pipeline="${2:-}"
  [ -n "$project" ] && [ -n "$pipeline" ] \
    || die "trigger_pipeline: usage: trigger_pipeline <project> <pipeline-name> [param=value ...]"
  shift 2

  local args=( pipelines run
    --organization "$AZDO_ORG_URL"
    --project "$project"
    --name "$pipeline"
    --branch refs/heads/main
    --query id -o tsv )

  if [ "$#" -gt 0 ]; then
    args+=( --parameters )
    local p
    for p in "$@"; do
      args+=( "$p" )
    done
  fi

  local id
  id=$(_nco_az "${args[@]}" 2>/dev/null | head -1)
  [ -n "$id" ] || die "trigger_pipeline: failed to start pipeline '$pipeline' in project '$project'"
  printf '%s' "$id"
}

# watch_run <project> <run-id> [--timeout-min N]
# Polls `az pipelines runs show` every NCO_WATCH_INTERVAL seconds (default 20)
# until the run reaches a terminal state. Prints one dot per poll (no newline)
# when stdout is a tty. Always prints a final summary line:
#
#   succeeded (Xm Ys)
#   failed (Xm Ys)
#   canceled (Xm Ys)
#   timed out after Nm
#
# Exit 0 on succeeded; exit 1 otherwise.
#
# Test-only overrides:
#   NCO_WATCH_INTERVAL=0       — poll without sleeping (fast tests)
#   NCO_WATCH_TIMEOUT_MIN=N    — override timeout in tests
watch_run() {
  local project="${1:-}" run_id="${2:-}"
  [ -n "$project" ] && [ -n "$run_id" ] \
    || die "watch_run: usage: watch_run <project> <run-id> [--timeout-min N]"
  shift 2

  local timeout_min=30
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --timeout-min) timeout_min="$2"; shift 2 ;;
      *) die "watch_run: unknown flag: $1" ;;
    esac
  done
  timeout_min="${NCO_WATCH_TIMEOUT_MIN:-$timeout_min}"
  local poll_interval="${NCO_WATCH_INTERVAL:-20}"
  local max_polls=$(( timeout_min * 60 / (poll_interval > 0 ? poll_interval : 1) ))
  [ "$max_polls" -lt 1 ] && max_polls=1

  local start_ts=$SECONDS
  local i status result
  for i in $(seq 1 "$max_polls"); do
    # First az call: status only. `az --query "[a,b]" -o tsv` outputs each
    # field on its own line (not tab-separated), so we use two queries when
    # the run reaches a terminal state — cheap (one extra round-trip total).
    status=$(_nco_az pipelines runs show \
      --organization "$AZDO_ORG_URL" --project "$project" \
      --id "$run_id" --query status -o tsv 2>/dev/null | head -1)
    if [ "$status" = "completed" ]; then
      result=$(_nco_az pipelines runs show \
        --organization "$AZDO_ORG_URL" --project "$project" \
        --id "$run_id" --query result -o tsv 2>/dev/null | head -1)
      local elapsed=$((SECONDS - start_ts))
      [ -t 1 ] && printf '\n'
      printf '%s (%dm %ds)\n' "${result:-unknown}" "$((elapsed / 60))" "$((elapsed % 60))"
      [ "$result" = "succeeded" ] && return 0 || return 1
    fi
    [ -t 1 ] && printf '.'
    [ "$poll_interval" -gt 0 ] && sleep "$poll_interval"
  done

  [ -t 1 ] && printf '\n'
  printf 'timed out after %dm\n' "$timeout_min"
  return 1
}

# _v2_pipeline_succeeded_count <project> <pipeline-id>
# Echoes the number of past runs of <pipeline-id> with result=='succeeded'.
# Echoes "0" when the pipeline doesn't exist or has never run.
_v2_pipeline_succeeded_count() {
  local project="$1" pipeline_id="$2"
  [ -z "$pipeline_id" ] && { printf '0'; return 0; }
  local count
  count=$(_nco_az pipelines runs list \
    --organization "$AZDO_ORG_URL" --project "$project" \
    --pipeline-ids "$pipeline_id" \
    --query "[?result=='succeeded'] | length(@)" \
    -o tsv 2>/dev/null | head -1)
  printf '%s' "${count:-0}"
}

# is_first_time_deploy <svc>
# Predicate (uses exit code, no stdout): returns 0 if this is a first-time
# deploy (IaC's <repo>-<svc>-deploy-test pipeline has never succeeded for
# this svc) and 1 if there's at least one prior success.
#
# Requires TARGET_REPO + AZDO_* context (callers usually run discover_pipelines
# first; this function runs it itself to get the pipeline IDs).
is_first_time_deploy() {
  local svc="${1:-}"
  [ -n "$svc" ] || die "is_first_time_deploy: usage: is_first_time_deploy <svc>"

  local target="${TARGET_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  [ -n "$target" ] || die "is_first_time_deploy: not inside a git repo"
  derive_azdo_context "$target"

  local iac_project; iac_project="$(discover_iac_project)"
  local iac_list iac_deploy_test_id
  iac_list=$(_nco_az pipelines list \
    --organization "$AZDO_ORG_URL" --project "$iac_project" \
    --query "[].[id,name]" -o tsv 2>/dev/null || true)
  iac_deploy_test_id=$(_v2_lookup_pipeline_id "$iac_list" "${AZDO_REPO}-${svc}-deploy-test")

  local count
  count=$(_v2_pipeline_succeeded_count "$iac_project" "$iac_deploy_test_id")
  [ "${count:-0}" -lt 1 ]
}

# discover_pipelines <svc>
# Echoes five lines of "<role>=<id>" — empty value when a pipeline doesn't
# exist in either project.
#
#   frontend_build=<id>     (project: the source repo's ADO project)
#   frontend_deploy=<id>    (same project)
#   iac_infra_build=<id>    (project: IaC)
#   iac_deploy_test=<id>    (project: IaC)
#   iac_deploy_prod=<id>    (project: IaC)
#
# Implementation: one `az pipelines list` call per project (just two HTTP
# requests total), then filter locally — much faster than five filtered
# queries and easier to stub in tests.
discover_pipelines() {
  local svc="${1:-}"
  [ -n "$svc" ] || die "discover_pipelines: usage: discover_pipelines <svc>"

  local target="${TARGET_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  [ -n "$target" ] \
    || die "discover_pipelines: not inside a git repo (cd into your target repo first)"

  derive_azdo_context "$target"

  local iac_project; iac_project="$(discover_iac_project)"
  local repo="$AZDO_REPO"

  local fp_list iac_list
  fp_list=$(_nco_az pipelines list \
    --organization "$AZDO_ORG_URL" --project "$AZDO_PROJECT" \
    --query "[].[id,name]" -o tsv 2>/dev/null || true)
  iac_list=$(_nco_az pipelines list \
    --organization "$AZDO_ORG_URL" --project "$iac_project" \
    --query "[].[id,name]" -o tsv 2>/dev/null || true)

  printf 'frontend_build=%s\n'  "$(_v2_lookup_pipeline_id "$fp_list"  "${repo}-${svc}-build")"
  printf 'frontend_deploy=%s\n' "$(_v2_lookup_pipeline_id "$fp_list"  "${repo}-${svc}-deploy")"
  printf 'iac_infra_build=%s\n' "$(_v2_lookup_pipeline_id "$iac_list" "${repo}-${svc}-infra-build")"
  printf 'iac_deploy_test=%s\n' "$(_v2_lookup_pipeline_id "$iac_list" "${repo}-${svc}-deploy-test")"
  printf 'iac_deploy_prod=%s\n' "$(_v2_lookup_pipeline_id "$iac_list" "${repo}-${svc}-deploy-prod")"
}

# derive_containerapp_name <svc>
# Pure string derivation. NO `az` calls — use this when you need the
# predicted name without verifying it exists in Azure.
#
# Convention: ca-<repo-prefix-lc>-<svc>
# repo-prefix-lc = first dash-segment of the source repo name, lowercased
# (e.g. ABC100001-myservice → abc100001 → ca-abc100001-<svc>).
derive_containerapp_name() {
  local svc="${1:-}"
  [ -n "$svc" ] || die "derive_containerapp_name: usage: derive_containerapp_name <svc>"

  local target="${TARGET_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
  [ -n "$target" ] \
    || die "derive_containerapp_name: not inside a git repo"

  derive_azdo_context "$target"

  local prefix="${AZDO_REPO%%-*}"
  prefix="$(printf '%s' "$prefix" | tr '[:upper:]' '[:lower:]')"
  printf 'ca-%s-%s' "$prefix" "$svc"
}

# discover_containerapp <svc>
# Best-effort lookup of the live container-app. Echoes three lines on
# success:
#
#   name=<container-app-name>
#   resource_group=<rg>
#   fqdn=<internal-fqdn>
#
# Resolution order:
#   (a) Honor explicit overrides: SVC_APP_NAME_OVERRIDE + SVC_RG_OVERRIDE
#       (FQDN unknown; emits empty).
#   (b) Query the IaC-declared common RG (IAC_COMMON_RESOURCE_GROUP_NAME).
#   (c) Fall back to a subscription-wide list using IAC_SUBSCRIPTION_ID.
#
# All failures `die` with a message naming the override env vars to set.
discover_containerapp() {
  local svc="${1:-}"
  [ -n "$svc" ] || die "discover_containerapp: usage: discover_containerapp <svc>"

  # Step (a): explicit overrides
  if [ -n "${SVC_APP_NAME_OVERRIDE:-}" ] && [ -n "${SVC_RG_OVERRIDE:-}" ]; then
    printf 'name=%s\n' "$SVC_APP_NAME_OVERRIDE"
    printf 'resource_group=%s\n' "$SVC_RG_OVERRIDE"
    printf 'fqdn=\n'
    return 0
  fi

  [ "${IAC__LOADED:-}" = "1" ] \
    || die "discover_containerapp: needs read_iac_variables to run first (or set SVC_APP_NAME_OVERRIDE + SVC_RG_OVERRIDE)"

  local derived; derived="$(derive_containerapp_name "$svc")"
  local common_rg="${IAC_COMMON_RESOURCE_GROUP_NAME:-}"
  local sub="${IAC_SUBSCRIPTION_ID:-}"
  local result

  # Step (b): query the IaC-declared common RG.
  if [ -n "$common_rg" ]; then
    result=$(_nco_az containerapp list \
      -g "$common_rg" \
      --query "[?name=='${derived}'] | [0].[name, resourceGroup, properties.configuration.ingress.fqdn]" \
      -o tsv 2>/dev/null | head -1)
    if [ -n "$result" ]; then
      _v2_emit_containerapp "$result"
      return 0
    fi
  fi

  # Step (c): subscription-wide fallback.
  if [ -n "$sub" ]; then
    result=$(_nco_az containerapp list \
      --subscription "$sub" \
      --query "[?name=='${derived}'] | [0].[name, resourceGroup, properties.configuration.ingress.fqdn]" \
      -o tsv 2>/dev/null | head -1)
    if [ -n "$result" ]; then
      _v2_emit_containerapp "$result"
      return 0
    fi
  fi

  die "discover_containerapp: could not find container app '${derived}' in RG '${common_rg}' or subscription '${sub}'.
Set SVC_APP_NAME_OVERRIDE=<name> and SVC_RG_OVERRIDE=<rg> to override."
}

# Parse a single TSV line of "<name>\t<rg>\t<fqdn>" into the public emit format.
_v2_emit_containerapp() {
  local line="$1" name rg fqdn
  IFS=$'\t' read -r name rg fqdn <<< "$line"
  printf 'name=%s\n' "$name"
  printf 'resource_group=%s\n' "$rg"
  printf 'fqdn=%s\n' "$fqdn"
}

# public_url_for <svc> <env>
# Returns the public URL ("<svc>.<DNS_ZONE_NAME>") when the service has
# ENABLE_PUBLIC_ENDPOINT: "true" in its config.<env>.yaml. Empty stdout +
# exit 0 when the service isn't public. Dies with a clear message if the
# required readers haven't been called first.
# find_pr_in_project <project> <repo> <source-branch>
# Echoes the first active PR id whose source ref is refs/heads/<source-branch>,
# or empty when none exists. Uses explicit --organization + --project so it
# works against any project (cross-project — e.g. IaC PR-B).
find_pr_in_project() {
  local project="${1:-}" repo="${2:-}" branch="${3:-}"
  [ -n "$project" ] && [ -n "$repo" ] && [ -n "$branch" ] \
    || die "find_pr_in_project: usage: find_pr_in_project <project> <repo> <source-branch>"

  _nco_az repos pr list \
    --organization "$AZDO_ORG_URL" --project "$project" \
    --repository "$repo" --status active \
    --query "[?sourceRefName=='refs/heads/${branch}'] | [0].pullRequestId" \
    -o tsv 2>/dev/null | head -1 | sed 's/^None$//'
}

# merge_pr_in_project <pr-id> <project> [<repo>]
# Self-approves (best-effort — many tenants forbid creators voting, errors
# ignored) then squash-completes the PR with source-branch deletion. Polls
# until terminal state (completed / abandoned). Always echoes a summary line.
# Returns 0 on completed, 1 on anything else.
#
# Cross-project safe: every az call uses explicit --organization + --project.
#
# Test-only env: NCO_WATCH_INTERVAL (poll interval in seconds; 0 = no sleep).
merge_pr_in_project() {
  local pr_id="${1:-}" project="${2:-}" repo="${3:-}"
  [ -n "$pr_id" ] && [ -n "$project" ] \
    || die "merge_pr_in_project: usage: merge_pr_in_project <pr-id> <project> [<repo>]"

  # Step 1: self-approve. Ignore errors (creator-can't-self-vote tenants).
  _nco_az repos pr set-vote \
    --organization "$AZDO_ORG_URL" --project "$project" \
    --id "$pr_id" --vote approve \
    >/dev/null 2>&1 || true

  # Step 2: squash-complete.
  if ! _nco_az repos pr update \
    --organization "$AZDO_ORG_URL" --project "$project" \
    --id "$pr_id" --status completed \
    --squash true --delete-source-branch true \
    --query status -o tsv >/dev/null 2>&1
  then
    printf 'merge_pr_in_project: failed to mark PR #%s completed (branch policy?)\n' "$pr_id" >&2
    return 1
  fi

  # Step 3: poll until terminal.
  local poll_interval="${NCO_WATCH_INTERVAL:-4}"
  local max_polls=30
  local i st=""
  for i in $(seq 1 "$max_polls"); do
    st=$(_nco_az repos pr show \
      --organization "$AZDO_ORG_URL" --project "$project" \
      --id "$pr_id" --query status -o tsv 2>/dev/null | head -1)
    case "$st" in
      completed)
        printf 'PR #%s completed\n' "$pr_id"
        return 0
        ;;
      abandoned)
        printf 'PR #%s was abandoned\n' "$pr_id" >&2
        return 1
        ;;
    esac
    [ "$poll_interval" -gt 0 ] && sleep "$poll_interval"
  done
  printf 'PR #%s did not complete (last status: %s)\n' "$pr_id" "${st:-unknown}" >&2
  return 1
}

public_url_for() {
  local svc="${1:-}" env="${2:-}"
  [ -n "$svc" ] && [ -n "$env" ] \
    || die "public_url_for: usage: public_url_for <svc> <env>"

  [ "${SVC_CFG__LOADED:-}" = "1" ] \
    || die "public_url_for: needs read_service_config to run first"
  [ "${IAC__LOADED:-}" = "1" ] \
    || die "public_url_for: needs read_iac_variables to run first"

  if [ "${SVC_CFG_ENABLE_PUBLIC_ENDPOINT:-}" != "true" ]; then
    return 0
  fi

  local dns="${IAC_DNS_ZONE_NAME:-}"
  [ -n "$dns" ] \
    || die "public_url_for: IAC_DNS_ZONE_NAME is empty (check IaC <env>.yaml)"

  printf '%s.%s' "$svc" "$dns"
}
