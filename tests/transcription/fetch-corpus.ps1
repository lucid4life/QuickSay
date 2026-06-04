# fetch-corpus.ps1 — Download and prepare the T2.6 transcription corpus
#
# Usage:
#   .\fetch-corpus.ps1                  # full download (~346 MB one-time, cached)
#   .\fetch-corpus.ps1 -SkipDownload    # skip download if tarball already present
#   .\fetch-corpus.ps1 -CacheDir <path> # override cache dir (default: $env:TEMP\qs-corpus)
#
# What it does:
#   1. Downloads LibriSpeech test-clean.tar.gz to $CacheDir (cached; never re-downloads)
#   2. Extracts the two chapter directories we need: 1089/134686 and 1221/135766 and 3570/5694
#   3. Converts FLAC → 16kHz mono WAV using bundled ffmpeg.exe
#   4. Reads the official .trans.txt files and populates expected_text in expected.json
#   5. Builds long-2min.wav (10 clips concatenated) and multi-speaker.wav (2 speakers interleaved)
#
# After running: all corpus/*.wav files are in place; expected.json has no null expected_text
# entries; run-stt-regression.ps1 will execute end-to-end.

param(
    [switch]$SkipDownload,
    [string]$CacheDir = (Join-Path $env:TEMP "qs-corpus")
)

$ErrorActionPreference = "Stop"
$Here  = $PSScriptRoot
$Dev   = Split-Path (Split-Path $Here -Parent) -Parent
$Ffmpeg = Join-Path $Dev "ffmpeg.exe"

if (!(Test-Path $Ffmpeg)) { throw "ffmpeg.exe not found at $Ffmpeg" }

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    WARN $msg" -ForegroundColor Yellow }

# ── Paths ──────────────────────────────────────────────────────────────────────
$Tarball   = Join-Path $CacheDir "test-clean.tar.gz"
$ExtractDir= Join-Path $CacheDir "librispeech-extract"
$CleanDir  = Join-Path $Here "corpus\clean"
$AccentsDir= Join-Path $Here "corpus\accents"
$EdgeDir   = Join-Path $Here "corpus\edge"

New-Item -ItemType Directory -Force $CacheDir, $CleanDir, $AccentsDir, $EdgeDir | Out-Null

# ── 1. Download tarball ────────────────────────────────────────────────────────
Write-Step "LibriSpeech test-clean.tar.gz"
if (Test-Path $Tarball) {
    Write-Ok "Already cached: $Tarball"
} elseif ($SkipDownload) {
    throw "Tarball not in cache and -SkipDownload set. Run without -SkipDownload first."
} else {
    $url = "https://www.openslr.org/resources/12/test-clean.tar.gz"
    Write-Host "    Downloading ~346 MB from openslr.org ..." -ForegroundColor Yellow
    Write-Host "    (one-time; subsequent runs use the cache)" -ForegroundColor Gray
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($url, $Tarball)
    Write-Ok "Downloaded to $Tarball"
}

# ── 2. Extract needed chapters ─────────────────────────────────────────────────
Write-Step "Extracting chapters from tarball"
New-Item -ItemType Directory -Force $ExtractDir | Out-Null

# The speakers/chapters we need
$chapters = @(
    @{ speaker="1089"; chapter="134686" },
    @{ speaker="1221"; chapter="135766" },
    @{ speaker="3570"; chapter="5694"   }
)

$alreadyExtracted = $chapters | Where-Object { Test-Path (Join-Path $ExtractDir "LibriSpeech\test-clean\$($_.speaker)\$($_.chapter)") }
if ($alreadyExtracted.Count -eq $chapters.Count) {
    Write-Ok "All chapters already extracted"
} else {
    Write-Host "    Extracting via Python tarfile (Windows tar lacks --wildcards) ..." -ForegroundColor Gray
    # Build a proper Python list literal — one quoted string per chapter, comma-separated
    $prefixList = ($chapters | ForEach-Object { "'LibriSpeech/test-clean/$($_.speaker)/$($_.chapter)/'" }) -join ", "
    $pyScript = @"
import tarfile, sys
tarball, outdir = sys.argv[1], sys.argv[2]
prefixes = [$prefixList]
with tarfile.open(tarball, 'r:gz') as tf:
    count = 0
    for m in tf.getmembers():
        if any(m.name.startswith(p) for p in prefixes):
            tf.extract(m, outdir, set_attrs=False)
            count += 1
    print(f'Extracted {count} members')
"@
    $result = python -c $pyScript "$Tarball" "$ExtractDir" 2>&1
    Write-Host "    $result" -ForegroundColor Gray
    foreach ($ch in $chapters) {
        $spk = $ch.speaker; $chap = $ch.chapter
        $outDir = Join-Path $ExtractDir "LibriSpeech\test-clean\$spk\$chap"
        if (Test-Path $outDir) { Write-Ok "Extracted $spk/$chap" }
        else { Write-Warn "Chapter $spk/$chap not found in tarball (skipping)" }
    }
}

