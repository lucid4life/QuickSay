# QuickSay Beta → Production Audit Campaign

**Drafted:** 2026-05-27
**Target release:** QuickSay v2.0.0 (first paid release)
**Approach:** Two-track parallel (Approach B from brainstorm)
**Total sessions:** 18 (+1 optional)
**Estimated wall-clock:** 5–6 weeks at sustained pace with 3 parallel windows during heaviest phases

This document is the source of truth for the audit campaign. Every session has its own ready-to-paste prompt file in `sessions/`. Update the **Status Tracker** at the bottom of this file as sessions complete.

---

## 1. Campaign goal

Move QuickSay from open beta to a polished, paid production release:

1. **Audit everything** — eliminate known and latent bugs across the recording engine, settings, history, installer, release pipeline, and infrastructure.
2. **Build production foundations** — license validation, 14-day trial enforcement, paywall, crash reporting, signed updates.
3. **Ship v2.0.0** — flip CTAs from beta signup to LemonSqueezy checkout, launch the paid product. **Pricing (resolved):** $39 one-time launch price for the first 500 orders, then $74 one-time with third-party installment financing on the $74 tier. 14-day trial. See OD-1.

**Out of scope for this campaign:** user accounts, cross-device sync, mobile companion, on-device Whisper (all deferred to v2.x+).

---

## 2. Phase map

```
PHASE 0 — Pre-Work                                    (2 sessions, serial)
─────────────────────────────────────────────────────────────────────────
  P0.1  Skill activation + custom skill creation
  P0.2  Test harness scaffolding + baseline inventory


PHASE 1 — Two parallel tracks (run concurrently after P0)
─────────────────────────────────────────────────────────────────────────

  TRACK 1 — Audit & Harden Existing App        TRACK 2 — Build Production Systems
  (7 sessions)                                  (6 sessions + 1 optional)

  Wave 1 (4 parallel, read-only audits):       Wave 1 (1 session, design gate):
    T1.1 Core engine audit                       T2.1 Backend infra design (ALL systems)
    T1.2 UI/settings + WebView2 bridge audit
    T1.3 Installer + release.ps1 audit          Wave 2 (2 parallel builds after T2.1):
    T1.4 Onboarding/widget/sound/dictionary       T2.2 Build CF Worker license issuer
                                                  T2.3 Trial + paywall (DPAPI + modal +
  Wave 2 (3 serial fixes from audit findings):       LemonSqueezy checkout)
    T1.5 History retention + auto-delete
    T1.6 Version sync sweep + automation       Wave 3 (2 parallel builds, anytime after T2.1):
    T1.7 Accessibility + multi-monitor +         T2.4 Crash reporting (Sentry envelope)
         hotkey conflict fixes                   T2.5 Signed updates (Ed25519)

                                                Wave 4 (anytime, parallel-safe):
                                                  T2.6 Transcription regression corpus

                                                Optional:
                                                  T2.7 Opt-in PostHog telemetry


PHASE 2 — Integration & Ship Readiness           (3 sessions, serial)
─────────────────────────────────────────────────────────────────────────
  M.1  Wire new systems into audited app — build v2.0.0-rc1
  M.2  Clean-VM install smoke + manual UAT (user-driven, scripted)
  M.3  Launch readiness — flip CTAs, set LemonSqueezy product ID, ship
```

---

## 3. Session table

