# Register Xingli relay server as a Windows startup task.
# Runs at system boot as SYSTEM (no user login required), hidden window.
# Uninstall with uninstall_autostart.ps1
$ErrorActionPreference = 'Stop'

$exeDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$exe    = Join-Path $exeDir 'relay_server.exe'
if (-not (Test-Path $exe)) { Write-Error "Cannot find $exe"; exit 1 }

$taskName  = 'XingliRelayAutostart'
$action    = New-ScheduledTaskAction -Execute $exe -WorkingDirectory $exeDir
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -Hidden `
    -ExecutionTimeLimit (New-TimeSpan -Days 3650) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "Registered startup task: $taskName"
Write-Host "  Program : $exe"
Write-Host "  Trigger : At system startup (no login required)"
Write-Host "Start now : Start-ScheduledTask -TaskName $taskName"
