# Session T2.3 — Build Trial + Paywall (BUILD)

> **Model:** Opus 4.7
> **Effort:** xhigh
> **Switch commands:** `/model opus` then `/effort xhigh`
> **Branch:** `audit/T2.3-trial-paywall`
> **Parallel-safe with:** T2.2, T2.4, T2.5, T2.6, all of Track 1 (different files)
> **Depends on:** T2.1 (backend design spec — paywall reads JWT issued by the worker built in T2.2)
> **Blocks:** M.1 (integration cannot start without the trial/paywall flow)
>
> Before pasting: confirm `/model opus` (no `[1m]` flag — scope is bounded), `/effort xhigh`.

---

## Prompt to paste

You are implementing QuickSay's 14-day trial + paywall + LemonSqueezy checkout flow. This is **the single most user-experience-critical session** in the campaign — every paying customer flows through this code. Get it right.

### Context

QuickSay is moving from open beta to a paid one-time / lifetime product, sold through **LemonSqueezy**. **Pricing: $39 launch price for the first 500 orders, then $74 with third-party installment financing.** On first install, the user gets a 14-day free trial. When the trial expires, the app shows a paywall modal that links to LemonSqueezy checkout. After purchase, the user's license key activates the app (via the CF Worker built in T2.2, which issues a 14-day Ed25519-signed JWT).

**CRITICAL pricing rule:** Do NOT hardcode the dollar amount in the compiled app — it flips $39→$74 at 500 orders. Either show "Get lifetime access" and let the LemonSqueezy checkout page show the price, or fetch the current price from the Worker's `GET /pricing` endpoint (per the T2.1 spec). The $74 tier must surface the installment-financing option.

