# QuickSay Build Script v2.3
# Builds from Development/ → dist/ → installer/
# Usage: powershell -ExecutionPolicy Bypass -File build_release.ps1

param(
    [switch]$SkipCompile,    # Skip AHK compilation (use interpreter mode)
    [switch]$SkipInstaller   # Skip Inno Setup (just build dist/)
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$dist = "$root\dist"
$version = "2.3"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " QuickSay Build v$version" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ─── SECURITY SCAN ───────────────────────────────────────────────────────────
Write-Host "[1/6] Security scan..." -ForegroundColor Yellow
$leaks = Select-String -Path "$root\*.ahk","$root\*.json","$root\*.bat","$root\*.html","$root\gui\*.html","$root\gui\*.css","$root\gui\*.js" -Pattern "gsk_[A-Za-z0-9]{20,}" -ErrorAction SilentlyContinue
if ($leaks) {
    Write-Host "SECURITY FAILURE: API key found in source files!" -ForegroundColor Red
    foreach ($leak in $leaks) {
        Write-Host "  $($leak.Filename):$($leak.LineNumber)" -ForegroundColor Red
    }
    Write-Host "Remove all API keys before building." -ForegroundColor Red
    exit 1
}
Write-Host "  No API keys found. OK" -ForegroundColor Green

# ─── CLEAN DIST ──────────────────────────────────────────────────────────────
Write-Host "[2/6] Cleaning dist/..." -ForegroundColor Yellow
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist | Out-Null
New-Item -ItemType Directory -Path "$dist\data" | Out-Null
New-Item -ItemType Directory -Path "$dist\data\audio" | Out-Null
Write-Host "  Clean dist/ created" -ForegroundColor Green

# ─── COPY SOURCE FILES ──────────────────────────────────────────────────────
Write-Host "[3/6] Copying files..." -ForegroundColor Yellow

# Core scripts
Copy-Item "$root\QuickSay-Launcher.ahk" "$dist\"
Copy-Item "$root\QuickSay-Next.ahk" "$dist\"
Copy-Item "$root\settings_ui.ahk" "$dist\"
Copy-Item "$root\onboarding_ui.ahk" "$dist\"
Copy-Item "$root\record.bat" "$dist\"

# Config -use example config for clean installs (no API key)
if (Test-Path "$root\config.example.json") {
    Copy-Item "$root\config.example.json" "$dist\config.json"
} else {
    # Create minimal safe config
    Set-Content -Path "$dist\config.json" -Value '{
    "groqApiKey": "",
    "sttModel": "whisper-large-v3-turbo",
    "llmModel": "llama-3.3-70b-versatile",
    "language": "en",
    "hotkey": "CapsLock",
    "hotkeyMode": "hold",
    "playSounds": true,
    "showOverlay": true,
    "llmCleanup": true,
    "autoRemoveFillers": true,
    "smartPunctuation": true,
    "debugLogging": false,
    "recordingQuality": "medium",
    "audioDevice": "Default",
    "launchAtStartup": false,
    "saveRecordings": false
}'
}

# Dictionary -ship starter entries (same array format as settings_ui.ahk)
Set-Content -Path "$dist\dictionary.json" -Value '[{"spoken":"groq","written":"Groq"},{"spoken":"kubernetes","written":"Kubernetes"},{"spoken":"sas","written":"SaaS"}]'

# GUI
Copy-Item "$root\gui" -Destination "$dist\gui" -Recurse
# Remove backup/dev files from gui
Remove-Item "$dist\gui\*.bak" -ErrorAction SilentlyContinue
Remove-Item "$dist\gui\*_BACKUP*" -ErrorAction SilentlyContinue
Remove-Item "$dist\gui\index.html" -ErrorAction SilentlyContinue
Remove-Item "$dist\gui\history.html" -ErrorAction SilentlyContinue
Remove-Item "$dist\gui\statistics.html" -ErrorAction SilentlyContinue
## settings.css is REQUIRED -do NOT delete it

# Libraries
Copy-Item "$root\lib" -Destination "$dist\lib" -Recurse

# Sounds
Copy-Item "$root\sounds" -Destination "$dist\sounds" -Recurse

# FFmpeg -bundle for seamless audio device support
if (Test-Path "$root\ffmpeg\ffmpeg.exe") {
    Copy-Item "$root\ffmpeg\ffmpeg.exe" "$dist\ffmpeg.exe"
    Write-Host "  Bundled ffmpeg.exe" -ForegroundColor Green
} else {
    Write-Host "  WARNING: ffmpeg\ffmpeg.exe not found -run download_ffmpeg.ps1 first" -ForegroundColor Yellow
    Write-Host "  Users will need to install FFmpeg manually for non-default mic support" -ForegroundColor Yellow
}

# WebView2 bootstrapper -ensures WebView2 runtime is available on Windows 10
if (Test-Path "$root\redist\MicrosoftEdgeWebview2Setup.exe") {
    if (-not (Test-Path "$dist\redist")) {
        New-Item -ItemType Directory -Path "$dist\redist" | Out-Null
    }
    Copy-Item "$root\redist\MicrosoftEdgeWebview2Setup.exe" "$dist\redist\"
    Write-Host "  Bundled WebView2 bootstrapper" -ForegroundColor Green
} else {
    Write-Host "  WARNING: redist\MicrosoftEdgeWebview2Setup.exe not found -run download_webview2.ps1" -ForegroundColor Yellow
}

Write-Host "  All files copied" -ForegroundColor Green

# ─── COMPILE OR DEPLOY INTERPRETER ──────────────────────────────────────────
Write-Host "[4/6] Preparing executables..." -ForegroundColor Yellow

