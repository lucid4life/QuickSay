# Session T1.7 — Accessibility + Multi-Monitor Safety + Hotkey Conflict Detection (FIX)

> **Model:** Sonnet 4.6
> **Effort:** high
> **Switch commands:** `/model sonnet` then `/effort high`
> **Branch:** `audit/T1.7-a11y-multimon-hotkey`
> **Parallel-safe with:** T1.5, T1.6, and all of Track 2 (you touch UI + widget/overlay + hotkey-registration surface; T1.5 owns history, T1.6 owns version strings — no overlap if you stay in scope)
> **Depends on:** T1.2 findings (`docs/audit-campaign/findings/T1.2-ui-settings-webview2.md` — the UI/WebView2 audit flagged the a11y gaps and the multi-monitor repositioning bug). Soft-depends on P0.2 (the Playwright/CDP harness drives axe-core; the multi-monitor harness exists there too).
> **Blocks:** nothing (leaf fix).
>
> Before pasting this prompt: confirm `/model sonnet` and `/effort high`. Three bounded, independent fixes — do them in the order below and verify each before moving on. Do NOT let scope creep turn this into a UI rewrite.

---

## Prompt to paste

You are shipping three **bounded, independent** hardening fixes that a paid product needs but the beta skipped:

- **(a) WCAG basics** in the settings UI — keyboard navigation, visible focus indicators, ARIA labeling, and color contrast.
- **(b) Multi-monitor safety** for the floating widget and recording overlay — when a monitor is unplugged/rearranged, the widget and overlay must snap back to a valid, visible position instead of stranding off-screen.
- **(c) Hotkey conflict detection** at registration — if `Ctrl+Win` (or the user's chosen hotkey) is already claimed by Windows or another app, warn the user during onboarding / on registration failure with a clear recovery path.

Each fix is self-contained. Treat them as three mini-sessions sharing one branch.

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2). The settings and onboarding UIs are HTML/CSS/JS rendered in an embedded Chromium (WebView2). The floating widget (`widget-overlay.ahk`) is a 44×44 draggable circle whose position is persisted in config as `widgetX`/`widgetY`. The recording overlay (`lib/web-overlay.ahk`) is a GDI+ layered window that renders an audio-reactive waveform. The global hotkey is registered in `QuickSay.ahk` (`RegisterHotkey()` ~line 2432) and there's already a `WM_DISPLAYCHANGE` handler registered (`OnMessage(0x7E, OnDisplayChange)` ~line 200) — confirm what it currently does.

