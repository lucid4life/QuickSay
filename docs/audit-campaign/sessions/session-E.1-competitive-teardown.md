# Session E.1 — Hands-On Competitive Teardown (Wispr Flow + Aqua Voice)

> **Model:** Opus 4.8 (Fable 5 / Sonnet 5 acceptable at same effort)
> **Effort:** high
> **Switch commands:** `/model claude-opus-4-8` then `/effort high`
> **Branch:** none for code (this session changes NO app code); findings commit on `audit/E.1-competitive-teardown` in the ROOT repo (`C:\QuickSay`)
> **Parallel-safe with:** E.2 (E.1 touches no code)
> **Depends on:** user pre-work (see "Before you start" below)
> **Blocks:** E.4 (visual polish consumes this session's benchmark gallery); informs E.2's quality bar
>
> **USER MUST BE PRESENT** — this session drives GUI apps on your desktop via computer-use and needs you to dictate a standardized test battery into three apps with your own voice and mic.

---

## Before you start (user pre-work — do this BEFORE opening the session)

1. **Both apps are already installed with active, previously-used accounts** (confirmed 2026-07-13). Just verify both launch and are signed in, and note the current plan/tier of each — free-tier word limits (Wispr ≈ 2k words/week, Aqua ≈ 1k words as of 2026-05 research) gate how much battery dictation they'll accept, so check remaining quota before Phase 2.
2. Prior usage means their personalization (auto-learned dictionary, tone adaptation) may be active. That's fine — it represents each app at its best; note it in findings where it affects a comparison.
3. **Onboarding capture is best-effort, NOT a blocker:** look for a "replay tutorial / re-run setup" option in each app; otherwise capture the flow from official docs/demo videos. Do **not** uninstall/reinstall or create fresh accounts just for this — low value for the effort.
4. Have QuickSay running (your current dev/rc build) with your normal mic.
5. Close anything sensitive on screen — the session takes desktop screenshots.

## Prompt to paste

You are running a hands-on competitive teardown of **Wispr Flow** and **Aqua Voice** against **QuickSay** on this machine, via computer-use (screenshots + driving the apps). The user is present and will dictate the test battery. Your output is a findings document + screenshot gallery that (a) flags every **core-loop quality gap** as a must-fix, (b) catalogs **structural differences we deliberately keep**, and (c) hands E.2 a measured quality bar and E.4 a visual benchmark.

### Locked positioning (judge everything through this lens)

**Match core quality, win on ownership.** QuickSay must be indistinguishable from Wispr/Aqua on the core loop — accuracy, latency, formatting, polish — and wins structurally: $39-once vs subscription, no account, no cloud, private by default, your-own-Groq-key. Their cloud features (sync, mobile companion, team features, account-based history) are **noted and skipped**, not gaps. A core-loop difference where QuickSay is worse = must-fix candidate. A structural difference = marketing ammunition, record it.

### Read first
1. `C:\QuickSay\docs\audit-campaign\research\competitor-backend-research.md` — the existing backend-level research (don't repeat it; this session is the PRODUCT-level complement).
2. `C:\QuickSay\CLAUDE.md` — QuickSay's architecture, so observations map to our implementation reality.
3. Memory: `project_E_series_pivot.md` — why this campaign exists, the transcription-quality evidence already gathered.

### Phase 1 — Surface + feature inventory (per competitor, ~45 min each)

Drive each app via computer-use. For every surface, take a screenshot and file it under `C:\QuickSay\docs\audit-campaign\findings\E.1-assets\<app>\`:
- Onboarding flow (best-effort — replay option / docs / demo videos, per pre-work note 3)
- Main window / dashboard, the recording indicator/widget in **every state** (idle, listening, processing, error)
- Settings — every tab/pane
- Dictionary / vocabulary / auto-learning features
- AI-edit / tone / formatting features, command mode if present
- Upgrade/paywall surfaces and how the free-tier limit presents
- Tray/menu-bar presence, hotkey configuration UX

Build a feature matrix: feature × {Wispr, Aqua, QuickSay} × {has it, quality 1–5, core-loop or structural}.

### Phase 2 — Standardized dictation battery (the heart of the session)

The user dictates each utterance below into **all three apps** (same mic, same order, into Notepad or each app's target). For each: record the exact output text, formatting quality, and **latency** (release-to-text, stopwatch via screen recording timestamps or count-in). Battery — read verbatim, natural pace:

1. *"The quick brown fox jumps over the lazy dog."* (clean baseline)
2. *"Should we meet at five tomorrow, or is Thursday better for you?"* (question — QuickSay's known answer-leakage probe; watch whether any app answers or appends)
3. *"So I was thinking — um, actually, let's move the deadline to, uh, Friday. No wait, Monday."* (fillers + self-correction)
4. *"Email John Smith at john dot smith at gmail dot com about the Q3 report."* (spoken formatting)
5. *"The invoice is for one thousand two hundred forty seven dollars and sixty cents, due March third."* (numbers, currency, dates)
6. *"QuickSay uses Groq, Whisper, AutoHotkey, and LemonSqueezy under the hood."* (jargon/brand terms — dictionary test)
7. *"Okay."* (sub-second utterance — hallucination probe)
8. A 60–90 second natural monologue about your day (long-form: paragraphing, sustained accuracy, drift)
9. *"git commit dash m quote fix the login bug quote"* (code/terminal dictation)
10. Hold the hotkey, say nothing for 5 seconds, release (silence — hallucination probe)
11. *"Their manager said they're going to leave their laptops there."* (homophone stress)
12. One utterance while music/TV plays quietly in the background (noise robustness)

Record results in a table: utterance × app × {output verbatim, errors, latency s, notes}. Score each app per category. Where QuickSay loses, that's an E.2 input; where it wins, that's marketing copy.

### Phase 3 — Classification + verdicts

Sort every observed difference into exactly one bucket:
- **MUST-FIX (core-loop quality gap):** QuickSay measurably worse on accuracy/latency/formatting/reliability/polish of the dictate→text loop. Assign each to E.2 (transcription), E.3 (behavior/bugs), or E.4 (visual).
- **KEEP (structural win):** differences that follow from ownership positioning — record as marketing ammunition with the evidence.
- **SKIP (their moat, not ours):** cloud features we deliberately don't chase. One line each on why.

### Phase 4 — Write findings

`C:\QuickSay\docs\audit-campaign\findings\E.1-competitive-teardown.md`: feature matrix, full battery results table, latency comparison, the three buckets, the visual-benchmark gallery index (per-surface side-by-side references for E.4), and a "top 5 things that would most change a buyer's mind" ranked list.

### Done When
- [ ] Both competitors inventoried with screenshots of every surface (incl. onboarding) in `findings/E.1-assets/`.
- [ ] Full 12-utterance battery run through all 3 apps with verbatim outputs + latency recorded.
- [ ] Every difference bucketed MUST-FIX / KEEP / SKIP; must-fixes assigned to E.2/E.3/E.4.
- [ ] Findings doc written; committed on `audit/E.1-competitive-teardown` (root repo); MASTER-PLAN Status Tracker → E.1 ✅.
- [ ] Uninstall guidance offered to the user (leave installed only if they want continued reference use — note the free tiers may nag).

### What NOT to do
- ❌ No app-code changes in this session — findings only.
- ❌ Do not create accounts, enter passwords, or accept paid upgrades — the user drives all account/auth/payment surfaces.
- ❌ Do not paste anything sensitive into the competitor apps — they are cloud services; the battery text above is safe by design.
- ❌ Do not judge their cloud features as gaps — positioning is locked (match core quality, win on ownership).
- ❌ Do not skip latency measurement — "feels fast" is not data.

### Estimated time
Phase 1: ~1.5 h (both apps). Phase 2: ~1 h (user-driven). Phase 3–4: ~1 h. **Total: ~3.5–4 h with the user present for Phase 2.**

### When you're done, report back with
- The top-5 buyer-mind-changing gaps, each with its assigned fix session.
- The battery scoreboard (accuracy/latency/formatting per app).
- The structural-win list (marketing ammunition).
- Confirmation E.2 and E.4 have their inputs.
