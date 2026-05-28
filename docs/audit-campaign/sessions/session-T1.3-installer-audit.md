# Session T1.3 — Installer + `release.ps1` Audit (READ-ONLY)

> **Model:** Opus 4.7
> **Effort:** xhigh
> **Switch commands:** `/model opus` then `/effort xhigh`
> **Branch:** `audit/T1.3-installer-release`
> **Parallel-safe with:** T1.1, T1.2, T1.4 (different files, all read-only audits — open all four windows at once)
> **Depends on:** P0.2 (test harnesses + baseline)
> **Blocks:** T1.6 (version sync sweep + `release.ps1 --check-sync` gate builds directly on these findings)
>
> Before pasting: confirm `/model opus` (no `[1m]` flag — the installer/release surface is bounded; standard context is enough) and `/effort xhigh`. The deliverable is a findings doc, not a fix.

---

## Prompt to paste

You are performing a comprehensive, **read-only** audit of QuickSay's packaging and release pipeline: the Inno Setup installer, the release automation script, the code-signing config, and the bundled redistributables. **Make ZERO changes this session** — not to `setup.iss`, not to `release.ps1`, not to anything. The deliverable is a findings document with file:line citations and a precise clean-VM test procedure. The fixes land in T1.6 and M.1/M.3.

### Context

QuickSay ships as a signed Windows installer built with Inno Setup. The release pipeline (`release.ps1`) bumps the version, compiles `QuickSay.ahk` → `QuickSay.exe` with Ahk2Exe, signs binaries with **Azure Trusted Signing**, builds the installer with ISCC, uploads to Cloudflare R2, and writes `version.json` for the in-app auto-updater. The installer bundles the WebView2 runtime bootstrapper for machines that lack it.

