# bin/deploy.ps1 — trigger a service's CD pipeline.
# NOTE: PowerShell port. Unverified on Mac.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "deploy"
$SCRIPT_DESCRIPTION = "Trigger a service's CD pipeline (test or prod)."
$SCRIPT_USAGE       = "noclickops deploy <service> [test|prod] [--watch]"
$SCRIPT_EXAMPLE     = "noclickops deploy test-holderdeord test --watch"
$SCRIPT_CATEGORY    = "deploy"
# --- end metadata ---

[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Service,
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest = @(),
  [switch]$Help
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../lib/logging.ps1"
. "$PSScriptRoot/../lib/utilities.ps1"
. "$PSScriptRoot/../lib/paths.ps1"
. "$PSScriptRoot/../lib/metadata.ps1"
. "$PSScriptRoot/../lib/azdo.ps1"

if ($Help) {
  Show-Help -Path $PSCommandPath
  exit 0
}

if (-not $Service) { Die -Message "Usage: $SCRIPT_USAGE" }

$envName = 'test'
$watch = $false
foreach ($a in $Rest) {
  switch ($a) {
    'test'    { $envName = 'test' }
    'prod'    { $envName = 'prod' }
    '--watch' { $watch = $true }
    default   { Die -Message "Unknown argument: $a (expected test|prod or --watch)" }
  }
}

if (-not $script:TARGET_REPO) { Die -Message "Not inside a git repository. cd into a repo and re-run." }

$serviceDir = Join-Path (Join-Path $script:TARGET_REPO 'services') $Service
if (-not (Test-Path $serviceDir)) {
  $servicesDir = Join-Path $script:TARGET_REPO 'services'
  if (Test-Path $servicesDir) {
    $available = (Get-ChildItem -Path $servicesDir -Directory | ForEach-Object { "  $($_.Name)" }) -join "`n"
    Die -Message "Service '$Service' not found at $serviceDir.`nAvailable services:`n$available"
  } else {
    Die -Message "Service '$Service' not found and $script:TARGET_REPO has no 'services/' directory."
  }
}

Derive-AzdoContext -TargetRepo $script:TARGET_REPO
Require-Az

$pipeline = "$($script:AZDO_REPO)-$Service-CD"
Log-Step -Message "Deploying '$Service' to '$envName'  (pipeline: $pipeline)"

$runId = & az pipelines run --name $pipeline --branch refs/heads/main `
  --parameters "targetEnvironment=$envName" --query id -o tsv
$runUrl = "$($script:AZDO_ORG_URL)/$($script:AZDO_PROJECT)/_build/results?buildId=$runId"

Log-Success -Message "Started run $runId"
Write-Host "  $runUrl"

if ($watch) {
  Log-Info -Message "Watching (Ctrl-C to stop watching; the run keeps going)..."
  for ($i = 0; $i -lt 90; $i++) {
    $st = & az pipelines runs show --id $runId --query status -o tsv
    if ($st -eq 'completed') {
      $res = & az pipelines runs show --id $runId --query result -o tsv
      if ($res -eq 'succeeded') {
        Log-Success -Message "Deploy succeeded (run $runId)."
        exit 0
      } else {
        Die -Message "Deploy finished with result '$res'. See: $runUrl"
      }
    }
    Start-Sleep -Seconds 20
  }
  Log-Warn -Message "Timed out after 30min watching run $runId. The run keeps going; check: $runUrl"
}
