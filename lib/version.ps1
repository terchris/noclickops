# lib/version.ps1 — local version + remote-check + update-hint helpers.
# NOTE: PowerShell port. Unverified on Mac.

if ($script:NCO_VERSION_LOADED) { return }
$script:NCO_VERSION_LOADED = $true

. "$PSScriptRoot/paths.ps1"

$script:NCO_VERSION_CACHE_TTL = if ($env:NCO_VERSION_CACHE_TTL) { [int]$env:NCO_VERSION_CACHE_TTL } else { 3600 }

# Derive the version-check URL from $NOCLICKOPS_DIR's origin remote.
# Same portability principle as lib/azdo.sh — no hardcoded identity,
# fork-friendly. Env override $NCO_VERSION_CHECK_URL wins.
function _Nco-DeriveCheckUrl {
  $url = & git -C $script:NOCLICKOPS_DIR remote get-url origin 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $url) { return '' }
  if ($url -match '\.git$') { $url = $url.Substring(0, $url.Length - 4) }
  if ($url -match '^https://github\.com/([^/]+/[^/]+)$') {
    return "https://raw.githubusercontent.com/$($Matches[1])/main/version.txt"
  }
  if ($url -match '^git@github\.com:(.+)$') {
    return "https://raw.githubusercontent.com/$($Matches[1])/main/version.txt"
  }
  return ''
}

function Nco-LoadVersion {
  $script:NCO_VERSION = 'unknown'
  $f = Join-Path $script:NOCLICKOPS_DIR 'version.txt'
  if (Test-Path $f) {
    $v = (Get-Content $f -Raw -ErrorAction SilentlyContinue).Trim()
    if ($v) { $script:NCO_VERSION = $v }
  }
}

function Nco-CheckRemote {
  $script:NCO_REMOTE_VERSION = ''
  $cache = Join-Path $script:NOCLICKOPS_DIR '.version-cache'

  if (Test-Path $cache) {
    $line = Get-Content $cache -First 1 -ErrorAction SilentlyContinue
    if ($line -match '^(\d+)\s+(\S+)$') {
      $cachedAt = [int]$Matches[1]
      $cachedVer = $Matches[2]
      $now = [int][double]::Parse((Get-Date -UFormat %s))
      if (($now - $cachedAt) -lt $script:NCO_VERSION_CACHE_TTL) {
        if ($cachedVer -and $cachedVer -ne $script:NCO_VERSION) {
          $script:NCO_REMOTE_VERSION = $cachedVer
        }
        return
      }
    }
  }

  $url = if ($env:NCO_VERSION_CHECK_URL) { $env:NCO_VERSION_CHECK_URL } else { _Nco-DeriveCheckUrl }
  if (-not $url) { return }

  try {
    $resp = Invoke-WebRequest -Uri $url `
              -TimeoutSec 4 -UseBasicParsing -ErrorAction Stop
    $remote = $resp.Content.Trim()
    if ($remote) {
      $now = [int][double]::Parse((Get-Date -UFormat %s))
      "$now $remote" | Out-File -FilePath $cache -Encoding ascii -ErrorAction SilentlyContinue
      if ($remote -ne $script:NCO_VERSION) { $script:NCO_REMOTE_VERSION = $remote }
    }
  } catch {
    # Silent — no network, no GitHub, whatever. No hint, no warning.
  }
}

function Nco-ShowUpdateHint {
  if (-not $script:NCO_REMOTE_VERSION) { return }
  Write-Host ""
  Write-Host "⬆ Update available: v$($script:NCO_REMOTE_VERSION) — run 'noclickops update'" -ForegroundColor Yellow
}

function Nco-ClearVersionCache {
  $cache = Join-Path $script:NOCLICKOPS_DIR '.version-cache'
  if (Test-Path $cache) { Remove-Item $cache -ErrorAction SilentlyContinue }
}
