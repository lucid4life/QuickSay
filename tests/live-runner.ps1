<#
.SYNOPSIS
    QuickSay P0.2 — AHK live runner

.DESCRIPTION
    Starts QuickSay.ahk under AutoHotkey64.exe, enables debug logging in
    config.json (temporarily, restored on teardown), tails the debug log live,
    and prints inferred recording/processing/idle/error state transitions.

    Operates against Development/data/ and Development/config.json — never
    touches %APPDATA%\QuickSay\ user data.

.PARAMETER Settings
    Launch in --settings mode instead of tray mode (to observe the settings UI).

.PARAMETER TestMode
    Set QUICKSAY_TEST_MODE=1 and WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=
    --remote-debugging-port=9222 so this runner composes with the Playwright
    harness (tests\playwright\run.mjs).

.PARAMETER DurationSeconds
    Auto-stop after this many seconds. If omitted, runs until Ctrl+C.

.EXAMPLE
    # Run tray mode indefinitely, tail log
    pwsh tests\live-runner.ps1

.EXAMPLE
    # Run settings mode for 30s, then stop
    pwsh tests\live-runner.ps1 -Settings -DurationSeconds 30

.EXAMPLE
    # Run with CDP debug port for Playwright composition
    pwsh tests\live-runner.ps1 -TestMode -Settings

.NOTES
    Built in P0.2. Used by T1.1, T1.2, T1.5, T1.7 audit/fix sessions.
