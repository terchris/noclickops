# bin/noclickops.ps1 — list all noclickops commands, grouped by category.
# NOTE: PowerShell port. Unverified on Mac.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "noclickops"
$SCRIPT_DESCRIPTION = "List all noclickops commands grouped by category."
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
. "$PSScriptRoot/../lib/version.ps1"

if ($Help) {
  Show-Help -Path $PSCommandPath
  exit 0
}

Nco-LoadVersion
Nco-CheckRemote

# Section titles in canonical order.
$sections = [ordered]@{
  'meta'              = 'Meta'
  'git'               = 'Git / pull requests'
  'deploy'            = 'Deployment'
  'service-lifecycle' = 'Service lifecycle'
  'inspect'           = 'Inspect / observe'
}

# Group commands.
$grouped = @{}
foreach ($cat in $sections.Keys) { $grouped[$cat] = @() }

Get-ChildItem -Path $script:BIN_DIR -Filter *.ps1 | ForEach-Object {
  $cmd  = $_.BaseName
  $meta = Parse-Metadata -Path $_.FullName
  if (-not $meta) { return }
  $desc = if ($meta['SCRIPT_DESCRIPTION']) { $meta['SCRIPT_DESCRIPTION'] } else { '(no description)' }
  $cat  = if ($meta['SCRIPT_CATEGORY']) { $meta['SCRIPT_CATEGORY'] } else { 'meta' }
  if (-not $grouped.ContainsKey($cat)) { $cat = 'meta' }
  $grouped[$cat] += "  {0,-15} {1}" -f $cmd, $desc
}

Write-Host ""
Write-Host "noclickops v$($script:NCO_VERSION)" -ForegroundColor White
Write-Host "  portable script suite for developers"
Write-Host "  Install: $script:NOCLICKOPS_DIR"

foreach ($cat in $sections.Keys) {
  $lines = $grouped[$cat]
  if ($lines.Count -eq 0) { continue }
  Write-Host ""
  Write-Host $sections[$cat] -ForegroundColor White
  $lines | ForEach-Object { Write-Host $_ }
}

Write-Host ""
Write-Host "Run 'noclickops <cmd> -Help' for usage details, e.g.:"
Write-Host "  noclickops update -Help"

Nco-ShowUpdateHint
