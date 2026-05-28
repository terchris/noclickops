# bin/update.ps1 — pull the latest noclickops from origin.
# NOTE: PowerShell port. Unverified on Mac.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "update"
$SCRIPT_DESCRIPTION = "Pull the latest noclickops from origin (fast-forward only)."
$SCRIPT_USAGE       = "noclickops update"
$SCRIPT_EXAMPLE     = "noclickops update"
$SCRIPT_CATEGORY    = "meta"
# --- end metadata ---

[CmdletBinding()]
param([switch]$Help)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../lib/logging.ps1"
. "$PSScriptRoot/../lib/utilities.ps1"
. "$PSScriptRoot/../lib/paths.ps1"
. "$PSScriptRoot/../lib/metadata.ps1"

if ($Help) {
  Show-Help -Path $PSCommandPath
  exit 0
}

Require-Cmd -Name git

Log-Step -Message "Updating noclickops at $script:NOCLICKOPS_DIR"

if (-not (Test-Path (Join-Path $script:NOCLICKOPS_DIR ".git"))) {
  Die -Message "$script:NOCLICKOPS_DIR is not a git checkout. Re-install via PLAN-002's installer."
}

& git -C $script:NOCLICKOPS_DIR pull --ff-only
if ($LASTEXITCODE -ne 0) {
  Die -Message "git pull failed in $script:NOCLICKOPS_DIR — resolve manually, then re-run."
}

Log-Success -Message "noclickops is up to date."
