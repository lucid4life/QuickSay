# T2.4 — crash-reporter test runner
#
# Usage:
#   .\tests\crash\run-tests.ps1            # unit suite (offline; no network)
#
# Exit 0 = all unit tests pass. The crash-reporter unit suite is fully offline:
# the Sentry POST is replaced by an injected send-hook and the clock/identity
# are injected, so it runs identically on any host with no DSN configured.

$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$Ahk  = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
if (!(Test-Path $Ahk)) { $Ahk = "C:\Program Files\AutoHotkey\AutoHotkey64.exe" }
$pass = 0; $fail = 0

function Announce($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  PASS  $m" -ForegroundColor Green;  $script:pass++ }
function Fail($m) { Write-Host "  FAIL  $m" -ForegroundColor Red;    $script:fail++ }
function Skip($m) { Write-Host "  SKIP  $m" -ForegroundColor Yellow }

function Run-AhkSuite($name, $script) {
    if (!(Test-Path $Ahk))    { Skip "$name (AutoHotkey64.exe not found)"; return }
    if (!(Test-Path $script)) { Fail "$name (missing $script)"; return }
    # AutoHotkey64.exe is a GUI-subsystem app, so `& $Ahk` returns immediately without
    # waiting/capturing. Start-Process -Wait -PassThru gives a real exit code, and
    # /ErrorStdOut is redirected to a temp file so we still see the per-test lines.
    $outFile = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $Ahk -ArgumentList @("/ErrorStdOut", $script) `
                -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outFile
        if (Test-Path $outFile) { Get-Content $outFile | ForEach-Object { Write-Host "    $_" } }
        if ($p.ExitCode -eq 0) { Ok "$name (exit 0)" } else { Fail "$name (exit $($p.ExitCode))" }
    } finally {
        Remove-Item $outFile -ErrorAction SilentlyContinue
    }
}

Announce "Crash reporter unit tests (crash-tests.ahk)"
Run-AhkSuite "crash-tests" (Join-Path $Here "crash-tests.ahk")

Announce "Summary"
$total = $pass + $fail
Write-Host "$pass/$total suites passed" -ForegroundColor ($fail -eq 0 ? "Green" : "Yellow")
if ($fail -gt 0) { exit 1 } else { exit 0 }
