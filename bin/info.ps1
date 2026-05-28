# bin/info.ps1 — show config + live container-app state for a service in an env.
# NOTE: PowerShell port. Unverified on Mac.
#
# --- noclickops metadata ---
$SCRIPT_NAME        = "info"
$SCRIPT_DESCRIPTION = "Show service config and live container-app state."
$SCRIPT_USAGE       = "noclickops info <service> [test|prod]"
$SCRIPT_EXAMPLE     = "noclickops info test-holderdeord test"
$SCRIPT_CATEGORY    = "inspect"
# --- end metadata ---

[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Service,
  [Parameter(Position = 1)][string]$EnvName = 'test',
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
if (-not $script:TARGET_REPO) { Die -Message "Not inside a git repository. cd into a repo and re-run." }

Resolve-ServiceContext -Service $Service -EnvName $EnvName -TargetRepo $script:TARGET_REPO

Write-Host ""
Write-Host "Service: $($script:SVC_NAME) ($($script:SVC_ENV))" -ForegroundColor White
Write-Host "────────────────────────────────────────"
Write-Host "  Folder:            $($script:SVC_DIR)"
Write-Host "  APP_NAME:          $($script:SVC_APP_NAME)"
Write-Host "  ENVIRONMENT:       $($script:SVC_ENVIRONMENT)"
Write-Host "  SUBSCRIPTION_ID:   $($script:SVC_SUBSCRIPTION_ID)"
Write-Host "  Resource group:    $($script:SVC_RESOURCE_GROUP)"
Write-Host "  Common RG:         $($script:SVC_COMMON_RG)"

Write-Host ""
Write-Host "Service config:" -ForegroundColor White
Write-Host "  Port:              $($script:SVC_PORT)"
Write-Host "  Health check:      $($script:SVC_HEALTH_PATH)"
Write-Host "  CPU:               $($script:SVC_CPU)"
Write-Host "  Memory:            $($script:SVC_MEMORY)"
Write-Host "  Replicas (min):    $($script:SVC_MIN_REPLICAS)"
Write-Host "  Replicas (max):    $($script:SVC_MAX_REPLICAS)"
Write-Host "  Public endpoint:   $($script:SVC_PUBLIC_ENDPOINT)"

Write-Host ""
Write-Host "Container app (live):" -ForegroundColor White

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  Write-Host "  (live state unavailable — 'az' not on PATH)"
  exit 0
}
& az account show *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "  (live state unavailable — not logged in to Azure; run 'az login')"
  exit 0
}
if (-not (Try-AzSubscription -SubscriptionId $script:SVC_SUBSCRIPTION_ID)) {
  Write-Host "  (live state unavailable — see warnings above)"
  exit 0
}

$raw = & az containerapp list `
  --subscription $script:SVC_SUBSCRIPTION_ID `
  --resource-group $script:SVC_RESOURCE_GROUP `
  --query "[?contains(name, '$($script:SVC_NAME)')] | [0].{name:name, status:properties.runningStatus, revision:properties.latestRevisionName, fqdn:properties.configuration.ingress.fqdn, image:properties.template.containers[0].image, minR:properties.template.scale.minReplicas, maxR:properties.template.scale.maxReplicas}" `
  -o tsv 2>$null

if (-not $raw) {
  Log-Warn -Message "No container app found in $($script:SVC_RESOURCE_GROUP) matching '$($script:SVC_NAME)'."
  Log-Warn -Message "The pipeline may not have deployed yet. Try: noclickops deploy $($script:SVC_NAME) $($script:SVC_ENV) --watch"
  exit 0
}

$fields = $raw -split "`t"
function IsSet { param([string]$v) return ($v -and $v -ne 'None') }

if (IsSet $fields[0]) { Write-Host "  Name:              $($fields[0])" }
if (IsSet $fields[1]) { Write-Host "  Status:            $($fields[1])" }
if (IsSet $fields[2]) { Write-Host "  Latest revision:   $($fields[2])" }
if (IsSet $fields[3]) { Write-Host "  FQDN:              https://$($fields[3])" }
if (IsSet $fields[4]) { Write-Host "  Image:             $($fields[4])" }
if ((IsSet $fields[5]) -or (IsSet $fields[6])) {
  Write-Host "  Replicas (live):   min=$($fields[5]), max=$($fields[6])"
}
