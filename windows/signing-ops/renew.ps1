#Requires -Version 5.1
<#
  Automated re-sign & install of an existing IPA through iLoader (Windows).

  No credentials are handled here. If the iLoader session has expired this script
  stops with exit code 7 and asks you to log in yourself
  (Apple ID must be the +86 phone number, Anisette Server = StikStore), then rerun.

  Usage:
    .\renew.ps1 -DryRun          # inspect only, click nothing
    .\renew.ps1                  # perform the renewal
    .\renew.ps1 -IpaPath X.ipa   # override IPA path

  Exit codes:
    0 ok | 2 no venv | 3 no device | 4 no IPA | 5 no iLoader exe | 6 no window
    7 not logged in | 8 no device card | 9 Import IPA off-screen
   10 file dialog missing | 11 filename box missing | 12 iLoader error | 13 timeout
#>
[CmdletBinding()]
param(
  [string]$IpaPath,
  [switch]$DryRun,
  [int]$TimeoutSec = 420,
  [string]$IloaderExe = ''
)

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot 'config.json'
$logPath = Join-Path $PSScriptRoot 'renew.log'
if (-not (Test-Path $configPath)) { throw "missing config.json - copy config.example.json and fill it in" }
$state = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $IpaPath) { $IpaPath = $state.ipaPath }
if (-not $IloaderExe -and $state.iloaderExe) { $IloaderExe = $state.iloaderExe }

function Log([string]$msg) {
  $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
  Write-Host $line
  Add-Content -Path $logPath -Value $line -Encoding UTF8
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$cs = @"
using System;
using System.Runtime.InteropServices;
public class WinApi {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int data, UIntPtr extra);
  public static void Focus(IntPtr h) {
    ShowWindow(h, 9);
    uint pid;
    uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), out pid);
    uint me = GetCurrentThreadId();
    AttachThreadInput(me, fgThread, true);
    BringWindowToTop(h);
    SetForegroundWindow(h);
    AttachThreadInput(me, fgThread, false);
  }
  public static void ClickAt(int x, int y) {
    SetCursorPos(x, y);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(60);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
  public static void Wheel(int delta) {
    mouse_event(0x0800, 0, 0, delta, UIntPtr.Zero);
  }
}
"@
if (-not ('WinApi' -as [type])) { Add-Type -TypeDefinition $cs }

function Get-IloaderWindow {
  $p = Get-Process iloader -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $p) { return $null }
  return $p.MainWindowHandle
}

function Get-Tree([IntPtr]$h) {
  $el = [System.Windows.Automation.AutomationElement]::FromHandle($h)
  if (-not $el) { return @() }
  return $el.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
}

function Find-ByName([IntPtr]$h, [string]$name) {
  foreach ($e in (Get-Tree $h)) { if ($e.Current.Name -eq $name) { return $e } }
  return $null
}

function Find-ByNameLike([IntPtr]$h, [string]$pattern) {
  foreach ($e in (Get-Tree $h)) { if ($e.Current.Name -like $pattern) { return $e } }
  return $null
}

function Invoke-El($el) {
  if (-not $el) { return $false }
  $r = $el.Current.BoundingRectangle
  if (-not $r.IsEmpty -and -not [double]::IsInfinity($r.X) -and -not [double]::IsInfinity($r.Y)) {
    [WinApi]::Focus((Get-IloaderWindow)) | Out-Null
    Start-Sleep -Milliseconds 250
    [WinApi]::ClickAt([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)) | Out-Null
    return $true
  }
  $pat = $null
  if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pat)) { $pat.Invoke(); return $true }
  return $false
}

function Get-FileDialog {
  return (Get-Process | Where-Object { $_.MainWindowTitle -match '(?i)^(Open|\u6253\u5F00)$' } | Select-Object -First 1)
}

# ---------- 1. device ----------
if (-not $state.pythonPath) { $py = Join-Path $state.workRoot '.venv\Scripts\python.exe' } else { $py = $state.pythonPath }
if (-not (Test-Path $py)) { Log "FATAL: python not found: $py"; exit 2 }
$devOut = & $py -m pymobiledevice3 usbmux list 2>&1 | Out-String
if ($devOut -notmatch 'USB') {
  Log 'FATAL: no iPhone visible over USB. Unlock the phone, reconnect the cable, then retry.'
  exit 3
}
Log 'device: iPhone visible over USB'
if (-not (Test-Path $IpaPath)) { Log "FATAL: IPA not found: $IpaPath"; exit 4 }
Log "ipa: $IpaPath"

# ---------- 2. iLoader ----------
$hwnd = Get-IloaderWindow
if (-not $hwnd -or $hwnd -eq [IntPtr]::Zero) {
  if ($DryRun) { Log 'DRYRUN: iLoader is not running (would start it)'; exit 0 }
  if (-not $IloaderExe) {
    $IloaderExe = (Get-ChildItem "$env:LOCALAPPDATA\iloader\iloader.exe", "$env:LOCALAPPDATA\Programs\iloader\iloader.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
  }
  if (-not $IloaderExe) { Log 'FATAL: iLoader executable not found; set iloaderExe in config.json'; exit 5 }
  Log "starting iLoader: $IloaderExe"
  Start-Process -FilePath $IloaderExe | Out-Null
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    $hwnd = Get-IloaderWindow
    if ($hwnd -and $hwnd -ne [IntPtr]::Zero) { break }
  }
  if (-not $hwnd -or $hwnd -eq [IntPtr]::Zero) { Log 'FATAL: iLoader window did not appear'; exit 6 }
  Start-Sleep -Seconds 2
}
[WinApi]::Focus($hwnd) | Out-Null
Start-Sleep -Milliseconds 800
Log "iLoader window: $hwnd"

