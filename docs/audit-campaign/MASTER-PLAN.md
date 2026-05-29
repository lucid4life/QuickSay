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
| 3 | T1.1 | Core engine audit (read-only) | Opus 4.7 [1m] | `xhigh` | T1.2, T1.3, T1.4 | T1.5 |
| 4 | T1.2 | UI/settings + WebView2 bridge audit (read-only) | Opus 4.7 [1m] | `xhigh` | T1.1, T1.3, T1.4 | T1.5, T1.6, T1.7 |
| 5 | T1.3 | Installer + release.ps1 audit (read-only) | Opus 4.7 | `xhigh` | T1.1, T1.2, T1.4 | T1.6 |
| 6 | T1.4 | Onboarding + widget + sound + dictionary audit | Sonnet 4.6 | `high` | T1.1, T1.2, T1.3 | — |
| 7 | T1.5 | Fix history retention + race condition (use `ultrathink`) | Opus 4.7 | `xhigh` | T1.6, T1.7, all of Track 2 | — |
| 8 | T1.6 | Version sync sweep + `release.ps1 --check-sync` gate | Sonnet 4.6 | `medium` | T1.5, T1.7, all of Track 2 | M.1 (gate) |
| 9 | T1.7 | Accessibility + multi-monitor + hotkey conflicts | Sonnet 4.6 | `high` | T1.5, T1.6, all of Track 2 | — |
| 10 | T2.1 | **Backend infra design** — single spec, all systems | Opus 4.7 [1m] | **`max`** | All of Track 1 Wave 1 | T2.2, T2.3, T2.4, T2.5 |
| 11 | T2.2 | Build CF Worker license issuer | Sonnet 4.6 | `high` | T2.3, T2.4, T2.5, T2.6, all of Track 1 | M.1 |
| 12 | T2.3 | Build trial + paywall | Opus 4.7 | `xhigh` | T2.2, T2.4, T2.5, T2.6, all of Track 1 | M.1 |
| 13 | T2.4 | Build crash reporting + opt-in flow | Sonnet 4.6 | `high` | T2.2, T2.3, T2.5, T2.6, all of Track 1 | M.1 |
| 14 | T2.5 | Build signed updates (Ed25519) | Opus 4.7 | `xhigh` | T2.2, T2.3, T2.4, T2.6, Track 1 **except T1.6** (shared `release.ps1`) | M.1 |
| 15 | T2.6 | Transcription regression corpus | Sonnet 4.6 | `medium` | All other Track 2 | — |
| 16 | M.1 | Wire new systems into audited app → rc1 | Opus 4.7 [1m] | `xhigh` | — | M.2 |
| 17 | M.2 | UAT script + clean-VM manual testing | Sonnet 4.6 | `medium` | — | M.3 |
| 18 | M.3 | Launch — flip CTAs, ship v2.0.0 | Sonnet 4.6 | `medium` | — | — |
| 19 | T2.7 | (OPTIONAL) Opt-in PostHog telemetry | Sonnet 4.6 | `high` | All other Track 2 | — |

### Distribution
- **Sonnet 4.6: 10 sessions** — mechanical, scoped, spec-driven work
- **Opus 4.7: 8 sessions** — audit, design, security, integration
- **`[1m]` context flag: 4 sessions** — when many files coexist in head (T1.1, T1.2, T2.1, M.1)
- **`max` effort: 1 session only** (T2.1)
- **`ultrathink` inline keyword:** flagged where useful (T1.5 root-cause moment)

---

## 4. Parallelism map (visual dependency graph)

