# Session T2.1 — Backend Infrastructure Design (DESIGN GATE)

> **Model:** Opus 4.7 [1m]
> **Effort:** max
> **Switch commands:** `/model opus[1m]` then `/effort max`
> **Branch:** `audit/T2.1-backend-design`
> **Parallel-safe with:** All of Track 1 Wave 1 (T1.1, T1.2, T1.3, T1.4) — but should START only after T1.1 and T1.2 findings land, so the design isn't built on broken assumptions.
> **Depends on:** T1.1 + T1.2 findings (read them), the research corpus, the `quicksay-go-to-paid` skill, memory `project_payment_lemonsqueezy.md`
> **Blocks:** T2.2 (CF Worker), T2.3 (trial/paywall — already written, but its spec references this doc), T2.4 (crash reporting), T2.5 (signed updates)
>
> Before pasting this prompt: confirm `/model opus[1m]` and `/effort max`. This is the ONLY session in the entire campaign that runs at `max` effort — it is the design gate that every Track 2 build inherits. If you run it at a lower effort, every downstream build inherits a weaker contract. Do not economize here.

---

## Prompt to paste

You are the lead backend architect for QuickSay's beta-to-paid transition. Your single deliverable this session is **one authoritative design specification** that every Track 2 build session (T2.2 through T2.5) will implement against. This is the design gate: nothing downstream gets built until this spec is written, security-reviewed, and **approved by the user in this session**.

**You write a spec. You do not write production code, deploy anything, or create the worker directory.** Code-shaped illustrations (interface signatures, JSON shapes, pseudocode) belong in the spec; runnable implementations do not.

### Context

QuickSay is a Windows speech-to-text dictation app (AutoHotkey v2 + WebView2). It is moving from open beta to a paid one-time / lifetime product sold through **LemonSqueezy**. **Pricing: $39 launch (first 500 orders) → $74 regular, with third-party installment financing on the $74 tier.** The app must enforce a **14-day free trial**, then a paywall. Licensed users get an **Ed25519-signed JWT** issued by a **Cloudflare Worker** that wraps the LemonSqueezy License API, so the app can verify licenses **offline** within the token window (no network round-trip on every recording).

These decisions are **locked** (do NOT relitigate them — they are confirmed in memory + the skill):

| Decision | Locked value |
|---|---|
| Payment processor | LemonSqueezy (Merchant-of-Record; handles VAT/tax) |
| Price | $39 launch (first 500 orders) → $74 regular, one-time/lifetime; installment financing on $74 tier. Price NOT hardcoded in-app (Worker `/pricing` or checkout page is source of truth). Provider for financing = OD-1b, verify in this session. |
| Trial | 14-day local trial, DPAPI-encrypted state file |
| License token | Ed25519-signed JWT, 14-day exp, 7-day grace period |
| License storage | DPAPI-encrypted `%APPDATA%\QuickSay\license.dat` (NEVER plaintext) |
| Machine binding | `SHA256(MAC + Windows ProductID)`, truncated 32 hex |
| License server | Cloudflare Worker at `license.quicksay.app` wrapping LS License API |
| Update integrity | `version.json` signed with the SAME Ed25519 key |
| Crash reporting | Sentry envelope POST (no SDK), opt-in, throttled 5/hr |
| Accounts / sync | None in v2.x |

