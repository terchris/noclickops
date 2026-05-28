#!/usr/bin/env bash
# lib/version.sh — local version + remote-check + update-hint helpers.
#
# Adopted from devcontainer-toolbox's manage/lib/version-utils.sh, with
# the addition of a 1-hour cache so the lister doesn't pay a curl
# roundtrip on every invocation.
#
# After nco_load_version + nco_check_remote:
#   NCO_VERSION         — local version (e.g. "1.0.0"; "unknown" on missing file)
#   NCO_REMOTE_VERSION  — set when remote differs from local, else empty
#
# Tests can stub the remote URL via NCO_VERSION_CHECK_URL.

[[ -n "${_NCO_VERSION_LOADED:-}" ]] && return 0
_NCO_VERSION_LOADED=1

_ver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${_NCO_PATHS_LOADED:-}" ]] && . "$_ver_dir/paths.sh"
unset _ver_dir

NCO_VERSION_CACHE_TTL="${NCO_VERSION_CACHE_TTL:-3600}"  # 1 hour

# Derive the version-check URL from $NOCLICKOPS_DIR's origin remote. The
# whole noclickops portability principle is "no hardcoded identity" — that
# rule applies to noclickops's OWN repo identity too. A fork at
# alice/noclickops checks alice's main, not terchris's.
#
# Supports:
#   https://github.com/<user>/<repo>(.git)?     → raw.githubusercontent.com/<user>/<repo>/main/version.txt
#   git@github.com:<user>/<repo>(.git)?         → same
#
# Returns empty (and we silently skip the version check) for any other
# shape — a local clone without an origin remote, an SCP-style alias that
# doesn't match the github.com host, or a non-GitHub upstream.
#
# Tests override via NCO_VERSION_CHECK_URL=file:///path/to/stub.
_nco_derive_check_url() {
  local url
  url="$(git -C "$NOCLICKOPS_DIR" remote get-url origin 2>/dev/null || true)"
  [ -n "$url" ] || return 1
  url="${url%.git}"

  local user_repo=""
  if [[ "$url" =~ ^https://github\.com/([^/]+/[^/]+)$ ]]; then
    user_repo="${BASH_REMATCH[1]}"
  elif [[ "$url" =~ ^git@github\.com:(.+)$ ]]; then
    user_repo="${BASH_REMATCH[1]}"
  else
    return 1
  fi
  printf 'https://raw.githubusercontent.com/%s/main/version.txt' "$user_repo"
}

# Read local version from $NOCLICKOPS_DIR/version.txt.
nco_load_version() {
  NCO_VERSION="unknown"
  local f="$NOCLICKOPS_DIR/version.txt"
  if [ -f "$f" ]; then
    NCO_VERSION="$(tr -d '[:space:]' < "$f" 2>/dev/null)"
    [ -n "$NCO_VERSION" ] || NCO_VERSION="unknown"
  fi
}

# Check the remote for a newer version. Sets NCO_REMOTE_VERSION (empty if
# remote == local or any failure). Uses cache to avoid every-call latency.
nco_check_remote() {
  NCO_REMOTE_VERSION=""

  local cache="$NOCLICKOPS_DIR/.version-cache"
  local now cached_at cached_ver

  # Try cache first.
  if [ -f "$cache" ]; then
    local line
    line="$(head -1 "$cache" 2>/dev/null || true)"
    cached_at="${line%% *}"
    cached_ver="${line#* }"
    case "$cached_at" in
      ''|*[!0-9]*) : ;;   # malformed → fall through to network
      *)
        now="$(date +%s)"
        if [ "$((now - cached_at))" -lt "$NCO_VERSION_CACHE_TTL" ]; then
          if [ -n "$cached_ver" ] && [ "$cached_ver" != "$NCO_VERSION" ]; then
            NCO_REMOTE_VERSION="$cached_ver"
          fi
          return 0
        fi
        ;;
    esac
  fi

  # Cache miss or expired — hit the network.
  command -v curl >/dev/null 2>&1 || return 0

  # Env override wins; otherwise derive from origin. If neither is set,
  # silently no-op (e.g. detached clone with no remote).
  local url="${NCO_VERSION_CHECK_URL:-}"
  if [ -z "$url" ]; then
    url="$(_nco_derive_check_url)" || return 0
  fi

  local remote
  remote="$(curl -fsSL --connect-timeout 2 --max-time 4 \
              "$url" 2>/dev/null \
              | tr -d '[:space:]' || true)"

  if [ -n "$remote" ]; then
    # Write cache (failure is fine; just means we'll re-fetch next time).
    printf '%s %s\n' "$(date +%s)" "$remote" > "$cache" 2>/dev/null || true
    [ "$remote" != "$NCO_VERSION" ] && NCO_REMOTE_VERSION="$remote"
  fi
}

# Print the "⬆ Update available" hint if a remote update is known.
# Idempotent: safe to call even if nco_check_remote wasn't reached.
nco_show_update_hint() {
  [ -n "${NCO_REMOTE_VERSION:-}" ] || return 0
  printf "\n${_NCO_YELLOW:-}⬆${_NCO_NC:-} Update available: v%s — run 'noclickops update'\n" \
    "$NCO_REMOTE_VERSION"
}

# Clear the cache. Call after a successful update so the next lister
# invocation sees fresh state.
nco_clear_version_cache() {
  rm -f "$NOCLICKOPS_DIR/.version-cache" 2>/dev/null || true
}
