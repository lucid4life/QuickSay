# Session M.1 — Wire New Systems Into the Audited App → v2.0.0-rc1 (INTEGRATION)

> **Model:** Opus 4.7 [1m]
> **Effort:** xhigh
> **Switch commands:** `/model opus[1m]` then `/effort xhigh`
> **Branch:** `audit/M.1-integration`
> **Parallel-safe with:** nothing — this is the convergence session; everything else must be merged to `main` first.
> **Depends on:** ALL prior sessions — every Track 1 fix (T1.5/T1.6/T1.7), every Track 2 build (T2.2/T2.3/T2.4/T2.5/T2.6, + T2.7 if run), and the T1.6 `release.ps1 --check-sync` gate. Merge all of them to `main` before starting.
> **Blocks:** M.2 (UAT runs against the rc1 this session produces).
>
> Before pasting this prompt: confirm `/model opus[1m]` and `/effort xhigh`. You need 1M context because every subsystem coexists in your head here, and `xhigh` because integration conflicts are where latent bugs hide. Confirm via the MASTER-PLAN Status Tracker that every dependency session is ✅ before you begin.

---

## Prompt to paste

You are integrating all the Track 2 production systems into the Track-1-audited QuickSay app and producing the first release candidate: **v2.0.0-rc1**, signed and installable. This is the convergence point of the entire campaign. Bias hard toward **minimal glue** — the subsystems were built to spec; your job is to wire them together, resolve the integration conflicts the parallel work created, and prove the whole thing builds, signs, installs, and runs. **This is not a place to refactor or add features.**

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2) going from open beta to a paid v2.0.0. Over the campaign, two tracks ran in parallel:
- **Track 1** audited and hardened the existing app (core engine, UI, installer, onboarding) and fixed history retention + the clear-history race (T1.5), version drift (T1.6 — shipped `release.ps1 --check-sync` + a `VERSION` source of truth), and accessibility/multi-monitor/hotkey conflicts (T1.7).
- **Track 2** built new production systems: the CF Worker license issuer (T2.2, on staging), the trial + paywall + LemonSqueezy activation flow (T2.3), crash reporting (T2.4), signed updates (T2.5), the transcription regression corpus (T2.6), and optionally telemetry (T2.7).

Each track merged to `main` independently. They have NOT been exercised together. The known integration hotspots:
- **The paywall recording-gate (T2.3) must coexist with the T1.5 history/retention fix and the T1.7 hotkey/accessibility changes.** All three touch the recording entry path and `QuickSay.ahk` startup. A naive merge can double-gate recording or skip the trial check.
- **The signed-update verification (T2.5) changes `CheckForUpdates()`**, which T1.6's version sync also touches (version strings + `version.json`). They must agree on the `version.json` schema.
- **Crash reporting (T2.4) and telemetry (T2.7, if present) both add emit points and share a PII scrub discipline.** Confirm they don't double-report or leak.
- **`release.ps1 --check-sync` (T1.6)** is now a hard gate — the build won't proceed if any version string is out of sync. The new files (`lib/license.ahk`, etc.) may carry version strings that need to be in the sync set.

