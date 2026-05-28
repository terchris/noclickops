# shell/init.ps1 — defines the `noclickops` shell function for PowerShell.
# NOTE: PowerShell port. Unverified on Mac (no pwsh on maintainer's machine).
#
# Source from your $PROFILE:
#
#   if (Test-Path "$HOME/.noclickops/shell/init.ps1") { . "$HOME/.noclickops/shell/init.ps1" }

function noclickops {
  $install_dir = if ($env:NOCLICKOPS_DIR) { $env:NOCLICKOPS_DIR } else { Join-Path $HOME ".noclickops" }
  if (-not (Test-Path (Join-Path $install_dir "bin"))) {
    Write-Error "noclickops: install dir $install_dir not found (set NOCLICKOPS_DIR or re-run install.ps1)"
    return
  }
  if ($args.Count -eq 0) {
    & (Join-Path $install_dir "bin/noclickops.ps1")
    return
  }
  $cmd = $args[0]
  $rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
  $script = Join-Path $install_dir "bin/$cmd.ps1"
  if (-not (Test-Path $script)) {
    Write-Error "noclickops: no such command '$cmd' (try: noclickops)"
    return
  }
  & $script @rest
}
