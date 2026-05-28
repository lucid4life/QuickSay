# Session M.2 — UAT Script for v2.0.0-rc1 (WRITE THE SCRIPT)

> **Model:** Sonnet 4.6
> **Effort:** medium
> **Switch commands:** `/model sonnet` then `/effort medium`
> **Branch:** `audit/M.2-uat`
> **Parallel-safe with:** nothing — runs after M.1 produces rc1.
> **Depends on:** M.1 (the signed v2.0.0-rc1 installer exists). You need to know what shipped to write accurate steps.
> **Blocks:** M.3 (launch is gated on the UAT checklist being ✓ or explicitly waived in writing — MASTER-PLAN §7).
>
> Before pasting this prompt: confirm `/model sonnet` and `/effort medium`. **You WRITE the test script; the USER executes it later on a fresh VM.** Do not try to run the 14 items yourself — most require a clean Windows VM you don't have.

---

## Prompt to paste

You are writing the manual User Acceptance Test (UAT) script that the user will run against the **v2.0.0-rc1** build on a **fresh Windows VM** (Windows Sandbox or a clean Hyper-V VM) before launch. Your deliverable is a single, self-contained checklist document the user can follow item by item with zero ambiguity. **You write it; you do not execute it** — the whole point is a clean-room test on a machine with no QuickSay residue, which only the user has.

### Context

QuickSay is going from open beta to a paid v2.0.0 (LemonSqueezy, $39 launch → $74 regular one-time, 14-day trial → paywall). M.1 just produced a signed, installable `v2.0.0-rc1`. Before M.3 flips the website CTAs and ships, a human must verify the whole product works on a machine that has never seen QuickSay — because the dev box has years of state, registry keys, config, and license files that mask "fresh install" bugs.

This UAT is a **gate** (MASTER-PLAN §7, risk "Manual UAT skipped to move faster" — impact Critical): nothing ships until every item is ✓ or explicitly waived in writing.

Working directory: `C:\QuickSay\Development\`. Deliverable: `docs/audit-campaign/uat-2.0.0-rc1.md` (path resolves from the Development dir via the parent `C:\QuickSay\docs\`).

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — install locations (`%LOCALAPPDATA%\Programs\QuickSay Beta\`, `%APPDATA%\QuickSay\data\`), the recording flow, config fields, the onboarding wizard, IPC model, sound themes, accessibility mode.
2. `C:\QuickSay\docs\audit-campaign\MASTER-PLAN.md` — to confirm what M.1 shipped (Status Tracker) and the UAT gate semantics (§7), and the rc1 caveat that it points at the LICENSE **staging** worker.
3. `C:\QuickSay\docs\audit-campaign\specs\T2-production-systems-design.md` — the trial state machine + paywall trigger conditions + activation flow, so the trial-countdown / paywall / activation steps are accurate.
4. T2.3's `findings/T2.3-ux-decisions.md` — exact paywall behavior (blocking vs dismissible, countdown banner start day) so the "expected result" for those items is correct.
5. The M.1 session report / its commit — for the rc1 version string, the staging test-license key (from T2.2's README), and any residual risk M.1 flagged for UAT to probe.
6. The `quicksay-go-to-paid` skill — invoke it (installer audit checklist: silent install, upgrade path, uninstall cleanup; trial anti-cheat behaviors).

Invoke the `verify` skill for the structure/discipline of a good manual verification script (clear action → expected → pass/fail).

### The deliverable: a 14-item UAT script

Write `docs/audit-campaign/uat-2.0.0-rc1.md`. Structure:

```
# QuickSay v2.0.0-rc1 — Manual UAT Checklist
> Build: v2.0.0-rc1 (signed) | License endpoint: STAGING | Date prepared: <date>
> Run on a FRESH Windows VM (Windows Sandbox or clean Hyper-V). Estimated total: ~45–60 min.
> GATE: launch (M.3) does not proceed until every item is PASS or explicitly WAIVED (with a written reason).

## Pre-flight (VM setup)
  - VM requirements, where to put the rc1 installer + the staging test license key, how to confirm no prior QuickSay residue.

## Items 1–14   (each in the standard block below)

## Result summary
  - Pass/fail tally, blocker list, sign-off line.