Working directory: `C:\QuickSay\Development\`.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — full architecture, build commands, `release.ps1` workflow, Azure signing pre-check, dual-function-sync rule (`GetDefaultModes()` in both `QuickSay.ahk` and `lib/settings-ui.ahk`), required-build-files-not-in-git list, IPC target window name.
2. `C:\QuickSay\docs\audit-campaign\MASTER-PLAN.md` — §6 (infra topology + version sync regime), §7 (risk register), and the Status Tracker (confirm all deps ✅).
3. `C:\QuickSay\docs\audit-campaign\specs\T2-production-systems-design.md` — the contracts every Track 2 piece was built to. Your integration must preserve these contracts, not bend them.
4. All Track 1 findings docs (`findings/T1.1`…`T1.4`) — re-scan for any P0/P1 marked "owned by M.1" or "integration concern."
5. The UX-decisions doc from T2.3 (`findings/T2.3-ux-decisions.md`) — the paywall blocking behavior you must preserve when wiring the recording gate.
6. The `quicksay-go-to-paid` skill — invoke it (installer audit checklist, the locked decisions, the anti-patterns to flag).

Run the `audit-project` plugin's `/audit-project` slash command (activated in P0.1) as a cross-cutting integration sweep if it helps surface seams.

### Scope — what you may touch

This is integration glue. You may modify:
- `Development/QuickSay.ahk` — to wire the trial/paywall gate, crash hook, signed-update check, and (if present) telemetry emit points into a single coherent startup + recording path. **Minimal edits to reconcile the merge, not a rewrite.**
- Small reconciliation edits across `lib/license.ahk`, `lib/crash.ahk` (or whatever T2.4 named it), `lib/update.ahk` (or wherever T2.5's signing verification lives), `lib/telemetry.ahk` — ONLY where two sessions' code collides and needs a referee.
- `Development/setup.iss` — to add the new files (`lib/license.ahk`, `gui/paywall.html`, etc.) to the `[Files]` section so they're bundled. Confirm every new `Source:` resolves.
- `Development/VERSION` and the version-string set — bump to `2.0.0-rc1` (or `2.0.0` with rc tracked separately — follow T1.6's `--check-sync` convention).
- `Development/config.example.json` — reconcile any new fields from multiple sessions.

**Forbidden:**
- ❌ `Backend/license-worker/*` — T2.2 owns it. You may flip the app's endpoint from staging→production ONLY if the user confirms; otherwise rc1 points at staging for UAT. (Production cutover is properly M.3.)
- ❌ `Website/*` — that's M.3.
- ❌ New features, refactors, or "while I'm here" cleanups. If you spot something, `spawn_task` it.
- ❌ Changing any subsystem's contract from the T2.1 spec. If two pieces disagree, the spec is the referee — reconcile to the spec, don't invent a third behavior.

### Phase 1 — Sync, confirm, map the seams

1. `git pull origin main`. Confirm via the MASTER-PLAN Status Tracker that every dependency is ✅. If any required session is incomplete, STOP and report which — do not integrate against a half-built subsystem.
2. Build the **integration seam map**: for each hotspot above, find the exact lines in `QuickSay.ahk` (and the lib files) where two sessions' work meets. List them. The four critical seams: (a) startup license/trial check ordering, (b) the per-recording gate, (c) `CheckForUpdates()` signed-manifest verification vs version sync, (d) crash + telemetry emit points.
3. Present the seam map to the user before editing.

### Phase 2 — Resolve the seams, minimal glue

Invoke `code-reviewer` mentally as you go. Resolve each seam:

- **Startup ordering:** establish one clear startup sequence — load config → init trial/license state (T2.3) → register crash handler (T2.4) → register hotkey (T1.7) → deferred update check (T2.5) → optional telemetry app_started (T2.7). Document the order in a comment. No subsystem should silently depend on running before another.
- **Recording gate:** there must be exactly ONE gate that refuses to record in `PAYWALL_BLOCKING` state (per T2.3's UX-decisions doc), and it must not interfere with the T1.5 history-write path or the T1.7 hotkey-conflict handling. Confirm: in LICENSED / TRIAL_ACTIVE / GRACE_PERIOD the recording path is byte-for-byte the audited Track 1 behavior. In PAYWALL_BLOCKING, recording is refused but settings/help/paywall still open.
- **Signed updates vs version sync:** `CheckForUpdates()` verifies the `version.json` Ed25519 signature (T2.5) AND reads the version produced by T1.6's sync regime. Confirm the `version.json` schema is the single one from the T2.1 spec, and that `--check-sync` knows about every version string including any in the new files.
- **Crash + telemetry:** confirm they don't double-emit the same event and that both honor the shared scrub list (no transcript, no JWT, no key, no PII). Crash reporting is opt-in; telemetry (if present) is opt-in and off by default — confirm a fresh install with both off sends nothing.

Keep edits surgical. Every edit should be traceable to a named seam.

### Phase 3 — Run the gates

1. **Version sync gate (T1.6):** run `release.ps1 --check-sync` (or the exact invocation T1.6 defined). It MUST pass. If it flags a drift, fix the drifting string — do not bypass the gate.
2. **Transcription regression (T2.6):** run the regression corpus runner (`tests/transcription/` per P0.2 / T2.6). Confirm no WER regression and the hallucination filter still behaves. Paste the summary.
3. **WebView2 / UI suite (T1.2 / T1.4):** run the Playwright-over-CDP suite (`tests/playwright/`) against settings + onboarding + the new paywall UI. Confirm the paywall renders and its CTAs work, and that settings (including the new License tab and, if present, the telemetry toggle) still pass.
4. **All unit test suites:** history (T1.5), license (T2.3), telemetry (T2.7 if present), and any others. All green.

### Phase 4 — Build, sign, install v2.0.0-rc1

Follow the CLAUDE.md release workflow. **Azure signing pre-check first** — MFA tokens expire; if `az account get-access-token --resource "https://codesigning.azure.net"` fails, re-auth per CLAUDE.md before building.

1. Bump the version to the rc1 value across the sync set (let `release.ps1` do it). Confirm the required-build-files-not-in-git (wizard bmps, license rtf/html, etc. per CLAUDE.md) are present in `Development/`.
2. Compile `QuickSay.ahk` → `QuickSay.exe` and `onboarding_ui.ahk` → setup binary per the build commands.
3. Sign with Azure Trusted Signing (same cert for main + uninstaller — SmartScreen groups by cert hash).
4. Build the Inno Setup installer. Confirm every `Source:` line resolves (the new files are bundled).
5. Produce a **signed `version.json`** (Ed25519 per T2.5) for the rc — but do NOT publish rc1 to the public R2 path (rc1 is internal per the MASTER-PLAN glossary; M.2 tests it, M.3 ships the real 2.0.0).

### Phase 5 — Install + smoke on the dev box

Invoke `verification-before-completion`. On THIS machine (or a clean profile):
1. Install the rc1 installer (silent or interactive). Confirm files land at `%LOCALAPPDATA%\Programs\QuickSay Beta\` and user data at `%APPDATA%\QuickSay\`.
2. Launch. Confirm: tray icon, hotkey registers, **a fresh trial starts** (TRIAL_ACTIVE), settings opens with the License tab showing the trial countdown.
3. **Full dictation smoke:** hold hotkey, speak, release → transcript pastes at cursor. This is the non-negotiable core — it must work exactly as the audited Track 1 behavior.
4. **Paywall smoke:** shim `trialStartedAt` to 15 days ago in `license.dat` (or set the clock) → relaunch → paywall blocks recording; "Get my license" opens the LemonSqueezy URL; pasting the **T2.2 staging test license key** activates → LICENSED → recording restored.
5. **Update smoke:** point `CheckForUpdates()` at a signed test `version.json` → valid signature accepted; tamper one byte → rejected (no download).
6. **Crash smoke:** trigger the crash path (with reporting opted in) → a scrubbed envelope is produced (inspect it: no transcript, no JWT, no key).
7. Confirm NO unresolved Track 1 P0/P1 remains and NO new regression was introduced by the integration.

### Done When

- [ ] Integration seam map produced and all four seams resolved with minimal, traceable glue.
- [ ] `release.ps1 --check-sync` passes (version sync clean across the whole set including new files).
- [ ] Transcription regression (T2.6) passes — no WER regression, hallucination filter intact.
- [ ] Playwright UI suite (settings + onboarding + paywall) passes.
- [ ] All unit suites (history, license, telemetry-if-present, others) pass.
- [ ] **v2.0.0-rc1 compiled, Azure-signed (main + uninstaller, same cert), Inno-installer built**, every `Source:` resolves.
- [ ] `version.json` for the rc is Ed25519-signed (T2.5).
- [ ] rc1 installs cleanly on the dev box; full dictation smoke passes; paywall + activation (against staging key) works; signed-update accept/reject works; crash envelope is scrubbed.
- [ ] No unresolved Track 1 P0/P1; no new regressions from integration.
- [ ] rc1 NOT published to the public R2 download path (internal only).
- [ ] `docs/audit-campaign/MASTER-PLAN.md` Status Tracker updated: M.1 → ✅, noting the rc1 version string and that the app points at LICENSE **staging** for UAT.
- [ ] Branch `audit/M.1-integration` committed (use `commit-commands:commit`). PR opened against `main`.

### What NOT to do

- ❌ Do not add features or refactor. Glue only. `spawn_task` anything you're tempted to "improve."
- ❌ Do not change any subsystem's contract. The T2.1 spec is the referee for every disagreement.
- ❌ Do not point the app at the PRODUCTION license worker (`license.quicksay.app`) for rc1 — staging is correct for UAT. Production cutover is M.3 (or only with explicit user confirmation here).
- ❌ Do not publish rc1 to the public R2 path or cut a GitHub release. That's M.3 with the real 2.0.0.
- ❌ Do not bypass `release.ps1 --check-sync`. If it fails, fix the drift.
- ❌ Do not skip the Azure signing pre-check — a hung "Submitting digest for signing…" means the token expired (re-auth per CLAUDE.md).
- ❌ Do not let the paywall gate block settings/help/paywall paths — only recording.
- ❌ Do not double-gate recording or run the trial check twice. Exactly one gate, one startup sequence.
- ❌ Do not touch the website.

### Estimated time

Phase 1 (sync + seam map): 45–60 min. Phase 2 (resolve seams): 90 min. Phase 3 (run all gates): 45–60 min. Phase 4 (build + sign + installer): 45–60 min (longer if Azure re-auth needed). Phase 5 (install + 7 smokes): 60–90 min. **Total wall-clock: ~5–6.5 hours.**

### When you're done

Report back with:
- The rc1 version string and the path to the built (signed) installer.
- The integration seam map and how each seam was resolved (one line each).
- Pass/fail for every gate (check-sync, transcription regression, Playwright UI, all unit suites).
- Pass/fail for all 7 dev-box smokes.
- Confirmation the app points at staging (not prod) license worker.
- Any residual risk or unresolved item M.2 should specifically probe.
- Any cross-session item to add to MASTER-PLAN (e.g. "M.3 must `wrangler deploy --env production` and flip the app's license endpoint to prod").
