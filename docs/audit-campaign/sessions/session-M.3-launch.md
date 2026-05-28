# Session M.3 — Launch v2.0.0 (THE LAUNCH)

> **Model:** Sonnet 4.6
> **Effort:** medium
> **Switch commands:** `/model sonnet` then `/effort medium`
> **Branch:** `audit/M.3-launch`
> **Parallel-safe with:** nothing — this is the final, irreversible session.
> **Depends on:** M.2 sign-off (the 14-item UAT must be PASS or explicitly waived in writing before you ship). Also M.1 (the release pipeline produced a clean rc).
> **Blocks:** nothing — this is the end of the campaign.
>
> Before pasting this prompt: confirm `/model medium` is set… actually confirm `/model sonnet` and `/effort medium`. **This session ships a paid product to real customers. Stop and ask the user before any irreversible step** (publishing the GitHub release, deploying the website, flipping the price). Get the M.2 UAT sign-off in hand first.

---

## Prompt to paste

You are executing QuickSay's launch: flipping the website from beta-signup to paid checkout, bumping the app to v2.0.0, running the full signed release, publishing it, deploying the website, and verifying a real end-to-end purchase against production LemonSqueezy. This is the moment the product starts taking money. Move deliberately. **Confirm the M.2 UAT is signed off before you begin, and ask the user before each irreversible action.**

### Context

QuickSay is launching as a paid product: **LemonSqueezy, one-time / lifetime, 14-day trial → paywall.** Two repos are involved:
- **App + release pipeline:** `C:\QuickSay\Development\` (runs `release.ps1`).
- **Website:** `C:\QuickSay\Website\` (Astro → Cloudflare Pages, deployed via `wrangler`, NOT git push).

The website currently shows beta CTAs (`BetaCTA` → `/beta#signup`) everywhere; the paid `BuyButton` (→ LemonSqueezy) is dormant with a `PRODUCT_ID` placeholder. A purchase-ready website snapshot exists at commit `58124f9` on branch `main-purchase-ready`.

**✅ Price is RESOLVED (OD-1, 2026-05-27):** **$39 one-time launch price for the first 500 orders, then $74 one-time**, with **third-party installment financing on the $74 tier**. The website's existing `$39 launch / $74 regular` framing (`terms.astro`, `BuyButton.astro` "Get QuickSay — $39") was correct. The earlier "$39.99" in memory/skill/app was a mistake and has been purged. Your job here is consistency, not a decision: make the website, `terms.astro`, `BuyButton.astro`, the app paywall copy, and the LemonSqueezy product all reflect **$39 launch → $74 regular** — and confirm **no `$39.99` survives anywhere** (grep the whole site + app). Just reconfirm with the user on launch day that $39/$74 still holds.

Working directory: start in `C:\QuickSay\Development\` for the release; switch to `C:\QuickSay\Website\` for the CTA flip + deploy.

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — the full release workflow (`release.ps1 -Version 2.0.0 -Changelog "…"`), Azure signing pre-check, R2 upload, `version.json`, and the "website deploy is a SEPARATE manual step" note.
2. `C:\QuickSay\Website\CLAUDE.md` — BetaCTA vs BuyButton (swap all imports back to BuyButton), the `main-purchase-ready` snapshot at `58124f9`, the wrangler deploy command (`--branch=main` for production), the download redirect chain (`/downloads/<filename>` → R2), and the brand voice rules (never start with "In today's world…", "$39 one-time" framing, "zero telemetry").
3. `C:\QuickSay\docs\audit-campaign\MASTER-PLAN.md` — Status Tracker (confirm M.2 ✅), §7 (UAT gate, key-loss / webhook-outage risks).
4. `C:\QuickSay\docs\audit-campaign\specs\T2-production-systems-design.md` — the LemonSqueezy + license-worker contract, so the production cutover (real PRODUCT_ID, prod license worker) is done per spec.
5. The `quicksay-go-to-paid` skill — invoke it (LemonSqueezy checkout URL format, the production-deploy + secret-put steps, the installer/SmartScreen notes, the anti-patterns).
6. The M.2 UAT result + the M.1 report — confirm sign-off and pick up the staging→production cutover notes M.1 flagged.

Invoke `marketing-skills:launch-strategy` to structure the launch sequence and the announcement draft.

### The launch checklist (execute in this order; stop-and-ask before each irreversible step)

#### Step 0 — Gate check + price confirmation
- Confirm M.2 UAT is PASS or has a written waiver. If not, STOP — do not launch.
- **Price is RESOLVED (OD-1):** **$39 one-time launch price for the first 500 orders, then $74 one-time** with **third-party installment financing on the $74 tier**. The $39-launch/$74-regular framing on the website was already correct. Just confirm with the user that this still holds on launch day, then apply it consistently. (The earlier "$39.99" was a scrapped mistake — make sure no `$39.99` survives anywhere; grep for it.)
- Confirm OD-1b (financing provider) is decided: whatever T2.1 selected (LemonSqueezy-native installments if supported, else Affirm/Klarna/Afterpay/PayPal-Pay-in-4, or financing deferred to post-launch). Wire it on the $74 tier or note it as a fast-follow.
- Confirm the production LemonSqueezy product exists and you have its real product ID + store slug, AND that it's configured with the $39 launch price (with a plan to flip to $74 at 500 orders — LemonSqueezy doesn't auto-flip on order count, so this is a manual or scripted switch the user must own; document the cutover procedure). If the product doesn't exist, the user must create it first — ask.

#### Step 1 — Website: flip CTAs to BuyButton + set the real PRODUCT_ID
- In `C:\QuickSay\Website\`: swap every `BetaCTA` import back to `BuyButton` (the `main-purchase-ready` snapshot at `58124f9` is the reference — diff against it to find every site).
- Set the real LemonSqueezy product URL in `BuyButton.astro` (replace `https://quicksay.lemonsqueezy.com/checkout/buy/PRODUCT_ID` with the real product ID/slug). Add the prefill params per the skill's checkout URL format if useful (`checkout[email]`, `checkout[custom][machine_id]`).
- Update the `BuyButton` default text to the agreed price.

