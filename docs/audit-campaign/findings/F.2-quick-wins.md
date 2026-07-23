# F.2 Findings — Competitive Quick Wins

> **Session:** F.2 (2026-07-22), per `sessions/session-F.2-quick-wins.md`
> **Branch:** `feature/F.2-quick-wins` (Development repo), off `main` @ 3b8a44a
> **Commits:** 8a06b06 (Phase 1), 3025150 (Phase 2), 1a0e0cf (Phase 3), 1207630 (Phase 4), 49274a0 (review wording fix)
> **Prompt wording:** user-approved 2026-07-22.

## What shipped

1. **Language auto-detect** — new `lib/languages.ahk` is the single source of truth for the 25-language list (`GetLanguageList()`, `GetLanguageCodeToName()`, `GetLanguageNameToCode()`, `ResolveLanguageCode()`, `AddLanguageField()`), `#Include`d by both binaries. "Auto-detect" (`value="auto"`) is the first option in the settings dropdown and tray submenu. All three Whisper call sites now build the form via `AddLanguageField()`, which **omits the `language` field entirely** (not empty-string) for `auto`/empty — Whisper requires the field absent for auto-detect.
2. **STT model picker** — settings dropdown "Transcription model": *Fast (recommended)* = `whisper-large-v3-turbo`, *Max accuracy* = `whisper-large-v3`. Hard allow-list in `ParseConfig` (QuickSay.ahk:1906-1909): any other value falls back to turbo. No free-text path.
3. **Friendly 429 handling** — both HTTP helpers (`HttpPostFile` in lib/http.ahk, `HttpPostJson` in QuickSay.ahk) capture the `Retry-After` header on 429; shared `FormatRateLimitMessage()` renders "Groq's free-tier speed limit reached. Wait N seconds and try again." at all 429 surfaces (file path, live path, onboarding demo). 401/403/500/503 branches untouched. **Auto-retry included for the LLM cleanup call only** via `HttpPostJsonWithRetry429()`: one retry when `retry-after` ≤ 15s, otherwise skip + friendly TrayTip + raw-transcript fallback. No new Whisper retry.
4. **Language-neutral cleanup prompts** — the filler-removal and Casual slang-whitelist sentences in all four mode prompts are now language-generic with the English items kept as examples. Both `GetDefaultModes()` copies verified byte-identical (independent SHA-256 of extracted bodies). All FORBIDDEN guardrail blocks byte-for-byte unchanged.

## Verification (all green, 2026-07-22)

Unit suites: history 22/22, crash 36/36, telemetry 43/43, datadir 22/22 (+4 parse probes), dictionary 5/5, license 6/6, update 4/4, cleanup-guard 39/39.
E.2 cleanup harness (live LLM, gpt-oss-20b, temp 0.3): **24/24 PASS** — guardrail cases A1–A4 (never answer) and B1–B2 (never inject) explicitly green against the new prompts.

### T2.6 corpus WER (29 clips incl. E.2 spontaneous + jargon tiers)

| Tier (n) | turbo, bias OFF | turbo, bias ON | v3, bias OFF | v3, bias ON | Baseline v2.0 |
|---|---|---|---|---|---|
| clean (10) | 0.00% | 3.39% | 3.49% | 2.83% | 0.00% |
| accents (5) | 2.33% | 2.87% | 1.72% | 2.97% | 2.33% |
| edge (3) | 1.30% | 3.06% | 0.55% | 5.04% | 1.30% |
| spontaneous (6) | 0.00% | 0.00% | 0.98% | 0.98% | — (new) |
| jargon (3) | 7.47% | 4.44% | 12.59% | 8.89% | — (new) |
| **Aggregate (27 scored)** | **1.41%** | 2.62% | 3.29% | 3.36% | 0.86% (20-clip set) |

Result files: `Development/tests/transcription/results/20260722-2015*.json` … `-202035.json`. Turbo/bias-OFF matched `baseline-v2.0.json` exactly on every overlapping clip — **no regression** from F.2.

### Bias-prompt decision (Done-When item)

**Dictionary bias stays gated to turbo + live-dictation path only; NOT extended to `whisper-large-v3`.** On v3 bias is a wash in aggregate (3.29%→3.36%) and clearly hurts long-form/edge (0.55%→5.04%). The only consistent bias win (jargon: turbo 7.47%→4.44%, v3 12.59%→8.89%) is already captured by the existing gating. Turbo remains the stronger base model overall and the recommended default; v3 earns its "Max accuracy" label on accents (1.72% vs 2.33%) and edge (0.55% vs 1.30%) unbiased.

## Notes & residuals

- **Fifth duplicate language map**: session evidence listed four; a fifth (code→name, in `SelectLanguage()`) existed and was unified too. The two legacy name→code maps only covered 7 of 25 languages — a latent bug for legacy full-name configs, fixed by deriving the map from the full list.
- **Pre-existing Whisper 429 retry**: `HttpPostFileWithRetry()` (QuickSay.ahk:3750) has done one blind 2s retry on 429 since a prior session. Left as-is (predates F.2; friendly message still shows if the retry fails, using the second response's Retry-After). Possible future tweak: use Retry-After for that sleep.
- **`language=auto` wire check**: field omission is source-verified (all three sites go through `AddLanguageField()`); no harness exercises auto-detect (`run-stt-regression.ps1` hardcodes `en`). Residual: one live dictation with Language→Auto-detect + debugLogging to confirm on the wire; fold into E.5/UAT smoke.
- **artifact-filter.ahk untouched**: no citable source for non-English Whisper hallucination phrase lists was found; per the session's "do not invent phrase lists" rule, nothing added. The language-agnostic single-word fallback remains the only non-English guard.
- **Custom-mode migration**: users who saved custom modes based on the old prompts keep their saved text (custom prompts are stored verbatim in config); only the four built-in defaults changed. No migration needed; users who cloned a built-in mode before F.2 keep English-only filler lists until they re-clone.
- **Onboarding demo** reads `sttModel` without an allow-list; harmless (value comes from our own onboarding write or tray-sanitized config) — the tray process re-sanitizes via `ParseConfig` before real use.