Working directory: `C:\QuickSay\Development\`. The spec is written to `docs/audit-campaign/specs/T2-production-systems-design.md` (the campaign docs live under `C:\QuickSay\docs\`, accessible from the Development working dir via the parent path — verify the path resolves before writing).

**Read these first, in this order. Do not skip any.**

1. `C:\QuickSay\CLAUDE.md` — app architecture, DPAPI usage, config mutex, IPC model, `EscapeJson`/`AtomicWriteFile` utilities, FFmpeg gotchas.
2. `docs/audit-campaign/MASTER-PLAN.md` — §6 (cross-cutting infrastructure: starting topology, KV namespaces, secrets) and §7 (risk register: webhook outage, key loss, Sentry rate limit). These are constraints you must honor.
3. `docs/audit-campaign/research/competitor-backend-research.md` — **§4 (Recommended Stack)** is the derivation of everything below; **§3** is the industry baseline; **§6** is the unverified-assumptions list (note what's inferred vs confirmed).
4. `docs/audit-campaign/research/tooling-research.md` — §5 (Sentry envelope vs minidump), §6 (auto-update / Appcast), §7 (license validation patterns, Ed25519 grace).
5. `docs/audit-campaign/research/app-surface-inventory.md` — the existing config/file-I/O surface the new systems must integrate with (esp. Category 6 file I/O, Category 5 API endpoints, Category 10 version strings).
6. `docs/audit-campaign/findings/T1.1-core-engine.md` and `docs/audit-campaign/findings/T1.2-ui-settings-webview2.md` — the audit findings. **Critical:** if either is not yet present (the audits haven't landed), STOP and tell the user this session is premature per the MASTER-PLAN dependency. Do not design on top of un-audited assumptions.
7. The `quicksay-go-to-paid` skill — invoke it now (it holds all the locked decisions, the LemonSqueezy endpoint contracts, the Sentry envelope wire format, and the anti-patterns list). Everything in the skill is authoritative; if your design diverges from it, you must flag that to the user explicitly.
8. Memory: [project_payment_lemonsqueezy.md](file:///C:/Users/abeek/.claude/projects/C--QuickSay/memory/project_payment_lemonsqueezy.md)

### The deliverable

A single markdown spec at `docs/audit-campaign/specs/T2-production-systems-design.md`, **~3000–4000 words**, that fully specifies the interface contracts (not implementations) for all six production subsystems. Each Track 2 session reads this spec and builds its piece against the contracts you define. The spec is the **frozen interface boundary** between sessions — get the contracts exactly right, because changing them later forces a re-build cascade.

The six subsystems the spec MUST cover, each as its own top-level section:

#### (a) Cloudflare Worker license issuer (wraps LemonSqueezy License API)

- Worker topology: routes, KV namespaces (`LICENSE_CACHE`, `TRIAL_BLOCKLIST`), secrets (`ED25519_PRIVATE_KEY`, `LEMONSQUEEZY_API_KEY`, `LEMONSQUEEZY_WEBHOOK_SECRET`), staging vs production env (`license-staging.quicksay.app` → `[env.staging]`, `license.quicksay.app` → `[env.production]`).
- Endpoint contracts — request shape, response shape, status codes, error codes — for: `POST /activate {license_key, machine_id}`, `POST /validate {jwt}`, `POST /refresh` (re-sign with same claims if LS still says active), `POST /deactivate` (PC-transfer flow), `POST /webhook` (LS → us).
- The wrapping behavior: on `/activate`, the Worker calls LS `activate-license-key`, and only on LS success does it mint a JWT. Define exactly when the Worker hits LS live vs serves from KV cache, and the **failure mode + recovery path** for each (e.g. "LS API 500 on /activate → return 503 with Retry-After; the app stays in its current state and retries"). Honor the MASTER-PLAN risk-register requirement: a cached license check must survive a 14-day LS issuer outage.
- Rate limiting: `/activate` capped per machine_id (the skill says 10/hr — confirm or propose); document the 429 + `Retry-After` contract.

#### (b) Ed25519 JWT issuance + verification

- Exact JWT claim shape: claim names, types, and meaning for every claim. The skill proposes `{sub: license_key_hash, machine: machine_id_hash, email, plan, iat, exp, iss: "license.quicksay.app"}`. Lock the final names — these become hardcoded in `lib/license.ahk` (T2.3) and the Worker (T2.2), so they MUST match exactly.
- TTL: 14-day `exp` is locked. Specify whether `iat`/`nbf` are present, and the precise grace semantics (7 days after `exp` the app is in GRACE_PERIOD; specify the day-boundary math — inclusive/exclusive, UTC).
- Signing algorithm string (`EdDSA` with `crv: Ed25519` in JOSE), key encoding (PEM vs raw), where the **public** key lives (committed to the repo + baked into the AHK source as a constant) vs the **private** key (CF secret store + offline backup only, never in git).
- Verification contract for the AHK side: what `lib/license.ahk` must do to verify a JWT offline (parse, check signature with bundled public key, check `exp` + grace, check `iss`, check `machine` claim matches local machine id). Specify the exact failure → state mapping (bad sig → LICENSE_REVOKED, expired-but-in-grace → GRACE_PERIOD, etc.).

#### (c) LemonSqueezy webhook handler

- Events to handle: `license_key_created`, `license_key_updated`, `license_key_deleted` (and optionally `order_created` for support visibility — recommend yes/no). For each event, specify exactly how KV is mutated.
- Signature verification: HMAC-SHA256 over the raw request body using `LEMONSQUEEZY_WEBHOOK_SECRET`, compared against the `X-Signature` header in **constant time**. Specify the exact verification steps and the reject-before-parse ordering (verify signature on the raw bytes BEFORE JSON parsing).
- Idempotency: webhooks can be redelivered. Specify how the handler stays idempotent (e.g. last-write-wins keyed by license id, or an event-id dedup set in KV).
- Failure mode: what the Worker returns on bad signature (401, no body), on unknown event (200 ignore), on KV write failure (500 so LS retries).

#### (d) Trial enforcement

- The DPAPI-encrypted `license.dat` file format (JSON shape: `trialStartedAt`, `trialMachineId`, `licenseJwt`, `licenseEmail`, `lastValidation`, `lastValidationResult`, `stateVersion`). This is the contract T2.3 implements — match it to T2.3's already-written session.
- The full state machine (INSTALLED → TRIAL_ACTIVE → TRIAL_EXPIRED → PAYWALL_BLOCKING → LICENSED ↔ GRACE_PERIOD ↔ RE-VALIDATION_NEEDED → LICENSE_REVOKED), with the precise transition predicate for each edge.
- Anti-cheat contracts (these are locked behaviors, specify them precisely):
  - **Clock-rollback:** if `trialStartedAt` is in the future relative to current time, treat as tampered → force TRIAL_EXPIRED.
  - **Machine-id hash:** `SHA256(MAC + Windows ProductID)` truncated to 32 hex chars. Specify which MAC (first non-loopback? the one used at install?) and how to read Windows ProductID — pick the stablest source and document why.
  - **Reinstall detection:** the local soft check (file present?) AND the server-side hard check (`TRIAL_BLOCKLIST` KV keyed by `trialMachineId`). Specify when the app reports `trialMachineId` to the Worker so the blocklist can be populated, and what the Worker does on a re-activation attempt from a known trial-exhausted machine.
- Explicitly list the anti-cheats deliberately NOT included (VM detection, hardware fingerprinting beyond MAC+ProductID, sub-14-day forced re-validation) and the one-line reason for each — so a future session doesn't "helpfully" add them.

#### (e) Crash reporting endpoint — **recommend Sentry-direct vs self-hosted CF forwarder**

- Present BOTH options the research surfaced: (1) POST Sentry envelope directly from AHK to `https://oXXX.ingest.sentry.io/api/PROJECT/envelope/`, vs (2) a self-hosted CF Worker (`crash.quicksay.app`) that forwards to Sentry / writes to R2 / pings Discord.
- **Make a recommendation** with explicit tradeoffs (the research §5 leans Sentry-direct as the cheapest path; the self-hosted forwarder gives you a redaction chokepoint and avoids exposing the project DSN in the binary). State which you recommend and why, then design the contract for the recommended option (the other becomes a documented fallback).
- Specify the exact envelope wire format (the skill has the minimum viable JSON-only event envelope — reproduce it), the PII scrub list (groqApiKey, licenseJwt, transcript text, audio paths→`data/audio/[FILE]`, username→`[USER]`, machine name→`[MACHINE]`), and the client-side throttle (5 envelopes/hr, drop excess — honor the MASTER-PLAN risk register).
- The opt-in contract: crash reporting is OPT-IN (off by default), specify the config field and the consent UX touchpoint (the actual UI is built in T2.4; you specify the contract).

