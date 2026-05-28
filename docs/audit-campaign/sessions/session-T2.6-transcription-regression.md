# Session T2.6 — Transcription Regression Corpus + Baseline Snapshot (BUILD)

> **Model:** Sonnet 4.6
> **Effort:** medium
> **Switch commands:** `/model sonnet` then `/effort medium`
> **Branch:** `audit/T2.6-transcription-regression`
> **Parallel-safe with:** T2.2, T2.3, T2.4, T2.5, and all of Track 1 (you create `Development/tests/transcription/` — its own directory; touches nothing other sessions own)
> **Depends on:** P0.2 (the test-harness scaffolding — `Development/tests/` exists, and `live-runner.ps1` / the transcription harness stub were created there; you build on that, not from scratch)
> **Blocks:** nothing directly — but it's the safety net that lets M.1 and future releases prove transcription quality hasn't regressed.
>
> Before pasting this prompt: confirm `/model sonnet` and `/effort medium`. This is corpus-assembly + a runner — bounded, spec-light, but the WER math and hallucination flagging must be correct. There is no `xhigh` on Sonnet; `medium` fits.

---

## Prompt to paste

You are building QuickSay's **transcription regression suite**: a small, curated audio corpus with expected transcripts, plus a runner that feeds each clip through QuickSay's actual transcription path (`HttpPostFile()` → Groq Whisper), computes Word Error Rate (WER), flags hallucinations, and emits a JSON report. You will run it once to capture a **committed baseline snapshot at v2.0** so that any future Whisper-side or code-side change that degrades transcription quality is caught by comparing against this baseline.

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2). Transcription goes: WAV captured → `HttpPostFile()` POSTs to Groq Whisper (`/openai/v1/audio/transcriptions`) → hallucination check (`IsWhisperHallucination()`) rejects silence artifacts ("Thank you for watching", repeated phrases, punctuation-only) → dictionary regex + voice commands → optional LLM cleanup. There is **no automated way today to know if a model swap, a prompt change, or a Groq-side update silently made transcription worse.** This session builds that safety net.

The research (`tooling-research.md` §8) specifies the corpus sources and the suite layout. Follow it.

