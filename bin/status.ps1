# bin/status.ps1 — show the status of an Azure DevOps pipeline run.
# NOTE: PowerShell port. Unverified on Mac.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "status"
$SCRIPT_DESCRIPTION = "Show the status of an Azure DevOps pipeline run."
$SCRIPT_USAGE       = "noclickops status <run-id>"
$SCRIPT_EXAMPLE     = "noclickops status 12345"
$SCRIPT_CATEGORY    = "inspect"
# --- end metadata ---

[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$RunId,
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

if (-not $RunId) { Die -Message "Usage: $SCRIPT_USAGE" }
if ($RunId -notmatch '^[0-9]+$') { Die -Message "Run id must be numeric: '$RunId'" }

if (-not $script:TARGET_REPO) { Die -Message "Not inside a git repository. cd into a repo and re-run." }

Derive-AzdoContext -TargetRepo $script:TARGET_REPO
Require-Az

$raw = & az pipelines runs show --id $RunId `
  --query "{name:definition.name, status:status, result:result, started:startTime, finished:finishTime}" `
  -o tsv

$fields  = $raw -split "`t"
$pipeline = $fields[0]
$status   = $fields[1]
$result   = if ($fields.Length -gt 2) { $fields[2] } else { '' }
$started  = if ($fields.Length -gt 3) { $fields[3] } else { '' }
$finished = if ($fields.Length -gt 4) { $fields[4] } else { '' }

$runUrl = "$($script:AZDO_ORG_URL)/$($script:AZDO_PROJECT)/_build/results?buildId=$RunId"

function IsSet { param([string]$v) return ($v -and $v -ne 'None') }

Write-Host ""
Write-Host "Run $RunId"
Write-Host "  Pipeline:  $pipeline"
Write-Host "  Status:    $status"
if (IsSet $result)   { Write-Host "  Result:    $result" }
if (IsSet $started)  { Write-Host "  Started:   $started" }
if (IsSet $finished) { Write-Host "  Finished:  $finished" }
Write-Host "  URL:       $runUrl"

exit 0
