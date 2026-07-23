# E.2 — Transcription Quality Lab: findings

> Session: 2026-07-13/14 · Branch: `audit/E.2-transcription-lab` (Development) · Model: Fable 5, xhigh
> Scope: full-history mining (every entry ever recorded) → cleanup-stage fix → Whisper dictionary biasing → dogfood instrumentation → corpus expansion.
> Privacy: all history content analyzed locally + Anthropic/Groq only (user-authorized 2026-07-13). **No raw dictation content appears in this document, in commits, or in any committed test asset.**

## 1. The corpus (Phase 1)

| Source | Entries (unique) | Notes |
|---|---|---|
| Live `%APPDATA%\QuickSay\data\history.json` | 500 | current era (June–July 2026, GPT-OSS + guardrail prompts) |
| Live `history_backup.json` | 2 | |
| Legacy `%LOCALAPPDATA%\Programs\QuickSay Beta\data\history.json` (1.656 GB) | 819 | Feb 2026 era; streamed, never loaded whole |
| **Total** | **1,321** | 0 parse failures, 0 duplicate ids |

**The 1.6 GB mystery solved:** the legacy file holds only 819 entries. Its size is **exponential UTF-8 double-encoding** by the pre-T1.5 writer — each save re-encoded non-ASCII characters (an em dash, window-title arrows), ballooning one `appContext` field to **148 MB** and one `cleanedText` to 296 KB of mojibake. 18 divergent pairs are pure encoding corruption. T1.5's history-core rewrite (real JSON serializer, UTF-8 raw atomic writes) already fixed the writer; the legacy file is archival. **Recommendation: leave it in place (or archive-and-delete after E-series) — nothing reads it.**

Pipeline: mechanical pre-classification (`tests/transcription/tools/mine-history.mjs`) → 12-agent LLM classification of all 399 non-mojibake harmful/ambiguous/benign-sample pairs → adversarial spot-check (8 verdicts re-derived by hand, 6 confirmed outright, 2 consistent-but-truncated).

## 2. Baseline harmful-cleanup rate (the number the fix must beat)

| Era | Entries | Confirmed harmful cleanups | Rate |
|---|---|---|---|
| Legacy (LLaMA 3.3 → Feb-14 guardrails) | 819 | 53 | 6.5% |
| Live (GPT-OSS 20B + guardrail prompts) | 502 | 46 | **9.2%** |
| **Overall** | **1,321** | **99** | **7.5%** (~8.3% extrapolating the under-sampled benign-minor bucket) |

Mechanical-classifier precision was only 42.5% (LLM verification was essential); the mechanical "benign" buckets hid ~8% harmful (sampled), included in the extrapolation.

## 3. The "answers my question / random trailing yes" verdict

It is **two separate bugs**:

