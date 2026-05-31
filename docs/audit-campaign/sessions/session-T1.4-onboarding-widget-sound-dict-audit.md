# Session T1.4 — Onboarding + Widget + Sound + Dictionary Audit (READ-ONLY)

> **Model:** Sonnet 4.6
> **Effort:** high
> **Switch commands:** `/model sonnet` then `/effort high`
> **Branch:** `audit/T1.4-onboarding-widget-sound-dict`
> **Parallel-safe with:** T1.1, T1.2, T1.3 (different files, all read-only audits — open all four windows at once)
> **Depends on:** P0.2 (test harnesses + baseline — you drive the Playwright/CDP harness against the onboarding wizard)
> **Blocks:** — (this is a leaf audit; its findings feed T1.7 for any a11y/widget fixes and T1.5 has no dependency on it)
>
> Before pasting: confirm `/model sonnet` and `/effort high`. **Sonnet 4.6 has a 200K context window.** This audit spans several files plus Playwright output — if your context tightens, split into TWO passes (UI files first: onboarding + widget; then a fresh pass for sound + dictionary) rather than escalating to Opus. The split point is called out explicitly in Phase 2. Read-only: the deliverable is a findings doc, no code changes.

---

## Prompt to paste

You are performing a comprehensive, **read-only** audit of QuickSay's first-run experience and three supporting subsystems: the onboarding wizard, the floating recording widget, the sound-theme system, and the custom dictionary engine. **Make ZERO code changes this session.** The deliverable is a findings document with file:line citations and evidence. Fixes happen in later sessions (mostly T1.7 for a11y/widget polish).

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2). On fresh install, a first-run wizard (`onboarding_ui.ahk`, a separate `QuickSay-Setup.exe` binary) walks the user through API-key entry and a mic test. At runtime, an optional floating widget (`widget-overlay.ahk`) offers click-to-record. Six sound themes play feedback on record start/stop/error. A custom dictionary applies spoken→written replacements via a compiled regex.

