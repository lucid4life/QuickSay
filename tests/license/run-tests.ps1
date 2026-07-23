# T2.3 — Trial + license + Ed25519 verifier test runner
#
# Usage:
#   .\tests\license\run-tests.ps1            # fixtures + unit suites + live staging smoke
#   .\tests\license\run-tests.ps1 -SkipLive  # offline: unit suites only
#
# Exit 0 = all unit suites pass. The live staging smoke is informational (SKIP on
# network failure) and never fails the run on its own.

param([switch]$SkipLive)

$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$Ahk  = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
if (!(Test-Path $Ahk)) { $Ahk = "C:\Program Files\AutoHotkey\AutoHotkey64.exe" }
$Worker = "https://license-staging.quicksay.app"   # M.3 flips to https://license.quicksay.app
$pass = 0; $fail = 0

function Announce($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  PASS  $m" -ForegroundColor Green;  $script:pass++ }
function Fail($m) { Write-Host "  FAIL  $m" -ForegroundColor Red;    $script:fail++ }
function Skip($m) { Write-Host "  SKIP  $m" -ForegroundColor Yellow }

# Run an AHK unit driver; capture its REAL exit code (no pipe — a pipe would make
# $LASTEXITCODE reflect the cmdlet, not AutoHotkey).
function Run-AhkSuite($name, $script) {
    if (!(Test-Path $Ahk)) { Skip "$name (AutoHotkey64.exe not found)"; return }
    if (!(Test-Path $script)) { Fail "$name (missing $script)"; return }
    $out  = & $Ahk /ErrorStdOut $script 2>&1
    $code = $LASTEXITCODE
    $out | ForEach-Object { Write-Host "    $_" }
    if ($code -eq 0) { Ok "$name (exit 0)" } else { Fail "$name (exit $code)" }
}

# ── 1. Fixtures (Node) ────────────────────────────────────────────────────────
# Regeneration needs Node + the qs-2026 private key (~/.quicksay-keys). After M.1
# deletes the local key, regeneration is impossible — fall back to the committed
# fixtures.json (it holds only the PUBLIC key + test-machine-bound JWTs; no secret).
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

# ── 2. Ed25519 verifier unit tests ────────────────────────────────────────────
Announce "Ed25519 verifier (ed25519-tests.ahk)"
Run-AhkSuite "ed25519-tests" (Join-Path $Here "ed25519-tests.ahk")

# ── 3. License state-machine unit tests ───────────────────────────────────────
Announce "License state machine (license-tests.ahk)"
Run-AhkSuite "license-tests" (Join-Path $Here "license-tests.ahk")

# ── 4. Live staging smoke (informational; never fails the run) ────────────────
if (-not $SkipLive) {
    Announce "Live staging smoke ($Worker)"
    $tm = "0123456789abcdef0123456789abcdef"
    try {
        $pricing = Invoke-RestMethod -Uri "$Worker/pricing" -TimeoutSec 8
        if ($pricing.tier -and $pricing.checkoutUrl -ne $null) {
            Write-Host "    /pricing → tier=$($pricing.tier) price=$($pricing.price) financing=$($pricing.financingAvailable)"
            Ok "GET /pricing returns the documented shape"
        } else { Fail "GET /pricing missing tier/checkoutUrl" }
    } catch { Skip "GET /pricing unreachable ($($_.Exception.Message))" }

    try {
        $ts = Invoke-RestMethod -Uri "$Worker/trial/status?machineId=$tm" -TimeoutSec 8
        if ($ts.PSObject.Properties.Name -contains "blocked") {
            Write-Host "    /trial/status → blocked=$($ts.blocked)"
            Ok "GET /trial/status returns { blocked }"
        } else { Fail "GET /trial/status missing 'blocked'" }
    } catch { Skip "GET /trial/status unreachable ($($_.Exception.Message))" }

    # /validate with a junk JWT must be rejected (403) — proves the verify endpoint is live
    try {
        $body = @{ jwt = "eyJhbGciOiJFZERTQSJ9.eyJzdWIiOiJ4In0.AAAA" } | ConvertTo-Json
        $r = Invoke-WebRequest -Uri "$Worker/validate" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 8 -SkipHttpErrorCheck
        if ($r.StatusCode -eq 403) { Ok "POST /validate rejects a bogus JWT (403)" }
        else { Fail "POST /validate returned $($r.StatusCode), expected 403" }
    } catch { Skip "POST /validate unreachable ($($_.Exception.Message))" }
} else {
    Announce "Live staging smoke"
    Skip "skipped (-SkipLive)"
}

# ── Summary ───────────────────────────────────────────────────────────────────
Announce "Summary"
$total = $pass + $fail
Write-Host "$pass/$total checks passed" -ForegroundColor ($fail -eq 0 ? "Green" : "Yellow")
if ($fail -gt 0) { exit 1 } else { exit 0 }
