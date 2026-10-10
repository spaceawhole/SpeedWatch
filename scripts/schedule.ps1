# SpeedWatch - shared settings and schedule helpers.
# Dot-sourced by install.ps1 and panel.ps1 so there is exactly one place that
# knows how the scheduled task is built.

$SwTaskName = 'SpeedWatch Daily Speedtest'
$SwTaskPath = '\SpeedWatch\'

# Every user-adjustable value lives in settings.json. Defaults are applied here
# and nowhere else, so a missing or partial file always yields a complete,
# validated set. Keys that are not recognised are preserved on save.
$SwDefaults = [ordered]@{
    planMbps          = $null          # download plan, Mb/s. No default: guessing a plan
                                       # would colour every reading against a wrong target.
    planUpMbps        = $null          # upload plan, Mb/s, optional.
    times             = @('14:00')
    bands             = @(25, 50, 75)  # % of plan where red/yellow/white/green change
    retries           = 3
    retryDelaySeconds = 45
    reportDays        = 30             # how far back the report opens on; 0 = everything
}

function ConvertTo-SwMbps {
    <#
      Parses a speed typed by a person into a number of Mb/s, or $null.
      Accepts 1000, 1.000, 1,000, 300, 300.5, 300,5. A dot or comma followed by
      exactly three digits is a thousands separator (common in Spanish and
      German); followed by one or two digits it is a decimal separator.
    #>
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [double] -or $Value -is [int] -or $Value -is [long] -or $Value -is [decimal]) {
        $n = [double]$Value
    } else {
        $t = ([string]$Value).Trim() -replace '\s', ''
        $t = $t -replace '(?i)\s*(mb/?s|mbps|megas?)$', ''
        if ($t -eq '') { return $null }
        if ($t -match '^\d{1,3}([.,]\d{3})+$') {
            $t = $t -replace '[.,]', ''
        } elseif ($t -match '^\d+[.,]\d{1,2}$') {
            $t = $t -replace ',', '.'
        } elseif ($t -notmatch '^\d+$') {
            return $null
        }
        $n = [double]::Parse($t, [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($n -le 0 -or $n -gt 100000) { return $null }
    return $n
}

function ConvertTo-SwReportDays {
    # Days of history the report opens on: a whole number 1-3650, or 0 / "all"
    # for everything. Anything else falls back to the default rather than
    # producing an empty or broken report.
    param($Value)
    if ($null -eq $Value) { return [int]$SwDefaults.reportDays }
    $t = ([string]$Value).Trim()
    if ($t -match '^(all|0)$') { return 0 }
    if ($t -match '^\d{1,4}$') {
        $n = [int]$t
        if ($n -ge 1 -and $n -le 3650) { return $n }
    }
    return [int]$SwDefaults.reportDays
}

function ConvertTo-SwBands {
    # Three ascending percentages between 1 and 100, or the defaults.
    param($Bands)
    try {
        $b = @($Bands | ForEach-Object { [double]$_ })
        if ($b.Count -eq 3 -and $b[0] -gt 0 -and $b[0] -lt $b[1] -and $b[1] -lt $b[2] -and $b[2] -le 100) {
            return $b
        }
    } catch { }
    return @($SwDefaults.bands)
}

function Get-SwSettings {
    param([string]$Root)

    $out = [ordered]@{}
    foreach ($k in $SwDefaults.Keys) { $out[$k] = $SwDefaults[$k] }

    $f = Join-Path $Root 'settings.json'
    $s = $null
    try {
        if (Test-Path -LiteralPath $f) {
            $s = Get-Content -LiteralPath $f -Raw -ErrorAction Stop | ConvertFrom-Json
        }
    } catch { $s = $null }

    if ($s) {
        # carry unknown keys through untouched
        foreach ($p in $s.PSObject.Properties) {
            if (-not $out.Contains($p.Name) -and $p.Name -ne 'note') { $out[$p.Name] = $p.Value }
        }
        $out.planMbps   = ConvertTo-SwMbps $s.planMbps
        $out.planUpMbps = ConvertTo-SwMbps $s.planUpMbps
        if ($s.times) {
            $t = @(ConvertTo-SwTimes ([string[]]@($s.times)))
            if ($t.Count -gt 0) { $out.times = $t }
        }
        if ($null -ne $s.bands) { $out.bands = ConvertTo-SwBands $s.bands }
        try { $out.retries = [int][math]::Min(5, [math]::Max(1, [int]$s.retries)) } catch { }
        if ($null -eq $s.retries) { $out.retries = $SwDefaults.retries }
        try { $out.retryDelaySeconds = [int][math]::Min(120, [math]::Max(10, [int]$s.retryDelaySeconds)) } catch { }
        if ($null -eq $s.retryDelaySeconds) { $out.retryDelaySeconds = $SwDefaults.retryDelaySeconds }
        $out.reportDays = ConvertTo-SwReportDays $s.reportDays
    }
    return $out
}

function Save-SwSettings {
    param([string]$Root, $Settings)

    $obj = [ordered]@{}
    $obj.planMbps          = if ($null -ne $Settings.planMbps)   { [double]$Settings.planMbps }   else { $null }
    $obj.planUpMbps        = if ($null -ne $Settings.planUpMbps) { [double]$Settings.planUpMbps } else { $null }
    $obj.times             = @($Settings.times)
    $obj.bands             = @(ConvertTo-SwBands $Settings.bands)
    $obj.retries           = [int]$Settings.retries
    $obj.retryDelaySeconds = [int]$Settings.retryDelaySeconds
    $obj.reportDays        = ConvertTo-SwReportDays $Settings.reportDays
    foreach ($k in @($Settings.Keys)) {
        if (-not $obj.Contains($k) -and $k -ne 'note') { $obj[$k] = $Settings[$k] }
    }
    $obj.note = 'Speeds are MEGABITS per second (Mb/s), not megabytes. planMbps = the download speed your plan is sold at (1000 megas / 1 Gbps = 1000). planUpMbps = its upload speed, optional. times = 24-hour HH:MM, one test at each. bands = % of plan where colours change: under the 1st red, then yellow, white, and green from the 3rd up. retries / retryDelaySeconds = how hard to try before falling back to Cloudflare. reportDays = how many days back the report opens on (0 = everything); the report remembers the last range you pick. Plan and times can be changed from the SpeedWatch panel.'

    $json = $obj | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $Root 'settings.json'), $json, (New-Object Text.UTF8Encoding $false))
    Write-SwReportSettings -Root $Root -Settings $obj
}

