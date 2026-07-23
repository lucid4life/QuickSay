# QuickSay STT Regression Suite (T2.6)

Detects transcription quality regressions before each release. Feeds WAV clips through
QuickSay's actual transcription path (direct API parity with `HttpPostFile()` → Groq Whisper),
computes Word Error Rate (WER), flags hallucinations, and emits a JSON report.

---

## Quick Start

```powershell
# 1. One-time corpus download (~346 MB LibriSpeech)
.\tests\transcription\fetch-corpus.ps1

# 2. Run the suite (GROQ_API_KEY env var or DPAPI from app config)
cd Development
$env:GROQ_API_KEY = "gsk_..."
.\tests\transcription\run-stt-regression.ps1

# 3. Compare against the committed v2.0 baseline
.\tests\transcription\run-stt-regression.ps1 -CompareBaseline
```

Exit `0` = all clips pass. Exit `1` = failure or regression detected. Exit `2` = config error.

---

## Corpus Layout

```
corpus/
  clean/     10 LibriSpeech test-clean clips (speaker 1089, chapter 134686)
  accents/    5 LibriSpeech test-clean clips (speakers 1221, 3570 — diverse speaker set)
  edge/       5 edge cases (generated/constructed)
    silence.wav          pure silence — must be rejected by hallucination filter
    noise.wav            white noise  — must be rejected by hallucination filter
    short-utterance.wav  ~1.5s SAPI "okay" — guards false-positive risk (T1.1 #015)
    long-2min.wav        all 38 chapter-1089 utterances concatenated (~276s, >2 min)
    multi-speaker.wav    two LibriSpeech speakers interleaved

baseline/
  baseline-v2.0.json   committed v2.0 baseline snapshot

lib/
  wer.ps1          WER computation + Normalize-Text + Test-WER self-test
  hallucination.ps1  PowerShell port of IsWhisperHallucination() + StripTrailingArtifacts()
```

`corpus/clean/`, `corpus/accents/`, `corpus/edge/long-2min.wav`, and `corpus/edge/multi-speaker.wav`
are **gitignored** (download-on-demand). Run `fetch-corpus.ps1` after a fresh clone.

---

## Corpus Sources & Licenses

| Bucket    | Source | License |
|-----------|--------|---------|
| `clean`   | LibriSpeech test-clean (openslr.org/12), speaker 1089, ch 134686 | CC BY 4.0 |
| `accents` | LibriSpeech test-clean (openslr.org/12), speakers 1221 & 3570 | CC BY 4.0 |
| `edge/silence.wav` | FFmpeg `anullsrc` 3s synthetic silence | generated |
| `edge/noise.wav` | FFmpeg `anoisesrc` 3s white noise | generated |
| `edge/short-utterance.wav` | Windows SAPI TTS "okay" ~1.5s | generated |
| `edge/long-2min.wav` | LibriSpeech clips concatenated by `fetch-corpus.ps1` | CC BY 4.0 |
| `edge/multi-speaker.wav` | LibriSpeech speakers 1089 + 1221 interleaved | CC BY 4.0 |

LibriSpeech is derived from LibriVox audiobooks (public domain) and released under CC BY 4.0.

---

## WER Thresholds & Rationale

| Bucket    | `max_wer` | Rationale |
|-----------|-----------|-----------|
| `clean`   | 0.10 (10%) | Whisper-large-v3-turbo achieves <5% on LibriSpeech test-clean. 10% gives headroom for API variation without masking real regressions. |
| `accents` | 0.20 (20%) | Diverse-speaker speech is harder; 20% is tight enough to catch severe regressions. |
| `edge/silence` | n/a | `empty_or_hallucination` — must be rejected by filter |
| `edge/noise` | n/a | `empty_or_hallucination` — must be rejected by filter |
| `edge/short-utterance` | n/a | `exact_raw` — asserts Whisper returns "okay" at API level (see note below) |
| `edge/long-2min` | 0.15 (15%) | Slight allowance for the concat seam |
| `edge/multi-speaker` | n/a | `informational` — WER recorded but never fails the suite |

**Short-utterance false-positive note (T1.1 finding #015):** `IsWhisperHallucination()` flags
single-word output as a hallucination artifact. "okay" is correctly returned by Whisper
(`actual_raw` = "okay") but is dropped by the filter (`actual_kept` = ""). The test
asserts `actual_raw` is correct (Whisper is fine); the false positive is a known gap in
the app's filter, tracked separately.

---

## WER Normalization

Both reference and hypothesis are normalized before WER comparison:

1. Lowercase
2. Expand common contractions (won't → will not, can't → cannot, etc.)
3. Strip all punctuation (replace `[^\w\s]` with space)
4. Collapse whitespace

Normalization is implemented in `lib/wer.ps1 : Normalize-Text`. LibriSpeech references are
already uppercase in the official transcripts; they are lowercased during normalization.

**WER self-test** (gate 3): `ref="the cat sat"`, `hyp="the cat sit"` → 1 sub / 3 words = 0.3333.
Run: `.\run-stt-regression.ps1 -WerSelfTest`

---

## API Key

The runner uses this resolution order:

1. `-ApiKey gsk_...` parameter
2. `$env:GROQ_API_KEY` (CI / automation)
3. DPAPI-decrypted `groqApiKey` from `%LOCALAPPDATA%\Programs\QuickSay Beta\config.json`
   (same key the app uses; `lib/dpapi.ahk` entropy `"QuickSay-v1-entropy-2026"`)

The key is **never written to the report** (`results/*.json`). A post-run grep confirms this.

---

## Refreshing the Baseline

The baseline (`baseline/baseline-v2.0.json`) is the v2.0 reference. **Never auto-overwrite it.**

To update after an intentional quality improvement (new model, better normalization, etc.):

```powershell
.\run-stt-regression.ps1 -RefreshBaseline   # prompts "Type YES to confirm"
git add baseline/baseline-v2.0.json
git commit -m "chore(stt): refresh baseline — <reason for improvement>"
```

**Do not run `-RefreshBaseline` to hide a regression.** If WER has increased, investigate
the cause (model change, prompt change, Groq-side update) before re-baselining.

---

## CI Integration

```yaml
- name: STT regression
  run: |
    cd Development
    pwsh tests/transcription/run-stt-regression.ps1 -CompareBaseline
  env:
    GROQ_API_KEY: ${{ secrets.GROQ_API_KEY }}
```

Requires the corpus to be pre-fetched. For CI, commit the audio to the repo (Option A) or
run `fetch-corpus.ps1` as a separate setup step (Option B, current config).

---

## Installer Note

`Development/tests/` is committed to git but **not bundled in the installer** (`setup.iss`
copies only named paths; no wildcard includes `tests\`). Verified during T2.6.
