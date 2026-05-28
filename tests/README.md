# QuickSay — Test Harnesses (P0.2)

Three harnesses built in P0.2. All subsequent audit and fix sessions (Phase 1 Track 1 and Track 2) use them.

These tests live in `Development/tests/` (committed to git) and are **never bundled into the installer** — `setup.iss` copies named paths only; `tests/` is excluded by omission.

---

## (a) Playwright/CDP — WebView2 UI harness

Drives the settings and onboarding windows via Chrome DevTools Protocol.

```powershell
# Install (one time)
cd tests\playwright
npm install

# Run smoke tests
node tests\playwright\run.mjs settings
node tests\playwright\run.mjs onboarding
```

See [`tests/playwright/README.md`](playwright/README.md) for full details.

**Prerequisites:** Node ≥ 18, AutoHotkey v2, WebView2 Runtime.
**No `npx playwright install` needed** — attaches to existing WebView2 Chromium.

---

## (b) STT Regression — Whisper transcription harness

Validates WER against a baseline corpus and captures hallucination outputs.

```powershell
# Offline-assert-only mode (no API key needed, exits 0)
pwsh tests\transcription\run-stt-regression.ps1

# Live API mode (computes real WER)
$env:GROQ_API_KEY = "gsk_..."
pwsh tests\transcription\run-stt-regression.ps1
```

See [`tests/transcription/README.md`](transcription/README.md) for full details.

**Prerequisites:** PowerShell 7+. `GROQ_API_KEY` for live runs.
**Note:** Corpus currently uses synthetic placeholders. Run `fetch-corpus.ps1` to swap in real LibriSpeech + whisper-hallucinations clips (T2.6 owns full expansion).

---

## (c) AHK Live Runner

Starts QuickSay under AutoHotkey v2, tails the debug log, and prints state transitions.

```powershell
# Tray mode (indefinite, Ctrl+C to stop)
pwsh tests\live-runner.ps1

# Settings window mode, auto-stop after 30s
pwsh tests\live-runner.ps1 -Settings -DurationSeconds 30

# Compose with Playwright harness (enables CDP port 9222)
pwsh tests\live-runner.ps1 -TestMode -Settings
```

**Prerequisites:** PowerShell 7+, AutoHotkey v2 at `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`.

The runner:
1. Temporarily enables `debugLogging` in `config.json` (restored on exit)
2. Launches `QuickSay.ahk` via `AutoHotkey64.exe`
3. Tails `debug_log.txt` and prints state: RECORDING / PROCESSING / IDLE / ERROR
4. On Ctrl+C or `-DurationSeconds` timeout: kills the process tree, restores config

**Safety:** Never deletes user data. Only modifies `debugLogging` in `Development/config.json`, always restored on teardown.

---

## Harness composition

```
live-runner.ps1 -TestMode -Settings
    → sets WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS + QUICKSAY_TEST_MODE=1
    ↕ (CDP on port 9222)
run.mjs settings
    → connects over CDP, asserts DOM, screenshots
```

T1.2 and T1.4 use this combined mode for interactive UI debugging.
