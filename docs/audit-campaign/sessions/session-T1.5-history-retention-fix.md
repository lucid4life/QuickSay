# Session T1.5 — Fix History Retention + Race Condition (FIX)

> **Model:** Opus 4.7
> **Effort:** xhigh
> **Switch commands:** `/model opus` then `/effort xhigh`
> **Branch:** `audit/T1.5-history-retention-fix`
> **Parallel-safe with:** T1.6, T1.7, all of Track 2 (different files)
> **Depends on:** T1.1 (core engine findings — where the retention surface lives) AND T1.2 (UI/settings findings — where the clear-history race condition surfaces)
> **Blocks:** nothing (this is a leaf fix)
>
> Before pasting this prompt: confirm `/model opus` and `/effort xhigh`. This session has an explicit `ultrathink` step at the root-cause-analysis moment — do not skip it.

---

## Prompt to paste

You are fixing three closely-related bugs in QuickSay's history/retention layer. All three were flagged in the T1.1 and T1.2 audits. You will read those findings, root-cause them as a group, then ship a single coherent fix with regression tests.

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2). The history layer stores every transcription in `data/history.json`. The audio layer optionally saves the source WAV at `data/audio/QS_YYYYMMDD_HHmmss.wav`. Two config fields are supposed to cap growth:

| Field | Default | Purpose |
|---|---|---|
| `historyRetention` | 100 | Max number of entries in `history.json` |
| `keepLastRecordings` | 10 | Max number of WAV files retained in `data/audio/` |

**Both are orphaned.** They appear in the settings UI, they round-trip through `LoadConfig()` (see `QuickSay.ahk:1654-1655`), but nothing actually enforces the caps. The user has also reported — verbatim — that "I cleared history and it came back after my next transcription." That is the race condition you will also fix.

