# run-cleanup-tests.ps1 — QuickSay LLM-cleanup regression harness (E.2)
#
# Feeds probe transcripts through the REAL Groq cleanup call — same payload
# shape, model, temperature, and reasoning_effort as QuickSay.ahk builds at its
# two cleanup call sites — using the production mode prompts extracted live from
# QuickSay.ahk (with a dual-sync check against lib/settings-ui.ahk).
#
# Usage:
#   .\run-cleanup-tests.ps1                       # run committed probes.json
#   .\run-cleanup-tests.ps1 -Samples 3            # run each probe 3x (flakiness check)
#   .\run-cleanup-tests.ps1 -Temperature 0.0      # override app temperature
#   .\run-cleanup-tests.ps1 -IncludeLocalCorpus   # also run gitignored local-corpus\*.json
#   .\run-cleanup-tests.ps1 -ApiKey gsk_xxx
#
# Exit codes: 0 all pass · 1 failures · 2 config error
#
# PRIVACY: local-corpus\ holds probes derived from the user's real dictation.
# It and results\ are gitignored — never commit either.

param(
    [string]$ApiKey      = $env:GROQ_API_KEY,
    [int]$Samples        = 1,
    [double]$Temperature = 0.3,          # matches the app payload default
    [switch]$IncludeLocalCorpus,
    [string]$Model       = ""
)

$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$Dev  = Split-Path $Here -Parent | Split-Path -Parent

. (Join-Path $Here "lib\extract-prompts.ps1")
. (Join-Path $Here "lib\assertions.ps1")

# ── API key (same resolution as tests/transcription) ─────────────────────────
function Get-GroqApiKeyFromConfig {
    $candidates = @(
        (Join-Path $Dev "config.json"),
        (Join-Path $Dev "data\config.json"),
        "$env:APPDATA\QuickSay\config.json",
        "$env:LOCALAPPDATA\Programs\QuickSay Beta\config.json"
    )
    foreach ($cfgPath in $candidates) {
        if (!(Test-Path $cfgPath)) { continue }
        try {
            $cfg       = Get-Content $cfgPath -Raw | ConvertFrom-Json
            $encrypted = $cfg.groqApiKey
            if ([string]::IsNullOrEmpty($encrypted)) { continue }
            Add-Type -AssemblyName System.Security
            $bytes   = [Convert]::FromBase64String($encrypted.Trim())
            $entropy = [System.Text.Encoding]::UTF8.GetBytes("QuickSay-v1-entropy-2026")
            $plain   = [Security.Cryptography.ProtectedData]::Unprotect(
                          $bytes, $entropy,
                          [Security.Cryptography.DataProtectionScope]::CurrentUser)
            return [System.Text.Encoding]::UTF8.GetString($plain)
        } catch {
            Write-Warning "DPAPI decrypt failed for $cfgPath : $($_.Exception.Message)"
        }
    }
    return $null
}

if (!$ApiKey) { $ApiKey = Get-GroqApiKeyFromConfig }
if (!$ApiKey) {
    Write-Host "ERROR: No Groq API key found (set GROQ_API_KEY or make the app config readable)." -ForegroundColor Red
    exit 2
}

if ($Model -eq "") {
    $Model = "openai/gpt-oss-20b"
    foreach ($cfgPath in @((Join-Path $Dev "config.json"), "$env:APPDATA\QuickSay\config.json")) {
        if (Test-Path $cfgPath) {
            try { $m = (Get-Content $cfgPath -Raw | ConvertFrom-Json).llmModel; if ($m) { $Model = $m; break } } catch { }
        }
    }
}

# ── Production prompts (dual-sync verified) ──────────────────────────────────
$Prompts = Get-AhkModePrompts -DevRoot $Dev
Write-Host "`nQuickSay Cleanup Regression Harness (E.2)" -ForegroundColor Cyan
Write-Host ("=" * 50)
Write-Host "  Model      : $Model"
Write-Host "  Temperature: $Temperature"
Write-Host "  Samples    : $Samples per probe"
Write-Host "  Prompts    : extracted from QuickSay.ahk (dual-sync OK)"

# ── Load probes ───────────────────────────────────────────────────────────────
$probeFiles = @((Join-Path $Here "probes.json"))
if ($IncludeLocalCorpus) {
    $localDir = Join-Path $Here "local-corpus"
    if (Test-Path $localDir) { $probeFiles += (Get-ChildItem $localDir -Filter *.json | ForEach-Object FullName) }
}
$probes = @()
foreach ($pf in $probeFiles) {
    $doc = Get-Content $pf -Raw -Encoding UTF8 | ConvertFrom-Json
    $probes += $doc.probes
}
Write-Host "  Probes     : $($probes.Count) from $($probeFiles.Count) file(s)`n"

