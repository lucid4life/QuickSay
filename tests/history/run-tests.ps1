<#
.SYNOPSIS
    T1.5 — history / retention / clear-history regression runner.

.DESCRIPTION
    Two layers:

    1. AHK-native unit driver (history-core.test.ahk) exercising the REAL
       functions in lib/history-core.ahk (no copied bodies, no drift):
         retention (1-5), audio (6-8), clear-history race (9 + resurrection),
         corruption/atomicity (10), entry-count (12), config-merge (11c/11d).

    2. Source assertions over lib/settings-ui.ahk for the settings-side
       pagination-cache invalidation (test 11). The real SettingsUI class
       cannot be headless-loaded for a unit test (its WebView2 include chain
       hangs without a desktop), so the invalidation method AND its 0x5555
       wiring are verified structurally — that is exactly the regression that
       would reintroduce stale history counts.

    Operates in a scratch temp dir — never touches Development/data/ or
    config.json.

.EXAMPLE
    pwsh tests\history\run-tests.ps1

.NOTES
    Built in T1.5. Prereq: AutoHotkey v2 at
    'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' (falls back to the
    bundled Development\AutoHotkey64.exe). Run from PowerShell, not the bash
    sandbox (the AHK GUI host needs a real window station).
#>
[CmdletBinding()]
param([switch]$KeepArtifacts)

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

$Scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("qs-t15-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $Scratch -Force | Out-Null

$results = @()   # [pscustomobject]{ Name; Status; Detail }
$fatal   = @()

# --- Layer 1: AHK unit driver --------------------------------------------------
$driver  = Join-Path $Here 'history-core.test.ahk'
$resFile = Join-Path $Scratch 'core.results.txt'
$errFile = Join-Path $Scratch 'core.stderr.txt'
# The driver wipes+recreates its work dir, so it must be a SUBDIR distinct from
# the results/stderr files (whose handles the parent holds open during the run).
$workDir = Join-Path $Scratch 'work'

$p = Start-Process -FilePath $Ahk `
        -ArgumentList @('/ErrorStdOut', $driver, $resFile, $workDir) `
        -NoNewWindow -PassThru -RedirectStandardError $errFile
if (-not $p.WaitForExit(60000)) {
    $p.Kill(); $p.WaitForExit()
    $fatal += "history-core.test.ahk timed out (60s)."
}

if (Test-Path $resFile) {
    $raw  = Get-Content $resFile -Encoding UTF8
    if ($raw -notcontains '__DONE__') {
        $stderr = if (Test-Path $errFile) { (Get-Content $errFile -Raw).Trim() } else { '' }
        $fatal += "history-core.test.ahk did not complete. stderr: $stderr"
    }
    foreach ($line in ($raw | Where-Object { $_ -and $_ -ne '__DONE__' })) {
        $parts = $line -split "`t", 3
        $results += [pscustomobject]@{
            Name   = $parts[0]
            Status = $parts[1]
            Detail = if ($parts.Count -ge 3) { $parts[2] } else { '' }
        }
    }
} else {
    $fatal += "history-core.test.ahk produced no results file."
}

# --- Layer 2: settings-ui source assertions (test 11) --------------------------
function Add-SourceAssertion {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    $script:results += [pscustomobject]@{
        Name = $Name; Status = ($Ok ? 'PASS' : 'FAIL'); Detail = $Detail
    }
}

$settingsSrc = Get-Content (Join-Path $DevDir 'lib\settings-ui.ahk') -Raw

# The invalidation method must reset BOTH pagination caches.
$methodOk = ($settingsSrc -match '(?s)static\s+InvalidateHistoryCaches\s*\(\s*\)\s*\{[^}]*_historyRetention\s*:=\s*0[^}]*_historyCache\s*:=\s*""[^}]*\}')
Add-SourceAssertion '11_settings_invalidate_method_resets_caches' $methodOk `
    ($methodOk ? 'method resets _historyRetention + _historyCache' : 'InvalidateHistoryCaches missing or does not reset both caches')

# ...and it must be wired to the 0x5555 config-reload message.
$wiredOk = (($settingsSrc -match 'OnMessage\(\s*0x5555') -and ($settingsSrc -match 'InvalidateHistoryCaches'))
Add-SourceAssertion '11b_settings_invalidate_wired_to_0x5555' $wiredOk `
    ($wiredOk ? 'OnMessage(0x5555) -> InvalidateHistoryCaches' : 'no OnMessage(0x5555) wiring for InvalidateHistoryCaches')

# --- Report --------------------------------------------------------------------
Write-Host ""
Write-Host "T1.5 history/retention regression" -ForegroundColor Cyan
Write-Host ("-" * 66)

$pass = 0; $fail = 0
foreach ($t in $results | Sort-Object Name) {
    if ($t.Status -eq 'PASS') {
        $pass++
        Write-Host ("  PASS  " + $t.Name) -ForegroundColor Green
    } else {
        $fail++
        $msg = "  FAIL  " + $t.Name
        if ($t.Detail) { $msg += "  [" + $t.Detail + "]" }
        Write-Host $msg -ForegroundColor Red
    }
}
foreach ($e in $fatal) { Write-Host ("  ERROR " + $e) -ForegroundColor Red }

Write-Host ("-" * 66)
Write-Host ("  {0} passed, {1} failed, {2} total" -f $pass, $fail, ($pass + $fail))

if (-not $KeepArtifacts) {
    Remove-Item $Scratch -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "  artifacts: $Scratch" -ForegroundColor DarkGray
}

if ($fail -gt 0 -or $fatal.Count -gt 0) { exit 1 } else { exit 0 }
