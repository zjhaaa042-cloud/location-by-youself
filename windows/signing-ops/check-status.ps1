#Requires -Version 5.1
<#
  Free-signing maintenance status check (iOS / Windows / iLoader).

  Reads config.json next to this script. Exit codes:
    0 = healthy
    1 = warning  (signature expires within warnDays, or anisette endpoint unreachable)
    2 = critical (signature expired, or the app is gone from a *connected* device)

  An unplugged phone is NOT an error: the signature lives on the device and daily
  use never needs the cable. USB is only required when renewing.

  Usage:
    .\check-status.ps1              # human readable report
    .\check-status.ps1 -Deep        # also verify the app on the device (~10s)
    .\check-status.ps1 -Alert       # tray balloon when not healthy
    .\check-status.ps1 -Quiet       # no console output (for scheduled tasks)
#>
[CmdletBinding()]
param(
  [switch]$Deep,
  [switch]$Alert,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot 'config.json'
$reportPath = Join-Path $PSScriptRoot 'last-status.txt'
if (-not (Test-Path $configPath)) { throw "missing config.json - copy config.example.json and fill it in" }
$cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

$out = New-Object System.Collections.Generic.List[string]
function Emit([string]$s) { $out.Add($s); if (-not $Quiet) { Write-Host $s } }

$status = 0
function Worse([int]$code) { if ($script:status -lt $code) { $script:status = $code } }

function Resolve-Python {
  if ($cfg.pythonPath) { return $cfg.pythonPath }
  return (Join-Path $cfg.workRoot '.venv\Scripts\python.exe')
}

# ---------- signature window ----------
$signed = [datetime]::Parse($cfg.signedOn)
$expires = $signed.AddDays([int]$cfg.validDays)
$remaining = $expires - (Get-Date)
$daysLeft = [math]::Round($remaining.TotalHours / 24.0, 1)
$warnDays = [int]$cfg.warnDays

Emit ('Free-signing status  {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Emit ('  account        : {0}  (team {1})' -f $cfg.appleId, $cfg.teamId)
Emit ('  bundle id      : {0}' -f $cfg.bundleId)
Emit ('  signed on      : {0}' -f $signed.ToString('yyyy-MM-dd HH:mm'))
Emit ('  expires on     : {0}' -f $expires.ToString('yyyy-MM-dd HH:mm'))
if ($remaining.TotalSeconds -le 0) {
  Emit ('  remaining      : EXPIRED {0} days ago' -f [math]::Abs($daysLeft))
  Worse 2
} else {
  Emit ('  remaining      : {0} days' -f $daysLeft)
  if ($daysLeft -le $warnDays) { Worse 1 }
}

# ---------- device ----------
$py = Resolve-Python
if (-not (Test-Path $py)) {
  Emit ('  device         : UNKNOWN (python not found: {0})' -f $py)
  Worse 2
} else {
  $devOut = & $py -m pymobiledevice3 usbmux list 2>&1 | Out-String
  if ($devOut -match 'USB') {
    $name = 'unknown'; $ios = 'unknown'
    if ($devOut -match '"DeviceName"\s*:\s*"([^"]+)"') { $name = $Matches[1] }
    if ($devOut -match '"ProductVersion"\s*:\s*"([^"]+)"') { $ios = $Matches[1] }
    Emit ('  device         : {0} / iOS {1} [USB OK]' -f $name, $ios)
  } else {
    Emit '  device         : not connected (only renewal needs USB - this is not an error)'
  }

  if ($Deep) {
    if ($devOut -notmatch 'USB') {
      Emit '  app installed  : skipped (no device)'
    } else {
      $tmp = Join-Path $env:TEMP 'signing_ops_apps.json'
      try {
        & $py -m pymobiledevice3 apps list 2>$null | Out-File -FilePath $tmp -Encoding utf8
        $raw = Get-Content $tmp -Raw -Encoding UTF8
        if ($raw -match [regex]::Escape($cfg.bundleId)) { Emit '  app installed  : yes' }
        else { Emit '  app installed  : NO (signature expired or app removed?)'; Worse 2 }
      } catch {
        Emit ('  app installed  : UNKNOWN ({0})' -f $_.Exception.Message)
        Worse 1
      }
    }
  }
}

# ---------- anisette endpoint ----------
$ani = $cfg.anisetteServer
if ($ani) {
  $tcp = New-Object System.Net.Sockets.TcpClient
  try {
    $ok = $tcp.ConnectAsync($ani, 443).Wait(6000) -and $tcp.Connected
    if ($ok) { Emit ('  anisette       : {0}:443 [reachable]' -f $ani) }
    else { Emit ('  anisette       : {0}:443 [UNREACHABLE]' -f $ani); Worse 1 }
  } catch {
    Emit ('  anisette       : {0}:443 [ERROR {1}]' -f $ani, $_.Exception.Message); Worse 1
  } finally { $tcp.Dispose() }
}

switch ($status) {
  0 { Emit '  verdict        : OK' }
  1 { Emit '  verdict        : WARNING - renew soon (run renew.ps1)' }
  2 { Emit '  verdict        : CRITICAL - action required' }
}
Emit '  note           : severity depends on signature age only; an unplugged phone is normal.'

$out | Set-Content -Path $reportPath -Encoding UTF8

if ($Alert -and $status -ne 0) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $icon = New-Object System.Windows.Forms.NotifyIcon
    $icon.Icon = [System.Drawing.SystemIcons]::Warning
    $icon.BalloonTipTitle = 'iOS free-signing maintenance'
    if ($status -eq 2) { $icon.BalloonTipText = 'Signature expired or app/device missing. Run renew.ps1.' }
    else { $icon.BalloonTipText = ('Signature expires in {0} days. Run renew.ps1.' -f $daysLeft) }
    $icon.Visible = $true
    $icon.ShowBalloonTip(15000)
    Start-Sleep -Seconds 12
    $icon.Dispose()
  } catch { }
}

exit $status
