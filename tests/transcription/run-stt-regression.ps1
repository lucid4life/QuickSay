# run-stt-regression.ps1 — QuickSay Whisper STT regression suite (T2.6)
#
# Usage:
#   .\run-stt-regression.ps1                         # run full corpus
#   .\run-stt-regression.ps1 -ApiKey gsk_xxx         # explicit key (overrides env/config)
#   .\run-stt-regression.ps1 -CompareBaseline        # compare to committed baseline-v2.0.json
#   .\run-stt-regression.ps1 -RefreshBaseline        # HUMAN-DECIDED: overwrite baseline snapshot
#   .\run-stt-regression.ps1 -WerSelfTest            # run WER unit self-test only, no API calls
#
# Exit codes:
#   0  all clips meet their assertions (green)
#   1  one or more clips failed their assertion OR CompareBaseline detected a regression
#   2  configuration error (no API key, missing corpus)
#
# API key resolution order:
#   1. -ApiKey parameter
#   2. $env:GROQ_API_KEY  (CI)
#   3. DPAPI-decrypted key from QuickSay config.json  (local dev)
#
# Run fetch-corpus.ps1 first to download LibriSpeech clips and populate expected.json.

param(
    [string]$ApiKey        = $env:GROQ_API_KEY,
    [switch]$CompareBaseline,
    [switch]$RefreshBaseline,
    [switch]$WerSelfTest,
    [string]$BaselineFile  = "",
    # E.2: optional Whisper biasing prompt (mirrors AddWhisperBiasField in the
    # app). Used to prove dictionary biasing does not distort normal speech.
    [string]$BiasPrompt    = ""
)

$ErrorActionPreference = "Stop"
$Here  = $PSScriptRoot
$Dev   = Split-Path (Split-Path $Here -Parent) -Parent

# ── Dot-source helpers ─────────────────────────────────────────────────────────
. (Join-Path $Here "lib\wer.ps1")
. (Join-Path $Here "lib\hallucination.ps1")

# ── Helper functions ───────────────────────────────────────────────────────────

# Read the Groq API key from QuickSay's DPAPI-encrypted config.json
function Get-GroqApiKeyFromConfig {
    $candidates = @(
        (Join-Path $Dev "config.json"),             # dev working config (preferred)
        (Join-Path $Dev "data\config.json"),
        "$env:APPDATA\QuickSay\config.json",        # installed app config (v1.9+)
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
            # DPAPI decryption failed (wrong user context, corrupted blob, or wrong entropy).
            # Log to stderr so the caller's "no key found" message has context.
            Write-Warning "DPAPI decrypt failed for $cfgPath : $($_.Exception.Message)"
        }
    }
    return $null
}

function Get-QuickSayConfigValue([string]$key) {
    $candidates = @(
        (Join-Path $Dev "config.json"),             # dev working config (preferred)
        (Join-Path $Dev "data\config.json"),
        "$env:LOCALAPPDATA\Programs\QuickSay Beta\config.json"
    )
    foreach ($cfgPath in $candidates) {
        if (!(Test-Path $cfgPath)) { continue }
        try {
            $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
            $val = $cfg.$key
            if ($null -ne $val) { return $val }
        } catch { }
    }
    return $null
}