Working directory: `C:\QuickSay\Development\`.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — file map, IPC model (`0x5555` config reload, `0x7E` WM_DISPLAYCHANGE for overlay repositioning), widget/overlay descriptions, UX Priorities ("The Dad Test").
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign context, Status Tracker (update at end).
3. `docs/audit-campaign/findings/T1.2-ui-settings-webview2.md` — every finding tagged "owned by T1.7" (a11y gaps, focus traps, the multi-monitor stranding bug, hotkey-failure UX). Copy each into a scratchpad before you start.
4. `docs/audit-campaign/research/tooling-research.md` — §2 (Playwright over CDP for WebView2 — the harness you'll run axe-core through; `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222`).
5. The P0.2 harness: `Development/tests/playwright/` (CDP runner) and `Development/tests/live-runner.ps1` (AHK live runner) — you'll extend these, not rebuild them.

### Scope — files you may modify

| File | Fix(es) | Why |
|---|---|---|
| `Development/gui/settings.html` | (a) | Add ARIA roles/labels, `tabindex` order, skip-links, form-control labeling |
| `Development/gui/settings.css` | (a) | Visible `:focus-visible` indicators, contrast fixes, respect `prefers-reduced-motion` |
| `Development/widget-overlay.ahk` | (b) | Clamp `widgetX`/`widgetY` to a valid monitor on display change; reset to safe default if unreachable |
| `Development/lib/web-overlay.ahk` | (b) | Reposition overlay to the active monitor on display change; never render off all screens |
| `Development/QuickSay.ahk` | (b),(c) | `OnDisplayChange` (0x7E) handler coordination; `RegisterHotkey()` conflict detection + warning |
| `Development/onboarding_ui.ahk` | (c) | Surface the hotkey-conflict warning during first-run setup |
| `Development/gui/onboarding.html` | (c) | Onboarding warning UI (only if the conflict surfaces here) |
| `Development/tests/playwright/*` | (a) | axe-core run against settings UI (extend the P0.2 harness) |
| `Development/tests/multimon/*` | (b) | **CREATE** — multi-monitor reposition test using P0.2's display-change harness |

**Forbidden** (other sessions' surface):
- `gui/paywall.html`, `gui/paywall.css`, `lib/license.ahk` → T2.3
- `lib/settings-ui.ahk` history/retention logic → T1.5 (you MAY touch settings-ui.ahk ONLY for the `0x5555`/a11y wiring if strictly needed, but prefer to keep a11y in HTML/CSS; coordinate if T1.5 is mid-flight)
- `setup.iss`, `release.ps1`, `Development/VERSION` → T1.3, T1.6
- `dictionary.json`, `sounds/` → T1.4
- Crash reporting / Sentry → T2.4

### Phase 0 — Sync + read findings

```powershell
git fetch origin
git checkout -b audit/T1.7-a11y-multimon-hotkey origin/main
```

Read `docs/audit-campaign/findings/T1.2-ui-settings-webview2.md`. If it's not yet ✅ in the Status Tracker, you can still proceed (T1.2 is a soft dependency for context, not a hard blocker — the three fixes are well-specified here), but prefer to wait for it so you're fixing the exact issues it found rather than guessing. Extract every T1.7-owned finding into a scratchpad.

---

## FIX (a) — WCAG basics in the settings UI

Invoke the `accessibility` skill for this fix.

### a1 — Baseline audit (axe-core via the P0.2 Playwright/CDP harness)

The settings UI runs in WebView2. Per tooling-research §2, drive it via Playwright over CDP:

1. Launch QuickSay in test mode with the remote debugging port (the P0.2 harness already does this — `QUICKSAY_TEST_MODE=1` → sets `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222`). Open the settings window (`--settings` flag).
2. `connectOverCDP('http://localhost:9222')`, grab the settings page.
3. Inject and run **axe-core** against the settings DOM. Capture the violations JSON.

Record the baseline violation count by severity (critical / serious / moderate / minor) before any fix. This is your before/after evidence.

### a2 — Keyboard navigation + focus order

- Every interactive control (buttons, toggles, dropdowns, text inputs, tab navigation, the guided-tour controls) must be reachable by `Tab` in a logical order and operable by `Enter`/`Space`.
- No keyboard traps: `Tab` must cycle through and `Shift+Tab` must reverse without getting stuck (the guided-tour overlay and any modal are the prime suspects — verify they release focus).
- Add a "skip to main content" affordance if the sidebar nav is long.
- The settings tabs (sidebar) must be navigable with arrow keys per the ARIA tablist pattern, or at minimum Tab + Enter.

### a3 — Visible focus indicators

- In `settings.css`, add a clearly visible `:focus-visible` outline (not just the browser default, which WebView2 may suppress). Use the existing design-token palette — an outline with sufficient contrast against the control's background (≥3:1 against adjacent colors).
- Do NOT remove focus outlines anywhere (`outline: none` without a replacement is a WCAG failure — grep for it and fix any instances).

### a4 — ARIA labeling

- Icon-only buttons get `aria-label`.
- Toggles get `role="switch"` + `aria-checked` (or use native `<input type="checkbox">` properly labeled).
- Form inputs get associated `<label>` (via `for`/`id`) or `aria-label`.
- The recording-state / status regions that update live get `aria-live="polite"`.
- Tabs get `role="tab"` / `role="tabpanel"` / `aria-selected` if you implement the tablist pattern.

### a5 — Color contrast

- Run the axe contrast check. Fix any text/background pair below WCAG AA (4.5:1 for normal text, 3:1 for large text and UI components).
- Adjust **only** the failing tokens, and adjust them minimally — keep the visual design intact. Record each token you changed (old → new hex) in a short note.

### a6 — Reduced motion

- Wrap the audio-reactive / animated CSS in `@media (prefers-reduced-motion: reduce)` so motion-sensitive users get a static fallback. (The overlay waveform is GDI+ not CSS, so this applies to any CSS animations in the settings UI — tour highlights, transitions.)

### a7 — Re-run axe → 0 critical

Re-run the axe-core scan. **Zero critical violations** is the gate. Serious violations should be driven to zero too where reasonable; document any you consciously defer with justification.

---

## FIX (b) — Multi-monitor safety (widget + overlay)

Invoke `superpowers:systematic-debugging` for the root-cause of the stranding bug.

### b1 — Understand the current state

- Read `RegisterHotkey()` neighbors and the `OnMessage(0x7E, OnDisplayChange)` handler (~line 200 in `QuickSay.ahk`). Document exactly what `OnDisplayChange` does today: does it reposition the overlay? The widget? Neither?
- Read `widget-overlay.ahk` — how `widgetX`/`widgetY` are loaded (config `widget_x`/`widget_y`, see `QuickSay.ahk` ~line 1667-1670) and applied to the window position.
- Read `lib/web-overlay.ahk` — how the overlay computes its position (centered on a monitor? fixed coords?).

### b2 — The invariant

**After any `WM_DISPLAYCHANGE` (0x7E), both the widget and the overlay must be fully visible on a currently-connected monitor.** If their persisted/intended position is now off all screens (monitor unplugged, resolution shrank, arrangement changed), they snap to a safe default.

Define "safe default" concretely:
- **Widget:** if `(widgetX, widgetY)` (the 44×44 rect) does not fully fit within the union of current monitor work areas, reset to a corner of the **primary** monitor's work area (e.g. bottom-right with a margin), and persist the new `widgetX`/`widgetY` via the existing config-write path (atomic + mutex). Do not silently lose the user's chosen position if it's still valid — only move it when it's actually unreachable.
- **Overlay:** recompute its position relative to the **active** monitor (the one with the foreground window, or primary as fallback) on every display change, so it's always centered/visible where the user is working.

### b3 — Implement clamping

- Add a helper `ClampRectToMonitors(x, y, w, h)` that returns a position guaranteed visible. Use `SysGet`/`MonitorGet`/`MonitorGetWorkArea` (AHK v2) to enumerate monitor work areas. Prefer keeping the rect on the monitor it's *mostly* on; only fall back to primary if it fits on none.
- Wire the widget repositioning into `OnDisplayChange` (0x7E). The overlay repositioning likely already hangs off 0x7E (CLAUDE.md says 0x7E is "for overlay repositioning") — verify it actually works and extend it to cover the widget.
- Guard against the display-change firing mid-recording: repositioning the overlay during an active recording must not crash or visually glitch the waveform. Test the unplug-while-recording path.
- All position writes use the existing atomic-write + config-mutex path. Wrap in `try/catch` — a failed reposition must never crash the tray process or block a recording.

### b4 — Multi-monitor regression test

Create `Development/tests/multimon/` using the P0.2 display-change harness. Since you can't physically unplug a monitor in CI, drive it via:
- A test shim that calls `ClampRectToMonitors` directly with synthetic monitor layouts (single monitor at 1920×1080, dual side-by-side, the user's widget at coords only valid on the now-removed second monitor) and asserts the clamped output is inside a current work area.
- A live-harness step (P0.2 `live-runner.ps1`) that posts a synthetic `WM_DISPLAYCHANGE` (`PostMessage 0x7E` to the tray window — target `"QuickSay_TrayMode ahk_class AutoHotkey"` per CLAUDE.md) after shimming the widget to off-screen coords in config, then reads back `widgetX`/`widgetY` to assert they were clamped to a visible position.

Tests:
1. Widget at `(3000, 500)` with only a single 1920×1080 monitor → clamped onto the primary work area.
2. Widget at `(100, 100)` with that position valid → **unchanged** (don't move valid positions).
3. Widget rect partially off the bottom edge → clamped fully on-screen.
4. Overlay position recomputed to active monitor on display change (assert it's within some current monitor's bounds).
5. Display change posted mid-"recording" (simulate via the harness) → no crash, recording state intact.

---

## FIX (c) — Hotkey conflict detection

Invoke `superpowers:systematic-debugging`.

### c1 — Current behavior

`RegisterHotkey()` (~line 2432) already has a `try/catch` around `Hotkey(newHotkey, ...)` and on failure shows a TrayTip: *"Your custom hotkey could not be registered (it may conflict with another app). Using default: Ctrl+Win..."* (~line 2461). Two gaps:

1. The **default** `Ctrl+Win` (`^LWin`) path doesn't detect conflicts — if Windows or another app has already claimed `Ctrl+Win`, registration may *succeed* in AHK but the key never fires for QuickSay, OR it silently steals it. There's no proactive warning.
2. **Onboarding** doesn't test the hotkey at all (a known friction point in CLAUDE.md UX Priorities: "No hotkey practice during setup").

### c2 — Detect conflict at registration

- After registering the hotkey, **verify it's actually live**. The cleanest signal in AHK v2: the `Hotkey()` call throws on hard failure (already caught). For soft conflicts (another app also bound it), AHK can't always tell — so add a **best-effort** check:
  - Known Windows-reserved combos to warn about (e.g. `Win+L` lock, `Ctrl+Win+arrows` virtual desktop, `Win+D`). If the user's chosen hotkey base collides with a documented Windows system shortcut, warn at registration.
  - Keep this a **warning**, not a hard block — `Ctrl+Win` itself is QuickSay's default and is generally free, but document the known collisions (e.g. some keyboard software, PowerToys, Discord push-to-talk).
- TrayTip warnings auto-dismiss and are easy to miss (CLAUDE.md UX friction #4). For the **conflict-on-registration** case, additionally write a persistent indicator the user can find later (e.g. a flag the settings UI reads to show a "your hotkey may be in conflict — change it here" banner). Keep this minimal — a config field + a settings-UI read.

### c3 — Onboarding hotkey check

- During onboarding (`onboarding_ui.ahk` / `gui/onboarding.html`), add a step that registers the hotkey and confirms it fires (the existing "practice the hotkey" friction point). If it doesn't fire within a short window, surface the conflict warning with a "pick a different hotkey" affordance.
- Keep the onboarding change small and inside the existing wizard flow — do NOT redesign onboarding. If onboarding already has a hotkey step, just add the conflict check + warning to it.

### c4 — Recovery path (Dad Test)

Every warning must tell the user **what to do**, not just that something is wrong: "Ctrl+Win didn't respond — another app may be using it. Open Settings → Hotkey to choose a different shortcut." Per CLAUDE.md UX Priorities, plain English, clear recovery.

---

## Phase Final — Verification

Invoke `superpowers:verification-before-completion`. Produce real evidence per gate.

**Fix (a) — a11y:**
- [ ] axe-core re-run output: **0 critical** violations (paste before/after counts).
- [ ] Manual keyboard pass: open settings, navigate every tab and every control with Tab/Shift+Tab/Enter/Space/arrows end-to-end with no trap. Describe the path.
- [ ] Focus indicators visible on every control (screenshot or description).
- [ ] Contrast: every fixed token listed (old → new hex) and re-checked passing AA.

**Fix (b) — multi-monitor:**
- [ ] `Development/tests/multimon/` tests all pass (paste runner output).
- [ ] Manual or harness smoke: widget shimmed to off-screen coords → 0x7E posted → widget reappears on a visible monitor and `widgetX`/`widgetY` persisted to a valid value.
- [ ] Valid widget position is NOT moved by a display change (no false repositioning).
- [ ] Unplug-while-recording path does not crash (harness-simulated).

**Fix (c) — hotkey:**
- [ ] Registration conflict warning fires with a clear recovery message (simulate by temporarily binding `^LWin` to a no-op elsewhere, or by forcing the catch path).
- [ ] Onboarding hotkey check surfaces a warning when the hotkey doesn't fire.
- [ ] No regression: with a free hotkey, registration is silent and dictation works (hold hotkey, speak, release, paste).

**Cross-cutting:**
- [ ] No regression in core dictation across all three fixes.
- [ ] Invoke `code-review` on the full diff; address every P0/P1.

### Done When

- [ ] Settings UI is fully tab-navigable end-to-end with visible focus and no keyboard trap.
- [ ] axe-core reports **0 critical** violations against the settings UI.
- [ ] All contrast pairs meet WCAG AA; reduced-motion respected.
- [ ] Widget + overlay reposition to a valid monitor on `WM_DISPLAYCHANGE`; off-screen positions reset to a safe default and persist; valid positions are left alone.
- [ ] `Development/tests/multimon/` exists with 5 passing tests.
- [ ] Hotkey conflict detection warns at registration AND during onboarding, each with a plain-English recovery path.
- [ ] No regression in dictation, overlay rendering, or widget drag.
- [ ] `code-review` run; P0/P1 addressed.
- [ ] Branch `audit/T1.7-a11y-multimon-hotkey` committed; PR opened against `main`.
- [ ] MASTER-PLAN.md Status Tracker updated: `T1.7 — Accessibility + multi-monitor + hotkey conflict fixes` → ✅ done.

### What NOT to do

- ❌ Do not redesign the settings UI or onboarding. These are targeted hardening fixes, not a visual refresh. Reuse existing design tokens.
- ❌ Do not remove any focus outline without an equally-or-more visible replacement.
- ❌ Do not change the widget's drag behavior or its 44×44 size — only its *bounds clamping* on display change.
- ❌ Do not change the audio-reactive overlay's visual design — only its *positioning* logic.
- ❌ Do not make the hotkey conflict a **hard block**. `Ctrl+Win` is the default and usually fine — over-warning trains users to ignore warnings. Warn only on real/known collisions, always with a fix.
- ❌ Do not touch history/retention (`lib/settings-ui.ahk` history logic) — that's T1.5. Touch settings-ui.ahk only if strictly required for a11y/`0x5555` wiring, and coordinate with T1.5's branch.
- ❌ Do not touch version strings, `setup.iss`, or `release.ps1` — that's T1.6.
- ❌ Do not introduce a new background process or thread for monitor watching — use the existing `WM_DISPLAYCHANGE` (0x7E) message.
- ❌ Do not refactor unrelated UI/widget code "while you're in there." File a `spawn_task` flag.

### Estimated time

Phase 0 (sync + findings): 20 min. Fix (a) a11y: 90–120 min. Fix (b) multi-monitor: 90 min. Fix (c) hotkey: 60 min. Verification: 45 min. **Total wall-clock: ~5–6 hours.** (This is the heaviest of the three Sonnet Wave-2 fixes — `high` effort is justified.)

### When you're done

Report back with:
- axe-core before/after violation counts by severity.
- The keyboard-navigation path through settings (proving no trap).
- The list of contrast tokens changed (old → new hex).
- The 5 multimon test names + pass/fail.
- The hotkey-conflict warning copy you wrote and where it surfaces (registration TrayTip + persistent banner + onboarding).
- Confirmation core dictation is unregressed.
- Anything you noticed out of scope (e.g. an overlay rendering smell) — flag via `spawn_task`, do not fix here.