Working directory: `C:\QuickSay\Development\`.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — architecture; the Process Model (`QuickSay-Setup.exe` is the onboarding binary), the Sound Theme System (CLAUDE.md says **6 themes**: bloom, click, crystal, mechanical, neon, subtle), the Dictionary System (`DictCompiledPattern`, import formats), the WebView2 pattern, the `UX Priorities` "Dad Test" section.
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign context; you update the Status Tracker at the end.
3. `docs/audit-campaign/findings/P0.2-baseline.md` — the verified baseline, including the **resolved sound-theme count** (the surface inventory claimed 7 with `default`+`silent`; CLAUDE.md and the `sounds/` dir say 6 — P0.2 settled it; use its number) and how to run the Playwright/CDP harness against the onboarding wizard.
4. `docs/audit-campaign/research/app-surface-inventory.md` — Category 3 (hotkey/widget), Category 4 (sounds), the Dictionary tab notes. Treat as a starting map to verify.
5. `docs/audit-campaign/research/tooling-research.md` — §2 (Playwright/CDP for the onboarding WebView2 UI).

### Scope

| File / dir | Priority | Why |
|---|---|---|
| `onboarding_ui.ahk` | **CRITICAL** | The first-run wizard back end (WebView2 host, step state, API-key test, mic test). |
| `gui/onboarding.html` | **CRITICAL** | The wizard front end (step nav, inputs, mic-test UI, the postMessage bridge). |
| `widget-overlay.ahk` | **HIGH** | The 44×44 floating click-to-record widget. Drag-vs-click detection, position persistence, multi-monitor edges. |
| `sounds/` | **MEDIUM** | The sound-theme directories + their WAV files. Presence + audibility per theme/event. |
| Dictionary engine in `QuickSay.ahk` | **HIGH** | `LoadDictionary()`, `ParseDictionaryJson()`, `CompileDictionaryPattern()`, `ApplyDictionary()`, `AddToDictionary()`. ReDoS + import/export safety. (You read ONLY the dictionary functions in `QuickSay.ahk`, not the rest of the engine.) |

**Forbidden** (owned by sibling sessions — do not audit, do not touch):
- The rest of `QuickSay.ahk` (recording/transcription/typing engine, timers, IPC) → T1.1. You read ONLY the dictionary functions, cited as such.
- `lib/settings-ui.ahk`, `gui/settings.html`, `gui/settings.css` → T1.2. (The settings **Dictionary tab UI** is T1.2's; the dictionary **compile/apply engine** in `QuickSay.ahk` is yours. Be precise about the boundary.)
- `setup.iss`, `release.ps1`, `signing/` → T1.3.

### Known concrete anchors (verify, don't trust)

From a prior read:
- `sounds/` on disk contains **6 theme dirs** — `bloom`, `click`, `crystal`, `mechanical`, `neon`, `subtle` — each with `start.wav`, `stop.wav`, `error.wav` (18 files). Confirm against P0.2's resolved count.
- Dictionary engine in `QuickSay.ahk`: `LoadDictionary()` at ~`:1538`, `ParseDictionaryJson()` at ~`:1675`, `ApplyDictionary()` at ~`:1997`, `CompileDictionaryPattern()` at ~`:2028`. The compiled pattern is built at ~`:2046` as `"i)\b(" . StrJoin(patterns, "|") . ")\b"` (case-insensitive, word-boundary-anchored alternation). `AddToDictionary()` is invoked from the "Dictionary Learning" flow around `:2572`.
- Widget click-vs-drag state machine in `widget-overlay.ahk`: `static isDragging`, `static wasClick`, `dragStartWinX/Y` (~`:16`–`:22`); `WM_LBUTTONDOWN` handler registered at ~`:113`; mousedown records position + sets `wasClick:=true` (~`:288`); mouseup branches on `wasClick` (toggle record) vs `isDragging` (save position) (~`:312`–`:325`); the **5px drag threshold** that flips `wasClick→false` is at ~`:341`. **This threshold is the prior fix for "accidental recording on drag" — verify it still holds.**

Re-read fresh and confirm — line numbers may have shifted.

### Phase 1 — Map the four subsystems (deep read)

Invoke `superpowers:systematic-debugging`.

Produce a line-cited map of each subsystem and present it before findings:

1. **Onboarding wizard** — the step graph (how many steps, how nav advances/reverses), the API-key entry + test action, the mic-test action, the WebView2 postMessage bridge (which actions the HTML sends, which the AHK handles), and how it writes the `onboarding_done` marker / `tourCompleted`.
2. **Widget** — the full click-vs-drag state machine, the WM_ message handlers, where `widgetX`/`widgetY` persist, and how the widget computes its on-screen position.
3. **Sounds** — the theme→file resolution (`soundTheme` config → `sounds/<theme>/<event>.wav`), the play call, and the `playSounds` gate.
4. **Dictionary** — `LoadDictionary` → `ParseDictionaryJson` → `CompileDictionaryPattern` → `ApplyDictionary`, plus import/export and `AddToDictionary`.

### Phase 2 — Findings categories

For EVERY finding: ID (`T1.4-001`, …), severity (P0/P1/P2/P3), file:line, evidence snippet, recommended fix, owner-session tag (`owned by T1.7` / `owned by T1.4-followup`). Every bullet gets a finding or an explicit "no issue — here's the evidence." No hand-waving.

> **CONTEXT SPLIT POINT:** Categories A–B (onboarding + widget) read the two largest files. Categories C–D (sound + dictionary) are separate. If your context is tightening after Phase 1 + Categories A–B, **commit your partial findings, clear context, and start a second pass** for C–D against a fresh read. Do NOT escalate to Opus — the split keeps you in Sonnet's 200K budget. Note the split in your findings doc so it reads as one coherent document.

#### Category A — Onboarding wizard

- [ ] **Step navigation.** Can the user get stuck (a step with no working Next/Back)? Does Back preserve entered data? Does closing mid-wizard leave a half-configured state? Trace each step transition.
- [ ] **API-key test.** The wizard tests the entered Groq key. Trace it: does it actually hit the Groq API (or just format-check)? What does the user see on success / wrong key / network down / rate-limited? Per the "Dad Test" (CLAUDE.md UX Priorities), is the error recovery clear and jargon-free, or does it say "401 invalid_api_key"? Flag jargon as a P2 UX finding tagged for T1.7.
- [ ] **Mic test.** The mic test confirms audio capture. Does it work with the default device AND a named device (FFmpeg path)? What happens with no mic, a muted mic, or a busy mic? Does it give actionable feedback or hang?
- [ ] **API-key storage.** Confirm the key entered in onboarding is stored DPAPI-encrypted (never plaintext), same as the settings path. Cite the encryption call. Flag if the key is ever written plaintext, logged, or passed in a way the debug log could capture.
- [ ] **Completion + idempotency.** Does finishing write `onboarding_done` correctly so the wizard never re-fires? What if `onboarding_done` exists but config is incomplete (partial prior run)? Does re-running the wizard manually work?
- [ ] **Bridge robustness.** Same WebView2 dispatcher concerns as T1.2 but for the onboarding HTML: unknown/malformed action handling, dead actions, dead handlers. Injection surface on any key/URL field.

#### Category B — Widget drag/click edge cases

- [ ] **Accidental-recording-on-drag (the prior fix — verify it held).** The 5px threshold at ~`widget-overlay.ahk:341` flips `wasClick→false` once the pointer moves past 5px, so a drag does NOT trigger a recording. Confirm the logic is intact and the threshold is sensible. Test with the live runner (P0.2): grab the widget and nudge it 2px (should still click-record) vs 10px (should drag, not record). Flag any regression as P1.
- [ ] **Click vs drag boundary.** Is 5px the right threshold? A jittery hand or high-DPI display could exceed it on an intended click. Reason about DPI scaling — is the threshold in physical pixels or DIPs? Document.
- [ ] **Position persistence.** `widgetX`/`widgetY` save on drag-end. What if the saved position is off-screen (monitor disconnected, resolution changed)? Does the widget clamp back on-screen, or vanish? (Multi-monitor edge — cross-ref T1.7 which owns multi-monitor; cite and tag.)
- [ ] **Mouse-capture hygiene.** The widget uses manual mouse capture (`SetCapture`-style, per the comment at ~`:299`) to avoid the system modal loop stealing focus. Confirm capture is ALWAYS released on mouseup, even on error/edge paths — a stuck capture freezes the whole desktop's mouse. This is a potential P0. Trace every exit from the capture state.
- [ ] **Focus stealing.** The comment says click "toggle recording (focus stays on previous window)." Verify the widget never steals focus from the target app — if it did, the transcript would paste into the widget's owner, not the user's app. Confirm `WS_EX_NOACTIVATE` (or equivalent) is set.
- [ ] **Show/hide gate.** `showWidget` config (default 0). Confirm the widget only exists when enabled, and toggling it off cleanly destroys it (no leaked GDI/window handle).

#### Category C — Sound themes (all 6 × 3 events present + audible)

- [ ] **Completeness.** For each of the 6 themes (per P0.2's resolved count), confirm all 3 event files exist: `start.wav`, `stop.wav`, `error.wav` (18 files total). List any missing file as a P1 (a missing sound = silent failure for that user).
- [ ] **Audibility / validity.** Spot-check that the WAVs are real, playable audio (non-zero size, valid WAV header) — not empty or corrupt placeholders. Play a sample of them via the live runner or directly. Flag any silent/corrupt file.
- [ ] **Resolution + fallback.** Trace `soundTheme` config → file path. What happens if `soundTheme` names a theme dir that doesn't exist (typo, removed theme, the legacy `default`/`silent` names the surface inventory mentioned)? Does it fall back gracefully or throw / play nothing silently? Cite the resolution code.
- [ ] **`playSounds` gate + theme switch.** Confirm `playSounds=0` mutes all events. Confirm switching `soundTheme` takes effect without restart (or document that it needs a `0x5555` reload — cross-ref T1.2). Confirm `previewSound` (the settings action) maps to the right file.
- [ ] **No blocking play.** Does sound playback block the hot path (record-start latency)? Sounds should play async. Flag if a sync play call sits on the path between hotkey-press and recording-start.

#### Category D — Dictionary regex safety + round-trip

- [ ] **ReDoS / compile-time blowup.** The pattern is `"i)\b(" . StrJoin(patterns, "|") . ")\b"` (~`:2046`). User-supplied "spoken" terms are concatenated into a single alternation. Reason about: (1) Are the user terms regex-**escaped** before being joined? If a user enters `a.*b` or `(((` as a spoken term, does it become a live regex metacharacter (injection) or is it escaped to a literal? This is the central finding of this category — trace whether `CompileDictionaryPattern` escapes each term. **If terms are NOT escaped, that is a P1: a crafted dictionary entry could ReDoS the hot path or break the compile.** (2) Upper bound: how many entries before compile time or per-transcription match time becomes noticeable? Estimate and document.
- [ ] **Match correctness.** The `\b…\b` word-boundary anchoring + `i)` case-insensitive flag. Does it handle multi-word spoken phrases ("for example" → "e.g.")? Does `\b` behave for terms starting/ending in non-word characters (numbers, punctuation, Unicode accented letters)? Flag any class of entry that silently never matches.
- [ ] **Import/export round-trip.** CLAUDE.md says two import formats: array of `{spoken, written}` objects, and a legacy corrections block. Trace `ParseDictionaryJson` for both. Then: export a dictionary, re-import it — is it lossless? Does import validate (reject malformed JSON, dedupe, cap size)? Does a malformed import file crash `LoadDictionary` or degrade gracefully (CLAUDE.md shows a `try` around the read at ~`:1543` — confirm it catches parse failures and falls back to an empty `Map()`)?
- [ ] **`AddToDictionary` (Dictionary Learning).** The learning flow (~`:2572`) adds corrections. Does it use `AtomicWriteFile()` + the config mutex when writing `dictionary.json`? (Cross-ref the file-safety concern; cite.) Does it re-compile the pattern after adding? Could a rapid add race the compile?
- [ ] **Empty / disabled.** `dictionary_enabled=false` (the gate at ~`:2000`) — confirm `ApplyDictionary` short-circuits and returns text unchanged. Confirm an empty dictionary doesn't build a broken `\b()\b` empty-group pattern.

### Phase 3 — Live verification

Use the P0.2 harnesses.

- **Onboarding (Playwright/CDP):** Launch the wizard via the harness (`node tests/playwright/run.mjs onboarding`). Walk the steps via Playwright: enter a bad API key (observe the error), enter a (test) good key (observe success), trigger the mic test (observe feedback). Screenshot each step for the findings doc. Verify the bridge actions fire.
- **Widget (live-runner.ps1):** With QuickSay running, enable `showWidget`, then test the 2px-nudge (click) vs 10px-drag (no record) behavior described in Category B. Confirm position persists and the widget stays on-screen.
- **Sounds:** Play one event from each theme (via `previewSound` through the harness, or directly) and confirm audible + correct.
- **Dictionary:** Add an entry with a regex metacharacter (e.g. spoken term `c++`) and confirm whether it is escaped (matches literally) or breaks the compile. This single test settles the ReDoS/injection finding.

For each suspected bug, write the smallest reproduction recipe.

### Done When

The following are all true. Do not declare complete without verifying each.

- [ ] `docs/audit-campaign/findings/T1.4-onboarding-widget-sound-dict.md` written. Each finding has: ID, severity, file:line, evidence, recommended fix, owner-session tag.
- [ ] The four subsystem maps are at the top of the doc.
- [ ] Every Category A–D bullet has a finding or an explicit "no issue — here's the evidence."
- [ ] The **accidental-recording-on-drag** fix is explicitly confirmed-still-holding (or flagged as regressed) with the 2px/10px live test result.
- [ ] The **mouse-capture-release** invariant is verified (no path leaves capture stuck) — this is a potential P0.
- [ ] All **6 themes × 3 events = 18 sound files** confirmed present + audible (or missing/corrupt files flagged).
- [ ] The **dictionary regex-escape question** is answered definitively (escaped → safe, or not-escaped → P1 ReDoS/injection) with the `c++` test result.
- [ ] The onboarding **API-key DPAPI storage** is confirmed (never plaintext/logged).
- [ ] a11y / multi-monitor / UX-jargon findings tagged `owned by T1.7`.
- [ ] If you split into two passes, the doc reads as one coherent document and notes the split.
- [ ] **Zero changes to source.** `git diff` shows only the new findings file.
- [ ] MASTER-PLAN.md Status Tracker updated: T1.4 → ✅ done, with total finding count + P0/P1 count.
- [ ] Branch `audit/T1.4-onboarding-widget-sound-dict` committed. Title: `T1.4 — Onboarding + widget + sound + dictionary audit (N total, N P0, N P1)`. PR opened against `main`.

### What NOT to do

- ❌ Do not modify any source file. Read-only. Recommend fixes; do not write them.
- ❌ Do not audit the rest of `QuickSay.ahk` — ONLY the dictionary functions. The recording/transcription engine is T1.1.
- ❌ Do not audit the settings Dictionary *tab UI* (`gui/settings.html`) — that is T1.2. You own the *engine* in `QuickSay.ahk`. Respect the boundary.
- ❌ Do not escalate to Opus if context tightens — split into two passes (UI files, then sound/dict) per the Phase 2 split point.
- ❌ Do not fix a11y/multi-monitor/jargon findings — locate and tag `owned by T1.7`.
- ❌ Do not modify any sound WAV files or the dictionary file. Verifying audibility is read/play only.
- ❌ Do not add a "Clear all recordings" button or any widget feature — leaf audit, no features.
- ❌ Do not skip the `c++`-style dictionary escape test — it is the one test that settles the ReDoS/injection finding.

### Estimated time

Phase 1 (mapping): ~30-45 min. Phase 2 (Categories A–D, possibly two passes): ~60-90 min. Phase 3 (live verification): ~30-45 min. **Total wall-clock: ~2.5-3 hours** (add ~30 min if you split into two passes).

### When you're done

Report back with:
- Total finding count, P0 count, P1 count.
- Whether the accidental-recording-on-drag fix held (yes/regressed + the 2px/10px result).
- Whether the mouse-capture is always released (the potential-P0 verdict).
- The 18-sound-file completeness result (all present + audible, or what's missing/corrupt).
- The dictionary-escape verdict in one sentence (escaped = safe, or not-escaped = P1 with the `c++` evidence).
- Whether you split into two passes (and if so, where).
- Any cross-session dependency discovered (especially anything T1.7 must coordinate).
- Confirmation MASTER-PLAN.md Status Tracker is updated and the PR is open.
