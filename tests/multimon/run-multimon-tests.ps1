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
    # AHK FileAppend("*") stdout isn't reliably captured via & without an attached console,
    # so trust the script's exit code (0 = all asserts passed, 1 = a failure) as the source of truth.
    & $Ahk /ErrorStdOut $unitScript 2>&1 | Write-Host
    if ($LASTEXITCODE -eq 0) { Ok "clamp-logic.ahk unit tests passed (exit 0)" }
    else { Fail "clamp-logic.ahk unit tests reported failures (exit $LASTEXITCODE)" }
}

# ── Live test: WM_DISPLAYCHANGE harness ──────────────────────────────────────
if (-not $SkipLive) {
    Announce "Live test — WM_DISPLAYCHANGE (requires running QuickSay tray)"

    # NOTE on scope: this live step verifies the OnDisplayChange→RepositionToVisible
    # *wiring* survives a WM_DISPLAYCHANGE without crashing the tray. It does NOT try to
    # strand the widget via a config shim — that can't work against a running tray:
    #   • FloatingWidget.Show() already self-corrects off-screen config positions on load, and
    #   • RepositionToVisible() acts on the in-memory this.posX/this.posY, not the config file.
    # The off-screen→snap math is covered exhaustively by the headless unit tests above.

    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
}
"@ -ErrorAction SilentlyContinue
    # The tray's hidden window title is literally "QuickSay_TrayMode" (set via WinSetTitle);
    # "ahk_class AutoHotkey" is AHK WinTitle syntax, NOT part of the Win32 title string.
    $trayHwnd = [Win32]::FindWindow("AutoHotkey", "QuickSay_TrayMode")

    if (!$trayHwnd -or $trayHwnd -eq [IntPtr]::Zero) {
        Write-Host "  SKIP  QuickSay tray not running (no QuickSay_TrayMode window) — skipping live test" -ForegroundColor Yellow
    } else {
        # Snapshot the tray process so we can confirm it survives the message
        $trayProc = Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" |
            Where-Object { $_.CommandLine -like '*QuickSay.ahk*' } | Select-Object -First 1
        $WM_DISPLAYCHANGE = 0x7E
        [void][Win32]::PostMessage($trayHwnd, $WM_DISPLAYCHANGE, [IntPtr]::Zero, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 700
        [void][Win32]::PostMessage($trayHwnd, $WM_DISPLAYCHANGE, [IntPtr]::Zero, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 700
        Write-Host "  Posted WM_DISPLAYCHANGE (0x7E) x2 to tray window"

        $stillThere = [Win32]::FindWindow("AutoHotkey", "QuickSay_TrayMode")
        if ($stillThere -ne [IntPtr]::Zero) {
            Ok "Live T1: tray survived WM_DISPLAYCHANGE (no crash from RepositionToVisible wiring)"
        } else {
            Fail "Live T1: tray window gone after WM_DISPLAYCHANGE — handler may have crashed"
        }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Announce "Summary"
$total = $pass + $fail
Write-Host "$pass/$total passed" -ForegroundColor ($fail -eq 0 ? "Green" : "Yellow")
if ($fail -gt 0) { exit 1 } else { exit 0 }
