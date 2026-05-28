# bin/create-pr.ps1 — open an Azure DevOps PR from the current branch to main.
# NOTE: PowerShell port. Unverified on Mac.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "create-pr"
$SCRIPT_DESCRIPTION = "Open an Azure DevOps PR from the current branch to main."
$SCRIPT_USAGE       = "noclickops create-pr `"<title>`" [`"<description>`"]"
$SCRIPT_EXAMPLE     = "noclickops create-pr `"feat: add login flow`""
$SCRIPT_CATEGORY    = "git"
# --- end metadata ---

[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Title,
  [Parameter(Position = 1)][string]$Description,
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

if (-not $Title) { Die -Message "Usage: $SCRIPT_USAGE" }
if (-not $Description) { $Description = $Title }

if (-not $script:TARGET_REPO) { Die -Message "Not inside a git repository. cd into a repo and re-run." }
Set-Location $script:TARGET_REPO

$branch = & git rev-parse --abbrev-ref HEAD
if ($branch -eq 'main') {
  Die -Message "You are on main. Create a feature branch first:`n  git checkout -b feature/<name>"
}

Derive-AzdoContext -TargetRepo $script:TARGET_REPO
Require-Az

# Push + set upstream if no tracking ref yet.
& git rev-parse --abbrev-ref --symbolic-full-name '@{u}' *> $null
if ($LASTEXITCODE -ne 0) {
  Log-Info -Message "Pushing $branch to origin (setting upstream)..."
  & git push -u origin $branch
}

Log-Step -Message "Creating PR '$Title' ($branch → main) in $($script:AZDO_REPO)"

$prId = & az repos pr create --repository $script:AZDO_REPO `
  --source-branch $branch --target-branch main `
  --title $Title --description $Description `
  --query pullRequestId -o tsv

Log-Success -Message "Created PR #$prId"
Write-Host "  $($script:AZDO_ORG_URL)/$($script:AZDO_PROJECT)/_git/$($script:AZDO_REPO)/pullrequest/$prId"
Write-Host ""
Log-Info -Message "Next: noclickops merge-pr $prId"
