#Requires -Version 5.1
<#
  Register (or remove) the daily maintenance check.

  The task runs check-status.ps1 -Deep -Alert once a day. It only reads state;
  it never signs or installs anything.

  Usage:
    .\install-schedule.ps1                 # daily at 20:00
    .\install-schedule.ps1 -Time 09:30
    .\install-schedule.ps1 -Remove
#>
[CmdletBinding()]
param(
  [string]$TaskName = 'iOS-FreeSigning-Maintenance',
  [string]$Time = '20:00',
  [switch]$Remove
)

$ErrorActionPreference = 'Stop'

if ($Remove) {
  $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($existing) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "removed task: $TaskName"
  } else { Write-Host "task not present: $TaskName" }
  exit 0
}

$script = Join-Path $PSScriptRoot 'check-status.ps1'
if (-not (Test-Path $script)) { throw "missing: $script" }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Deep -Alert' -f $script)

$trigger = New-ScheduledTaskTrigger -Daily -At $Time

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

$principal = New-ScheduledTaskPrincipal -UserId ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) `
  -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
  -Settings $settings -Principal $principal `
  -Description 'Warn before the free Apple ID 7-day signature expires.' -Force | Out-Null

$t = Get-ScheduledTask -TaskName $TaskName
Write-Host ("registered: {0}  state={1}  next={2:yyyy-MM-dd HH:mm}" -f $t.TaskName, $t.State,
  (Get-ScheduledTaskInfo -TaskName $TaskName).NextRunTime)
Write-Host ("command   : powershell.exe -File `"{0}`" -Deep -Alert" -f $script)
