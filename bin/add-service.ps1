# bin/add-service.ps1 — trigger the Copier-based add-service pipeline.
# NOTE: PowerShell port. Unverified on Mac.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "add-service"
$SCRIPT_DESCRIPTION = "Trigger the add-service pipeline to scaffold a new service."
$SCRIPT_USAGE       = "noclickops add-service <service-name> [--persistent-storage] [--no-public-endpoint] [--watch]"
$SCRIPT_EXAMPLE     = "noclickops add-service test-myapp --watch"
$SCRIPT_CATEGORY    = "service-lifecycle"
# --- end metadata ---

[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Service,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @(),
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

$persistent = 'false'
$public     = 'true'
$watch      = $false
foreach ($a in $Rest) {
  switch ($a) {
    '--persistent-storage' { $persistent = 'true' }
    '--no-public-endpoint' { $public = 'false' }
    '--watch'              { $watch = $true }
    default {
      if ($a.StartsWith('-')) {
        Die -Message "Unknown flag: $a (expected --persistent-storage, --no-public-endpoint, or --watch)"
      } else {
        Die -Message "Unexpected positional argument: $a (only the service name is positional)"
      }
    }
  }
}

# Service-name shape validation.
if ($Service.StartsWith('-'))   { Die -Message "Service name '$Service' must not start with '-'." }
if ($Service -match '[/\\]')    { Die -Message "Service name '$Service' must not contain path separators." }
if ($Service -match '\s')       { Die -Message "Service name '$Service' must not contain whitespace." }
if ($Service.Length -gt 50)     { Die -Message "Service name '$Service' is too long (max 50 chars)." }

if (-not $script:TARGET_REPO) { Die -Message "Not inside a git repository. cd into a repo and re-run." }

$svcDir = Join-Path (Join-Path $script:TARGET_REPO 'services') $Service
if (Test-Path $svcDir) {
  Die -Message @"
Service folder already exists: $svcDir
If you meant to update it instead of create, use 'noclickops sync-lovable' or your editor.
"@
}

Derive-AzdoContext -TargetRepo $script:TARGET_REPO
Require-Az

$pipeline = "$($script:AZDO_REPO)-add-service"
Log-Step -Message "Triggering '$pipeline' to scaffold '$Service'"
Log-Info -Message "  persistent_storage=$persistent  public_endpoint=$public"

$runId = & az pipelines run --name $pipeline --branch refs/heads/main `
  --parameters "serviceName=$Service" "persistent_storage=$persistent" "public_endpoint=$public" `
  --query id -o tsv

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
        Log-Success -Message "add-service pipeline succeeded."
        Write-Host ""
        Write-Host "Next steps:"
        Write-Host "  1. The pipeline opened a PR titled 'Add service $Service'."
        Write-Host "  2. Review the diff, then complete with:  noclickops merge-pr <id>"
        Write-Host "  3. After merge, customise the service: 'noclickops clean-sample $Service'"
        Write-Host "     and/or 'noclickops sync-lovable <lovable-repo> $Service'."
        Write-Host "  4. Deploy with:  noclickops deploy $Service test --watch"
        exit 0
      } else {
        Die -Message "add-service finished with result '$res'. See: $runUrl"
      }
    }
    Start-Sleep -Seconds 20
  }
  Log-Warn -Message "Timed out after 30min watching run $runId. The run keeps going; check: $runUrl"
} else {
  Write-Host ""
  Write-Host "Next steps:"
  Write-Host "  1. Wait for the pipeline to finish (or re-run with --watch)."
  Write-Host "  2. It opens PR 'Add service $Service' on completion — merge with:"
  Write-Host "       noclickops merge-pr <id>"
  Write-Host "  3. Customise the service and deploy."
}