**Read these first:**
1. `C:\QuickSay\CLAUDE.md`
2. `docs/audit-campaign/MASTER-PLAN.md`
3. `docs/audit-campaign/specs/T2-production-systems-design.md` — the spec that defines the JWT shape, trial file format, paywall trigger conditions
4. `docs/audit-campaign/research/competitor-backend-research.md` — section on trial flows (SuperWhisper, BetterTouchTool patterns)
5. Memory: [project_payment_lemonsqueezy.md](file:///C:/Users/abeek/.claude/projects/C--QuickSay/memory/project_payment_lemonsqueezy.md)

### Scope — files you may create or touch

| File | Action | Why |
|---|---|---|
| `Development/lib/license.ahk` | **CREATE** | New module: trial expiry check, JWT verification, license state machine |
| `Development/gui/paywall.html` | **CREATE** | Paywall modal UI (loaded in WebView2 — separate window) |
| `Development/gui/paywall.css` | **CREATE** | Styles for paywall (match settings.css design tokens) |
| `Development/QuickSay.ahk` | **MODIFY** | Hook trial check into startup; show paywall on expiry |
| `Development/lib/settings-ui.ahk` | **MODIFY** | Add "License" tab/section showing trial state or licensed status |
| `Development/gui/settings.html` | **MODIFY** | Add "License" section UI |
| `Development/config.example.json` | **MODIFY** | Document new fields: `trialStartedAt`, `trialState`, `licenseJwt` |
| `Development/tests/license/*` | **CREATE** | Unit tests for trial logic + JWT verification |

**Forbidden** (other sessions):
- `Development/setup.iss` — installer-related changes go in M.1 / M.3
- `Backend/license-worker/*` — owned by T2.2
- `Website/*` — owned by M.3
- Anything in `Development/lib/http.ahk` core (you may **import** it but not modify it without explicit reason)

### What you're building (per the T2.1 spec)

**State machine** — track these states in a single file `data/license.dat`, encrypted with DPAPI:

```
INSTALLED (no state yet)
   │
   ▼
TRIAL_ACTIVE (trialStartedAt set, currentDate < trialStartedAt + 14d)
   │
   ├──► TRIAL_EXPIRED (currentDate ≥ trialStartedAt + 14d, no JWT)
   │       │
   │       ▼
   │     PAYWALL_BLOCKING (paywall shown, app refuses to record until purchase)
   │       │
   │       ▼
   ├──► LICENSED (JWT present, signature valid, exp claim still in future)
   │       │
   │       ▼
   │     GRACE_PERIOD (JWT exp claim passed but within 7-day re-validate grace; allow use)
   │       │
   │       ▼
   │     RE-VALIDATION_NEEDED (>7 days past JWT exp; force re-check with CF Worker)
   │
   └──► LICENSE_REVOKED (signature invalid, or worker returns 403; treat as TRIAL_EXPIRED)
```

**File format** (`data/license.dat`, DPAPI-encrypted JSON):
```json
{
  "trialStartedAt": "2026-05-27T14:23:00Z",
  "trialMachineId": "<hash of MAC + Windows product ID>",
  "licenseJwt": null,
  "licenseEmail": null,
  "lastValidation": null,
  "lastValidationResult": null,
  "stateVersion": 1
}
```

**Paywall trigger points** — show the paywall modal when:
1. Trial expires (countdown reaches 0 on startup or while running)
2. User opens settings → license tab and trial is expired
3. JWT exp claim passes the 7-day grace window
4. Worker returns 403 on re-validation

**Paywall modal MUST contain:**
- Clear headline: "Your free trial has ended" (or "Welcome to QuickSay — get a lifetime license")
- Subhead: "One-time payment. No subscription. Lifetime updates." (price itself shown on checkout / fetched from `/pricing` — not hardcoded)
- Primary CTA: "Get my license" → opens LemonSqueezy checkout in default browser
- Secondary CTA: "I already purchased — paste my license key" → opens license-key input
- Footer micro: link to terms, support email, refund policy

**License key entry flow:**
- User pastes license key
- App POSTs `{license_key, machine_id}` to `https://license.quicksay.app/activate` (CF Worker from T2.2)
- Worker returns either `{jwt, email, expires_at}` (success) or `{error}` (fail)
- On success: store JWT in `license.dat`, transition to LICENSED, dismiss paywall, restore recording
- On fail: show the specific error inline ("Already activated on another machine", "License not found", etc.)

### Phase 1 — Read the design spec carefully

Open `docs/audit-campaign/specs/T2-production-systems-design.md`. Read the trial section AND the JWT section AND the LemonSqueezy webhook section. If anything is ambiguous, stop and ask the user before writing code.

Confirm you understand:
- Exact JWT claim names (sub = license key, exp = unix timestamp, machine = machine id hash, etc.)
- Ed25519 public key location (committed to the repo, baked into the AHK source)
- The exact `https://license.quicksay.app/activate` endpoint contract

### Phase 2 — Plan before code

Use `superpowers:brainstorming` skill ONLY if the spec is missing something material. Otherwise jump to `superpowers:test-driven-development` and write the test list first:

Test list (in `Development/tests/license/`):
1. Fresh install → state == INSTALLED; calling `InitTrial()` sets `trialStartedAt` to now and transitions to TRIAL_ACTIVE
2. Trial active, 13 days in → `CheckLicenseState()` returns TRIAL_ACTIVE with `daysRemaining=1`
3. Trial active, 15 days in → returns TRIAL_EXPIRED
4. Trial active but clock rolled back → detect and refuse (use the "trialStartedAt is in the future" check)
5. Valid JWT, exp in future → state == LICENSED
6. Valid JWT, exp 3 days ago → state == GRACE_PERIOD (allow use)
7. Valid JWT, exp 10 days ago → state == RE-VALIDATION_NEEDED (trigger silent re-check)
8. JWT with tampered claim (signature invalid) → state == LICENSE_REVOKED
9. JWT signed by wrong key → state == LICENSE_REVOKED
10. License activation: valid key returns 200 → store JWT
11. License activation: already-activated key returns 403 → show specific error
12. Machine ID stability: same machine returns same ID across reboots (compute from MAC + Windows ProductID hash)
13. DPAPI encryption: `license.dat` cannot be read by another user account on the same machine

Write tests FIRST. Then implementation. Verify tests pass.

### Phase 3 — Implementation order

1. `lib/license.ahk` — pure functions: encrypt/decrypt license.dat, compute machine ID, verify Ed25519 signature on JWT, state-machine evaluation
2. Unit tests for above. Iterate until green.
3. Paywall UI (`gui/paywall.html` + `paywall.css`) — static HTML first, then wire to WebView2 host
4. Activation flow — POST to `https://license.quicksay.app/activate`, handle responses
5. `QuickSay.ahk` integration — trial init on first run; paywall trigger on expiry; recording gate
6. Settings UI — license tab showing current state, trial countdown, or licensed email
7. End-to-end manual smoke (use the test harness from P0.2)

### Phase 4 — UX micro-decisions (you will need to make some)

Pre-decided in the spec (do NOT relitigate):
- 14-day trial length
- Pricing: $39 launch (first 500 orders) → $74 regular + financing. Price NOT hardcoded in-app (fetch from `/pricing` or defer to checkout page).
- LemonSqueezy as processor
- 7-day grace window after JWT exp

Up to you, with rationale (record in `docs/audit-campaign/findings/T2.3-ux-decisions.md`):
- Paywall modal: blocking (cannot dismiss) vs dismissible-but-recording-disabled
- Trial countdown banner: show in app from day 7? Day 10? Day 12? Or never until expiry?
- "Buy now" button placement in settings during trial — visible from day 1 or only after countdown banner starts?
- Failed activation: how many retries before suggesting support?

Default recommendation (use unless you have a better idea, justified): blocking modal after expiry; subtle countdown banner from day 11; "Buy now" link always visible in settings; 3 retries with exponential backoff before showing support link.

### Phase 5 — Live verification

Use `superpowers:verification-before-completion` before declaring done. Specifically verify:

- [ ] Fresh install (delete `%APPDATA%\QuickSay\license.dat`) → trial starts, countdown banner visible after day 11
- [ ] Set system clock forward 15 days (or shim `trialStartedAt` to 15 days ago in license.dat) → paywall appears, recording disabled
- [ ] Click "Get my license" → LemonSqueezy URL opens in default browser
- [ ] Paste a known-good test license key (T2.2 should have set up a test license you can use) → activation succeeds, paywall dismisses, settings shows licensed state
- [ ] Tamper with `license.dat` after activation (modify a JWT character) → app detects, returns to TRIAL_EXPIRED state on next startup
- [ ] Clock rollback attack (set system clock back 30 days after trial expired) → state remains TRIAL_EXPIRED (the "trialStartedAt is in the future" guard)

### Phase 6 — Document the UX in `findings/T2.3-ux-decisions.md`

Brief writeup. What you decided, why, what alternatives you considered. This becomes the source of truth if anyone questions a paywall behavior later.

### Done When

- [ ] `lib/license.ahk` exists, ~300–600 LOC, all functions documented
- [ ] `gui/paywall.html` + `gui/paywall.css` exist, render correctly in WebView2, match settings design tokens
- [ ] `QuickSay.ahk` hooks trial check into startup AND has a recording gate that refuses to record in PAYWALL_BLOCKING state
- [ ] Settings UI has a License tab/section
- [ ] All 13 unit tests pass (run via `tests/license/run-tests.ps1`)
- [ ] All 6 live verification steps pass
- [ ] `docs/audit-campaign/findings/T2.3-ux-decisions.md` written
- [ ] `config.example.json` documents the new fields with comments
- [ ] No regressions: dictation still works (run a quick "hold hotkey, speak, release" smoke). The audio path is unchanged.
- [ ] MASTER-PLAN.md status updated: T2.3 → ✅
- [ ] Branch `audit/T2.3-trial-paywall` committed. PR opened.

### What NOT to do

- ❌ Do not hardcode the LemonSqueezy product ID (it goes in M.3). Use a placeholder constant `LEMONSQUEEZY_PRODUCT_URL` defined at top of `license.ahk` with TODO comment.
- ❌ Do not store the license JWT in plaintext anywhere. DPAPI-encrypted only.
- ❌ Do not allow the trial to be reset by uninstalling + reinstalling — `trialMachineId` should detect that the same machine already used its trial. (This is a soft check, will be reinforced by the CF Worker in T2.2 keeping a hash of trial-machine-ids. For now, just check it locally.)
- ❌ Do not let recording succeed in PAYWALL_BLOCKING state — but DO let the app open (settings, help, paywall) so users can purchase.
- ❌ Do not change the existing audio recording flow. The license check is a startup gate + a per-recording gate, not a code rewrite.
- ❌ Do not write a license-key generator in the app. The CF Worker (T2.2) issues JWTs; the app only validates.

### Estimated time

Phase 1 (read spec): 15 min. Phase 2 (test list): 30 min. Phase 3 (implementation): 2–3 hours. Phase 4 (UX decisions doc): 20 min. Phase 5 (verification): 45 min. Total wall-clock: ~4–5 hours.

### When you're done

Report back with:
- Path to the unit test runner and how to invoke it
- A 60-second video script (text, not actual video) describing what a fresh-install user sees through day 1, day 11, day 14, day 15, and purchase
- Anything in T2.1's spec that turned out to be ambiguous or wrong, with how you handled it
