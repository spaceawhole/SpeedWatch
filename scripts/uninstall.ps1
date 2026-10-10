# SpeedWatch - uninstaller
# Removes the scheduled task and the desktop shortcut. Your recorded results are
# left alone unless you ask for them to go. After this, deleting the SpeedWatch
# folder leaves nothing behind anywhere on the machine.

[CmdletBinding()]
param(
    [switch]$KeepData,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

$Root     = Split-Path -Parent $PSScriptRoot
$DataDir  = Join-Path $Root 'data'
$TaskName = 'SpeedWatch Daily Speedtest'
$TaskPath = '\SpeedWatch\'

function Say  { param($m) Write-Host "  $m" }
function Ok   { param($m) Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "  [!]  $m" -ForegroundColor Yellow }

Write-Host ''
Write-Host '  SpeedWatch - remove' -ForegroundColor Cyan
Write-Host '  -------------------'
Write-Host ''

# ---------------------------------------------------------------- the task

$task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
if ($task) {
    try {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
        Ok 'Scheduled task removed'
    } catch {
        Warn "Could not remove the scheduled task: $($_.Exception.Message)"
    }
} else {
    Say 'No scheduled task found (already removed).'
}

# Clean up the empty \SpeedWatch\ folder inside Task Scheduler, if it is empty.
try {
    $svc = New-Object -ComObject 'Schedule.Service'
    $svc.Connect()
    $rootFolder = $svc.GetFolder('\')
    $sub = $rootFolder.GetFolder('SpeedWatch')
    if ($sub.GetTasks(0).Count -eq 0) {
        $rootFolder.DeleteFolder('SpeedWatch', 0)
        Ok 'Task Scheduler folder removed'
    }
} catch { }

# ---------------------------------------------------------------- shortcut

try {
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'SpeedWatch.lnk'
    if (Test-Path -LiteralPath $lnk) {
        Remove-Item -LiteralPath $lnk -Force
        Ok 'Desktop shortcut removed'
    }
} catch {
    Warn "Could not remove the desktop shortcut: $($_.Exception.Message)"
}

# ---------------------------------------------------------------- data

if (-not $KeepData -and -not $Quiet -and (Test-Path -LiteralPath $DataDir)) {
    Write-Host ''
    $answer = Read-Host '  Also delete the recorded results and images? (y/N)'
    if ($answer -match '^[yY]') {
        try {
            Remove-Item -LiteralPath $DataDir -Recurse -Force
            Ok 'Recorded results deleted'
        } catch {
            Warn "Could not delete the data folder: $($_.Exception.Message)"
        }
    } else {
        Say "Results kept in  $DataDir"
    }
}

Write-Host ''
Ok 'Done. Nothing of SpeedWatch is registered on this machine any more.'
Say 'Delete this folder whenever you like - that is all that is left.'
Write-Host ''

if (-not $Quiet) {
    Write-Host ''
    Read-Host '  Press Enter to close' | Out-Null
}
