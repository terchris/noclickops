# lib/service.ps1 — per-service + per-env context resolution.
# NOTE: PowerShell port. Unverified on Mac.

if ($script:NCO_SERVICE_LOADED) { return }
$script:NCO_SERVICE_LOADED = $true

. "$PSScriptRoot/logging.ps1"
. "$PSScriptRoot/utilities.ps1"

function Yaml-Var {
  param([string]$Path, [string]$Key)
  if (-not (Test-Path $Path)) { return '' }
  $line = (Select-String -Path $Path -Pattern "^\s*${Key}:\s" | Select-Object -First 1).Line
  if (-not $line) { return '' }
  $val = $line -replace "^\s*${Key}:\s*", ''
  if ($val -match '^"(.*)"\s*$') { return $Matches[1] }
  if ($val -match "^'(.*)'\s*$") { return $Matches[1] }
  return $val.TrimEnd()
}

function Resolve-ServiceContext {
  param(
    [Parameter(Mandatory)][string]$Service,
    [string]$EnvName = 'test',
    [string]$TargetRepo = $script:TARGET_REPO
  )
  if (-not $TargetRepo) { Die -Message "resolve_service_context: needs target repo path" }
  if ($EnvName -notin @('test', 'prod')) { Die -Message "Invalid environment '$EnvName' (expected: test | prod)" }

  $svcDir = Join-Path (Join-Path $TargetRepo 'services') $Service
  if (-not (Test-Path $svcDir)) { Die -Message "Service '$Service' not found at $svcDir." }

  $commonYaml = Join-Path $TargetRepo '.pipelines/variables/common.yaml'
  $envYaml    = Join-Path $TargetRepo ".pipelines/variables/$EnvName.yaml"
  $svcEnvYaml = Join-Path $svcDir ".pipelines/variables/$EnvName.yaml"

  if (-not (Test-Path $commonYaml)) { Die -Message "Repo-level variables missing: $commonYaml" }
  if (-not (Test-Path $envYaml))    { Die -Message "Env variables missing: $envYaml" }
  if (-not (Test-Path $svcEnvYaml)) { Die -Message "Service env variables missing: $svcEnvYaml" }

  $script:SVC_NAME            = $Service
  $script:SVC_DIR             = $svcDir
  $script:SVC_ENV             = $EnvName

  $script:SVC_APP_NAME        = Yaml-Var -Path $commonYaml -Key 'APP_NAME'
  $script:SVC_SUBSCRIPTION_ID = Yaml-Var -Path $envYaml    -Key 'SUBSCRIPTION_ID'
  $script:SVC_ENVIRONMENT     = Yaml-Var -Path $envYaml    -Key 'ENVIRONMENT'
  $script:SVC_COMMON_RG       = Yaml-Var -Path $envYaml    -Key 'COMMON_RESOURCE_GROUP_NAME'

  $script:SVC_PORT            = Yaml-Var -Path $svcEnvYaml -Key 'SERVICE_PORT'
  $script:SVC_HEALTH_PATH     = Yaml-Var -Path $svcEnvYaml -Key 'SERVICE_HEALTH_CHECK_PATH'
  $script:SVC_PUBLIC_ENDPOINT = Yaml-Var -Path $svcEnvYaml -Key 'ENABLE_PUBLIC_ENDPOINT'
  $script:SVC_CPU             = Yaml-Var -Path $svcEnvYaml -Key 'SERVICE_CPU'
  $script:SVC_MEMORY          = Yaml-Var -Path $svcEnvYaml -Key 'SERVICE_MEMORY'
  $script:SVC_MIN_REPLICAS    = Yaml-Var -Path $svcEnvYaml -Key 'SERVICE_MIN_REPLICAS'
  $script:SVC_MAX_REPLICAS    = Yaml-Var -Path $svcEnvYaml -Key 'SERVICE_MAX_REPLICAS'

  if ($script:SVC_APP_NAME) {
    $script:SVC_RESOURCE_GROUP = "rg-$EnvName-nrx-$($script:SVC_APP_NAME)"
  } else {
    $script:SVC_RESOURCE_GROUP = ''
  }
}

function Try-AzSubscription {
  param([string]$SubscriptionId)
  if (-not $SubscriptionId) {
    Log-Warn -Message "SUBSCRIPTION_ID is empty in this environment's variables file."
    return $false
  }
  & az account set --subscription $SubscriptionId *> $null
  if ($LASTEXITCODE -ne 0) {
    Log-Warn -Message "Cannot access Azure subscription '$SubscriptionId'."
    Log-Warn -Message "  You need 'Reader' (or higher) on this subscription to see live Azure state."
    Log-Warn -Message "  Ask your team admin to grant Reader on subscription $SubscriptionId."
    return $false
  }
  return $true
}
