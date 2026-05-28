# Session P0.1 — Skill Activation + Custom `quicksay-go-to-paid` Skill

> **Model:** Sonnet 4.6
> **Effort:** medium
> **Switch commands:** `/model sonnet` then `/effort medium`
> **Branch:** `audit/P0.1-skill-activation`
> **Parallel-safe with:** — (this is the first session)
> **Depends on:** — (campaign kickoff)
> **Blocks:** P0.2 (test harnesses use no plugins, but they share the project memory) and the entire audit campaign (most Track 1/Track 2 sessions reference these skills)
>
> Before pasting this prompt: confirm `/model sonnet` and `/effort medium`. This is mechanical setup work — don't burn Opus.

---

## Prompt to paste

You are bootstrapping the QuickSay audit campaign's tooling layer. The work is in two parts:

1. **Activate 5 cloned-but-inactive Claude Code plugins** so the audit sessions that depend on them can run.
2. **Author a custom skill `quicksay-go-to-paid`** that consolidates the bespoke patterns QuickSay needs (Inno Setup audit + LemonSqueezy integration + license-server design) into a single, deletion-friendly skill.

**Zero application source changes in this session.** Configuration only.

### Context

QuickSay is moving from open beta to a paid one-time/lifetime product ($39 launch → $74 regular). The campaign MASTER-PLAN.md depends on tooling that is *cloned* in the marketplaces but not *activated* as plugins. The research in `docs/audit-campaign/research/skills-inventory.md` identified 5 plugins to activate and 1 custom skill to write.

Working directory: `C:\QuickSay\` (repo root — the campaign docs live here; the skill goes to the user's global `~/.claude/skills/`).

**Read these first, in order:**
1. `C:\QuickSay\CLAUDE.md` — project conventions and file map
2. `docs/audit-campaign/MASTER-PLAN.md` — campaign context (you will update the Status Tracker at the end)
3. `docs/audit-campaign/research/skills-inventory.md` — section "Skills to Install Before Campaign Starts (shortlist — 6 items)" is your install list and skill spec
4. `docs/audit-campaign/research/competitor-backend-research.md` — section 4 "Recommended Stack" informs the LemonSqueezy + license-worker patterns the new skill will encode

### Phase 1 — Activate the 5 plugins

The 5 plugins below are **already cloned** in installed marketplaces (`claude-code-workflows` and `awesome-claude-plugins`) but are not active. Run each `claude plugin install` and verify each lands.

| # | Plugin | Marketplace | What it gives us | Used by sessions |
|---|---|---|---|---|
| 1 | `payment-processing` | `claude-code-workflows` | `stripe-integration`, `paypal-integration`, `billing-automation`, `pci-compliance` skills | T2.3 (paywall) |
| 2 | `security-scanning` | `claude-code-workflows` | `threat-modeling-expert` agent + `attack-tree-construction`, `sast-configuration`, `stride-analysis-patterns`, `threat-mitigation-mapping` skills | T2.1, T2.2, T2.3, T2.4, T2.5 |
| 3 | `accessibility-compliance` | `claude-code-workflows` | `wcag-audit-patterns`, `screen-reader-testing` skills | T1.7, T1.2 |
| 4 | `observability-monitoring` | `claude-code-workflows` | `distributed-tracing`, `prometheus-configuration`, `slo-implementation` skills | T2.4 (crash reporting design) |
| 5 | `audit-project` | `awesome-claude-plugins` | `/audit-project`, `/audit-project-agents`, `/audit-project-github` slash commands | M.1 integration session |

#### Install steps (run in order)

```bash
claude plugin install payment-processing@claude-code-workflows
claude plugin install security-scanning@claude-code-workflows
claude plugin install accessibility-compliance@claude-code-workflows
claude plugin install observability-monitoring@claude-code-workflows
claude plugin install audit-project@awesome-claude-plugins
```

If any `install` fails because the marketplace name is slightly different on disk, fall back to:
```bash
claude plugin list --available | findstr <plugin-name>
```
and use the exact marketplace identifier shown there. Do NOT clone from upstream — the repos are already on disk.

#### Verify

After all 5 installs:

```bash
claude plugin list
```

Confirm each of the 5 plugins shows status `active` (or whatever indicator the CLI version uses for "loaded"). If any are missing, stop and report — do not silently skip.

Also verify the skills came along by listing skills:

```bash
claude skills list 2>NUL | findstr /I "wcag stride distributed-tracing stripe-integration audit-project"
```

You should see at least one match per plugin. If the skill names differ slightly (e.g. `wcag-audit-patterns` vs `wcag-audit`), record the actual names in your final report — Track 1/Track 2 prompts may reference them.

### Phase 2 — Author the `quicksay-go-to-paid` custom skill

**Skill path:** `C:\Users\abeek\.claude\skills\quicksay-go-to-paid\SKILL.md`

This skill consolidates 3 bespoke patterns that no marketplace skill covers cleanly:

1. **Inno Setup installer audit checklist** — silent install, upgrade path, uninstall cleanup, Defender SmartScreen reputation, version sync.
2. **LemonSqueezy integration** — checkout URL construction, license-key activation contract, webhook signature verification, refund/cancel flow.
3. **License-server design** — Cloudflare Worker + KV + Ed25519-signed JWTs + 14-day trial enforcement + 7-day grace period.

Why one skill, not three: per the research (`skills-inventory.md` §5), all three are "one workstream" — the Go To Paid workstream. Keep them in one file so they're easy to delete after launch if the maintenance burden isn't worth it.

#### Required frontmatter (YAML)

```yaml
---
name: quicksay-go-to-paid
description: |
  Guidance for shipping QuickSay's first paid release. Covers Inno Setup
  installer hardening (silent install, upgrade path, uninstall cleanup, SmartScreen
  reputation), LemonSqueezy integration (checkout, activation, webhooks, refunds),
  and license-server design (Cloudflare Worker + KV + Ed25519 JWT + trial + grace).
  Use this skill when working on QuickSay's beta-to-production transition: the
  installer (setup.iss), payment flow (LemonSqueezy), license validation (CF
  Worker + JWT), trial enforcement (DPAPI license.dat), or launch readiness.
  Trigger keywords: "go to paid", "release v2", "LemonSqueezy", "license server",
  "Inno Setup audit", "SmartScreen", "license JWT", "trial expiry", "paywall",
  "checkout URL", "Ed25519", "Cloudflare Worker license", "activation endpoint",
  "license.quicksay.app". Do not use for unrelated AHK refactoring, marketing copy,
  or website work.
