#!/usr/bin/env bash
# lib/azdo.sh — Azure DevOps target-repo derivation + az auth helpers.
#
# Every ADO-touching bin/ script sources this. After `derive_azdo_context`,
# the following globals are available:
#   AZDO_ORG       e.g. "AcmeCorp"
#   AZDO_ORG_URL   e.g. "https://dev.azure.com/AcmeCorp"
#   AZDO_PROJECT   e.g. "Platform"
#   AZDO_REPO      e.g. "some-app"
#
# Values come from parsing `git remote get-url origin` on the target repo.
# NO fallback to a hardcoded repo name — portability is non-negotiable.

[[ -n "${_NCO_AZDO_LOADED:-}" ]] && return 0
_NCO_AZDO_LOADED=1

_azdo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${_NCO_LOGGING_LOADED:-}"   ]] && . "$_azdo_dir/logging.sh"
[[ -z "${_NCO_UTILITIES_LOADED:-}" ]] && . "$_azdo_dir/utilities.sh"
unset _azdo_dir

# Derive AZDO_ORG / AZDO_ORG_URL / AZDO_PROJECT / AZDO_REPO from the target
# repo's 'origin' remote. Dies with a clear error on unrecognised URL.
derive_azdo_context() {
  local target_repo="${1:-}"
  [ -n "$target_repo" ] || die "derive_azdo_context: needs target repo path argument"

  local url
  url="$(git -C "$target_repo" remote get-url origin 2>/dev/null)" \
    || die "no 'origin' remote in $target_repo"

  # Strip trailing .git for cleaner regex.
  url="${url%.git}"

  # https://[user@]dev.azure.com/<org>/<project>/_git/<repo>
  if [[ "$url" =~ ^https://([^@/]+@)?dev\.azure\.com/([^/]+)/([^/]+)/_git/([^/]+)$ ]]; then
    AZDO_ORG="${BASH_REMATCH[2]}"
    AZDO_PROJECT="${BASH_REMATCH[3]}"
    AZDO_REPO="${BASH_REMATCH[4]}"
  # git@ssh.dev.azure.com:v3/<org>/<project>/<repo>
  elif [[ "$url" =~ ^git@ssh\.dev\.azure\.com:v3/([^/]+)/([^/]+)/([^/]+)$ ]]; then
    AZDO_ORG="${BASH_REMATCH[1]}"
    AZDO_PROJECT="${BASH_REMATCH[2]}"
    AZDO_REPO="${BASH_REMATCH[3]}"
  else
    die "remote URL doesn't look like Azure DevOps: $url
Expected one of:
  https://dev.azure.com/<org>/<project>/_git/<repo>
  git@ssh.dev.azure.com:v3/<org>/<project>/<repo>"
  fi
  AZDO_ORG_URL="https://dev.azure.com/$AZDO_ORG"
}

# Ensure az is installed, logged in, the azure-devops extension is present,
# and `az devops configure --defaults` is set to the derived context.
# Call this AFTER derive_azdo_context.
require_az() {
  require_cmd az
  az account show >/dev/null 2>&1 \
    || die "Not logged in to Azure. Run: az login"
  if ! az extension show --name azure-devops >/dev/null 2>&1; then
    log_info "Installing azure-devops extension..."
    az extension add --name azure-devops >/dev/null \
      || die "Failed to install azure-devops extension."
  fi
  az devops configure --defaults \
      organization="$AZDO_ORG_URL" project="$AZDO_PROJECT" \
      >/dev/null 2>&1 || true
}
