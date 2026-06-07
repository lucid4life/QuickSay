# History / Retention regression suite (T1.5)

Guards the history + audio retention layer and the clear-history race fix.

```powershell
# Run from PowerShell (NOT the bash sandbox — the AHK host needs a window station)
pwsh tests\history\run-tests.ps1
```

Exit code 0 = all green. Operates in a scratch temp dir; never touches
`Development/data/` or `config.json`.

## Layers

1. **`history-core.test.ahk`** — AHK-native unit driver exercising the REAL
   functions in `lib/history-core.ahk` (no copied bodies, so it can't drift from
   production). The runner extracts pass/fail to a TSV and asserts in PowerShell.
2. **Source assertions** (in `run-tests.ps1`) over `lib/settings-ui.ahk` for the
   pagination-cache invalidation (test 11). The real `SettingsUI` class can't be
   headless-loaded (its WebView2 include chain hangs without a desktop), so the
   `InvalidateHistoryCaches` method and its `0x5555` wiring are verified
   structurally — exactly the regression that would reintroduce stale counts.

## Coverage

| Test | Guards |
|---|---|
| 01–05 | `historyRetention`: under-cap keep, at-cap trim, 250-entry migration, `0`=unlimited, newest-kept/oldest-dropped order |
| 06–08 | `keepLastRecordings`: trim to N when saving on, no-prune when saving off, `0`=delete all |
| 09 / 09b / 09c | clear-history: in-flight write dropped by the generation guard, normal write proceeds, **old entries never resurrect** after a clear |
| 10 / 10b | sequential writes leave valid JSON; transcript containing `},` / `"id":` never corrupts the file (kills the old string-surgery bug) |
| 11 / 11b | settings `InvalidateHistoryCaches` resets both caches and is wired to `0x5555` |
| 11c / 11d | config merge / lost-update: updates preserve unrelated keys; deletes remove only requested keys |
| 12 | `getHistoryCount` counts parsed entries, not physical lines |
| 13 | a valid-but-non-array (legacy object) file is preserved to `.corrupt`, never silently lost |

**Prereq:** AutoHotkey v2 at `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`
(falls back to the bundled `Development\AutoHotkey64.exe`).
