# Session E.4 — Benchmark-Driven Visual Polish (widget, onboarding, settings, paywall)

> **Model:** Opus 4.8 (Fable 5 acceptable; invoke `frontend-design` + `interface-design` skills)
> **Effort:** high
> **Switch commands:** `/model claude-opus-4-8` then `/effort high`
> **Branch:** `audit/E.4-visual-polish` (Development repo, off E.3's merged tip)
> **Parallel-safe with:** nothing in the E-series tail (touches gui/*, widget-overlay.ahk, lib/settings-ui.ahk)
> **Depends on:** E.1 (the visual benchmark gallery is the input), E.3 merged
> **Blocks:** E.5
>
> Scope guard: **polish pass, not redesign.** The goal is that a first-time buyer's eye finds nothing that reads "dated" or "untrustworthy" next to Wispr/Aqua. First impressions drive the "$39 worth it?" judgment for the first 500.

---

## Prompt to paste

You are closing the visual gaps identified in E.1's side-by-side benchmark between QuickSay and Wispr Flow / Aqua Voice — on exactly four surfaces: the **recording widget**, **onboarding wizard**, **settings window**, and **paywall**. Targeted upgrades only; every change verified in the running UI with before/after screenshots; the T1.7 accessibility work is a hard regression floor.

### Read first
1. `findings/E.1-competitive-teardown.md` + `findings/E.1-assets/` — the benchmark gallery and the E.4-assigned must-fix list. **This is the work list; do not invent gaps E.1 didn't observe.**
2. `C:\QuickSay\Development\CLAUDE.md` — WebView2 UI pattern, Dad Test copy rules.
3. T1.7 notes (MASTER-PLAN Status Tracker) — the a11y floor: contrast ≥ AA (#8b8b9e floor), skip link, aria-live regions, keyboard nav, reduced-motion support. None of these may regress.
4. Invoke `frontend-design` (and `interface-design:audit` for the existing-state check) before writing UI code.

### Priorities (stack-ranked; stop when the timebox ends, in this order)
1. **Recording widget** (`widget-overlay.ahk`) — every user sees it on every dictation. States: idle/listening/processing/error. Smoothness, legibility, dark/light sanity, no jank on state transitions.
2. **Onboarding** (`gui/onboarding.html`, `onboarding_ui.ahk`) — the first 5 minutes decide refunds. Visual hierarchy, progress affordance, plain-English copy (Dad Test — "free AI account", never raw "API key" jargon), hotkey-practice step polish.
3. **Paywall** (`gui/paywall.html`) — the money surface. Trustworthy, calm, price displayed via the live `/pricing` fetch (never hardcode $39/$74 — T2.3 rule).
4. **Settings** (`gui/settings.html`) — consistency pass: spacing, typography scale, control styling coherence across tabs.

### Method (per surface)
1. BEFORE screenshot set (all states) via the Playwright/CDP harness (`Development/tests/playwright/`) or live app.
2. Apply the E.1-assigned fixes. Match the app's existing idiom — no new frameworks, no build-step additions; keep everything self-contained per the WebView2 pattern.
3. AFTER screenshots; a11y re-check (keyboard-only walk, contrast spot-check on any changed colors, reduced-motion respected).
4. Live verify via the harness where scripted, by launching the app (PowerShell tool, not Bash) where not.

### Done When
- [ ] Every E.4-assigned E.1 finding addressed or explicitly deferred with reason.
- [ ] Before/after screenshot pairs for each touched surface in `findings/E.4-assets/`.
- [ ] A11y floor verified unregressed (keyboard nav walk + contrast on changed styles + reduced-motion).
- [ ] Playwright settings/onboarding smokes green; paywall renders with live pricing; widget states exercised live.
- [ ] No hardcoded price anywhere new (grep `$39`/`$74` in changed files → only via `/pricing`).
- [ ] Findings note committed (root); code on `audit/E.4-visual-polish` + PR; MASTER-PLAN → E.4 ✅.

### What NOT to do
- ❌ No redesign, no new component systems, no framework/CDN additions (WebView2 pages stay self-contained).
- ❌ No gap-invention beyond E.1's observed list — scope creep here delays launch.
- ❌ Never regress T1.7 a11y to look prettier.
- ❌ No marketing copy/website work — app surfaces only (website is M.3's).

### Estimated time
Widget ~2 h · Onboarding ~2 h · Paywall ~1 h · Settings ~1.5 h · verification throughout. **Total: ~6–7 h, hard-capped by the stack rank.**

### When you're done, report back with
- Before/after pairs per surface (the launch announcement can reuse these).
- Anything deferred and why.
- Confirmation the a11y floor held.
