# shell/init.ps1 — defines the `noclickops` shell function for PowerShell.
# NOTE: PowerShell port. Unverified on Mac (no pwsh on maintainer's machine).
#
# Source from your $PROFILE:
#
#   if (Test-Path "$HOME/.noclickops/shell/init.ps1") { . "$HOME/.noclickops/shell/init.ps1" }
#
# From v1.2.1: thin wrapper that forwards everything to bin/noclickops.ps1.
# Single source of dispatch — same fix as init.sh.

function noclickops {
  $install_dir = if ($env:NOCLICKOPS_DIR) { $env:NOCLICKOPS_DIR } else { Join-Path $HOME ".noclickops" }
  if (-not (Test-Path (Join-Path $install_dir "bin"))) {
    Write-Error "noclickops: install dir $install_dir not found (set NOCLICKOPS_DIR or re-run install.ps1)"
    return
  }
  & (Join-Path $install_dir "bin/noclickops.ps1") @args
}