**3a. "Answers the question" — LLM-side, already fixed by the Feb-14 guardrail prompts, now regression-locked.**
8 confirmed cases, **all legacy-era, zero in the live era**. Sub-patterns (catalog): `no-transcript-meta-response` ×3 (the model typed "You have not provided the raw speech transcript" into the user's document), `question-answered-with-report` ×2 (fabricated research reports with invented facts), `request-turned-assistant-reply`, `question-converted-to-assistant-intent` ("Can you do research" → "I can do research"), `system-prompt-echoed-as-answer`. The commit `05e0446` (2026-02-14, GPT-OSS switch + "NEVER answer questions" rules) eliminated the class. E.2 adds two independent backstops so it can never return silently: harness probes A1–A4/I1/K2 + the post-cleanup sanity guard (`meta-response`, `answer-lead`, `length-explosion`, `low-overlap` tripwires → raw-text fallback).

**3b. "Random trailing yes/okay" — Whisper-side (raw), fixed in `StripTrailingArtifacts`.**
The ack is already in `rawText` before the LLM runs: 5 raw `…? Yes.` / `…? Okay.` cases + 7 trailing thank-you variants across the corpus, including one live-era case from 2026-06-23. Whisper hallucinates a one-word answer to the speaker's own question out of trailing silence/breath — which reads exactly like "it answered my question." Fix: strip a single trailing ack (`Yes|Yeah|Yep|No|Nope|Sure|Okay|OK`) **only when it directly follows a terminal `?`** (evidence-shaped, conservative: acks after statements are left alone — 3 corpus cases were plausibly spoken). PS port synced; unit tests strip-01..08; committed corpus tripwire `spont-trailing-silence.wav` (any single appended ack word ⇒ WER 0.125 > 0.1 ⇒ suite fails).

## 4. Harmful-pattern catalog → disposition (each class: probe + fix, or accepted-with-reason)

| Class (count, confirmed) | Era | Fix | Probe |
|---|---|---|---|
| answered-question family (8) | legacy only | prompts (already) + sanity guard | A1–A4, I1, K2 |
| injected-trailing-ack (1 cleaned-side + 5 raw-side) | both | raw: artifact stripper; LLM: prompt rule + guard | B1–B3, strip-01/02, spont-trailing-silence |
| hedge-stripping / certainty-shift (~15) | mostly live | prompt FORBIDDEN rule (hedge list, verbatim) | C1–C2, spont-hedges, harness hedge assertions |
| dropped-content (43: leading sentences, embedded questions, clauses) | both | prompt no-summarize/no-merge rule + guard `over-deletion`/`question-lost` | D1–D2, LC corpus |
| pronoun/perspective swap (~4) | both | prompt rule (kept from old prompt, strengthened) | E1 |
| tense-shift (1) | live | new prompt rule | F1 |
| gap-fill invention on garbled speech (~6) | both | prompt "never guess at garbled speech" | G1–G2 |
| format defects: markdown/quotes (2) | legacy | prompt + guard `format-scaffold` | H1 |
| special typography (NBSP, U+2011 — the mojibake fuel) | live (harness-discovered) | new prompt rule: plain keyboard characters only | J3 |
| false-start resolved to wrong side (1, harness-discovered) | live | prompt: "the LATER phrasing wins" | J2 |
| email-scaffold (legacy Email-mode formatting) | legacy | **accepted**: that is Email mode doing its job | M1 bounds it |
| encoding-corruption (18) | legacy | **accepted/resolved**: T1.5 writer fix; not a cleanup bug | n/a |
| benign-rephrase grey zone (62) | both | minimal-edit prompt shrinks it; not harm | ratio assertions |

## 5. Before/after (the bar was "perfect cleanup every time")

Harness = `tests/cleanup/` : 24 synthetic probes (one per class, committable) + 44 gitignored real-dictation probes (the live era's worst raws), assertions mechanical (no LLM judging).

| Corpus | Old prompts (temp 0.3) | New prompts (temp 0.3) |
|---|---|---|
| 24 synthetic | 21/24 | **24/24** |
| 44 real worst-case raws | 20/44 (55% fail) | **41–44/44 per run** |

Residual (honest): 0–3 single-sample failures per run on the real corpus, stochastic, all minor-severity — a single hedge dropped, or a one-token substitution that is usually a *correction* of a Whisper mishearing (e.g. "Crew Crab" → "Crew Cab"). No answered questions, no injected acks, no meta-responses, no content fabrication, no large deletions in any post-fix run. The sanity guard additionally hard-stops every egregious class at runtime (raw-text fallback — a wrong cleanup can no longer beat the raw transcript). **Temperature measured 0.0 vs 0.3 on the full corpus: no improvement at 0.0 (63/68 vs 65/68); payload keeps 0.3.**

## 6. What shipped (branch `audit/E.2-transcription-lab`)

1. **All 4 mode prompts rewritten** (minimal-edit contract + FORBIDDEN list per catalog class) in **both** `GetDefaultModes()` copies, generated from one source of truth: `tests/cleanup/tools/set-mode-prompts.mjs` (`--check` = drift gate). Also fixes the old Code-mode `C:\\` double-backslash artifact.
2. **`lib/cleanup-guard.ahk`** — post-cleanup sanity guard at both call sites (8 tripwires → raw fallback).
3. **`lib/artifact-filter.ahk`** — `IsWhisperHallucination` + `StripTrailingArtifacts` extracted from QuickSay.ahk (tests exercise the real code) + the ack-after-question rule; PS port synced.
4. **Built-in prompt migration**: `builtIn` mode prompts always resolve from compiled-in defaults (`ResolveModePrompt` engine-side, `NormalizeBuiltInModes` settings-side). Saves normalize stale built-ins instead of rejecting them (the old S-13 check would have permanently blocked mode-saving for users carrying pre-E.2 prompt snapshots — found and fixed here). Custom modes keep their prompts untouched.
5. **Whisper dictionary biasing** (`lib/whisper-bias.ahk`): natural-sentence prompt from dictionary written-forms, 600-char cap, **live-dictation path only** + `IsBiasPromptEcho` no-speech filter. Measured on T2.6: bare glossary format echoed verbatim on silence (would have been typed!) and blew long-2min WER 1.2%→18.5%; sentence format keeps jargon wins (Quicksay→QuickSay, Grok→Groq, TailScale→Tailscale) but still degrades long-form (→6.5%), so the file-transcription path stays unbiased. Dictionary regexes remain the deterministic backstop on both paths. AHK v2 gotchas logged: Maps enumerate **sorted, not insertion-ordered**; unassigned globals referenced by an included lib throw a load-time warning *dialog* (invisible under hidden windows — looks like a hang).
6. **Dogfood instrumentation**: `FlagNewestHistoryEntry()` in history-core (+3 tests) + tray "⚑ Flag Last Transcription"; `saveAudioRecordings=1`, `keepLastRecordings=100` flipped on the user's machine (backup kept; defaults unchanged) and hot-reloaded via 0x5555. Loop documented in `Development/docs/dogfood-transcription-lab.md`.
7. **Corpus expansion**: `spontaneous/` tier (question, fillers, restart, hedges, sub-second, trailing-silence) + `jargon/` tier — all synthetic SAPI clips (committable, zero personal data), wired into `expected.json` with measured expectations.

## 7. Full suite status at close

| Suite | Result |
|---|---|
| STT T2.6 + spontaneous + jargon (`tests/transcription`) | **29/29**, no baseline regression (clean 0.0% / accents 2.3% — unchanged) |
| Cleanup LLM harness, synthetic (`tests/cleanup`) | **24/24** |
| Cleanup guard + artifact filter + bias units | **39/39** |
| History incl. flag (`tests/history`) | **22/22** |
| License | 6/6 checks (exit 0) |
| Crash | 36/36 |
| Telemetry | 43/43 |
| Update (signed manifest, fail-closed) | pass (exit 0) |
| Datadir | 26/26 |
| Multimon | 13/13 + clamp unit |
| Dictionary recompile guard | all pass |

(Playwright GUI probes not run — need a built exe + display session; unchanged by this branch. Real-dictation cleanup corpus is gitignored local-only; its latest run: 41/44 with 3 minor-severity stochastic residuals, detailed in §5.)

## 8. Open items / decisions for the user

- **No model-level gap found**: whisper-large-v3-turbo is 0.0% WER on the clean corpus and the residual cleanup issues are LLM-behavioral, not STT-accuracy. No case for a model swap this cycle; revisit only if E.1's battery shows otherwise.
- The residual ~2–5% single-token/hedge stochastic imperfection on worst-case run-on dictations is a **GPT-OSS-20B-at-low-effort ceiling** under prompt-only control. If dogfood flags show it still annoys in practice, the next lever is model/effort (e.g. `reasoning_effort: medium` or a stronger cleanup model) — a cost/latency decision, deliberately not taken unilaterally here.
- Legacy 1.6 GB file: safe to archive/delete after the E-series (nothing reads it). User call.
- Dogfood habit (one line): **dictate normally; tray → "⚑ Flag Last Transcription" whenever output is imperfect.** E.3 harvests the flags (needs the E.2 build installed for the flag item; audio+raw/cleaned capture is already live on 1.9.0-beta).