# POST a WAV file to Groq Whisper — same endpoint/field names as HttpPostFile() in lib/http.ahk
# Mirrors HttpPostFileWithRetry: retries once on 429 with 3s backoff (Groq free tier rate limit)
function Invoke-GroqWhisper([string]$Key, [string]$FilePath, [string]$Model, [string]$Lang) {
    $url     = "https://api.groq.com/openai/v1/audio/transcriptions"
    $retries = 0
    $form    = @{ file = Get-Item $FilePath; model = $Model; language = $Lang }
    if ($script:BiasPrompt -ne "") { $form["prompt"] = $script:BiasPrompt }
    while ($true) {
        try {
            $resp = Invoke-RestMethod -Uri $url -Method Post `
                        -Headers @{ Authorization = "Bearer $Key" } `
                        -Form $form `
                        -TimeoutSec 180
            $text = $resp.text
            if ($null -eq $text) { return "" }
            return $text
        } catch {
            $status = 0
            if ($_.Exception.Response) {
                $status = [int]$_.Exception.Response.StatusCode
            }
            if ($status -eq 429 -and $retries -lt 2) {
                $retries++
                Write-Host ("    [rate-limited, retry $retries in 5s]") -ForegroundColor Yellow
                Start-Sleep -Seconds 5
                continue
            }
            throw
        }
    }
}

# ── WER self-test mode ─────────────────────────────────────────────────────────
if ($WerSelfTest) {
    Write-Host "=== WER self-test ===" -ForegroundColor Cyan
    $ok = Test-WER
    Write-Host "EXIT: $(if ($ok) { 0 } else { 1 })"
    exit $(if ($ok) { 0 } else { 1 })
}

# ── Announce ───────────────────────────────────────────────────────────────────
Write-Host "`nQuickSay STT Regression Suite (T2.6)" -ForegroundColor Cyan
Write-Host ("=" * 50)

# ── API key ────────────────────────────────────────────────────────────────────
if (!$ApiKey) { $ApiKey = Get-GroqApiKeyFromConfig }
if (!$ApiKey) {
    Write-Host "ERROR: No Groq API key found.`n  Set GROQ_API_KEY env var or ensure the app's config.json is readable." -ForegroundColor Red
    exit 2
}
Write-Host "  API key : [set, $($ApiKey.Length) chars]" -ForegroundColor Gray

# ── Config ─────────────────────────────────────────────────────────────────────
$SttModel = "whisper-large-v3-turbo"
$Language = "en"
try {
    $cfgModel = Get-QuickSayConfigValue "stt_model"
    if ($cfgModel) { $SttModel = $cfgModel }
} catch { }
Write-Host "  Model   : $SttModel"
Write-Host "  Language: $Language"

# ── Load expected.json ─────────────────────────────────────────────────────────
$expectedPath = Join-Path $Here "expected.json"
if (!(Test-Path $expectedPath)) {
    Write-Host "ERROR: $expectedPath not found" -ForegroundColor Red; exit 2
}
$expected = Get-Content $expectedPath -Raw | ConvertFrom-Json
Write-Host "  Corpus  : $($expected.clips.Count) entries`n"

# ── Run the corpus ─────────────────────────────────────────────────────────────
$results = [System.Collections.Generic.List[object]]::new()
$skipped = 0

foreach ($clip in $expected.clips) {
    $wavPath = Join-Path $Here $clip.file

    if (!(Test-Path $wavPath)) {
        Write-Host ("  SKIP  {0,-44} (file missing)" -f ([IO.Path]::GetFileName($clip.file))) -ForegroundColor Yellow
        $skipped++; continue
    }
    if ($null -eq $clip.expected_text -and $clip.assert -notin @("informational","empty_or_hallucination")) {
        Write-Host ("  SKIP  {0,-44} (no transcript — run fetch-corpus.ps1)" -f ([IO.Path]::GetFileName($clip.file))) -ForegroundColor Yellow
        $skipped++; continue
    }

    # Transcribe
    $rawText  = ""
    $apiError = ""
    try {
        $rawText = Invoke-GroqWhisper -Key $ApiKey -FilePath $wavPath -Model $SttModel -Lang $Language
    } catch {
        $apiError = $_.Exception.Message
    }

    # Hallucination filter (mirrors QuickSay's pipeline)
    $keptText         = if ($apiError -eq "") { Get-FilteredText $rawText } else { "" }
    $hallucinationFlag= ($rawText -ne "" -and $keptText -eq "" -and $apiError -eq "")

    # WER on actual_raw (pre-filter)
    $wer = $null
    if ($apiError -eq "") {
        $ref = if ($null -ne $clip.expected_text) { $clip.expected_text } else { "" }
        if ($ref -ne "" -and $rawText -ne "") {
            $wer = Compute-WER $ref $rawText
        } elseif ($ref -eq "" -and $rawText -eq "") {
            $wer = [double]0.0
        }
    }

    # Verdict
    $verdict = "fail"
    if ($apiError -ne "") {
        $verdict = "error"
    } else {
        switch ($clip.assert) {
            "wer" {
                $verdict = if ($null -ne $wer -and $null -ne $clip.max_wer -and $wer -le $clip.max_wer) { "pass" } else { "fail" }
            }
            { $_ -in "exact", "exact_raw" } {
                # Both assert on actual_raw (before hallucination filter).
                # exact_raw is explicit: guards Whisper correctness on short-utterance
                # independent of the app's filter false-positive (T1.1 #015).
                $verdict = if ((Normalize-Text $rawText) -eq (Normalize-Text $clip.expected_text)) { "pass" } else { "fail" }
            }
            "empty_or_hallucination" {
                $verdict = if ($rawText -eq "" -or $hallucinationFlag) { "pass" } else { "fail" }
            }
            "informational" {
                $verdict = "pass"   # always pass; WER recorded for trend tracking only
            }
        }
    }

    $row = [pscustomobject]@{
        file                 = $clip.file
        bucket               = $clip.bucket
        expected             = $clip.expected_text
        actual_raw           = $rawText
        actual_kept          = $keptText
        wer                  = $wer
        hallucination_flagged= $hallucinationFlag
        assert               = $clip.assert
        max_wer              = $clip.max_wer
        verdict              = $verdict
        api_error            = $apiError
    }
    $results.Add($row)

    $icon  = switch ($verdict) { "pass"{"PASS"} "fail"{"FAIL"} "error"{"ERR "} default{"????"} }
    $color = switch ($verdict) { "pass"{"Green"} "fail"{"Red"} "error"{"Magenta"} default{"Gray"} }
    $werStr= if ($null -ne $wer) { ("WER={0:F3}" -f $wer) } else { "       " }
    $extra = if ($hallucinationFlag) { " [hallucination-flagged]" } else { "" }
    Write-Host ("  {0}  {1,-44} {2}{3}" -f $icon, ([IO.Path]::GetFileName($clip.file)), $werStr, $extra) -ForegroundColor $color
}

# ── Summary ────────────────────────────────────────────────────────────────────
$passed  = ($results | Where-Object { $_.verdict -eq "pass"  }).Count
$failed  = ($results | Where-Object { $_.verdict -eq "fail"  }).Count
$errors  = ($results | Where-Object { $_.verdict -eq "error" }).Count

$cleanRows  = $results | Where-Object { $_.bucket -eq "clean"   -and $null -ne $_.wer }
$accentRows = $results | Where-Object { $_.bucket -eq "accents" -and $null -ne $_.wer }
$meanClean  = if ($cleanRows.Count  -gt 0) { [Math]::Round(($cleanRows  | Measure-Object wer -Average).Average, 4) } else { $null }
$meanAccent = if ($accentRows.Count -gt 0) { [Math]::Round(($accentRows | Measure-Object wer -Average).Average, 4) } else { $null }

$summary = [pscustomobject]@{
    total            = $results.Count
    passed           = $passed
    failed           = $failed
    errors           = $errors
    skipped          = $skipped
    mean_wer_clean   = $meanClean
    mean_wer_accents = $meanAccent
    run_at           = (Get-Date -Format "o")
    stt_model        = $SttModel
    language         = $Language
}

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host ("  Total: {0}   Pass: {1}   Fail: {2}   Errors: {3}   Skipped: {4}" -f `
    $summary.total, $summary.passed, $summary.failed, $summary.errors, $summary.skipped)
if ($null -ne $meanClean)  { Write-Host ("  Mean WER clean   : {0:P1}  ({0:F4})" -f $meanClean) }
if ($null -ne $meanAccent) { Write-Host ("  Mean WER accents : {0:P1}  ({0:F4})" -f $meanAccent) }

# ── Write report JSON ──────────────────────────────────────────────────────────
$resultsDir = Join-Path $Here "results"
New-Item -ItemType Directory -Force $resultsDir | Out-Null
$stamp      = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $resultsDir "$stamp.json"

$report    = [ordered]@{ summary = $summary; clips = $results }
$reportJson = $report | ConvertTo-Json -Depth 10

# ── API key leak check (scan in-memory before writing to disk) ─────────────────
if ($reportJson -match 'gsk_[A-Za-z0-9_-]{20,}') {
    Write-Host "  SECURITY: API key pattern detected in report — not writing!" -ForegroundColor Red
    exit 1
}
Write-Host "  Key leak check: CLEAN (no gsk_ found in report)" -ForegroundColor Green

$reportJson | Set-Content $reportPath -Encoding UTF8
Write-Host "`n  Report written: $reportPath" -ForegroundColor Gray

# ── -CompareBaseline mode ──────────────────────────────────────────────────────
$regressionDetected = $false
if ($CompareBaseline) {
    $blPath = if ($BaselineFile -ne "") { $BaselineFile } else { Join-Path $Here "baseline\baseline-v2.0.json" }
    Write-Host "`n--- Compare to baseline: $([IO.Path]::GetFileName($blPath)) ---" -ForegroundColor Cyan
    if (!(Test-Path $blPath)) {
        Write-Host "  WARN: baseline file not found at $blPath" -ForegroundColor Yellow
    } else {
        $baseline = Get-Content $blPath -Raw | ConvertFrom-Json
        $blIndex  = @{}
        foreach ($bc in $baseline.clips) { $blIndex[$bc.file] = $bc }

        foreach ($r in $results) {
            if (!$blIndex.ContainsKey($r.file)) { continue }
            $bl = $blIndex[$r.file]
            if ($null -eq $r.wer -or $null -eq $bl.wer)  { continue }
            if ($r.assert -eq "informational")            { continue }

            $delta = $r.wer - $bl.wer
            # Regressed if WER rose by >0.05 absolute OR crossed the clip's max_wer threshold
            $crossed = ($null -ne $r.max_wer -and $r.wer -gt $r.max_wer -and $bl.wer -le $r.max_wer)
            $regressed = ($delta -gt 0.05) -or $crossed
            if ($regressed) {
                $dSign = if ($delta -ge 0) { "+" } else { "" }
                Write-Host ("  REGRESSION  {0,-40}  BL={1:F4}  NOW={2:F4}  delta={3}{4:F4}" -f `
                    [IO.Path]::GetFileName($r.file), $bl.wer, $r.wer, $dSign, $delta) -ForegroundColor Red
                $regressionDetected = $true
            } else {
                Write-Host ("  OK          {0,-40}  WER={1:F4}  (BL={2:F4})" -f `
                    [IO.Path]::GetFileName($r.file), $r.wer, $bl.wer) -ForegroundColor Green
            }
        }
        if (!$regressionDetected) {
            Write-Host "  No regressions detected vs baseline." -ForegroundColor Green
        }
    }
}

# ── -RefreshBaseline mode ──────────────────────────────────────────────────────
if ($RefreshBaseline) {
    Write-Host "`n--- RefreshBaseline ---" -ForegroundColor Yellow
    Write-Host "  This OVERWRITES the committed baseline snapshot." -ForegroundColor Yellow
    Write-Host "  Only do this when transcription quality has genuinely improved — never to hide a regression." -ForegroundColor Yellow
    $confirm = Read-Host "  Type 'YES' to confirm"
    if ($confirm -ne "YES") {
        Write-Host "  Cancelled — baseline unchanged." -ForegroundColor Gray
    } else {
        $blDir  = Join-Path $Here "baseline"
        New-Item -ItemType Directory -Force $blDir | Out-Null
        $blPath = Join-Path $blDir "baseline-v2.0.json"
        $report | ConvertTo-Json -Depth 10 | Set-Content $blPath -Encoding UTF8
        Write-Host "  Baseline refreshed at $blPath" -ForegroundColor Green
        Write-Host "  Remember to: git add $blPath && git commit -m 'chore: refresh STT baseline'" -ForegroundColor Cyan
    }
}

# ── Exit code ──────────────────────────────────────────────────────────────────
$exitCode = if ($failed -gt 0 -or $errors -gt 0 -or $regressionDetected) { 1 } else { 0 }
Write-Host "`nEXIT: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })
exit $exitCode