---
```

The `description` is what Claude reads when matching skills to user prompts. Make it concrete enough that it triggers reliably on the right prompts and does NOT trigger on unrelated work. The list of trigger keywords above is the matching surface — keep them in the description.

#### Skill body — 3 sections

After the frontmatter, the body should be **roughly 250–500 lines** of markdown organized as:

##### Section 1 — Inno Setup installer audit checklist

Codify these checks (drawn from `tooling-research.md` §3 + Microsoft's desktop cert checklist in §4):

- [ ] Every `Source:` line in `setup.iss` resolves to a real file in `Development/`. Build a preflight that fails fast on missing files.
- [ ] `AppVersion` and `VersionInfoVersion` match `Development/VERSION` (single source of truth, defined in T1.6).
- [ ] Silent install: `installer.exe /VERYSILENT /SUPPRESSMSGBOXES /LOG=install.log` succeeds with exit code 0.
- [ ] Silent install creates expected files at `%LOCALAPPDATA%\Programs\QuickSay Beta\` and `%APPDATA%\QuickSay\data\`.
- [ ] Silent install registers uninstall entry at `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\<AppId>`.
- [ ] Upgrade install (over existing version) preserves `%APPDATA%\QuickSay\data\` (config.json, history.json, license.dat).
- [ ] Uninstall (`unins000.exe /VERYSILENT`) removes program files but leaves user data unless user opted to remove.
- [ ] Code-signing: every `.exe` (main + uninstaller) signed with the same Azure Trusted Signing cert (Microsoft groups by cert hash for SmartScreen).
- [ ] DPI-aware manifest entry present.
- [ ] Manifest declares Windows 10/11 supportedOS GUIDs.
- [ ] SmartScreen reputation: cert + binary hash submitted to Microsoft via Partner Center (or downloads have built up enough volume).
- [ ] WebView2 redistributable bootstrapper (`redist/MicrosoftEdgeWebview2Setup.exe`) is bundled and runs only if WebView2 runtime missing.

Each item should have a one-line "how to verify" command or pointer (PowerShell, registry query, file existence check). Don't write the verification scripts in this skill — point to where they live (e.g. "see `Development/scripts/installer-preflight.ps1`, written in T1.3").

##### Section 2 — LemonSqueezy integration patterns

Codify (drawn from `competitor-backend-research.md` §4 + memory `project_payment_lemonsqueezy.md` if it exists):

- **Checkout URL format:** `https://<store>.lemonsqueezy.com/checkout/buy/<product-id>?checkout[email]=...&checkout[custom][machine_id]=...`. List which fields are useful to prefill.
- **License-key format issued by LS:** alphanumeric, dashed, ~32-40 chars. Validate format client-side before POSTing.
- **Activation endpoint contract:** `POST https://api.lemonsqueezy.com/v1/licenses/activate` with `{license_key, instance_name}`. Returns `{activated: true, license_key: {...}, instance: {id, name}}`. Document the response fields the app should cache.
- **Webhook signature verification:** HMAC-SHA256 with the store webhook secret. Verify before processing. Show the exact `crypto` call.
- **Webhook events to handle:** `order_created`, `order_refunded`, `subscription_created` (for future), `license_key_created`, `license_key_updated`.
- **Refund flow:** when `order_refunded` arrives, deactivate all license-key instances. App detects on next refresh → returns to TRIAL_EXPIRED.
- **Test mode:** LemonSqueezy has separate test/live API keys. Document the gotcha: test license keys don't work against live store URLs and vice versa.
- **MoR tax handling:** LS handles VAT/sales tax — the app doesn't need to. Just display the listed price.

