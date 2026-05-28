# lib/paths.ps1 — well-known paths for noclickops.
# NOTE: PowerShell port. Unverified on Mac.

if ($script:NCO_PATHS_LOADED) { return }
$script:NCO_PATHS_LOADED = $true

$script:NOCLICKOPS_DIR = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:BIN_DIR        = Join-Path $script:NOCLICKOPS_DIR "bin"
$script:LIB_DIR        = Join-Path $script:NOCLICKOPS_DIR "lib"
$script:TEMPLATES_DIR  = Join-Path $script:NOCLICKOPS_DIR "templates"

# Target repo = the git repo enclosing pwd. Empty when pwd isn't in a repo.
$script:TARGET_REPO = $null
try {
  $top = git rev-parse --show-toplevel 2>$null
  if ($LASTEXITCODE -eq 0) { $script:TARGET_REPO = $top }
} catch { }
