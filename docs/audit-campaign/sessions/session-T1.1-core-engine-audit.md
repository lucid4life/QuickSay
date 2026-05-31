# Session T1.1 — Core Engine Audit (READ-ONLY)

> **Model:** Opus 4.7 [1m]
> **Effort:** xhigh
> **Switch commands:** `/model opus[1m]` then `/effort xhigh`
> **Branch:** `audit/T1.1-core-engine`
> **Parallel-safe with:** T1.2, T1.3, T1.4 (different files, all read-only)
> **Depends on:** P0.2 (test harnesses + baseline)
> **Blocks:** T1.5 (history fix needs these findings)
>
> Before pasting this prompt: confirm your effort is `xhigh` (`/effort xhigh`) and your model is Opus 4.7 with 1M context (`/model opus[1m]`). If you skip either, the audit will be shallower than the campaign requires.

---

## Prompt to paste

You are performing a comprehensive, read-only audit of QuickSay's core engine — the recording, transcription, and clipboard-paste pipeline. **Make zero code changes during this session.** The output is a findings document; fixes happen in later sessions.

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2). Hold `Ctrl+Win`, speak, release — transcript types at cursor. Uses Groq Whisper API for transcription and (optionally) Groq GPT-OSS 20B for LLM cleanup. Working directory: `C:\QuickSay\Development\`.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — full project architecture, file map, critical gotchas
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign context
3. `docs/audit-campaign/research/app-surface-inventory.md` — starting inventory (treat as starting point, verify don't trust)
4. `docs/audit-campaign/research/tooling-research.md` — tools you may use

### Scope

| File | Priority | Why |
|---|---|---|
| `QuickSay.ahk` | **CRITICAL** | ~3400 lines. Main engine: tray icon, hotkey, recording loop, transcription, typing. Almost everything that matters is here. |
| `lib/http.ahk` | **HIGH** | HTTP/API layer. Timeouts, retries, UTF-8 handling. |
| `lib/web-overlay.ahk` | **MEDIUM** | GDI+ recording overlay. WASAPI mic level polling. |

**Forbidden** (covered by sibling sessions — do not touch):
- `lib/settings-ui.ahk`, `gui/settings.html`, `gui/settings.css` → T1.2
- `setup.iss`, `release.ps1`, `signing/` → T1.3
- `onboarding_ui.ahk`, `gui/onboarding.html`, `widget-overlay.ahk`, `sounds/`, `dictionary.json` → T1.4

### Phase 1 — Codebase exploration (deep read)

Invoke `superpowers:systematic-debugging` for this phase. Use the Explore subagent for breadth-first mapping where the codebase reads call for it.

Produce a complete mental map of:

1. **Recording pipeline** — `StartRecording()` and everything it calls. Both MCI path and FFmpeg path, separately. Every COM call, every timer, every error handler. Line-number cite everything.
2. **Transcription pipeline** — `StopAndProcess()` → `HttpPostFile()` → hallucination filter → dictionary regex → optional LLM cleanup → clipboard paste. Every step with timing implications.
3. **File I/O surface** — every read/write of: config.json, history.json, statistics.json, dictionary.json, audio/*.wav, debug.txt. Note which use `AtomicWriteFile()` and which acquire the config mutex. Flag any that do neither.
4. **Concurrency model** — every `SetTimer` call with interval and what it does. Every Windows message (`OnMessage` registration + every `PostMessage` call). Identify any callbacks that could collide with active recording.
5. **Hot path** — the milliseconds from hotkey-press to clipboard-paste. List every synchronous operation, every Sleep, every blocking call.

Present this map to me before proceeding to findings.

### Phase 2 — Findings categories

Apply each category below to the code you just mapped. For every finding, produce: severity (P0/P1/P2/P3), file:line citation, evidence (the actual code snippet), and a recommended fix. Be precise. No hand-waving.

#### Category A — Performance (highest priority)

- [ ] All synchronous operations on the hotkey-press → paste hot path. List them in order with estimated wall-clock cost.
- [ ] Is `config.json` re-read during recording? It shouldn't be.
- [ ] Do history/statistics writes block the paste return? They shouldn't.
- [ ] `SetTimer` intervals — any polling too aggressively (>10 Hz unless justified)?
- [ ] WASAPI `IAudioMeterInformation` polling rate in `lib/web-overlay.ahk` — what CPU does it cost?
- [ ] Arrays/maps that grow unbounded (memory leak shape).
- [ ] `history.json` serialization time — does it grow linearly with entry count?
- [ ] Any `Sleep` on the hot path.
- [ ] Verify the historyRetention/keepLastRecordings enforcement is actually wired. The surface inventory flagged it as orphaned. **ultrathink — if it's orphaned, why hasn't anyone noticed for so long? What's the actual failure mode?**

#### Category B — Reliability & error handling

- [ ] Every HTTP call (Groq STT, Groq LLM, version check): handles timeout, network error, invalid JSON, rate limit (429), server error (500)?
- [ ] MCI recording failure: can the app get stuck in "recording" state with no recovery?
- [ ] FFmpeg recording failure: same question — what if process hangs or crashes?
- [ ] Clipboard backup/restore edge cases — could clipboard be lost or corrupted?
- [ ] What happens if `config.json` is locked, corrupted, or deleted mid-operation?
- [ ] What happens if `data/` directory is deleted while running?
- [ ] Max recording size — what happens at 5 minutes with high-quality audio?
- [ ] COM objects (WebView2, WASAPI, MCI) — all released on exit / on error?
- [ ] What happens if the hotkey is held longer than the max-recording auto-stop?
- [ ] What happens if the hotkey is released during HTTP transcription (before paste)?

#### Category C — Security

- [ ] Is the DPAPI-encrypted Groq API key ever logged, written to debug.txt, exposed in error messages, or sent in URL query strings? Trace EVERY place `groqApiKey` is read.
- [ ] FFmpeg command construction — sanitizer (`SanitizeDeviceName`) coverage. Any other shell-command-construction paths? (Confirm blocklist is still complete per the FFmpeg gotcha in CLAUDE.md.)
- [ ] Are temp WAV files cleaned up on error paths, not just success?
- [ ] Any user-controllable input that reaches a `Run` / `RunWait` / shell call without sanitization?
- [ ] HTTP responses — does the JSON parser tolerate malformed responses without crashing or executing string content?

#### Category D — Correctness

- [ ] Hallucination filter (`IsWhisperHallucination`) — false positive risk: does it ever drop legitimate short utterances ("OK.", "No.", "Hi.")?
- [ ] Hallucination filter — false negative risk: any common Whisper hallucinations it still passes through?
- [ ] Custom dictionary regex compilation — any patterns that could ReDoS or just take forever to compile? What's the upper bound on dictionary entries before compile time matters?
- [ ] Voice command parsing — any ambiguity between voice command and literal text?
- [ ] Hotkey hold vs tap behavior — race between the two modes if the user mid-flight changes setting.
- [ ] Hotkey collision with other apps — what happens if Windows snap or another app has captured Ctrl+Win?

#### Category E — Observability

- [ ] When `debugLogging=true`, is every important state transition logged? List what's missing.
- [ ] When `debugLogging=false`, are any logs still being written? They shouldn't be.
- [ ] Are timestamps in debug.txt monotonic and useful for after-the-fact debugging?
- [ ] Is there any way to capture "what was the last error" for a user to send to support?

#### Category F — The 5 suspect items from prior research (confirm or refute)

- [ ] `contextAwareModes` — field exists in config; does any code actually read it and switch modes based on foreground window?
- [ ] `keepLastRecordings` — is cleanup logic wired? Where?
- [ ] STT and LLM models — hardcoded? Confirm exact line numbers.
- [ ] Version string mismatch — `1.9.0-beta` (config) vs `1.9.0.0` (resource). Confirm and locate every divergence. (T1.6 will fix; T1.1 just documents.)
- [ ] `AtomicWriteFile` usage — list every JSON file write in `QuickSay.ahk` and whether it uses atomic writes + the mutex.

### Phase 3 — Live verification

Use the test harness from P0.2 to verify your findings against a running instance where possible. **You may execute QuickSay.ahk under AutoHotkey64.exe** — but you may **NOT** modify the source. Read `data/logs/debug.txt` to confirm assertions.

For each suspected bug, where possible, write the smallest reproduction recipe (just enough that a human can trigger it).

### Done When

The following items are all true. **Do not declare complete without verifying each item.**

- [ ] `docs/audit-campaign/findings/T1.1-core-engine.md` written with all findings categorized A–F. Each finding has: ID (T1.1-001, T1.1-002…), severity, file:line, evidence snippet, recommended fix, sibling-session dependency tag (e.g. "owned by T1.5", "owned by T1.6").
- [ ] Architecture map at the top of the findings doc (recording pipeline + transcription pipeline + file I/O surface + concurrency model + hot path).
- [ ] Every Category A–F bullet has either a finding or an explicit "no issue found, here's the evidence" entry.
- [ ] The 5 suspect items in Category F each have a definitive confirm/refute with line citations.
- [ ] **Zero changes to source files.** `git diff` shows only the new findings file.
- [ ] MASTER-PLAN.md status tracker updated: T1.1 → ✅ done. Note the total finding count and the P0/P1 count.
- [ ] Branch committed: `audit/T1.1-core-engine`. Title: `T1.1 — Core engine audit findings (N total, N P0, N P1)`.
- [ ] PR opened against `main`.

### What NOT to do

- ❌ Do not modify any source file. This is read-only.
- ❌ Do not write a fix. Recommend fixes only — they belong to later sessions.
- ❌ Do not touch the files in the "Forbidden" list.
- ❌ Do not summarize without the architecture map.
- ❌ Do not skip Phase 3 verification just because the read got long. Live verification is the difference between "I think this is broken" and "I confirmed it."

### Estimated time

Phase 1 (mapping): ~30–45 min model time. Phase 2 (findings): ~45–60 min. Phase 3 (verification): ~15–30 min. Total wall-clock: 1.5–2.5 hours.

### When you're done

Report back with: total finding count, P0 count, P1 count, the 3 most important findings in plain English, and any cross-session dependencies discovered (e.g. "T1.5 will need to coordinate with T1.6 because…").
