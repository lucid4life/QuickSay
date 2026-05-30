# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

QuickSay is a Windows speech-to-text dictation app. Hold `Ctrl+Win`, speak, release — transcript typed at the cursor in any app. Built in AutoHotkey v2 with WebView2 for GUI, Groq Whisper API for transcription, GPT-OSS 20B for optional AI text cleanup.

**Scope of this repo:** Application code only (`QuickSay.ahk`, `lib/`, `gui/`, `onboarding_ui.ahk`, etc.). Do not generate marketing copy, website HTML/CSS, N8N workflows, or social media content here.

## Build Commands

```powershell
# Compile a single .ahk file to .exe (run from repo root)
& "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe" /in QuickSay.ahk /out QuickSay.exe

# Full release pipeline (version bump → compile → sign → installer → GitHub release)
.\release.ps1                  # auto-increments patch version
.\release.ps1 -Version 1.9.0   # specific version
.\release.ps1 -Major           # bump major
.\release.ps1 -Minor           # bump minor

# Version-sync tooling (no build) — see "Version Sync Regime" below
.\release.ps1 -CheckSync       # verify all files match VERSION (read-only; exit 0 ok / 1 drift)
.\release.ps1 -SyncOnly        # propagate VERSION to every file (no compile/sign/publish)

# Build installer only (after manual compile)
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" setup.iss
```

`release.ps1` reads the canonical version from `Development/VERSION` (single source of truth) and propagates it to every version string in the codebase before compiling. See **Version Sync Regime** below.

## Version Sync Regime (T1.6)

The version is spelled in ~30 places across `QuickSay.ahk`, `onboarding_ui.ahk`, `settings_ui.ahk`, `lib/settings-ui.ahk`, `setup.iss`, and `gui/settings.html` (plus the website). To stop these from drifting:

