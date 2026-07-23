# Session T1.6 — Version Sync Sweep + `release.ps1 --check-sync` Gate (FIX + TOOLING)

> **Model:** Sonnet 4.6
> **Effort:** medium
> **Switch commands:** `/model sonnet` then `/effort medium`
> **Branch:** `audit/T1.6-version-sync`
> **Parallel-safe with:** T1.5, T1.7, all of Track 2 (different files — you own the version-string surface + release pipeline; coordinate only if T1.3/T1.5 are mid-flight on the same lines)
> **Depends on:** T1.3 findings (`docs/audit-campaign/findings/T1.3-installer-release.md` — the installer/release audit located the version-string divergences you will fix here)
> **Blocks:** **M.1 (gate).** The integration session refuses to build `v2.0.0-rc1` unless `release.ps1 --check-sync` returns 0. This session creates that gate.
>
> Before pasting this prompt: confirm `/model sonnet` and `/effort medium`. This is mechanical, spec-driven sweep + automation work — do NOT burn Opus on it. There is no `xhigh` on Sonnet; `medium` is correct for this scope.

---

## Prompt to paste

You are eliminating **version drift** in QuickSay and building the automated gate that prevents it from ever recurring. Today the version is spelled differently across the codebase (`1.9.0` in some files, `1.9.0.0` in resource metadata, possibly `1.9.0-beta` somewhere in config/website history). Before the paid v2.0.0 release, every tracked file must agree on the version, derived from a **single source of truth** — and a build-time check must fail loudly if any file diverges.

This session has two deliverables:
1. **Create `Development/VERSION`** — the single source of truth (one line, e.g. `2.0.0`).
2. **Add `release.ps1 --check-sync`** — reads `Development/VERSION`, asserts every tracked file's version string matches, exits `0` when clean and `1` on any drift. Wire it as a pre-commit hook (or local CI check) so drift is caught before it lands.

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2). The release pipeline `release.ps1` (in `Development/`) already auto-detects the current version from `localVersion := "..."` in `QuickSay.ahk` and rewrites version strings across several files before compiling (it has an `Update-FileVersion` helper). What it does NOT have:

- A single canonical source-of-truth file. Right now `QuickSay.ahk`'s `localVersion` is the de-facto source, which is fragile — it's buried in 3,400 lines of app code and is also a runtime constant.
- A **verification** mode that checks all files agree without rewriting anything. The rewrite path can silently miss a file (e.g. the website, the changelog top entry) and nobody notices until a user sees the wrong version in the update dialog.
- Any enforcement (hook / CI) that blocks a commit or build when drift exists.

Working directory: `C:\QuickSay\Development\` for the app/pipeline work. The website source lives at `C:\QuickSay\Website\` (sibling directory — a **separate git repo**; see CLAUDE.md "Repo Structure"). You will *read* and update the website's displayed-version reference, but be aware it commits to the root monorepo, not the Development repo.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — file map, build commands, "Full Release Workflow", "Development vs Production Directories", "Repo Structure" (two independent git repos).
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign context, §6 "Version sync regime" (this session implements it), Status Tracker (you update it at the end).
3. `docs/audit-campaign/findings/T1.3-installer-release.md` — the installer/release audit. Every finding tagged "owned by T1.6" or mentioning version divergence is in scope. **Read this before touching anything** — T1.3 already located the divergences; do not re-discover them blindly, but DO verify each against the live source.
4. `docs/audit-campaign/research/tooling-research.md` — §3 (Inno Setup), §4 (consistent ProductName/ProductVersion across binaries is a Microsoft cert checklist item), §6 (version.json wire format).

### The complete version-string surface — sweep ALL of these

The version appears (or should appear) in every location below. Your sweep must find and reconcile **every one**. T1.3 confirmed the line numbers; re-verify with Grep before editing because earlier sessions (T1.5, T1.7) may have shifted lines.

| # | File | Token / pattern | Current (verify) | Format |
|---|---|---|---|---|
| 1 | `Development/VERSION` | entire file | **does not exist — you create it** | `MAJOR.MINOR.PATCH` (e.g. `2.0.0`) |
| 2 | `Development/QuickSay.ahk` | `;@Ahk2Exe-SetFileVersion X.X.X.X` (~line 3) | `1.9.0.0` | 4-part |
| 3 | `Development/QuickSay.ahk` | `;@Ahk2Exe-SetProductVersion X.X.X.X` (~line 5) | `1.9.0.0` | 4-part |
| 4 | `Development/QuickSay.ahk` | `localVersion := "X.X.X"` (~line 3398, inside `CheckForUpdates`) | `1.9.0` | 3-part |
| 5 | `Development/setup.iss` | `#define MyAppVersion "X.X.X"` (~line 5) | `1.9.0` | 3-part |
| 6 | `Development/setup.iss` | `AppVersion={#MyAppVersion}` (~line 14) | derived | 3-part (derived) |
| 7 | `Development/setup.iss` | `VersionInfoVersion={#MyAppVersion}` (~line 34) | derived | 3-part (derived) |
| 8 | `Development/setup.iss` | `VersionInfoProductVersion={#MyAppVersion}` (~line 38) | derived | 3-part (derived) |
| 9 | `Development/onboarding_ui.ahk` | `;@Ahk2Exe-SetFileVersion` + `SetProductVersion` (release.ps1 already rewrites these — verify) | `1.9.0.0` | 4-part |
| 10 | `Development/config.example.json` | `lastSeenVersion` field | verify | 3-part |
| 11 | `Development/data/changelog.json` | top entry `version` field | verify | 3-part |
| 12 | `Website/src/data/*` (changelog/version data files — Grep to locate) | displayed-version reference | verify | 3-part |
| 13 | `version.json` deployed to R2 by `release.ps1` (the `version` field written during release) | the value `release.ps1` writes | derived at release | 3-part |