##### Section 3 — License-server design (CF Worker + KV + JWT)

Codify the architecture (drawn from `competitor-backend-research.md` §4 + MASTER-PLAN.md §6):

- **Topology** — one Worker (`license.quicksay.app`), two KV namespaces (`LICENSE_KEYS` cache, `TRIAL_BLOCKLIST` for revoked trials), secrets for Ed25519 private key + LS API key.
- **Endpoints** — `POST /activate` (key→JWT), `POST /refresh` (re-sign with same claims if still valid), `POST /deactivate` (transfer flow), `POST /webhook/lemonsqueezy` (LS calls us, we update KV cache).
- **JWT claim shape** — `{sub: license_key_hash, machine: machine_id_hash, email, plan, iat, exp, iss: "license.quicksay.app"}`. Ed25519 signature. 14-day exp.
- **Machine ID** — `SHA256(MAC + Windows ProductID)` truncated to 32 hex chars. Stable across reboots. Different across reinstalls of Windows (acceptable).
- **Grace periods** — JWT valid until exp claim. 7 days after exp, app keeps working in GRACE_PERIOD state but tries to refresh in background. 7 days after that, RE-VALIDATION_NEEDED (force online check).
- **Offline support** — App verifies JWT signature locally with bundled public key. No network needed within the 14-day window. This is the key reason we wrap LS instead of using it directly.
- **Trial enforcement** — `trialStartedAt` in `license.dat` (DPAPI-encrypted). Server-side: KV `TRIAL_BLOCKLIST` keyed by `trialMachineId` prevents trial reset via reinstall. Soft check locally + reinforced server-side.
- **Clock-rollback defense** — if `trialStartedAt` is in the future relative to `currentDate`, treat as tampered, force TRIAL_EXPIRED.
- **Rate limits** — `/activate` capped at 10 attempts per machine per hour. Documented HTTP 429 with `Retry-After`.

For each architectural element, include the *failure mode* and the *recovery path*. Example: "If LemonSqueezy webhook is delayed by minutes, KV cache is stale — `/activate` falls back to live LS API call, slower but correct."

#### Skill quality bar

