# Session F.3: Auto-Learning Dictionary + Shareable Stat Card

> **Model:** Fable 5 (`/model claude-fable-5`), Opus 4.8 acceptable
> **Effort:** high (`/effort high`)
> **Branch:** `feature/F.3-auto-dictionary-statcard` (Development repo), off `main`.
> **POST-LAUNCH (v2.1) per user decision 2026-07-22** — do NOT run before M.3 ships; this is the first auto-update beat after launch (signed updates via T2.5 deliver it to the first 500 buyers).
> **Parallel-safe with:** F.4 (research spike). NOT parallel with other app-code sessions (shared `QuickSay.ahk`, `gui/settings.html`).
> **Depends on:** v2.0.0 launched (M.3); F.1/F.2 merged.
> **Why:** Competitive deep-dive 2026-07-22: Wispr Flow's dictionary "auto-learns names and jargon" while QuickSay's needs manual entry, and Wispr/Superwhisper both ship shareable usage stats (WPM, streaks) that drive word of mouth. QuickSay already stores everything needed for both; this session is mostly wiring, sized M + M in codebase recon.

---

## Prompt to paste

You are shipping two features: (1) an auto-learning dictionary that mines dictation history for repeated corrections and proposes them for user approval, and (2) a shareable weekly stat card. Both build almost entirely on primitives that already exist; reuse them, do not reinvent.

### Evidence already in hand (codebase recon 2026-07-22; build on it, do not re-derive)

**Dictionary + learning primitives (all shipped today):**
- Storage `dictionary.json` (`QuickSay.ahk:122`), load `LoadDictionary()` `:1838-1854`, one-regex compile `CompileDictionaryPattern()` `:2323-2342`, apply `ApplyDictionary()` `:2292-2320` (called `:1290` file path, `:3455` live path).
- **Manual learn flow already exists:** `Ctrl+Shift+D` -> `LearnFromSelection()` `:2892-2940` diffs the user's corrected text against `LastTranscription` (<120s old) via `FindWordDifferences()` `:2942-3003` (case + fuzzy hyphen matching) and calls `AddToDictionary()` `:3005-3056`. The auto version generalizes exactly these functions.
- History entries store BOTH `rawText` and `cleanedText` (+ `appContext`, `wordCount`, `timestamp`, `flagged` optional) per `SaveToHistory()` `:2146-2155`; pure read/write helpers in `lib/history-core.ahk` (`ReadHistoryArray` `:20-40`, `FlagNewestHistoryEntry` `:133-143`).
- **No miner exists today** (verified: `tests/dictionary/` and `tests/history/` are unit tests only). E.2's flag-last-transcription affordance marks entries `flagged: true`; flagged entries are prime mining input.
- Dictionary terms feed the Whisper bias prompt (`lib/whisper-bias.ahk`, live path only, ~224-token budget with oldest-dropped truncation `:47-56`). **A polluted dictionary poisons transcription for every future request. Silent auto-add is therefore forbidden; user approval is a hard requirement.**
- Schema wrinkle: settings-UI writes an `addedAt` field (`gui/settings.html:2027`) that `AddToDictionary()` does not; align while you are in here.

**Stats primitives (all shipped today):**
- `UpdateStatistics()` `QuickSay.ahk:2192-2286` persists `totalWords`, `totalSessions`, `averageWPM` (filtered >=5s & >=3 words), `byDay[date] = {sessions, words}`, `byApp`, `dailyStreak`, `firstUse`/`lastUse` to `statistics.json`. **These aggregates are NEVER trimmed.**
- `history.json` is capped at `history_retention` = 100 entries default (`:1957`; trim in `history-core.ahk:44-53`). **Any stat that scans history.json silently truncates. The card MUST read `statistics.json`.**
- `CheckWeeklySummary()` `:740-821` already computes week words/sessions + streak + minutes saved (`weekWords/40`, `:801`) but (a) delivers it as a TrayTip only and (b) derives week numbers by regex-scanning history.json (`:778-785`), which is both fragile and retention-capped. Refactor it to read `statistics.json:byDay`.
- The settings WebView2 already renders a full stats dashboard: `gui/settings.html` `#view-statistics` (`:667+`), period selector, KPI cards, derived keystrokes/pages metrics (`:2696-2761`), achievements (`:2719-2724`). **No canvas/toDataURL/PNG-export exists anywhere** (verified), and `lib/GDI.ahk` has no text-draw or bitmap-export either. Recommended path: in-page `<canvas>` render + `toDataURL` + copy-image-to-clipboard inside the settings WebView2 (pure DOM/JS, no new native code).

