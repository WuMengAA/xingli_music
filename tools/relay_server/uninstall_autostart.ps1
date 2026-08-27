# Remove the Xingli relay server startup task (see install_autostart.ps1).
$ErrorActionPreference = 'Stop'
$taskName = 'XingliRelayAutostart'
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed startup task: $taskName"
} else {
    Write-Host "Task not found (nothing to remove): $taskName"
}
