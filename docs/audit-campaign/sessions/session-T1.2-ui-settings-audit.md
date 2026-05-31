# Session T1.2 — UI / Settings + WebView2 Bridge Audit (READ-ONLY)

> **Model:** Opus 4.7 [1m]
> **Effort:** xhigh
> **Switch commands:** `/model opus[1m]` then `/effort xhigh`
> **Branch:** `audit/T1.2-ui-settings-webview2`
> **Parallel-safe with:** T1.1, T1.3, T1.4 (different files, all read-only audits — open all four windows at once)
> **Depends on:** P0.2 (test harnesses + baseline — you drive the Playwright/CDP harness here)
> **Blocks:** T1.5 (clear-history race fix), T1.6 (version sync sweep), T1.7 (accessibility + responsive fixes)
>
> Before pasting this prompt: confirm your model is Opus 4.7 with 1M context (`/model opus[1m]`) and effort is `xhigh` (`/effort xhigh`). This audit holds three files (one large HTML, one large CSS, the settings-ui class) plus harness output in head simultaneously — the 1M window is why it is Opus[1m]. If you skip the flag, you will lose the cross-file bridge mapping mid-audit.

---

## Prompt to paste

You are performing a comprehensive, **read-only** audit of QuickSay's settings UI and the WebView2 bridge that connects the HTML front end to the AHK back end. **Make ZERO code changes this session.** The deliverable is a findings document with line citations and evidence; the fixes happen in T1.5, T1.6, and T1.7.

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2). The settings window is HTML/CSS/JS rendered inside an embedded Chromium (WebView2). Communication is bidirectional:
- **AHK → HTML:** `webview.PostWebMessageAsString(jsonString)`
- **HTML → AHK:** the HTML calls `window.chrome.webview.postMessage({action, ...})`; an `add_WebMessageReceived` handler in the AHK side parses the JSON `action` and dispatches.

The settings window is a **separate process** from the always-running tray process. When a setting changes, the settings process sends Windows message `0x5555` (`QuickSay_ConfigReloadMsg`) to the tray process to trigger a live config reload. **IPC target window is `"QuickSay_TrayMode ahk_class AutoHotkey"`** — confirmed in CLAUDE.md; flag any `PostMessage(0x5555)` that targets the wrong window title.