Working directory: `C:\QuickSay\Development\`.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — Recording→Transcription Flow, `HttpPostFile()` in `lib/http.ahk`, `IsWhisperHallucination()` + `StripTrailingArtifacts()`, the Groq endpoint, config (`sttModel`, `language`, `recordingQuality`), DPAPI'd `groqApiKey`.
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign context, §6 test-harness table (`Development/tests/transcription/` is the target path), Status Tracker (update at end).
3. `docs/audit-campaign/research/tooling-research.md` — **§8 "Whisper STT Regression Testing"** — the corpus buckets (LibriSpeech test-clean, Common Voice accents, whisper-hallucinations dataset, synthetic silence/noise), the recommended `tests/audio/` layout, the WER + hallucination-flag approach, the Calm-Whisper backing.
4. The P0.2 scaffolding under `Development/tests/` — find the transcription harness stub P0.2 created and extend it. If P0.2 left a `transcription/` placeholder or a `live-runner.ps1`, reuse them.

### Scope — files you may create or touch

| Path | Action | Why |
|---|---|---|
| `Development/tests/transcription/corpus/` | **CREATE** | The audio clips, organized by bucket (see layout) |
| `Development/tests/transcription/expected.json` | **CREATE** | Ground-truth transcript + metadata per clip |
| `Development/tests/transcription/run-stt-regression.ps1` | **CREATE** | The runner: feed clip → transcribe → WER → hallucination flag → JSON report |
| `Development/tests/transcription/lib/` | **CREATE (as needed)** | WER computation, normalization, hallucination detection helpers |
| `Development/tests/transcription/baseline/` | **CREATE** | The committed baseline snapshot JSON (the v2.0 reference) |
| `Development/tests/transcription/README.md` | **CREATE** | How to run, how to refresh the baseline, what each bucket tests |
| `Development/tests/transcription/.gitignore` | **CREATE if needed** | Keep large audio out of git IF the team prefers download-on-demand (decide in Phase 1) |

**Forbidden** (do not modify — you only READ/CALL these):
- `Development/QuickSay.ahk` — you reuse its transcription logic conceptually, but the runner should call the **same HTTP path** (`HttpPostFile()` to Groq) rather than driving the full app, OR drive the app via the P0.2 live-runner. Do NOT modify `QuickSay.ahk`.
- `lib/http.ahk`, `lib/settings-ui.ahk` — call, don't change.
- Anything owned by other Track 2 sessions (`lib/license.ahk`, `lib/crash-reporter.ahk`, `release.ps1` signing, etc.).

### The corpus (≥20 cases total, per tooling-research §8)

Assemble these buckets. Aim for small, license-clean clips — you don't need hours of audio, you need *coverage*.

| Bucket | Count | Source | Purpose |
|---|---|---|---|
| `corpus/clean/` | **10** | LibriSpeech `test-clean` (openslr.org/12) — pick 10 short utterances with their official transcripts | Baseline WER on clean read speech |
| `corpus/accents/` | **a few** | Mozilla Common Voice English (commonvoice.mozilla.org/en/datasets) — a handful of accent-varied clips with their transcripts | Catch accent-handling regressions |
| `corpus/edge/` | **5** | Self-generate / curate the 5 edge cases below | Catch the failure modes that bite real users |

The **5 mandatory edge cases** (`corpus/edge/`), each with an expected behavior (not always exact text):
1. **`silence.wav`** — pure silence (generate via FFmpeg: `ffmpeg -f lavfi -i anullsrc -t 3 silence.wav`). Expected: empty / hallucination-flagged (this is exactly what `IsWhisperHallucination()` should catch — a known artifact like "Thank you for watching" here is a **fail**).
2. **`noise.wav`** — pure noise (FFmpeg `anoisesrc`). Expected: empty / hallucination-flagged.
3. **`short-utterance.wav`** — a single short word/phrase ("Okay." / "Hello.") near the 500ms floor. Expected: the exact short word, NOT dropped as a false-positive hallucination (this guards the false-positive risk T1.1 flagged for short legit utterances like "OK." / "No.").
4. **`long-2min+.wav`** — a >2-minute continuous clip. Expected: full transcript, no truncation, completes within timeout. (Stitch LibriSpeech clips if needed to reach length.)
5. **`multi-speaker.wav`** — two speakers / overlapping speech. Expected: best-effort transcript; the test asserts it doesn't crash or hallucinate, and records the WER as informational (multi-speaker WER is expected higher — flag it, don't fail on it).

> **Whisper-hallucinations dataset (optional bonus, per §8):** if time permits, pull a few clips from `sachaarbonel/whisper-hallucinations` (HuggingFace) into `corpus/hallucination/` — these are known silence/noise → hallucinated-text inputs, a direct test for `IsWhisperHallucination()`. Not required to hit the 20-case bar, but valuable.

**Each clip MUST have an entry in `expected.json`:**
```json
{
  "clips": [
    {
      "file": "clean/1089-134686-0000.wav",
      "bucket": "clean",
      "expected_text": "He hoped there would be stew for dinner...",
      "assert": "wer",            // "wer" | "empty_or_hallucination" | "exact" | "informational"
      "max_wer": 0.10,            // threshold for this clip (clean: tight; accents: looser)
      "source": "LibriSpeech test-clean 1089-134686-0000",
      "license": "CC BY 4.0"
    }
  ]
}
```

Record the `source` and `license` for every clip — these are third-party assets and provenance matters.

### Phase 1 — Decide: commit audio, or download-on-demand?

Audio files bloat git. Decide (and document in the README):
- **Option A — commit the clips** (simplest; the corpus is small — 20 short WAVs is a few MB). The suite is fully self-contained and CI can clone-and-run. Preferred unless the total exceeds ~25 MB.
- **Option B — download-on-demand**: commit only `expected.json` + a `fetch-corpus.ps1` that downloads the clips from their sources into `corpus/` (gitignored). More robust to repo bloat but adds a fetch step and depends on upstream availability.

Pick A if the curated set is small; B if it isn't. Either way, the runner must work after a fresh clone (Option B: run fetch first). Also ensure `Development/tests/` is excluded from the **installer** scope (per MASTER-PLAN §6: tests are committed to git but must NOT be bundled into the .exe — verify `setup.iss` doesn't pull them in; if it might, note it for T1.6/M.1, do NOT edit setup.iss yourself).

### Phase 2 — Build the runner (`run-stt-regression.ps1`)

The runner, given the corpus + `expected.json`, for each clip:

1. **Transcribe** via QuickSay's real path. Two viable approaches — pick the one P0.2 set up:
   - **Direct API parity:** POST the WAV to Groq Whisper the same way `HttpPostFile()` does (same endpoint, same `sttModel`/`language`/multipart fields read from config). This is faster and isolates the model's output. Reuse the exact request shape from `lib/http.ahk` / `QuickSay.ahk` so it's representative.
   - **Through the app:** drive `QuickSay.ahk` via the P0.2 `live-runner.ps1` to exercise the full pipeline (incl. `IsWhisperHallucination()` + dictionary). Slower, but tests the whole chain.
   - **Recommended:** do BOTH layers — capture the **raw** Whisper output (API parity) AND apply QuickSay's `IsWhisperHallucination()` logic to it (port/call the same check), so the report shows both "what Whisper said" and "what QuickSay would keep." The edge cases (silence/noise) specifically test the hallucination filter, so you need its verdict.
   - The API key: read the DPAPI'd `groqApiKey` the same way the app does, OR accept it from an env var for CI (`GROQ_API_KEY`). Never print it; never write it to the report.

2. **Normalize** both expected and actual for WER (lowercase, strip punctuation, collapse whitespace — standard WER preprocessing). Document the normalization exactly (so WER numbers are reproducible).

3. **Compute WER** = (substitutions + insertions + deletions) / reference-word-count, via Levenshtein on the word sequences. Implement it correctly (it's the standard edit-distance over tokens) — add a unit self-test with a known pair (e.g. ref "the cat sat", hyp "the cat sit" → 1 sub / 3 = 0.333).

4. **Flag hallucinations** on the edge/silence/noise clips: if `assert == "empty_or_hallucination"`, the clip PASSES when the output is empty or `IsWhisperHallucination()` would reject it, and FAILS if real text leaks through.

5. **Per-clip verdict** against its `assert` + `max_wer`:
   - `wer`: pass if WER ≤ `max_wer`.
   - `exact`: pass if normalized output == normalized expected.
   - `empty_or_hallucination`: pass if empty or hallucination-flagged.
   - `informational`: always "pass," but record the WER for tracking (multi-speaker).

6. **Emit a JSON report**: per-clip `{file, bucket, expected, actual_raw, actual_kept, wer, hallucination_flagged, assert, max_wer, verdict}`, plus a summary `{total, passed, failed, mean_wer_clean, mean_wer_accents, run_at, stt_model, language}`.

7. **Exit code:** `0` if every clip meets its assertion (green); `1` if any clip regresses against its assertion **or** against the committed baseline (Phase 4). This is what makes it CI-able.

### Phase 3 — Run it, sanity-check, tune thresholds

Run the suite against the current app. Inspect the report:
- Clean clips should have low WER (Whisper-large is good on LibriSpeech — expect WER well under 10%). If a clean clip is wildly off, your normalization or the clip↔transcript pairing is wrong — fix it, don't loosen the threshold to hide it.
- Edge cases behave as specified (silence/noise → flagged; short utterance → kept).
- Set each clip's `max_wer` to a sane threshold: tight for clean (e.g. 0.10), looser for accents (e.g. 0.25), informational for multi-speaker. Justify the thresholds in the README.

### Phase 4 — Capture the committed baseline snapshot

Once the suite runs clean and thresholds are justified:
- Write the run's report to `Development/tests/transcription/baseline/baseline-v2.0.json` and **commit it**. This is the v2.0 reference.
- Add a `-CompareBaseline` mode to the runner: re-run the corpus, compare each clip's WER to the baseline. If any clip's WER is **materially worse** than baseline (define the tolerance — e.g. WER increased by >0.05 absolute or crossed its `max_wer`), the runner reports a **regression** and exits `1`. This is the actual regression-detection use: M.1 and future releases run `-CompareBaseline` to prove transcription didn't degrade.
- Add a `-RefreshBaseline` mode (explicit, never automatic) so a future intentional improvement can re-baseline with a human in the loop. Document that re-baselining requires a deliberate decision (you don't silently overwrite the reference when quality changes).

### Phase 5 — Verification

Invoke `superpowers:verification-before-completion`. Real evidence per gate.

1. **End-to-end run:** `run-stt-regression.ps1` runs all ≥20 cases against Groq and produces the JSON report. Paste the summary block.
2. **Green exit:** with the tuned thresholds, the suite exits `0`. Paste `echo "EXIT: $LASTEXITCODE"`.
3. **WER self-test:** the known-pair WER unit test passes (proves the math).
4. **Edge cases correct:** silence.wav + noise.wav → flagged (pass); short-utterance.wav → kept, not dropped (pass). Paste those rows.
5. **Baseline committed:** `baseline/baseline-v2.0.json` exists and is committed.
6. **Regression detection works:** artificially inject a regression (e.g. temporarily set a clean clip's expected text to something the model won't match, OR point `-CompareBaseline` at a hand-edited baseline with much lower WER) → `-CompareBaseline` reports a regression and exits `1`. Revert the injection. Paste the regression output.
7. **Fresh-clone runnable:** describe (or test) that after a clean clone, `run-stt-regression.ps1` works (Option B: after `fetch-corpus.ps1`).
8. **No key leak:** the report and console output contain no `gsk_` / API key. Grep-confirm.
9. `code-review` on the runner + helpers; address P0/P1.

### Done When

- [ ] `Development/tests/transcription/` exists with `corpus/` (≥20 clips across clean/accents/edge), `expected.json` (ground truth + license + assert per clip), `run-stt-regression.ps1`, `baseline/`, `README.md`.
- [ ] Corpus has the 10 LibriSpeech clean clips, the accent clips, and all 5 mandatory edge cases (silence, noise, short utterance, >2min, multi-speaker).
- [ ] Runner feeds each clip through QuickSay's transcription path (`HttpPostFile` parity and/or the live app), computes WER, and flags hallucinations.
- [ ] WER computation is correct (known-pair self-test passes); normalization documented.
- [ ] Runner emits a JSON report and is CI-able: **exit 0 when green, exit 1 on regression** (proven both ways — gates 2 and 6).
- [ ] Baseline snapshot `baseline/baseline-v2.0.json` committed; `-CompareBaseline` detects degradation; `-RefreshBaseline` is explicit-only.
- [ ] Edge cases behave correctly (silence/noise flagged; short utterance kept) — gate 4.
- [ ] No API key leaks into the report or logs (gate 8).
- [ ] Every clip has documented `source` + `license`.
- [ ] `Development/tests/` is not bundled into the installer (verified or noted for M.1; don't edit setup.iss).
- [ ] `code-review` run; P0/P1 addressed.
- [ ] Branch `audit/T2.6-transcription-regression` committed; PR opened against `main`.
- [ ] MASTER-PLAN.md Status Tracker updated: `T2.6 — Transcription regression corpus` → ✅ done. Note the case count + the baseline mean WER (clean).

### What NOT to do

- ❌ Do not modify `QuickSay.ahk`, `lib/http.ahk`, or `lib/settings-ui.ahk`. Call/parity them; don't change them. If the runner needs the hallucination logic, port a faithful copy into the test lib (and note the duplication for future sync) or drive the live app — do not edit the source to make testing easier.
- ❌ Do not loosen a WER threshold to make a failing clip "pass" if the real cause is a bad clip↔transcript pairing or wrong normalization. Fix the cause.
- ❌ Do not commit huge audio. Keep the corpus small (short clips). If it's big, use download-on-demand (Option B).
- ❌ Do not commit any audio without recording its license/provenance. LibriSpeech (CC BY 4.0) and Common Voice (CC0) are fine; respect attribution.
- ❌ Do not print or write the Groq API key anywhere. Read it like the app does (DPAPI) or from `GROQ_API_KEY` env for CI.
- ❌ Do not auto-overwrite the baseline. `-RefreshBaseline` is an explicit, human-decided action.
- ❌ Do not let the multi-speaker clip's (expectedly high) WER fail the suite — it's `informational`.
- ❌ Do not bundle this corpus into the installer. It's a dev/CI artifact.
- ❌ Do not refactor app transcription logic "to make it testable." Flag improvements via `spawn_task`.

### Estimated time

Phase 1 (corpus decision + assembly): 60–90 min (sourcing/curating clips is the bulk). Phase 2 (runner + WER + hallucination flag): 90 min. Phase 3 (run + tune thresholds): 30 min. Phase 4 (baseline + compare/refresh modes): 30 min. Phase 5 (verification): 30 min. **Total wall-clock: ~4 hours** (corpus curation dominates).

### When you're done

Report back with:
- The runner invocation + the summary block (total / passed / failed / mean clean WER / mean accent WER).
- The green `EXIT: 0` and the injected-regression `EXIT: 1` outputs (gates 2 + 6).
- The case count by bucket and confirmation all 5 mandatory edge cases are present + behaving.
- Whether you chose committed-audio (A) or download-on-demand (B) and why.
- The baseline file path + the v2.0 baseline mean clean WER.
- Confirmation no API key leaks into the report.
- Anything you noticed about `IsWhisperHallucination()` (false-positive/false-negative behavior on the corpus) — useful signal for the core engine; flag via `spawn_task` if it's a real bug, don't fix here.
