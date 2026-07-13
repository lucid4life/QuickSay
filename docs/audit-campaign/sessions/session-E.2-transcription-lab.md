# Session E.2 — Transcription Quality Lab (history mining → cleanup fix → dictionary biasing → instrumentation)

> **Model:** Opus 4.8 (Fable 5 acceptable)
> **Effort:** xhigh — this touches the dictation hot path, the product's core. (Ultracode optional: it only adds value in Phase 1 if the divergent-pair set is large enough to fan out classification via Workflow; xhigh alone is fine otherwise.)
> **Switch commands:** `/model claude-opus-4-8` then `/effort xhigh`
> **Branch:** `audit/E.2-transcription-lab` (Development repo, off `audit/M.1-integration`)
> **Parallel-safe with:** E.1 (E.1 touches no code). NOT parallel with E.3/E.4 (shared `QuickSay.ahk`).
> **Depends on:** nothing hard; E.1's battery results enrich Phase 5 if available
> **Blocks:** E.3 (serial — shared files), E.5 (rc2 rebuild)
>
> **This is the highest-value session of the E-series.** The user's #1 complaint: "sometimes the transcriptions aren't perfect… if I'm asking a question, it will answer the question… every once in a while it'll just add a random yes at the end."

---

## Prompt to paste

You are running QuickSay's transcription quality lab: mine the user's real dictation history for error patterns, root-cause and fix the "answers my question / random trailing yes" bug, wire the custom dictionary into Whisper's biasing prompt, harden the LLM cleanup prompts, and instrument the app so ongoing dogfooding captures every future imperfect transcription as a test case. Work test-first where a harness exists; measure before/after.

### Evidence already in hand (verified 2026-07-13 — build on it, don't re-derive)