**Format rule:** The canonical form in `VERSION` is **3-part semver** (`2.0.0`). The two 4-part `@Ahk2Exe-Set*Version` resource fields require a trailing `.0` (Windows resource versions are 4-part). The check-sync logic must treat `2.0.0` and `2.0.0.0` as **matching** by normalizing both to 4-part before comparison. Document this normalization explicitly.

> Note: `setup.iss` items 6–8 derive from `#define MyAppVersion` (item 5) via `{#MyAppVersion}`. The check only needs to assert that `#define MyAppVersion` matches `VERSION`; the derived fields follow automatically. But the check should still confirm the `{#MyAppVersion}` references exist (a refactor could break the derivation).

### Phase 0 — Sync with `main` and read T1.3

```powershell
git fetch origin
git checkout -b audit/T1.6-version-sync origin/main
```

Read `docs/audit-campaign/findings/T1.3-installer-release.md` end to end. Extract every version-related finding into a scratchpad with its file:line. If T1.3 has NOT been completed yet (file missing or its Status Tracker entry is not ✅), **stop and report** — this session depends on T1.3's findings. Do not proceed on guesses.

### Phase 1 — Inventory the live surface (verify, don't trust)

Invoke `superpowers:systematic-debugging` for the mapping.

For each of the 13 rows above, use Grep to locate the exact current line and value. Produce a table in a scratchpad: `file:line | pattern | current value | target value`. Flag any **divergence** (e.g. config says `1.9.0-beta` but resource says `1.9.0.0`). Note any version-bearing location NOT in the table that you discover — the table is a starting point from T1.3, not gospel.

Specifically confirm or refute these suspected divergences (from the original audit brief):
- [ ] `1.9.0-beta` in config vs `1.9.0.0` in resource metadata — does the `-beta` suffix actually exist anywhere tracked? (Check `config.example.json`, `data/changelog.json`, website data, AND `git log --all -S "1.9.0-beta"` to see if it ever existed.)
- [ ] 3-part vs 4-part inconsistency between the AHK resource directives and `localVersion`.
- [ ] Website displayed version lagging the app version.

Present this inventory to me before changing any file.

### Phase 2 — Create `Development/VERSION` (single source of truth)

Create `Development/VERSION` containing exactly one line: the current canonical version (use whatever the app is actually at right now — likely `1.9.0` — NOT `2.0.0` yet; the bump to `2.0.0` happens at the real release in M.3, not here). One trailing newline, no other content, no BOM.

Rationale to record in your commit message: a plain `VERSION` file is the conventional single-source-of-truth pattern (used by countless projects). It is trivially readable by `release.ps1`, by a pre-commit hook, by CI, and by a human. It removes `localVersion` in `QuickSay.ahk` from being the de-facto source.

### Phase 3 — Refactor `release.ps1` to read from `VERSION`

`release.ps1` currently derives the current version via `Get-CurrentVersion` (regex on `localVersion := "..."` in `QuickSay.ahk`, ~line 39-49). Change this so:

- `Get-CurrentVersion` reads `Development/VERSION` as the authoritative current version (fall back to the `QuickSay.ahk` regex with a **warning** only if `VERSION` is missing, so an old checkout still works).
- When `release.ps1` bumps the version (patch/minor/major or explicit `-Version`), it writes the new version to `Development/VERSION` **first**, then propagates to all other files via the existing `Update-FileVersion` calls.
- Do NOT change the existing `Update-FileVersion` rewrite behavior beyond pointing it at `VERSION` as the source. The rewrite path already touches items 2,3,4,5,9 (verify) — extend it to also rewrite items 10 (`lastSeenVersion`), 11 (changelog top entry — only if a `-Changelog` was given, else leave), and 13 (`version.json` it already writes). Item 12 (website) is a separate repo; have `release.ps1` print a reminder to update + deploy the website rather than reaching across repos.