### Phase 1: History miner (M)
1. `MineHistoryForCorrections()`: read history via `ReadHistoryArray`, run `FindWordDifferences(rawText, cleanedText)` per entry, aggregate identical spoken->written diffs across entries, and threshold (propose only diffs seen >= 3 times, tunable const). Weight `flagged: true` entries (count double or lower threshold; document the choice).
2. Filter noise: skip diffs already in the dictionary, pure-case-only diffs below threshold, single-character diffs, and anything matching the E.2 filler/punctuation classes (cleanup legitimately deletes fillers; those are NOT vocabulary corrections). Reuse classification logic from the E.2 harness where it exists.
3. Trigger: on settings-open or a "Review suggestions" button, NOT on the dictation hot path (mining must never add latency to a dictation).

### Phase 2: Review-and-approve UX (M)
1. Dictionary tab gets a "Suggested" section: proposed spoken->written pairs with occurrence counts, Approve / Ignore per row (Ignore persists so a rejected pair never resurfaces; store ignore-list beside the dictionary).
2. Approved entries flow through the existing `saveDictionary` round-trip (`lib/settings-ui.ahk:1241-1252`) so `CompileDictionaryPattern()` and the bias prompt update exactly as a manual add would. Align the `addedAt` schema wrinkle here.
3. Respect the bias-prompt budget: if the dictionary approaches the ~224-token cap, surface a gentle count warning in the tab (truncation already drops oldest terms silently; tell the user instead).

### Phase 3: Stat card (M)
1. Refactor `CheckWeeklySummary()` week-math onto `statistics.json:byDay`; keep the TrayTip but add "View your week" click-through that opens Settings -> Statistics.
2. In the stats tab, add "Share card": render a fixed-size card (canvas, ~1200x630) with words this week, average WPM, streak, minutes saved, and a small QuickSay wordmark; `toDataURL` -> clipboard as image + save-PNG-to-file option. Keep the design consistent with the settings UI look; no external assets (CSP/offline).
3. Privacy: the card contains aggregate numbers only, never transcript text or app names. State this in the findings doc.

### Phase 4: Tests + verification
1. Miner unit tests (PowerShell or AHK harness per existing patterns in `tests/`): synthetic history arrays covering threshold, dedupe-against-dictionary, ignore-list persistence, filler-class exclusion.
2. Dictionary recompile test still green (`tests/dictionary/dictionary-recompile-test.ps1`); history suite 19/19; full suite sweep.
3. Manual: seed history with a repeated correction, confirm it appears in Suggested, approve, dictate the term, confirm bias + regex both apply.

### Done When
- [ ] Miner proposes only threshold-passing, noise-filtered corrections; NEVER auto-adds; Ignore is permanent.
- [ ] Approved suggestions land through the existing save path (regex + bias prompt verified live).
- [ ] Stat card renders from `statistics.json` only, copies to clipboard as an image, and saves as PNG.
- [ ] `CheckWeeklySummary()` no longer regex-scans history.json.
- [ ] All suites green incl. new miner tests; findings doc `C:\QuickSay\docs\audit-campaign\findings\F.3-auto-dictionary-statcard.md`; PR from `feature/F.3-auto-dictionary-statcard`.

### What NOT to do
- No silent dictionary additions, ever (bias-prompt poisoning risk).
- No mining on the dictation hot path.
- No stat derived from history.json (retention-capped); `statistics.json` only.
- No transcript content or per-app names on the share card.
- Do not touch the hotkey/recording layers (F.1 territory).

### Estimated time
Phase 1: ~1.5 h. Phase 2: ~1.5 h. Phase 3: ~2 h. Phase 4: ~1 h. Total: ~5.5-6 h.

### When you're done, report back with
- A screenshot of the Suggested section with real mined pairs and of the share card.
- Miner precision on the user's real history (how many proposals were junk).
- Whether the ~224-token bias budget warning triggered on the user's dictionary.
