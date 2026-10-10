# SpeedWatch - tests for the pure logic in schedule.ps1.
# Runs anywhere PowerShell runs; touches no scheduled tasks and no real settings.

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\schedule.ps1')

$script:pass = 0
$script:fail = 0

function Check {
    param([string]$Name, $Expected, $Actual)
    $e = ($Expected -join '|'); $a = ($Actual -join '|')
    if ($e -eq $a) { $script:pass++; Write-Host ("  PASS  {0}" -f $Name) -ForegroundColor Green }
    else {
        $script:fail++
        Write-Host ("  FAIL  {0}`n        expected [{1}]`n        actual   [{2}]" -f $Name, $e, $a) -ForegroundColor Red
    }
}

Write-Host "`nConvertTo-SwTimes" -ForegroundColor Cyan
Check '1551 -> 15:51'        @('15:51')  (ConvertTo-SwTimes @('1551'))
Check '15:51 stays'          @('15:51')  (ConvertTo-SwTimes @('15:51'))
Check '15.51 -> 15:51'       @('15:51')  (ConvertTo-SwTimes @('15.51'))
Check '930 -> 09:30'         @('09:30')  (ConvertTo-SwTimes @('930'))
Check '9:30 -> 09:30'        @('09:30')  (ConvertTo-SwTimes @('9:30'))
Check '0000 -> 00:00'        @('00:00')  (ConvertTo-SwTimes @('0000'))
Check '2359 -> 23:59'        @('23:59')  (ConvertTo-SwTimes @('2359'))
Check 'whitespace trimmed'   @('14:00')  (ConvertTo-SwTimes @('  14:00  '))
Check 'sorted + deduped'     @('09:00','14:00','21:00') (ConvertTo-SwTimes @('21:00','09:00','14:00','2100'))
Check 'hour 24 rejected'     @()         (ConvertTo-SwTimes @('24:00'))
Check 'minute 60 rejected'   @()         (ConvertTo-SwTimes @('12:60'))
Check 'letters rejected'     @()         (ConvertTo-SwTimes @('abc'))
Check 'empty rejected'       @()         (ConvertTo-SwTimes @(''))
Check 'junk dropped, rest kept' @('14:00') (ConvertTo-SwTimes @('nope','14:00'))
Check 'empty input'          @()         (ConvertTo-SwTimes @())