# ── Groq chat call — EXACT payload shape from QuickSay.ahk:1228 / :3347 ──────
function Invoke-GroqCleanup([string]$Key, [string]$SystemPrompt, [string]$RawText, [string]$Mdl, [double]$Temp) {
    $payload = @{
        model             = $Mdl
        temperature       = $Temp
        include_reasoning = $false
        reasoning_effort  = "low"
        messages          = @(
            @{ role = "system"; content = $SystemPrompt },
            @{ role = "user";   content = "<transcript>$RawText</transcript>" }
        )
    } | ConvertTo-Json -Depth 6
    $retries = 0
    while ($true) {
        try {
            $resp = Invoke-RestMethod -Uri "https://api.groq.com/openai/v1/chat/completions" -Method Post `
                        -Headers @{ Authorization = "Bearer $Key" } `
                        -ContentType "application/json; charset=utf-8" `
                        -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 60
            return $resp.choices[0].message.content
        } catch {
            $status = 0
            if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
            if ($status -eq 429 -and $retries -lt 3) {
                $retries++
                Write-Host "    [rate-limited, retry $retries in 6s]" -ForegroundColor Yellow
                Start-Sleep -Seconds 6
                continue
            }
            throw
        }
    }
}

# ── Run ────────────────────────────────────────────────────────────────────────
$results = [System.Collections.Generic.List[object]]::new()
$failedProbes = 0

foreach ($probe in $probes) {
    $mode = if ($probe.mode) { $probe.mode } else { "standard" }
    if (!$Prompts.Contains($mode)) {
        Write-Host ("  SKIP  {0,-42} (unknown mode '{1}')" -f $probe.id, $mode) -ForegroundColor Yellow
        continue
    }
    $probeFailed = $false
    $sampleRows = @()
    for ($s = 1; $s -le $Samples; $s++) {
        $cleaned = ""
        $apiErr = ""
        try { $cleaned = Invoke-GroqCleanup $ApiKey $Prompts[$mode] $probe.raw $Model $Temperature }
        catch { $apiErr = $_.Exception.Message }

        if ($apiErr -ne "") {
            $sampleRows += [pscustomobject]@{ sample = $s; cleaned = ""; failures = @("api-error: $apiErr") }
            $probeFailed = $true
            continue
        }
        $failures = Test-CleanupAssertions -Probe $probe -Cleaned $cleaned
        if ($failures.Count -gt 0) { $probeFailed = $true }
        $sampleRows += [pscustomobject]@{ sample = $s; cleaned = $cleaned; failures = @($failures) }
    }

    if ($probeFailed) { $failedProbes++ }
    $verdict = if ($probeFailed) { "FAIL" } else { "PASS" }
    $color   = if ($probeFailed) { "Red" } else { "Green" }
    Write-Host ("  {0}  {1,-44} [{2}]" -f $verdict, $probe.id, $mode) -ForegroundColor $color
    foreach ($row in $sampleRows) {
        foreach ($f in $row.failures) { Write-Host ("        s{0}: {1}" -f $row.sample, $f) -ForegroundColor DarkYellow }
    }
    $results.Add([pscustomobject]@{
        id = $probe.id; class = $probe.class; mode = $mode; verdict = $verdict; samples = $sampleRows
    })
}

# ── Summary + report ──────────────────────────────────────────────────────────
$passed = ($results | Where-Object { $_.verdict -eq "PASS" }).Count
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host ("  Probes: {0}   Pass: {1}   Fail: {2}" -f $results.Count, $passed, $failedProbes)

$resultsDir = Join-Path $Here "results"
New-Item -ItemType Directory -Force $resultsDir | Out-Null
$reportPath = Join-Path $resultsDir ((Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
$reportJson = @{ summary = @{ total = $results.Count; passed = $passed; failed = $failedProbes;
                              model = $Model; temperature = $Temperature; samples = $Samples;
                              run_at = (Get-Date -Format "o") };
                 probes = $results } | ConvertTo-Json -Depth 8
if ($reportJson -match 'gsk_[A-Za-z0-9_-]{20,}') {
    Write-Host "  SECURITY: API key pattern detected in report — not writing!" -ForegroundColor Red
    exit 1
}
$reportJson | Set-Content $reportPath -Encoding UTF8
Write-Host "  Report: $reportPath (gitignored)" -ForegroundColor Gray

$exit = if ($failedProbes -gt 0) { 1 } else { 0 }
Write-Host "`nEXIT: $exit" -ForegroundColor $(if ($exit -eq 0) { "Green" } else { "Red" })
exit $exit
