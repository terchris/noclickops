# lib/logging.ps1 — colored output helpers for noclickops.
# NOTE: PowerShell port. Unverified on Mac (no pwsh on the maintainer's
# machine); the Windows path is the verification surface.

if ($script:NCO_LOGGING_LOADED) { return }
$script:NCO_LOGGING_LOADED = $true

function Log-Info {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host "ℹ $Message" -ForegroundColor Blue
}
function Log-Success {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host "✓ $Message" -ForegroundColor Green
}
function Log-Warn {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host "⚠ $Message" -ForegroundColor Yellow
}
function Log-Error {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host "✗ $Message" -ForegroundColor Red
}
function Log-Step {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor White
}