- **History stores BOTH `rawText` (Whisper output) and `cleanedText` (post-LLM)** per entry, plus `appContext`, `duration`, `timestamp`, `wordCount`, `audioFile`, `hotkey`, `id`. This means raw-vs-cleaned diffing over the full history needs NO new instrumentation.
- **Live history:** `%APPDATA%\QuickSay\data\history.json` (~732 KB, actively written). **Legacy goldmine:** `%LOCALAPPDATA%\Programs\QuickSay Beta\data\history.json` (**1.6 GB** — the pre-T1.5 unbounded file; stream/sample it, NEVER load whole). Feb-era WAVs exist in `%APPDATA%\QuickSay\data\audio\` (~24 MB); recent entries have `audioFile: ""` (saveRecordings defaults false since T1.1-023 fix).
- **Cleanup call sites:** `QuickSay.ahk:1228` and `QuickSay.ahk:3347` (duplicated tray/settings paths — consolidation candidate). Payload: `gpt-oss-20b`, `temperature 0.3`, `reasoning_effort low`, system = active mode prompt, user = `<transcript>…</transcript>`.
- **Mode prompts live in `GetDefaultModes()` in BOTH `QuickSay.ahk` AND `lib/settings-ui.ahk`** — the dual-sync rule (CLAUDE.md) applies to every prompt edit.
- **The Whisper transcription call sends NO `prompt` parameter** — the custom dictionary only regex-corrects AFTER transcription. Biasing the model BEFORE is an open quick win (`lib/http.ahk` `HttpPostFile()` will need an extra multipart field).
- Hallucination defenses exist: `IsWhisperHallucination()` + `StripTrailingArtifacts()` in `QuickSay.ahk`, with a PowerShell port in `tests/transcription/lib/hallucination.ps1` that **must stay in sync**.
- T2.6 regression corpus: 20 clips, WER clean 0.0% / accents 2.3% — clean READ speech only. Real-world spontaneous speech is the uncovered class.

### Privacy rules (hard)
- History content is the user's personal dictation. The user explicitly authorized full-history analysis (2026-07-13), which includes Claude/agents reading entries in-session (Anthropic API) and re-running his own text/clips through Groq (same trust boundary as normal app use). **Nothing goes to any other third party**, and never commit raw history excerpts to git; corpus clips derived from his data need his explicit per-clip approval before entering the repo (or keep a gitignored local corpus dir).

### Phase 1 — Mine the ENTIRE history (user mandate 2026-07-13: full analysis, every entry ever recorded)

The user explicitly wants a **complete** pass over all dictation history — the stated bar is **"perfect cleanup every time."** Not a sample: the FULL live history AND the FULL 1.6 GB legacy file (streamed/chunked parsing — it's a JSON array; never load it whole; dedupe any overlap between legacy and live by entry `id`/timestamp).

Write a local analysis script (scratchpad or `tests/transcription/tools/`, PowerShell or Node) that:
1. Streams **every entry** from both files and emits every `rawText != cleanedText` divergence.
2. Mechanically pre-classifies what it can (pure-deletion of known fillers = benign; token-injection detection; length-ratio outliers), then **LLM-classify the remaining divergent set**: **benign** (fillers removed, punctuation) vs **harmful** — (a) cleanup ANSWERED the transcript (question in, answer out), (b) injected tokens absent from raw (the "random yes" — check specifically for sentence-final `yes/no/sure/okay` in cleaned but not raw), (c) dropped meaningful content, (d) meaning changed. If the divergent set runs to thousands of pairs, fan the classification out with the Workflow tool (batches of ~50 pairs per agent, adversarial spot-check on a sample of each class).
3. Quantifies: harmful-cleanup rate overall, per mode, per era (legacy vs current build); a **named catalog of every harmful pattern class found** — this catalog is the contract for Phase 2 (each class must get a probe in the cleanup harness and be fixed or explicitly accepted).
4. Separately catalogs raw-side weirdness across the full corpus: trailing artifacts, repeated-token loops, hallucinated boilerplate in `rawText` itself (Whisper-side — routes to filter tuning, not prompt fixes).
Deliver the numbers + the pattern catalog to the user before touching prompts — this is the baseline the fix must beat. **Disambiguate the "random yes":** cleaned-only → LLM guilt (Phase 2); raw-side → hallucination filter (also Phase 2, different fix).

### Phase 2 — Fix the cleanup stage

1. Build a **cleanup regression harness** (`tests/cleanup/`): feeds recorded raw texts (from Phase 1's harmful set + synthetic probes: questions, imperatives, "should I…?") through the real Groq cleanup call per mode, asserts the output never answers/appends/injects. Red first against current prompts.
2. Rewrite the 4 mode prompts (Standard/Email/Code/Casual) with explicit guardrails: you are a TEXT EDITOR not an assistant; never answer questions in the transcript; never add words not spoken (except punctuation); output ONLY the cleaned transcript; preserve meaning verbatim. Consider `temperature 0.3 → 0.0` (measure — determinism helps tests too).
3. Add a **cheap post-cleanup sanity guard** in code: if cleaned output looks like an answer (e.g., length ratio wildly off, or starts with `Yes,/No,/Sure` when raw didn't) → fall back to `rawText` (with dictionary regex still applied). A wrong cleanup must never beat a raw transcript.
4. **Update BOTH `GetDefaultModes()` copies** (QuickSay.ahk + lib/settings-ui.ahk). Note: users with saved custom modes keep old prompts — decide + document migration (recommend: only replace prompts that byte-match the old defaults).
5. If Phase 1 showed raw-side trailing artifacts: extend `StripTrailingArtifacts()`/`IsWhisperHallucination()` conservatively + sync the PowerShell port + T2.6 corpus tests.

### Phase 3 — Dictionary → Whisper biasing prompt

1. Extend `HttpPostFile()` (lib/http.ahk) to accept extra form fields; send `prompt` on the transcription POST built from custom-dictionary terms (Whisper prompt budget ≈ 224 tokens — cap + truncate oldest; document ordering). Both call paths (tray + onboarding test if applicable).
2. Verify with jargon tests (dictionary term spoken → correctly transcribed pre-regex). Confirm no regression on T2.6 corpus (biasing must not distort normal speech — run full suite).

### Phase 4 — Dogfood instrumentation

1. Flip `saveRecordings` ON for the dogfood window (rotation is safe post-T1.5) so future bad transcriptions have paired audio.
2. Add a **"⚑ Flag last transcription"** affordance (tray menu item; optional hotkey) that marks the newest history entry `"flagged": true` — every annoyance becomes a captured test case. Keep it dumb and safe (history-core mutation under the existing mutex).
3. Confirm raw/cleaned/audio triples land for flagged entries; document the dogfood loop for the user (dictate normally; flag anything imperfect; E.3/E.5 harvest flags).

### Phase 5 — Corpus expansion + before/after

1. Add a **spontaneous-speech tier** to `tests/transcription/`: questions, fillers/restarts, jargon, sub-second, trailing-silence (synthetic or user-approved clips; gitignore anything personal).
2. Re-run: T2.6 full corpus (no WER regression), new cleanup harness (green), history-mining script over post-fix dogfood output when available.
3. Findings doc `C:\QuickSay\docs\audit-campaign\findings\E.2-transcription-lab.md`: baseline harmful-rate vs post-fix, root cause of the "yes" bug with evidence, what changed, corpus deltas.

### Done When
- [ ] **Full-corpus** harmful-cleanup rate measured and reported (entire live + entire legacy history), with the named harmful-pattern catalog.
- [ ] **Every harmful pattern class in the catalog** has a failing-then-passing probe in the cleanup harness (fixed) or an explicit accepted-with-reason note.
- [ ] "Answers the question" and "random trailing yes" root-caused with evidence, reproduced in a failing test, then fixed (prompts + sanity guard) — harness green.
- [ ] Both `GetDefaultModes()` copies updated in sync; custom-mode migration decided + implemented.
- [ ] Dictionary terms bias Whisper via `prompt` param; T2.6 suite still 20/20, no WER regression.
- [ ] Flag-last-transcription instrumentation shipped; saveRecordings on for dogfood; loop documented for the user.
- [ ] Spontaneous-speech corpus tier added; all suites green (history 19, license, crash, telemetry, update, cleanup NEW).
- [ ] Findings committed (root repo docs branch); code on `audit/E.2-transcription-lab` + PR; MASTER-PLAN → E.2 ✅.

### What NOT to do
- ❌ Never load the 1.6 GB legacy file into memory whole — stream/sample.
- ❌ No raw history content in commits, findings, or any external service beyond Groq.
- ❌ Don't edit one `GetDefaultModes()` without the other (CLAUDE.md dual-sync).
- ❌ Don't let cleanup fixes regress the hallucination filter or T2.6 baselines — run everything.
- ❌ Don't redesign the pipeline (no streaming/model swap here) — that's out of scope unless E.1's battery proves a model-level accuracy gap; if so, propose it in findings for a decision, don't just do it.

### Estimated time
Phase 1: ~2.5–3 h (full corpus). Phase 2: ~2 h. Phase 3: ~1.5 h. Phase 4: ~1 h. Phase 5: ~1.5 h. **Total: ~8–9 h (one long session or split after Phase 2).**

### When you're done, report back with
- Baseline vs post-fix harmful-cleanup numbers; the "yes" bug verdict (LLM vs Whisper) with the evidence.
- What the user should do during dogfooding (one line).
- Any model-level gap that needs a decision (e.g., whisper-large-v3 vs turbo).
