# lib/azdo.ps1 — Azure DevOps target-repo derivation + az auth helpers.
# NOTE: PowerShell port. Unverified on Mac (no pwsh).
#
# After Derive-AzdoContext, the following script-scope vars are set:
#   $script:AZDO_ORG       e.g. "AcmeCorp"
#   $script:AZDO_ORG_URL   e.g. "https://dev.azure.com/AcmeCorp"
#   $script:AZDO_PROJECT   e.g. "Platform"
#   $script:AZDO_REPO      e.g. "some-app"

if ($script:NCO_AZDO_LOADED) { return }
$script:NCO_AZDO_LOADED = $true

. "$PSScriptRoot/logging.ps1"
. "$PSScriptRoot/utilities.ps1"

function Derive-AzdoContext {
  param([Parameter(Mandatory)][string]$TargetRepo)

  $url = & git -C $TargetRepo remote get-url origin 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $url) {
    Die -Message "no 'origin' remote in $TargetRepo"
  }
  # Strip trailing .git
  if ($url -match '\.git$') { $url = $url.Substring(0, $url.Length - 4) }

  if ($url -match '^https://(?:[^@/]+@)?dev\.azure\.com/([^/]+)/([^/]+)/_git/([^/]+)$') {
    $script:AZDO_ORG     = $Matches[1]
    $script:AZDO_PROJECT = $Matches[2]
    $script:AZDO_REPO    = $Matches[3]
  } elseif ($url -match '^git@ssh\.dev\.azure\.com:v3/([^/]+)/([^/]+)/([^/]+)$') {
    $script:AZDO_ORG     = $Matches[1]
    $script:AZDO_PROJECT = $Matches[2]
    $script:AZDO_REPO    = $Matches[3]
  } else {
    Die -Message @"
remote URL doesn't look like Azure DevOps: $url
Expected one of:
  https://dev.azure.com/<org>/<project>/_git/<repo>
  git@ssh.dev.azure.com:v3/<org>/<project>/<repo>
"@
  }
  $script:AZDO_ORG_URL = "https://dev.azure.com/$($script:AZDO_ORG)"
}

function Require-Az {
  Require-Cmd -Name az
  & az account show *> $null
  if ($LASTEXITCODE -ne 0) { Die -Message "Not logged in to Azure. Run: az login" }
  & az extension show --name azure-devops *> $null
  if ($LASTEXITCODE -ne 0) {
    Log-Info -Message "Installing azure-devops extension..."
    & az extension add --name azure-devops *> $null
    if ($LASTEXITCODE -ne 0) { Die -Message "Failed to install azure-devops extension." }
  }
  & az devops configure --defaults `
      organization=$($script:AZDO_ORG_URL) project=$($script:AZDO_PROJECT) *> $null
}

# Squash-complete a PR (v1.3.0). Shared between merge-pr and add-service's
# auto-merge path. Returns $true on completion, $false otherwise.
function Squash-CompletePr {
  param([Parameter(Mandatory)][string]$PrId)
  Log-Step -Message "Completing PR #$PrId (squash, delete source branch)"
  & az repos pr update --id $PrId --status completed `
      --squash true --delete-source-branch true `
      --query status -o tsv *> $null
  if ($LASTEXITCODE -ne 0) {
    Log-Error -Message "az repos pr update failed for PR #$PrId"
    return $false
  }

  Log-Info -Message "Waiting for completion..."
  $st = ''
  for ($i = 0; $i -lt 30; $i++) {
    $st = & az repos pr show --id $PrId --query status -o tsv
    if ($st -eq 'completed') { break }
    if ($st -eq 'abandoned') {
      Log-Error -Message "PR #$PrId was abandoned."
      return $false
    }
    Start-Sleep -Seconds 4
  }
  if ($st -ne 'completed') {
    Log-Error -Message "PR #$PrId did not complete (status: $st). Check branch policies."
    return $false
  }
  Log-Success -Message "PR #$PrId completed."
  return $true
}