#### Step 2 — Website: testimonials, pricing deadline, download page, customer portal
- Update testimonials if M.2 / launch produced new ones (only real ones — match brand voice).
- Set the launch-offer framing on the pricing page: **$39 for the first 500 orders, then $74**. Prefer an order-count framing ("first 500 customers") over a date deadline, since the cutover is volume-based — but if a date is easier to display, set a real one. Show the $74 as the anchored regular price.
- Update the download-page customer-portal URL to the LemonSqueezy customer portal (so buyers can manage their license / re-download).
- Update the download href to the v2.0.0 installer filename (the redirect chain `/downloads/<filename>` → R2; per Website CLAUDE.md the filename is versioned — confirm the new name `release.ps1` produces).
- **Fix the price string everywhere** to the agreed number: `terms.astro` (description + the two body mentions of $39/$74), `BuyButton.astro`, any pricing component, meta descriptions. Grep the whole site for `$39`, `$39.99`, `$74` and reconcile.

#### Step 3 — App: bump to v2.0.0 + run the full signed release
- In `C:\QuickSay\Development\`: **Azure signing pre-check** (`az account get-access-token --resource "https://codesigning.azure.net"`; re-auth per CLAUDE.md if it fails).
- Production cutover: confirm the app points at the PRODUCTION license worker (`license.quicksay.app`, not staging) and the production LemonSqueezy product. (M.1 left rc1 on staging — flip to prod here, and confirm T2.2's worker is deployed `--env production` with prod secrets put. If the prod worker isn't deployed, do it / coordinate per the M.1 cross-session note.)
- Run: `release.ps1 -Version 2.0.0 -Changelog "<real changelog>"` (write a real, brand-voice changelog — what's new in 2.0.0: paid release, license/trial, signed updates, the Track-1 fixes; honest, specific, no hype words).
- Confirm the pipeline: version bump across the sync set, compile, Azure sign, Inno installer, R2 upload, signed `version.json`. The `--check-sync` gate (T1.6) must pass.

#### Step 4 — Verify the full release flow produced correct artifacts
- The signed `QuickSay.exe` + signed installer on R2 at the versioned path.
- `version.json` on R2 is Ed25519-signed (T2.5) and points at the 2.0.0 installer.
- The website download link resolves to the new installer through the redirect chain.

#### Step 5 — GitHub release
- Publish the v2.0.0 GitHub release with the changelog and the signed installer asset, per the existing release convention (check `git log` / prior releases for the format). **Ask the user before publishing** — this is public and irreversible.

#### Step 6 — Deploy the website
- `cd C:\QuickSay\Website && npm run build`
- `npx wrangler pages deploy dist --project-name quicksay-app --branch=main` (the `--branch=main` is required for production per Website CLAUDE.md; without it you only get a preview URL). **Ask the user before deploying** — this flips the public site to paid.

#### Step 7 — Production smoke (user-verified)
This is the proof the launch works. Walk the user through (or do where you safely can):
- Download the installer from `quicksay.app` (real production download path).
- Install on a clean machine/VM.
- Confirm the website CTAs go to the real LemonSqueezy checkout at the agreed price.
- Do a **real (or test-mode-against-prod-product) purchase** → receive a license key → paste it into the app → it activates against the PRODUCTION license worker → LICENSED → recording works.
- Confirm the LemonSqueezy webhook hit the production worker (the KV cache updated). 
- The buyer can reach the customer portal from the download page.

#### Step 8 — Announcement (draft, not necessarily sent)
- Using `marketing-skills:launch-strategy`, draft the launch announcement (e.g. for the website changelog/blog, and short social copy) in QuickSay brand voice — honest, specific, no hype words, no "In today's world…". **Draft only; the user decides when/whether to send.** (Do NOT post to social here — social posting is the Automation workspace's job, not this session.)

### Done When

- [ ] M.2 UAT sign-off confirmed (PASS or written waiver) before any launch step.
- [ ] Pricing ($39 launch → $74 regular + financing) applied CONSISTENTLY across website, `terms.astro`, `BuyButton.astro`, app paywall copy, and the LemonSqueezy product. **No `$39.99` survives anywhere** (grep-verified across both repos + app). The $39/$74 pair is intentional; a stray $39.99 is not.
- [ ] All website `BetaCTA` imports flipped to `BuyButton` with the real production PRODUCT_ID set.
- [ ] Testimonials, launch-offer deadline, download href (v2.0.0 filename), and customer-portal URL updated.
- [ ] App points at the PRODUCTION license worker + production LemonSqueezy product (prod worker deployed `--env production` with secrets put).
- [ ] `release.ps1 -Version 2.0.0 -Changelog "…"` ran clean: version sync passed, compiled, Azure-signed, installer built, R2 upload done, `version.json` Ed25519-signed.
- [ ] v2.0.0 GitHub release published with the signed installer asset (user-approved).
- [ ] Website built and deployed to production (`wrangler pages deploy … --branch=main`, user-approved).
- [ ] Production smoke passes (user-verified): download from quicksay.app → install → checkout at the right price → activate a real/test-mode license against the PROD worker → LICENSED → recording works → webhook updated KV → customer portal reachable.
- [ ] Launch announcement drafted (brand voice, no hype) — not necessarily sent.
- [ ] `docs/audit-campaign/MASTER-PLAN.md` Status Tracker updated: M.3 → ✅. Campaign complete.
- [ ] Branch `audit/M.3-launch` committed (use `commit-commands:commit`). Website commit goes in the ROOT/Website repo; any app/release commit goes in the Development repo (separate histories — CLAUDE.md). PRs opened as appropriate.

### What NOT to do

- ❌ Do not launch before M.2 UAT is signed off. The UAT is a hard gate.
- ❌ Do not ship a price-inconsistent product. The intended pricing is the **$39 launch → $74 regular** pair (with financing on $74) — apply it consistently everywhere, and ensure no stray **$39.99** survives.
- ❌ Do not publish the GitHub release or deploy the website without asking the user — both are public, irreversible.
- ❌ Do not deploy the website via `git push` — it's `wrangler pages deploy … --branch=main` (Website CLAUDE.md).
- ❌ Do not leave the app pointing at the STAGING license worker. Production cutover is required.
- ❌ Do not bypass `release.ps1 --check-sync`. Fix drift, don't skip.
- ❌ Do not skip the Azure signing pre-check (a hang = expired token; re-auth per CLAUDE.md).
- ❌ Do not write hype copy. No "revolutionary", "game-changing", "powered by AI", "In today's world…". Brand voice per Website CLAUDE.md.
- ❌ Do not post to social media from this session (that's the Automation workspace). Draft the announcement; let the user route it.
- ❌ Do not commit the LemonSqueezy API key or any secret to either repo.
- ❌ Do not generate AHK code, N8N workflows, or social posts in the Website repo (Website CLAUDE.md scope rule).

### Estimated time

Step 0 (gate + price): 15 min + user turnaround. Step 1–2 (website CTA flip + copy): 45–60 min. Step 3 (release run): 30–45 min (+ Azure re-auth if needed). Step 4 (verify artifacts): 15 min. Step 5 (GitHub release): 15 min. Step 6 (website deploy): 15 min. Step 7 (prod smoke): 30–45 min (user-driven). Step 8 (announcement draft): 20 min. **Total wall-clock: ~3–4 hours**, gated by user approvals at each irreversible step.

### When you're done

Report back with:
- The final launch price and confirmation it's consistent everywhere (with the grep evidence).
- The live v2.0.0 download URL and the GitHub release URL.
- Confirmation the website is deployed to production and CTAs hit the real LemonSqueezy checkout.
- The production-smoke result (user-verified): purchase → activate → record worked end to end against the PROD worker.
- The announcement draft (or a pointer to where it's saved).
- Confirmation the paywall is enabled and MASTER-PLAN shows the campaign complete.
- Any post-launch follow-ups worth a `spawn_task` (e.g. monitor first webhooks, SmartScreen reputation watch, the "zero telemetry" website-copy update if T2.7 shipped).
