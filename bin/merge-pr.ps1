# bin/merge-pr.ps1 — squash-complete an Azure DevOps PR, sync local main,
# delete the local feature branch.
# NOTE: PowerShell port. Unverified on Mac.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "merge-pr"
$SCRIPT_DESCRIPTION = "Squash-complete a PR, sync local main, delete the feature branch."
$SCRIPT_USAGE       = "noclickops merge-pr <pr-id>"
$SCRIPT_EXAMPLE     = "noclickops merge-pr 4779"
$SCRIPT_CATEGORY    = "git"
# --- end metadata ---

[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$PrId,
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

if (-not $PrId) { Die -Message "Usage: $SCRIPT_USAGE" }

if (-not $script:TARGET_REPO) { Die -Message "Not inside a git repository. cd into a repo and re-run." }
Set-Location $script:TARGET_REPO

Derive-AzdoContext -TargetRepo $script:TARGET_REPO
Require-Az

Log-Step -Message "Completing PR #$PrId (squash, delete source branch)"
& az repos pr update --id $PrId --status completed `
    --squash true --delete-source-branch true `
    --query status -o tsv *> $null

Log-Info -Message "Waiting for completion..."
$st = ''
for ($i = 0; $i -lt 30; $i++) {
  $st = & az repos pr show --id $PrId --query status -o tsv
  if ($st -eq 'completed') { break }
  if ($st -eq 'abandoned') { Die -Message "PR #$PrId was abandoned." }
  Start-Sleep -Seconds 4
}
if ($st -ne 'completed') { Die -Message "PR #$PrId did not complete (status: $st). Check branch policies." }
Log-Success -Message "PR #$PrId completed."

$feature = & git rev-parse --abbrev-ref HEAD
Log-Step -Message "Syncing local main and cleaning up"
& git checkout main
& git fetch --prune

& git merge --ff-only origin/main *> $null
if ($LASTEXITCODE -eq 0) {
  if ($feature -ne 'main') {
    & git branch -D $feature *> $null
    if ($LASTEXITCODE -eq 0) { Log-Success -Message "Deleted local branch $feature" }
  }
  Log-Success -Message "Local main is in sync with origin/main."
} else {
  Log-Warn -Message "Local main diverged from origin/main and can't fast-forward."
  Write-Host "  Local main likely has unpushed commits."
  Write-Host "  If local main has nothing worth keeping:  git reset --hard origin/main"
}
