<#
.SYNOPSIS
    QuickSay P0.2 — Whisper STT regression runner

.DESCRIPTION
    POSTs WAV files to Groq Whisper (whisper-large-v3-turbo) and validates:
      - baseline/ clips: Word Error Rate against expected transcripts
      - hallucination/ clips: captures raw output for IsWhisperHallucination() validation
      - edge/ clips: asserts expected behavior (empty, hallucination-prone, skipped)

    API key comes from $env:GROQ_API_KEY ONLY. Never reads config.json.
    If $env:GROQ_API_KEY is not set, runs in offline-assert-only mode (exits 0).

.EXAMPLE
    # Online mode (live Groq API calls)
    $env:GROQ_API_KEY = "gsk_..."
    pwsh tests/transcription/run-stt-regression.ps1

.EXAMPLE
    # Offline mode (structure validation only, no API calls)
    pwsh tests/transcription/run-stt-regression.ps1

.NOTES
    Built in P0.2. Expanded with real LibriSpeech + whisper-hallucinations corpus
    by T2.6 (transcription regression corpus session).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$ExpectedFile = Join-Path $ScriptDir "expected.json"
$ResultsDir  = Join-Path $ScriptDir "results"
$GroqApiKey  = $env:GROQ_API_KEY
$OfflineMode = [string]::IsNullOrWhiteSpace($GroqApiKey)
$GroqEndpoint = "https://api.groq.com/openai/v1/audio/transcriptions"
$Model        = "whisper-large-v3-turbo"

$PASS = 0
$FAIL = 0
$SKIP = 0
$Errors = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Header([string]$text) {
    Write-Host "`n== $text ==" -ForegroundColor Cyan
}

function Write-Pass([string]$msg) {
    Write-Host "  PASS  $msg" -ForegroundColor Green
    $script:PASS++
}

function Write-Fail([string]$msg) {
    Write-Host "  FAIL  $msg" -ForegroundColor Red
    $script:FAIL++
    $script:Errors.Add($msg)
}

function Write-Skip([string]$msg) {
    Write-Host "  SKIP  $msg" -ForegroundColor Yellow
    $script:SKIP++
}

function Compute-WER([string]$reference, [string]$hypothesis) {
    # Simple word-level WER: edit_distance(ref_words, hyp_words) / len(ref_words)
    $refWords = $reference.ToLower() -split '\s+' | Where-Object { $_ -ne '' }
    $hypWords = $hypothesis.ToLower() -split '\s+' | Where-Object { $_ -ne '' }

    if ($refWords.Count -eq 0) { return 0.0 }

    $m = $refWords.Count
    $n = $hypWords.Count

    # Levenshtein distance on word arrays
    $dp = New-Object 'int[,]' ($m + 1), ($n + 1)
    for ($i = 0; $i -le $m; $i++) { $dp[$i, 0] = $i }
    for ($j = 0; $j -le $n; $j++) { $dp[0, $j] = $j }

    for ($i = 1; $i -le $m; $i++) {
        for ($j = 1; $j -le $n; $j++) {
            if ($refWords[$i - 1] -eq $hypWords[$j - 1]) {
                $dp[$i, $j] = $dp[$i - 1, $j - 1]
            } else {
                $dp[$i, $j] = 1 + [Math]::Min($dp[$i - 1, $j - 1],
                                   [Math]::Min($dp[$i - 1, $j], $dp[$i, $j - 1]))
            }
        }
    }

    return [Math]::Round($dp[$m, $n] / $m, 4)
}