Working directory: `C:\QuickSay\Development\`.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — architecture, the WebView2 pattern, config system, `0x5555` IPC contract, the dual-function-sync gotcha (`GetDefaultModes()` lives in BOTH `QuickSay.ahk` and `lib/settings-ui.ahk`).
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign context; you update the Status Tracker at the end.
3. `docs/audit-campaign/findings/P0.2-baseline.md` — the verified baseline. It tells you which of the 6 flagged items are CONFIRMED, and how to run the Playwright/CDP harness you will drive in Phase 3.
4. `docs/audit-campaign/research/app-surface-inventory.md` — Category 1 (settings by tab), Category 9 (the ~33 WebView2 actions), Category 8 (Windows messages). Treat as a starting map to verify, NOT as fact.
5. `docs/audit-campaign/research/tooling-research.md` — §2 (the Playwright/CDP path) for how the harness drives the WebView2 UI.

### Scope

| File | Priority | Why |
|---|---|---|
| `lib/settings-ui.ahk` | **CRITICAL** | The `SettingsUI` class. The `add_WebMessageReceived` dispatcher, every action handler, the `0x5555` send sites, history pagination, statistics load, `GetDefaultModes()` (one of the two synced copies). |
| `gui/settings.html` | **CRITICAL** | The entire settings front end. Every `postMessage({action})` call, every tab, the guided tour JS, the history/stats rendering, dark-mode + responsive logic. |
| `gui/settings.css` | **HIGH** | Design tokens, dark-mode rules, responsive breakpoints. Where the accessibility + responsive findings live (owned by T1.7 to fix). |

**Forbidden** (owned by sibling sessions — do not audit, do not touch):
- `QuickSay.ahk` core recording/transcription engine → T1.1. **Exception:** you MAY read the tray-side ends of bridges that originate in settings — specifically the `0x5555` receive handler and the tray's history-write site — but only to trace the IPC/race surface, and you cite them as "cross-ref, owned by T1.1/T1.5". Do not audit unrelated parts of `QuickSay.ahk`.
- `setup.iss`, `release.ps1`, `signing/` → T1.3.
- `onboarding_ui.ahk`, `gui/onboarding.html`, `widget-overlay.ahk`, `sounds/`, dictionary code → T1.4. (The settings Dictionary *tab* HTML is yours; the dictionary regex-compile engine in `QuickSay.ahk` is T1.4's.)

### Phase 1 — Map the bridge (deep read)

Invoke `superpowers:systematic-debugging` for this phase.

Produce a complete, line-cited map of three things and present it to me before writing findings:

1. **The WebView2 action table.** Enumerate every `action` the HTML can send (search `gui/settings.html` for `postMessage(` and `action:`/`"action"`). The surface inventory lists ~33: `loadConfig, saveConfig, testGroqAPI, getAudioDevices, loadDictionary, saveDictionary, getHistoryCount, clearHistory, viewLogs, closeAfterSave, closeSettings, openUrl, importDictionary, exportDictionary, exportHistory, loadHistoryData, loadMoreHistory, loadStatisticsData, deleteHistoryFile, loadLegalDoc, loadModes, saveModes, setMode, previewSound, loadChangelog, markChangelogSeen, exportConfig, importConfig, testHotkey, startHotkeyCapture, stopHotkeyCapture, tourCompleted, clearStartTourFlag`. **Verify this list against both sides.** For each action build a row: `action name | sent from (settings.html:line) | handled in (settings-ui.ahk:line) | response shape | sends 0x5555? | persists to config?`.
2. **The response path.** For each action that returns data, trace the AHK → HTML reply (`PostWebMessageAsString`) and the HTML handler that consumes it. Note the response envelope (the inventory says `{result, data, error}` — verify).
3. **The `0x5555` send sites.** Every `PostMessage(0x5555, ...)` in `lib/settings-ui.ahk` — what triggers it (saveConfig, saveModes, setMode), what window it targets, and what the tray's receive handler does with it.

### Phase 2 — Findings categories

Apply each category to the mapped code. For EVERY finding: ID (`T1.2-001`, `T1.2-002`, …), severity (P0/P1/P2/P3), file:line citation, evidence (the actual code snippet), recommended fix, and an **owner-session tag** (`owned by T1.5` / `owned by T1.6` / `owned by T1.7` / `owned by T1.2-followup`). Every bullet gets either a finding or an explicit "no issue found — here is the evidence" entry. No hand-waving.

#### Category A — WebView2 bridge completeness

- [ ] **Each of the ~33 postMessage actions has a live handler.** Cross-reference the HTML send sites against the AHK dispatcher. Build the matrix.
- [ ] **Dead actions** — any `action` the HTML sends that has NO handler in `lib/settings-ui.ahk` (silent no-op; user clicks, nothing happens). Flag each.
- [ ] **Dead handlers** — any handler in `lib/settings-ui.ahk` for an action the HTML never sends (unreachable code). Flag each.
- [ ] **Malformed payload handling** — what happens if the JSON `action` is missing, unknown, or the payload is malformed? Does the dispatcher crash, silently swallow, or log? Trace the parse path.
- [ ] **Response correlation** — if two actions are in flight (e.g. `loadHistoryData` + `loadStatisticsData`), can responses get crossed? Is there any request ID, or does the HTML assume single-flight?
- [ ] **Injection surface** — does any action pass HTML-side string content into an AHK code path that runs it (file path, URL, shell)? Specifically scrutinize `openUrl`, `viewLogs`, `loadLegalDoc`, `deleteHistoryFile`, `importDictionary`, `importConfig`. Does `openUrl` validate the scheme (could it open `file://` or a local exe)?

#### Category B — settings ↔ tray IPC robustness

- [ ] **Correct IPC target.** Every `PostMessage(0x5555)` targets `"QuickSay_TrayMode ahk_class AutoHotkey"` — NOT `"QuickSay ahk_class AutoHotkey"`. Cite each send site and its target string. (CLAUDE.md gotcha — a wrong target means the tray never reloads.)
- [ ] **Tray-not-running.** If the user opens settings while the tray process is dead/crashed, what does a `0x5555` send do? Does the settings process detect the missing window, or silently drop the reload (so config changes never take effect until restart)?
- [ ] **Rapid-toggle.** Drive a checkbox on/off rapidly via the harness — does each toggle write config + send `0x5555`, and does the tray coalesce or thrash? Any debounce? Any chance of a write storm corrupting `config.json`?
- [ ] **Mutex coverage.** Does the settings process acquire the config mutex (`AcquireConfigLock()`) before every `config.json` read-modify-write, and use `AtomicWriteFile()`? Cite every write site. Cross-reference P0.2 baseline item 4. Flag any write that does neither.
- [ ] **Stale in-memory cache.** `lib/settings-ui.ahk` holds cached values (the baseline/T1.5 notes a `static _historyRetention` cache). Enumerate every `static` cache in the class and ask: is it invalidated when the tray broadcasts a config change back, or does the settings UI show stale values? (This is the cache-invalidation surface T1.5 will fix for history — find ALL of them, tag history's for T1.5 and any others for T1.6/T1.7.)
- [ ] **Clear-history race (the user-reported bug).** Trace the full path: HTML "Clear History" button → `clearHistory` action → settings-ui.ahk handler → file write → and the **tray-side deferred write** that re-introduces the cleared entries. Cite both ends (the tray write site is cross-ref owned by T1.5). This finding is the linchpin for T1.5 — make the trace airtight with line numbers so T1.5 starts from your evidence, not a re-investigation.

#### Category C — History pagination & correctness

- [ ] **Pagination contract.** Prior work set history to 100 entries per page. Confirm the page size, the `loadHistoryData` / `loadMoreHistory` cursor logic, and that paging never drops or duplicates an entry at a page boundary. Cite the pagination code in both HTML and AHK.
- [ ] **Large history.** With a multi-thousand-entry `history.json`, does the initial load block the UI (synchronous full read + parse)? Does pagination actually limit the parse, or parse-everything-then-slice? Measure with the harness if feasible.
- [ ] **`getHistoryCount` accuracy** — does the displayed count match the on-disk entry count? Cross-check against `historyRetention` (P0.2 confirmed whether retention is enforced — if it is orphaned, the count grows unbounded; note the UX implication).
- [ ] **Export/delete.** `exportHistory` and `deleteHistoryFile` — do they operate on the right file, handle a missing/locked file, and never corrupt `history.json`?
- [ ] **Empty + error states.** No history yet; corrupted `history.json`; `data/` missing — what does the UI render?

#### Category D — Statistics correctness

- [ ] **Read-only integrity.** Statistics load from `statistics.json` (per CLAUDE.md: `byApp, byDay, dailyStreak, averageWPM, totalDuration`). Does the UI ever WRITE statistics from the settings side? It should not — flag if it does.
- [ ] **Computation honesty.** Trace each displayed stat back to its source field. Any stat computed in JS that could be wrong (e.g. WPM dividing by zero, streak math across DST/timezone boundaries, day-rollover off-by-one)?
- [ ] **Missing/partial data.** What renders if `statistics.json` is absent, empty, or has a field the UI expects but the file lacks (schema drift between app versions)?

#### Category E — Dark mode + responsive

- [ ] **Dark mode coverage.** Toggle dark mode via the harness. Are there elements that don't recolor (hardcoded light-mode colors in `settings.css`)? Cite the rules. Tag for T1.7.
- [ ] **Contrast.** Spot-check text/background contrast in both themes against WCAG AA (4.5:1 for body text). Invoke the `wcag-audit-patterns` skill (activated in P0.1) for the systematic pass. Tag findings for T1.7.
- [ ] **Responsive breakpoints.** Resize the WebView2 page (the Playwright harness can set viewport) to narrow/short windows. Does the layout break — overlapping controls, clipped text, horizontal scrollbars, unreachable buttons? Cite breakpoints in `settings.css`. Tag for T1.7.
- [ ] **Keyboard navigation.** Tab order through the settings controls — is every interactive control reachable and operable by keyboard? Focus visible? (Accessibility — tag for T1.7.)
- [ ] **Guided tour.** The JS-driven tour (`tourCompleted` / `clearStartTourFlag` actions). Does it work in both themes, at small viewport, and does it correctly persist `tourCompleted`? Any step that points at an element that may not exist?

### Phase 3 — Live verification with the P0.2 Playwright harness

This is the part that separates "I think this is broken" from "I confirmed it." Use the harness from P0.2.

- Launch the settings UI via the harness (`node tests/playwright/run.mjs settings` and/or the reusable helpers it exports).
- For a representative sample of settings (at least: a checkbox like `autoPaste`, the hotkey capture, the sound-theme dropdown, a Modes change, Clear History), drive the control through Playwright and verify:
  1. The HTML fires the expected `postMessage` action (read the console / network or instrument the page).
  2. The change persists to `config.json` (read the file after the action).
  3. A `0x5555` is sent to the correct tray window (observe via the P0.2 `live-runner.ps1` tailing `debug.txt` for the reload, if `debugLogging` logs the reload — run the two harnesses together).
- For the **clear-history race**: with QuickSay running under `live-runner.ps1`, do a transcription (or simulate the deferred-write timing per the P0.2 baseline notes), then clear history via the harness, and observe whether entries reappear. Capture the exact reproduction recipe (a human must be able to follow it) — T1.5 needs it.
- Screenshot dark mode + a narrow viewport for the T1.7 findings.

For each suspected bug, write the smallest reproduction recipe.

### Done When

The following are all true. Do not declare complete without verifying each.

- [ ] `docs/audit-campaign/findings/T1.2-ui-settings.md` written. Each finding has: ID, severity, file:line, evidence snippet, recommended fix, owner-session tag.
- [ ] The **WebView2 action matrix** (all ~33 actions × send-site / handler / response / 0x5555 / persists) is at the top of the findings doc. Every dead action and dead handler is explicitly listed (or "none found").
- [ ] Every Category A–E bullet has either a finding or an explicit "no issue, here's the evidence" entry.
- [ ] The **clear-history race** has an airtight, line-cited trace and a reproduction recipe, tagged `owned by T1.5`.
- [ ] Every `PostMessage(0x5555)` send site is confirmed to target the correct tray window, with citations.
- [ ] Dark-mode + responsive + a11y findings are tagged `owned by T1.7` with cited CSS rules.
- [ ] Version-string findings surfaced in the UI (e.g. About tab `lastSeenVersion`) are tagged `owned by T1.6`.
- [ ] Live verification ran: harness drove at least the 5 sample controls + the clear-history repro; screenshots captured.
- [ ] **Zero changes to source.** `git diff` shows only the new findings file.
- [ ] MASTER-PLAN.md Status Tracker updated: T1.2 → ✅ done, with total finding count + P0/P1 count.
- [ ] Branch `audit/T1.2-ui-settings-webview2` committed. Title: `T1.2 — UI/settings + WebView2 bridge audit (N total, N P0, N P1)`. PR opened against `main`.

### What NOT to do

- ❌ Do not modify any source file. This is read-only. Recommend fixes; do not write them.
- ❌ Do not touch the Forbidden list. You may *read* the tray-side IPC receiver and history-write site to trace bridges, but cite them as cross-ref and do not audit unrelated `QuickSay.ahk`.
- ❌ Do not audit the dictionary regex-compile engine (`QuickSay.ahk` `CompileDictionaryPattern`/`ApplyDictionary`) — that is T1.4. The Dictionary *tab* HTML/JS is yours.
- ❌ Do not fix the `GetDefaultModes()` dual-sync drift if you find it — document it, tag `owned by T1.6`. (CLAUDE.md: both copies must stay in sync.)
- ❌ Do not skip Phase 3 live verification because the read got long. The harness is the whole reason this depends on P0.2.
- ❌ Do not present findings without the action matrix at the top.
- ❌ Do not write fixes for dark-mode/responsive/a11y — those are T1.7's; you only locate and cite.

### Estimated time

Phase 1 (bridge mapping): ~45-60 min. Phase 2 (findings across A–E): ~60-90 min. Phase 3 (live harness verification): ~30-45 min. **Total wall-clock: ~2.5-3.5 hours.**

### When you're done

Report back with:
- Total finding count, P0 count, P1 count.
- The WebView2 action matrix summary: how many actions, how many dead actions, how many dead handlers.
- The 3 most important findings in plain English.
- The clear-history race reproduction recipe in 3-4 steps (T1.5 inherits this verbatim).
- Any cross-session dependency you discovered (e.g. "T1.7 must coordinate with T1.6 because the About tab version display is both a responsive issue and a version-sync issue").
- Confirmation MASTER-PLAN.md Status Tracker is updated and the PR is open.