#### (f) Signed updates

- The `version.json` schema on R2, extended with a signature. Specify: which fields are signed (the whole canonical JSON minus the signature field? a specific subset?), the signature encoding (base64url Ed25519 over the canonical bytes), and the field name.
- How `CheckForUpdates()` (existing in `QuickSay.ahk`) verifies the signature before trusting the version/download URL. Specify the failure mode (bad signature → treat as no-update-available + log, never auto-download an unsigned/invalid manifest).
- Key rotation: the SAME Ed25519 key signs both JWTs and `version.json`. Specify a rotation procedure (how do you roll the key without bricking installed apps that have the old public key baked in?). This is genuinely hard — **if you cannot resolve it without an assumption (e.g. ship two public keys, accept either signature for a transition window), STOP and ask the user about rotation cadence and the transition-window length before locking it.**

### Phase 1 — Read everything, build the constraint map

Read all 8 sources above. Then write (in your working notes, not the spec yet) a **constraint map**: every hard constraint the design must satisfy, tagged by source. Examples: "JWT exp = 14d [locked: memory/skill]", "cached check survives 14d LS outage [MASTER-PLAN §7]", "`license.dat` format must match T2.3's already-written file shape [T2.3 session]", "machine id = SHA256(MAC+ProductID) [skill]". Anything you find in the T1.1/T1.2 findings that affects the design (e.g. config mutex coverage gaps, IPC target window name, AtomicWriteFile usage) goes here too.

