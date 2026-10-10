# SpeedWatch - installer
# Creates one scheduled task (with a trigger per configured time) and, if needed,
# fetches the Ookla Speedtest CLI. No service, no startup entry, no admin rights.
# Everything lives in this folder plus a single Task Scheduler entry, both removed
# by Uninstall.cmd.

[CmdletBinding()]
param(
    [string[]]$Times,
    [string]$PlanMbps,        # download plan in Mb/s, e.g. 1000 (also accepts 1.000)
    [string]$PlanUpMbps,      # upload plan in Mb/s, optional
    [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$Root   = Split-Path -Parent $PSScriptRoot
$DataDir = Join-Path $Root 'data'
$BinDir  = Join-Path $Root 'bin'

. (Join-Path $PSScriptRoot 'schedule.ps1')

function Say  { param($m) Write-Host "  $m" }
function Ok   { param($m) Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Fail { param($m) Write-Host "  [x]  $m" -ForegroundColor Red }

Write-Host ''
Write-Host '  SpeedWatch - setup' -ForegroundColor Cyan
Write-Host '  ------------------'
Write-Host ''

# ---------------------------------------------------------------- folders

foreach ($d in @($DataDir, (Join-Path $DataDir 'images'), $BinDir)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
Ok "Folders ready under $Root"

# Files extracted from a downloaded zip carry Windows' "came from the internet"
# mark. On the .vbs launchers that can make Windows stop and ask before running
# them - and for the background test nobody would ever see that question, so
# tests would silently never run. Running Install.cmd is the person saying yes,
# so clear the mark on SpeedWatch's own files (and only those).
try {
    $marked = @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction Stop |
                Where-Object { Get-Item -LiteralPath $_.FullName -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue })
    if ($marked.Count) {
        $marked | Unblock-File -ErrorAction SilentlyContinue
        Ok ("Cleared the downloaded-from-internet mark on {0} SpeedWatch file(s)" -f $marked.Count)
    }
} catch { }

# ---------------------------------------------------------------- settings

$settings = Get-SwSettings -Root $Root
if ($PlanMbps) {
    $p = ConvertTo-SwMbps $PlanMbps
    if ($null -eq $p) { Warn "Ignoring -PlanMbps '$PlanMbps': use a number in Mb/s, for example 1000" }
    else { $settings.planMbps = $p }
}
if ($PlanUpMbps) {
    $p = ConvertTo-SwMbps $PlanUpMbps
    if ($null -eq $p) { Warn "Ignoring -PlanUpMbps '$PlanUpMbps': use a number in Mb/s, for example 100" }
    else { $settings.planUpMbps = $p }
}
if ($Times)          { $settings.times    = @(ConvertTo-SwTimes $Times) }
if (@($settings.times).Count -eq 0) { $settings.times = @('14:00') }
Save-SwSettings -Root $Root -Settings $settings

if ($null -ne $settings.planMbps) {
    Ok ("Plan: {0} Mb/s download (megabits per second)" -f [int]$settings.planMbps)
    Say '     change it any time from the SpeedWatch panel'
} else {
    Warn 'Plan speed not set yet.'
    Say '     Open the SpeedWatch panel and enter the speed your plan is sold at,'
    Say '     in Mb/s (a 1000 megas plan is 1000). Until then readings are shown'
    Say '     without colours, because there is nothing to compare them against.'
}

# ---------------------------------------------------------------- speedtest CLI

function Resolve-SpeedtestExe {
    $candidates = @(
        (Join-Path $Root 'bin\speedtest.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\speedtest.exe')
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    $cmd = Get-Command 'speedtest.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$exe = Resolve-SpeedtestExe

if (-not $exe) {
    Say 'Speedtest CLI not found. Trying winget...'
    $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($winget) {
        try {
            & $winget.Source install --id Ookla.Speedtest.CLI -e --source winget `
                --accept-package-agreements --accept-source-agreements | Out-Null
        } catch { Warn "winget could not install it: $($_.Exception.Message)" }
        $exe = Resolve-SpeedtestExe
    } else {
        Warn 'winget is not available on this machine.'
    }
}

if (-not $exe) {
    Say 'Trying a direct download...'
    $zipUrl = 'https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip'
    $zip    = Join-Path $env:TEMP 'ookla-speedtest-cli.zip'
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing -TimeoutSec 120
        Expand-Archive -LiteralPath $zip -DestinationPath $BinDir -Force
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        $exe = Resolve-SpeedtestExe
    } catch { Warn "Direct download failed: $($_.Exception.Message)" }
}

if ($exe) {
    Ok "Speed test engine: $exe"
} else {
    Fail 'Could not obtain the Speedtest CLI automatically.'
    Say ''
    Say 'Install it yourself, then run Install.cmd again:'
    Say '    winget install Ookla.Speedtest.CLI'
    Say "    (or download the Windows CLI from https://www.speedtest.net/apps/cli"
    Say "     and drop speedtest.exe into  $BinDir )"
    Say ''
    Say 'SpeedWatch can still record readings without it - it falls back to'
    Say 'Cloudflare - but you lose the shareable speedtest.net result card.'
    Say ''
}

# ---------------------------------------------------------------- scheduled task

try {
    $applied = Set-SwSchedule -Root $Root -Times $settings.times
    $settings.times = $applied
    Save-SwSettings -Root $Root -Settings $settings

    if ($applied.Count -eq 1) { Ok "Scheduled task created - one test a day at $($applied[0])" }
    else { Ok ("Scheduled task created - {0} tests a day at {1}" -f $applied.Count, ($applied -join ', ')) }
    Ok 'Missed runs (PC off or asleep) run as soon as the PC is available'
    Say '     add or remove times from the SpeedWatch panel at any time'
}
catch {
    Fail "Could not create the scheduled task: $($_.Exception.Message)"
    exit 1
}

# ---------------------------------------------------------------- seed + shortcut

$jsFile = Join-Path $DataDir 'history.js'
if (-not (Test-Path -LiteralPath $jsFile)) {
    $seed = "window.SPEEDWATCH = {`r`n  generated: null,`r`n  planMbps: $(if ($null -ne $settings.planMbps) { [int]$settings.planMbps } else { 'null' }),`r`n  runs: []`r`n};`r`n"
    [IO.File]::WriteAllText($jsFile, $seed, (New-Object Text.UTF8Encoding $false))
}

if (-not $NoShortcut) {
    try {
        $lnk   = Join-Path ([Environment]::GetFolderPath('Desktop')) 'SpeedWatch.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $s     = $shell.CreateShortcut($lnk)
        # Point straight at wscript so opening the panel never flashes a console.
        $s.TargetPath       = 'wscript.exe'
        $s.Arguments        = '//nologo "{0}"' -f (Join-Path $PSScriptRoot 'panel-hidden.vbs')
        $s.WorkingDirectory = $Root
        $s.IconLocation     = 'powershell.exe,0'
        $s.Description      = 'SpeedWatch - connection monitor'
        $s.Save()
        Ok 'Desktop shortcut created'
    } catch {
        Warn "Could not create the desktop shortcut: $($_.Exception.Message)"
    }
}

Write-Host ''
Ok 'Setup complete.'
Write-Host ''
Say 'Open SpeedWatch.cmd (or the desktop shortcut) to turn it on, change the'
Say 'test times, run a test now, or see the report. To remove everything, run'
Say 'Uninstall.cmd and then delete this folder.'
Write-Host ''
