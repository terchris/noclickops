# lib/utilities.ps1 — shared helpers for noclickops.
# NOTE: PowerShell port. Unverified on Mac.

if ($script:NCO_UTILITIES_LOADED) { return }
$script:NCO_UTILITIES_LOADED = $true

. "$PSScriptRoot/logging.ps1"

function Die {
  param([Parameter(Mandatory)][string]$Message)
  Log-Error -Message $Message
  exit 1
}

function Require-Cmd {
  param([Parameter(Mandatory)][string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Die -Message "'$Name' not found on PATH. Install it first."
  }
}
