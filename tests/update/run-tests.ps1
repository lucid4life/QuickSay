# T2.5 — Signed version.json test runner
#
# Usage:
#   .\tests\update\run-tests.ps1            # fixtures + unit suite + real round-trip
#   .\tests\update\run-tests.ps1 -SkipSign  # offline: unit suite only (no key needed)
#
# Exit 0 = all checks pass. The real signer↔verifier round-trip needs the qs-2026
# private key (~/.quicksay-keys or QUICKSAY_ED25519_PRIVATE_KEY*); after M.1 deletes
# the local key it SKIPs (informational) and the committed fixtures.json still drives
# the unit suite.

param([switch]$SkipSign)

$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$Dev  = Split-Path (Split-Path $Here -Parent) -Parent
$Ahk  = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
if (!(Test-Path $Ahk)) { $Ahk = "C:\Program Files\AutoHotkey\AutoHotkey64.exe" }
$pass = 0; $fail = 0

function Announce($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  PASS  $m" -ForegroundColor Green;  $script:pass++ }
function Fail($m) { Write-Host "  FAIL  $m" -ForegroundColor Red;    $script:fail++ }
function Skip($m) { Write-Host "  SKIP  $m" -ForegroundColor Yellow }

# Run an AHK driver and capture its REAL exit code + stdout (Start-Process is the
# reliable way to capture a GUI-subsystem AHK exe's stdout/exit).
function Run-Ahk($scriptPath, $argList) {
    $o = [System.IO.Path]::GetTempFileName(); $e = [System.IO.Path]::GetTempFileName()
    $args = @("/ErrorStdOut", $scriptPath) + $argList
    $p = Start-Process -FilePath $Ahk -ArgumentList $args -Wait -PassThru -NoNewWindow -RedirectStandardOutput $o -RedirectStandardError $e
    $out = (Get-Content $o -Raw); $err = (Get-Content $e -Raw)
    Remove-Item $o,$e -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $err }
}

# ── 1. Fixtures (Node) ────────────────────────────────────────────────────────
Announce "Fixtures (gen-fixtures.mjs)"
$fixtures = Join-Path $Here "fixtures.json"
try {
    $node = (Get-Command node -ErrorAction Stop).Source
    $out  = & $node (Join-Path $Here "gen-fixtures.mjs") 2>&1
    $code = $LASTEXITCODE
    $out | ForEach-Object { Write-Host "    $_" }
    if ($code -eq 0) { Ok "fixtures regenerated" }
    elseif (Test-Path $fixtures) { Skip "gen-fixtures failed (exit $code) — using committed fixtures.json" }
    else { Fail "gen-fixtures.mjs (exit $code) and no committed fixtures.json" }
} catch {
    if (Test-Path $fixtures) { Skip "node/key unavailable — using committed fixtures.json" }
    else { Fail "no node and no committed fixtures.json ($($_.Exception.Message))" }
}

# ── 2. Unit suite (11 tests + KAT + trust anchor) ─────────────────────────────
Announce "Update verifier unit tests (update-tests.ahk)"
if (!(Test-Path $Ahk)) { Skip "AutoHotkey64.exe not found" }
else {
    $r = Run-Ahk (Join-Path $Here "update-tests.ahk") @()
    ($r.Out -split "`n") | ForEach-Object { if ($_ -ne "") { Write-Host "    $_" } }
    if ($r.Err) { ($r.Err -split "`n") | ForEach-Object { if ($_ -ne "") { Write-Host "    $_" -ForegroundColor Red } } }
    if ($r.Code -eq 0) { Ok "update-tests (exit 0)" } else { Fail "update-tests (exit $($r.Code))" }
}

# ── 3. Real signer ↔ verifier round-trip (gate 3) ─────────────────────────────
Announce "Real signer<->verifier round-trip (sign-version-json.mjs -> verify-file.ahk)"
if ($SkipSign) { Skip "skipped (-SkipSign)" }
elseif (!(Test-Path $Ahk)) { Skip "AutoHotkey64.exe not found" }
else {
    $haveKey = ($env:QUICKSAY_ED25519_PRIVATE_KEY) -or ($env:QUICKSAY_ED25519_PRIVATE_KEY_PATH -and (Test-Path $env:QUICKSAY_ED25519_PRIVATE_KEY_PATH)) -or (Test-Path (Join-Path $HOME ".quicksay-keys\qs-2026-ed25519-private.pem"))
    if (-not $haveKey) { Skip "qs-2026 private key not present (post-M.1) — round-trip needs the signing key" }
    else {
        try {
            $node = (Get-Command node -ErrorAction Stop).Source
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("qs_rt_" + [guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Force -Path $tmp | Out-Null
            $fields = Join-Path $tmp "fields.json"; $vjson = Join-Path $tmp "version.json"
            # non-ASCII changelog stresses the canonicalization agreement
            $f = [ordered]@{ version="9.9.9"; download_url="https://quicksay.app/download";
                changelog=@("Round-trip 🚀 entry","Accent é / slash"); installer_sha256=("d"*64);
                released_at="2026-06-02T00:00:00Z"; keyId="qs-2026" }
            ($f | ConvertTo-Json -Depth 5) | Set-Content $fields -Encoding UTF8 -NoNewline
            & $node (Join-Path $Dev "scripts\sign-version-json.mjs") --in $fields --out $vjson 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Fail "signer failed (exit $LASTEXITCODE)" }
            else {
                $v = Run-Ahk (Join-Path $Here "verify-file.ahk") @($vjson)
                if ($v.Code -eq 0) { Ok "real signed manifest accepted by AHK verifier" }
                else { Fail "AHK verifier rejected a real signed manifest: $($v.Out.Trim())" }
                # tamper: flip the signed version → must reject
                $tj = Join-Path $tmp "tampered.json"
                ((Get-Content $vjson -Raw) -replace '"version": "9.9.9"','"version": "9.9.8"') | Set-Content $tj -Encoding UTF8 -NoNewline
                $vt = Run-Ahk (Join-Path $Here "verify-file.ahk") @($tj)
                if ($vt.Code -eq 1) { Ok "tampered signed manifest rejected (fail closed)" }
                else { Fail "tampered manifest NOT rejected (exit $($vt.Code)): $($vt.Out.Trim())" }
            }
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        } catch { Fail "round-trip error: $($_.Exception.Message)" }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Announce "Summary"
$total = $pass + $fail
Write-Host "$pass/$total checks passed" -ForegroundColor ($fail -eq 0 ? "Green" : "Yellow")
if ($fail -gt 0) { exit 1 } else { exit 0 }
