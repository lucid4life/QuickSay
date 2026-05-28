# QuickSay App Surface Inventory (STARTING POINT)

> ⚠️ **Status: partial / unverified.** This was compiled by the surface-mapping agent partly from incomplete reads. Treat every claim as a *hypothesis to verify*, not fact. Session **P0.2** re-verifies the flagged items; the audit sessions (T1.1–T1.4) produce the authoritative inventory with line citations.

---

## Category 1: Settings (by tab)

**General Tab:**
- API Key (text input, DPAPI-encrypted, `groqApiKey`)
- Hotkey (capture, default `^LWin`, `hotkey`, PostMessage reload on change)
- Toggle Mode (button action in WebView2)
- Auto-paste (bool, default 1, `autoPaste`)
- Show overlay (bool, default 1, `showOverlay`)
- Show widget (bool, default 0, `showWidget`, persists `widgetX`/`widgetY`)
- Launch at startup (bool, default 1, `launchAtStartup`, writes HKCU registry)
- Accessibility Mode (bool, default 0, `accessibilityMode`)
- Play sounds (bool, default 1, `playSounds`)
- Language (dropdown, default `en`, `language`, 43 languages)

**Audio Tab:**
- Audio Device (dropdown, default `Default`, `audioDevice`, enumerated via FFmpeg)
- Recording Quality (dropdown, default `medium`, `recordingQuality`: low/medium/high)
- Sound Theme (dropdown, default `default`, `soundTheme`: default/subtle/click/crystal/neon/bloom/silent)
- Save audio recordings (bool, default 0, `saveAudioRecordings`)
- Keep last recordings (numeric, default 10, `keepLastRecordings`) ⚠️ **flagged orphaned — cleanup may not be wired**

**Processing Tab:**
- Smart punctuation (bool, default 1, `smartPunctuation`)
- Auto-remove fillers (bool, default 1, `autoRemoveFillers`)
- Enable LLM cleanup (bool, default 1, `enableLLMCleanup`)
- Context aware modes (bool, default 0, `contextAwareModes`) ⚠️ **flagged — implementation may not exist**
- Debug logging (bool, default 0, `debugLogging`)

**Modes Tab:** Mode selector (dynamic load, triggers 0x5555 reload)

**Dictionary Tab:** load/save/import/export via WebView2 postMessage

**View-History Tab:**
- History retention (numeric, default 500, `historyRetention`) ⚠️ **flagged — enforcement unverified**
- Clear history action ⚠️ **user reports broken: appears to clear, then reappears**
- Export history action

**View-Statistics Tab:** read-only from statistics.json

**About Tab:**
- Last seen version (`lastSeenVersion`, default `1.9.0-beta`) ⚠️ **version format mismatch vs `1.9.0.0` resource**
- Last update check (`lastUpdateCheck`, default `2026-05-19`)
- Changelog viewer

**Total: ~28 config fields across 8 tabs.**

---

## Category 2: Transcription modes

4 built-in (verify exact prompt text + dual-sync between QuickSay.ahk and lib/settings-ui.ahk during T1.1/T1.2):

1. **Standard** — "Transcribe spoken words exactly as heard… Fix obvious speech-to-text errors but maintain the speaker's original intent and vocabulary."
2. **Email** — "Convert spoken text into professional email format… formal tone, paragraphs, subject line if appropriate."
3. **Code** — "Convert spoken text into valid code comments or documentation… preserve variable/function names exactly."
4. **Casual** — "Convert spoken text into casual, conversational written form… contractions, remove fillers, friendly tone."

Notes: custom modes loaded dynamically from config; LLM model `openai/gpt-oss-20b` hardcoded for all modes; no per-mode model customization.

---

## Category 3: Hotkey behaviors

- Registration via `RegisterHotkey()`, default `^LWin`
- Hold vs tap: `stickyMode` toggle (default 0)
- Low-level keyboard hook (WH_KEYBOARD_LL) in `StartHotkeyCapture()`
- Press → record start; release → record stop
- Startup persistence: HKCU\…\Run via `UpdateStartupRegistry()`

---

## Category 4: Sounds

- 3 events per theme: `start.wav`, `stop.wav`, `error.wav`
- **6 themes (VERIFIED on disk 2026-05-27):** `bloom`, `click`, `crystal`, `mechanical`, `neon`, `subtle` — matches CLAUDE.md exactly.
  - ⚠️ The original agent draft claimed 7 themes ("default", "silent" + missed "mechanical"). That was WRONG. Ground truth is the 6 above.
  - There is no "default" or "silent" theme directory. If `soundTheme` defaults to `"default"` in config, that's a config-vs-disk mismatch T1.4 must resolve (does the code fall back gracefully when the named theme dir is absent?).
- Stored in `sounds/<theme>/`; toggled via `playSounds`; selected via `soundTheme`
- 18 sound files total (3 × 6)

---

## Category 5: API endpoints