function Write-SwReportSettings {
    # The report is a local HTML file and cannot read settings.json itself
    # (browsers block file:// fetches), so a copy is written as a script it can
    # load. Written on every save, so the report reflects a changed plan at
    # once rather than after the next test.
    param([string]$Root, $Settings)
    try {
        $d = Join-Path $Root 'data'
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        $pub = [ordered]@{
            planMbps   = $Settings.planMbps
            planUpMbps = $Settings.planUpMbps
            bands      = @(ConvertTo-SwBands $Settings.bands)
            times      = @($Settings.times)
            reportDays = ConvertTo-SwReportDays $Settings.reportDays
        }
        $js = "window.SPEEDWATCH_SETTINGS = " + ($pub | ConvertTo-Json -Depth 4 -Compress) + ";`r`n"
        [IO.File]::WriteAllText((Join-Path $d 'settings.js'), $js, (New-Object Text.UTF8Encoding $false))
    } catch { }
}

function ConvertTo-SwTimes {
    # Normalises free-typed times to HH:MM, drops anything invalid, sorts, dedupes.
    param([string[]]$Times)

    $clean = New-Object System.Collections.ArrayList
    foreach ($raw in @($Times)) {
        $t = ([string]$raw).Trim()
        if ($t -match '^(\d{1,2})[:.\s]?(\d{2})$') {
            $h = [int]$Matches[1]; $m = [int]$Matches[2]
            if ($h -ge 0 -and $h -le 23 -and $m -ge 0 -and $m -le 59) {
                # Build the string first. Inside a method call, .Add('..' -f $h, $m)
                # is parsed as TWO arguments - the comma binds to the argument list,
                # not to the -f operator - so the format string loses {1}.
                $norm = '{0:00}:{1:00}' -f $h, $m
                [void]$clean.Add($norm)
            }
        }
    }
    return @($clean | Sort-Object -Unique)
}