Present the constraint map to the user before proceeding.

### Phase 2 — Brainstorm the open questions

Invoke `superpowers:brainstorming`. The goal is to surface every parameter that is NOT already locked, and decide whether you can choose it yourself (with rationale) or must ask the user.

**Decision rule (follow this exactly):** For any parameter not pinned by memory, research, or the skill, you have two choices:
- If it's a low-stakes engineering default with an obvious best answer and reversing it later is cheap → choose it, and record the choice + rationale in the spec's "Decisions made by the architect" appendix.
- If it materially changes user-visible behavior, security posture, cost, or is expensive to reverse → **STOP and ask the user before assuming it.**

Parameters the prompt-author already knows are NOT fully locked and likely need a user decision (ask about these explicitly unless the answer is unambiguously implied by a source you cite):
- **Exact JWT TTL beyond the 14-day exp** — the 14d is locked, but: does `/refresh` extend by another 14d each time it succeeds? Is there a hard outer cap (e.g. re-validate against LS at least every N days regardless)? Ask.
- **Exact paywall blocking behavior** — modal blocking (cannot dismiss) vs dismissible-but-recording-disabled. T2.3 has a default recommendation (blocking after expiry) but flags it as the architect's call. Confirm with the user which one the SPEC mandates, since T2.3 builds to the spec.
- **Key rotation cadence** — how often (if ever) the Ed25519 key rotates, and the transition-window length for accepting old+new signatures. Ask (subsystem f).
- **Crash reporting recommendation acceptance** — present your Sentry-direct vs self-hosted-forwarder recommendation and get the user to confirm before locking the contract, since it determines whether T2.4 builds a Worker.
- **Rate-limit thresholds** — `/activate` 10/hr per machine: confirm or adjust.
- **Whether `order_created` webhook is handled** — recommend, then confirm.

Write the list of questions, ask them, and wait for answers before writing the spec. Do not guess on any of these six.

### Phase 3 — Ultrathink each subsystem contract

For each of the six subsystems, **type `ultrathink` into your reasoning** and work the contract end to end. The failure modes are where the value is — a JWT spec that doesn't say what happens on a clock skew between the Worker and the app, or a webhook handler that parses before verifying the signature, is a spec that ships a bug into three downstream sessions.

For every subsystem, your reasoning must explicitly cover:
- The happy path (request → response, or event → state change).
- Every failure mode (network, malformed input, signature mismatch, KV stale, clock skew, redelivery) and its recovery path.
- The security boundary: what is trusted, what is attacker-controlled, where verification happens, what is never logged.
- The integration seam with the existing app (which existing function it hooks, which config field it reads/writes, whether it needs the config mutex).

