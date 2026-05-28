# bin/noclickops.ps1 — list all noclickops commands (PLAN-001 stub).
# NOTE: PowerShell port. Unverified on Mac.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "noclickops"
$SCRIPT_DESCRIPTION = "List all noclickops commands and their descriptions."
$SCRIPT_USAGE       = "noclickops [<subcommand> [args...]]"
$SCRIPT_EXAMPLE     = "noclickops"
$SCRIPT_CATEGORY    = "meta"
# --- end metadata ---

[CmdletBinding()]
param([switch]$Help)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../lib/logging.ps1"
. "$PSScriptRoot/../lib/paths.ps1"
. "$PSScriptRoot/../lib/metadata.ps1"

if ($Help) {
  Show-Help -Path $PSCommandPath
  exit 0
}

Write-Host ""
Write-Host "noclickops" -ForegroundColor White
Write-Host "  portable script suite for developers"
Write-Host "  Install: $script:NOCLICKOPS_DIR"
Write-Host ""
Write-Host "Available commands:"
Write-Host ""

Get-ChildItem -Path $script:BIN_DIR -Filter *.ps1 | ForEach-Object {
  $cmdName = $_.BaseName
  $meta = Parse-Metadata -Path $_.FullName
  if ($meta) {
    $desc = if ($meta['SCRIPT_DESCRIPTION']) { $meta['SCRIPT_DESCRIPTION'] } else { '(no description)' }
    "  {0,-15} {1}" -f $cmdName, $desc
  }
}

Write-Host ""
Write-Host "Run with -Help on any command for usage details, e.g.:"
Write-Host "  $script:BIN_DIR/update.ps1 -Help"
Write-Host ""
Write-Host "NOTE: PLAN-001 ships this foundation. PLAN-002 adds:"
Write-Host "  - one-line install"
Write-Host "  - typeable 'noclickops <subcommand>' form via shell function"
Write-Host "  - category-grouped listing"