- **`Development/VERSION`** is the **single source of truth** — one line, 3-part semver (e.g. `1.9.0`). `release.ps1` reads it via `Get-CurrentVersion` (falling back to `QuickSay.ahk`'s `localVersion` with a warning only if `VERSION` is missing). A version bump writes `VERSION` first, then propagates.
- **One shared `$VersionTargets` table** in `release.ps1` drives BOTH the rewrite path (STEP 1) and the verification gate. Add a new version location in one place and it is both rewritten and checked.
- **`.\release.ps1 -CheckSync`** — read-only gate. Verifies every tracked location matches `VERSION`, normalizing 3-part vs 4-part (`1.9.0` ≡ `1.9.0.0`) and comparing shortVer (`1.9`) locations on major.minor only. Collects **all** drift in one pass. **Exit `0`** when clean, **`1`** on any drift. Also fails on any forbidden `X.Y.Z-beta` version suffix in tracked files (the product name "QuickSay Beta" is fine; only the *version* suffix is banned).
- **`.\release.ps1 -SyncOnly`** — propagates `VERSION` to every file (rewrite + assertion) with **no** compile/sign/publish. This is the fix to run when `-CheckSync` reports drift. Bare `-SyncOnly` propagates the *current* `VERSION` (no bump); add `-Version X.Y.Z` to set a new value first.
- **`release.ps1` STEP 1b** re-asserts sync after every rewrite and **aborts the build** if any location failed to update (no silent warn-and-continue).

### Pre-commit hook (local enforcement)

A version-sync gate lives at `Development/.githooks/pre-commit`. **Activate it once** (from the Development repo root):

```powershell
git config core.hooksPath .githooks
```

It runs `release.ps1 -CheckSync` and **aborts the commit** on drift. Emergency bypass (drift *will* ship if you use it):

```powershell
$env:QUICKSAY_SKIP_VERSION_CHECK = "1"   # then git commit; unset afterward
```

### Website (separate repo) — warning-only

The website (`C:\QuickSay\Website\`, a separate git repo) displays the version in `Footer.astro` and `beta/getting-started.astro`. `-CheckSync` verifies these **only if the website path is reachable**, and treats unreachable/drifted website targets as **warnings, not failures** — so the Development repo checks out and gates standalone. The website is updated + deployed separately (`release.ps1` STEP 7 + a manual `wrangler` deploy); never committed from the Development repo.

> `Development/config.example.json` `lastSeenVersion` and `data/changelog.json` entries are intentionally **excluded** from the equality gate: the former is a per-user runtime field (ships empty), the latter is a historical record that legitimately lags the prepared version.

## Architecture

### Process Model

Two processes at runtime:
1. **`QuickSay.exe`** (from `QuickSay.ahk`) — permanent tray process, owns the global hotkey and recording engine. Launched with `--settings` flag to open the settings window instead (same binary, mode-switched at line 53).
2. **`QuickSay-Setup.exe`** (from `onboarding_ui.ahk`) — first-run wizard, launched by the installer on fresh install.

### Recording → Transcription Flow

`StartRecording()` → MCI or FFmpeg capture → `StopAndProcess()`:
1. WAV captured via Windows MCI (default mic) or `ffmpeg -f dshow` (named device)
2. `HttpPostFile()` POSTs to Groq Whisper (`/openai/v1/audio/transcriptions`)
3. Custom dictionary regex replacements applied
4. If `enableLLMCleanup=1`: POST to Groq LLM API with the active mode prompt
5. `SendInput` types result at cursor; history/stats written to `data/`

Minimum recording: 500ms. If shorter, gives feedback instead of calling API. Max: 5 minutes (auto-stop timer).

### WebView2 UI Pattern

Both settings and onboarding use embedded Chromium (WebView2) for HTML/CSS/JS UI. Communication is bidirectional:
- AHK → HTML: `webview.PostWebMessageAsString(jsonString)`
- HTML → AHK: `add_WebMessageReceived` handler parses JSON action payloads

### Config System

`config.json` is loaded at startup by `LoadConfig()`. The settings window sends Windows message `0x5555` to the tray process to trigger a live reload. The Groq API key is encrypted at rest using Windows DPAPI (`lib/dpapi.ahk`) — never stored in plaintext.

Key config fields: `groqApiKey`, `sttModel`, `llmModel`, `hotkey`, `hotkeyMode` (`hold`/`tap`), `enableLLMCleanup`, `currentMode`, `contextAwareModes`, `audioDevice`, `historyRetention`.

## Critical: Dual Function Sync

`GetDefaultModes()` exists in **BOTH** `QuickSay.ahk` AND `lib/settings-ui.ahk`. These contain the 4 preset mode prompts (Standard, Email, Code, Casual) and **must always be kept in sync**. When updating any mode prompt, update both files.

Context-aware mode switching (`GetContextModeId()`) auto-selects a mode based on the foreground window process name (e.g., `code.exe` → Code mode, `OUTLOOK.EXE` → Email mode).

## File Map

| File | Role |
|---|---|
| `QuickSay.ahk` | Main engine: tray icon, hotkey, recording loop, transcription, typing |
| `lib/settings-ui.ahk` | `SettingsUI` class + `GetDefaultModes()` (shared by both processes) |
| `lib/http.ahk` | `HttpPostFile()` multipart POST and `Utf8Decode()` — used by both processes |
| `settings_ui.ahk` | Thin launcher that calls `SettingsUI.Show()` |
| `onboarding_ui.ahk` | First-run wizard (WebView2) |
| `widget-overlay.ahk` | Floating recording widget |
| `gui/settings.html` | Settings UI rendered in WebView2 |
| `gui/onboarding.html` | Onboarding wizard UI |
| `setup.iss` | Inno Setup installer definition |
| `release.ps1` | Full release pipeline |
| `config.example.json` | All config keys with defaults |

**Installed app data** (history, stats) lives at `%LOCALAPPDATA%\Programs\QuickSay Beta\data\` — separate from the dev `data/` folder.

## UX Priorities

**The Dad Test:** Could a non-technical person use QuickSay without calling for help?
- Replace "API key" jargon with plain English ("free AI account" or "connection key")
- Replace "LLM cleanup" with "AI text cleanup"
- Provide clear error recovery steps (not just "invalid API key")

**Known friction points to fix:**
1. "API key" is the single biggest barrier for non-technical users
2. No hotkey practice during setup — users released with no muscle memory
3. Short recording (<500ms) gives zero feedback — user may think app is broken
4. Error TrayTips auto-dismiss and are easy to miss

## FFmpeg Note

FFmpeg is bundled in the installer for non-default mic support (Windows MCI only captures the default device). Named device capture uses `ffmpeg -f dshow -i audio="<device>"`. The `audioDevice` config value is the DirectShow device name string.
