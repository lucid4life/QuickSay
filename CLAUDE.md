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

# Build installer only (after manual compile)
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" setup.iss
```

`release.ps1` auto-detects the version from `localVersion` in `QuickSay.ahk` and updates all version strings across source files before compiling.

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