```
                            ┌─ P0.1 ──► P0.2 ──┐
                            └──────────────────┤
                                               │
                  ┌─ T1.1 (Opus[1m] xhigh) ─┐  │
                  ├─ T1.2 (Opus[1m] xhigh) ─┤  │
            ┌─────┼─ T1.3 (Opus      xhigh) ┤◄─┘
            │     └─ T1.4 (Sonnet    high)  ┘
   Track 1 ─┤
            │     ┌─ T1.5 (Opus xhigh, needs T1.1+T1.2 findings)
            └─────┼─ T1.6 (Sonnet medium, needs T1.3 findings, BLOCKS M.1)
                  └─ T1.7 (Sonnet high)

            ┌─ T2.1 (Opus[1m] MAX, design gate — needs Track 1 W1 first) ┐
   Track 2 ─┤                                                            │
            │     ┌─ T2.2 (Sonnet high)  ◄─┐                             │
            │     ├─ T2.3 (Opus xhigh)    ─┤◄────────────────────────────┘
            └─────┼─ T2.4 (Sonnet high)   ─┤
                  ├─ T2.5 (Opus xhigh)    ─┤
                  └─ T2.6 (Sonnet medium) ─┘

   Phase 2 ──► M.1 (Opus[1m] xhigh) ──► M.2 (Sonnet medium) ──► M.3 (Sonnet medium)
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
| **T2.1 → {T2.2, T2.3, T2.5}** | Key material | The Ed25519 **keypair is generated as the final concrete step of T2.1** (see §6). Private key → CF secret store + offline backup. Public key → committed + baked into the AHK app. This keeps T2.2 (signs JWTs), T2.3 (verifies JWTs), and T2.5 (signs/verifies `version.json`) **parallel-safe** — none waits on another for key handoff. |
| **T2.2 ↔ T2.3** | Contract | Both must agree byte-for-byte on the JWT claim names defined in the T2.1 spec. T2.2's README restates the public key + claim schema as the canonical reference. |
| **M.1 → M.3** | Environment flip | M.1 builds rc1 against the **staging** license worker (`license-staging.quicksay.app`). M.3 must `wrangler deploy --env production`, re-put prod secrets, and flip the app's endpoint to `license.quicksay.app` before the public build ships. |
| **T2.7 → M.3** | Copy reconciliation | *If* telemetry ships, the website's "zero telemetry / 100% private" copy must be revisited at launch. If T2.7 is skipped, no action. |

## 5. How to run a session

1. **Open a new Claude Code window** in the right project directory (`C:\QuickSay\Development` for app sessions; `C:\QuickSay\Website` only for M.3 launch; `C:\QuickSay\Backend\license-worker` for T2.2 — it doesn't exist yet, T2.1's spec will create it).
2. **Switch model:** `/model opus[1m]` or `/model sonnet[1m]` per session header.
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
 │   ├─ LICENSE_KEYS               (LemonSqueezy webhook-populated cache)
 │   └─ TRIAL_BLOCKLIST            (revoked trials)
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
| **Effort level** | `low / medium / high / xhigh / max` — Opus 4.7 supports all 5; Sonnet 4.6 supports 4 (no `xhigh`). |
| **`[1m]`** | 1M-token context flag. Switched via `/model opus[1m]` or `/model sonnet[1m]`. |
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
- ⬜ T1.3 — Installer + release.ps1 audit
- ✅ T1.4 — Onboarding + widget + sound + dictionary audit (2026-05-29: findings/T1.4-onboarding-widget-sound-dict.md — **16 findings: 0 P0, 1 P1, 8 P2, 7 P3** + 11 verified-clean. The 1 P1: "Learn from Selection" reports success but never recompiles the dictionary pattern, so the learned word is inert until the next 0x5555 reload/restart (025). Six required verdicts: drag-fix HELD (5px threshold intact, widget-overlay.ahk:341); mouse-capture always released → NOT a P0; 18 sound files all present + valid RIFF/WAVE; **dictionary terms ARE regex-escaped → SAFE, no ReDoS/injection** (proven via isolated AHK PCRE run — c++→c\+\+, a.*b literal, metachar keys no-throw); onboarding API key DPAPI-encrypted + never logged; a11y/DPI tagged T1.7. Key P2s: `mechanical` installed but omitted from settings dropdown (017, verifies T1.2-024); `default` theme relies on top-level sounds\*.wav present in installed app but MISSING from Development tree → next build regresses default audio to SoundBeep (019, cross-ref T1.3); `\b…\b` anchoring silently kills dict entries with leading/trailing non-word chars like c++/c#/.net (023); ParseDictionaryJson is a brittle regex parser not JSON.Parse (024); AddToDictionary + HideAndUpdateConfig write files without the config mutex (026/016, cross-ref T1.6). Cross-deps: T1.2 (dropdown HTML), T1.3 (build inputs), T1.6 (no-mutex writes), T1.7 (DPI/multimon). **Phase 3 live verification EXECUTED** (Playwright/CDP onboarding walkthrough: bad-key→error, good-key→"Connected successfully", mic test→"Recording successful", +screenshots; settings drive confirmed mechanical absent from live #soundTheme + c++ saveDictionary round-trip; 6 themes live-played; tray launch confirmed c++ compile-on-load; widget threshold via exact-code replica 0/2/5px=click,6/10px=drag). Only synthetic widget mouse-injection skipped (hung the AHK harness) — physical click + "Skip for now" no-op (002) owed to a manual eyeball. Configs restored; zero source changes.)
- ⬜ T1.5 — History retention + race condition fix
- ⬜ T1.6 — Version sync sweep + automation
- ⬜ T1.7 — Accessibility + multi-monitor + hotkey conflict fixes

### Phase 1 — Track 2 (New Systems)
- ⬜ T2.1 — Backend infra design (gate)
- ⬜ T2.2 — CF Worker license issuer
- ⬜ T2.3 — Trial + paywall
- ⬜ T2.4 — Crash reporting
- ⬜ T2.5 — Signed updates
- ⬜ T2.6 — Transcription regression corpus
- ⬜ T2.7 — (OPTIONAL) PostHog telemetry

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
