# lib/metadata.ps1 — parse SCRIPT_* metadata from script files; print -Help.
# NOTE: PowerShell port. Unverified on Mac.
#
# Each bin/*.ps1 declares (near the top):
#   $SCRIPT_NAME        = "<short name>"
#   $SCRIPT_DESCRIPTION = "<one line>"
#   $SCRIPT_USAGE       = "<one-line usage form>"
#   $SCRIPT_EXAMPLE     = "<one example>"
#   $SCRIPT_CATEGORY    = "<meta|git|deploy|service-lifecycle|inspect>"

if ($script:NCO_METADATA_LOADED) { return }
$script:NCO_METADATA_LOADED = $true

. "$PSScriptRoot/logging.ps1"

$script:NCO_VALID_CATEGORIES = @('meta', 'git', 'deploy', 'service-lifecycle', 'inspect')

function Valid-Category {
  param([Parameter(Mandatory)][string]$Category)
  return $script:NCO_VALID_CATEGORIES -contains $Category
}

function Parse-Metadata {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path $Path)) {
    Log-Error -Message "metadata: file not found: $Path"
    return $null
  }
  $result = @{}
  $fields = @('SCRIPT_NAME','SCRIPT_DESCRIPTION','SCRIPT_USAGE','SCRIPT_EXAMPLE','SCRIPT_CATEGORY')
  foreach ($field in $fields) {
    $match = Select-String -Path $Path -Pattern "^\`$$field\s*=\s*[`"']([^`"']*)[`"']" | Select-Object -First 1
    if ($match) {
      $result[$field] = $match.Matches[0].Groups[1].Value
    } else {
      $result[$field] = ''
    }
  }
  return $result
}

function Show-Help {
  param([Parameter(Mandatory)][string]$Path)
  $meta = Parse-Metadata -Path $Path
  if (-not $meta) { return }
  Write-Output "$($meta['SCRIPT_NAME']) — $($meta['SCRIPT_DESCRIPTION'])"
  Write-Output ""
  Write-Output "Usage:"
  Write-Output "  $($meta['SCRIPT_USAGE'])"
  Write-Output ""
  Write-Output "Example:"
  Write-Output "  $($meta['SCRIPT_EXAMPLE'])"
  Write-Output ""
  Write-Output "Category: $($meta['SCRIPT_CATEGORY'])"
  Write-Output "Flags:"
  Write-Output "  -Help    Show this help and exit."
}