### Phase 4 — Build `release.ps1 --check-sync`

Add a new parameter `-CheckSync` (switch) to `release.ps1`. When invoked as `.\release.ps1 --check-sync` (also accept `-CheckSync`), it:

1. Reads `Development/VERSION` → `$expected` (3-part).
2. Computes `$expected4 = "$expected.0"` (4-part normalization).
3. For each file in the surface table, Grep/regex out the actual version value.
4. Normalizes both sides to 4-part for comparison (so `2.0.0` ≡ `2.0.0.0`).
5. Collects **all** mismatches (don't bail on first — report every drift in one pass).
6. **Does NOT modify any file.** This is read-only verification.
7. Prints a clean table: `OK` / `DRIFT (found X, expected Y)` per file.
8. Exit code: `0` if all match, `1` if any drift. The exit code is the gate — M.1 and the pre-commit hook depend on it.

For the website (item 12, separate repo): `--check-sync` should check it **only if** `C:\QuickSay\Website\` is reachable, and treat an unreachable website path as a **warning, not a failure** (because the Development repo can be cloned standalone). Document this behavior.

Implementation notes:
- Keep it pure PowerShell (no external deps) — runs in the same environment as the rest of `release.ps1`.
- Use `Set-StrictMode -Version Latest` consistency with the existing script.
- Reuse the existing regex patterns from `Update-FileVersion` calls where possible — they already know how to find each version string. Factor the patterns into one `$VersionTargets` array of `@{ File=...; Pattern=...; Format='3'|'4' }` so check-sync and the rewrite path share one definition (DRY — a new file added in one place is checked in both).
- `--check-sync` must run standalone in <2 seconds with no side effects (no compile, no signing, no upload).

### Phase 5 — Wire the enforcement gate (pre-commit hook OR CI check)

Add **one** enforcement mechanism. Prefer a **Git pre-commit hook** because the campaign runs locally with no CI server yet:

- Create `Development/.githooks/pre-commit` (a portable location — not `.git/hooks/`, which isn't tracked).
- The hook runs `pwsh -NoProfile -File release.ps1 -CheckSync` (or invokes a thin wrapper) and **aborts the commit** (exit non-zero) on drift, printing the drift table.
- Add a one-time setup line to CLAUDE.md and to the hook itself: `git config core.hooksPath Development/.githooks` to activate it. (Do not run `git config` yourself unless the user asks — document the command instead, per the git-safety rules.)
- Make the hook **fast and skippable in emergencies** via `QUICKSAY_SKIP_VERSION_CHECK=1` env var (documented), but default-on.

If a GitHub Actions workflow already exists in the repo, add a `version-sync` job to it **instead of** the hook (or in addition, your call — but at minimum the local hook must exist since the campaign is local-first). Check for `.github/workflows/` before deciding.

### Phase 6 — Document in CLAUDE.md

Update `C:\QuickSay\CLAUDE.md`:
- In the "Build Commands" or "Full Release Workflow" section, document `.\release.ps1 --check-sync` (what it does, exit codes, when to run it).
- Document `Development/VERSION` as the single source of truth in the version regime.
- Document the pre-commit hook activation (`git config core.hooksPath Development/.githooks`) and the `QUICKSAY_SKIP_VERSION_CHECK=1` escape hatch.
- Note that the website version (item 12) lives in a separate repo and is a warning-not-failure in check-sync.

Keep edits surgical — add to the relevant existing sections, do not restructure CLAUDE.md.

### Phase 7 — Verification (the Done-When evidence)

Invoke `superpowers:verification-before-completion`. Produce **actual command output** for each gate below — do not assert without evidence.

1. **Clean state returns 0:**
   ```powershell
   .\release.ps1 --check-sync ; echo "EXIT: $LASTEXITCODE"
   ```
   After your sweep, all files agree → prints all `OK` → `EXIT: 0`.

2. **Injected drift returns 1:** Temporarily edit ONE tracked file's version (e.g. change `config.example.json` `lastSeenVersion` to `9.9.9`), then:
   ```powershell
   .\release.ps1 --check-sync ; echo "EXIT: $LASTEXITCODE"
   ```
   Must print `DRIFT (found 9.9.9, expected ...)` for that file and `EXIT: 1`. **Revert the temporary edit** afterward and re-run to confirm `EXIT: 0`.

3. **Normalization works:** Confirm the 4-part resource fields (`2.0.0.0`) are reported `OK` against a 3-part `VERSION` (`2.0.0`) — i.e. normalization is not a false-positive drift.

4. **Hook fires:** With the hook active, stage a file with injected drift and attempt a commit → commit is aborted with the drift table. (Then revert.) Capture the output.

5. **No source behavior change:** `git diff` shows only: new `VERSION`, `release.ps1` changes, new `.githooks/pre-commit`, CLAUDE.md doc additions, and any genuine version-string reconciliations. The app's runtime behavior is unchanged (you only reconciled version *strings* to agree; you did not change the version *value* — unless a divergence forced a pick, in which case you picked the value the app actually reports today and documented why).

6. **`-beta` is gone:** `git grep "beta" -- "*.json" "*.ahk" "*.iss"` shows no `1.9.0-beta` style version suffix in tracked files (legitimate non-version uses of the word "beta" — like "QuickSay Beta" the product name — are fine; only version-suffix `-beta` is forbidden).

Invoke `code-review` on your diff before committing. Address every P0/P1 the reviewer flags.

### Done When

Verify EACH — do not declare complete without evidence:

- [ ] `Development/VERSION` exists, one line, current canonical version, single trailing newline.
- [ ] `release.ps1` reads `VERSION` as source of truth (with a warning-fallback to the old regex if `VERSION` missing).
- [ ] `release.ps1 --check-sync` (and `-CheckSync`) exists, is read-only, reports per-file `OK`/`DRIFT`, **returns 0 when clean and 1 on any drift** — proven with the injected-drift test (gate 2).
- [ ] Version-string surface reconciled: all 13 rows agree (where applicable; website is warning-only). The `1.9.0-beta` suffix is gone from tracked files.
- [ ] 3-part/4-part normalization is correct — no false drift on the resource fields (gate 3).
- [ ] Pre-commit hook at `Development/.githooks/pre-commit` aborts commits on drift (gate 4), with `QUICKSAY_SKIP_VERSION_CHECK=1` escape hatch.
- [ ] CLAUDE.md documents `--check-sync`, the `VERSION` source of truth, hook activation, and the escape hatch.
- [ ] `git diff` shows ONLY version-sync + tooling + doc changes — no incidental app-behavior changes.
- [ ] `code-review` run on the diff; P0/P1 addressed.
- [ ] Branch `audit/T1.6-version-sync` committed; PR opened against `main`.
- [ ] MASTER-PLAN.md Status Tracker updated: `T1.6 — Version sync sweep + automation` → ✅ done. Note in the PR description that the **M.1 gate is now live** (`--check-sync` must return 0 before rc1).

### What NOT to do

- ❌ Do not bump the version to `2.0.0` in this session. The real bump happens at the M.3 launch. `VERSION` holds the **current** version (likely `1.9.0`). This session makes everything agree on the current value and builds the gate — it does not release.
- ❌ Do not change the version *value* anywhere to fix a divergence without recording the decision. If `localVersion` says `1.9.0` and config says `1.8.9`, the correct value is whatever the app actually ships as today (almost always `localVersion`) — pick it, reconcile to it, and note why.
- ❌ Do not rewrite the existing `Update-FileVersion` rewrite logic from scratch. Refactor it to share the `$VersionTargets` definition with `--check-sync`; don't reinvent it.
- ❌ Do not reach across repos to commit the website. `Website/` is a separate git repo. Update its version string if trivially needed, but the website **commit + deploy** is a separate manual step (and largely M.3's job). At most, print a reminder.
- ❌ Do not install or depend on any external tool (no Node, no jq) for `--check-sync`. Pure PowerShell only.
- ❌ Do not put the hook in `.git/hooks/` (untracked, won't survive clone). Use `Development/.githooks/` + `core.hooksPath`.
- ❌ Do not run `git config` yourself to set `core.hooksPath` unless the user explicitly asks — document the command instead (git-safety rule).
- ❌ Do not modify app runtime behavior. This is version-string + pipeline tooling only.
- ❌ Do not refactor unrelated parts of `release.ps1` "while you're in there." File a `spawn_task` flag if you spot something.

### Estimated time

Phase 0–1 (sync + inventory): 30 min. Phase 2 (VERSION): 5 min. Phase 3 (release.ps1 source refactor): 30 min. Phase 4 (`--check-sync`): 45–60 min. Phase 5 (hook): 20 min. Phase 6 (docs): 15 min. Phase 7 (verification): 30 min. **Total wall-clock: ~3 hours.**

### When you're done

Report back with:
- The full `--check-sync` clean-state output (the per-file `OK` table) + `EXIT: 0`.
- The injected-drift output (the `DRIFT` line + `EXIT: 1`), confirming the gate fires.
- The final list of the 13 surface locations and the value each now holds.
- Whether `1.9.0-beta` was ever present in tracked history (`git log --all -S` result) and where.
- Confirmation the pre-commit hook aborts a drifting commit.
- Confirmation MASTER-PLAN.md is updated and the PR notes the M.1 gate is live.
- Anything T1.3 flagged that turned out NOT to be a version-sync issue (so it can be re-routed to the right owner).