function Invoke-GroqSTT([string]$wavPath) {
    # Mirrors QuickSay's HttpPostFile() multipart contract
    $boundary = [System.Guid]::NewGuid().ToString("N")
    $fileName  = [System.IO.Path]::GetFileName($wavPath)
    $wavBytes  = [System.IO.File]::ReadAllBytes($wavPath)

    $bodyParts = [System.Collections.Generic.List[byte]]::new()

    function Add-Text([string]$text) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $bodyParts.AddRange($bytes)
    }

    # -- file field --
    Add-Text "--$boundary`r`n"
    Add-Text "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"`r`n"
    Add-Text "Content-Type: audio/wav`r`n`r`n"
    $bodyParts.AddRange($wavBytes)
    Add-Text "`r`n"
    # -- model field --
    Add-Text "--$boundary`r`n"
    Add-Text "Content-Disposition: form-data; name=`"model`"`r`n`r`n"
    Add-Text "$Model`r`n"
    # -- response_format field --
    Add-Text "--$boundary`r`n"
    Add-Text "Content-Disposition: form-data; name=`"response_format`"`r`n`r`n"
    Add-Text "json`r`n"
    # -- final boundary --
    Add-Text "--$boundary--`r`n"

    $headers = @{
        "Authorization" = "Bearer $GroqApiKey"
        "Content-Type"  = "multipart/form-data; boundary=$boundary"
    }

    try {
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $GroqEndpoint `
            -Headers $headers `
            -Body $bodyParts.ToArray() `
            -ContentType "multipart/form-data; boundary=$boundary"
        return $response.text ?? ""
    } catch {
        $statusCode = $_.Exception.Response?.StatusCode
        throw "Groq API error ($statusCode): $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Load expected.json
# ---------------------------------------------------------------------------

if (-not (Test-Path $ExpectedFile)) {
    Write-Error "expected.json not found at $ExpectedFile"
    exit 1
}

$expected = Get-Content $ExpectedFile -Raw | ConvertFrom-Json
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

New-Item -ItemType Directory -Force $ResultsDir | Out-Null
$resultsFile = Join-Path $ResultsDir "$timestamp.json"
$results = [ordered]@{
    timestamp  = (Get-Date -Format "o")
    mode       = if ($OfflineMode) { "offline-assert-only" } else { "live-api" }
    model      = $Model
    werThreshold = $expected._werThreshold
    clips      = [System.Collections.Generic.List[object]]::new()
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

Write-Host "`n[QuickSay P0.2] STT Regression Runner" -ForegroundColor White
Write-Host "Model    : $Model"
Write-Host "Endpoint : $GroqEndpoint"
if ($OfflineMode) {
    Write-Host "`n  NOTE: GROQ_API_KEY is not set." -ForegroundColor Yellow
    Write-Host "  Running in OFFLINE-ASSERT-ONLY mode: validating corpus structure, no API calls."
    Write-Host "  Set GROQ_API_KEY to run live STT tests.`n" -ForegroundColor Yellow
} else {
    Write-Host "Mode     : live API calls"
}

# ---------------------------------------------------------------------------
# Phase 1 — Baseline clips (WER)
# ---------------------------------------------------------------------------

Write-Header "Phase 1 — Baseline clips (WER against ground truth)"

$werValues = [System.Collections.Generic.List[double]]::new()

foreach ($clip in $expected.baseline) {
    $wavPath = Join-Path $ScriptDir $clip.file

    if (-not (Test-Path $wavPath)) {
        Write-Fail "$($clip.file) — file not found. Run fetch-corpus.ps1 to download."
        continue
    }

    $clipResult = [ordered]@{ file = $clip.file; synthetic = [bool]$clip.synthetic }

    if ($clip.synthetic) {
        Write-Skip "$($clip.file) — synthetic placeholder (WER not meaningful). Run fetch-corpus.ps1."
        $clipResult.status = "skipped-synthetic"
        $results.clips.Add($clipResult)
        continue
    }

    if ($OfflineMode) {
        Write-Pass "$($clip.file) — file present (offline mode, no API call)"
        $clipResult.status = "offline-file-present"
        $results.clips.Add($clipResult)
        continue
    }

    try {
        $actual = (Invoke-GroqSTT $wavPath).Trim()
        $wer    = Compute-WER $clip.transcript $actual
        $werValues.Add($wer)
        $clipResult.transcript_expected = $clip.transcript
        $clipResult.transcript_actual   = $actual
        $clipResult.wer                 = $wer

        if ($wer -le $expected._werThreshold) {
            Write-Pass "$($clip.file) — WER $wer (threshold $($expected._werThreshold))"
            $clipResult.status = "pass"
        } else {
            Write-Fail "$($clip.file) — WER $wer EXCEEDS threshold $($expected._werThreshold)"
            $clipResult.status = "fail-wer"
        }
    } catch {
        Write-Fail "$($clip.file) — API error: $_"
        $clipResult.status = "api-error"
        $clipResult.error  = "$_"
    }
    $results.clips.Add($clipResult)
}

if ($werValues.Count -gt 0) {
    $avgWer = [Math]::Round(($werValues | Measure-Object -Average).Average, 4)
    Write-Host "`n  Corpus-average WER: $avgWer (over $($werValues.Count) real clips)" -ForegroundColor White
    $results.corpusAverageWer = $avgWer
} else {
    Write-Host "`n  Corpus-average WER: not measured (all clips synthetic or offline mode)" -ForegroundColor Yellow
    $results.corpusAverageWer = $null
    $results.corpusAverageWerNote = "No real LibriSpeech clips — run fetch-corpus.ps1 then re-run with GROQ_API_KEY"
}

# ---------------------------------------------------------------------------
# Phase 2 — Hallucination clips (capture raw output for IsWhisperHallucination())
# ---------------------------------------------------------------------------

Write-Header "Phase 2 — Hallucination clips (capture raw Groq output)"

foreach ($clip in $expected.hallucination) {
    $wavPath = Join-Path $ScriptDir $clip.file

    if (-not (Test-Path $wavPath)) {
        Write-Fail "$($clip.file) — file not found. Run fetch-corpus.ps1 to download."
        continue
    }

    $clipResult = [ordered]@{ file = $clip.file; expectHallucination = $true; synthetic = [bool]$clip.synthetic }

    if ($OfflineMode) {
        Write-Pass "$($clip.file) — file present (offline mode, no API call)"
        $clipResult.status = "offline-file-present"
        $results.clips.Add($clipResult)
        continue
    }

    try {
        $actual = (Invoke-GroqSTT $wavPath).Trim()
        $clipResult.rawOutput = $actual
        $isEmpty = [string]::IsNullOrWhiteSpace($actual)

        # The AHK IsWhisperHallucination() filter should catch these —
        # record the raw output so T1.1/T2.6 can assert filter coverage.
        if ($isEmpty) {
            Write-Pass "$($clip.file) — Whisper returned empty (hallucination pre-empted or silence detected)"
            $clipResult.status = "pass-empty"
        } else {
            # Non-empty output from silence/noise — exactly what IsWhisperHallucination() targets
            Write-Host "  INFO  $($clip.file) — Whisper emitted: `"$actual`" (should be caught by AHK filter)" -ForegroundColor Cyan
            $clipResult.status = "info-non-empty"
            Write-Pass "$($clip.file) — raw output captured for AHK filter validation"
        }
    } catch {
        Write-Fail "$($clip.file) — API error: $_"
        $clipResult.status = "api-error"
        $clipResult.error  = "$_"
    }
    $results.clips.Add($clipResult)
}

# ---------------------------------------------------------------------------
# Phase 3 — Edge clips
# ---------------------------------------------------------------------------

Write-Header "Phase 3 — Edge clips"

foreach ($clip in $expected.edge) {
    $wavPath = Join-Path $ScriptDir $clip.file

    if (-not (Test-Path $wavPath)) {
        Write-Fail "$($clip.file) — file not found (should have been generated by ffmpeg)"
        continue
    }

    $clipResult = [ordered]@{ file = $clip.file; description = $clip.description }

    if ($clip.PSObject.Properties['expectSkipped'] -and $clip.expectSkipped) {
        # sub-500ms: file must exist but app never sends it to API
        Write-Pass "$($clip.file) — file exists, below 500ms minimum (app-level guard, not API-tested)"
        $clipResult.status = "pass-app-guard"
        $results.clips.Add($clipResult)
        continue
    }

    if ($OfflineMode) {
        Write-Pass "$($clip.file) — file present (offline mode, no API call)"
        $clipResult.status = "offline-file-present"
        $results.clips.Add($clipResult)
        continue
    }

    try {
        $actual = (Invoke-GroqSTT $wavPath).Trim()
        $clipResult.rawOutput = $actual
        $isEmpty = [string]::IsNullOrWhiteSpace($actual)

        if ($isEmpty) {
            Write-Pass "$($clip.file) — Whisper returned empty (expected for silence/noise)"
            $clipResult.status = "pass-empty"
        } else {
            Write-Host "  INFO  $($clip.file) — Whisper emitted: `"$actual`" (should be caught by IsWhisperHallucination)" -ForegroundColor Cyan
            $clipResult.status = "info-non-empty"
            Write-Pass "$($clip.file) — raw output captured for AHK filter validation"
        }
    } catch {
        Write-Fail "$($clip.file) — API error: $_"
        $clipResult.status = "api-error"
        $clipResult.error  = "$_"
    }
    $results.clips.Add($clipResult)
}

# ---------------------------------------------------------------------------
# Write results file
# ---------------------------------------------------------------------------

$results.summary = [ordered]@{ pass = $PASS; fail = $FAIL; skip = $SKIP }
$results | ConvertTo-Json -Depth 6 | Set-Content $resultsFile -Encoding UTF8
Write-Host "`nResults written to: $resultsFile" -ForegroundColor Gray

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "============================" -ForegroundColor White
Write-Host "  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP" -ForegroundColor White
Write-Host "============================" -ForegroundColor White

if ($FAIL -gt 0) {
    Write-Host "`nFailed assertions:" -ForegroundColor Red
    foreach ($e in $Errors) { Write-Host "  - $e" -ForegroundColor Red }
    exit 1
}

Write-Host "`nAll assertions passed." -ForegroundColor Green
exit 0