This is the `max`-effort heart of the session. Do not rush it.

### Phase 4 — Write the spec

Write `docs/audit-campaign/specs/T2-production-systems-design.md`. Structure:

```
# T2 — Production Systems Design Specification
> Status: DRAFT pending user approval | Author: T2.1 session | Date: <date>
> This spec is the frozen interface boundary for T2.2–T2.5. Changing a contract here
> forces a re-build of the dependent session.

## 0. Scope, locked decisions, and how to read this spec
## 1. System topology (the one-diagram overview: CF account, Workers, KV, secrets, app side)
## 2. Subsystem A — CF Worker license issuer
## 3. Subsystem B — Ed25519 JWT issuance + verification
## 4. Subsystem C — LemonSqueezy webhook handler
## 5. Subsystem D — Trial enforcement (state machine + anti-cheat)
## 6. Subsystem E — Crash reporting (recommendation + chosen contract)
## 7. Subsystem F — Signed updates + key rotation
## 8. Cross-subsystem concerns (key management, secret inventory, staging→prod promotion)
## 9. Per-session build handoff (which session implements which section, in what order)
## 10. Appendix: Decisions made by the architect (with rationale)
## 11. Appendix: Open questions resolved with the user this session (Q → A)
```

Requirements for the spec body:
- Every contract is **concrete and testable**: exact field names, exact status codes, exact error strings, exact JSON shapes. No "the worker validates the license" hand-waving — say HOW.
- Code-shaped illustrations are allowed (TypeScript interface declarations, JSON examples, AHK function signatures, pseudocode) but NOT runnable implementations. The point is the contract, not the code.
- Every subsystem section ends with a **"Failure modes & recovery"** subsection and an **"Integration seam"** subsection (what existing app code it touches).
- §9 must give each downstream session (T2.2, T2.3, T2.4, T2.5) an explicit "you implement section X; here are your inputs and your acceptance criteria" handoff. T2.3 is already written against this spec — confirm your §5 (trial) matches the `license.dat` format and state machine T2.3 expects, and note any place they diverge.
- Word count target ~3000–4000. If you blow past 4000 because a subsystem genuinely needs it, that's fine — completeness beats brevity here. But cut filler.

### Phase 5 — Security review the draft