```

**Every item uses this exact block format:**

```
### Item N — <short title>
- **Why it matters:** one line.
- **Setup:** precise precondition (what state the machine/app must be in first).
- **Action:** the exact clicks/keys/commands the tester performs.
- **Expected:** the precise, observable pass condition (what they should SEE).
- **Pass / Fail:** ☐ Pass  ☐ Fail
- **Notes:** _____________________ (free space for the tester)
```

Each item must take **under 5 minutes** to execute. Order them so state builds naturally (clean install first, uninstall last) to minimize VM resets.

**The 14 items must cover exactly these (one item each):**

1. **Clean install — no prior residue.** Installer runs, lands files at the expected paths, registers the uninstall entry, no SmartScreen hard-block (note: rep is earned by volume — a warning is acceptable to note, a block is a fail), signed-publisher shown.
2. **Onboarding wizard end-to-end.** First-run wizard launches, walks through API-key entry (plain-English, "free AI account" framing per the Dad Test), hotkey practice if present, completes, writes the `onboarding_done` marker.
3. **Trial countdown shows the expected days.** Fresh install → License tab / countdown reflects ~14 days remaining (and the countdown banner appears on the day T2.3's UX doc specifies, not before).
4. **Paywall on expiry.** Shim `trialStartedAt` to 15 days ago (give the exact edit / clock method) → relaunch → paywall blocks recording, but settings/help/paywall still open.
5. **License activation with the staging test key.** Paste the T2.2 staging test license key in the paywall's "I already purchased" flow → activates → LICENSED → paywall dismisses → recording restored. (Note clearly this uses the STAGING worker.)
6. **Dictation in Notepad.** Hold hotkey, speak a known sentence, release → correct transcript pastes in Notepad.
7. **Dictation in Chrome** (an address bar or a textarea) → transcript pastes correctly.
8. **Dictation in a terminal** (PowerShell/Windows Terminal) → transcript pastes correctly (the terminal paste path uses Shift+Insert per CLAUDE.md — verify it lands).
9. **Audio device switch.** Change the input device in settings to a non-default mic (FFmpeg path) → record → transcript still works with the new device.
10. **Settings persistence across restart.** Change a few settings (sound theme, hotkey mode, a toggle), close the app fully, relaunch → settings persisted.
11. **History retention enforcement.** Set `historyRetention` low (e.g. 3), dictate 5 times → only the 3 most recent remain (proves the T1.5 fix in the shipped build). Also: clear history, dictate once → the cleared entries do NOT come back (the race fix).
12. **Hotkey collision warning.** Set the hotkey to something likely to collide (or trigger the T1.7 conflict detection) → the app warns clearly rather than silently failing.
13. **Accessibility tab-navigation.** In settings, navigate the whole UI with Tab/Shift+Tab/Enter/Space only (no mouse) → every control is reachable and operable; focus is visible (proves the T1.7 a11y work).
14. **Clean uninstall — no residue.** Uninstall via the standard uninstaller → program files removed from `%LOCALAPPDATA%\Programs\QuickSay Beta\`, uninstall registry entry gone, startup `Run` key gone; user data in `%APPDATA%\QuickSay\` handled per the documented policy (left unless the user opted to remove). State explicitly what SHOULD remain vs be gone.

For any item whose exact expected behavior depends on a T2.3 UX decision or an M.1 detail you can't confirm from the docs, write the expected result as precisely as the docs allow and add a bracketed `[CONFIRM: …]` note rather than guessing.

### Phase 1 — Gather the specifics

Read the sources. Pin down: the rc1 version string, the staging test-license key + the exact activation steps, the trial-countdown-banner start day, the paywall blocking behavior, the terminal-paste mechanism, the a11y expectations, and the uninstall data policy. Where a fact isn't in the docs, mark `[CONFIRM]` rather than invent.

### Phase 2 — Write the script

Write all 14 items in the standard block format. Make the Setup/Action steps copy-pasteable where they involve commands (e.g. the `license.dat` shim, the registry check, the file-existence check). The expected results must be observable by a non-engineer following along.

### Phase 3 — Self-review for executability

Re-read as if you were the tester on a fresh VM with only this doc. For each item ask: "Could I do this with no other knowledge?" Fix anything that assumes context the tester won't have. Confirm the pre-flight section gets a blank VM to the starting line (where to get the installer, where to get the staging key, how to confirm no residue).

### Done When

- [ ] `docs/audit-campaign/uat-2.0.0-rc1.md` exists with the header, pre-flight, all 14 items in the exact block format, and a result-summary/sign-off section.
- [ ] All 14 required topics are covered, one item each, each executable in <5 min.
- [ ] Items are ordered so machine state builds naturally (install → use → uninstall).
- [ ] Every item has a precise, observable Expected result; uncertain ones carry a `[CONFIRM]` note rather than a guess.
- [ ] The doc states clearly that rc1 uses the STAGING license worker and includes the staging test key + activation steps.
- [ ] The gate semantics are stated (PASS or written WAIVER, else launch is blocked).
- [ ] You notify the user the script is ready to run, with the one-line "run this on a fresh VM" instruction.
- [ ] `docs/audit-campaign/MASTER-PLAN.md` Status Tracker updated: M.2 → ✅ (script written; execution by user is the separate gate).
- [ ] Branch `audit/M.2-uat` committed (use `commit-commands:commit`). PR opened against `main`.

### What NOT to do

- ❌ Do not execute the UAT yourself or claim items pass — you don't have a fresh VM, and a dev-box "pass" defeats the purpose. You WRITE the script.
- ❌ Do not exceed 14 items or merge topics — each of the 14 listed gets its own item.
- ❌ Do not guess an expected result you can't source. Use `[CONFIRM]`.
- ❌ Do not write items that need an engineer — a careful non-engineer must be able to follow each.
- ❌ Do not point any step at the PRODUCTION license worker — rc1 is staging.
- ❌ Do not modify app code, the installer, or the website. This session only writes a doc.
- ❌ Do not mark the launch gate as satisfied — only the user's execution can do that.

### Estimated time

Phase 1 (gather specifics): 30 min. Phase 2 (write 14 items): 60 min. Phase 3 (self-review): 20 min. **Total wall-clock: ~2 hours.** (User's execution on the VM is a separate ~45–60 min, later.)

### When you're done

Report back with:
- The path to the UAT doc and the item count (14).
- Any `[CONFIRM]` items where you couldn't source the exact expected result — the user resolves these before running.
- The one-line instruction the user needs to start (where the installer + staging key are, what VM to use).
- Confirmation the gate semantics are documented and M.2 is marked ✅ (script-written).