Working directory: `C:\QuickSay\Development\`.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — file map, IPC model, AtomicWriteFile + config mutex
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign context, Status Tracker
3. `docs/audit-campaign/findings/T1.1-core-engine.md` — every history/audio finding tagged "owned by T1.5"
4. `docs/audit-campaign/findings/T1.2-ui-settings-webview2.md` — the clear-history race condition trace (HTML → WebMessage → settings-ui.ahk → QuickSay.ahk)
5. `docs/audit-campaign/research/competitor-backend-research.md` — section 6 (sync) confirms local-only retention is fine; no need to design a sync hook here.

### Scope — files you may modify

| File | Why |
|---|---|
| `Development/QuickSay.ahk` | Main engine. Owns the history-write side. `LoadConfig()`, `SaveHistory()`-equivalent flow, and the IPC handler that responds to `clearHistory` are here. |
| `Development/lib/settings-ui.ahk` | Settings IPC handler (`HandleClearHistory()` at line 1199). Currently writes the empty array — but the tray process may write again from an in-flight transcription before the write lands. |
| `Development/tests/history/` | **CREATE** — new regression test directory. |
| `Development/config.example.json` | Confirm the two fields are documented; add a comment if missing. |

**Forbidden** (other sessions' surface):
- Anything in `gui/onboarding.html`, `onboarding_ui.ahk`, `widget-overlay.ahk`, `sounds/`, `dictionary.json` → T1.4
- `setup.iss`, `release.ps1`, `signing/` → T1.3, T1.6
- New license/paywall code → T2.3
- Crash reporting hooks → T2.4

### Phase 1 — Read both audit findings and reconstruct the failure surface

Invoke `superpowers:systematic-debugging`.

For each finding tagged "owned by T1.5" in the T1.1 and T1.2 findings docs, copy it into a working scratchpad. You should end up with at least these three:

1. **`keepLastRecordings` orphan** — config field exists, read by `LoadConfig()`, never consulted by any audio-write site.
2. **`historyRetention` orphan** — config field exists, read by `LoadConfig()` and `settings-ui.ahk:1366-1379`, but never enforced when a new entry is appended to `history.json`.
3. **Clear-history race condition** — user clicks "Clear History" in settings, the array is replaced with `[]` and written, but the **tray process** has a deferred `SetTimer` write pending from the just-completed transcription which then re-writes the entry into the now-empty file. The user sees history "come back."

Map each one to specific call sites by file:line. Cite from the source — do not trust the surface inventory blindly.

### Phase 2 — ultrathink the root cause

**Type the word `ultrathink` into your reasoning at this step.** This is the part of the session where shallow analysis will produce a fix that papers over the actual bug.

Specifically reason about:

- **Why have the retention orphans survived this long without anyone noticing?** Possibilities: nobody has accumulated 100+ entries in beta; the file just keeps growing silently; users assume retention is happening because the UI implies it. Pick the most likely answer and *verify* by reading `data/history.json` in your own install (it should reveal how many entries are there). The answer informs whether your fix needs migration logic for users whose file is already huge.

- **Where does the clear-history race actually originate?** Three candidates:
  1. The settings IPC handler writes to disk but the tray's deferred-write timer (the `SetTimer` after each transcription) fires after and re-adds.
  2. The two processes both hold an in-memory history array. Settings clears its copy and writes. Tray writes its (un-cleared) copy on next transcription.
  3. AtomicWriteFile is being used but the mutex isn't being acquired on one side.

  The correct answer determines the fix shape — single source of truth (option 2), IPC reload message (option 2 + 0x5555), or just always re-read from disk before appending (slower but trivially correct).

- **What is the cleanest invariant?** "After any history-modifying operation, the on-disk file is the truth and any in-memory caches are flushed." That invariant, properly enforced, fixes both the race AND the retention enforcement in one stroke (because retention can be applied at the same flush point).

Write your conclusion as a short root-cause memo at the top of `docs/audit-campaign/findings/T1.5-root-cause.md` before you write any code. Two paragraphs is enough.

### Phase 3 — Write the failing tests first

Invoke `superpowers:test-driven-development`.

Create `Development/tests/history/` with a runner (`run-tests.ps1`) and these test cases. Use the AHK test harness scaffolded in P0.2 (`Development/tests/live-runner.ps1`) where it helps, and AHK-native unit tests (via `ahk-testlib` or inline asserts — match whatever P0.2 settled on) where it doesn't.

**Retention tests:**
1. `history.json` starts with 95 entries, `historyRetention=100` — adding 1 entry leaves 96 in the file.
2. `history.json` starts with 100 entries, `historyRetention=100` — adding 1 entry trims oldest, file has 100.
3. `history.json` starts with 250 entries (legacy bloated state), `historyRetention=100` — first new write trims to 100. (Migration test.)
4. `historyRetention=0` is treated as "unlimited" (existing config semantics — confirm against `lib/settings-ui.ahk:1371` before locking it).
5. Order is preserved: oldest entries are dropped, newest kept.

**Audio retention tests:**
6. `data/audio/` starts with 15 WAV files, `keepLastRecordings=10`, `saveAudioRecordings=true` — next save trims to 10 (5 oldest deleted by `FileGetTime` mtime).
7. `data/audio/` has 15 WAV files, `keepLastRecordings=10`, `saveAudioRecordings=false` — no trimming happens, save is skipped, the 15 stale files remain (the user must turn the setting back on or use a "Clear all recordings" button).
8. `keepLastRecordings=0` — every recording is deleted immediately after transcription (already the implicit behavior — assert it).

**Race-condition tests:**
9. With QuickSay.ahk running under the test harness: simulate a transcription that is mid-flight (deferred timer pending). Trigger clear-history via the IPC pathway (or directly call `HandleClearHistory()`). After the deferred timer fires, `history.json` must still be empty.
10. Two near-simultaneous writes (one from each process) — the file is never corrupted (still parseable JSON, atomic-write semantics held).
11. Settings UI `_historyRetention` cache (`lib/settings-ui.ahk:26`) is invalidated when the tray process broadcasts a config-reload (`0x5555`). Otherwise the UI shows stale counts.

Run the tests. They MUST fail before you write the fix. If any pass already, you have not reproduced the bug correctly — go back to Phase 2.

### Phase 4 — Implement the fix

The fix has three pieces. Implement in this order, running the relevant test after each:

#### 4a. History retention enforcement (tests 1–5)

In the transcription-complete handler in `QuickSay.ahk` (the place that appends to history — start near `QuickSay.ahk:1817` and trace outward), call a new helper `TrimHistoryToRetention(historyArray, retentionLimit)` before writing. Implementation:

- If `retentionLimit <= 0`, return the array unchanged.
- Otherwise, slice to keep the most recent `retentionLimit` entries.
- The write must use `AtomicWriteFile()` AND the config mutex (`AcquireConfigLock()`).

Add migration: if the loaded array is larger than the limit, trim on first append (the first new transcription after upgrade silently brings the file in line). Log to `data/logs/debug.txt` when this happens, gated by `debugLogging`.

#### 4b. Audio directory retention (tests 6–8)

Add a new helper `PruneAudioDirectory(dirPath, keepCount)` to `QuickSay.ahk`:

- Enumerate `*.wav` in `data/audio/` sorted by `FileGetTime`/mtime descending.
- Delete everything past index `keepCount`.
- Wrap in `try/catch` — never let a failed delete prevent the user's recording from saving.

Wire it into the audio-save path (the WAV-rename or WAV-move step that runs only when `saveAudioRecordings=true`). Call AFTER the save, so the just-saved file is included in the keep set.

When `saveAudioRecordings=false`: do NOT prune. The user may have files from a previous session they want to keep. (Add a "Clear all recordings" button to the settings UI in a follow-up — that work is owned by T1.7, do not do it here.)

#### 4c. Clear-history race condition (tests 9–11)

Whichever root cause Phase 2 identified, implement the fix:

- **If two in-memory copies:** make the settings process broadcast `0x5555` (`QuickSay_ConfigReloadMsg`) after writing the empty array. The tray's existing `0x5555` handler must invalidate any cached history array AND cancel any pending `SetTimer` write that has stale data. **IPC target is `"QuickSay_TrayMode ahk_class AutoHotkey"`** — confirmed in `CLAUDE.md`.
- **If deferred timer race:** change the history write to be synchronous on the hot path's tail (the part after paste has already returned), not deferred via `SetTimer`. Or — if you keep the timer for perf reasons — make the timer's callback always re-read the file before appending (slower but trivially correct).
- **If mutex side:** add `AcquireConfigLock()` to the side that's missing it. Both sides must hold the mutex during any read-modify-write of `history.json`.

Whichever path you take, the invariant is: **after `HandleClearHistory()` returns success, no subsequent transcription can re-introduce the cleared entries.**

#### 4d. Settings UI cache invalidation (test 11)

In `lib/settings-ui.ahk`, the `static _historyRetention` cache (line 26) is set in `LoadHistoryPaginated()` and never invalidated. Add a small invalidation: when the settings process receives the `0x5555` config reload message, reset `_historyRetention := 0` so the next pagination call re-reads from config.

### Phase 5 — Verification

Invoke `superpowers:verification-before-completion`.

Verifiable gates:

- [ ] Run the test runner. All 11 tests pass.
- [ ] Manual smoke: start `QuickSay.ahk`, transcribe ~5 short utterances, open settings → History tab, count entries (should equal 5). Click "Clear History" — file is empty. Transcribe again — file has 1 entry (the new one, not the cleared 5).
- [ ] Manual smoke for retention: set `historyRetention=3` in config.json, then transcribe 5 times. History tab and the on-disk file both show only the 3 most recent.
- [ ] Manual smoke for audio: set `keepLastRecordings=3` and `saveAudioRecordings=true`, do 5 recordings, list `data/audio/` — only 3 WAV files remain.
- [ ] Invoke `code-review` skill on your diff before committing. Address every P0/P1 the reviewer flags.

### Done When

- [ ] `docs/audit-campaign/findings/T1.5-root-cause.md` exists with the Phase 2 root-cause memo
- [ ] `Development/tests/history/` directory exists with 11 tests + a runner
- [ ] All 11 tests pass
- [ ] `QuickSay.ahk` enforces `historyRetention` on every history write
- [ ] `QuickSay.ahk` enforces `keepLastRecordings` on every audio save (when `saveAudioRecordings=true`)
- [ ] Clear-history race condition fix is in place — clearing history persists across the next 3 transcriptions in manual smoke
- [ ] `lib/settings-ui.ahk` cache invalidation is wired to `0x5555`
- [ ] `AtomicWriteFile()` + config mutex used on every read-modify-write of `history.json`
- [ ] No regressions in dictation: hold hotkey, speak, release, paste works exactly as before
- [ ] Branch `audit/T1.5-history-retention-fix` committed; PR opened
- [ ] MASTER-PLAN.md status updated: T1.5 → ✅, with test count noted

### What NOT to do

- ❌ Do not change the audio file naming convention (`QS_YYYYMMDD_HHmmss.wav`). It is referenced by the history entries.
- ❌ Do not add a "Clear all recordings" button to the settings UI — that lives in T1.7.
- ❌ Do not introduce a new background thread or worker process. Use existing `SetTimer` or synchronous calls.
- ❌ Do not change the on-disk `history.json` schema. Existing entries must remain readable.
- ❌ Do not call any HTTP endpoint for history pruning. This is purely local.
- ❌ Do not refactor unrelated history code "because you noticed something." File a `spawn_task` flag for it instead.
- ❌ Do not silently swallow exceptions in `PruneAudioDirectory()` — log them when `debugLogging=true`.
- ❌ Do not write a one-shot migration script. Migration must happen inline on first append after upgrade.
- ❌ Do not skip Phase 2's `ultrathink` step. The whole point of this session is the root-cause memo.

### Estimated time

Phase 1 (read findings + map): 30 min. Phase 2 (ultrathink + memo): 30 min. Phase 3 (write 11 tests): 60 min. Phase 4 (implement fix): 90 min. Phase 5 (verification): 30 min. Total wall-clock: ~4 hours.

### When you're done

Report back with:
- Path to the test runner and exact invocation
- The 11 test names + pass/fail status (should be 11/11 green)
- The root-cause from Phase 2 in one sentence each (one for the orphans, one for the race)
- Which fix-shape you chose for the race (4c options A/B/C) and why
- Anything you noticed in the surrounding code that smelled bad but was out of scope — flag via `spawn_task`, do not fix here.
