# Session F.4: Offline Transcription Spike (benchmark + go/no-go, NO app integration)

> **Model:** Fable 5 (`/model claude-fable-5`), Opus 4.8 acceptable
> **Effort:** high (`/effort high`)
> **Branch:** none needed for the spike itself (no app code changes); artifacts land in `tests/offline-spike/` on `feature/F.4-offline-spike` if anything is worth keeping.
> **Parallel-safe with:** F.1/F.2/F.3 (touches no shared app files). Run it whenever.
> **Depends on:** nothing.
> **Why:** Offline/local mode is the flagship next-cycle bet from the 2026-07-22 competitive deep-dive (privacy moat vs Wispr's audio-cache scandal, kills even the pennies of Groq dependency, matches Superwhisper's headline feature). Research verdict: whisper.cpp (MIT) + distil-small.en default + large-v3-turbo-q8 opt-in, persistent local server. **The single unresolved unknown is real latency on a mid-range consumer laptop CPU: every published benchmark is GPU, desktop CPU, or unspecified. This spike replaces third-party numbers with measurements before any build is approved.**

---

## Prompt to paste

You are running a measurement spike, not a build. Decide with evidence whether QuickSay's offline mode meets the latency bar on real hardware, and produce a go/no-go recommendation. Do not integrate anything into QuickSay.ahk.

### Research already in hand (2026-07-22; trust it, verify only what is marked open)

- **Engine choice: whisper.cpp** (MIT, 51.8k stars, active through June 2026). Official Windows release zips ship `whisper-cli.exe` + `whisper-server.exe` (HTTP). It is the ONLY candidate engine confirmed to support `initial_prompt`, which preserves QuickSay's E.2 dictionary-biasing investment unchanged. Alternatives rejected for v1: sherpa-onnx/Parakeet (fastest CPU numbers, but weaker on accented English per multiple 2026 write-ups AND no documented biasing lever), whisperfile (packaging fallback, older fork), Moonshine (least field-proven; non-English models under a community license).
- **Model candidates to benchmark:** `distil-small.en` (~5.6x faster than large-v2 at ~1% WER delta, English-only), `base.en` quantized, `large-v3-turbo` q8_0 (~874MB, int8 costs <0.1% WER). Parakeet 0.6B int8 via sherpa-onnx as a comparison point ONLY (RTF 0.325 on i7-12700K desktop, unverified on laptops).
- **Vulkan iGPU path:** whisper.cpp 1.8.3 showed ~12x speedup on integrated GPUs (Phoronix, Ryzen 680M / Intel Arc), but there is NO official Windows Vulkan binary yet (open issue, Feb 2026); third-party builds exist (jerryshell, DomoticX). Benchmark CPU-only first; Vulkan is a stretch goal measurement.
- **Latency bar (from the competitive analysis):** text within ~1-3 s of hotkey release for a ~10 s utterance, mid-range laptop CPU, no discrete GPU. Model load time (2-10 s) is why the eventual architecture is a persistent warm server; for the spike, measure load time and inference time separately.
- **Distribution facts for the writeup (no action):** every competitor (VoiceInk, MacWhisper, Superwhisper) downloads models on demand post-install rather than bundling; SHA-256 verification is standard; a shipped engine exe must be code-signed through release.ps1 or it resets SmartScreen reputation (Windows 11 Smart App Control can block unsigned binaries outright).

### Phase 1: Bench harness (~1 h)
1. Download the official whisper.cpp Windows x64 release + models: `base.en` (q5/q8), `distil-small.en` (convert or fetch ggml build), `large-v3-turbo` q8_0. Record exact versions/hashes.
2. Test corpus: reuse `tests/transcription/` clips (T2.6 20-clip corpus + E.2 spontaneous tier) so WER is comparable to the cloud baseline. Add one ~10 s and one ~60 s clip if the corpus lacks them.
3. Harness script (PowerShell, in `tests/offline-spike/`): per model, measure (a) cold model-load ms, (b) inference ms per clip, (c) peak RAM, on the user's actual machine. Run each 3x, report median. Use `whisper-cli.exe` for simplicity; note that server mode removes load time from the per-request path.

### Phase 2: Measure (~1-1.5 h)
1. CPU-only runs across all models x all clips. Compute RTF (audio seconds / inference seconds) and the derived "wait after release" for a 10 s utterance.
2. WER against the corpus reference texts; compare with the recorded cloud whisper-large-v3-turbo baselines from T2.6/E.2.
3. `initial_prompt` parity check: run the E.2 jargon clips with the same bias sentence `BuildWhisperBiasPrompt` would emit; confirm biased terms transcribe correctly and no prompt-echo-on-silence regression (the E.2 `IsBiasPromptEcho` failure mode).
4. Stretch: one Vulkan third-party build measurement on the iGPU, clearly labeled as third-party-binary numbers.

### Phase 3: Decision doc (~1 h)
Write `C:\QuickSay\docs\audit-campaign\findings\F.4-offline-spike.md`:
- The full measurement table (model x clip x load/infer/RAM/WER).
- Go/no-go per tier: does ANY model meet the 1-3 s bar on this hardware? Which model is the shippable default, which the opt-in?
- The build plan IF go (from research, adjusted by measurements): Phase 1 spawn-per-request MVP behind a "Transcribe offline (beta)" settings toggle; Phase 2 persistent warm `whisper-server.exe` with crash/restart lifecycle; Phase 3 on-demand model download with the Ed25519 signed-manifest pattern from `lib/update-verify.ahk` + code-signed engine exe via release.ps1; Phase 4 Vulkan fast path.
- Explicit risks carried forward: accented-speech regression vs cloud, SmartScreen on the second exe, installer/download size.

### Done When
- [ ] Measurement table complete on real hardware, 3-run medians, exact versions/hashes recorded.
- [ ] WER compared against the existing cloud baselines on the SAME corpus.
- [ ] `initial_prompt` biasing parity confirmed or refuted with evidence.
- [ ] Go/no-go recommendation with a named default model, written to the findings doc.
- [ ] No changes to any app source file.

### What NOT to do
- Do not integrate into QuickSay.ahk, the installer, or settings (that is the follow-up build session, gated on this spike's verdict).
- Do not benchmark on cloud VMs or quote third-party numbers as findings; the entire point is first-party laptop measurements.
- Do not commit model binaries or engine exes to git (gitignore `tests/offline-spike/bin/` and `models/`).
- Do not spend more than ~30 min fighting a Vulkan build; it is a stretch goal, CPU numbers decide the spike.

### Estimated time
~3-4 h total.

### When you're done, report back with
- The one-line verdict: go / no-go / go-with-caveats, and the recommended default model.
- The measured "wait after release" for a 10 s utterance per model.
- Whether biasing parity held.
