# Session E.5 — rc2 Rebuild + UAT Refresh (mini-integration → the launch gate, again)

> **Model:** Sonnet (5 or 4.6)
> **Effort:** high
> **Switch commands:** `/model sonnet` then `/effort high`
> **Branch:** `audit/E.5-rc2-rebuild` (Development repo, off the merged E-series tip)
> **Parallel-safe with:** nothing — final integration.
> **Depends on:** E.2, E.3, E.4 merged. E.1 findings closed out.
> **Blocks:** M.2-execution (user's UAT run) → M.3 launch.

---

## Prompt to paste

You are consolidating the E-series into a fresh release candidate **v2.0.0-rc2** and refreshing the UAT script so the user can run the (still-unsatisfied) launch gate against the build that will actually ship. This is M.1's playbook re-run smaller, plus an M.2 doc refresh. No production/publish steps — rc2 stays internal like rc1.

### Read first
1. Memory `project_M1_complete.md` + `reference_quicksay_repo_topology.md` — **build-env gotchas: `release.ps1`'s hardcoded `$ahk2base` fails on this machine; use the repo's own `AutoHotkey64.exe` as the Ahk2Exe base. The full release.ps1 pipeline PUBLISHES (R2/website) with no internal-only flag — build rc2 manually like M.1 did.**
2. `docs/audit-campaign/uat-2.0.0-rc1.md` — the doc to refresh.
3. E.2/E.3/E.4 findings — what changed since rc1 (drives which UAT items need updating).

### Steps
1. Merge order sanity: E.2 → E.3 → E.4 onto the integration line; resolve `QuickSay.ahk` seams; `GetDefaultModes()` dual-sync grep-verified identical.
2. Full gate run: `-CheckSync` (all targets @ 2.0.0), every unit suite (history/license/crash/telemetry/update/datadir/multimon/hotkey/rollback/installer-hygiene/**cleanup NEW**/**seams NEW**), T2.6 transcription regression vs baseline, Playwright smokes.
3. Manual rc2 build per M.1's procedure: compile both exes (repo AutoHotkey64.exe base), Azure-sign (pre-check `az account get-access-token --resource "https://codesigning.azure.net"` first), Inno installer, sign+verify, Ed25519-sign a local `version.json`. **No R2 upload, no GitHub release, no website.**
4. Refresh the UAT doc → `docs/audit-campaign/uat-2.0.0-rc2.md`: rc2 artifact name/paths, E-series behavior deltas (cleanup guard, dictionary biasing, flag-affordance, any E.3 behavior decisions like focus-change handling, E.4 visual notes), still STAGING license worker. Add UAT items ONLY if the E-series added user-facing behavior worth gating (candidate: "dictate a question → output is the question, not an answer").
5. Re-verify the two rc1-era UAT blockers' status and surface them to the user again: (a) staging LemonSqueezy test store provisioning (Item 13), (b) mic-capable VM for dictation items.

### Done When
- [ ] rc2 built, signed, verified; all gates green; artifacts in `installer/`.
- [ ] `uat-2.0.0-rc2.md` refreshed and accurate to the build.
- [ ] User notified: run the UAT on a fresh VM; gate semantics unchanged (PASS or written waiver, else no launch).
- [ ] MASTER-PLAN → E.5 ✅; branches committed + PRs.

### What NOT to do
- ❌ No publishing of any artifact anywhere. rc2 is internal.
- ❌ No production cutover (staging worker stays until M.3).
- ❌ Do not run the UAT yourself or mark the gate satisfied.

### Estimated time
~2–3 h.