1. **Groq Whisper STT** — `https://api.groq.com/openai/v1/audio/transcriptions`, POST multipart, model `whisper-large-v3-turbo` (hardcoded), 120s timeout, retry via `HttpPostFileWithRetry`, Bearer `groqApiKey`
2. **Groq LLM** — `https://api.groq.com/openai/v1/chat/completions`, POST JSON, model `openai/gpt-oss-20b` (hardcoded), 120s timeout, Bearer `groqApiKey`
3. **Update check** — `https://quicksay.app/version.json` (per CLAUDE.md `CheckForUpdates()`)

---

## Category 6: File I/O

- `config.json` (%APPDATA%\QuickSay\) — DPAPI for key; AtomicWriteFile + mutex (verify coverage)
- `dictionary.json` — regex-compiled at load
- `history.json` — appended per transcription; retention `historyRetention`; ⚠️ atomic/mutex coverage unclear
- `statistics.json` — updated per transcription
- `data/audio/*.wav` — if `saveAudioRecordings`; retain `keepLastRecordings` ⚠️
- `onboarding_done` marker
- `debug.txt` / logs — if `debugLogging`
- `changelog.json`

---

## Category 7: Timers & background work (verify in T1.1)

Estimated 6+ SetTimer callbacks: history cleanup, statistics/streak, tray menu refresh, display-change (0x7E), config reload (0x5555), audio device enumeration. FFmpeg subprocess killed in OnExit, 120s blocking timeout.

---

## Category 8: Windows messages

- `WM_DISPLAYCHANGE` (0x7E) — overlay/widget reposition
- `QuickSay_ConfigReloadMsg` (0x5555) — config/mode reload; **target window `QuickSay_TrayMode ahk_class AutoHotkey`**
- `WM_SETICON` (0x80) — tray icon update
- Posted: `PostMessage(0x5555, 1, 0)` from settings-ui.ahk after saveConfig/saveModes/setMode

---

## Category 9: WebView2 actions (~33 identified, verify dead actions in T1.2)

loadConfig, saveConfig, testGroqAPI, getAudioDevices, loadDictionary, saveDictionary, getHistoryCount, clearHistory, viewLogs, closeAfterSave, closeSettings, openUrl, importDictionary, exportDictionary, exportHistory, loadHistoryData, loadMoreHistory, loadStatisticsData, deleteHistoryFile, loadLegalDoc, loadModes, saveModes, setMode, previewSound, loadChangelog, markChangelogSeen, exportConfig, importConfig, testHotkey, startHotkeyCapture, stopHotkeyCapture, tourCompleted, clearStartTourFlag.

Response pattern: `window.chrome.webview.postMessage({result, data, error})`.

---

## Category 10: Version strings (CRITICAL for T1.6)

- `QuickSay.ahk` lines 2–8: `"QuickSay Beta v1.9"`, `version = "1.9.0.0"`, `product = "QuickSay Beta v1.9"`
- `config.json` `lastSeenVersion`: `"1.9.0-beta"` ⚠️ **format mismatch**
- `config.json` `lastUpdateCheck`: `"2026-05-19"`
- `settings-ui.ahk`: `markChangelogSeen` updates `lastWeeklySummary`
- changelog.json top entry

⚠️ **Inconsistent version tracking across at least 5 locations. T1.6 establishes single source of truth (`Development/VERSION`) + `release.ps1 --check-sync` gate.**

---

## Category 11: TODO/FIXME/HACK

None explicitly marked in partial reads. **Implicit tech-debt flags (verify):**
1. STT model hardcoded `whisper-large-v3-turbo`
2. LLM model hardcoded `openai/gpt-oss-20b`
3. AtomicWriteFile usage not uniform (race risk)
4. `contextAwareModes` field with no implementation
5. `keepLastRecordings` not wired to cleanup

T1.1 must run a full `grep -rni "TODO|FIXME|HACK|XXX"` and replace this section with verified results.

---

## Category 12: Directories outside Development/

- `%APPDATA%\QuickSay\` — config, dictionary, history, statistics, onboarding_done
- `%APPDATA%\QuickSay\data\audio\` — recordings
- `%APPDATA%\QuickSay\logs\` — debug log
- `%LOCALAPPDATA%\Programs\QuickSay Beta\` — installed app (production build)
- `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` — startup registry
- `%TEMP%\` — FFmpeg temp files
- `C:\QuickSay\Website\`, `C:\QuickSay\Automation\`, `C:\QuickSay\Marketing\` — sibling repos (out of app scope)

---

## The 6 things flagged as surprising / broken-looking

1. **Model hardcoding** — both STT and LLM models hardcoded, no UI customization despite API support.
2. **`contextAwareModes`** — config field exists (default 0) but no implementation found in reviewed code. Likely abandoned.
3. **`keepLastRecordings`** — persists to config but cleanup logic appears not wired to retention enforcement.
4. **File-sync uncertainty** — config.json and history.json writes use unclear synchronization; AtomicWriteFile exists but not uniformly enforced → potential race conditions.
5. **Version format mismatch** — `lastSeenVersion: "1.9.0-beta"` vs ScriptVersionInfo `"1.9.0.0"`. Could break changelog display logic.
6. **History clear** — user reports it appears to clear then reappears (race between tray in-memory cache and settings-process file clear). This is the bug T1.5 fixes.
