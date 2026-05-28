# bin/sync-lovable.ps1 — DEFERRED FOR v1.
#
# The rsync-based mirror semantics in bin/sync-lovable.sh are non-trivial to
# reproduce reliably in PowerShell (robocopy excludes don't map 1:1; Copy-Item
# can't easily delete extraneous receiver files matching the rsync --delete
# behaviour). Rather than ship a half-working port that risks deleting real
# code, v1 steers Windows users to bash.
#
# Workarounds for Windows users:
#   1. Run from Git Bash:    ~/.noclickops/bin/sync-lovable.sh <src> <service>
#   2. Run from WSL:         wsl ~/.noclickops/bin/sync-lovable.sh <src> <service>
#
# Native PowerShell port is a future PLAN.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "sync-lovable"
$SCRIPT_DESCRIPTION = "Sync a Lovable repo into a service folder (bash required for v1)."
$SCRIPT_USAGE       = "noclickops sync-lovable <lovable-repo-path> <service>"
$SCRIPT_EXAMPLE     = "noclickops sync-lovable ~/learn/helpers/holderdeord test-holderdeord"
$SCRIPT_CATEGORY    = "service-lifecycle"
# --- end metadata ---

[CmdletBinding()]
param([switch]$Help)

. "$PSScriptRoot/../lib/logging.ps1"
. "$PSScriptRoot/../lib/utilities.ps1"
. "$PSScriptRoot/../lib/paths.ps1"
. "$PSScriptRoot/../lib/metadata.ps1"

if ($Help) {
  Show-Help -Path $PSCommandPath
  exit 0
}

Log-Error -Message @"
sync-lovable v1 requires bash. Native PowerShell support is deferred.

Run instead from Git Bash or WSL:
  ~/.noclickops/bin/sync-lovable.sh <lovable-repo-path> <service>

See PLAN-006 for the rationale.
"@
exit 1
