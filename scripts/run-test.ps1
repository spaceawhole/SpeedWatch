# SpeedWatch - worker
# Takes one reading of the connection and exits. Nothing stays resident.
#
# Engines, in order:
#   1. Ookla Speedtest CLI  - preferred: produces a speedtest.net result URL
#                             and the shareable result card.
#   2. Cloudflare           - fallback when Ookla is unreachable, so an outage
#                             at one provider never costs a day's reading.
# Each record says which engine produced it.

[CmdletBinding()]
param(
    [switch]$Manual,
    [int]$Attempts = 0,            # 0 = use settings.json (retries)
    [int]$RetryDelaySeconds = 0,   # 0 = use settings.json (retryDelaySeconds)
    [switch]$NoFallback
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$Root    = Split-Path -Parent $PSScriptRoot
$DataDir = Join-Path $Root 'data'
$ImgDir  = Join-Path $DataDir 'images'
$History = Join-Path $DataDir 'history.ndjson'
$LogFile = Join-Path $DataDir 'speedwatch.log'
$MaxLogLines     = 500

. (Join-Path $PSScriptRoot 'schedule.ps1')
$Settings = Get-SwSettings -Root $Root
if ($Attempts -le 0)          { $Attempts          = [int]$Settings.retries }
if ($RetryDelaySeconds -le 0) { $RetryDelaySeconds = [int]$Settings.retryDelaySeconds }

foreach ($d in @($DataDir, $ImgDir)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0}  {1,-5}  {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch { }
}

function Trim-Log {
    try {
        if (-not (Test-Path -LiteralPath $LogFile)) { return }
        $lines = @(Get-Content -LiteralPath $LogFile -ErrorAction Stop)
        if ($lines.Count -gt $MaxLogLines) {
            Set-Content -LiteralPath $LogFile -Encoding UTF8 `
                -Value $lines[($lines.Count - $MaxLogLines)..($lines.Count - 1)]
        }
    } catch { }
}

function Resolve-SpeedtestExe {
    $local = Join-Path $Root 'bin\speedtest.exe'
    if (Test-Path -LiteralPath $local) { return $local }
    $winget = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\speedtest.exe'
    if (Test-Path -LiteralPath $winget) { return $winget }
    $cmd = Get-Command 'speedtest.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-RootMessage {
    # WaitAll wraps failures in an AggregateException whose message is only
    # "One or more errors occurred." Walk down to the error that actually happened.
    param($Exception)
    $e = $Exception
    while ($e) {
        if ($e -is [System.AggregateException] -and $e.InnerExceptions.Count) { $e = $e.InnerExceptions[0]; continue }
        if ($e.InnerException -and $e.Message -match 'One or more errors|Exception calling') { $e = $e.InnerException; continue }
        break
    }
    if ($e) { return $e.Message } else { return [string]$Exception }
}

function Get-Num {
    param($Value, $Default = $null)
    if ($null -eq $Value) { return $Default }
    try { return [double]$Value } catch { return $Default }
}

# ================================================================ engine 1: Ookla

function Invoke-OoklaOnce {
    param([string]$Exe)

    # speedtest.exe writes UTF-8. Windows PowerShell decodes a program's output
    # with the console code page (850 on Spanish Windows), which turned "Bogota"
    # with an accent into box-drawing garbage. Decode as UTF-8 for the call, then restore.
    $prevEnc = $null
    try { $prevEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    try {
        $raw  = & $Exe --format=json --accept-license --accept-gdpr --progress=no 2>&1
        $exit = $LASTEXITCODE
    } finally {
        if ($prevEnc) { try { [Console]::OutputEncoding = $prevEnc } catch { } }
    }
    $text = ($raw | Out-String).Trim()

    $obj = $null
    foreach ($line in ($text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t.StartsWith('{')) {
            try {
                $c = $t | ConvertFrom-Json
                if ($c.type -eq 'result' -or $c.download) { $obj = $c }
            } catch { }
        }
    }
    if ($obj) { return $obj }

    $detail = ($text -split "`r?`n" |
               Where-Object { $_ -match '\[error\]|error|Cannot|Failed|Unable' } |
               Select-Object -Last 1)
    if (-not $detail) { $detail = ($text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1) }
    if (-not $detail) { $detail = "no output (exit code $exit)" }
    throw ([string]$detail).Trim()
}

function Test-Retryable {
    param([string]$Message)
    return ($Message -match '503|502|504|Cannot retrieve configuration|Configuration|Timeout|timed out|temporarily|Unable to connect|Cannot open socket|Network is unreachable|No servers')
}

# ================================================================ engine 2: Cloudflare
# Same measurement Cloudflare's own speed test page performs: timed transfers
# against speed.cloudflare.com, sized so each phase runs about ten seconds.

function Invoke-CloudflareTest {

    Add-Type -AssemblyName System.Net.Http | Out-Null

    $handler = New-Object System.Net.Http.HttpClientHandler
    try { $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::None } catch { }
    $client  = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(90)

    try {
        $down = 'https://speed.cloudflare.com/__down?bytes={0}'
        $up   = 'https://speed.cloudflare.com/__up'

        # --- where we landed -------------------------------------------------
        $colo = $null; $ispName = $null
        try {
            $meta = $client.GetStringAsync('https://speed.cloudflare.com/meta').GetAwaiter().GetResult() | ConvertFrom-Json
            $colo = [string]$meta.colo
            $ispName = [string]$meta.asOrganization
        } catch { }

        # --- latency ---------------------------------------------------------
        $samples = @()
        for ($i = 0; $i -lt 8; $i++) {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try {
                [void]$client.GetByteArrayAsync(($down -f 0)).GetAwaiter().GetResult()
                $sw.Stop()
                $samples += $sw.Elapsed.TotalMilliseconds
            } catch { $sw.Stop() }
        }
        if ($samples.Count -lt 3) { throw 'Cloudflare endpoint did not respond to latency probes.' }
        $sorted  = $samples | Sort-Object
        $pingMs  = [math]::Round($sorted[0], 1)
        $avg     = ($samples | Measure-Object -Average).Average
        $jitter  = [math]::Round((($samples | ForEach-Object { [math]::Abs($_ - $avg) } |
                                   Measure-Object -Average).Average), 1)

        # --- sizing probe ----------------------------------------------------
        function Measure-Down {
            param([int]$Bytes, [int]$Streams)
            $tasks = @()
            $sw = [Diagnostics.Stopwatch]::StartNew()
            for ($s = 0; $s -lt $Streams; $s++) { $tasks += $client.GetByteArrayAsync(($down -f $Bytes)) }
            [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tasks)
            $sw.Stop()
            $total = 0
            foreach ($t in $tasks) { $total += $t.Result.Length }
            return @{ Bytes = $total; Seconds = [math]::Max($sw.Elapsed.TotalSeconds, 0.001) }
        }

        $probe = Measure-Down -Bytes 2000000 -Streams 1
        $estMbps = ($probe.Bytes * 8 / 1000000) / $probe.Seconds
        if ($estMbps -le 0) { $estMbps = 5 }

        # target ~10 seconds of transfer, clamped to something sane
        # Double literals throughout: an integer first argument makes [math]::Min/Max
        # use the Int32 overload, which overflows above ~1.7 Gb/s and crashes the test.
        $targetBytes = [int][math]::Min(200000000.0, [math]::Max(4000000.0, ($estMbps * 1000000.0 / 8) * 10))
        $streams     = 4
        $perStream   = [int][math]::Max(1000000.0, $targetBytes / $streams)

        $res = Measure-Down -Bytes $perStream -Streams $streams
        $downMbps = [math]::Round((($res.Bytes * 8 / 1000000) / $res.Seconds), 2)

        # --- upload ----------------------------------------------------------
        $upMbps = $null
        try {
            $upTarget = [int][math]::Min(50000000.0, [math]::Max(2000000.0, ($estMbps * 1000000.0 / 8) * 5))
            $perUp    = [int][math]::Max(1000000.0, $upTarget / 2)
            $buffer   = New-Object byte[] $perUp
            (New-Object Random).NextBytes($buffer)

            $tasks = @()
            $sw = [Diagnostics.Stopwatch]::StartNew()
            for ($s = 0; $s -lt 2; $s++) {
                $content = New-Object System.Net.Http.ByteArrayContent(,$buffer)
                $tasks += $client.PostAsync($up, $content)
            }
            [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tasks)
            $sw.Stop()
            $upBytes = [double]$perUp * 2
            $upMbps  = [math]::Round((($upBytes * 8 / 1000000) / [math]::Max($sw.Elapsed.TotalSeconds, 0.001)), 2)
        } catch {
            Write-Log "Cloudflare upload phase failed: $(Get-RootMessage $_.Exception)" 'WARN'
        }

        $serverName = if ($colo) { "Cloudflare - $colo" } else { 'Cloudflare' }

        return @{
            downMbps = $downMbps
            upMbps   = $upMbps
            pingMs   = $pingMs
            jitterMs = $jitter
            server   = $serverName
            isp      = $ispName
        }
    }
    finally {
        try { $client.Dispose() }  catch { }
        try { $handler.Dispose() } catch { }
    }
}

# ================================================================ history

function Write-History {
    param([hashtable]$Record)
    # history.ndjson is the permanent record: one line per run, never rewritten.
    Add-Content -LiteralPath $History -Encoding UTF8 -Value ($Record | ConvertTo-Json -Depth 6 -Compress)
    # history.js is the copy the report reads; rebuilt from the record each time.
    Write-SwReportData -Root $Root -Settings $Settings
}

# ================================================================ run

$startedAt = Get-Date
$source = if ($Manual) { 'manual' } else { 'scheduled' }
Write-Log "Test started ($source)."

$record = @{
    ts        = $startedAt.ToString('o')
    date      = $startedAt.ToString('yyyy-MM-dd')
    time      = $startedAt.ToString('HH:mm')
    source    = $source
    engine    = 'ookla'
    ok        = $false
    error     = $null
    ooklaError = $null
    attempts  = 0
    downMbps  = $null
    upMbps    = $null
    pingMs    = $null
    jitterMs  = $null
    loadedDownMs = $null
    loadedUpMs   = $null
    packetLoss   = $null
    # The plan in force when this reading was taken, so a later plan change
    # does not recolour history.
    planMbps     = $Settings.planMbps
    planUpMbps   = $Settings.planUpMbps
    isp       = $null
    server    = $null
    resultUrl = $null
    image     = $null
}

$ooklaFailure = $null

# ---- engine 1 --------------------------------------------------------------
try {
    $exe = Resolve-SpeedtestExe
    if (-not $exe) { throw 'Speedtest CLI not found. Run Install.cmd again.' }

    $obj = $null; $lastErr = $null
    for ($i = 1; $i -le $Attempts; $i++) {
        $record.attempts = $i
        try { $obj = Invoke-OoklaOnce -Exe $exe; if ($i -gt 1) { Write-Log "Attempt $i succeeded." }; break }
        catch {
            $lastErr = $_.Exception.Message
            if ($i -lt $Attempts -and (Test-Retryable $lastErr)) {
                Write-Log "Attempt $i failed ($lastErr). Retrying in $RetryDelaySeconds s." 'WARN'
                Start-Sleep -Seconds $RetryDelaySeconds
            } else { break }
        }
    }
    if (-not $obj) { throw $lastErr }

    $dBw = Get-Num $obj.download.bandwidth
    $uBw = Get-Num $obj.upload.bandwidth
    if ($null -ne $dBw) { $record.downMbps = [math]::Round($dBw * 8 / 1000000, 2) }
    if ($null -ne $uBw) { $record.upMbps   = [math]::Round($uBw * 8 / 1000000, 2) }

    $p = Get-Num $obj.ping.latency; if ($null -ne $p) { $record.pingMs   = [math]::Round($p, 1) }
    $j = Get-Num $obj.ping.jitter;  if ($null -ne $j) { $record.jitterMs = [math]::Round($j, 1) }
    $ld = Get-Num $obj.download.latency.iqm; if ($null -ne $ld) { $record.loadedDownMs = [math]::Round($ld, 1) }
    $lu = Get-Num $obj.upload.latency.iqm;   if ($null -ne $lu) { $record.loadedUpMs   = [math]::Round($lu, 1) }
    $pl = Get-Num $obj.packetLoss;           if ($null -ne $pl) { $record.packetLoss   = [math]::Round($pl, 2) }

    $record.isp = Repair-SwText ([string]$obj.isp)
    if ($obj.server) {
        $record.server = Repair-SwText ((@($obj.server.name, $obj.server.location) | Where-Object { $_ }) -join ' - ')
    }

    if ($obj.result -and $obj.result.url) {
        $record.resultUrl = [string]$obj.result.url
        $imgName = $startedAt.ToString('yyyy-MM-dd_HHmm') + '.png'
        $imgPath = Join-Path $ImgDir $imgName
        try {
            Invoke-WebRequest -Uri ($record.resultUrl + '.png') -OutFile $imgPath -UseBasicParsing -TimeoutSec 60
            if ((Get-Item -LiteralPath $imgPath).Length -gt 1024) { $record.image = "images/$imgName" }
            else { Remove-Item -LiteralPath $imgPath -Force -ErrorAction SilentlyContinue }
        } catch { Write-Log "Could not download the result image: $($_.Exception.Message)" 'WARN' }
    }

    $record.ok = $true
    Write-Log ("Test finished (Ookla): {0} Mbps down / {1} Mbps up, ping {2} ms." -f
               $record.downMbps, $record.upMbps, $record.pingMs)
}
catch {
    $ooklaFailure = $_.Exception.Message
    Write-Log ("Ookla failed after {0} attempt(s): {1}" -f $record.attempts, $ooklaFailure) 'ERROR'
}

# ---- engine 2 --------------------------------------------------------------
if (-not $record.ok -and -not $NoFallback) {
    Write-Log 'Falling back to Cloudflare.'
    try {
        $cf = Invoke-CloudflareTest
        $record.engine     = 'cloudflare'
        $record.ok         = $true
        $record.ooklaError = $ooklaFailure
        $record.downMbps   = $cf.downMbps
        $record.upMbps     = $cf.upMbps
        $record.pingMs     = $cf.pingMs
        $record.jitterMs   = $cf.jitterMs
        $record.server     = $cf.server
        $record.isp        = $cf.isp
        Write-Log ("Test finished (Cloudflare fallback): {0} Mbps down / {1} Mbps up, ping {2} ms." -f
                   $record.downMbps, $record.upMbps, $record.pingMs)
    }
    catch {
        $record.ok    = $false
        $cfMsg = Get-RootMessage $_.Exception
        $record.error = "Ookla: $ooklaFailure | Cloudflare: $cfMsg"
        Write-Log "Cloudflare fallback also failed: $cfMsg" 'ERROR'
    }
}
elseif (-not $record.ok) {
    $record.error = $ooklaFailure
}

try { Write-History -Record $record }
catch { Write-Log "Could not write history: $($_.Exception.Message)" 'ERROR' }

# keep the report's copy of the settings current
Write-SwReportSettings -Root $Root -Settings $Settings

Trim-Log

if ($Manual) {
    if ($record.ok) { Write-Host ("Done ({0}) - {1} Mbps down / {2} Mbps up" -f $record.engine, $record.downMbps, $record.upMbps) }
    else            { Write-Host "Test failed: $($record.error)" }
}

exit 0
