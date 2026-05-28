# bin/add-service.ps1 — trigger the add-service pipeline + auto-merge.
# NOTE: PowerShell port. Unverified on Mac.
#
# v1.3.0 (PLAN-102): default behavior is watch + auto-merge. --no-merge
# restores PLAN-007a's fire-and-forget for callers that want it.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "add-service"
$SCRIPT_DESCRIPTION = "Scaffold a new service (Copier pipeline + auto-merge the PR)."
$SCRIPT_USAGE       = "noclickops add-service <service-name> [--persistent-storage] [--no-public-endpoint] [--no-merge]"
$SCRIPT_EXAMPLE     = "noclickops add-service test-myapp --persistent-storage"
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
$noMerge    = $false
foreach ($a in $Rest) {
  switch ($a) {
    '--persistent-storage' { $persistent = 'true' }
    '--no-public-endpoint' { $public = 'false' }
    '--no-merge'           { $noMerge = $true }
    default {
      if ($a.StartsWith('-')) {
        Die -Message "Unknown flag: $a (expected --persistent-storage, --no-public-endpoint, or --no-merge)"
      } else {
        Die -Message "Unexpected positional argument: $a (only the service name is positional)"
      }
    }
  }
}

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

# --- Fire-and-forget (--no-merge) ---
if ($noMerge) {
  Write-Host ""
  Write-Host "Fire-and-forget mode (--no-merge). The shell returns now."
  Write-Host ""
  Write-Host "Check progress any time:"
  Write-Host "  noclickops status $runId"
  Write-Host ""
  Write-Host "Then merge the resulting PR manually:"
  Write-Host "  noclickops merge-pr <pr-id>"
  exit 0
}

# --- Watch the pipeline ---
Log-Step -Message "Watching pipeline (poll every 5s, 10 min cap)"
$st = ''
for ($i = 0; $i -lt 120; $i++) {
  $st = & az pipelines runs show --id $runId --query status -o tsv 2>$null
  if ($st -eq 'completed') { break }
  Start-Sleep -Seconds 5
}

if ($st -ne 'completed') {
  Log-Warn -Message "Pipeline didn't complete within 10 minutes (status: $st). It keeps running."
  Write-Host "  Re-attach later: noclickops status $runId"
  exit 1
}

$result = & az pipelines runs show --id $runId --query result -o tsv
if ($result -ne 'succeeded') {
  Die -Message "Pipeline finished with result '$result'. See: $runUrl"
}
Log-Success -Message "Pipeline succeeded (run $runId)."

# --- Find the scaffold PR ---
Log-Step -Message "Looking up the scaffold PR (source: add-service-$Service)"
$prId = & az repos pr list --status active `
  --query "[?sourceRefName=='refs/heads/add-service-$Service'] | [0].pullRequestId" `
  -o tsv 2>$null

if (-not $prId -or $prId -eq 'None') {
  Log-Warn -Message "No active PR found for branch add-service-$Service."
  Log-Warn -Message "Either Copier had nothing to commit, or the PR was completed/abandoned out-of-band."
  Write-Host "  Check the pipeline log: $runUrl"
  exit 0
}
Log-Info -Message "Found PR #$prId"

# --- Squash-merge ---
if (-not (Squash-CompletePr -PrId $prId)) {
  Log-Error -Message "Failed to merge PR #$prId."
  Write-Host "  PR URL: $($script:AZDO_ORG_URL)/$($script:AZDO_PROJECT)/_git/$($script:AZDO_REPO)/pullrequest/$prId"
  exit 1
}

# --- Sync local main ---
Log-Step -Message "Syncing local main"
& git -C $script:TARGET_REPO fetch --prune
& git -C $script:TARGET_REPO merge --ff-only origin/main *> $null
if ($LASTEXITCODE -eq 0) {
  Log-Success -Message "Local main is in sync with origin/main."
} else {
  Log-Warn -Message "Local main can't fast-forward — it has diverged from origin/main."
  Write-Host "  If local main has nothing worth keeping:  git reset --hard origin/main"
}

Write-Host ""
Log-Success -Message "Done. services/$Service is on main."
Write-Host ""
Write-Host "Next steps:"
Write-Host "  noclickops clean-sample $Service                # strip the Next.js placeholder"
Write-Host "  noclickops sync-lovable <lovable-repo> $Service # (if syncing a Lovable app)"
Write-Host "  noclickops deploy $Service test --watch         # deploy to test"