# ---------- 3. login gate ----------
if (-not (Find-ByName $hwnd 'LOGGED IN AS')) {
  Log 'FATAL: iLoader is not logged in. Sign in with the +86 phone number (Anisette = StikStore), then rerun.'
  exit 7
}
Log 'iLoader session: logged in'

if ($DryRun) {
  foreach ($n in @('Import IPA', '*Selected', ('Anisette Server: ' + $state.anisetteServer))) {
    $e = Find-ByNameLike $hwnd $n
    if ($e) {
      $r = $e.Current.BoundingRectangle
      Log ("DRYRUN: found '{0}' at {1},{2} {3}x{4}" -f $e.Current.Name, [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height)
    } else { Log "DRYRUN: NOT found '$n'" }
  }
  Log 'DRYRUN: no click performed'
  exit 0
}

# ---------- 4. device card ----------
if (-not (Find-ByNameLike $hwnd '*Selected')) {
  $dev = Find-ByNameLike $hwnd 'iPhone*USB*'
  if ($dev) { Log 'selecting device card'; Invoke-El $dev | Out-Null; Start-Sleep -Seconds 2 }
  else { Log 'FATAL: device card not found in iLoader UI'; exit 8 }
}

# ---------- 5. bring Import IPA into view ----------
$importBtn = $null
for ($i = 0; $i -lt 10; $i++) {
  $importBtn = Find-ByName $hwnd 'Import IPA'
  if (-not $importBtn) { Start-Sleep -Milliseconds 500; continue }
  $r = $importBtn.Current.BoundingRectangle
  if ($r.Y -gt 700 -and $r.Y -lt 1080) { break }
  [WinApi]::SetCursorPos([int]($r.X + 200), 800) | Out-Null
  if ($r.Y -ge 1080) { [WinApi]::Wheel(-240) } else { [WinApi]::Wheel(240) }
  Start-Sleep -Milliseconds 900
  $importBtn = $null
}
if (-not $importBtn) { Log 'FATAL: could not bring "Import IPA" into view'; exit 9 }

# ---------- 6. file dialog ----------
$dlg = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
  [WinApi]::Focus($hwnd) | Out-Null
  Start-Sleep -Milliseconds 400
  $importBtn = Find-ByName $hwnd 'Import IPA'
  if (-not $importBtn) { Start-Sleep -Seconds 1; continue }
  Log ("clicking Import IPA (attempt {0})" -f $attempt)
  Invoke-El $importBtn | Out-Null
  for ($i = 0; $i -lt 12; $i++) {
    Start-Sleep -Milliseconds 500
    $dlg = Get-FileDialog
    if ($dlg) { break }
  }
  if ($dlg) { break }
}
if (-not $dlg) { Log 'FATAL: file dialog did not appear'; exit 10 }
[WinApi]::Focus($dlg.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 600
Log 'file dialog open'

# filename box = the bottom-most Edit control (the search box sits at the top)
$edit = $null
foreach ($e in (Get-Tree $dlg.MainWindowHandle)) {
  if ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.Edit') {
    if (-not $edit) { $edit = $e }
    elseif ($e.Current.BoundingRectangle.Y -gt $edit.Current.BoundingRectangle.Y) { $edit = $e }
  }
}
if (-not $edit) { Log 'FATAL: filename edit box not found'; exit 11 }
$vp = $null
if ($edit.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) {
  $vp.SetValue($IpaPath)
  Log 'ipa path set via ValuePattern'
} else {
  $r = $edit.Current.BoundingRectangle
  [WinApi]::ClickAt([int]($r.X + 20), [int]($r.Y + $r.Height / 2)) | Out-Null
  Set-Clipboard -Value $IpaPath
  Start-Sleep -Milliseconds 300
  $ws = New-Object -ComObject WScript.Shell
  $ws.SendKeys('^a'); Start-Sleep -Milliseconds 200; $ws.SendKeys('^v')
  Log 'ipa path pasted'
}
Start-Sleep -Milliseconds 500

$openBtn = $null
foreach ($e in (Get-Tree $dlg.MainWindowHandle)) {
  if ($e.Current.Name -match '(?i)^(Open|\u6253\u5F00.*)$') { $openBtn = $e; break }
}
if ($openBtn) { Invoke-El $openBtn | Out-Null }
else { Log 'open button not found, sending ENTER'; (New-Object -ComObject WScript.Shell).SendKeys('{ENTER}') }
Start-Sleep -Seconds 3

# ---------- 7. wait for completion ----------
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$ok = $false
$err = $null
while ((Get-Date) -lt $deadline) {
  if (Find-ByName $hwnd 'Operation completed') { $ok = $true; break }
  $e = Find-ByNameLike $hwnd 'An Error Occured*'
  if ($e) {
    $detail = Find-ByNameLike $hwnd 'Auth error*'
    $err = if ($detail) { $detail.Current.Name } else { 'unknown error (check the iLoader window)' }
    break
  }
  Start-Sleep -Seconds 3
}

if ($ok) {
  Log 'iLoader reports: Operation completed'
  $d = Find-ByName $hwnd 'Dismiss'
  if ($d) { Invoke-El $d | Out-Null }
  $state.signedOn = (Get-Date).ToString('o')
  $state | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
  Log 'config.json updated (new signing time)'
  exit 0
}
if ($err) { Log "FAILED: $err"; exit 12 }
Log 'TIMEOUT waiting for iLoader result'
exit 13