$compiler = "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
$base = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"

if (-not $SkipCompile -and (Test-Path $compiler) -and (Test-Path $base)) {
    # Try compilation
    Write-Host "  Compiling QuickSay-Launcher.ahk..." -ForegroundColor Gray
    $iconPath = "$root\gui\assets\icon.ico"

    try {
        if (Test-Path $iconPath) {
            & $compiler /in "$dist\QuickSay-Launcher.ahk" /out "$dist\QuickSay-Launcher.exe" /base "$base" /icon "$iconPath"
        } else {
            & $compiler /in "$dist\QuickSay-Launcher.ahk" /out "$dist\QuickSay-Launcher.exe" /base "$base"
        }
        Write-Host "  Compiled QuickSay-Launcher.exe" -ForegroundColor Green
    } catch {
        Write-Host "  Compilation failed, falling back to interpreter mode" -ForegroundColor Yellow
        Copy-Item $base "$dist\QuickSay-Launcher.exe"
    }
} else {
    # Interpreter mode -ship AutoHotkey.exe renamed as launcher
    if (Test-Path $base) {
        Copy-Item $base "$dist\QuickSay-Launcher.exe"
        Write-Host "  Deployed in interpreter mode (AHK runtime + .ahk scripts)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: AutoHotkey v2 not found at $base" -ForegroundColor Yellow
        Write-Host "  Install AutoHotkey v2 or place AutoHotkey64.exe in dist/ manually" -ForegroundColor Yellow
    }
}

# Always ship AutoHotkey64.exe as runtime for child scripts (engine, settings, onboarding)
# The compiled launcher needs this to run .ahk scripts
if (Test-Path $base) {
    Copy-Item $base "$dist\AutoHotkey64.exe"
    Write-Host "  Shipped AutoHotkey64.exe runtime for child scripts" -ForegroundColor Green
} else {
    Write-Host "  WARNING: Cannot ship AHK runtime - child scripts will not work!" -ForegroundColor Red
}

# ─── VERIFY DIST ─────────────────────────────────────────────────────────────
Write-Host "[5/6] Verifying dist/..." -ForegroundColor Yellow
$required = @(
    "QuickSay-Launcher.ahk",
    "QuickSay-Next.ahk",
    "settings_ui.ahk",
    "onboarding_ui.ahk",
    "config.json",
    "dictionary.json",
    "gui\settings.html",
    "gui\onboarding.html",
    "gui\settings.css",
    "lib\GDI.ahk",
    "lib\WebView2.ahk",
    "lib\web-overlay.ahk",
    "lib\JSON.ahk",
    "sounds\start.wav",
    "sounds\stop.wav",
    "sounds\error.wav",
    "ffmpeg.exe"
)

$missing = @()
foreach ($file in $required) {
    if (-not (Test-Path "$dist\$file")) {
        $missing += $file
    }
}

if ($missing.Count -gt 0) {
    Write-Host "  MISSING FILES:" -ForegroundColor Red
    foreach ($f in $missing) { Write-Host "    - $f" -ForegroundColor Red }
    Write-Host "  Build may be incomplete!" -ForegroundColor Red
} else {
    Write-Host "  All $($required.Count) required files present" -ForegroundColor Green
}

# Final security re-scan on dist
$distLeaks = Select-String -Path "$dist\*.ahk","$dist\*.json","$dist\gui\*.html" -Pattern "gsk_[A-Za-z0-9]{20,}" -ErrorAction SilentlyContinue
if ($distLeaks) {
    Write-Host "  SECURITY FAILURE: API key leaked into dist!" -ForegroundColor Red
    foreach ($leak in $distLeaks) {
        Write-Host "    $($leak.Filename):$($leak.LineNumber)" -ForegroundColor Red
    }
    exit 1
}
# Also verify config.json doesn't have non-empty groqApiKey (should be blank for distribution)
$distConfig = Get-Content "$dist\config.json" -Raw -ErrorAction SilentlyContinue
$apiPattern = 'groqApiKey.*:\s*"[^"]{10,}'
if ($distConfig -match $apiPattern) {
    Write-Host "  SECURITY WARNING: config.json has a non-empty API key value" -ForegroundColor Yellow
    Write-Host "  This may be an encrypted key - verify it is not plaintext" -ForegroundColor Yellow
}
Write-Host "  Dist security scan passed" -ForegroundColor Green

# ─── BUILD INSTALLER ─────────────────────────────────────────────────────────
if (-not $SkipInstaller) {
    Write-Host "[6/6] Building installer..." -ForegroundColor Yellow

    $iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    if (-not (Test-Path $iscc)) {
        $iscc = "C:\Program Files\Inno Setup 6\ISCC.exe"
    }
    if (-not (Test-Path $iscc)) {
        $iscc = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    }

    if (Test-Path $iscc) {
        if (-not (Test-Path "$root\installer")) {
            New-Item -ItemType Directory -Path "$root\installer" | Out-Null
        }
        & $iscc "$root\setup.iss"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Installer built: installer\QuickSay_Setup_v$version.exe" -ForegroundColor Green
        } else {
            Write-Host "  Inno Setup failed with exit code $LASTEXITCODE" -ForegroundColor Red
        }
    } else {
        Write-Host "  Inno Setup not found. Install from https://jrsoftware.org/isinfo.php" -ForegroundColor Yellow
        Write-Host "  Skipping installer build. dist/ folder is ready for manual packaging." -ForegroundColor Yellow
    }
} else {
    Write-Host "[6/6] Skipping installer (-SkipInstaller flag)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Build complete!" -ForegroundColor Cyan
Write-Host " dist/ folder: $dist" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
