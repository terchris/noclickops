# install.ps1 — noclickops one-time installer.
# NOTE: PowerShell port. Unverified on Mac (no pwsh on maintainer's machine).
#
# Two ways to run:
#
#   1) iwr -useb https://raw.githubusercontent.com/terchris/noclickops/main/install.ps1 | iex
#   2) ~/.noclickops/install.ps1            (re-run after manual clone)
#
# Env overrides:
#   $env:NOCLICKOPS_DIR        default: $HOME/.noclickops
#   $env:NOCLICKOPS_REPO_URL   default: https://github.com/terchris/noclickops.git

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Info { param([string]$m) Write-Host "ℹ $m" -ForegroundColor Blue }
function Ok   { param([string]$m) Write-Host "✓ $m" -ForegroundColor Green }
function Warn { param([string]$m) Write-Host "⚠ $m" -ForegroundColor Yellow }
function Err  { param([string]$m) Write-Host "✗ $m" -ForegroundColor Red }
function Step { param([string]$m) Write-Host ""; Write-Host "==> $m" -ForegroundColor White }
function Die  { param([string]$m) Err $m; exit 1 }

function Ask-YesNo {
  param([string]$Prompt, [string]$Default = 'y')
  $ans = Read-Host -Prompt $Prompt
  if (-not $ans) { $ans = $Default }
  return ($ans -match '^[yY]')
}

# --- Setup ----------------------------------------------------------------

$NoclickopsDir = if ($env:NOCLICKOPS_DIR) { $env:NOCLICKOPS_DIR } else { Join-Path $HOME ".noclickops" }
$NoclickopsRepoUrl = if ($env:NOCLICKOPS_REPO_URL) { $env:NOCLICKOPS_REPO_URL } else { "https://github.com/terchris/noclickops.git" }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Die "'git' not found on PATH. Install git first."
}

# --- Clone or pull --------------------------------------------------------

$gitDir = Join-Path $NoclickopsDir ".git"
$FreshInstall = $false
if (Test-Path $gitDir) {
  Step "noclickops already installed at $NoclickopsDir — pulling latest"
  & git -C $NoclickopsDir pull --ff-only
  if ($LASTEXITCODE -ne 0) { Die "git pull failed in $NoclickopsDir — resolve manually, then re-run." }
  Ok "noclickops up to date."
} elseif (Test-Path $NoclickopsDir) {
  Die "$NoclickopsDir exists but is not a git checkout. Move it aside and re-run."
} else {
  Step "Installing noclickops to $NoclickopsDir"
  Info "Source: $NoclickopsRepoUrl"
  & git clone $NoclickopsRepoUrl $NoclickopsDir
  if ($LASTEXITCODE -ne 0) { Die "git clone failed." }
  Ok "Cloned to $NoclickopsDir."
  $FreshInstall = $true
}

# --- Wire into $PROFILE (idempotent) --------------------------------------

$initRel  = '$HOME/.noclickops/shell/init.ps1'
$srcLine  = "if (Test-Path `"$initRel`") { . `"$initRel`" }"

Step "Wiring 'noclickops' into your PowerShell `$PROFILE ($PROFILE)"

$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
  New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
}
if (-not (Test-Path $PROFILE)) {
  New-Item -ItemType File -Force -Path $PROFILE | Out-Null
}

$existing = Get-Content $PROFILE -ErrorAction SilentlyContinue
if ($existing -and ($existing -match '\.noclickops[/\\]shell[/\\]init\.ps1')) {
  Ok "Shell function is already wired into $PROFILE — leaving it alone."
} else {
  Info "Will append to ${PROFILE}:"
  Write-Host "    $srcLine"
  if (Ask-YesNo -Prompt "Append now? [Y/n] " -Default 'y') {
    Add-Content -Path $PROFILE -Value ""
    Add-Content -Path $PROFILE -Value "# noclickops — typeable shell function (installed $(Get-Date -Format 'yyyy-MM-dd'))"
    Add-Content -Path $PROFILE -Value $srcLine
    Ok "Appended."
  } else {
    Warn "Skipped. Paste this line into `$PROFILE manually when ready:"
    Write-Host "    $srcLine"
  }
}

# --- Welcome --------------------------------------------------------------

# Show full welcome only on first install; keep the re-run path quiet.
$welcome = Join-Path $NoclickopsDir "templates/welcome.txt"
if ($FreshInstall -and (Test-Path $welcome)) {
  Write-Host ""
  Get-Content $welcome
}

Write-Host ""
Ok "Done. Restart PowerShell or run:  . `$PROFILE"
