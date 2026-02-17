# QuickSay App Development

This workspace is for developing the QuickSay desktop application.

- Language: AutoHotkey v2
- Architecture: AHK + WebView2 for onboarding wizard
- APIs: Groq Whisper API (transcription), GPT-OSS 20B via Groq (text cleanup)
- Build: Compiled AHK → .exe, code-signed for SmartScreen
- Focus: Features, bugs, DPI scaling, hotkey system, settings menu, onboarding flow

Do not generate marketing copy, website HTML/CSS, N8N workflows, or social media content here.
Focus on application code, UX improvements, testing, and technical documentation.

## Critical: Dual Function Sync

`GetDefaultModes()` exists in BOTH `QuickSay.ahk` AND `lib/settings-ui.ahk`. These contain the 4 preset mode prompts (Standard, Email, Code, Casual) and MUST always be kept in sync. When updating mode prompts, update both files.

## UX Priorities

**The Dad Test:** Could a non-technical person use QuickSay without calling for help?
- Replace "API key" jargon with plain English ("free AI account" or "connection key")
- Replace "LLM cleanup" with "AI text cleanup"
- Add hotkey practice during onboarding (currently missing)
- Provide clear error recovery steps (not just "invalid API key")

**Critical friction points:**
1. "API key" is the single biggest barrier for non-technical users
2. No hotkey practice during setup — users released with no muscle memory
3. Short recording (<500ms) gives zero feedback — user may think app is broken
4. Error TrayTips auto-dismiss and are easy to miss

**File locations:**
- Main engine: `QuickSay.ahk`
- Settings UI: `settings_ui.ahk` + `lib/settings-ui.ahk` + `gui/settings.html`
- Onboarding: `onboarding_ui.ahk` + `gui/onboarding.html`
- HTTP/encoding: `lib/http.ahk` (shared `Utf8Decode()` and `HttpPostFile()`)
- Installed app data: `%LOCALAPPDATA%\Programs\QuickSay Beta\data\` (history, stats — separate from dev `data/`)