#>
[CmdletBinding()]
param(
    [switch]$Settings,
    [switch]$TestMode,
    [int]$DurationSeconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DevDir     = Split-Path $PSScriptRoot -Parent
$AhkExe     = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
$ConfigFile = Join-Path $DevDir 'config.json'
$TrayLog    = Join-Path $DevDir 'debug_log.txt'
$SettingsLog= Join-Path $DevDir 'data\logs\debug.txt'
$LogFile    = if ($Settings) { $SettingsLog } else { $TrayLog }

$OriginalDebugLogging = $null
$AhkProcess           = $null

# ---------------------------------------------------------------------------
# State parsing
# ---------------------------------------------------------------------------
function Get-QuickSayState([string]$line) {
    if ($line -match 'Recording started:')            { return 'RECORDING' }
    if ($line -match '--- NEW RUN ---')               { return 'PROCESSING' }
    if ($line -match 'Whisper Raw:')                  { return 'PROCESSING (STT done)' }
    if ($line -match 'LLM cleanup using model:')      { return 'PROCESSING (LLM)' }
    if ($line -match 'Groq LLM Clean:')               { return 'PROCESSING (LLM done)' }
    if ($line -match 'Clipboard restored')            { return 'IDLE (paste complete)' }
    if ($line -match 'Recording too short')           { return 'IDLE (too short)' }
    if ($line -match 'network error|API error|transcription network|transcription API') { return 'ERROR' }
    if ($line -match 'hallucination filtered')        { return 'IDLE (hallucination blocked)' }
    if ($line -match 'Show\(\) called')               { return 'SETTINGS_OPEN' }
    if ($line -match 'HandleLoad')                    { return 'SETTINGS_LOADING' }
    return $null
}

function Write-StateChange([string]$state, [string]$line) {
    $ts = Get-Date -Format 'HH:mm:ss.fff'
    Write-Host "  [$ts] STATE: $state" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Config helpers (operate on Development/config.json ONLY)
# ---------------------------------------------------------------------------
function Enable-DebugLogging {
    if (-not (Test-Path $ConfigFile)) {
        Write-Warning "config.json not found at $ConfigFile — debug logging not enabled"
        return
    }

    $raw = Get-Content $ConfigFile -Raw -Encoding UTF8
    $cfg = $raw | ConvertFrom-Json

    # Preserve original value so we can restore it
    $script:OriginalDebugLogging = if ($cfg.PSObject.Properties['debugLogging']) { $cfg.debugLogging } else { 0 }

    if ($script:OriginalDebugLogging -eq 1) {
        Write-Host "  debugLogging already enabled in config.json" -ForegroundColor Gray
        return
    }

    # Set to 1 and write back — use a temp-then-rename pattern (mirrors AtomicWriteFile)
    $cfg.debugLogging = 1
    $tmp = "$ConfigFile.liverunner.tmp"
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $tmp -Encoding UTF8
    Move-Item -Path $tmp -Destination $ConfigFile -Force
    Write-Host "  debugLogging enabled in config.json (was $($script:OriginalDebugLogging))" -ForegroundColor Gray
}

function Restore-DebugLogging {
    if ($null -eq $script:OriginalDebugLogging) { return }
    if (-not (Test-Path $ConfigFile)) { return }

    try {
        $raw = Get-Content $ConfigFile -Raw -Encoding UTF8
        $cfg = $raw | ConvertFrom-Json
        $cfg.debugLogging = $script:OriginalDebugLogging
        $tmp = "$ConfigFile.liverunner.tmp"
        $cfg | ConvertTo-Json -Depth 10 | Set-Content $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $ConfigFile -Force
        Write-Host "`n  debugLogging restored to $($script:OriginalDebugLogging) in config.json" -ForegroundColor Gray
    } catch {
        Write-Warning "Could not restore debugLogging: $_"
    }
}

# ---------------------------------------------------------------------------
# Cleanup on exit
# ---------------------------------------------------------------------------
function Stop-Runner {
    if ($AhkProcess -and -not $AhkProcess.HasExited) {
        Write-Host "`n  Stopping QuickSay process (PID $($AhkProcess.Id))..." -ForegroundColor Yellow

        # Kill the process tree (QuickSay may have an FFmpeg child)
        try {
            $children = Get-CimInstance Win32_Process |
                Where-Object { $_.ParentProcessId -eq $AhkProcess.Id }
            foreach ($child in $children) {
                try { Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
            }
            Stop-Process -Id $AhkProcess.Id -Force -ErrorAction SilentlyContinue
        } catch {}
    }
    Restore-DebugLogging
    Write-Host "  Runner stopped." -ForegroundColor Green
}

# Register cleanup on Ctrl+C / normal exit
$null = Register-EngineEvent PowerShell.Exiting -Action { Stop-Runner }

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
Write-Host "`n[QuickSay P0.2] AHK Live Runner" -ForegroundColor White
Write-Host "  Dev dir   : $DevDir"
Write-Host "  AHK exe   : $AhkExe"
Write-Host "  Log file  : $LogFile"
Write-Host "  Mode      : $(if ($Settings) { 'settings' } else { 'tray' })$(if ($TestMode) { ' +TestMode (CDP port 9222)' } else { '' })"
if ($DurationSeconds -gt 0) {
    Write-Host "  Auto-stop : ${DurationSeconds}s"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if (-not (Test-Path $AhkExe)) {
    Write-Error "AutoHotkey v2 not found at $AhkExe. Install from https://www.autohotkey.com/"
}
if (-not $Settings) {
    # Tray mode: check for existing instance
    $existing = Get-Process -Name AutoHotkey64 -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Warning "AutoHotkey64 process(es) already running (PIDs: $($existing.Id -join ', ')). QuickSay tray mode will exit immediately if a tray instance already exists."
        Write-Warning "Stop the existing instance first, or use -Settings to launch settings mode alongside it."
    }
}

# ---------------------------------------------------------------------------
# Enable debug logging before launch
# ---------------------------------------------------------------------------
Write-Host "`n  Enabling debug logging..." -ForegroundColor Gray
Enable-DebugLogging

# ---------------------------------------------------------------------------
# Build AHK launch args + env
# ---------------------------------------------------------------------------
$scriptFile = Join-Path $DevDir 'QuickSay.ahk'
$scriptArgs = @($scriptFile)
if ($Settings) { $scriptArgs += '--settings' }

$env = [System.Collections.Hashtable]([System.Environment]::GetEnvironmentVariables())
if ($TestMode) {
    $env['QUICKSAY_TEST_MODE']                  = '1'
    $env['WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS'] = '--remote-debugging-port=9222'
    $env['WEBVIEW2_USER_DATA_FOLDER']            = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(), "qs-live-$(Get-Random)")
    Write-Host "  TestMode: CDP port 9222, isolated user-data folder" -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# Launch QuickSay
# ---------------------------------------------------------------------------
Write-Host "  Launching: $AhkExe $($scriptArgs -join ' ')`n" -ForegroundColor Gray

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName  = $AhkExe
$psi.Arguments = ($scriptArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
$psi.UseShellExecute = $false
foreach ($kvp in $env.GetEnumerator()) {
    $psi.Environment[$kvp.Key] = $kvp.Value
}

$script:AhkProcess = [System.Diagnostics.Process]::Start($psi)
if ($null -eq $script:AhkProcess) {
    Restore-DebugLogging
    Write-Error "Failed to start AHK process"
}

Write-Host "  QuickSay started (PID $($script:AhkProcess.Id))" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Poll until the log file appears (up to 10s)
# ---------------------------------------------------------------------------
Write-Host "  Waiting for log file: $LogFile"
$deadline = (Get-Date).AddSeconds(10)
while (-not (Test-Path $LogFile) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 250
    if ($script:AhkProcess.HasExited) {
        Write-Warning "QuickSay exited early (code $($script:AhkProcess.ExitCode))."
        Write-Warning "In tray mode, this usually means another instance is already running."
        Restore-DebugLogging
        exit 1
    }
}
if (-not (Test-Path $LogFile)) {
    Write-Host "  Log file not yet created (debugLogging may not have taken effect). Continuing anyway..." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Tail the log
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  === Tailing $LogFile ===" -ForegroundColor White
Write-Host "  (recording/processing/idle state transitions will be printed in cyan)"
Write-Host "  Press Ctrl+C to stop, or wait ${DurationSeconds}s auto-stop.`n" -ForegroundColor Gray

$lastState = ''
$startTime = Get-Date
$logJob    = $null

try {
    # Use a background job to tail the file so we can also watch the timer
    $tailScript = {
        param($path, $from)
        Get-Content -Path $path -Wait -Tail 0 -Encoding UTF8 2>$null
    }

    if (Test-Path $LogFile) {
        $logJob = Start-Job -ScriptBlock $tailScript -ArgumentList $LogFile, 0
    }

    while ($true) {
        # Check duration limit
        if ($DurationSeconds -gt 0) {
            $elapsed = ((Get-Date) - $startTime).TotalSeconds
            if ($elapsed -ge $DurationSeconds) {
                Write-Host "`n  Auto-stop: ${DurationSeconds}s elapsed." -ForegroundColor Yellow
                break
            }
        }

        # Check if AHK process exited
        if ($script:AhkProcess.HasExited) {
            Write-Host "`n  QuickSay process exited (code $($script:AhkProcess.ExitCode))." -ForegroundColor Yellow
            break
        }

        # Start log job if the file appeared after launch
        if ($null -eq $logJob -and (Test-Path $LogFile)) {
            $logJob = Start-Job -ScriptBlock $tailScript -ArgumentList $LogFile, 0
        }

        # Drain pending log lines
        if ($null -ne $logJob) {
            $lines = Receive-Job $logJob -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                $ts = Get-Date -Format 'HH:mm:ss.fff'
                Write-Host "  [$ts] $line"
                $state = Get-QuickSayState $line
                if ($state -and $state -ne $lastState) {
                    Write-StateChange $state $line
                    $lastState = $state
                }
            }
        }

        Start-Sleep -Milliseconds 200
    }
} finally {
    if ($null -ne $logJob) {
        Stop-Job $logJob -ErrorAction SilentlyContinue
        Remove-Job $logJob -ErrorAction SilentlyContinue
    }
    Stop-Runner
}
