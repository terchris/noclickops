# bin/logs.ps1 — show or stream a service's container-app logs.
# NOTE: PowerShell port. Unverified on Mac.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "logs"
$SCRIPT_DESCRIPTION = "Show or stream the container-app logs for a service."
$SCRIPT_USAGE       = "noclickops logs <service> [test|prod] [-Follow] [-Tail N] [-System]"
$SCRIPT_EXAMPLE     = "noclickops logs test-holderdeord test -Follow"
$SCRIPT_CATEGORY    = "inspect"
# --- end metadata ---

[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Service,
  [Parameter(Position = 1)][string]$EnvName = 'test',
  [switch]$Follow,
  [int]$Tail = 100,
  [switch]$System,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../lib/logging.ps1"
. "$PSScriptRoot/../lib/utilities.ps1"
. "$PSScriptRoot/../lib/paths.ps1"
. "$PSScriptRoot/../lib/metadata.ps1"
. "$PSScriptRoot/../lib/service.ps1"

if ($Help) {
  Show-Help -Path $PSCommandPath
  exit 0
}

if (-not $Service) { Die -Message "Usage: $SCRIPT_USAGE" }
if ($Tail -lt 1)   { Die -Message "-Tail must be a positive integer" }
if (-not $script:TARGET_REPO) { Die -Message "Not inside a git repository. cd into a repo and re-run." }

Resolve-ServiceContext -Service $Service -EnvName $EnvName -TargetRepo $script:TARGET_REPO

Require-Cmd -Name az
& az account show *> $null
if ($LASTEXITCODE -ne 0) { Die -Message "Not logged in to Azure. Run: az login" }

if (-not (Try-AzSubscription -SubscriptionId $script:SVC_SUBSCRIPTION_ID)) { exit 1 }

$appName = & az containerapp list `
  --subscription $script:SVC_SUBSCRIPTION_ID `
  --resource-group $script:SVC_RESOURCE_GROUP `
  --query "[?contains(name, '$($script:SVC_NAME)')] | [0].name" `
  -o tsv 2>$null

if (-not $appName -or $appName -eq 'None') {
  Die -Message @"
No container app found in $($script:SVC_RESOURCE_GROUP) matching '$($script:SVC_NAME)'.
Has it been deployed yet?  noclickops deploy $($script:SVC_NAME) $($script:SVC_ENV) --watch
"@
}

$argv = @(
  'containerapp', 'logs', 'show',
  '--name', $appName,
  '--resource-group', $script:SVC_RESOURCE_GROUP,
  '--subscription', $script:SVC_SUBSCRIPTION_ID,
  '--tail', $Tail
)
if ($Follow) { $argv += '--follow' }
if ($System) { $argv += @('--type', 'system') }

$desc = "(env: $($script:SVC_ENV), tail: $Tail"
if ($Follow) { $desc += ', follow' }
if ($System) { $desc += ', system' }
$desc += ')'
Log-Info -Message "Container app: $appName $desc"

& az @argv
exit $LASTEXITCODE