- ✅ Skill is **self-contained** — a future Claude session can read just SKILL.md and ship the work.
- ✅ Every section has concrete, testable assertions (not vague "be secure" handwaving).
- ✅ Cross-links to QuickSay repo paths use absolute paths (`C:\QuickSay\Development\setup.iss`, etc.) so the skill keeps working from any working directory.
- ✅ No business logic in the skill — only prompt templates and checklists. (Per `skills-inventory.md` §5, this keeps it deletion-friendly.)
- ✅ Length: aim for 250–500 lines total. Cut anything beyond.

### Phase 3 — Verify the skill triggers

After writing the skill, restart your skill registry (close + reopen the Claude Code session, or run `claude skills reload` if available). Then test triggering:

1. Open a fresh test prompt and type: *"What's the LemonSqueezy webhook event for refunds?"* — the skill should appear in your active-skills list.
2. Try: *"How does QuickSay enforce a 14-day trial?"* — should trigger.
3. Try: *"What font should I use for the website hero?"* — should NOT trigger.

If trigger #1 or #2 fails, edit the `description` to make keywords more prominent and retry. Document the final triggering verbatim in your final report.

### Phase 4 — Commit the `.claude/` changes (if any)

`claude plugin install` typically writes to `~/.claude/plugins.json` (or similar), which is **outside the repo**. The custom skill at `C:\Users\abeek\.claude\skills\quicksay-go-to-paid\SKILL.md` is also outside the repo.

Inside the repo: the only files that may have changed are `docs/audit-campaign/MASTER-PLAN.md` (Status Tracker update) and possibly nothing else.

If `.claude/` exists at the repo root and has tracked files that changed, commit those on this session's branch. If not, the only commit will be the MASTER-PLAN.md tracker update.

Use the `commit-commands:commit` skill to do this cleanly. Commit message format: `P0.1 — activate 5 plugins + write quicksay-go-to-paid skill`.

### Done When

The following items are all true. Do not declare complete without verifying each:

- [ ] `claude plugin list` shows all 5 plugins active: `payment-processing`, `security-scanning`, `accessibility-compliance`, `observability-monitoring`, `audit-project`.
- [ ] At least one skill from each of the 5 plugins is visible in `claude skills list`. Names captured in your final report.
- [ ] `C:\Users\abeek\.claude\skills\quicksay-go-to-paid\SKILL.md` exists, has the YAML frontmatter, and has all 3 body sections.
- [ ] Skill triggers on at least 2 of the 3 test prompts in Phase 3 (and does NOT trigger on the negative test).
- [ ] `docs/audit-campaign/MASTER-PLAN.md` Status Tracker updated: `P0.1 — Skill activation + custom skill creation` → ✅ done.
- [ ] Branch `audit/P0.1-skill-activation` exists with at least the MASTER-PLAN.md commit. PR opened against `main`.

### What NOT to do

- ❌ Do not modify any QuickSay application source files (`QuickSay.ahk`, `lib/*`, `gui/*`, `setup.iss`, etc.). This session is tooling-only.
- ❌ Do not author the skill anywhere except `C:\Users\abeek\.claude\skills\quicksay-go-to-paid\SKILL.md`. Per-project `.claude/skills/` is for project-shared skills — this one is user-global because the patterns apply only to this user's workflow.
- ❌ Do not write actual business logic in the skill (no LemonSqueezy API client code, no Worker source). The skill is checklists + prompts only.
- ❌ Do not install additional plugins beyond the 5 listed. The research already decided what's in scope.
- ❌ Do not clone repositories from GitHub — the marketplaces are already cloned. Use `claude plugin install`.
- ❌ Do not bundle Inno Setup, LemonSqueezy, and license-server into **separate** skills. One consolidated skill per the research recommendation.

### Estimated time

Phase 1 (5 installs + verify): ~15 min. Phase 2 (skill authoring): ~45–60 min. Phase 3 (trigger verification): ~10 min. Phase 4 (commit): ~5 min. **Total wall-clock: ~75–90 min.**

### When you're done

Report back with:
- The exact `claude plugin list` output showing 5 active plugins
- The skill file path + character count (should be 8–20 KB)
- The 3 test prompts and whether each triggered correctly
- Any skill names from the 5 plugins that differ from what `skills-inventory.md` predicted — Track 1/Track 2 prompts reference them by name
- Confirmation that MASTER-PLAN.md Status Tracker is updated and PR opened