Invoke `security-auditor` (and the `security-scanning` plugin's `threat-modeling-expert` / `stride-analysis-patterns` if available from P0.1) over the spec draft. Run the threat model against, at minimum:
- **Spoofing:** can an attacker forge a JWT? (Ed25519 — verify the public/private split is airtight and the verification contract checks signature before trusting any claim.)
- **Tampering:** can `license.dat` or `version.json` be tampered to extend trial / install a malicious update? (Clock-rollback guard, signed manifest.)
- **Repudiation / Replay:** can a webhook be replayed to re-grant a revoked license? (Idempotency + dedup.)
- **Information disclosure:** does any path log or transmit the JWT, license key, Groq API key, transcript, or DSN-with-auth? (Trace the crash-reporting scrub list and the Worker secrets.)
- **DoS:** `/activate` rate limit; Sentry envelope throttle; KV read amplification.
- **Elevation:** is the LemonSqueezy API key ever exposed to the client? (It must live only in the Worker secret store.)

For every finding, either fix it in the spec or document why it's an accepted risk (cite the MASTER-PLAN risk register where relevant). Record the security review outcome in an appendix or a sibling `findings/T2.1-security-review.md`.

### Phase 6 — Revise, then PRESENT TO USER FOR APPROVAL

Revise the spec per the security review. Then **stop and present the spec to the user for explicit approval.** Do NOT mark the session done, do NOT update the Status Tracker, and do NOT merge until the user says "approved" (or equivalent). Summarize for them:
- The six subsystem contracts in one paragraph each.
- Every decision you made as architect (the §10 appendix) so they can veto any of them.
- Every open question you asked and the answer you got (§11).
- The security review outcome and any accepted risks.

If the user requests changes, revise and re-present. The session is not complete until the user approves.

### Done When

The following are ALL true. Do not declare complete without verifying each:

- [ ] `docs/audit-campaign/specs/T2-production-systems-design.md` exists, ~3000–4000 words, with all 11 sections.
- [ ] All six subsystems (a–f) are fully specified with concrete, testable contracts — exact claim names, status codes, JSON shapes, error strings.
- [ ] Every subsystem has a "Failure modes & recovery" and an "Integration seam" subsection.
- [ ] The crash-reporting recommendation (Sentry-direct vs self-hosted forwarder) is made AND confirmed with the user.
- [ ] §5 (trial) matches T2.3's `license.dat` format and state machine, or divergences are explicitly noted with resolution.
- [ ] §9 hands off an implementable contract + acceptance criteria to each of T2.2, T2.3, T2.4, T2.5.
- [ ] Every parameter that was not locked is either (a) decided by the architect with rationale in §10, or (b) asked of the user and answered in §11. No silent assumptions.
- [ ] Security review run (`security-auditor` + STRIDE); findings fixed in spec or documented as accepted risk; outcome recorded.
- [ ] **USER HAS EXPLICITLY APPROVED THE SPEC.** (This is the gate — the session is not done without it.)
- [ ] `docs/audit-campaign/MASTER-PLAN.md` Status Tracker updated: T2.1 → ✅ done, with a one-line note of the crash-reporting decision and any rotation decision.
- [ ] Branch `audit/T2.1-backend-design` committed (use `commit-commands:commit`). PR opened against `main`. Commit message: `T2.1 — backend production systems design spec (approved)`.

### What NOT to do

- ❌ Do not write any runnable production code. No `src/index.ts`, no `lib/license.ahk`, no `wrangler.toml`. Those are T2.2–T2.5. You write contracts only.
- ❌ Do not create the `Backend/license-worker/` directory. T2.2 creates it.
- ❌ Do not relitigate any locked decision (LemonSqueezy, $39 launch→$74 pricing, 14-day trial, Ed25519, no accounts/sync). If you think one is wrong, flag it to the user as a one-line note — do not silently redesign around it.
- ❌ Do not assume any of the six flagged open parameters (JWT refresh/cap, paywall blocking mode, key rotation cadence, crash backend, rate limits, order_created handling). Ask.
- ❌ Do not mark the session done, update the Status Tracker, or merge before the user approves the spec.
- ❌ Do not design accounts, sync, or on-device Whisper — all explicitly out of scope per MASTER-PLAN §1.
- ❌ Do not let the spec balloon with implementation detail that belongs in a build session (no full TypeScript route handlers, no AHK function bodies). Contracts and shapes, not code.
- ❌ Do not skip the `ultrathink` pass in Phase 3 on any subsystem. The failure-mode reasoning is the deliverable's core value.
- ❌ Do not begin if the T1.1 / T1.2 findings docs are missing — surface that to the user as a dependency violation first.

### Estimated time

Phase 1 (read + constraint map): 45–60 min. Phase 2 (brainstorm + user Q&A): 30–45 min (plus user turnaround). Phase 3 (ultrathink six contracts): 60–90 min — this is the bulk. Phase 4 (write spec): 60–90 min. Phase 5 (security review): 30–45 min. Phase 6 (revise + present + user approval): 30 min + user turnaround. **Total active model time: ~4.5–6 hours**, plus user review/approval cycles. This is the longest single design session in the campaign by design.

### When you're done

Report back with:
- The path to the spec and its final word count.
- The six subsystem contracts in one sentence each.
- Every architect-decided parameter (§10) and every user-answered open question (§11), as a bulleted list.
- The crash-reporting recommendation and the user's decision.
- The security review outcome: number of findings, how many fixed-in-spec vs accepted-risk.
- Explicit confirmation that the user approved.
- Any cross-session dependency you discovered that should be added to MASTER-PLAN (e.g. "T2.5 must coordinate with T2.2 on the key-rotation transition window because they share the Ed25519 key").