Working directory: `C:\QuickSay\Development\`.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — the **Full Release Workflow**, the **Azure Signing Pre-Check** (the exact re-auth recipe — you will reference it), the **Required Build Files (Not in Git)** table, and the file map (`setup.iss`, `release.ps1`, `signing/metadata.json`, `redist/`).
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign context; §6 defines the version-sync regime that T1.6 will enforce (you feed it). You update the Status Tracker at the end.
3. `docs/audit-campaign/findings/P0.2-baseline.md` — the verified baseline. Item 5 (version-format mismatch) and the installer-exclusion confirmation are directly relevant. P0.2 already confirmed `setup.iss` does not bundle `tests/` — verify and extend.
4. `docs/audit-campaign/research/tooling-research.md` — §3 (Inno Setup audit approach — no real linter exists, write a PowerShell preflight; this is what T1.3 *recommends* and T1.6 builds), §4 (Windows desktop production checklist; **EV no longer buys SmartScreen reputation in 2026** — reputation is per-hash + per-publisher, earned via download volume).
5. The `quicksay-go-to-paid` skill (activated in P0.1) — its Section 1 is the Inno Setup installer audit checklist. Use it as your category backbone.

### Scope

| File / dir | Priority | Why |
|---|---|---|
| `setup.iss` | **CRITICAL** | The installer definition. `[Files]` Source lines, `[Registry]`, `[Run]`, `[UninstallDelete]`, version macros, the WebView2 bootstrap `[Code]` section, signing flags. |
| `release.ps1` | **CRITICAL** | The full pipeline: version bump → compile → sign → installer → R2 upload → version.json. Idempotency, failure modes, the Azure signing hang. |
| `signing/metadata.json` | **HIGH** | Azure Trusted Signing config (`Endpoint`, `CodeSigningAccountName`, `CertificateProfileName`). |
| `redist/` | **MEDIUM** | `MicrosoftEdgeWebview2Setup.exe` — the bundled WebView2 bootstrapper. |

**Forbidden** (owned by sibling sessions — do not audit, do not touch):
- `QuickSay.ahk` recording/transcription engine → T1.1. (You MAY read the version-string declarations near the top — `ScriptVersionInfo`, `localVersion` — to cross-reference version drift, cited as "cross-ref owned by T1.6". Nothing else.)
- `lib/settings-ui.ahk`, `gui/*` → T1.2 / T1.4.
- `onboarding_ui.ahk`, `widget-overlay.ahk`, `sounds/`, dictionary → T1.4.

### Known concrete anchors (verify, don't trust)

From a prior read of `setup.iss`:
- `setup.iss:5` — `#define MyAppVersion "1.9.0"`
- `setup.iss:14` — `AppVersion={#MyAppVersion}`
- `setup.iss:34` — `VersionInfoVersion={#MyAppVersion}`
- `setup.iss:38` — `VersionInfoProductVersion={#MyAppVersion}`
- `setup.iss:54` — `[Files]` section start
- `[Files]` Source lines (~`:57`–`:103`): `QuickSay.exe`, `QuickSay-Setup.exe`, `AutoHotkey64.exe`, `ffmpeg.exe`, `onboarding_ui.ahk`, `config.json` (onlyifdoesntexist), `dictionary.json` (onlyifdoesntexist), `data\changelog.json`, `gui\*` (excludes the two wizard bmps), `lib\*`, `64bit\*`, `sounds\*` (excludes `*.py,README.md`), the four `docs\*` legal files, `LICENSES\*`, `LICENSE`, and `redist\MicrosoftEdgeWebview2Setup.exe` (to `{tmp}`, `deleteafterinstall`).
- `setup.iss:117`–`:118` — `[Run]` postinstall entries (`QuickSay-Setup.exe` with `Check: not OnboardingAlreadyDone`; `QuickSay.exe` with `Check: OnboardingAlreadyDone`).

Re-read the file fresh and confirm these — line numbers may have shifted.

### Phase 1 — Map the pipeline (deep read)

Invoke the `code-review` skill and `superpowers:systematic-debugging` for this phase.

Produce a line-cited map and present it before findings:

1. **Installer file manifest.** Every `Source:` line in `setup.iss` → the file it points to → does that file exist in `Development/`? Note the `Flags` (`ignoreversion`, `onlyifdoesntexist`, `deleteafterinstall`, `recursesubdirs`) and what each implies for upgrade/preserve behavior. Pay attention to the wildcard sources (`gui\*`, `lib\*`, `64bit\*`, `sounds\*`) — what do they actually sweep, and do they pull in anything that should NOT ship (the `tests/` exclusion from P0.2, stray `.py` scripts, `README.md`, the wizard bmps)?
2. **Registry + uninstall surface.** Every `[Registry]` entry, `[UninstallDelete]`, and the uninstall behavior. What gets written to `HKCU` (the startup `Run` key is written by the app, not the installer per the surface inventory — confirm which side owns it). What does the uninstaller remove vs leave.
3. **The release pipeline stages.** Walk `release.ps1` top to bottom: version detection (`localVersion`), the version-string propagation across source files, compile (Ahk2Exe), sign (Azure), build installer (ISCC), R2 upload, `version.json` write. Note every external dependency (Azure CLI, ISCC path, R2 credentials) and every place the script can fail half-done.

### Phase 2 — Findings categories

For EVERY finding: ID (`T1.3-001`, …), severity (P0/P1/P2/P3), file:line, evidence snippet, recommended fix, owner-session tag (`owned by T1.6` / `owned by M.1` / `owned by M.3` / `owned by T1.3-followup`). Every bullet gets a finding or an explicit "no issue — here's the evidence." No hand-waving.

#### Category A — Installer file integrity

- [ ] **Every `Source:` file exists.** For each `[Files]` Source line, resolve the path against `Development/` and confirm the file is present. The CLAUDE.md "Required Build Files (Not in Git)" table lists files that must exist but aren't tracked (`gui/assets/wizard_*.bmp`, the four `docs/*` legal docs, `LICENSES/`, `LICENSE`, `dictionary.json`). Flag any Source line whose target is missing — that is a P0 build break. **Recommend a preflight** (per `tooling-research.md` §3: parse Source lines, assert each exists, fail fast) — this is what T1.6 will build into `release.ps1 --check-sync`.
- [ ] **Wildcard hygiene.** Do `gui\*`, `lib\*`, `64bit\*`, `sounds\*` sweep in unwanted files? Confirm the `Excludes:` are sufficient (`*.py,README.md` for sounds; the two bmps for gui). Confirm `tests/` is excluded by omission (P0.2 baseline) and that no wildcard would catch it. Flag any path that would ship dev artifacts, source `.ahk` that should be compiled, or secrets.
- [ ] **`onlyifdoesntexist` correctness.** `config.json` and `dictionary.json` use `onlyifdoesntexist` — confirm this is the right flag so an upgrade does NOT clobber the user's existing config/dictionary. Reason about: does the installed app actually read config from `{app}` or from `%APPDATA%\QuickSay\`? (CLAUDE.md says user data is in `%APPDATA%\QuickSay\data\` / `%LOCALAPPDATA%\Programs\QuickSay Beta\`.) If config lives in `%APPDATA%` at runtime but the installer drops a default into `{app}`, document the relationship and any orphan-file risk.
- [ ] **Version macros.** `MyAppVersion` (`setup.iss:5`) feeds `AppVersion`, `VersionInfoVersion`, `VersionInfoProductVersion`. Confirm. Cross-reference the P0.2 baseline item 5 version mismatch (`1.9.0` here vs `1.9.0-beta` in config vs `1.9.0.0` resource). Document every divergent version location — tag `owned by T1.6`.

#### Category B — `release.ps1` idempotency & failure modes

- [ ] **Re-run safety.** If `release.ps1` is run twice for the same version, what happens? Does it overwrite the R2 object, duplicate a GitHub release, double-bump the version, or fail cleanly? Document the actual behavior.
- [ ] **Half-done failure.** If the script dies after compile but before sign, or after sign but before R2 upload, what state is left? Are version strings already bumped in source (leaving the repo in an inconsistent committed-but-unreleased state)? Is there any rollback or is it manual cleanup?
- [ ] **`-Changelog` flow.** CLAUDE.md insists `-Changelog` must always be passed. What happens if it is omitted — silent empty changelog, or a prompt, or a failure? Recommend a guard.
- [ ] **External dependency assumptions.** Hardcoded paths (`C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe`, `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`), Azure CLI presence, R2 credentials. What is the failure message if any is missing? Is it actionable for a non-expert?
- [ ] **`--check-sync` precursor.** T1.6 will add `release.ps1 --check-sync` (single source of truth = `Development/VERSION`, per MASTER-PLAN.md §6). Document the exact list of files the gate must check (QuickSay.ahk `ScriptVersionInfo` + `localVersion`, `setup.iss` macros, `config.example.json` `lastSeenVersion`, `data/changelog.json` top entry, Website data, R2 `version.json`). This IS the spec T1.6 implements — make it complete.

#### Category C — Azure Trusted Signing

- [ ] **Token-refresh path.** CLAUDE.md documents the MFA-token-expiry hang ("Submitting digest for signing…") and the exact re-auth recipe (`az logout` → `az login --tenant "f93a0e57-..." --scope "https://codesigning.azure.net/.default"`, account `a.beeksma21@gmail.com`, test with `az account get-access-token --resource "https://codesigning.azure.net"`). **Reference this recipe in your findings** and assess: does `release.ps1` detect the hang and surface the recipe, or does it silently block forever? Recommend a pre-sign token check + a clear error pointing at the recipe (tag `owned by T1.6`).
- [ ] **Every binary signed.** Confirm `release.ps1` signs BOTH `QuickSay.exe` AND `QuickSay-Setup.exe` AND the final installer AND the uninstaller — all with the same cert (Microsoft groups SmartScreen reputation by cert hash + publisher; per `tooling-research.md` §4, consistent signing across binaries is what builds reputation). Flag any binary that ships unsigned.
- [ ] **`signing/metadata.json` integrity.** Confirm `Endpoint`, `CodeSigningAccountName`, `CertificateProfileName` are present and consistent with the CLAUDE.md tenant. Confirm no secret/token is committed in the file (it should be config, not credentials). Flag if any credential leaks into git.

#### Category D — SmartScreen + production-readiness checklist

Use the `quicksay-go-to-paid` skill's Section 1 + `tooling-research.md` §4 as the checklist.

- [ ] **SmartScreen reputation status.** Per the 2026 reality (`tooling-research.md` §4): EV does NOT grant instant reputation; it is earned by download volume per hash + publisher. Document QuickSay's current standing as best you can determine (is the publisher established? are downloads accumulating?) and the recommendation: stay on Azure Trusted Signing, sign every binary consistently, accumulate volume. This is informational — there is no code fix, but it must be in the findings so launch (M.3) sets expectations.
- [ ] **Manifest checks.** Does the compiled `QuickSay.exe` declare DPI-awareness and Windows 10/11 supportedOS GUIDs? (These come from the Ahk2Exe manifest / `ScriptVersionInfo`.) Document what is present. Tag manifest gaps `owned by T1.6` or `owned by M.1`.
- [ ] **Consistent ProductName/ProductVersion** across `QuickSay.exe`, the installer, and the uninstaller (per the Microsoft checklist). Flag inconsistencies.

#### Category E — Uninstall + residue (clean-VM behavior)

This is the highest-value section for launch confidence. The invariant to verify:
**Uninstall removes program files at `%LOCALAPPDATA%\Programs\QuickSay Beta\` but does NOT remove user data at `%APPDATA%\QuickSay\` (config, history, dictionary, statistics, future `license.dat`).**

- [ ] **Uninstaller scope.** From `setup.iss` (`[UninstallDelete]`, install dir, `AppId`), determine exactly what the uninstaller removes. Confirm it cleans the program dir. Confirm it leaves `%APPDATA%\QuickSay\` intact (so a reinstall keeps the user's settings + a future trial/license can't be trivially reset by uninstall — relevant to T2.3's trial-machine binding). Flag if it wipes user data without consent, or if it leaves the program dir dirty.
- [ ] **Registry residue.** After uninstall, is the uninstall entry (`HKCU\…\Uninstall\<AppId>`) removed? Is the startup `Run` key (written by the app) removed by uninstall, or orphaned (so Windows tries to launch a deleted exe at boot)? This is a common production wart — trace who owns the `Run` key and whether uninstall cleans it. Recommend a fix (tag `owned by M.1`).
- [ ] **WebView2 bootstrapper.** `redist\MicrosoftEdgeWebview2Setup.exe` ships to `{tmp}` with `deleteafterinstall`. Confirm the `[Code]` / `[Run]` logic: (1) runs the bootstrapper silently, (2) ONLY if the WebView2 runtime is missing (skip-if-present), (3) does not block or error on machines that already have it, (4) is cleaned up after. Cite the detection logic. Flag if it reinstalls WebView2 unconditionally or fails on already-present.

### Phase 3 — Clean-VM install procedure (document, don't necessarily run)

A true clean-VM smoke test belongs to **M.2** (UAT). Your job here is to **write the exact procedure** M.2 will follow, so M.2 is push-button. If a clean Windows VM is available to you, run it and record results; if not, document precisely and mark "not executed — for M.2."

The procedure must cover, in order:
1. Fresh Windows 11 VM, no WebView2 runtime pre-installed (or note how to remove it).
2. Run installer silently: `installer.exe /VERYSILENT /SUPPRESSMSGBOXES /LOG=install.log`. Assert exit code 0.
3. Verify expected files at `%LOCALAPPDATA%\Programs\QuickSay Beta\` and the WebView2 runtime got installed.
4. Verify the uninstall entry at `HKCU\…\Uninstall\<AppId>`.
5. Launch the app, confirm onboarding wizard fires (since `OnboardingAlreadyDone` is false on a fresh box), confirm the tray icon + hotkey work.
6. Verify user-data dir `%APPDATA%\QuickSay\` is created.
7. **Upgrade test:** install an older build first, then the new one over it; assert `config.json`/`history.json`/`dictionary.json` survive (the `onlyifdoesntexist` flags).
8. **Uninstall test:** run `unins000.exe /VERYSILENT`; assert program dir removed, `%APPDATA%\QuickSay\` preserved, `Run` key removed, uninstall registry entry removed, no orphaned files.
9. Capture every residue found into a residue table.

Hand this procedure to M.2 verbatim by putting it in your findings doc under a clearly labeled "## M.2 clean-VM procedure" heading.

### Done When

The following are all true. Do not declare complete without verifying each.

- [ ] `docs/audit-campaign/findings/T1.3-installer.md` written. Each finding has: ID, severity, file:line, evidence, recommended fix, owner-session tag.
- [ ] The **installer file manifest** (every Source line → file → exists? → flags implication) is at the top of the doc, with any missing-file P0 break flagged.
- [ ] Every Category A–E bullet has a finding or an explicit "no issue — here's the evidence."
- [ ] The **`--check-sync` file list** (Category B) is complete and explicit — it is T1.6's implementation spec.
- [ ] The **Azure token-refresh recipe** from CLAUDE.md is referenced, with a recommendation for `release.ps1` to detect the hang and surface it.
- [ ] The **uninstall/residue invariant** is verified with citations, and the `Run`-key residue question is answered.
- [ ] The **"## M.2 clean-VM procedure"** section is complete and push-button (run + recorded, OR documented + marked "for M.2").
- [ ] SmartScreen reputation status documented per the 2026 reality (informational, for M.3).
- [ ] **Zero changes to source.** `git diff` shows only the new findings file.
- [ ] MASTER-PLAN.md Status Tracker updated: T1.3 → ✅ done, with total finding count + P0/P1 count.
- [ ] Branch `audit/T1.3-installer-release` committed. Title: `T1.3 — Installer + release.ps1 audit (N total, N P0, N P1)`. PR opened against `main`.

### What NOT to do

- ❌ Do not modify `setup.iss`, `release.ps1`, `signing/metadata.json`, or anything else. Read-only. Recommend; do not fix.
- ❌ Do not run `release.ps1` for real (it bumps versions, signs, uploads to R2, cuts a GitHub release). You may dry-read it and reason about its behavior; you may run isolated, side-effect-free fragments (e.g. a Source-line parse) but never the full pipeline.
- ❌ Do not run a real Azure signing operation (it consumes MFA tokens and can hang). Reference the recipe; don't execute it.
- ❌ Do not upload anything to R2 or GitHub.
- ❌ Do not build the `--check-sync` gate or the preflight script — you SPEC them; T1.6 builds them.
- ❌ Do not fix the version drift — document every location and tag `owned by T1.6`.
- ❌ Do not touch the Forbidden files. Reading the version declarations at the top of `QuickSay.ahk` for cross-reference is the only exception.
- ❌ Do not skip the M.2 procedure section because no VM is handy — document it precisely for M.2.

### Estimated time

Phase 1 (pipeline mapping): ~45-60 min. Phase 2 (findings A–E): ~60-90 min. Phase 3 (M.2 procedure + optional VM run): ~30-45 min (longer if you actually run a VM). **Total wall-clock: ~2.5-3.5 hours.**

### When you're done

Report back with:
- Total finding count, P0 count, P1 count.
- Any missing `Source:` file (P0 build break) — name it.
- `release.ps1` idempotency verdict in one sentence (safe to re-run? what breaks?).
- The complete `--check-sync` file list you handed to T1.6.
- The uninstall residue verdict (does the `Run` key get orphaned? does user data survive?).
- Whether you ran the clean-VM procedure or left it for M.2.
- SmartScreen standing in one sentence.
- Confirmation MASTER-PLAN.md Status Tracker is updated and the PR is open.
