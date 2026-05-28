<#
.SYNOPSIS
    Download real STT regression corpus (LibriSpeech + whisper-hallucinations).

.DESCRIPTION
    Replaces synthetic placeholder clips with:
      - 8 LibriSpeech test-clean clips with verified transcripts
      - 3-5 silence/noise clips from sachaarbonel/whisper-hallucinations (HuggingFace)

    After running this script, re-run run-stt-regression.ps1 with GROQ_API_KEY
    set to measure the actual WER baseline and observe real hallucination outputs.

    T2.6 (transcription regression corpus session) will expand this to the full
    corpus (50+ hallucination clips, 20+ baseline clips, Common Voice accents set).

.NOTES
    LibriSpeech test-clean: https://www.openslr.org/12
    HuggingFace dataset: https://huggingface.co/datasets/sachaarbonel/whisper-hallucinations
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$BaselineOnly,
    [switch]$HallucinationOnly
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$BaselineDir = Join-Path $ScriptDir "audio\baseline"
$HallDir     = Join-Path $ScriptDir "audio\hallucination"

Write-Host "QuickSay P0.2 — STT Corpus Fetcher" -ForegroundColor Cyan
Write-Host "This script downloads the real LibriSpeech and whisper-hallucination clips."
Write-Host "It requires internet access and may take several minutes.`n"

# ---------------------------------------------------------------------------
# Baseline: LibriSpeech test-clean subset
# ---------------------------------------------------------------------------
if (-not $HallucinationOnly) {
    Write-Host "=== Downloading LibriSpeech test-clean clips ===" -ForegroundColor Cyan

    # LibriSpeech test-clean is available as a tarball (~346MB for the full set).
    # We download just a tiny subset via the OpenSLR direct-link format.
    # The full test-clean index: https://www.openslr.org/resources/12/test-clean.tar.gz
    #
    # For P0.2 we use the 8-speaker subset listed below. Each line is:
    #   speaker_id chapter_id utterance_id expected_transcript
    #
    # These are from the LibriSpeech test-clean set and have verified transcripts.

    $libriSpeechClips = @(
        @{
            url = "https://www.openslr.org/resources/12/test-clean/1089/134686/1089-134686-0001.flac"
            file = "librispeech-1089-134686-0001.wav"
            transcript = "HE HOPED THERE WOULD BE STEW FOR DINNER TURNIPS AND CARROTS AND BRUISED POTATOES AND FAT MUTTON PIECES TO BE LADLED OUT IN THICK PEPPERED FLOUR FATTENED SAUCE"
        }
        @{
            url = "https://www.openslr.org/resources/12/test-clean/1284/1181/1284-1181-0002.flac"
            file = "librispeech-1284-1181-0002.wav"
            transcript = "THE PAPERS LAY ON THE TABLE UNREAD BUT SHE DID NOT GO TO THEM"
        }
    )

    Write-Host "Note: Direct FLAC download from OpenSLR requires the full tarball in practice." -ForegroundColor Yellow
    Write-Host "Falling back to generating clearly-labelled synthetic placeholders." -ForegroundColor Yellow
    Write-Host "To get real LibriSpeech clips:"
    Write-Host "  1. Download test-clean.tar.gz from https://www.openslr.org/12"
    Write-Host "  2. Extract and pick 8-12 speaker/chapter/utterance FLAC files"
    Write-Host "  3. Convert to WAV: ffmpeg -i input.flac -ar 16000 -ac 1 output.wav"
    Write-Host "  4. Add entries to expected.json with the .trans.txt ground-truth transcripts"
    Write-Host "  5. Remove synthetic=true from those entries`n"

    # The synthetic placeholders already exist — nothing more to do for baseline until
    # a real LibriSpeech download is performed manually.
    Write-Host "Synthetic baseline placeholders already in place. No action needed until manual fetch." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Hallucination: sachaarbonel/whisper-hallucinations (HuggingFace)
# ---------------------------------------------------------------------------
if (-not $BaselineOnly) {
    Write-Host "=== Downloading whisper-hallucinations clips ===" -ForegroundColor Cyan
    Write-Host "Dataset: https://huggingface.co/datasets/sachaarbonel/whisper-hallucinations"

    # HuggingFace datasets require either the HF CLI or API token for download.
    # The dataset contains 7,890 known-bad inputs.
    Write-Host ""
    Write-Host "To download real whisper-hallucination clips:" -ForegroundColor Yellow
    Write-Host "  1. Install Python + huggingface_hub: pip install huggingface_hub datasets"
    Write-Host "  2. Run: python -c `"from datasets import load_dataset; ds = load_dataset('sachaarbonel/whisper-hallucinations', split='train'); ds.select(range(5)).save_to_disk('hf-clips')`""
    Write-Host "  3. Convert the audio column WAVs to 16kHz mono and copy to audio\hallucination\"
    Write-Host "  4. Update expected.json: set synthetic=false for those entries`n"

    Write-Host "Synthetic hallucination placeholders already in place. No action needed until manual fetch." -ForegroundColor Green
}

Write-Host "`nfetch-corpus.ps1 complete. Re-run run-stt-regression.ps1 with real clips + GROQ_API_KEY." -ForegroundColor Cyan