# ── 3. Convert FLAC → 16kHz mono WAV ──────────────────────────────────────────
Write-Step "Converting FLAC → WAV"

function Convert-Flac([string]$src, [string]$dst) {
    if (Test-Path $dst) { return }
    & $Ffmpeg -i $src -ar 16000 -ac 1 -acodec pcm_s16le $dst -y 2>&1 | Out-Null
    if (!(Test-Path $dst)) { throw "ffmpeg failed converting $src" }
}

# speaker 1089 → clean bucket (utterances 0000-0009)
for ($i = 0; $i -le 9; $i++) {
    $id = "1089-134686-{0:D4}" -f $i
    $flac = Join-Path $ExtractDir "LibriSpeech\test-clean\1089\134686\$id.flac"
    $wav  = Join-Path $CleanDir "$id.wav"
    if (Test-Path $flac) {
        Convert-Flac $flac $wav
        Write-Ok "$id.wav"
    } else {
        Write-Warn "$id.flac not found (utterance may not exist in chapter)"
    }
}

# speaker 1221 → accents bucket (utterances 0000-0002)
for ($i = 0; $i -le 2; $i++) {
    $id = "1221-135766-{0:D4}" -f $i
    $flac = Join-Path $ExtractDir "LibriSpeech\test-clean\1221\135766\$id.flac"
    $wav  = Join-Path $AccentsDir "$id.wav"
    if (Test-Path $flac) {
        Convert-Flac $flac $wav
        Write-Ok "$id.wav"
    } else {
        Write-Warn "$id.flac not found"
    }
}

# speaker 3570 → accents bucket (utterances 0000-0001)
for ($i = 0; $i -le 1; $i++) {
    $id = "3570-5694-{0:D4}" -f $i
    $flac = Join-Path $ExtractDir "LibriSpeech\test-clean\3570\5694\$id.flac"
    $wav  = Join-Path $AccentsDir "$id.wav"
    if (Test-Path $flac) {
        Convert-Flac $flac $wav
        Write-Ok "$id.wav"
    } else {
        Write-Warn "$id.flac not found"
    }
}

# ── 4. Build long-2min.wav (10 clips concatenated) ───────────────────────────
Write-Step "Building long-2min.wav"
$longDst = Join-Path $EdgeDir "long-2min.wav"
if (!(Test-Path $longDst)) {
    $clips = @()
    for ($i = 0; $i -le 9; $i++) {
        $id = "1089-134686-{0:D4}" -f $i
        $w = Join-Path $CleanDir "$id.wav"
        if (Test-Path $w) { $clips += $w }
    }
    if ($clips.Count -lt 5) { throw "Not enough clean clips to build long-2min.wav (got $($clips.Count))" }

    # Write ffmpeg concat list
    $listFile = Join-Path $env:TEMP "qs-concat.txt"
    ($clips | ForEach-Object { "file '$_'" }) | Set-Content $listFile -Encoding UTF8
    & $Ffmpeg -f concat -safe 0 -i $listFile -ar 16000 -ac 1 -acodec pcm_s16le $longDst -y 2>&1 | Out-Null
    Remove-Item $listFile -Force -ErrorAction SilentlyContinue
    if (!(Test-Path $longDst)) { throw "ffmpeg failed building long-2min.wav" }
    $dur = & $Ffmpeg -i $longDst 2>&1 | Select-String "Duration" | Select-Object -First 1
    Write-Ok "long-2min.wav created ($dur)"
} else {
    Write-Ok "long-2min.wav already exists"
}