Write-Host "`nsettings round-trip" -ForegroundColor Cyan
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("swtest_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $d = Get-SwSettings -Root $tmp
    Check 'defaults: plan unset' $true ($null -eq $d.planMbps)
    Check 'defaults: times'  @('14:00') $d.times

    $d.planMbps = 300
    $d.times    = @('09:30','21:00')
    Save-SwSettings -Root $tmp -Settings $d

    $r = Get-SwSettings -Root $tmp
    Check 'saved plan reloads'  300                  $r.planMbps
    Check 'saved times reload'  @('09:30','21:00')   $r.times
    Check 'file is valid JSON'  $true ((Get-Content (Join-Path $tmp 'settings.json') -Raw | ConvertFrom-Json) -ne $null)

    # a settings file written by hand, with loose times
    Set-Content -Path (Join-Path $tmp 'settings.json') -Encoding UTF8 -Value '{ "planMbps": 500, "times": ["800","2015","bad"] }'
    $h = Get-SwSettings -Root $tmp
    Check 'hand-edited plan'    500                 $h.planMbps
    Check 'hand-edited times'   @('08:00','20:15')  $h.times

    # corrupt file must not throw - fall back to defaults
    Set-Content -Path (Join-Path $tmp 'settings.json') -Encoding UTF8 -Value '{ not json'
    $c = Get-SwSettings -Root $tmp
    Check 'corrupt file -> defaults' @('14:00') $c.times
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host "`nGet-SwLastDueTime" -ForegroundColor Cyan
$midnightOnly = Get-SwLastDueTime -Times @('00:00')
Check 'a past time is returned'  $true  ($null -ne $midnightOnly)
$future = Get-SwLastDueTime -Times @('23:59')
$expectFuture = if ((Get-Date).Hour -eq 23 -and (Get-Date).Minute -ge 59) { $true } else { $null -eq $future }
Check 'a future-only time gives nothing' $true $expectFuture

Write-Host "`nGet-SwGrade" -ForegroundColor Cyan
Check 'zero -> red'          'red'    (Get-SwGrade 0)
Check '0.65% -> red'         'red'    (Get-SwGrade 0.65)
Check '24.99% -> red'        'red'    (Get-SwGrade 24.99)
Check '25% -> yellow'        'yellow' (Get-SwGrade 25)
Check '49.99% -> yellow'     'yellow' (Get-SwGrade 49.99)
Check '50% -> white'         'white'  (Get-SwGrade 50)
Check '74.99% -> white'      'white'  (Get-SwGrade 74.99)
Check '75% -> green'         'green'  (Get-SwGrade 75)
Check '92% -> green'         'green'  (Get-SwGrade 92)
Check '100% -> green'        'green'  (Get-SwGrade 100)
Check 'over 100 -> green'    'green'  (Get-SwGrade 140)

Write-Host "`nGet-SwGrade with custom bands" -ForegroundColor Cyan
Check '[10,40,90]: 9 -> red'      'red'    (Get-SwGrade 9  @(10,40,90))
Check '[10,40,90]: 10 -> yellow'  'yellow' (Get-SwGrade 10 @(10,40,90))
Check '[10,40,90]: 60 -> white'   'white'  (Get-SwGrade 60 @(10,40,90))
Check '[10,40,90]: 89 -> white'   'white'  (Get-SwGrade 89 @(10,40,90))
Check '[10,40,90]: 90 -> green'   'green'  (Get-SwGrade 90 @(10,40,90))
Check 'bad bands fall back'       'red'    (Get-SwGrade 24 @(50,40,30))

Write-Host "`nConvertTo-SwMbps (what a person types)" -ForegroundColor Cyan
Check '1000'              1000  (ConvertTo-SwMbps '1000')
Check '1.000 (es thousands)' 1000 (ConvertTo-SwMbps '1.000')
Check '1,000 (en thousands)' 1000 (ConvertTo-SwMbps '1,000')
Check '300'               300   (ConvertTo-SwMbps '300')
Check '300,5 (es decimal)' 300.5 (ConvertTo-SwMbps '300,5')
Check '300.5'             300.5 (ConvertTo-SwMbps '300.5')
Check '  600 Mbps '       600   (ConvertTo-SwMbps '  600 Mbps ')
Check '1000 megas'        1000  (ConvertTo-SwMbps '1000 megas')
Check 'numeric input'     1000  (ConvertTo-SwMbps 1000)
Check 'blank -> null'     $true ($null -eq (ConvertTo-SwMbps ''))
Check 'zero -> null'      $true ($null -eq (ConvertTo-SwMbps '0'))
Check 'negative -> null'  $true ($null -eq (ConvertTo-SwMbps '-5'))
Check 'text -> null'      $true ($null -eq (ConvertTo-SwMbps 'fast'))
Check 'absurd -> null'    $true ($null -eq (ConvertTo-SwMbps '9999999'))

Write-Host "`nsettings: new keys" -ForegroundColor Cyan
$tmp2 = Join-Path ([IO.Path]::GetTempPath()) ("swtest_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp2 -Force | Out-Null
try {
    $d = Get-SwSettings -Root $tmp2
    Check 'no file: plan is unset'     $true ($null -eq $d.planMbps)
    Check 'no file: upload unset'      $true ($null -eq $d.planUpMbps)
    Check 'no file: default bands'     @(25,50,75) $d.bands
    Check 'no file: default retries'   3  $d.retries
    Check 'no file: default delay'     45 $d.retryDelaySeconds

    # a settings.json from the previous version - must upgrade cleanly
    Set-Content -Path (Join-Path $tmp2 'settings.json') -Encoding UTF8 -Value '{ "planMbps": 1000, "times": ["12:00","19:00","23:00"], "note": "old" }'
    $o = Get-SwSettings -Root $tmp2
    Check 'old file: plan kept'        1000 $o.planMbps
    Check 'old file: times kept'       @('12:00','19:00','23:00') $o.times
    Check 'old file: bands defaulted'  @(25,50,75) $o.bands

    # save and reload everything, including an unknown key
    $o.planUpMbps = 100
    $o.bands = @(20, 60, 85)
    $o.retries = 4
    $o['myOwnKey'] = 'keep me'
    Save-SwSettings -Root $tmp2 -Settings $o
    $r = Get-SwSettings -Root $tmp2
    Check 'upload plan saved'          100 $r.planUpMbps
    Check 'bands saved'                @(20,60,85) $r.bands
    Check 'retries saved'              4 $r.retries
    Check 'unknown key preserved'      'keep me' $r.myOwnKey
    Check 'settings.js written for report' $true (Test-Path (Join-Path $tmp2 'data\settings.js'))
    $js = Get-Content (Join-Path $tmp2 'data\settings.js') -Raw
    Check 'settings.js carries the plan'   $true ($js -match '"planMbps":1000')
    # PowerShell 7 writes 20.0 where Windows PowerShell 5.1 writes 20 - both are valid
    Check 'settings.js carries the bands'  $true ($js -match '"bands":\[20(\.0)?,60(\.0)?,85(\.0)?\]')

    # out-of-range values are clamped, not trusted
    Set-Content -Path (Join-Path $tmp2 'settings.json') -Encoding UTF8 -Value '{ "planMbps": "1.000", "retries": 99, "retryDelaySeconds": 1, "bands": [90, 10, 5] }'
    $c = Get-SwSettings -Root $tmp2
    Check 'string plan with separator' 1000 $c.planMbps
    Check 'retries clamped to 5'       5  $c.retries
    Check 'delay clamped to 10'        10 $c.retryDelaySeconds
    Check 'bad bands -> defaults'      @(25,50,75) $c.bands
}
finally { Remove-Item -LiteralPath $tmp2 -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host "`nConvertTo-SwReportDays" -ForegroundColor Cyan
Check 'default when missing'   30   (ConvertTo-SwReportDays $null)
Check '7 stays 7'              7    (ConvertTo-SwReportDays 7)
Check '"90" from JSON text'    90   (ConvertTo-SwReportDays '90')
Check '0 means everything'     0    (ConvertTo-SwReportDays 0)
Check '"all" means everything' 0    (ConvertTo-SwReportDays 'all')
Check '3650 allowed'           3650 (ConvertTo-SwReportDays 3650)
Check '3651 -> default'        30   (ConvertTo-SwReportDays 3651)
Check 'negative -> default'    30   (ConvertTo-SwReportDays -5)
Check 'fraction -> default'    30   (ConvertTo-SwReportDays 7.5)
Check 'junk -> default'        30   (ConvertTo-SwReportDays 'lots')
Check 'huge -> default'        30   (ConvertTo-SwReportDays '99999999999')

$tmp2 = Join-Path ([IO.Path]::GetTempPath()) ("swtest_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp2 -Force | Out-Null
try {
    Set-Content -Path (Join-Path $tmp2 'settings.json') -Encoding UTF8 -Value '{ "planMbps": 1000, "reportDays": 14 }'
    $st = Get-SwSettings -Root $tmp2
    Check 'reportDays loads'              14 $st.reportDays
    Save-SwSettings -Root $tmp2 -Settings $st
    Check 'reportDays survives a save'    14 (Get-SwSettings -Root $tmp2).reportDays
    $pub = Get-Content (Join-Path $tmp2 'data/settings.js') -Raw
    Check 'reportDays reaches the report' $true ($pub -match '"reportDays":14')
    Set-Content -Path (Join-Path $tmp2 'settings.json') -Encoding UTF8 -Value '{ "planMbps": 1000 }'
    Check 'older settings file -> 30'     30 (Get-SwSettings -Root $tmp2).reportDays
} finally { Remove-Item -LiteralPath $tmp2 -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host "`nRepair-SwText (names mangled by the old console decoding)" -ForegroundColor Cyan
Check 'Bogot[box]i -> Bogota'      "Bogot$([char]0xE1)"       (Repair-SwText "Bogot$([char]0x251C)$([char]0xED)")
Check 'Ca[box]uelas -> Canuelas'   "Ca$([char]0xF1)uelas"     (Repair-SwText "Ca$([char]0x251C)$([char]0x2592)uelas")
Check 'correct accents untouched'  "Bogot$([char]0xE1)"       (Repair-SwText "Bogot$([char]0xE1)")
Check 'plain ASCII untouched'      'Example Net - Springfield' (Repair-SwText 'Example Net - Springfield')
Check 'lone box char left alone'   "a $([char]0x251C) b"      (Repair-SwText "a $([char]0x251C) b")
Check 'null-safe'                  ''                         (Repair-SwText $null)

Write-Host "`nScript encoding" -ForegroundColor Cyan
# Windows PowerShell 5.1 reads a .ps1 without a BOM in the ANSI code page, so any
# non-ASCII character in code silently becomes something else there. Keep them ASCII.
$scriptsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
foreach ($f in Get-ChildItem -LiteralPath $scriptsDir -Filter *.ps1) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count
    Check ("{0} is ASCII (or has a BOM)" -f $f.Name) $true ($hasBom -or $nonAscii -eq 0)
}

Write-Host ""
Write-Host ("  {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
Write-Host ""
if ($script:fail) { exit 1 }
