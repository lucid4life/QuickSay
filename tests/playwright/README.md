# QuickSay — Playwright/CDP Test Harness

Drives the QuickSay **settings** and **onboarding** WebView2 windows via the
Chrome DevTools Protocol (CDP). Attaches to the existing WebView2 Chromium —
**no separate browser download required**.

Built in P0.2. Consumed by T1.2 (UI/settings audit) and T1.4 (onboarding audit).

---

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Node.js | ≥ 18 | `node --version` |
| npm | any | bundled with Node |
| AutoHotkey v2 | v2.0+ | must be at `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe` |
| Microsoft Edge WebView2 Runtime | any | pre-installed on Win11; get from microsoft.com/edge/webview2 |

## Install

```powershell
cd tests\playwright
npm install
```

This installs the Playwright API library. Do **NOT** run `npx playwright install` —
CDP connects to the already-installed WebView2 Chromium, no local Chromium needed.

---

## One-command invocations

```powershell
# Test the settings window
node tests\playwright\run.mjs settings

# Test the onboarding wizard
node tests\playwright\run.mjs onboarding

# Both (npm shortcut)
cd tests\playwright && npm test
```

Exit `0` = pass. Exit non-zero = fail with a readable error message.

Screenshots land in `tests\playwright\artifacts\<target>-smoke.png`.

---

## How it works

1. **Launches** the AHK process with two env vars injected into its environment:
   - `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222`
     → tells WebView2 to expose the CDP endpoint on port 9222
   - `WEBVIEW2_USER_DATA_FOLDER=<tempdir>`
     → isolated profile so test runs never cross-contaminate
2. **Polls** `http://localhost:9222/json` until a page appears (timeout 15s).
3. **Connects** via `chromium.connectOverCDP('http://localhost:9222')`.
4. **Asserts** a known element:
   - `settings` → `<h2>General Settings</h2>` visible
   - `onboarding` → `<h1>Welcome to QuickSay</h1>` visible
5. **Screenshots** the window to `artifacts/<target>-smoke.png`.
6. **Tears down**: closes CDP, kills the AHK child, removes the temp user-data folder.

---

## The env-var injection approach

WebView2 respects `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` if it is set in the
**process environment before `CoreWebView2Environment` is created**. This is
Microsoft's documented approach. QuickSay's `lib/WebView2.ahk` wrapper calls
`CreateCoreWebView2EnvironmentWithOptions` at initialization time, so the env
var set in the parent Node process is inherited by the AHK child and picked up
before that call.

If this env-var path fails (e.g., a future AHK refactor creates the environment
before inheriting the env), see the "one allowed source touch" section in
`docs/audit-campaign/findings/P0.2-baseline.md`.

---

## Reusable exports

```js
import { launchUI, pollForCDP, connect, screenshot, teardown, DEV_DIR, DEBUG_PORT } from './run.mjs';
```

T1.2 and T1.4 import these helpers to write deeper UI tests without re-implementing
the CDP connect loop.

---

## Known limitations

- Requires the AHK source files + untracked libs (`lib/WebView2.ahk`, `lib/JSON.ahk`, etc.)
  to be present in `Development/`. See CLAUDE.md "Untracked Library Files" for the
  copy-from-installed-app procedure.
- The settings window will attempt to read `config.json`. If the file is malformed or
  missing fields, the UI still loads but the AHK side may log errors.
- The onboarding wizard opens unconditionally (no `onboarding_done` guard in
  `onboarding_ui.ahk`) — safe for repeated test runs.
- Allow ~5s after the AHK process starts before the WebView2 COM init completes.
  The 15s boot timeout covers even slow machines.
- If another QuickSay instance is already running on port 9222, the CDP connect
  may attach to the wrong window. Ensure no other QuickSay processes are running
  when using this harness.
