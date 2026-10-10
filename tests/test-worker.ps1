# SpeedWatch - tests for the worker helpers in run-test.ps1.
# Functions are pulled out through the parser: loading run-test.ps1 itself
# would start a real speed test.

$ErrorActionPreference = 'Stop'

$script  = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts') 'run-test.ps1'
$ast     = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$null)
foreach ($name in @('Get-RootMessage', 'Test-Retryable')) {
    $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) |
          Select-Object -First 1
    if (-not $fn) { throw "Function $name not found in run-test.ps1" }
    Invoke-Expression $fn.Extent.Text
}

$script:pass = 0
$script:fail = 0
function Check {
    param([string]$Name, $Expected, $Actual)
    if ([string]$Expected -eq [string]$Actual) { $script:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
    else {
        $script:fail++
        Write-Host ("  FAIL  {0}`n        expected [{1}]`n        actual   [{2}]" -f $Name, $Expected, $Actual) -ForegroundColor Red
    }
}

Write-Host "`nGet-RootMessage" -ForegroundColor Cyan
$cause = New-Object System.Exception 'No such host is known.'
$agg   = New-Object System.AggregateException $cause
Check 'unwraps AggregateException'              'No such host is known.' (Get-RootMessage $agg)

$wrap  = New-Object System.Management.Automation.MethodInvocationException `
         'Exception calling "WaitAll" with "1" argument(s): "One or more errors occurred."', $agg
Check 'unwraps WaitAll -> aggregate -> cause'   'No such host is known.' (Get-RootMessage $wrap)

$tmo   = New-Object System.Threading.Tasks.TaskCanceledException 'The request was canceled due to the configured HttpClient.Timeout of 90 seconds elapsing.'
Check 'timeout surfaces as the timeout'         $tmo.Message (Get-RootMessage (New-Object System.AggregateException $tmo))

Check 'a plain exception is left as it is'      'Cloudflare endpoint did not respond to latency probes.' `
      (Get-RootMessage (New-Object System.Exception 'Cloudflare endpoint did not respond to latency probes.'))

Write-Host "`nTest-Retryable" -ForegroundColor Cyan
Check 'Ookla 503 is retried'                    $true  (Test-Retryable '[error] Configuration - Cannot retrieve configuration document (503)')
Check 'timeout is retried'                      $true  (Test-Retryable 'Timeout occurred in connect.')
Check 'missing CLI is not retried'              $false (Test-Retryable 'Speedtest CLI not found. Run Install.cmd again.')

Write-Host ""
Write-Host ("  {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
Write-Host ""
if ($script:fail) { exit 1 }