| # | ID | Session | Model | Effort | Parallel-safe with | Blocks |
|---|---|---|---|---|---|---|
| 1 | P0.1 | Activate plugins + write `quicksay-go-to-paid` skill | Sonnet 4.6 | `medium` | — | P0.2 |
| 2 | P0.2 | Test harnesses + baseline inventory | Sonnet 4.6 | `high` | — | All of Phase 1 |
| 3 | T1.1 | Core engine audit (read-only) | Opus 4.8 | `xhigh` | T1.2, T1.3, T1.4 | T1.5 |
| 4 | T1.2 | UI/settings + WebView2 bridge audit (read-only) | Opus 4.8 | `xhigh` | T1.1, T1.3, T1.4 | T1.5, T1.6, T1.7 |
| 5 | T1.3 | Installer + release.ps1 audit (read-only) | Opus 4.8 | `xhigh` | T1.1, T1.2, T1.4 | T1.6 |
| 6 | T1.4 | Onboarding + widget + sound + dictionary audit | Opus 4.8 | `xhigh` | T1.1, T1.2, T1.3 | — |
| 7 | T1.5 | Fix history retention + race condition (use `ultrathink`) | Opus 4.8 | `xhigh` | T1.6, T1.7, all of Track 2 | — |
| 8 | T1.6 | Version sync sweep + `release.ps1 --check-sync` gate | Sonnet 4.6 | `medium` | T1.5, T1.7, all of Track 2 | M.1 (gate) |
| 9 | T1.7 | Accessibility + multi-monitor + hotkey conflicts | Sonnet 4.6 | `high` | T1.5, T1.6, all of Track 2 | — |
| 10 | T2.1 | **Backend infra design** — single spec, all systems | Opus 4.8 | **`max`** | All of Track 1 Wave 1 | T2.2, T2.3, T2.4, T2.5 |
| 11 | T2.2 | Build CF Worker license issuer | Opus 4.8 | `high` | T2.3, T2.4, T2.5, T2.6, all of Track 1 | M.1 |
| 12 | T2.3 | Build trial + paywall | Opus 4.8 | `xhigh` | T2.2, T2.4, T2.5, T2.6, all of Track 1 | M.1 |
| 13 | T2.4 | Build crash reporting + opt-in flow | Opus 4.8 | `high` | T2.2, T2.3, T2.5, T2.6, all of Track 1 | M.1 |
| 14 | T2.5 | Build signed updates (Ed25519) | Opus 4.8 | `xhigh` | T2.2, T2.3, T2.4, T2.6, Track 1 **except T1.6** (shared `release.ps1`) | M.1 |
| 15 | T2.6 | Transcription regression corpus | Sonnet 4.6 | `medium` | All other Track 2 | — |
| 16 | M.1 | Wire new systems into audited app → rc1 | Opus 4.8 | `xhigh` | — | M.2 |
| 17 | M.2 | UAT script + clean-VM manual testing | Sonnet 4.6 | `medium` | — | M.3 |
| 18 | M.3 | Launch — flip CTAs, ship v2.0.0 | Sonnet 4.6 | `high` | — | — |
| 19 | T2.7 | (OPTIONAL) Opt-in PostHog telemetry | Sonnet 4.6 | `high` | All other Track 2 | — |
| 20 | T1.8 | **Track-1 audit P1 remediation** — fixes the 5 unactioned P1s from T1.3 (4) + T1.4 (1); headline = data-location reconciliation (`{app}`→`%APPDATA%\QuickSay\`) that cross-cuts T2.3 | Opus 4.8 | `xhigh` | nothing (solo) | M.1 |

> **T1.8 (added 2026-06-04).** The read-only audits T1.3 + T1.4 surfaced 5 P1 bugs with no fix session assigned: T1.3-023 (user data under `{app}` not `%APPDATA%` — undermines the T2.3 trial design), T1.3-001 (installer ships the dev's live `config.json`), T1.3-011 (release.ps1 no rollback on mid-run failure), T1.3-025 (orphaned `HKCU\…\Run` autorun after uninstall), T1.4-025 ("Learn from Selection" never recompiles → learned word inert until reload). Runs after T2.6/T2.7, before M.1, so integration starts from clean code.

### Distribution
- **Sonnet 4.6: 7 sessions** — mechanical, scoped, spec-driven work (P0.1, P0.2, T1.6, T1.7, T2.6, M.2, M.3)
- **Opus 4.8: 11 sessions** — all audits (T1.1–T1.4), design (T2.1), security-critical builds (T2.2, T2.3, T2.4, T2.5), the history-race fix (T1.5), and integration (M.1)
- _Model-split note (2026-05-28):_ With Opus 4.8 a strict upgrade at the same price 4.7 was, T1.4 (the one remaining audit on Sonnet) plus the two security-critical builds T2.2 (license) and T2.4 (crash/PII) were promoted to Opus 4.8. The clearly-mechanical sessions stay on Sonnet — no reasoning bottleneck there.
- **Large-context (1M) sessions: 4** — T1.1, T1.2, T2.1, M.1 hold many files in head at once. On **Opus 4.8 the 1M window is standard** (no `[1m]` flag needed — `/model claude-opus-4-8` gives 1M), so these need no special handling beyond using Opus 4.8.
- **`max` effort: 1 session only** (T2.1)
- **`ultrathink` inline keyword:** flagged where useful (T1.5 root-cause moment)

---

## 4. Parallelism map (visual dependency graph)

```
                            ┌─ P0.1 ──► P0.2 ──┐
                            └──────────────────┤
                                               │
                  ┌─ T1.1 (Opus4.8 xhigh) ─┐  │
                  ├─ T1.2 (Opus4.8 xhigh) ─┤  │
            ┌─────┼─ T1.3 (Opus      xhigh) ┤◄─┘
            │     └─ T1.4 (Opus 4.8  xhigh) ┘
   Track 1 ─┤
            │     ┌─ T1.5 (Opus xhigh, needs T1.1+T1.2 findings)
            └─────┼─ T1.6 (Sonnet medium, needs T1.3 findings, BLOCKS M.1)
                  └─ T1.7 (Sonnet high)

            ┌─ T2.1 (Opus4.8 MAX, design gate — needs Track 1 W1 first) ┐
   Track 2 ─┤                                                            │
            │     ┌─ T2.2 (Opus 4.8 high) ◄─┐                            │
            │     ├─ T2.3 (Opus xhigh)    ─┤◄────────────────────────────┘
            └─────┼─ T2.4 (Opus 4.8 high) ─┤
                  ├─ T2.5 (Opus xhigh)    ─┤
                  └─ T2.6 (Sonnet medium) ─┘

   Phase 2 ──► M.1 (Opus4.8 xhigh) ──► M.2 (Sonnet medium) ──► M.3 (Sonnet medium)
```

**Reading the graph:**
- Lines flowing left-to-right are dependencies.
- T1.1, T1.2, T1.3, T1.4 are the 4 parallel audit windows — open all four Claude Code instances at once.
- T2.1 is the **design gate** — Track 2 builds cannot start until it lands. T2.1 should also wait for Track 1's audits to land so the design isn't built on broken assumptions.
- Track 1 Wave 2 and Track 2 Wave 2+3 can run concurrently with each other.

**Pragmatic 3-window flow (one human, three Claude windows):**

| Day(s) | Window A | Window B | Window C |
|---|---|---|---|
| 1 | P0.1 | — | — |
| 2 | P0.2 | — | — |
| 3–5 | T1.1 | T1.2 | T1.3 |
| 6–7 | T1.4 | T2.1 (design — start once T1.1 & T1.2 land) | — |
| 8–10 | T1.5 (`ultrathink` ready) | T2.2 | T2.3 |
| 11–13 | T1.6 | T2.4 | T2.5 |
| 14–15 | T1.7 | T2.6 | — |
| 16–18 | M.1 | — | — |
| 19 | M.2 (you drive on VM) | — | — |
| 20 | M.3 | — | — |

---

## 4a. Cross-session handoffs & merge-order constraints

The session table's dependency columns encode the main graph. These are the finer-grained hand-offs surfaced while authoring the prompts — read them before running the sessions involved.

| Handoff | Type | What must happen |
|---|---|---|
| **T1.2 → T1.5** | Evidence | T1.2's audit produces the airtight clear-history race trace + reproduction recipe. T1.5 inherits it verbatim — don't re-derive. |
| **T1.3 → M.2** | Artifact | T1.3 authors the push-button clean-VM install/uninstall procedure (under a `## M.2 clean-VM procedure` heading in its findings). M.2 *reads* it rather than designing fresh. |
| **T1.6 → T2.5** | **Merge-order** | Both edit `release.ps1`. They can be *developed* in parallel, but **T1.6 must merge to `main` first**; T2.5 then rebases its signing step onto T1.6's `VERSION` / `--check-sync` refactor. If they merge out of order, expect a `release.ps1` conflict (M.1 would catch it, but earlier is cheaper). |
| **T2.1 → {T2.2, T2.3, T2.5}** | Key material | The Ed25519 **keypair is generated as the final concrete step of T2.1** (see §6). Private key → CF secret store + offline backup. Public key → committed + baked into the AHK app. This keeps T2.2 (signs JWTs), T2.3 (verifies JWTs), and T2.5 (signs/verifies `version.json`) **parallel-safe** — none waits on another for key handoff. **✅ Done 2026-05-31: keypair `qs-2026` generated; public key in spec §8.1; private key at `%USERPROFILE%\.quicksay-keys\` pending move to CF secret + offline backup.** |
| **T2.1 → {T2.2, T2.3, T2.5, M.1/M.3}** (post-design) | Contract / Merge-order | From the approved T2.1 spec §9: **(a)** T2.3 ⇄ T2.5 **share one `lib/ed25519.ahk` verifier** — whoever lands first exposes `VerifyEd25519(...)`, the other imports it (don't implement Ed25519 twice); **(b)** T2.2 **uses the T2.1-generated `qs-2026` keypair**, it does NOT generate its own (supersedes T2.2's Phase-2 wording); **(c)** M.1/M.3 installer must **create + preserve `%APPDATA%\QuickSay\`** and never wipe it (today's uninstaller `DelTree({app}\data)` would lose the trial-reset defense); **(d)** T2.2 adds `/trial/status` + `/trial/report` gate endpoints. |
| **T2.2 ↔ T2.3** | Contract | Both must agree byte-for-byte on the JWT claim names defined in the T2.1 spec. T2.2's README restates the public key + claim schema as the canonical reference. |
| **M.1 → M.3** | Environment flip | M.1 builds rc1 against the **staging** license worker (`license-staging.quicksay.app`). M.3 must `wrangler deploy --env production`, re-put prod secrets, and flip the app's endpoint to `license.quicksay.app` before the public build ships. |
| **T2.7 → M.3** | Copy reconciliation | *If* telemetry ships, the website's "zero telemetry / 100% private" copy must be revisited at launch. If T2.7 is skipped, no action. |

## 5. How to run a session

1. **Open a new Claude Code window** in the right project directory (`C:\QuickSay\Development` for app sessions; `C:\QuickSay\Website` only for M.3 launch; `C:\QuickSay\Backend\license-worker` for T2.2 — it doesn't exist yet, T2.1's spec will create it).
2. **Switch model:** `/model claude-opus-4-8` (1M context is standard on 4.8 — no flag) or `/model sonnet` per session header.
3. **Set effort:** `/effort xhigh` (or `max` / `high` / `medium`) per session header.
4. **Open the matching session prompt file** in `docs/audit-campaign/sessions/session-NN-<slug>.md` and **paste the entire body into Claude Code**. Don't paraphrase — the prompts are tuned.
5. **Let it run.** Read its plan before approving destructive actions.
6. **At session end:** verify the "Done When" checklist is fully met. Update the **Status Tracker** in this file. Commit on the session branch and PR it before starting any session that depends on it.

### Branching convention

```
main
 └─ audit/P0.1-skill-activation
 └─ audit/T1.1-core-engine
 └─ audit/T1.2-ui-settings-webview2
 └─ ...
 └─ audit/M.3-launch
```

Each session works on its own branch. Merge to `main` after the Done When gate passes.

### `ultrathink` usage

The `ultrathink` keyword inside a prompt triggers maximum reasoning for that one turn without changing session-wide effort. Built into specific session prompts at root-cause-analysis moments (notably T1.5). If you want to use it ad-hoc inside any session, type it in your follow-up message: *"ultrathink — what are the failure modes here?"*

---

## 6. Cross-cutting infrastructure

These are decided once, used by every session.

### Test harness (built in P0.2, lives in `Development/tests/`)

| Component | Path | What it does |
|---|---|---|
| `Development/tests/playwright/` | WebView2/CDP test runner for settings + onboarding UI | Drives the embedded Chromium via Edge DevTools Protocol on `--remote-debugging-port=9222` |
| `Development/tests/transcription/` | Whisper regression corpus + runner | WAV files (LibriSpeech subset + silence/noise/edge cases) + assertion script |
| `Development/tests/live-runner.ps1` | AHK live runner with debug.txt tail | Starts QuickSay.ahk under AutoHotkey64.exe, tails `data/logs/debug.txt`, prints state |

Add `Development/tests/` to `.gitignore` only inside the **installer scope** (so it's not bundled in the .exe). It IS committed to git.

### Version sync regime (defined in T1.6, enforced thereafter)

Single source of truth: `Development/VERSION` file (new, contains e.g. `2.0.0`). `release.ps1 --check-sync` reads this file and verifies every version string in the codebase matches before allowing a release build. CI gate enforces.

Files that must contain the version:
- `Development/VERSION` (new — source of truth)
- `Development/QuickSay.ahk` (ScriptVersionInfo + `localVersion`)
- `Development/setup.iss` (`AppVersion`, `VersionInfoVersion`)
- `Development/config.example.json` (`lastSeenVersion`)
- `Development/data/changelog.json` (top entry)
- `Website/src/data/*` (whatever holds the displayed version)
- `version.json` on R2 (deployed by release.ps1)

### License + crash + telemetry endpoints (designed in T2.1)

```
Cloudflare account
 ├─ Workers
 │   ├─ license.quicksay.app       (issues JWTs)
 │   └─ crash.quicksay.app         (Sentry envelope forwarder OR direct to Sentry)
 ├─ KV namespaces
 │   ├─ LICENSE_CACHE              (LemonSqueezy webhook-populated cache; renamed from LICENSE_KEYS in T2.1 spec §2.1)
 │   └─ TRIAL_BLOCKLIST            (trial-reset gate via /trial/status; fail-open, never blocks a purchase — T2.1 §5.4)
 ├─ Secrets
 │   ├─ ED25519_PRIVATE_KEY        (signs JWTs + version.json)
 │   ├─ LEMONSQUEEZY_API_KEY       (server-to-server license validation)
 │   └─ SENTRY_DSN                 (only the project-public DSN, not auth)
```

T2.1 will finalize this — treat the above as starting topology.

**Ed25519 keypair lifecycle (decided):** The keypair is generated as the **final concrete step of T2.1** (the design session ends by producing the actual keys, since all three build sessions share them). The **private key** goes to the Cloudflare secret store (`wrangler secret put ED25519_PRIVATE_KEY`) **and** an offline backup (1Password or equivalent — never in git). The **public key** is committed to the repo and compiled into `QuickSay.ahk` as a constant. One key, two jobs: signs license JWTs (T2.2) and signs `version.json` (T2.5); verified in-app by the public key (T2.3 + update check). Generating it once in T2.1 is what keeps T2.2/T2.3/T2.5 parallel-safe.

---

## 7. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Track 2 design (T2.1) built on pre-fix assumptions | Medium | Medium | T2.1 runs **after** T1.1, T1.2 land. T2.1 freezes interface boundary only, not behavior. |
| Audit finds an issue that invalidates a Track 2 build mid-flight | Low | High | Each Track 2 session opens with `git pull origin main` + diff scan of dependent files. |
| Session scope creep | Medium | Medium | Each session prompt has explicit "Files forbidden" and "Out of scope" sections. |
| Memory drift between sessions | Low | High | MASTER-PLAN.md is the source of truth. Each session ends by updating the Status Tracker. |
| Version drift while we work | Medium | Medium | T1.6 ships `release.ps1 --check-sync` gate. Activated for all subsequent sessions. |
| Manual UAT skipped to move faster | High | Critical | M.2 is gated — nothing ships until the 14-item checklist is ✓ or explicitly waived in writing. |
| LemonSqueezy webhook outage on launch day | Low | High | T2.1 design includes a cached license check that survives 14-day issuer outage. |
| Ed25519 private key loss | Low | Critical | T2.5 mandates key in CF secret store + offline backup in 1Password (or equivalent). |
| Sentry rate limit hit on production crash flood | Low | Medium | T2.4 throttles to 5 envelopes/hour client-side; drop excess. |
| `quicksay-go-to-paid` custom skill becomes a maintenance burden | Low | Low | P0.1 keeps it small and deletion-friendly (no business logic, just prompt templates). |

---

## 8. Glossary

| Term | Meaning |
|---|---|
| **Track 1** | Audit & harden the existing app. 7 sessions. |
| **Track 2** | Build new production systems. 6 sessions + 1 optional. |
| **Phase Merge** | Phase 2: integrate the two tracks → ship v2.0.0. 3 sessions. |
| **Effort level** | `low / medium / high / xhigh / max` — Opus 4.8 supports all 5; Sonnet 4.6 supports 4 (no `xhigh`). **Opus 4.8 defaults to `high`** (4.7 defaulted to `xhigh`), so always set `xhigh`/`max` explicitly. |
| **1M context** | Million-token window. **Standard on Opus 4.8** (`/model claude-opus-4-8`) — no flag needed. (The old `[1m]` suffix was a 4.7-era thing; obsolete now.) |
| **`ultrathink`** | Keyword in a prompt that triggers max-reasoning for one turn without changing session effort. |
| **Done When** | The exit gate at the bottom of each session prompt. All items ✓ before the session is considered complete. |
| **`0x5555`** | Windows message ID used as `QuickSay_ConfigReloadMsg`. Settings → tray IPC. |
| **DPAPI** | Windows Data Protection API. Used to encrypt secrets at rest (Groq API key, trial expiry file, license JWT). |
| **JWT** | JSON Web Token. Signed license token issued by the CF Worker, valid 14 days, verified offline by the app. |
| **Envelope** | Sentry's HTTP wire format. POST-friendly. No SDK required. |
| **rc1** | Release candidate 1 — internal build for UAT, not published to R2. |

---

## 9. Status Tracker

Update this section at the end of every session. Mark with: ⬜ pending · 🟨 in progress · ✅ done · ⚠️ blocked · ⏭️ skipped/waived.

### Phase 0
- ✅ P0.1 — Skill activation + custom skill creation (2026-05-28: 5 plugins activated; `quicksay-go-to-paid` skill refined — 380 lines, all 3 sections, correct pricing)
- ✅ P0.2 — Test harnesses + baseline inventory (2026-05-28: 3 harnesses built; 6 items re-verified — 2 CONFIRMED, 2 REFUTED, 2 PARTIAL; baseline doc at findings/P0.2-baseline.md)

### Phase 1 — Track 1 (Audit & Harden)
- ✅ T1.1 — Core engine audit (2026-05-28: findings/T1.1-core-engine.md — **27 findings: 0 P0, 3 P1, 13 P2, 10 P3** + 5 Category-F verdicts. The 3 P1s: single-word transcriptions silently dropped (015), voice-commands fire keystrokes unconditionally (016), missing try/finally can wedge "processing" state (006). Verified live: 89 orphaned WAVs vs keepLastRecordings=10; single-word drop + voice-command keystroke injection reproduced via standalone harness. Key cross-deps: T1.5 inherits the history cache-resurrection vector + audio rotation; T1.6 owns version `localVersion` hardcode + unguarded weekly-summary config write. Zero source changes.)
- ✅ T1.2 — UI/settings + WebView2 bridge audit (2026-05-28: findings/T1.2-ui-settings.md — **19 findings: 0 P0, 2 P1, 13 P2, 4 P3** + 6 verified-clean entries. 33-action bridge matrix: 0 dead actions, 0 dead handlers, 0 dead responses; all 5 `0x5555` sends target the correct `QuickSay_TrayMode` window. The 2 P1s: clear-history race confirmed **NOT fully fixed** — tray's persistent `HistoryTextCache` + deferred `SaveToHistory` races the 100ms-deferred `ReloadConfig`, resurrecting cleared entries → airtight trace + repro for T1.5 (011); retention=0 + trim-removes-newest data loss, cross-ref T1.5 (016). Live-verified via Playwright/CDP harness (saveConfig/setMode/clearHistory persist + fire 0x5555; contrast measured — text-tertiary fails AA 4.5:1; getHistoryCount over-counts >2×) with byte-for-byte data restore. Cross-deps: T1.5 (history bugs), T1.6 (importConfig no-mutex, lost-update, hardcoded About version, GetDefaultModes dual-sync), T1.7 (no dark/light toggle, contrast, no responsive breakpoints, keyboard nav), T1.4 (sound dropdown missing `mechanical`). Zero source changes.)
- ✅ T1.3 — Installer + release.ps1 audit (done on branch `audit/T1.3-installer-release` — 22 findings, 0 P0, **4 P1**; branch not yet merged. The 4 P1s → owned by **T1.8**.)
- ✅ T1.4 — Onboarding + widget + sound + dictionary audit (done on branch `audit/T1.4-onboarding-widget-sound-dict` — 16 findings, 0 P0, **1 P1** (T1.4-025) → owned by **T1.8**; branch not yet merged.)
- ✅ T1.5 — History retention + race condition fix (2026-05-29: root-cause memo at findings/T1.5-root-cause.md; new `lib/history-core.ahk` makes every history mutation a fresh read→JSON.Parse→trim→atomic-write under the config mutex — one invariant fixes all three. **historyRetention** real-JSON slice replaces the corrupting `\}\s*,` string-surgery, drops oldest not newest, 0=unlimited, legacy files migrate on first append (T1.1-017, T1.2-016); **keepLastRecordings** PruneAudioDirectory prunes data/audio by mtime after each save, gated by saveRecordings (T1.1-024); **clear-history race** resurrection cache removed (always re-read) + generation guard — Clear posts 0x5556 to bump HistoryGeneration synchronously, deferred write drops itself if a clear superseded it, Clear holds the mutex during delete (T1.2-011). Concurrency folded in: importConfig mutex (T1.2-008), UpdateConfigKeys lock-held RMW for lost-update (T1.2-009), getHistoryCount counts parsed entries (T1.2-012), settings InvalidateHistoryCaches wired to 0x5555 (T1.2-010), non-array history.json preserved to .corrupt. Race fix = Phase-4c option B (re-read) hardened with option A (gen guard). **19/19 regression tests green** (tests/history/run-tests.ps1, AHK-native unit driver against real history-core + source assertions); QuickSay.ahk + settings_ui.ahk load clean. Dev PR #10. Mic-based manual smoke not runnable headless — automated suite + real-data round-trip cover the logic.)
- ✅ T1.6 — Version sync sweep + automation (done on branch `audit/T1.6-version-sync` — VERSION SSOT + `release.ps1 --check-sync` gate; branch not yet merged. Note: this branch is NOT in the T2.x line, so T2.5's `release.ps1` edits must be reconciled with it — T1.8 builds on T1.6's release.ps1; M.1 finalizes the merge.)
- ✅ T1.7 — Accessibility + multi-monitor + hotkey conflict fixes (2026-05-29: --text-tertiary #72728c→#8b8b9e (AA 5.0:1 bg-surface, 5.8:1 bg-base); skip link, aria-live status regions, span→button for password eye + dict delete icons, legal-link keyboard access, @media prefers-reduced-motion; FloatingWidget.RepositionToVisible() wired to OnDisplayChange (WM_DISPLAYCHANGE/0x7E) — snaps stranded widget to primary, leaves valid alone; 13/13 clamp-logic unit tests pass; hotkey conflict: Windows-reserved list check + AHK-level failure catch → SetHotkeyConflictFlag writes hotkeyConflict/hotkeyConflictMsg to config; settings banner (role=alert) + onboarding Done step banner both read from flag. Dev PR #13.)

### Phase 1 — Track 2 (New Systems)
- ✅ T2.1 — Backend infra design (gate) (2026-05-31: spec at `specs/T2-production-systems-design.md` (~7.4k words, 6 subsystems A–F) + `findings/T2.1-security-review.md`; **Ed25519 keypair `qs-2026` generated** (public baked into spec §8.1; private → CF secret + offline backup, NOT in git). Key decisions: crash=**Sentry-direct** (OD-5); **one shared key**, rotate-on-compromise; trial blocklist=**functional fail-open `/trial/status` gate** (never blocks a purchase); rate limits 10/hr ÷ 5/hr; `order_created` log-only; OD-1b financing=PayPal-surfaced pay-later (no LS-native BNPL, verified). KV `LICENSE_KEYS`→`LICENSE_CACHE`; webhook route `/webhook/lemonsqueezy`. Independent `security-auditor` pass: 4 P1 + 5 P2 all fixed in-spec. **Cross-deps:** (1) shared `lib/ed25519.ahk` verifier T2.3⇄T2.5; (2) installer must create+preserve `%APPDATA%\QuickSay\` and not wipe it — M.1/M.3; (3) **T2.2 uses the T2.1 keypair, not its own**; (4) additive `/trial/status`+`/trial/report` endpoints; (5) T2.5 merges after T1.6 (shared release.ps1). User-approved 2026-05-31.)
- ✅ T2.2 — CF Worker license issuer (2026-05-31: **staging only — prod deploy in M.1**. New subtree `Backend/license-worker/` (TypeScript, `jose` v5, wrangler v3). 8 endpoints + `/health` per spec §2/§3/§4: `/activate /validate /refresh /deactivate /pricing /trial/status /trial/report /webhook/lemonsqueezy`. Ed25519 JWT mint with `algorithms:["EdDSA"]` pinned (alg:none/confusion rejected); webhook HMAC-SHA256 verify-before-parse (constant-time `crypto.subtle.verify`) → evt-dedup → mandatory-timestamp gate → status-monotone apply (F4/R1/F9 closed); per-machine_id hourly KV rate limits; license keys stored only as sha256. **Uses the T2.1 `qs-2026` keypair** (does not generate one). **44/44 unit tests** (jwt 8 / license 18 / trial 7 / webhook 11; real jose Ed25519 + WebCrypto HMAC, in-memory KV fake — pool-workers harness incompatible w/ Win+Node24, README documents swap-back), tsc clean, 15/15 repeat runs (fixed a flaky b64url-padding tamper test). **Deployed** → `license-staging.quicksay.app` (custom domain live; CF acct 64160bcc…, zone quicksay.app); 3 KV namespaces created (ids in wrangler.toml); 3 secrets set (ED25519 priv from ~/.quicksay-keys, webhook secret, LS API key=PLACEHOLDER). **Live smoke all pass:** health/pricing/trial-status 200; validate-tampered→403 bad_signature; webhook bad-sig→401 empty; webhook valid-HMAC→200 + KV mutated to active; redelivery→deduped; activate(placeholder)→403 invalid; `wrangler tail` (6157 lines)=0 secret/JWT leaks; KV cleaned post-smoke. **Flags for user/T2.3:** (a) `/deactivate` local-only — LS seat not freed (raw key not in JWT; user-approved no-contract-change); (b) `/refresh` cache-miss→503 fail-safe (live-LS fallback structurally unreachable w/o raw key; never locks out); (c) `LEMONSQUEEZY_API_KEY` is PLACEHOLDER — real LS **test** key needed for the `/activate`→JWT chain (README has steps); (d) public key for T2.3: raw-32 `UmeruJlXQ1tyEX5fPzixUMjQD__Lm0NqIPSWReHRsw8`, sha256 `761d22df…fde09b`, iss `license.quicksay.app`. **M.1 cross-deps:** deploy `--env production` + re-put prod secrets + fill prod KV ids + flip app `LICENSE_WORKER_URL`; verify ~/.quicksay-keys private copy deleted (I-a). Branch `audit/T2.2-cf-worker-license` stacked on T2.1/PR #16.)
- ✅ T2.3 — Trial + paywall (2026-06-01: new `lib/ed25519.ahk` (pure-AHK EdDSA **verify** — BCrypt SHA-256/512 + base-2¹⁷ bignum + RFC 8032 point math; no DLL; passes RFC 8032 KAT + Node interop + trust-anchor SHA-256 I-c), `lib/license.ahk` (14-day trial state machine, DPAPI `license.dat` at `%APPDATA%\QuickSay\`, `ComputeMachineId`=SHA256(MAC+ProductID)[:32], JWT verify pinning `alg==EdDSA`/iss/machine/kid with per-token in-memory cache so it's off the hot path, clock-rollback guard, `/activate`·`/refresh`·`/trial/status`·`/trial/report`·`/pricing` via self-contained WinHTTP), `lib/paywall-ui.ahk` + `gui/paywall.{html,css}` (blocking paywall modal, separate WebView2 window). QuickSay.ahk: deferred startup verify, **recording gate** in `StartRecording()` (refuses in TRIAL_EXPIRED/REVOKED/RE_VALIDATION → shows paywall), tray "🔑 License/Unlock…", day-11 countdown TrayTip, 0x5555 reload refresh. Settings: "License" tab (status + dynamic price + activate); settings_ui.ahk + standalone exe updated. **Price never hardcoded** — fetched from worker `GET /pricing` ($39 launch→$74+financing) incl. checkoutUrl. **51 unit tests green** (ed25519 14 / license 37) via `tests/license/run-tests.ps1` + live staging smoke (/pricing /trial/status /validate) + paywall rendered & bridge-verified in a real browser ($39, $74-financing, offline-fallback all dynamic). Both entry points compile clean. **Deferred to M.1–M.3:** live `/activate`→JWT happy path (T2.2 LS key is placeholder → 403); flip `LICENSE_WORKER_URL` to prod; set real `LEMONSQUEEZY_PRODUCT_URL`; installer must create+preserve `%APPDATA%\QuickSay\`. **T2.5 imports `lib/ed25519.ahk`** (don't reimplement). Dev branch `audit/T2.3-trial-paywall`.)
- ✅ T2.4 — Crash reporting (2026-06-02: new `lib/crash-reporter.ahk` (Sentry-direct envelope POST, no SDK) — allowlist-only builder (§6.4) + PII `Scrub()` backstop + rolling-60-min throttle (max 5) + opt-in gate (hard no-op until `crashReportingEnabled` AND `crashReportingPrompted`) + crash-safe `OnError` (try-wrapped, returns 0 so the user's real error is never masked) + self-contained `application/x-sentry-envelope` POST (≤5 s, fire-and-forget). `last_action` derived from existing `isRecording`/`isProcessing` (no new hot-path writes, §6.7). New `lib/crash-optin-ui.ahk` + `gui/crash-optin.html` (first-run WebView2 modal, verbatim §6.5 copy, native MsgBox fallback). QuickSay.ahk: `OnError` installed early; `ConfigureCrashReporter()` on load+reload; deferred first-run modal; `crash_reporting_*` in ParseConfig/GetDefaultConfig. Settings "Privacy" toggle (enabling marks prompted). config.example.json documents both fields. **DSN = compiled `SENTRY_DSN_PUBLIC` (public key only), ships EMPTY → builds/sends nothing until M.1 bakes it in; M.3 flips `SENTRY_ENVIRONMENT` beta→production.** **Independent `comprehensive-review:security-auditor` pass:** found 1 real leak — `os_version` was the one allowlisted string field bypassing `Scrub()` (spec §6.4 "never machine name"): **FIXED** (now scrubbed; grep-gate covers a machine-name-valued os_version). JWT rule hardened to the distinctive `eyJ…\.eyJ…` shape → covers 2-segment (email-bearing) + dot-wrapped tokens. Residuals (mid-base64-segment newline split, backstop over-redaction) accepted + documented in code. **17 unit cases / 35 assertions green** (`tests/crash/run-tests.ps1`) + **gate-2 PII grep on real envelope bytes = 0 matches** for gsk_/eyJ/username/.wav/machine/transcript (`wire-capture.ahk`) + throttle/opt-out gates + full QuickSay.ahk include tree parses clean. **Gate 1 (live Sentry event ≤10 s) deferred to M.1** (needs the real DSN). Findings: `findings/T2.4-crash-reporting.md`. Dev branch `audit/T2.4-crash-reporting`.)
- ✅ T2.5 — Signed updates (2026-06-03: `version.json` is now Ed25519-signed (key `qs-2026`) and verified in `CheckForUpdates()` before any field is trusted — unsigned/tampered/wrong-key/unknown-`keyId` manifests are **rejected, fail-closed** (no update); the old unauthenticated JSON+regex parse is gone. New `lib/update-verify.ahk` (`VerifyUpdateManifest` + `UpdateManifest_Canonical`, trust anchor `TRUSTED_UPDATE_KEYS["qs-2026"]`) **imports the shared `lib/ed25519.ahk`** (T2.3's verifier — not reimplemented). Canonicalization pinned byte-for-byte (spec §7.2): sorted keys `{changelog,download_url,installer_sha256,keyId,released_at,version}`, compact separators, minimal RFC 8259 escaping, no `/` escaping, raw UTF-8 — shared `scripts/version-canonical.mjs` drives BOTH the signer and the test oracle. `scripts/sign-version-json.mjs` (Node) signs at release time, reads the private key from a secret/env (never the repo), **fails loudly if absent** (no unsigned release) + self-verifies + asserts keyId↔pubkey-SHA256. `release.ps1` STEP 6 computes `installer_sha256` of the final code-signed installer, then signs. `.gitignore` blocks `*.pem`/`.quicksay-keys/`. `QuickSay.ahk` also gains a single `global localVersion` SSOT (no more hardcoded "1.9.0" in the update check / Sentry release tag). **26 assertions green** (`tests/update/run-tests.ps1`): 11 cases (round-trip, tamper×3, stripped-sig, wrong-key, unknown-keyId, RFC 8032 KAT, canonicalization byte-identity incl. emoji+accent+slash, no-regression newer/same) + I-c trust-anchor SHA-256 + F1 escaped-surrogate + **real signer↔verifier round-trip** (sign-version-json.mjs → AHK verifier accepts; one-byte tamper → rejected, logs `update rejected: signature invalid`). **Independent `comprehensive-review:security-auditor` pass: APPROVE, no P0/P1** (fail-closed everywhere, keyId gate ordered first, no alg-confusion surface, signer key-handling safe); 1 P2 (escaped-surrogate equivalence) test-pinned + 3 P3 informational. **`installer_sha256` is signed but NOT yet enforced** (v2.0 opens `download_url` in a browser) — M.1 closes it by downloading + hash-checking before exec (F6). Threat model: `findings/T2.5-threat-model.md`. **I-a M.1 gate stands: delete the local `%USERPROFILE%\.quicksay-keys\` private key after it's in the CF secret store + offline backup — and from then on the release machine must supply it to `release.ps1` STEP 6 via `QUICKSAY_ED25519_PRIVATE_KEY` (PEM env, from the secret) or `QUICKSAY_ED25519_PRIVATE_KEY_PATH`; without it the signer fails closed and the release aborts (so the T2.5 release that first ships the verifier must also deploy a freshly-signed `version.json`, else upgraded apps fail-closed and see no updates).** Dev branch `audit/T2.5-signed-updates` (built on T1.6's `release.ps1`); docs branch `audit/T2.5-findings`.)
- ✅ T2.6 — Transcription regression corpus (2026-06-04: 20-clip corpus (10 clean + 5 accents + 5 edge) under `Development/tests/transcription/`. **Download-on-demand** (Option B): `fetch-corpus.ps1` downloads LibriSpeech test-clean (~346 MB, cached), extracts via Python tarfile, converts FLAC→WAV with bundled ffmpeg.exe, populates `expected.json` from official .trans.txt. Edge WAVs (silence/noise/short-utterance) committed (generated, tiny). Runner `run-stt-regression.ps1`: direct API parity with `HttpPostFile()` → Groq Whisper; WER via Levenshtein on normalised word sequences; hallucination detection = faithful PowerShell port of `IsWhisperHallucination()` + `StripTrailingArtifacts()`; exit 0 green / exit 1 on failure or `-CompareBaseline` regression; `-RefreshBaseline` explicit-only. **All 20 clips pass: 20/20, mean WER clean = 0.0%, mean WER accents = 2.3%.** Baseline committed at `baseline/baseline-v2.0.json`. Verification gates: gate 2 (exit 0) ✅, gate 3 (WER self-test 0.3333) ✅, gate 4 (silence/noise flagged, short-utterance raw=Okay) ✅, gate 5 (baseline committed) ✅, gate 6 (injected regression → exit 1) ✅, gate 8 (no gsk_ in report) ✅. Code-review P0 fixed (Python prefixes list construction bug). Note: `lib/hallucination.ps1` is a port of AHK hallucination logic — must stay in sync with `QuickSay.ahk` (flagged for M.1). Dev PR #24.)
- ✅ T2.7 — (OPTIONAL) PostHog telemetry (2026-06-04: opt-in, off-by-default PostHog analytics via HTTP capture API (no SDK). New `lib/telemetry.ahk`: master gate `TelemetryEnabled()`, allowlist-enforced `EmitEvent()` (6 events: `app_started`, `recording_completed`, `settings_changed`, `crash_reported`, `update_check`, `update_installed`), 3-layer PII defense (key-name denylist + unanchored value-pattern scrubber with email/JWT/API-key/MAC/path matchers + event-specific transforms: duration→bucket, mode→preset-or-"custom", settings keys → name-only), batched POST to EU endpoint (`eu.i.posthog.com/batch/`) ≥30 s throttle + max-20 queue, `CoCreateGuid`-based anonymous install ID (NOT `trialMachineId`, NOT hardware-derived) regenerated on opt-out→opt-in. Emit points wired in `QuickSay.ahk` (app_started deferred 5 s, recording_completed on success, update_check, update_installed, flush-on-exit). `lib/settings-ui.ahk`: `settings_changed` diff via allowlist (18 safe keys, never values), `Telemetry_RegenerateInstallId()` on opt-off (HIGH-1 fix). `gui/settings.html` Privacy section: honest toggle + expandable "What's collected?" disclosure + `receiveConfig`/`buildConfig` wiring + JS opt-out clears `telemetryInstallId`. `config.example.json` documents `telemetryEnabled` (false) and `telemetryInstallId` (""). `docs/telemetry-events.md` is the committed human-readable event contract. **43 assertions green** (`tests/telemetry/run-tests.ps1`): off-by-default gate, ON fires, PII scrub (under both denied and innocent key names — T3b HIGH-2 regression), allowlist, duration bucket, settings_changed filter, UUID install ID, not-hardware-derived, batch/throttle, failure swallowed, opt-out regenerates ID. **HIGH-1 (dead opt-out path)** and **HIGH-2 (anchored scrubber regexes)** from initial security audit CLOSED. `POSTHOG_PROJECT_KEY` ships empty → no data sent until M.3 sets the public capture key. ⚠️ FLAG FOR M.3: website currently says "zero telemetry / 100% private" — that copy MUST be updated if telemetry ships. Dev branch `audit/T2.7-telemetry`.)
- ⬜ T1.8 — Track-1 audit P1 remediation (fixes the 5 P1s from T1.3+T1.4; blocks M.1)

### Phase 2
- ⬜ M.1 — Wire systems → v2.0.0-rc1
- ⬜ M.2 — UAT script + clean-VM testing
- ⬜ M.3 — Launch

---

## 9a. Open decisions (need Adrian's input before the relevant session)

These can't be resolved from code/memory alone. Each is tagged with the session that's blocked until you decide.

| # | Decision | Current conflicting state | Blocks | Default if you don't decide |
|---|---|---|---|---|
| OD-1 | **Final price & framing** | ✅ **RESOLVED 2026-05-27:** **$39 one-time launch price for the first 500 orders**, then **$74 one-time** with **third-party installment financing** on the $74 tier. The website's existing `$39 launch / $74 regular` framing was correct; the "$39.99" in earlier notes was wrong and is now purged. | M.3 reconciles every surface; T2.1 designs the order-count price cutover + financing provider | — (resolved) |
| OD-1b | **Installment financing provider** | NEW: the $74 tier needs equal-payments/BNPL. Unknown whether LemonSqueezy supports this natively or needs Affirm/Klarna/Afterpay/PayPal-Pay-in-4 bolted on. | T2.1 (design) verifies; M.3 wires it | Research during T2.1; if LemonSqueezy lacks native support, evaluate a BNPL add-on or defer financing to post-launch. |
| OD-1c | **Price-cutover mechanism** | NEW: $39→$74 flips at 500 orders. The app paywall must not hardcode the number. | T2.1 + T2.3 | Worker exposes `GET /pricing`, or the modal defers the number to the LemonSqueezy checkout page. |
| OD-2 | **Trial length** | 14 days assumed everywhere. | T2.1, T2.3 | 14 days. |
| OD-3 | **Paywall hard-block vs soft** | T2.3 recommends a blocking modal after expiry (app opens, recording disabled). | T2.3 | Blocking modal; app still opens for purchase/help/settings. |
| OD-4 | **Ship telemetry (T2.7) before v2.0?** | Optional in the plan. Affects website "zero telemetry" copy. | T2.7, M.3 | Skip for v2.0; revisit in v2.1. Keep "100% private" claim true. |
| OD-5 | **Crash reporting backend: Sentry vs self-hosted CF Worker** | Research recommends Sentry envelope POST (free tier). | T2.1, T2.4 | Sentry free tier; revisit if volume exceeds free quota. |

**OD-1 is resolved** ($39 launch → $74 + financing). The remaining open items (OD-1b financing provider, OD-1c price-cutover mechanism, OD-2…OD-5) all have safe defaults and are addressed inside T2.1's design work. None blocks the start of the campaign.

## 10. References

### Research (informs the campaign)
- [`research/competitor-backend-research.md`](research/competitor-backend-research.md) — Wispr Flow, SuperWhisper, BetterTouchTool, etc. Recommended stack derived here.
- [`research/tooling-research.md`](research/tooling-research.md) — AHK v2 tools, Playwright/CDP for WebView2, WinSparkle, Sentry envelope, license servers, Whisper corpora.
- [`research/skills-inventory.md`](research/skills-inventory.md) — Installed skills coverage, 5 gaps, recommended installs.
- [`research/app-surface-inventory.md`](research/app-surface-inventory.md) — Starting inventory of every setting, mode, action, file I/O, etc. (Refined in P0.2.)

### Specs (produced by campaign)
- `specs/T2-production-systems-design.md` — produced by T2.1. License worker + JWT + trial + crash + signed updates, in one spec.

### Findings (produced by audit sessions)
- `findings/T1.1-core-engine.md`
- `findings/T1.2-ui-settings-webview2.md`
- `findings/T1.3-installer-release.md`
- `findings/T1.4-onboarding-widget-sound-dictionary.md`

### Sessions (ready-to-paste prompts)
- `sessions/session-P0.1-skill-activation.md`
- `sessions/session-P0.2-test-harnesses.md`
- `sessions/session-T1.1-core-engine-audit.md`
- `sessions/session-T1.2-ui-settings-audit.md`
- `sessions/session-T1.3-installer-audit.md`
- `sessions/session-T1.4-onboarding-widget-sound-dict-audit.md`
- `sessions/session-T1.5-history-retention-fix.md`
- `sessions/session-T1.6-version-sync.md`
- `sessions/session-T1.7-a11y-multimon-hotkey.md`
- `sessions/session-T2.1-backend-design.md`
- `sessions/session-T2.2-cf-worker-license.md`
- `sessions/session-T2.3-trial-paywall.md`
- `sessions/session-T2.4-crash-reporting.md`
- `sessions/session-T2.5-signed-updates.md`
- `sessions/session-T2.6-transcription-regression.md`
- `sessions/session-T2.7-telemetry.md` *(optional)*
- `sessions/session-M.1-integration.md`
- `sessions/session-M.2-uat.md`
- `sessions/session-M.3-launch.md`