function Get-SwGrade {
    <#
      Turns "share of the contracted plan" into a band name. Defined once here
      so the panel and the report can never disagree about what counts as bad.

        Defaults (settings.json "bands": [25, 50, 75]):
        under 25%  red     - a small fraction of what was paid for
        25 - 50%   yellow  - clearly short
        50 - 75%   white   - below par but not alarming
        75% and up green   - the plan, near enough
    #>
    param([double]$Percent, $Bands = $null)

    $b = ConvertTo-SwBands $(if ($null -ne $Bands) { $Bands } else { $SwDefaults.bands })
    if ($Percent -lt $b[0]) { return 'red' }
    if ($Percent -lt $b[1]) { return 'yellow' }
    if ($Percent -lt $b[2]) { return 'white' }
    return 'green'
}

function Repair-SwText {
    <#
      Undoes mojibake in text captured from speedtest.exe before the console
      encoding was fixed: the CLI writes UTF-8, but Windows PowerShell decoded it
      with the OEM code page, so an accented a (U+00E1) came out as U+251C U+00ED:
      "Bogota" with an accent was stored with a box-drawing character in it.

      Only text containing the tell-tale box-drawing lead characters is touched,
      and only when it converts back losslessly into valid UTF-8, so correct
      text - including correct accented text - passes through unchanged.
    #>
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text) -or $Text.IndexOfAny([char[]]@([char]0x251C, [char]0x252C)) -lt 0) { return $Text }
    try {
        # .NET Core (PowerShell 7) needs the legacy code pages registered first.
        $prov = 'System.Text.CodePagesEncodingProvider' -as [type]
        if ($prov) { [System.Text.Encoding]::RegisterProvider($prov::Instance) }
    } catch { }
    foreach ($cp in 850, 437) {
        try {
            $enc   = [System.Text.Encoding]::GetEncoding($cp)
            $bytes = $enc.GetBytes($Text)
            if ($enc.GetString($bytes) -ne $Text) { continue }         # not a lossless round trip
            $strict = New-Object System.Text.UTF8Encoding($false, $true)
            return $strict.GetString($bytes)                            # throws if not valid UTF-8
        } catch { }
    }
    return $Text
}

function Write-SwReportData {
    <#
      Rebuilds data\history.js - the copy of the history the report reads - from
      history.ndjson, which stays the untouched record of every run. Called after
      each test and whenever the panel opens the report, so the report is always
      current. Carries the newest $MaxRuns runs plus the true total, so the report
      can say when older readings are not included.
    #>
    param([string]$Root, $Settings, [int]$MaxRuns = 5000)

    $d    = Join-Path $Root 'data'
    $src  = Join-Path $d 'history.ndjson'
    $dest = Join-Path $d 'history.js'
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }

    $all = @()
    if (Test-Path -LiteralPath $src) {
        $all = @(Get-Content -LiteralPath $src -Encoding UTF8 -ErrorAction SilentlyContinue |
                 Where-Object { $_.Trim().Length -gt 0 } |
                 ForEach-Object { Repair-SwText $_ })
    }
    $total = $all.Count
    if ($all.Count -gt $MaxRuns) { $all = $all[($all.Count - $MaxRuns)..($all.Count - 1)] }

    $plan = 'null'
    if ($Settings -and $null -ne $Settings.planMbps) {
        $plan = ([double]$Settings.planMbps).ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    $js = "window.SPEEDWATCH = {`r`n" +
          "  generated: " + ((Get-Date).ToString('o') | ConvertTo-Json) + ",`r`n" +
          "  planMbps: $plan,`r`n" +
          "  total: $total,`r`n" +
          "  runs: [`r`n" + ($all -join ",`r`n") + "`r`n  ]`r`n};`r`n"
    [IO.File]::WriteAllText($dest, $js, (New-Object Text.UTF8Encoding $false))
}

