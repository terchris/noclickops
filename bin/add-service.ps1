# bin/add-service.ps1 — trigger the Copier-based add-service pipeline.
# NOTE: PowerShell port. Unverified on Mac.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "add-service"
$SCRIPT_DESCRIPTION = "Trigger the add-service pipeline to scaffold a new service."
$SCRIPT_USAGE       = "noclickops add-service <service-name> [--persistent-storage] [--no-public-endpoint]"
$SCRIPT_EXAMPLE     = "noclickops add-service test-myapp"
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
foreach ($a in $Rest) {
  switch ($a) {
    '--persistent-storage' { $persistent = 'true' }
    '--no-public-endpoint' { $public = 'false' }
    default {
      if ($a.StartsWith('-')) {
        Die -Message "Unknown flag: $a (expected --persistent-storage or --no-public-endpoint)"
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

# Fire-and-forget; add-service takes ~1h. Watching is hostile — use
# 'noclickops status $runId' later instead.
Write-Host ""
Write-Host "This pipeline takes ~1 hour. The shell returns now."
Write-Host ""
Write-Host "Check progress any time:"
Write-Host "  noclickops status $runId"
Write-Host ""
Write-Host "When the run completes, the pipeline will have opened PR 'Add service $Service'."
Write-Host "Then:"
Write-Host "  noclickops merge-pr <pr-id>                          # squash + sync"
Write-Host "  noclickops clean-sample $Service                      # (if removing the sample)"
Write-Host "  noclickops sync-lovable <lovable-repo> $Service       # (if syncing a Lovable app)"
Write-Host "  noclickops deploy $Service test --watch               # deploy to test"
