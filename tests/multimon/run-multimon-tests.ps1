# T1.7 Multi-monitor safety tests
# Runs: (1) pure-logic unit tests via AHK, (2) live WM_DISPLAYCHANGE harness if QuickSay is running.
# Usage:  .\tests\multimon\run-multimon-tests.ps1
#         .\tests\multimon\run-multimon-tests.ps1 -SkipLive   # unit tests only

param([switch]$SkipLive)

$Dev = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
$Ahk = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
if (!(Test-Path $Ahk)) { $Ahk = "C:\Program Files\AutoHotkey\AutoHotkey64.exe" }
$ConfigFile = Join-Path $Dev "config.json"
$pass = 0; $fail = 0

function Announce($title) { Write-Host "`n=== $title ===" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  PASS  $msg" -ForegroundColor Green; $script:pass++ }
function Fail($msg) { Write-Host "  FAIL  $msg" -ForegroundColor Red;   $script:fail++ }

# ── Test 1-5: AHK clamping unit tests (headless) ─────────────────────────────
Announce "Unit tests — clamping logic (headless AHK)"
$unitScript = Join-Path $PSScriptRoot "clamp-logic.ahk"
if (!(Test-Path $Ahk)) {
    Write-Host "  SKIP  AutoHotkey64.exe not found at $Ahk" -ForegroundColor Yellow
} elseif (!(Test-Path $unitScript)) {
    Fail "clamp-logic.ahk not found"
} else {
    $out = & $Ahk /ErrorStdOut $unitScript 2>&1
    Write-Host ($out | Out-String).Trim()
    # Count pass/fail lines from the AHK output
    $out -split "`n" | ForEach-Object {
        if ($_ -match "^\s+PASS") { $script:pass++ }
        elseif ($_ -match "^\s+FAIL") { $script:fail++ }
    }
}

# ── Live test: WM_DISPLAYCHANGE harness ──────────────────────────────────────
if (-not $SkipLive) {
    Announce "Live test — WM_DISPLAYCHANGE (requires running QuickSay tray)"

    # Find tray window
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
}
"@ -ErrorAction SilentlyContinue
    $trayHwnd = [Win32]::FindWindow("AutoHotkey", "QuickSay_TrayMode ahk_class AutoHotkey")
    if (!$trayHwnd -or $trayHwnd -eq [IntPtr]::Zero) {
        $trayHwnd = [Win32]::FindWindow("AutoHotkey", $null)  # fallback: find any AHK window
    }

    if (!$trayHwnd -or $trayHwnd -eq [IntPtr]::Zero) {
        Write-Host "  SKIP  QuickSay tray not running — skipping live test" -ForegroundColor Yellow
    } else {
        # Read current widget position from config
        if (!(Test-Path $ConfigFile)) {
            Write-Host "  SKIP  config.json not found" -ForegroundColor Yellow
        } else {
            $cfg = Get-Content $ConfigFile | ConvertFrom-Json

            # Shim widget to an off-screen position (way beyond any monitor)
            $cfg | Add-Member -NotePropertyName widgetX -NotePropertyValue 9999 -Force
            $cfg | Add-Member -NotePropertyName widgetY -NotePropertyValue 9999 -Force
            $cfg | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding UTF8
            Write-Host "  Shimmed widgetX/widgetY to (9999, 9999)"

            # Post WM_DISPLAYCHANGE (0x7E) to the tray window
            $WM_DISPLAYCHANGE = 0x7E
            [void][Win32]::PostMessage($trayHwnd, $WM_DISPLAYCHANGE, [IntPtr]::Zero, [IntPtr]::Zero)
            Write-Host "  Posted WM_DISPLAYCHANGE to tray window"

            # Wait for the handler to run and write back
            Start-Sleep -Milliseconds 600

            # Read back config
            $cfg2 = Get-Content $ConfigFile | ConvertFrom-Json
            $newX = $cfg2.widgetX
            $newY = $cfg2.widgetY
            Write-Host "  New widgetX=$newX  widgetY=$newY"

            # Assert the position moved off of (9999, 9999) and onto a real monitor
            if ($newX -ne 9999 -or $newY -ne 9999) {
                Ok "Live T1: widget repositioned from off-screen coords"
            } else {
                Fail "Live T1: widget NOT repositioned — still at (9999, 9999)"
            }

            # Sanity: both coords should be positive and reasonable
            if ($newX -ge 0 -and $newX -lt 7680 -and $newY -ge 0 -and $newY -lt 4320) {
                Ok "Live T2: repositioned coords within plausible screen bounds"
            } else {
                Fail "Live T2: repositioned coords out of range: ($newX, $newY)"
            }
        }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Announce "Summary"
$total = $pass + $fail
Write-Host "$pass/$total passed" -ForegroundColor ($fail -eq 0 ? "Green" : "Yellow")
if ($fail -gt 0) { exit 1 } else { exit 0 }
