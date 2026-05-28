# bin/clean-sample.ps1 — strip the Next.js Copier sample from a service.
# NOTE: PowerShell port. Unverified on Mac.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "clean-sample"
$SCRIPT_DESCRIPTION = "Remove the Next.js sample app from a service folder."
$SCRIPT_USAGE       = "noclickops clean-sample <service>"
$SCRIPT_EXAMPLE     = "noclickops clean-sample test-myapp"
$SCRIPT_CATEGORY    = "service-lifecycle"
# --- end metadata ---

[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Service,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../lib/logging.ps1"
. "$PSScriptRoot/../lib/utilities.ps1"
. "$PSScriptRoot/../lib/paths.ps1"
. "$PSScriptRoot/../lib/metadata.ps1"

if ($Help) {
  Show-Help -Path $PSCommandPath
  exit 0
}

if (-not $Service) { Die -Message "Usage: $SCRIPT_USAGE" }
if (-not $script:TARGET_REPO) { Die -Message "Not inside a git repository. cd into a repo and re-run." }
Set-Location $script:TARGET_REPO

$dir = "services/$Service"
if (-not (Test-Path $dir)) { Die -Message "No such service folder: $dir" }

$sample = @('app', 'components', 'public', 'package.json', 'package-lock.json', 'next.config.mjs')
$marker = Join-Path $dir 'components/control-panel.js'

if (-not (Test-Path $marker)) {
  $any = $false
  foreach ($p in $sample) { if (Test-Path (Join-Path $dir $p)) { $any = $true; break } }
  if (-not $any) {
    Log-Success -Message "$dir is already clean (no sample app present)."
    exit 0
  }
  Die -Message @"
$dir doesn't look like the unmodified Next.js sample (missing components/control-panel.js).
Refusing to auto-delete in case it contains real code. Remove files manually if you are sure.
"@
}

Log-Step -Message "Removing the Next.js sample app from $dir"
foreach ($p in $sample) {
  $target = Join-Path $dir $p
  if (-not (Test-Path $target)) { continue }
  & git ls-files --error-unmatch $target *> $null
  if ($LASTEXITCODE -eq 0) {
    & git rm -rq $target
  } else {
    Remove-Item -Recurse -Force $target
  }
  Log-Info -Message "removed $p"
}

Write-Host ""
Log-Success -Message "Done."
Write-Host "  Kept platform scaffolding: Dockerfile, service.yaml, .pipelines/, bicep/, README.md."
Write-Host "  Next: add the real app, adapt the Dockerfile, ensure /health + SERVICE_PORT, then deploy."
