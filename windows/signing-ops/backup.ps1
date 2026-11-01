#Requires -Version 5.1
<#
  Back up everything needed to rebuild the signing setup.

  Saved: config.json, iLoader account data + logs, the IPA, the injected pairing file,
         and a status snapshot.

  WARNING: the backup contains account session data. Keep it local, never commit it.

  Usage:
    .\backup.ps1
    .\backup.ps1 -Destination D:\SomewhereElse
#>
[CmdletBinding()]
param(
  [string]$Destination = ''
)

$ErrorActionPreference = 'Stop'
if (-not $Destination) { $Destination = Join-Path $PSScriptRoot 'backups' }

$configPath = Join-Path $PSScriptRoot 'config.json'
if (-not (Test-Path $configPath)) { throw "missing config.json - copy config.example.json and fill it in" }
$cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$target = Join-Path $Destination $stamp
New-Item -ItemType Directory -Force -Path $target | Out-Null

function Copy-ItemSafe([string]$src, [string]$dstDir) {
  if (-not $src -or -not (Test-Path $src)) { Write-Host "skip (missing): $src"; return }
  New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
  if ((Get-Item $src).PSIsContainer) { Copy-Item -Path $src -Destination $dstDir -Recurse -Force }
  else { Copy-Item -Path $src -Destination $dstDir -Force }
  Write-Host "saved: $src"
}

Copy-ItemSafe $configPath (Join-Path $target 'config')

$iloaderData = Join-Path $env:APPDATA 'me.nabdev.iloader'
Copy-ItemSafe (Join-Path $iloaderData 'data.json')        (Join-Path $target 'iloader')
Copy-ItemSafe (Join-Path $iloaderData 'preferences.json') (Join-Path $target 'iloader')
Copy-ItemSafe (Join-Path $iloaderData 'logs')            (Join-Path $target 'iloader')

Copy-ItemSafe $cfg.ipaPath (Join-Path $target 'ipa')

$pairing = $null
if ($cfg.workRoot) {
  $pairing = (Get-ChildItem $cfg.workRoot -Recurse -Filter '*pairing*.plist' -ErrorAction SilentlyContinue |
              Select-Object -First 1).FullName
}
if ($pairing) { Copy-ItemSafe $pairing (Join-Path $target 'pairing') }

try {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check-status.ps1') -Deep 2>&1 |
    Out-File -FilePath (Join-Path $target 'status.txt') -Encoding UTF8
} catch { }

Write-Host ''
Write-Host "backup root: $target"
Write-Host 'NOTE: contains account session data - keep it local, do not upload.'
