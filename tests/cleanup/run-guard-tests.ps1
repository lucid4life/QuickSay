<#
.SYNOPSIS
    E.2 — cleanup sanity guard + artifact filter unit tests (no API calls).

.DESCRIPTION
    Runs guard.test.ahk, which exercises the REAL functions in
    lib/cleanup-guard.ahk and lib/artifact-filter.ahk. Free and offline —
    unlike run-cleanup-tests.ps1 (live Groq calls).

.EXAMPLE
    pwsh tests\cleanup\run-guard-tests.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here   = $PSScriptRoot
$DevDir = (Resolve-Path (Join-Path $Here '..\..')).Path

$Ahk = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
if (-not (Test-Path $Ahk)) { $Ahk = Join-Path $DevDir 'AutoHotkey64.exe' }
if (-not (Test-Path $Ahk)) {
    Write-Host "AutoHotkey64.exe not found (looked in Program Files and $DevDir)." -ForegroundColor Red
    exit 2
}

$Scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("qs-e2-guard-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $Scratch -Force | Out-Null
$resFile = Join-Path $Scratch 'guard.results.txt'
$errFile = Join-Path $Scratch 'guard.stderr.txt'

Write-Host "`nE.2 Cleanup Guard + Artifact Filter Tests" -ForegroundColor Cyan
Write-Host ("=" * 50)

$proc = Start-Process -FilePath $Ahk `
    -ArgumentList @('/ErrorStdOut', (Join-Path $Here 'guard.test.ahk'), $resFile) `
    -RedirectStandardError $errFile -PassThru -WindowStyle Hidden
if (-not $proc.WaitForExit(60000)) {
    $proc.Kill()
    Write-Host "TIMEOUT: guard.test.ahk did not finish in 60s" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $resFile)) {
    Write-Host "No results file produced. stderr:" -ForegroundColor Red
    if (Test-Path $errFile) { Get-Content $errFile | Write-Host }
    exit 1
}

$pass = 0; $fail = 0
foreach ($line in Get-Content $resFile -Encoding UTF8) {
    if ($line.Trim() -eq '') { continue }
    $parts = $line -split "`t"
    $name = $parts[0]; $status = $parts[1]
    $detail = if ($parts.Count -gt 2) { $parts[2] } else { '' }
    if ($status -eq 'PASS') {
        $pass++
        Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green
    } else {
        $fail++
        Write-Host ("  FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red
    }
}

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host ("  Pass: {0}   Fail: {1}" -f $pass, $fail)
Remove-Item -Recurse -Force $Scratch -ErrorAction SilentlyContinue

$exit = if ($fail -gt 0 -or $pass -eq 0) { 1 } else { 0 }
Write-Host "EXIT: $exit" -ForegroundColor $(if ($exit -eq 0) { 'Green' } else { 'Red' })
exit $exit
