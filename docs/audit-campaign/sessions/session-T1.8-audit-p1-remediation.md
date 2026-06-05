# Session T1.8 — Track-1 Audit P1 Remediation (FIX)

> **Model:** Opus 4.8
> **Effort:** xhigh
> **Switch commands:** `/model claude-opus-4-8` then `/effort xhigh` _(4.8 defaults to `high` — you MUST set xhigh explicitly)_
> **Branch:** `audit/T1.8-audit-p1-remediation`
> **Parallel-safe with:** nothing — run solo. It edits `setup.iss`, `release.ps1`, `QuickSay.ahk`, and the data-path layer, which overlaps every other session's surface.
> **Depends on:** T1.3 + T1.4 findings (done, on their branches) AND the T2.1–T2.5 build line (the data-location fix must align with T2.3's `license.dat`/`trial.dat` choice). See "Base branch" below — the campaign's branches are not yet merged, so establishing a coherent base is step 0.
> **Blocks:** M.1 (integration should start from code where these 5 P1s are already fixed, not inherit them).
>
> Before pasting: confirm `/model claude-opus-4-8` and `/effort xhigh`. This session fixes 5 P1 bugs the read-only audits (T1.3, T1.4) surfaced but no fix session was assigned. One of them (T1.3-023, data location) **cross-cuts the already-built trial/license system** — treat it as the headline, not a footnote.

---

## Prompt to paste

You are remediating the five **P1** findings that the QuickSay Track-1 audits (T1.3 installer/release, T1.4 onboarding/widget/sound/dictionary) surfaced but that no fix session ever addressed. The audits were read-only; this session writes the fixes. Working directory: `C:\QuickSay\Development\` (plus `setup.iss` / `release.ps1` at the Development root).

This is a real-bug fix session, not an audit. Use `superpowers:systematic-debugging` to confirm each root cause against current code before changing it, `superpowers:test-driven-development` where a regression test is feasible, the `security-auditor` agent (`comprehensive-review` / `security-scanning`) for the two security-flavored P1s, and `superpowers:verification-before-completion` before you declare done.

### Context you must read first, in order

1. `C:\QuickSay\CLAUDE.md` — architecture, the runtime-directory split, `setup.iss`/`release.ps1` roles, the dual-sync gotcha.
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign structure + Status Tracker (you will update it at the end).
3. The two source findings docs (they live on the audit branches — read them via `git show` if not on your branch):
   - `git show origin/audit/T1.3-installer-release:docs/audit-campaign/findings/T1.3-installer.md`
   - `git show origin/audit/T1.4-onboarding-widget-sound-dict:docs/audit-campaign/findings/T1.4-onboarding-widget-sound-dict.md`
4. `docs/audit-campaign/specs/T2-production-systems-design.md` (T2.1 spec) — § on trial/license storage. The data-location fix (P1 #1 below) must end with the existing app's data path and T2.3's `license.dat`/`trial.dat` path being **the same place**.
5. The `quicksay-go-to-paid` skill — its installer-audit checklist + the `%APPDATA%\QuickSay\` assumption.

### Base branch (step 0 — do this before any fix)

The campaign's session branches are **not yet merged to main**, and they diverge: T1.3/T1.4/T1.6 are on one line; T2.1–T2.5 are on another. You need a base that contains **both** the Track-2 build (so you can see T2.3's `lib/license.ahk` data paths) **and** `setup.iss`/`release.ps1` in their current audited state.

1. Inspect the branch graph (`git log --oneline --all --graph | head -60`) and identify the Track-2 tip (the line with T2.1–T2.5).
2. Branch `audit/T1.8-audit-p1-remediation` off that Track-2 tip.
3. Bring in T1.6's `release.ps1` changes (VERSION SSOT + `--check-sync`) — cherry-pick or merge `origin/audit/T1.6-version-sync` — because P1 #3 (release rollback) edits the same file and must build on T1.6, not clobber it.
4. **Verify the current on-disk state of every file before fixing it** — the tree is mid-integration, so do not trust any finding's line numbers blindly; re-confirm against what's actually in your working copy. If a finding turns out already-fixed in your base, mark it RESOLVED-IN-BASE and move on.

If the branch topology is too tangled to get a clean base, STOP and report what you found — do not force a messy merge. A clean base is worth more than speed here.

---

## The five P1s to fix

### P1 #1 — T1.3-023: user data location is `{app}`, not `%APPDATA%\QuickSay\` (HEADLINE — cross-cuts Track 2)

**Problem.** The existing app resolves every data path from `A_ScriptDir` → `global ConfigFile := ScriptDir . "\config.json"`, so when installed, config/history/stats/audio all live under `{app}` = `%LOCALAPPDATA%\Programs\QuickSay Beta\`. But T2.3 placed `license.dat`/`trial.dat` under `%APPDATA%\QuickSay\`, and the T2.1 spec + `quicksay-go-to-paid` skill assume `%APPDATA%\QuickSay\` everywhere. **Right now the two halves disagree.** Worse: the uninstall "don't keep data" path does `DelTree {app}\data` — if the trial file ever lived under `{app}`, an uninstall/reinstall would reset the trial, defeating the anti-abuse design.

**Fix (decision = migrate to `%APPDATA%\QuickSay\`, per the Track-2 design).**
1. Introduce a single data-root resolver (e.g. `GetDataDir()` → `%APPDATA%\QuickSay\`) and route `ConfigFile`, `history.json`, `statistics.json`, `dictionary.json`, `data\audio\`, `data\logs\`, the onboarding-done marker, and `debug.txt` through it. No more `A_ScriptDir`-relative data paths.
2. Confirm T2.3's `lib/license.ahk` already uses `%APPDATA%\QuickSay\` and that they now resolve to the identical directory. If T2.3 hardcoded a slightly different path, reconcile to one canonical resolver.
3. **One-time migration:** on first run after upgrade, if `%APPDATA%\QuickSay\` is empty but `{app}\config.json` (or `{app}\data\`) exists, move the existing beta user's data over (config, history, stats, dictionary, audio). Idempotent; never destroy data on failure.
4. `setup.iss`: fix `[Dirs]`, `[UninstallDelete]`, and the uninstall data prompt so they target `%APPDATA%\QuickSay\` (and so the program dir under `{app}` is fully removed on uninstall while user data is preserved-or-removed per the user's choice).
5. Re-verify the dev `Development\data\` working-copy paths still work for local runs (the resolver should pick a sensible dev location when running uncompiled — match current behavior so the test harnesses and `live-runner.ps1` keep working).

This is the one with the most blast radius — touch it carefully, get the `security-auditor` to sanity-check the migration + the uninstall paths, and write a regression test for the resolver + migration if feasible.

### P1 #2 — T1.3-001: installer ships the developer's live `config.json` (encrypted key + personal prefs)

**Problem.** `setup.iss:72` does `Source: "config.json"; … Flags: onlyifdoesntexist`, shipping `Development/config.json` — which is YOUR working config (your DPAPI-encrypted `groqApiKey`, `launchAtStartup=1`, your widget position). Every fresh install inherits it; and because the shipped config *has* `launchAtStartup=1`, onboarding's `if !cfg.Has("launchAtStartup")` default-to-0 never fires, so every fresh install silently arms autorun (feeds P1 #5).

**Fix.** Ship a pristine seed, not your live file. Either generate a clean default at build time (no `groqApiKey`, `launchAtStartup=0`, neutral widget pos, a real existing `soundTheme` — NOT `default`/`silent` which have no dir, see T1.4-019), or point the installer's `Source:` at `config.example.json` rendered to `config.json`. The absence of `groqApiKey` makes onboarding correctly stay armed until the user enters a real `gsk_` key. Keep the `onlyifdoesntexist` flag (it correctly protects existing users on upgrade).

### P1 #3 — T1.3-011: half-done release leaves bumped source with no rollback

**Problem.** `release.ps1` STEP 1 mutates ~7 source files + `changelog.json` **before** compile/sign/ISCC/R2-upload. If the run dies mid-way (the documented Azure-sign hang, ISCC failure, R2 failure), the tree is left dirtied with a bumped-but-unreleased version, and STEP 7b commits only website files — the app-source bumps are never committed by the script. No `try/finally`, no rollback.

**Fix.** Wrap the pipeline so a failure restores source — snapshot before STEP 1 (`git stash` or record HEAD), restore on failure; or move the version mutation to *after* a successful compile+sign dry pass; at minimum, commit the app-source bumps on success so the tree is never left dirty-but-released. **Build on T1.6's `release.ps1`** (the VERSION SSOT + `--check-sync` gate) — coordinate, don't clobber. (Note for T2.5: T2.5's STEP-6 Ed25519 signing also lives in `release.ps1`; ensure your rollback wrapping is compatible with the signing step.)

### P1 #4 — T1.3-025: orphaned `HKCU\…\Run\QuickSay` autorun survives uninstall

**Problem.** The app (settings process) writes `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\QuickSay` → `"{app}\QuickSay.exe"`. The installer doesn't know about this value (it owns a separate `{userstartup}` shortcut), so uninstall leaves the `Run` value pointing at a deleted exe → ghost autorun error at every login. Combined with P1 #2, essentially every uninstall orphans it.

**Fix.** Add `[UninstallRun]` to delete the value, e.g. `Filename: "{cmd}"; Parameters: "/c reg delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v QuickSay /f"; Flags: runhidden; RunOnceId: "DelRunKey"`. Optionally also have the app delete its own `Run` value on clean exit. (P1 #2's `launchAtStartup=0` default reduces how often this key gets written in the first place.)

### P1 #5 — T1.4-025: "Learn from Selection" reports success but the learned word is inert until reload

**Problem.** `LearnFromSelection` → `AddToDictionary` (`QuickSay.ahk:~2659`) mutates the in-memory `Dictionary` and rewrites the file, shows *"Added N correction(s)"* (`:~2580`), **but never calls `CompileDictionaryPattern`** — so `DictCompiledPattern`/`DictReplacements` (what `ApplyDictionary` actually uses, `:~2011-2016`) stay stale. The correction does nothing until the next `0x5555` reload or restart. The success message lies.

**Fix.** Call `CompileDictionaryPattern()` at the end of `AddToDictionary` (or once after the `LearnFromSelection` loop). Confirm the compile uses the just-mutated `Dictionary`. Add a regression check if the dictionary test harness supports it.

---

## Phase plan

1. **Establish the base branch** (step 0 above). Report the topology you found and the base you chose before fixing.
2. **Confirm each root cause** against current on-disk code with `systematic-debugging`. Mark any already-fixed-in-base.
3. **Fix in this order:** #5 (smallest, isolated) → #2 (config seed) → #4 (uninstall reg, pairs with #2) → #3 (release rollback, on T1.6 base) → #1 (data location + migration — biggest, do last with the most context loaded).
4. **Security review** (`security-auditor`) specifically on #1 (migration + uninstall data paths) and #2 (no secret ships).
5. **Verify** with `verification-before-completion`: run the existing harnesses (`tests/history`, `tests/license`, `tests/playwright`, `live-runner.ps1`) and confirm nothing regressed from the data-path change; prove the migration moves data and is idempotent; prove a fresh `config.json` seed has no `groqApiKey` and `launchAtStartup=0`.

## Files you may modify

`QuickSay.ahk` (data-path resolver, migration, `AddToDictionary`), `lib/settings-ui.ahk` / `settings_ui.ahk` (data paths if referenced), `onboarding_ui.ahk` (data paths + `launchAtStartup` default), `setup.iss` ([Files] config seed, [Dirs]/[UninstallDelete]/[UninstallRun], data-dir targets), `release.ps1` (rollback wrapping, on T1.6 base), `config.example.json` (the clean seed), and new tests under `Development/tests/`. Touch `lib/license.ahk` only to *reconcile* its data path with the new resolver — do not redesign T2.3's logic.

## Done When

- [ ] All 5 P1s fixed (or explicitly marked RESOLVED-IN-BASE with evidence). Each fix cites the file:line changed.
- [ ] **Data location unified:** existing app data + T2.3's `license.dat`/`trial.dat` both resolve to `%APPDATA%\QuickSay\`; one-time migration moves legacy `{app}` data and is idempotent; `setup.iss` dirs/uninstall paths updated; uninstall "don't keep data" no longer wipes the trial file.
- [ ] Fresh-install `config.json` seed has no `groqApiKey` and `launchAtStartup=0`; `soundTheme` points at a real theme dir.
- [ ] `[UninstallRun]` removes the `HKCU\…\Run\QuickSay` value; verified it's gone after a simulated uninstall.
- [ ] `release.ps1` restores a clean tree on simulated mid-run failure; builds on T1.6's VERSION/`--check-sync`; compatible with T2.5's signing step.
- [ ] `AddToDictionary` recompiles the pattern; a learned word affects the very next transcription with no reload.
- [ ] `security-auditor` pass on #1 and #2; findings addressed.
- [ ] Existing harnesses still green (history, license, playwright, live-runner); no regression from the data-path change.
- [ ] `findings/T1.8-p1-remediation.md` written: per-P1 before/after, the data-location decision + migration design, and any T2.3/T2.1 reconciliation you had to do.
- [ ] MASTER-PLAN Status Tracker updated: add a T1.8 line → ✅, and (housekeeping) flip T1.3/T1.4/T1.6 to ✅ with their branch names, since they were done-but-unmarked.
- [ ] Branch `audit/T1.8-audit-p1-remediation` committed; PR opened.

## What NOT to do

- ❌ Do not redesign T2.3's trial/license logic. You only reconcile its *data path* with the unified resolver.
- ❌ Do not clobber T1.6's `release.ps1` changes — build on them.
- ❌ Do not ship any file containing a `gsk_` key or DPAPI blob as an installer seed. Prove the seed is clean.
- ❌ Do not destroy user data in the migration — move/copy with verification, never delete-then-write.
- ❌ Do not force a messy branch merge to get a base. If the topology is tangled, stop and report.
- ❌ Do not expand scope to P2/P3 findings — only the 5 P1s. (Note P2s like T1.4-019 "default theme is a build landmine" in your findings doc as recommended follow-ups for M.1, but don't fix them here unless trivially coupled to a P1 fix.)

## Estimated time

Step 0 base branch: 20–40 min (depends on topology). #5 + #2 + #4: ~45 min. #3 (rollback): ~30–45 min. #1 (data location + migration): ~90–120 min (the bulk). Security review + verification: ~45 min. **Total wall-clock: ~4–5 hours.**

## When you're done

Report: the base branch you chose + topology notes; per-P1 fixed/resolved-in-base with file:line; the data-location decision and how the migration works; any reconciliation you did against T2.3/T2.1; harness results; and the M.1 hand-off note (what integration still needs to know — e.g. "M.1: prod `license.dat` path is now `%APPDATA%\QuickSay\`; installer creates it; migration runs on first upgrade").
