# =============================================================================
# T1.8 installer-hygiene regression guards (static source checks)
# =============================================================================
# Guards the four installer/data P1s fixed in T1.8:
#   #2 (T1.3-001) clean config seed — no secret ships; seed is pristine
#   #4 (T1.3-025) uninstall removes the orphaned HKCU\...\Run\QuickSay value
#   #1 (T1.3-023) user data unified under %APPDATA%\QuickSay\ (resolver + dirs +
#                 uninstall preserves license.dat)
# Static checks only (the installer/app cannot be exercised headlessly here).
# Exit 0 = pass, 1 = fail.
# =============================================================================

$ErrorActionPreference = "Stop"
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # tests\installer -> Development

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS: $msg" -ForegroundColor Green }
    else       { Write-Host "  FAIL: $msg" -ForegroundColor Red; $script:fail++ }
}
function Section($t) { Write-Host "`n[$t]" -ForegroundColor Cyan }

$setupIss   = Get-Content (Join-Path $repo "setup.iss") -Raw
$exampleRaw = Get-Content (Join-Path $repo "config.example.json") -Raw
$example    = $exampleRaw | ConvertFrom-Json

# ---------------------------------------------------------------------------
Section "P1 #2 — clean config seed (T1.3-001)"
# ---------------------------------------------------------------------------
Assert ([string]::IsNullOrEmpty($example.groqApiKey)) `
       "config.example.json groqApiKey is empty (no key, no DPAPI blob)"
# DPAPI blobs start with the base64 'AQAAANCMnd8...' magic; ensure none present anywhere.
Assert ($exampleRaw -notmatch 'AQAAANCMnd8') `
       "config.example.json contains no DPAPI-encrypted blob"
Assert ($example.launchAtStartup -eq 0) `
       "config.example.json launchAtStartup = 0 (does not silently arm autorun)"
$theme = "$($example.soundTheme)"
Assert (Test-Path (Join-Path $repo "sounds\$theme")) `
       "config.example.json soundTheme '$theme' resolves to a real sounds\ dir"

# The installer must NOT ship the developer's live config.json / dictionary.json.
Assert ($setupIss -notmatch '(?m)^\s*Source:\s*"config\.json"') `
       "setup.iss does NOT ship the live config.json"
Assert ($setupIss -notmatch '(?m)^\s*Source:\s*"dictionary\.json"') `
       "setup.iss does NOT ship the live dictionary.json"
Assert ($setupIss -match '(?m)^\s*Source:\s*"config\.example\.json"') `
       "setup.iss ships config.example.json as the clean seed template"

# ---------------------------------------------------------------------------
Section "P1 #4 — uninstall removes orphaned HKCU Run value (T1.3-025)"
# ---------------------------------------------------------------------------
Assert ($setupIss -match '(?im)^\s*\[UninstallRun\]') `
       "setup.iss has an [UninstallRun] section"
Assert ($setupIss -match 'reg delete.*CurrentVersion\\Run.*\/v QuickSay \/f') `
       "[UninstallRun] deletes the HKCU\...\Run\QuickSay value"

# ---------------------------------------------------------------------------
Section "P1 #1 — user data unified under %APPDATA%\QuickSay\ (T1.3-023)"
# ---------------------------------------------------------------------------
$quicksay = Get-Content (Join-Path $repo "QuickSay.ahk") -Raw
$license  = Get-Content (Join-Path $repo "lib\license.ahk") -Raw
$datadir  = Get-Content (Join-Path $repo "lib\datadir.ahk") -Raw

# Shared resolver exists and targets the canonical prod dir.
Assert (Test-Path (Join-Path $repo "lib\datadir.ahk")) "lib\datadir.ahk resolver exists"
Assert ($datadir -match 'A_IsCompiled' -and $datadir -match 'APPDATA.*\\QuickSay') `
       "GetDataDir() returns %APPDATA%\QuickSay when compiled"

# App data globals route through GetDataDir(), not A_ScriptDir.
Assert ($quicksay -match 'ConfigFile\s*:=\s*GetDataDir\(\)') "ConfigFile resolves via GetDataDir()"
Assert ($quicksay -match 'HistoryFile\s*:=\s*GetDataDir\(\)') "HistoryFile resolves via GetDataDir()"
Assert ($quicksay -match 'StatsFile\s*:=\s*GetDataDir\(\)')   "StatsFile resolves via GetDataDir()"
Assert ($quicksay -match 'DictionaryFile\s*:=\s*GetDataDir\(\)') "DictionaryFile resolves via GetDataDir()"
Assert ($quicksay -match 'AudioDir\s*:=\s*GetDataDir\(\)')    "AudioDir resolves via GetDataDir()"
# No user-data file still hard-bound to the script dir.
Assert ($quicksay -notmatch '(?m)ScriptDir\s*\.?\s*"\\config\.json"') "no ScriptDir-relative config.json read remains"

# Co-location invariant: license.dat resolves to the SAME %APPDATA%\QuickSay\ root.
Assert ($license -match 'APPDATA.*\\QuickSay\\license\.dat') "license.dat resolves to %APPDATA%\QuickSay\ (co-located)"

# Installer: data dirs are created under %APPDATA%, not {app}.
Assert ($setupIss -match '(?m)^\s*Name:\s*"\{userappdata\}\\QuickSay') "[Dirs] creates the %APPDATA%\QuickSay tree"

# Uninstall: targets %APPDATA%, and NEVER deletes the trial/license file.
Assert ($setupIss.Contains("dataRoot := ExpandConstant('{userappdata}\QuickSay')")) "uninstall keep-prompt resolves dataRoot to {userappdata}\QuickSay"
Assert ($setupIss.Contains("DeleteFile(dataRoot + '\config.json')")) "uninstall removes user config under %APPDATA%"
Assert ($setupIss -notmatch 'DelTree\(ExpandConstant\(.\{app\}\\data') "uninstall no longer DelTrees {app}\data (the trial-wiping path)"
# The comment may mention license.dat; what matters is there is NO deletion of it.
Assert ($setupIss -notmatch '(?i)(DeleteFile|DelTree)\([^\r\n]*license\.dat') "uninstall never DELETES license.dat (trial anti-abuse preserved)"

# Onboarding marker is recognized at the new (and legacy) location.
Assert ($setupIss -match 'userappdata\}\\QuickSay\\data\\onboarding_done') "OnboardingAlreadyDone checks the %APPDATA% marker"

if ($fail -eq 0) {
    Write-Host "`nALL PASS (installer hygiene)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n$fail ASSERTION(S) FAILED" -ForegroundColor Red
    exit 1
}