# ── 5. Build multi-speaker.wav (two speakers interleaved) ─────────────────────
Write-Step "Building multi-speaker.wav"
$multiDst = Join-Path $EdgeDir "multi-speaker.wav"
if (!(Test-Path $multiDst)) {
    # Interleave by concatenating alternating utterances from two speakers
    $seg1 = Join-Path $CleanDir  "1089-134686-0000.wav"
    $seg2 = Join-Path $AccentsDir "1221-135766-0000.wav"
    $seg3 = Join-Path $CleanDir  "1089-134686-0001.wav"
    $seg4 = Join-Path $AccentsDir "1221-135766-0001.wav"
    $seg5 = Join-Path $CleanDir  "1089-134686-0002.wav"
    $seg6 = Join-Path $AccentsDir "1221-135766-0002.wav"

    $available = @($seg1,$seg2,$seg3,$seg4,$seg5,$seg6) | Where-Object { Test-Path $_ }
    if ($available.Count -lt 2) { throw "Not enough clips to build multi-speaker.wav" }

    $listFile = Join-Path $env:TEMP "qs-multi.txt"
    ($available | ForEach-Object { "file '$_'" }) | Set-Content $listFile -Encoding UTF8
    & $Ffmpeg -f concat -safe 0 -i $listFile -ar 16000 -ac 1 -acodec pcm_s16le $multiDst -y 2>&1 | Out-Null
    Remove-Item $listFile -Force -ErrorAction SilentlyContinue
    if (!(Test-Path $multiDst)) { throw "ffmpeg failed building multi-speaker.wav" }
    Write-Ok "multi-speaker.wav created"
} else {
    Write-Ok "multi-speaker.wav already exists"
}

# ── 6. Populate expected.json from official .trans.txt files ──────────────────
Write-Step "Populating expected.json with official transcripts"
$expectedPath = Join-Path $Here "expected.json"
$expected = Get-Content $expectedPath -Raw | ConvertFrom-Json

$transcripts = @{}

# Parse trans.txt for each chapter
$transFiles = @(
    (Join-Path $ExtractDir "LibriSpeech\test-clean\1089\134686\1089-134686.trans.txt"),
    (Join-Path $ExtractDir "LibriSpeech\test-clean\1221\135766\1221-135766.trans.txt"),
    (Join-Path $ExtractDir "LibriSpeech\test-clean\3570\5694\3570-5694.trans.txt")
)
foreach ($tf in $transFiles) {
    if (!(Test-Path $tf)) { Write-Warn "trans.txt not found: $tf"; continue }
    Get-Content $tf | ForEach-Object {
        if ($_ -match '^(\S+)\s+(.+)$') {
            $id  = $matches[1].ToLower()          # e.g. "1089-134686-0000"
            $txt = $matches[2].ToLower().Trim()   # lowercase (normalised for WER)
            $transcripts[$id] = $txt
        }
    }
}
Write-Ok "Loaded $($transcripts.Count) transcripts"

# Build long-2min expected text: concatenate the clean clips used
$longExpected = ""
for ($i = 0; $i -le 9; $i++) {
    $id = "1089-134686-{0:D4}" -f $i
    if ($transcripts.ContainsKey($id)) {
        $longExpected = ($longExpected + " " + $transcripts[$id]).Trim()
    }
}

# Build multi-speaker expected text: concatenate all interleaved segments
$multiExpected = ""
foreach ($id in @("1089-134686-0000","1221-135766-0000","1089-134686-0001","1221-135766-0001","1089-134686-0002","1221-135766-0002")) {
    if ($transcripts.ContainsKey($id)) {
        $multiExpected = ($multiExpected + " " + $transcripts[$id]).Trim()
    }
}

# Update expected.json
$updated = 0
foreach ($clip in $expected.clips) {
    $id = [System.IO.Path]::GetFileNameWithoutExtension($clip.file).ToLower()

    if ($clip.file -like "*/long-2min.wav" -and $longExpected -ne "") {
        $clip.expected_text = $longExpected
        $updated++
        continue
    }
    if ($clip.file -like "*/multi-speaker.wav") {
        $clip.expected_text = if ($multiExpected -ne "") { $multiExpected } else { "" }
        $updated++
        continue
    }
    if ($null -eq $clip.expected_text -and $transcripts.ContainsKey($id)) {
        $clip.expected_text = $transcripts[$id]
        $updated++
    }
}

$expected | ConvertTo-Json -Depth 10 | Set-Content $expectedPath -Encoding UTF8
Write-Ok "Updated $updated clips in expected.json"

# ── 7. Verify corpus completeness ─────────────────────────────────────────────
Write-Step "Corpus completeness check"
$missing = 0
foreach ($clip in $expected.clips) {
    $wavPath = Join-Path $Here $clip.file
    if (!(Test-Path $wavPath)) {
        Write-Warn "Missing: $($clip.file)"
        $missing++
    } elseif ($null -eq $clip.expected_text -and $clip.assert -ne "informational") {
        Write-Warn "No transcript: $($clip.file)"
        $missing++
    }
}

if ($missing -eq 0) {
    Write-Host "`n  All $($expected.clips.Count) corpus clips ready." -ForegroundColor Green
    Write-Host "  Run: .\run-stt-regression.ps1" -ForegroundColor Cyan
} else {
    Write-Host "`n  $missing clip(s) missing or without transcript." -ForegroundColor Yellow
    Write-Host "  Partial run is still possible; missing clips are skipped." -ForegroundColor Gray
}