function New-SwTriggers {
    param([string[]]$Times)
    $triggers = @()
    foreach ($t in (ConvertTo-SwTimes $Times)) {
        $p  = $t.Split(':')
        $at = (Get-Date).Date.AddHours([int]$p[0]).AddMinutes([int]$p[1])
        $triggers += New-ScheduledTaskTrigger -Daily -At $at
    }
    return $triggers
}

function Write-SwLog {
    param([string]$Root, [string]$Message)
    try {
        $d = Join-Path $Root 'data'
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        Add-Content -LiteralPath (Join-Path $d 'speedwatch.log') -Encoding UTF8 `
            -Value ('{0}  {1,-5}  {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), 'PANEL', $Message)
    } catch { }
}

function Set-SwSchedule {
    <#
      Applies the given times to the scheduled task.

      The task is always rebuilt with Register-ScheduledTask -Force rather than
      patched with Set-ScheduledTask: -Force re-registration is the path the
      installer uses and is reliable, whereas Set-ScheduledTask on a task that
      carries a principal fails on some systems. Rebuilding keeps one code path
      for "create" and "change", so the panel and the installer cannot diverge.

      A task that is currently disabled stays disabled - changing the schedule
      must never silently switch SpeedWatch back on.

      Returns the normalised list of times actually applied.
    #>
    param([string]$Root, [string[]]$Times)

    $times = ConvertTo-SwTimes $Times
    if ($times.Count -eq 0) { $times = @('14:00') }
    $triggers = @(New-SwTriggers $times)
    if ($triggers.Count -eq 0) { throw 'No valid trigger times.' }

    $existing = Get-ScheduledTask -TaskName $SwTaskName -TaskPath $SwTaskPath -ErrorAction SilentlyContinue
    $wasDisabled = ($null -ne $existing -and $existing.State -eq 'Disabled')

    $vbs = Join-Path $Root 'scripts\run-hidden.vbs'
    $action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//nologo "{0}"' -f $vbs)

    # StartWhenAvailable covers "the PC was off at the scheduled time" - Windows
    # runs the missed occurrence once the machine is back.
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -RunOnlyIfNetworkAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 20) `
        -Compatibility Win8

    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                                            -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $SwTaskName -TaskPath $SwTaskPath `
        -Action $action -Trigger $triggers -Settings $settings -Principal $principal `
        -Description 'Takes a speed test reading and records it. Part of SpeedWatch.' `
        -Force | Out-Null

    if ($wasDisabled) {
        Disable-ScheduledTask -TaskName $SwTaskName -TaskPath $SwTaskPath | Out-Null
    }

    Write-SwLog -Root $Root -Message ("Schedule set to: " + ($times -join ', '))
    return $times
}

function Get-SwLastDueTime {
    # The most recent scheduled moment that has already passed today, if any.
    # Used to decide whether a reading is owed after switching back on.
    param([string[]]$Times)

    $now = Get-Date
    $due = $null
    foreach ($t in (ConvertTo-SwTimes $Times)) {
        $p = $t.Split(':')
        $d = $now.Date.AddHours([int]$p[0]).AddMinutes([int]$p[1])
        if ($d -le $now -and ($null -eq $due -or $d -gt $due)) { $due = $d }
    }
    return $due
}
