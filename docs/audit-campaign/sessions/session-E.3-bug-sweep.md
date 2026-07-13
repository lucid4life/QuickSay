# Session E.3 — Targeted Real-World Bug Sweep + Dogfood Harvest

> **Model:** Opus 4.8 (Fable 5 acceptable)
> **Effort:** high
> **Switch commands:** `/model claude-opus-4-8` then `/effort high`
> **Branch:** `audit/E.3-bug-sweep` (Development repo, off E.2's merged tip)
> **Parallel-safe with:** E.1. NOT parallel with E.2/E.4 (shared `QuickSay.ahk` / UI files).
> **Depends on:** E.2 merged (shared files; and this session harvests E.2's flag instrumentation)
> **Blocks:** E.5
>
> Rationale: four read-only audits + ~250 automated tests already ran (2026-05/06). The surviving bug class is **real-world messy usage** — exactly what the silent open beta never exercised. This session hunts those seams deliberately, plus harvests whatever dogfooding flagged.

---

## Prompt to paste

You are hunting the bug class that survives audits: environment transitions, odd target apps, timing races, and messy human usage. Two prongs: (A) harvest the dogfood flags accumulated since E.2, (B) run a targeted exploratory sweep of the riskiest untested seams. Fix what you find with regression tests; document what you can't fix as known-limitations with graceful behavior.

### Read first
1. `C:\QuickSay\CLAUDE.md` + `C:\QuickSay\Development\CLAUDE.md` — architecture, flows.
2. Memory `reference_ahk_headless_testing.md` — **run AHK via the PowerShell tool, NOT Bash** (GUI apps hang under the Bash sandbox); `/ErrorStdOut` syntax-check trick; `tests/live-runner.ps1`.
3. `findings/E.2-transcription-lab.md` — what changed in the hot path (your sweep must cover it).
4. E.1 findings if present — any behavioral must-fixes assigned to E.3.

### Prong A — Harvest the dogfood flags (~1 h)
Pull every `"flagged": true` history entry since E.2 shipped. For each: raw vs cleaned vs (if saved) audio; classify (Whisper mishear / cleanup fault / typing-stage fault / user-error); reproduce where possible; fix or file. Flags that are transcription-quality → verify E.2's fixes actually cover them (if not, patch the prompts/guard within this session — small deltas only).

### Prong B — The seam matrix (work through ALL of these deliberately)

For each seam: predict expected behavior, test it live (PowerShell-driven AHK + `tests/live-runner.ps1` + debug.txt tail), record actual, fix or document. **User needed for the mic-dependent ones — batch them.**

| # | Seam | Test |
|---|---|---|
| 1 | **Sleep/resume** | Dictate → sleep the machine → resume → dictate. Hotkey still registered? MCI/FFmpeg capture recovers? Widget state sane? |
| 2 | **Focus change mid-processing** | Dictate, then click a DIFFERENT app before the transcript lands. Where does the text go? (Classic dictation-app data-loss/mis-paste bug — decide + implement correct behavior: type into originally-focused app or discard with feedback, never into the wrong window silently.) |
| 3 | **Unicode/emoji/IME targets** | Dictate into a field with an IME active, into a document containing emoji, RTL text nearby. SendInput mangling? |
| 4 | **DPI/monitor change mid-session** | Move widget across mixed-DPI monitors; unplug the monitor the widget lives on while recording. (T1.7's RepositionToVisible covers display-change — verify live, incl. DURING an active recording.) |
| 5 | **5-minute auto-stop** | Record to the cap. Clean stop + transcription of the full buffer? Feedback to user? |
| 6 | **Rapid-fire hotkey** | Spam hold/release fast 10×. State machine wedges? Overlapping recordings? (RecordingGeneration guard — verify live.) |
| 7 | **Mic unplugged mid-recording** | Pull the device (or disable in Sound settings) while held. Graceful error vs hang/crash? |
| 8 | **Network loss mid-transcription** | Kill network between release and API return (firewall rule or airplane toggle). Timeout feedback? Retry story? Recording preserved? |
| 9 | **API key revoked mid-session** | Swap config to an invalid key while running → dictate. Is the error actionable (Dad Test: recovery steps, not "401")? |
| 10 | **Elevated-window target** | Dictate into an admin-elevated app (e.g. elevated Notepad) from the non-elevated QuickSay. SendInput is blocked by UIPI — expected. Does the app FEEDBACK (text went nowhere) or fail silently? Silent = fix with detection + TrayTip/widget hint. |
| 11 | **Terminal paste path** | Windows Terminal, legacy conhost, VS Code terminal: Shift+Insert path works in each? Clipboard preserved/restored after? |
| 12 | **Settings open during dictation** | Dictate while the settings window is open and while it's SAVING (0x5555 reload race with an active recording). |
| 13 | **Long-session soak** | `live-runner.ps1` soak: hourly dictations for a workday equivalent (compressed), watch memory/handles of the tray process (leak check), history/stats integrity. |
| 14 | **Locale robustness** | Non-US decimal locale + non-English Windows display language: any parsing (durations, JSON, number formatting in stats) break? |

### Phase 3 — Fix, guard, document
- Every fix ships with a regression test (unit where possible; scripted live check where not — add to a new `tests/seams/run-tests.ps1` runner).
- Unfixable platform limits (e.g. UIPI) get: detection + user feedback in-app, and a line in a new `docs/KNOWN-LIMITATIONS.md`.
- Findings → `C:\QuickSay\docs\audit-campaign\findings\E.3-bug-sweep.md` (per-seam verdict table: PASS / FIXED / DOCUMENTED-LIMIT).

### Done When
- [ ] All dogfood flags harvested, classified, and resolved (fixed / covered-by-E.2 / filed with reason).
- [ ] All 14 seams tested with recorded verdicts; every FAIL either fixed+regression-tested or converted to detected-and-fed-back limitation.
- [ ] Focus-change (#2) and elevated-target (#10) have explicit, implemented, correct behavior — these are the two most likely silent-data-loss paths.
- [ ] Soak (#13) shows no leak growth trend.
- [ ] Full existing test suites still green (history/license/crash/telemetry/update/cleanup/transcription).
- [ ] Findings committed; code on `audit/E.3-bug-sweep` + PR; MASTER-PLAN → E.3 ✅.

### What NOT to do
- ❌ No feature work — this session only makes existing behavior correct under stress.
- ❌ Don't run AHK GUI tests through Bash (hangs) — PowerShell tool per memory.
- ❌ Don't mark a seam PASS from code reading alone — every verdict needs a live observation.
- ❌ Don't leave the machine's firewall/sound/locale test mutations in place afterward — restore everything.

### Estimated time
Prong A: ~1 h. Prong B: ~4–5 h (mic items batched with user, ~30 min of their time). Fixes: variable, budget ~2 h. **Total: ~7–8 h; may split into two sittings after the sweep.**

### When you're done, report back with
- The per-seam verdict table.
- Bugs fixed (with tests) vs documented limitations.
- Anything that should gate E.5/launch vs ride as post-launch known-issue.
