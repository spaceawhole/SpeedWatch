# SpeedWatch - checks on the control panel that do not need a window.
# Validates every XAML block (a missing namespace once disabled all button
# styling silently), checks each control the code looks up exists, and
# exercises the panel's pure helper functions.

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $PSScriptRoot
$panel = Join-Path $root 'scripts\panel.ps1'
. (Join-Path $root 'scripts\schedule.ps1')

$script:pass = 0; $script:fail = 0
function Check {
    param([string]$Name, $Expected, $Actual)
    if ("$Expected" -eq "$Actual") { $script:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL  $Name`n        expected [$Expected]`n        actual   [$Actual]" -ForegroundColor Red }
}

$src = Get-Content -LiteralPath $panel -Raw
$ast = [System.Management.Automation.Language.Parser]::ParseFile($panel, [ref]$null, [ref]$null)

Write-Host "`nXAML" -ForegroundColor Cyan
foreach ($name in 'xamlText', 'btnStyleXaml', 'chipBtnXaml') {
    $m = [regex]::Match($src, '\$' + $name + " = @'\r?\n(.*?)\r?\n'@", 'Singleline')
    $ok = $false
    if ($m.Success) { try { [void][xml]$m.Groups[1].Value; $ok = $true } catch { $ok = $_.Exception.Message } }
    Check "`$$name is valid XML (namespaces declared)" $true $ok
}
$main  = [regex]::Match($src, "\`$xamlText = @'\r?\n(.*?)\r?\n'@", 'Singleline').Groups[1].Value
$names = [regex]::Matches($main, 'x:Name="(\w+)"') | ForEach-Object { $_.Groups[1].Value }
$dupes = $names | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name
Check 'no duplicate x:Name' '' ($dupes -join ',')
$lookup = [regex]::Match($src, 'foreach \(\$n in @\((.*?)\)\) \{', 'Singleline').Groups[1].Value
$wanted = [regex]::Matches($lookup, "'(\w+)'") | ForEach-Object { $_.Groups[1].Value }
$missing = $wanted | Where-Object { $names -notcontains $_ }
Check 'every control the code looks up exists' '' ($missing -join ',')

Write-Host "`nhelpers (under Spanish number formatting)" -ForegroundColor Cyan
foreach ($fn in 'Format-Mbps', 'Get-GradeColour', 'Get-ReadingPlan', 'Set-PlanBar') {
    $def = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn }, $true)
    Invoke-Expression $def.Extent.Text
}
$cText = 'TEXT'; $cMuted = 'MUTED'
$cGrade = @{ red = 'RED'; yellow = 'YELLOW'; white = 'WHITE'; green = 'GREEN' }
$prev = [Threading.Thread]::CurrentThread.CurrentCulture
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('es-AR')
try {
    Check 'Format-Mbps 1000 (no "1.000")' '1000'  (Format-Mbps 1000)
    Check 'Format-Mbps 300.5 (no "300,5")' '300.5' (Format-Mbps 300.5)
    Check 'Format-Mbps null'              ''      (Format-Mbps $null)
    Check '932 of 1000 -> green'  'GREEN'  (Get-GradeColour 932.79 1000 @(25,50,75))
    Check '534 of 1000 -> white'  'WHITE'  (Get-GradeColour 534.86 1000 @(25,50,75))
    Check '385 of 1000 -> yellow' 'YELLOW' (Get-GradeColour 385.11 1000 @(25,50,75))
    Check '170 of 1000 -> red'    'RED'    (Get-GradeColour 170.51 1000 @(25,50,75))
    Check 'no plan -> neutral'    'TEXT'   (Get-GradeColour 500 $null @(25,50,75))
    Check 'no upload plan -> muted' 'MUTED' (Get-GradeColour 70 $null @(25,50,75) $cMuted)
    Check 'missing reading -> neutral' 'TEXT' (Get-GradeColour $null 1000 @(25,50,75))
} finally { [Threading.Thread]::CurrentThread.CurrentCulture = $prev }

Write-Host "`nreadings keep the plan they were taken under" -ForegroundColor Cyan
Check 'recorded plan wins'                 300  (Get-ReadingPlan 300 1000)
Check 'no recorded plan -> current'        1000 (Get-ReadingPlan $null 1000)
Check 'recorded 0 -> current'              1000 (Get-ReadingPlan 0 1000)
Check 'junk recorded -> current'           1000 (Get-ReadingPlan 'abc' 1000)
Check 'neither set -> nothing'             ''   (Get-ReadingPlan $null $null)
Check '200 under old 300 plan -> white'    'WHITE' (Get-GradeColour 200 (Get-ReadingPlan 300 1000) @(25,50,75))
Check '200 with no recorded plan -> red'   'RED'   (Get-GradeColour 200 (Get-ReadingPlan $null 1000) @(25,50,75))

Write-Host "`nplan bar is proportional, not pixel-sized" -ForegroundColor Cyan
try { Add-Type -AssemblyName PresentationFramework } catch { }
if ('System.Windows.GridLength' -as [type]) {
    $ui = @{ PlanFillCol = [pscustomobject]@{ Width = $null }; PlanRestCol = [pscustomobject]@{ Width = $null } }
    # compare numbers, not formatted strings: -f follows the locale (38,5 in Spanish)
    function Widths { @([double]$ui.PlanFillCol.Width.Value, [double]$ui.PlanRestCol.Width.Value) }
    Set-PlanBar 38.5; $w = Widths; Check '38.5% -> 38.5 : 61.5' $true ($w[0] -eq 38.5 -and $w[1] -eq 61.5)
    Set-PlanBar 140;  $w = Widths; Check 'over 100 clamps'      $true ($w[0] -eq 100  -and $w[1] -eq 0)
    Set-PlanBar 0.1;  $w = Widths; Check 'tiny stays visible'   $true ($w[0] -eq 0.6)
    Set-PlanBar 0;    $w = Widths; Check 'zero is empty'        $true ($w[0] -eq 0    -and $w[1] -eq 100)
} else {
    Write-Host '  skip  (WPF types not available on this platform - runs on Windows)' -ForegroundColor DarkGray
}

Write-Host ""
Write-Host ("  {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
Write-Host ""
if ($script:fail) { exit 1 }
