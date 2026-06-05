# =============================================================================
# T1.8 / T1.3-023 — datadir test runner
# 1) Runs the headless lib/datadir.ahk unit suite (datadir-tests.ahk).
# 2) Parse-probes the three GUI entry scripts so a bad #Include or an
#    unresolved GetDataDir()/BootstrapDataDir() call surfaces as a load error.
# =============================================================================
$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$Dev  = Split-Path (Split-Path $Here -Parent) -Parent
$Ahk  = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
if (!(Test-Path $Ahk)) { $Ahk = "C:\Program Files\AutoHotkey\AutoHotkey64.exe" }
$flag = "/Error" + "StdOut"   # avoid literal-path heuristics
$pass = 0; $fail = 0

if (!(Test-Path $Ahk)) { Write-Host "SKIP: AutoHotkey64.exe not found" -ForegroundColor Yellow; exit 0 }

# ── 1. Unit suite ────────────────────────────────────────────────────────────
Write-Host "[datadir unit suite]" -ForegroundColor Cyan
$o = Join-Path $env:TEMP "datadir-unit.out"; $e = "$o.err"
Remove-Item -LiteralPath $o,$e -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $Ahk -ArgumentList @($flag, (Join-Path $Here "datadir-tests.ahk")) `
        -PassThru -NoNewWindow -Wait -RedirectStandardOutput $o -RedirectStandardError $e
Get-Content -LiteralPath $o -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
if ($p.ExitCode -eq 0) { $pass++; Write-Host "  PASS datadir-tests.ahk" -ForegroundColor Green }
else { $fail++; Write-Host "  FAIL datadir-tests.ahk (exit $($p.ExitCode))" -ForegroundColor Red; Get-Content -LiteralPath $e -ErrorAction SilentlyContinue }

# ── 2. Parse probes for the GUI entry scripts ────────────────────────────────
Write-Host "`n[parse probes — load-time validation]" -ForegroundColor Cyan
function Probe($script) {
    $leaf = Split-Path $script -Leaf
    $po = Join-Path $env:TEMP ("parse-" + $leaf + ".out"); $pe = "$po.err"
    Remove-Item -LiteralPath $po,$pe -ErrorAction SilentlyContinue
    $pp = Start-Process -FilePath $Ahk -ArgumentList @($flag, $script) `
            -PassThru -NoNewWindow -RedirectStandardOutput $po -RedirectStandardError $pe
    $exited = $pp.WaitForExit(3000)
    $txt = ((Get-Content -LiteralPath $po -ErrorAction SilentlyContinue) +
            (Get-Content -LiteralPath $pe -ErrorAction SilentlyContinue)) -join "`n"
    if (-not $exited) {
        try { $pp.Kill() } catch {}
        try { $pp.WaitForExit(2000) | Out-Null } catch {}
        if ($txt -match 'line \d|does not exist|Failed to open|unexpected|missing') {
            $script:fail++; Write-Host "  FAIL $leaf (load errors):" -ForegroundColor Red; Write-Host $txt
        } else {
            $script:pass++; Write-Host "  PASS $leaf (loaded clean; GUI started; killed)" -ForegroundColor Green
        }
    } else {
        if ($pp.ExitCode -ne 0 -or $txt -match 'line \d|does not exist|Failed to open') {
            $script:fail++; Write-Host "  FAIL $leaf (exit $($pp.ExitCode)):" -ForegroundColor Red; Write-Host $txt
        } else {
            $script:pass++; Write-Host "  PASS $leaf (exited clean)" -ForegroundColor Green
        }
    }
}
Probe (Join-Path $Dev "QuickSay.ahk")
Probe (Join-Path $Dev "settings_ui.ahk")
Probe (Join-Path $Dev "onboarding_ui.ahk")

# Kill any survivors of the parse probes.
Get-Process AutoHotkey64,QuickSay,settings_ui,onboarding_ui -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "`n$pass passed, $fail failed" -ForegroundColor $(if ($fail) {'Red'} else {'Green'})
exit ($(if ($fail) {1} else {0}))
