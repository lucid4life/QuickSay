# T2 — Production Systems Design Specification

> **Status:** ✅ APPROVED (user, 2026-05-31) · **Author:** T2.1 session · **Date:** 2026-05-30 (revised 2026-05-31 per independent security review)
> This spec is the **frozen interface boundary** for T2.2–T2.5. Changing a contract here
> forces a re-build of the dependent session. Field names, status codes, JSON shapes, and
> error strings below are normative — implement them byte-for-byte.

---

## 0. Scope, locked decisions, and how to read this spec

This document specifies the **interface contracts** (not implementations) for the six production subsystems that take QuickSay from open beta to a paid one-time/lifetime product. Each Track 2 build session implements its assigned section against these contracts. Code-shaped illustrations (TypeScript interfaces, JSON shapes, AHK signatures, pseudocode) are contracts, **not** runnable code.

**Locked decisions (do not relitigate — confirmed in memory, the `quicksay-go-to-paid` skill, and MASTER-PLAN):**

| Decision | Value |
|---|---|
| Payment processor | LemonSqueezy (Merchant of Record; handles VAT/tax) |
| Price | $39 launch (first 500 orders) → $74 regular, one-time/lifetime; installment financing on the $74 tier. **Never hardcoded in the compiled app.** |
| Trial | 14-day local trial, DPAPI-encrypted state |
| License token | Ed25519-signed JWT, 14-day `exp`, 7-day grace |
| License storage | DPAPI-encrypted `%APPDATA%\QuickSay\license.dat` (never plaintext) |
| Machine binding | `SHA256(MAC + Windows ProductID)`, truncated to 32 hex chars |
| License server | Cloudflare Worker `license.quicksay.app` wrapping the LS License API |
| Update integrity | `version.json` signed with the **same** Ed25519 key |
| Crash reporting | Sentry envelope POST (no SDK), opt-in, throttled 5/hr — **Sentry-direct** (see §6) |
| Accounts / sync | None in v2.x |

**Decisions resolved this session** (full Q→A in §11; rationale in §10): blocking paywall after expiry · rolling-14-day JWT refresh with no extra hard cap · one shared Ed25519 key (rotate only on compromise, 1-release transition) · Sentry-direct crash reporting · `/activate` 10/hr + `/refresh` 5/hr · `order_created` handled log-only.

**Reading guide:** §1 is the one-screen topology. §2–§7 are the six subsystem contracts (A–F), each ending in **Failure modes & recovery** and **Integration seam** subsections. §8 covers key management and the staging→prod promotion. §9 is the per-session build handoff with acceptance criteria. §10/§11 are the decision appendices.

---

## 1. System topology

```
                         ┌─────────────────────────── Cloudflare account ───────────────────────────┐
                         │                                                                            │
  ┌──────────────┐       │   Worker: license.quicksay.app          (prod)                             │
  │ QuickSay.exe │──HTTPS─┼─► license-staging.quicksay.app          (staging, [env.staging])           │
  │  (AHK app)   │       │     routes: /activate /validate /refresh /deactivate                       │
  │              │       │             /webhook/lemonsqueezy /pricing                                  │
  │ lib/license  │       │   KV: LICENSE_CACHE   (sha256(key) → {status,email,plan,instanceId,...})    │
  │ lib/ed25519  │◄─JWT──┼─    KV: TRIAL_BLOCKLIST (trialMachineId → {blockedAt,reason})               │
  │ lib/update-  │       │   KV: RATE_LIMIT      (rl:<ep>:<machineId> → count, TTL 3600s)              │
  │   verify     │       │   Secrets: ED25519_PRIVATE_KEY · LEMONSQUEEZY_API_KEY                       │
  │ lib/crash-   │       │            · LEMONSQUEEZY_WEBHOOK_SECRET                                    │
  │   reporter   │       └────────────────────────────────────────────────────────────────────────────┘
  └──────┬───────┘                 ▲                                  ▲
         │                         │ webhooks (HMAC-SHA256)           │ server-to-server (LS API key)
         │                  ┌──────┴───────┐                  ┌───────┴────────┐
         │ Sentry envelope  │ LemonSqueezy │                  │ LemonSqueezy   │
         └─► o<ORG>.ingest. │  (checkout / │                  │  License API   │
            sentry.io       │   webhooks)  │                  │ (activate/etc) │
                            └──────────────┘                  └────────────────┘
  R2: version.json (Ed25519-signed) ──fetched by──► CheckForUpdates() in QuickSay.ahk
```

- **App side** (`C:\QuickSay\Development\`): new modules `lib/license.ahk` (T2.3), `lib/crash-reporter.ahk` (T2.4), `lib/update-verify.ahk` (T2.5), and a **shared** `lib/ed25519.ahk` verifier used by both T2.3 and T2.5 (see §8).
- **Worker** (`C:\QuickSay\Backend\license-worker\`, created by T2.2): one Worker, two environments (staging + production) sharing one codebase and one keypair.
- The app verifies JWTs and `version.json` **offline** with a public key compiled into the binary. The Worker and Sentry are the only network dependencies, and neither is on the per-recording hot path.

---

## 2. Subsystem A — Cloudflare Worker license issuer

The Worker wraps the LemonSqueezy License API so the app gets an **offline-verifiable Ed25519 JWT** instead of a per-recording live HTTPS call. The **LemonSqueezy API key lives only in the Worker** (`src/lemonsqueezy.ts`); the app never sees it.

### 2.1 Bindings (`wrangler.toml`)

| Binding | Kind | Purpose |
|---|---|---|
| `LICENSE_CACHE` | KV | `sha256(license_key)` (hex) → license status cache (webhook-populated) |
| `TRIAL_BLOCKLIST` | KV | `trialMachineId` (32-hex) → trial-consumed marker |
| `RATE_LIMIT` | KV | `rl:<endpoint>:<machineId>` → counter, 3600 s TTL |
| `ED25519_PRIVATE_KEY` | secret | PKCS#8 PEM; signs JWTs (this Worker) and `version.json` (release.ps1) |
| `LEMONSQUEEZY_API_KEY` | secret | server-to-server; only `src/lemonsqueezy.ts` reads it |
| `LEMONSQUEEZY_WEBHOOK_SECRET` | secret | HMAC-SHA256 webhook verification |

Environments: `[env.staging]` → `license-staging.quicksay.app`; `[env.production]` → `license.quicksay.app`. T2.2 deploys **staging only**; M.1 promotes to production.

> **Naming note:** the KV namespace is `LICENSE_CACHE` (matches the T2.1/T2.2 prompts and the implementer). MASTER-PLAN §6 and the skill say `LICENSE_KEYS` — update those to `LICENSE_CACHE` (see §10-D1).

### 2.2 KV value shapes

```jsonc
// LICENSE_CACHE[ sha256(license_key) ]
{ "status": "active" | "disabled", "email": "buyer@x.com", "plan": "lifetime",
  "orderId": 1001, "instanceId": "<LS instance uuid>" | null,
  "activationLimit": 1, "updatedAt": 1748620800, "disabledAt": null }

// TRIAL_BLOCKLIST[ trialMachineId ]   (TTL ~18 months; gates trial START only via /trial/status — NEVER a paid activation, §5.4)
{ "blockedAt": 1748620800, "reason": "trial_consumed", "count": 1 }
```

### 2.3 Endpoint contracts

All request/response bodies are JSON (`Content-Type: application/json`) unless noted. `machine_id` is the 32-hex string from §5.3.

```
POST /activate            body: { license_key: string, machine_id: string }
  200 { jwt: string, email: string, exp: number }            // LS active → JWT minted
  400 { error: "bad_request", code: "invalid_format" }       // key fails regex / missing field
  403 { error, code: "already_activated" | "invalid" }       // "invalid" = not-found OR disabled (no key-validity oracle)
  429 { error: "rate_limited" }            + Retry-After: 3600
  503 { error: "upstream_unavailable" }    + Retry-After: 30   // LS API down; app keeps state

POST /validate            body: { jwt: string }
  200 { valid: true, exp: number }
  403 { valid: false, code: "revoked" | "expired" | "bad_signature" }

POST /refresh             body: { jwt: string, machine_id: string }
  200 { jwt: string, exp: number }                            // re-signed fresh 14-day exp
  403 { error, code: "revoked" | "bad_signature" | "machine_mismatch" }
  429 { error: "rate_limited" }            + Retry-After: 3600
  503 { error: "upstream_unavailable" }    + Retry-After: 30

POST /deactivate          body: { jwt: string, machine_id: string }   // "transfer to new PC"
  200 { deactivated: true }
  403 { error, code: "bad_signature" | "machine_mismatch" }
  503 { error: "upstream_unavailable" }    + Retry-After: 30

GET  /pricing
  200 { tier: "launch" | "regular", price: 39 | 74, currency: "USD",
        ordersRemaining: number | null, financingAvailable: boolean,
        checkoutUrl: string }

GET  /trial/status?machineId=<32hex>          // client treats any failure as fail-open (§5.4)
  200 { blocked: boolean }
  429 { error: "rate_limited" }            + Retry-After: 3600

POST /trial/report        body: { trialMachineId: string }   // populates TRIAL_BLOCKLIST on trial-expiry (§5.4)
  202 { recorded: true }                                      // fire-and-forget; NEVER affects a paid /activate
  429 { error: "rate_limited" }            + Retry-After: 3600

POST /webhook/lemonsqueezy   → see §4
```

### 2.4 Wrapping behavior (live LS vs KV cache)

- **`/activate`** — call LS `activate-license-key` **live** (authoritative for activation-limit enforcement). On LS 200 → write `LICENSE_CACHE` (status `active`, record `orderId` + `instanceId`), mint and return a JWT (§3). LS "already activated"/limit → 403 `already_activated`; LS key-not-found **or** key-disabled → 403 `invalid` (collapsed — no key-validity oracle to an unauthenticated caller). On LS 5xx/timeout (10 s) → **503 + `Retry-After: 30`**; the app stays in its current state and retries. (`machine_id` is untrusted client input, §2.5; the trial blocklist is **not** consulted here — it gates trial *start* only via `/trial/status`, never a paid activation, §5.4.)
- **`/refresh`** — verify the JWT signature + `machine` claim **locally in the Worker first** (cheap). Then resolve status: read `LICENSE_CACHE` first; if `status:"active"` → re-sign immediately (no LS call). If the cache entry is missing/stale, fall back to a **live LS `validate-license-key`**; on LS down → 503. If status is `disabled`/not-found → 403 `revoked`. This is the path that **survives a 14-day LS outage** (MASTER-PLAN §7): a cached `active` lets refresh succeed without touching LS.
- **`/deactivate`** — verify JWT + `machine`; call LS `deactivate-license-key` for the cached `instanceId`; on success the user may re-activate on a new machine.
- **`/pricing`** — `tier` derived from the LS order count (live, cached ≤60 s in KV); `ordersRemaining = max(0, 500 − orders)` while `launch`, else `null`. **OD-1b (financing) — verified 2026-05 against LS docs:** LemonSqueezy's documented checkout methods are **cards, PayPal, and Apple Pay** (shown by location/device); it has **no documented native installment/BNPL product** (no Klarna/Affirm/Afterpay). So the "$74 financing" cannot rely on an LS-native feature — the realistic path is **PayPal-surfaced "Pay Later / Pay-in-4"** offered to eligible buyers in supported regions. Thus `financingAvailable` = "the LS checkout surfaces a pay-later method in this buyer's context" (PayPal/region-driven), **not** a QuickSay-built installment system. Do **not** build a custom installment flow; **M.3 verifies the then-current LS methods** and the paywall messaging degrades to "lifetime access" (no financing claim) if none is available.

### 2.5 Rate limiting

**`machine_id` is attacker-controlled request input — NOT a security boundary by itself.** Rate limiting therefore uses two layers:
- **Per-`machine_id` KV counters** (`RATE_LIMIT`, 3600 s TTL): **`/activate` 10/hr**, **`/refresh` 5/hr**, **`/trial/status` 5/hr**, **`/trial/report` 2/hr**. Breach → `429 { error: "rate_limited" }` + `Retry-After: 3600`.
- **Per-IP Cloudflare WAF rate rules** on `/activate`, `/refresh`, `/deactivate`, `/trial/status`, `/trial/report` (defeats `machine_id` rotation), **plus a global per-IP `/activate` ceiling sized to the LemonSqueezy API quota** — each `/activate` makes a live, paid LS call, so unbounded rotation would otherwise amplify into LS-API abuse and a key-probing oracle (mitigated further by the collapsed `invalid` code, §2.3). `/deactivate` (which needs a valid JWT + matching machine) is bounded by JWT possession, but the per-IP limit caps grief from a stolen-then-replayed `/deactivate` (I-b). `/validate` and `/pricing` make no secret/LS call but still sit behind CF WAF per-IP limits.

### 2.6 Failure modes & recovery

| Failure | Worker behavior | App recovery |
|---|---|---|
| LS API 5xx / timeout on `/activate` | 503 + `Retry-After: 30` | Stay in current state; "Activation temporarily unavailable — try again shortly." |
| LS API down on `/refresh` | Serve from `LICENSE_CACHE` if `active`; else 503 | Transparent within the 7-day grace; otherwise retry on next launch |
| KV read miss on `/refresh` | Fall back to live LS validate | Slower but correct |
| KV write failure (cache update) | 500 (so the caller/LS retries) | n/a (write retried) |
| Malformed body / missing field | 400 `bad_request` | App fixes request; never crashes |
| Rate-limit breach | 429 + `Retry-After` | App backs off (exponential) and surfaces support after 3 tries |
| Worker unreachable entirely | n/a | JWT valid locally to `exp`; 7-day grace absorbs the outage |

### 2.7 Integration seam

- App calls `/activate`, `/refresh`, `/deactivate` via `HttpPostFile()`/`HttpGet()` in `lib/http.ahk` (reuse, don't modify). Endpoint base URL is a compiled constant `LICENSE_WORKER_URL` (set to staging in M.1, production in M.3).
- The Worker is **server-side only** — no app code lives here. T2.2 owns the entire `Backend/license-worker/` subtree.

---

## 3. Subsystem B — Ed25519 JWT issuance + verification

### 3.1 Token format (compact JWS, EdDSA / Ed25519)

**Protected header:**
```json
{ "alg": "EdDSA", "typ": "JWT", "kid": "qs-2026" }
```

**Payload claims** (every claim is normative — T2.2 mints, T2.3 verifies, byte-for-byte):

| Claim | Type | Meaning |
|---|---|---|
| `iss` | string | Constant `"license.quicksay.app"` |
| `sub` | string | Lowercase hex `SHA-256(license_key)` (64 chars). The raw key is never in the token. |
| `machine` | string | 32-hex machine id (§5.3) |
| `email` | string | Buyer email (display + support). PII — token is DPAPI-encrypted at rest, never logged. |
| `plan` | string | `"lifetime"` (reserved for future tiers) |
| `iat` | number | Issued-at, unix seconds (UTC) |
| `exp` | number | `iat + 1209600` (14 days), unix seconds (UTC) |

`nbf` is **omitted** (no future-dating need; `iat` suffices). Signature = EdDSA over ASCII `base64url(header) + "." + base64url(payload)` (base64url, no padding).

### 3.2 Lifetime, refresh, and grace (UTC integer-seconds math)

`exp` is locked at `iat + 14 days`. `/refresh` re-signs a **fresh** `iat`/`exp` each success (rolling; **no extra hard cap** — §11 Q2). With `now` = local unix seconds and a **60 s `clockLeewaySeconds`** tolerance on the `exp` comparison:

Define `effectiveExp = exp + clockLeewaySeconds` (leeway applied **once**, only at the access cutoff — never at the gating edges). All rows are strict half-open intervals against `effectiveExp`, so they partition cleanly with no overlap:

| Condition (half-open intervals) | State |
|---|---|
| `now < effectiveExp` | **LICENSED** — full access, no network |
| `effectiveExp ≤ now < effectiveExp + 7d` | **GRACE_PERIOD** — full access; attempt silent `/refresh` in background |
| `effectiveExp + 7d ≤ now < effectiveExp + 14d` | **RE_VALIDATION_NEEDED** — app opens; recording requires a successful online `/refresh` first |
| `now ≥ effectiveExp + 14d` | **RE_VALIDATION_NEEDED persists** — recording stays gated on a successful online re-validation |
| bad signature / unknown `kid` / wrong `alg` / `machine` ≠ local / `iss` ≠ constant | **LICENSE_REVOKED** |
| Worker `/refresh` or `/validate` returns 403 | **LICENSE_REVOKED** → `PAYWALL_BLOCKING` |

The 7-day grace plus the `RE_VALIDATION_NEEDED` boundary means an honest user who goes online within any ~21-day window stays seamlessly licensed, while refunds/revocations always catch up by day 21 of being offline — so no separate outer cap is needed.

### 3.3 Key encoding & location

- **Algorithm string:** JOSE `alg: "EdDSA"`, curve Ed25519 (`crv: "Ed25519"` in the JWK form `jose` uses internally).
- **Private key:** PKCS#8 PEM, stored only in the CF secret store (`ED25519_PRIVATE_KEY`) + an offline backup (1Password or equivalent). **Never in git.**
- **Public key:** published two ways — SPKI PEM (human reference, committed) and **raw 32-byte, base64url** (the form baked into the AHK app as a `kid → publicKey` constant map). The raw form is what the AHK verifier consumes.

### 3.4 AHK verification contract (`lib/license.ahk` via shared `lib/ed25519.ahk`)

Offline JWT verification, in order — **fail closed** at every step:
1. Split the compact JWS into `header.payload.signature`; base64url-decode header + payload.
2. **Assert `header.alg == "EdDSA"` and `header.typ == "JWT"`.** Any other `alg` — including `"none"` or any RSA/HMAC value — → **LICENSE_REVOKED**. The verifier **hardcodes Ed25519 and MUST NOT select the algorithm from the token header** (defeats `alg:none` / algorithm-confusion).
3. Read `kid` from the header; look up the raw public key in the compiled `TRUSTED_KEYS[kid]` map. Unknown `kid` → **LICENSE_REVOKED**.
4. Verify the Ed25519 signature over `header.payload` with that public key (the third segment MUST be a present, non-empty, valid 64-byte signature). Bad/empty signature → **LICENSE_REVOKED**.
5. Check `iss == "license.quicksay.app"`. Mismatch → **LICENSE_REVOKED**.
6. Check `machine == ComputeMachineId()` (§5.3). Mismatch → **LICENSE_REVOKED** (token was copied from another machine).
7. Apply the §3.2 `effectiveExp`/grace table to derive LICENSED / GRACE_PERIOD / RE_VALIDATION_NEEDED.

`version.json` (§7) uses no `alg` field — its signature object carries only `keyId`; the verifier likewise hardcodes Ed25519 and never honors an algorithm hint.

### 3.5 Failure modes & recovery

| Failure | Detection | State / recovery |
|---|---|---|
| Forged/altered token | Ed25519 verify fails | LICENSE_REVOKED → paywall |
| Token copied to another PC | `machine` claim ≠ local id | LICENSE_REVOKED |
| Clock skew (small forward) | 60 s leeway on `exp` | No premature expiry |
| Clock skew (large forward) | grace/re-validation boundaries cross early | Worst case: a premature online re-check (safe) |
| Unknown `kid` (old app, new key) | not in `TRUSTED_KEYS` | Fail closed; user updates app or re-activates online |

### 3.6 Integration seam

- T2.2 mints with `jose` v5 (`SignJWT` / `EdDSA`). T2.3 verifies via `lib/ed25519.ahk` (shared with T2.5). The `TRUSTED_KEYS` map and the `iss` constant are compiled into `QuickSay.ahk`/`lib/license.ahk`.
- `machine` derivation (`ComputeMachineId()`) is shared between activation (sent to `/activate`) and verification (compared against the `machine` claim) — defined once in §5.3.

---

## 4. Subsystem C — LemonSqueezy webhook handler

`POST /webhook/lemonsqueezy` keeps `LICENSE_CACHE` current so activations are fast and revocations propagate.

### 4.1 Signature verification (before parse)

1. Read raw request **bytes** (do not parse JSON yet).
2. Read `X-Signature` header.
3. Compute HMAC-SHA256 over the raw bytes with `LEMONSQUEEZY_WEBHOOK_SECRET`.
4. **Constant-time** compare against `X-Signature`. Mismatch or missing → **401, empty body** (reject before parsing).
5. Only on match: parse JSON and dispatch.

### 4.2 Events and KV mutations

| Event | KV mutation |
|---|---|
| `license_key_created` | `LICENSE_CACHE[sha256(key)] = {status:"active", email, plan, orderId, instanceId:null, activationLimit, updatedAt:<event ts>, disabledAt:null}` |
| `license_key_updated` | Merge **non-status fields only** (e.g. raised `activationLimit`, `instanceId`). **`status` is never written by an update** (see §4.3 sticky-disable). |
| `license_key_deleted` | Terminal disable: `status:"disabled"`, `disabledAt:<event ts>` → subsequent `/activate` & `/refresh` return 403 |
| `order_refunded` | Terminal disable (as above); then call LS `deactivate-license-key` for the cached `instanceId`. **If `instanceId` is `null`** (key was never activated) → skip the LS call, still set `disabled`, return 200 (do not 500/retry). App's next `/refresh` → 403 → LICENSE_REVOKED → paywall ("Your refund was processed…") |
| `order_created` | **Log-only** (support visibility); bump the `/pricing` order counter (idempotent, §4.3). No license-state change. |
| `subscription_created` | **No-op** (log + ignore) — reserved for a future subscription tier |
| any other event | 200, ignored |

### 4.3 Idempotency & replay resistance

Webhooks can be redelivered, reordered, or replayed (even with a valid HMAC, e.g. from a captured copy). Processing order per event: **(1) HMAC verify (§4.1) → (2) `evt:<event_id>` dedup → (3) timestamp gate → (4) apply.**

- **Event timestamp is mandatory.** `updatedAt` = the LS event timestamp, read from a fixed payload field (`meta.event_created`, fallback `data.attributes.updated_at`). If that field is **absent or unparseable → reject (400, logged); KV is not mutated.** It is **never** defaulted to wall-clock or `0` — either default would break the monotonic gate (wall-clock makes every replay "newer"; `0` makes every event a no-op).
- **Dedup before gate.** A redelivered `event_id` already in the `evt:<event_id>` set (TTL 24 h) is acked `200` and **skipped entirely**, so a redelivery can't even reach the timestamp gate. The dedup set also guards non-idempotent side effects (the `/pricing` counter bump).
- **Monotonic apply.** Otherwise apply **only if the event timestamp ≥ the stored `updatedAt`**; an older event is a no-op. Defeats replayed *stale* events regardless of dedup-window expiry.
- **Disable is terminal and status-monotone.** `order_refunded` / `license_key_deleted` set `status:"disabled"` + `disabledAt`. Thereafter: `license_key_updated` **MUST NOT touch `status`** (non-status merge only — so a refund's *own* trailing, strictly-newer `updated` event cannot resurrect the license, F4); and `status` returns to `active` **only** via a `license_key_created` carrying a **new `orderId`** (a genuinely new purchase), never via any event for the already-disabled order. This closes both the stale-`created` replay (R1) and the trailing-`updated` resurrection (F4).

(Security review findings R1/F4/F9 — see `findings/T2.1-security-review.md`.)

### 4.4 Failure modes & recovery

| Condition | Response |
|---|---|
| Bad/missing signature | **401, no body** (rejected before parse) |
| Unknown event type | **200** (ignore) — never make LS retry an event we don't handle |
| KV write fails | **500** (so LS retries) |
| Duplicate delivery | 200; idempotent (last-write-wins + event-id dedup) |
| Malformed JSON after valid signature | 400; log; do not mutate KV |

### 4.5 Integration seam

Webhook URL is configured in the LemonSqueezy dashboard at M.3 (`https://license.quicksay.app/webhook/lemonsqueezy`); staging uses the staging host. No app-side code. T2.2 owns it.

---

## 5. Subsystem D — Trial enforcement (state machine + anti-cheat)

### 5.1 `license.dat` format (DPAPI-encrypted JSON at `%APPDATA%\QuickSay\license.dat`)

```json
{
  "trialStartedAt": "2026-05-27T14:23:00Z",
  "trialMachineId": "<32-hex SHA256(MAC + Windows ProductID)>",
  "licenseJwt": null,
  "licenseEmail": null,
  "lastValidation": null,
  "lastValidationResult": null,
  "stateVersion": 1
}
```

This is **the** contract T2.3 implements; the field set matches T2.3's session verbatim. The file is DPAPI-encrypted (CurrentUser scope) — another user on the same machine cannot read it. **Location is `%APPDATA%\QuickSay\license.dat`, not `A_ScriptDir\data\`** — see the integration seam (§5.6) for why this matters.

### 5.2 State machine

```
INSTALLED ──InitTrial()──► TRIAL_ACTIVE ──(now ≥ start+14d)──► TRIAL_EXPIRED ──► PAYWALL_BLOCKING
                                │                                                      │
                                │                                              (activate license)
                                ▼                                                      ▼
                          (activate license) ───────────────────────────────────► LICENSED
                                                                                       │
                                              ┌────────────────────────────────────────┤
                                              ▼                    ▼                    ▼
                                        GRACE_PERIOD ◄──► RE_VALIDATION_NEEDED    LICENSE_REVOKED
                                              │                    │                    │
                                              └──(refresh 403)──────┴────────────────────┴──► PAYWALL_BLOCKING
```

**Transition predicates:**

| Edge | Predicate |
|---|---|
| INSTALLED → TRIAL_ACTIVE | `license.dat` absent → best-effort `GET /trial/status` (§5.4): if online **and** `blocked` → TRIAL_EXPIRED; otherwise `InitTrial()` writes `trialStartedAt = now`, `trialMachineId = ComputeMachineId()` |
| TRIAL_ACTIVE → TRIAL_EXPIRED | `now ≥ trialStartedAt + 14d` and no valid `licenseJwt` |
| TRIAL_ACTIVE → TRIAL_EXPIRED (tamper) | `trialStartedAt > now` (clock rollback) — §5.4 |
| TRIAL_EXPIRED → PAYWALL_BLOCKING | always (paywall shown; recording disabled) |
| any trial state → LICENSED | `/activate` returns a valid JWT, signature + `machine` + `iss` check pass, `now < exp` |
| LICENSED → GRACE_PERIOD → RE_VALIDATION_NEEDED | the §3.2 `exp`/grace boundaries |
| GRACE/RE_VALIDATION → LICENSED | a successful `/refresh` |
| any licensed state → LICENSE_REVOKED | bad signature / `machine` mismatch / Worker 403 |
| LICENSE_REVOKED → PAYWALL_BLOCKING | always |

### 5.3 Machine ID derivation (`ComputeMachineId()`)

`SubStr( Lowercase( Hex( SHA256( macAddress . windowsProductId ) ) ), 1, 32 )`

- **MAC:** the first **non-loopback, physically-connected** adapter enumerated by `GetAdaptersAddresses` (IfType ≠ software loopback/tunnel, `IfOperStatusUp` preferred), captured at trial-start and stored as `trialMachineId`. Rationale: the active physical NIC is the most stable identifier across reboots; capturing once and persisting it avoids drift when adapters toggle (Wi-Fi vs Ethernet).
- **Windows ProductID:** registry `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProductId`. Rationale: stable across reboots, present on all Win10/11, changes on a clean Windows reinstall (acceptable — that path routes through support).
- Truncated to 32 hex chars to keep the JWT compact. This is **not** fingerprint cryptography — it's a stable-enough binding, by design (§5.5).

### 5.4 Anti-cheat contracts (locked behaviors)

- **Clock rollback:** if `trialStartedAt > now` (impossible under honest use), treat as tampered → force **TRIAL_EXPIRED**. Report the anomaly to crash reporting (without the file contents) if opted in.
- **Machine-id binding:** as §5.3. The JWT `machine` claim must equal the local `ComputeMachineId()` or the license is treated as revoked (stops copying an activated `license.dat` to another PC).
- **Reinstall detection (two layers):**
  - *Layer 1 — local soft check (offline, primary):* `license.dat` lives at `%APPDATA%\QuickSay\` and **survives uninstall** (§5.7), so a normal uninstall→reinstall does **not** reset the trial — a present file with a used/expired trial → stay TRIAL_EXPIRED.
  - *Layer 2 — server gate (best-effort, fail-open):* on first launch with **no** `license.dat` (about to start a trial), the app makes a best-effort `GET /trial/status?machineId=<trialMachineId>`. **Online and `blocked:true` → start in TRIAL_EXPIRED** (no fresh trial). **Call fails / times out (offline) → grant the trial (fail-open)** so first-time offline users are never blocked (no hard auth dependency); the app re-checks **once** on the next successful online launch during the initial trial and honors a `blocked:true` then. On entering **TRIAL_EXPIRED** the app fires `POST /trial/report { trialMachineId }` (fire-and-forget, rate-limited §2.5) to populate `TRIAL_BLOCKLIST` (TTL ~18 mo) for *other* installs of that machine.
  - *Invariant:* the blocklist gates **trial start only** — it is **never** consulted for a paid `/activate` (a purchase always activates, §2.4). Even a poisoned entry can at worst deny a *free trial*, never a purchase.
  - *Residuals (accepted):* **(A1)** a determined user who **also** wipes `%APPDATA%\QuickSay\` while offline gets another trial. **(A7)** pre-emptively blocklisting a *specific* victim requires knowing their `SHA256(MAC+ProductID)` (not remotely observable) and is rate-limited; worst case the victim is denied a *free trial* but can still purchase. Both acceptable at this price point.

### 5.5 Anti-cheats deliberately **not** included

| Excluded | One-line reason |
|---|---|
| VM detection | False-positives on legitimate users (devs, Windows-on-Mac, accessibility setups) |
| Hardware fingerprinting beyond MAC+ProductID | Overkill for a sub-$100 product; brittle across hardware swaps |
| Forced re-validation more often than the 14-day exp / 7-day grace | Annoys real users for marginal piracy benefit |
| *Hard* online requirement to start a trial | Replaced by a **best-effort, fail-open** `/trial/status` check (§5.4): offline first-time users still get the trial immediately — the online check only catches *online* reset attempts, so there is no hard auth dependency |

### 5.6 Failure modes & recovery

| Failure | Behavior |
|---|---|
| `license.dat` missing/corrupt | Treat as INSTALLED → start a fresh trial (corrupt file is backed up to `.corrupt`, mirroring history-core hardening) |
| DPAPI decrypt fails (different user/machine) | Treat as INSTALLED; do not crash |
| `%APPDATA%\QuickSay\` dir absent | Create it before writing (AtomicWriteFile does not create parents — T1.1-010) |
| Concurrent read-modify-write (tray + settings) | Hold `AcquireConfigLock()` across the **whole** RMW (T1.2-009 lost-update) |
| `/trial/status` fails / times out (offline) | **Fail-open** — grant the trial; re-check once on the next successful online launch (§5.4) |
| `/trial/report` fails (offline) | Non-fatal; local soft check still applies; report retried on next expiry-state entry |

### 5.7 Integration seam

- **Location seam (verified in code):** the app today stores all data under `{app}\` (`ConfigFile := A_ScriptDir . "\config.json"`; `setup.iss` `DefaultDirName={autopf}`), and the uninstaller runs `DelTree({app}\data)` + deletes `config.json`. `license.dat` is therefore deliberately placed at **`%APPDATA%\QuickSay\license.dat`** — outside the wipe path — so the trial survives uninstall/reinstall. **Hard requirement on M.1/M.3:** the installer must create `%APPDATA%\QuickSay\` and the uninstaller must **not** delete it. Migrating the rest of the app's data to `%APPDATA%` is out of scope for T2 (future work).
- **Privacy footprint (F11):** because `license.dat` intentionally survives uninstall, an encrypted file containing the buyer email + JWT remains in `%APPDATA%\QuickSay\` after the app is removed. It is DPAPI-encrypted (low risk), but a user who uninstalls expecting full data removal leaves PII behind. M.3 must (a) add a one-line disclosure to the privacy policy, and (b) offer a "remove my QuickSay data" affordance (e.g. an uninstaller checkbox or a settings action) that deletes `%APPDATA%\QuickSay\` on explicit consent.
- Hooks: `InitTrial()`/`CheckLicenseState()` are called early in `QuickSay.ahk` startup and gate `StartRecording()` (recording refused in `PAYWALL_BLOCKING`). The paywall is a **separate** WebView2 window (so the user can purchase even if settings is broken). Reads/writes go through `AcquireConfigLock()`. Config fields `crashReportingEnabled` etc. are unrelated; the trial/license state authoritatively lives in `license.dat`, **not** `config.json` (T2.3's `config.example.json` entries are documentation only).

---

## 6. Subsystem E — Crash reporting (recommendation + chosen contract)

### 6.1 The two options and the recommendation

| Option | Pros | Cons |
|---|---|---|
| **(1) Sentry-direct** — app POSTs the envelope straight to `o<ORG>.ingest.sentry.io` | No extra Worker; cheapest; matches T2.4 scope, research §5, OD-5; fewer processors in the data path | Public DSN ships in the binary (low-value secret) |
| (2) Self-hosted CF forwarder `crash.quicksay.app` | Server-side redaction backstop; hides DSN; can fan out to R2/Discord | Another Worker to build/deploy/monitor; endpoint equally discoverable; adds us as a processor |

**Recommendation (confirmed with the user — §11 Q4): (1) Sentry-direct.** The user-facing UX is identical either way (opt-in modal + toggle + a background POST), so the forwarder buys no UX. The correct safety mechanism is the **client-side allowlist** (attach only safe fields), which runs regardless of backend, and the public DSN is not a meaningful secret (Sentry rate-limits abuse). It is cheap to reverse: v2.x can add `crash.quicksay.app` by changing one POST URL, with the envelope + scrub logic unchanged. **The self-hosted forwarder is the documented v2.x fallback** (triggers: DSN-abuse quota exhaustion, a need for server-side redaction, or Discord/R2 mirroring).

### 6.2 DSN location

The **public** DSN key is a compiled constant `SENTRY_DSN_PUBLIC` in `QuickSay.ahk` (it is not a secret; only the project-public key ships — never the `sentry_secret`). The ingest URL is `https://o<ORG>.ingest.sentry.io/api/<PROJECT>/envelope/?sentry_key=<SENTRY_DSN_PUBLIC>&sentry_version=7`.

### 6.3 Envelope wire format (newline-delimited; `Content-Type: application/x-sentry-envelope`)

```
{"event_id":"<32-hex-no-dashes>","sent_at":"<iso8601>"}
{"type":"event","content_type":"application/json"}
{"event_id":"<same>","timestamp":<unix>,"level":"error","platform":"native","release":"quicksay@<VERSION>","environment":"<beta|production>","exception":{"values":[{"type":"<errClass>","value":"<scrubbed message>"}]},"tags":{"hotkey_mode":"<hold|tap>","last_action":"<idle|recording|transcribing|paste>"},"contexts":{"os":{"name":"Windows","version":"<generic build, e.g. 11 26200>"}},"extra":{"line_file":"<username-scrubbed path>","line_number":<int>,"this_func":"<A_ThisFunc>"}}
```

### 6.4 Allowlist (the envelope carries ONLY these) and PII scrub

**Allowlist:** `release`, `environment`, `level`, `platform`, `exception.type`, `exception.value` (scrubbed), `tags.hotkey_mode`, `tags.last_action`, `contexts.os` (generic name+build, **never** machine name), `extra.line_file` (username-scrubbed), `extra.line_number`, `extra.this_func`. Anything not listed is **not attached** (allowlist, not blocklist).

**Scrub (second line of defense over any free text that reaches `exception.value`/`line_file`):**

| Sensitive | Pattern | Replacement |
|---|---|---|
| Groq API key | `gsk_[A-Za-z0-9]+` | `[REDACTED_API_KEY]` |
| License JWT | three base64url segments joined by `.` (`eyJ…\.…\.…`) | `[REDACTED_JWT]` |
| Username in paths | any `<drive>:\Users\<name>\`, `%USERPROFILE%`, and UNC `\\host\…\Users\<name>\` | `…\Users\[USER]\` |
| Audio paths | `…\data\audio\QS_*.wav` | `[AUDIO_FILE]` |
| Transcript text | any transcribed content | **never attached** (omit, don't scrub) |
| Machine/computer name | `A_ComputerName` value | **never attached** |

> **F12 — the allowlist is the load-bearing control; the scrub is a best-effort backstop.** Safety comes from the envelope builder attaching *only* the allowlisted fields above — the regex scrub is a second line of defense for free text that reaches `exception.value`/`line_file`, and is explicitly **not** relied upon for completeness. The T2.4 PII grep-gate test (zero matches for `gsk_`/`eyJ`/username/`.wav`/computer-name on a synthetic-secrets envelope) is what proves the contract.

- **Throttle:** in-memory ring of send timestamps; **max 5 per rolling 60 minutes**; drop excess (debug-logged when `debugLogging`). Honors MASTER-PLAN §7.
- **Opt-in (off by default):** config `crashReportingEnabled` (default `false`) and `crashReportingPrompted` (default `false`). First-run modal copy (verbatim contract): *"Help us fix bugs? QuickSay can send anonymous crash reports — no transcripts, no audio, no personal information. [Yes, help out] / [No thanks]."* No envelope is ever sent before the user answers (`crashReportingPrompted=false` → hard no-op). The settings toggle (Privacy/Advanced) flips `crashReportingEnabled`; OFF stops all reporting immediately.

### 6.6 Failure modes & recovery

| Failure | Behavior |
|---|---|
| Network down / Sentry 5xx | Fire-and-forget, ≤5 s timeout; drop the report; never block the hot path |
| A bug inside the reporter | Reporter is crash-safe: log + attempt send, then let AHK's normal error handling proceed (never mask the user's real error) |
| Throttle exceeded | Drop the 6th+; debug-log the drop |
| Not opted in | `ReportError()` is a no-op (no POST attempted) |

### 6.7 Integration seam

`lib/crash-reporter.ahk` (T2.4) installs an `OnError` handler early in `QuickSay.ahk` startup. It POSTs via `lib/http.ahk` and builds JSON with `EscapeJson()`. Natural signal sources already audited: the `isProcessing` wedge (T1.1-006) and the absence of a persistent last-error (T1.1-022). It must **not** read `debug_log.txt` transcript bodies (T1.1-011).

---

## 7. Subsystem F — Signed updates + key rotation

### 7.1 Signed `version.json` schema (additive — old apps ignore new fields)

```json
{
  "version": "2.0.0",
  "download_url": "https://.../QuickSay-Setup-2.0.0.exe",
  "changelog": ["…", "…"],
  "installer_sha256": "<hex sha256 of the installer at download_url>",
  "released_at": "2026-..T..Z",
  "keyId": "qs-2026",
  "signature": "<base64url Ed25519 signature over the canonical payload>"
}
```

### 7.2 Canonicalization recipe (signer ≡ verifier, byte-for-byte)

The **signed payload** is the manifest **excluding `signature`**, serialized as:
- a JSON object containing exactly `{changelog, download_url, installer_sha256, keyId, released_at, version}`,
- **keys sorted lexicographically by ASCII code point** (all keys are fixed ASCII, so code-unit vs code-point is moot — stated for certainty),
- **compact separators** (`,` and `:`, no insignificant whitespace),
- UTF-8 bytes; array element order (`changelog`) preserved.

**Escaping is pinned exactly (F5) — Node `JSON.stringify` (signer) and `lib/JSON.ahk` (verifier) must agree byte-for-byte:** minimal RFC 8259 escaping only — escape `"` → `\"`, `\` → `\\`, and control chars U+0000–U+001F (as `\uXXXX` or their short forms `\n`,`\t`, etc.); **do NOT escape `/`**; **do NOT `\u`-escape non-ASCII** — emit raw UTF-8 (so an emoji/accented changelog entry is its literal bytes, matching `JSON.stringify`). Sign the UTF-8 bytes with Ed25519; `signature = base64url(no padding)` of the 64-byte signature. The verifier reconstructs the identical string and verifies. This is the classic break point — **T2.5's byte-identity test #9 MUST include a non-ASCII changelog entry** (emoji + accented char + a `/`), and test #8 asserts an RFC 8032 known-answer vector.

### 7.3 Verification in `CheckForUpdates()` (fail closed)

After `HttpGet(version.json)`: look up `TRUSTED_KEYS[keyId]` (unknown → reject) → rebuild the §7.2 canonical payload → Ed25519-verify `signature` (shared `lib/ed25519.ahk`, which hardcodes Ed25519 — no `alg` field is read, §3.4). On **missing/malformed/invalid signature or unknown `keyId`** → treat as **no update available**, do **not** offer the download, log the specific reason (gated by `debugLogging`; user-facing message stays generic: *"Could not verify the update. Please download from quicksay.app."*). On valid signature → proceed with the existing `CompareVersions(localVersion, …)` flow and the `^https://` `download_url` guard.

**F6 — `installer_sha256` is signed but binary-integrity is only *pending* in v2.0.** Today `CheckForUpdates()` opens `download_url` in the browser; it does **not** download-and-hash the installer, so the signed `installer_sha256` is committed-to but **not enforced** — the bytes the user runs are guarded by **Azure code-signing + TLS**, not yet by the manifest. The contract: **if/when the app downloads the installer itself (M.1 candidate), it MUST verify the bytes' SHA-256 equals the signed `installer_sha256` before executing, fail-closed.** Until then `CheckForUpdates()` surfaces/logs the expected hash, and the manifest signature protects the *version + URL + changelog*, with binary integrity resting on code-signing. (Self-review T2 is correspondingly downgraded to "mitigated-pending".)

### 7.4 Key rotation (same key as the JWT — §8)

The Ed25519 key that signs JWTs also signs `version.json`. Rotation uses the **`keyId` → public-key map** the app already trusts:
1. Generate a new keypair under a new `keyId` (e.g. `qs-2027`).
2. Ship an app release whose `TRUSTED_KEYS` map contains **both** the old and new public keys.
3. Once that release is widely adopted, switch the Worker (`ED25519_PRIVATE_KEY`) and `release.ps1` to sign with the **new** key.
4. Retire the old `keyId` after a **transition window of ≥1 release cycle (~90 days)** — long enough that nearly all installs trust the new key.

**Policy (§11 Q3): one shared key (`qs-2026`) for staging + production; rotate only on compromise** (no scheduled rotation). The multi-key map is the non-breaking mechanism for the day a rotation is forced.

### 7.5 Failure modes & recovery

| Failure | Behavior |
|---|---|
| Tampered manifest (any signed field changed) | Verify fails → no update offered + reason logged (fail closed) |
| `signature` stripped | Rejected (fail closed) |
| Unknown `keyId` | Rejected (fail closed) |
| Manifest fetch fails / R2 down | No update this cycle; retried next launch (status quo) |
| Old app (pre-T2.5) reads new manifest | Ignores new fields; behaves as today (no verification) — acceptable, additive |
| Private key absent at sign time | `release.ps1` **fails loudly** — no unsigned release ships |

### 7.6 Integration seam

`release.ps1` gains a sign step **after** the installer is built (so its SHA-256 is final) and **before** R2 upload; it plugs into T1.6's `VERSION`/`--check-sync` refactor (**T1.6 must merge first**). `CheckForUpdates()` (~`QuickSay.ahk:3392`) gains the verify step using `lib/ed25519.ahk`. The private key is read from a secret/env at sign time (never the repo); the public key map is compiled into the app.

---

## 8. Cross-subsystem concerns

### 8.1 Key management (the single most important shared asset)

- **One Ed25519 keypair**, `keyId = "qs-2026"`, generated as the final concrete step of **this session (T2.1)** — per MASTER-PLAN §6/§4a. It signs **both** license JWTs (T2.2) and `version.json` (T2.5); the app verifies **both** with the same public key (T2.3 + update check).
- **Private key** → CF secret `ED25519_PRIVATE_KEY` (PKCS#8 PEM) **+** offline backup (1Password/equivalent). Never in git.
- **Public key** → committed (SPKI PEM for reference; raw-32-byte base64url for the app) and baked into `QuickSay.ahk`/`lib/license.ahk` as `TRUSTED_KEYS["qs-2026"]`.

**Generated `qs-2026` public key (2026-05-30, this session — safe to commit/bake in):**
```
keyId            : qs-2026
publicKeySha256  : 761d22dfcc2302fe1364bc36ec76b7aa488c666adc828f0247e866bf80fde09b
SPKI PEM         : MCowBQYDK2VwAyEAUmeruJlXQ1tyEX5fPzixUMjQD//Lm0NqIPSWReHRsw8=
raw-32 base64url : UmeruJlXQ1tyEX5fPzixUMjQD__Lm0NqIPSWReHRsw8
```
The matching **private** key (PKCS#8 PEM) was generated to `%USERPROFILE%\.quicksay-keys\qs-2026-ed25519-private.pem` — **never committed, never logged**. Before T2.2 deploys: `wrangler secret put ED25519_PRIVATE_KEY` (staging) from this file **and** copy it to an offline backup (1Password/equivalent, per MASTER-PLAN §7).
- **I-a — deleting the local private-key copy is a MANDATORY M.1 gate, not advisory.** A lingering copy in `%USERPROFILE%\.quicksay-keys\` is the most likely real-world compromise path for the key that signs both licenses and updates. M.1 must verify the file is gone (and exists in the CF secret store + offline backup) before rc1.
- **I-c — build-time trust-anchor assertion.** T2.3/T2.5 MUST include a unit test asserting the SHA-256 of the compiled raw-32 public key equals `761d22df…fde09b`, so a corrupted/wrong paste can never ship a bad trust anchor.
- **Unified `keyId` scheme:** JWTs carry `kid` in the JOSE header; `version.json` carries `keyId`. Both resolve against the same app-side `TRUSTED_KEYS` map.
- **Shared verifier:** `lib/ed25519.ahk` exposes one `VerifyEd25519(message, signature, publicKey)` primitive used by **both** T2.3 (JWT) and T2.5 (manifest). Whichever session lands first creates it; the other imports it. (Cross-session dependency — §9 + MASTER-PLAN addition.)
- **Keypair-owner reconciliation:** T2.2's Phase 2 wording ("generate a staging key") is **superseded** — T2.2 *uses* the T2.1-generated key (`wrangler secret put ED25519_PRIVATE_KEY`), it does not generate a new one. T2.2's `scripts/generate-keypair.mjs` remains a documented utility for rotation/DR only.

### 8.2 Secret inventory

| Secret | Lives in | Seen by app? | Notes |
|---|---|---|---|
| `ED25519_PRIVATE_KEY` | CF secret + offline backup | No | Signs JWTs + version.json |
| `LEMONSQUEEZY_API_KEY` | CF secret | No | Only `src/lemonsqueezy.ts` |
| `LEMONSQUEEZY_WEBHOOK_SECRET` | CF secret | No | HMAC webhook verify |
| Ed25519 **public** key | git + app binary | Yes (by design) | Trust anchor |
| `SENTRY_DSN_PUBLIC` | app binary | Yes (not a secret) | Public DSN key only — never `sentry_secret` |

### 8.3 Staging → production promotion

T2.2 deploys to **staging** only and puts the (T2.1) private key as the staging secret. M.1 builds rc1 against `license-staging.quicksay.app`. M.3 runs `wrangler deploy --env production`, re-puts the **same** secrets for production, configures the LS production webhook URL, and flips the app's compiled `LICENSE_WORKER_URL` to `license.quicksay.app`. Because staging and production share one keypair (`qs-2026`), the rc1 binary needs no re-signing/rebuild to trust production tokens.

### 8.4 Logging discipline (normative, both sides)

- **Worker:** never log the JWT, the raw license key, the unhashed `machine_id`, the buyer email, or any secret (`ED25519_PRIVATE_KEY`, `LEMONSQUEEZY_API_KEY`, `LEMONSQUEEZY_WEBHOOK_SECRET`). License keys exist in KV only as `sha256(license_key)`, so a KV dump is not a key dump. `wrangler tail` during smoke tests must show none of these.
- **App:** never write the JWT, license key, or Groq API key to `debug_log.txt` (the crash-reporter scrub list, §6.4, is the backstop). The license-state log records only the coarse state name (e.g. `GRACE_PERIOD`), never token contents.

---

## 9. Per-session build handoff

| Session | Implements | Key inputs (from this spec) | Acceptance criteria |
|---|---|---|---|
| **T2.2** (CF Worker) | §2, §3 (mint), §4, plus the additive `/trial/status` + `/trial/report` (§5.4) | Endpoint table §2.3; JWT shape §3.1; KV shapes §2.2; webhook events §4.2; **uses the T2.1 keypair** (§8.1), does not generate one | `/activate /validate /refresh /deactivate /webhook/lemonsqueezy /pricing /trial/status /trial/report` match exactly; JWT decodes to §3.1 byte-for-byte; webhook verify-before-parse + constant-time; **status-monotone + mandatory-timestamp + dedup-before-gate (§4.3)**; LS-down → 503 (never lock out); per-IP + per-machine_id rate limits (§2.5); staging deploy live; no secret/JWT leakage in `wrangler tail` |
| **T2.3** (trial + paywall) | §5 + §3 (verify side) | `license.dat` format §5.1; state machine §5.2; `ComputeMachineId()` §5.3; anti-cheat §5.4; `/activate` contract §2.3; public key (raw-32 baked in); **blocking** paywall (§11 Q1) | 13 unit tests pass; recording refused in PAYWALL_BLOCKING; clock-rollback → TRIAL_EXPIRED; `license.dat` at `%APPDATA%`; **best-effort fail-open `/trial/status` gate at trial start (§5.4)**; tamper → REVOKED; **JWT verify pins `alg==EdDSA` (rejects `alg:none`, §3.4); build-time public-key SHA-256 assert (I-c)**; uses `lib/ed25519.ahk` |
| **T2.4** (crash reporting) | §6 | Envelope §6.3; allowlist + scrub §6.4; throttle + opt-in §6.5; DSN constant §6.2; **Sentry-direct** (§11 Q4) | Real Sentry event ≤10 s; PII grep on the wire = 0 matches; throttle caps 5/hr; default OFF until consent; 14 tests pass |
| **T2.5** (signed updates) | §7 | Schema §7.1; canonicalization §7.2; verify §7.3; `keyId` scheme + rotation §7.4/§8.1; key storage §8 | RFC 8032 KAT passes; tamper rejected; fail-closed; real signer↔verifier round-trip **incl. a non-ASCII changelog entry (§7.2 F5)**; **installer_sha256 verified-on-download if the app downloads it (§7.3 F6)**; private key not in git; uses `lib/ed25519.ahk`; **merges after T1.6** |

**T2.3 reconciliation (required by the session):** §5 matches T2.3's `license.dat` field set and state machine. Divergences resolved: (a) T2.3's file-header path `data/license.dat` → use **`%APPDATA%\QuickSay\license.dat`** (§5.6); (b) trial + license are **one** `license.dat` (the skill's separate `trial.dat` is superseded); (c) T2.3's `config.example.json` trial fields are documentation only — the authoritative state is in `license.dat`.

**Cross-session dependencies to add to MASTER-PLAN:**
1. **Shared AHK Ed25519 verifier** (`lib/ed25519.ahk`) between T2.3 and T2.5 — whichever lands first exposes `VerifyEd25519(...)`; the other imports it. Prevents two independent crypto implementations.
2. **Installer durability** — M.1/M.3 must create `%APPDATA%\QuickSay\` and exclude it from uninstall (today the uninstaller wipes `{app}\data`). Without this, the local trial-reset defense is lost.
3. **T2.2 uses the T2.1 keypair** (does not generate its own) — §8.1.
4. **`/trial/status` (gate) + `/trial/report` (populate)** are additive Worker endpoints for the fail-open trial-reset gate (rate-limited + 18-mo TTL, §2.5/§2.2); they gate **trial start only**, never a paid `/activate`.

---

## 10. Appendix — Decisions made by the architect (with rationale)

- **D1 · KV namespace `LICENSE_CACHE`** (not `LICENSE_KEYS`). The T2.1 and T2.2 prompts (the implementer) use `LICENSE_CACHE`; MASTER-PLAN §6 and the skill say `LICENSE_KEYS`. Locked to `LICENSE_CACHE`; MASTER-PLAN §6 + skill should be updated. Low-stakes naming; cheap to reverse.
- **D2 · Webhook route `/webhook/lemonsqueezy`** (not `/webhook`). Descriptive, future-proof for additional providers; the LS dashboard URL is set at M.3, so the path is internal. T2.2 follows the spec.
- **D3 · Single `license.dat`** holding trial + license (the skill's separate `trial.dat` is superseded by T2.3's unified file). One DPAPI file, one lock path.
- **D4 · `license.dat` at `%APPDATA%\QuickSay\`** (the skill locks this; I confirm it against the real installer). Survives uninstall → trial-reset resistance. Imposes the M.1/M.3 installer requirement (§5.7).
- **D5 · Unified `keyId` scheme** — JWT `kid` header + `version.json` `keyId`, one app-side `TRUSTED_KEYS` map, one shared `lib/ed25519.ahk` verifier. Avoids duplicate crypto and a key-handoff cascade.
- **D6 · `nbf` omitted, `iat` present** in the JWT. No future-dating need; smaller token.
- **D7 · 60 s `clockLeewaySeconds`** on the `exp` comparison so trivial clock skew never prematurely expires a valid license.
- **D8 · KV value shapes** (§2.2) and the `RATE_LIMIT` counter scheme (§2.5) — concrete so T2.2 and the webhook agree.
- **D9 · `order_refunded` + `subscription_created` added** to the webhook event set (from the skill); refunds must revoke, future subscriptions must no-op safely.
- **D10 · Rate limits** `/activate` 10/hr, `/refresh` 5/hr per machine_id (skill defaults; user did not override — §11 Q5).
- **D11 · `order_created` = log-only** + `/pricing` order-counter bump; no license-state change (user did not override — §11 Q6).
- **D12 · Crash reporting = Sentry-direct** (user delegated the call — §11 Q4); self-hosted forwarder documented as the v2.x fallback. Rationale in §6.1.
- **D13 · OD-1b financing (verified 2026-05 against LS docs):** LemonSqueezy's documented methods are cards/PayPal/Apple Pay — **no native installment/BNPL**. So "$74 financing" = PayPal-surfaced "Pay Later/Pay-in-4" in eligible regions, not an LS-native or QuickSay-built system. No custom installment flow; M.3 verifies the then-current methods; messaging degrades to "lifetime access" if none. (§2.4)
- **D14 · `/trial/status` + `/trial/report` endpoints** implement the fail-open trial-reset gate (see D17).

### Decisions added from the independent security-auditor pass (2026-05-31)
*(An independent `comprehensive-review:security-auditor` agent reviewed the draft; it raised 4 P1 + 5 P2 + minor findings. All P1/P2 are resolved in-spec; outcomes recorded in `findings/T2.1-security-review.md`.)*
- **D15 · JWT `alg` is pinned (F1).** §3.4 asserts `alg=="EdDSA"`/`typ=="JWT"` before the signature check; the verifier hardcodes Ed25519 and never reads the algorithm from the token (defeats `alg:none`/confusion). `version.json` carries no `alg` field at all.
- **D16 · Webhook is status-monotone + timestamp-mandatory (F4/F9).** A refund's own trailing `license_key_updated` can no longer resurrect a `disabled` license (`updated` never touches `status`; re-grant needs a `created` with a new `orderId`); a missing/unparseable event timestamp is rejected, never defaulted; dedup runs before the monotonic gate.
- **D17 · Trial blocklist = functional fail-open gate (F2/F3; user-selected 2026-05-31).** The server blocklist **gates trial start** via a best-effort `GET /trial/status` (fail-open when offline; re-checked once on the next online launch), populated by `/trial/report` on trial-expiry; both rate-limited + 18-mo TTL (§2.5/§2.2). It is **never** consulted for a paid `/activate`. The user chose this over advisory-telemetry for stronger anti-reset. Accepted tradeoffs: a single machine-id-hash call to the first-party license endpoint on first launch (no PII, fail-open, privacy-policy disclosed), and a bounded victim-grief residual (A7, §5.4).
- **D18 · `/activate` error codes collapsed to `invalid` (F8).** `not_found` and `disabled` both return `invalid` so an unauthenticated caller gets no key-validity oracle; `already_activated` is retained for legitimate-UX (transfer flow).
- **D19 · Two-layer rate limiting; `machine_id` is not a security boundary (F8).** Per-machine_id KV counters + per-IP Cloudflare WAF rules on the mutating endpoints, plus a global per-IP `/activate` ceiling sized to the LS quota (each `/activate` is a paid LS call).
- **D20 · `version.json` canonicalization escaping pinned (F5).** Minimal RFC 8259 escaping; no `/` escaping; no `\u` of non-ASCII (raw UTF-8) — and the T2.5 byte-identity KAT must include a non-ASCII changelog entry.
- **D21 · `installer_sha256` is "mitigated-pending" (F6).** Signed and committed-to, but binary integrity rests on Azure code-signing + TLS until the app downloads-and-hashes the installer itself (M.1 candidate; verify-before-exec, fail-closed).
- **D22 · Grace table uses `effectiveExp` half-open partition (F7).** `effectiveExp = exp + leeway`; leeway applied once at the access cutoff only; intervals partition cleanly.

## 11. Appendix — Open questions resolved with the user this session

| # | Question | Answer |
|---|---|---|
| Q1 | Paywall behavior after trial expiry | **Blocking modal** (app opens for purchase/settings/help; recording disabled; cannot dismiss into a working recording state) |
| Q2 | JWT refresh / re-validation cap | **Rolling 14-day** — each `/refresh` re-signs a fresh `exp`; **no extra hard cap** (the 7-day grace + RE_VALIDATION_NEEDED boundary already forces an online re-check by ~day 21 offline) |
| Q3 | Key strategy + rotation | **One shared key** (`qs-2026`) for staging + prod; **rotate only on compromise**; ≥1-release (~90-day) transition window via the multi-key `keyId` map |
| Q4 | Crash backend (Sentry-direct vs forwarder) | **Sentry-direct** (user delegated to the architect; recommendation accepted) — forwarder is the v2.x fallback |
| Q5 | Rate-limit thresholds | **`/activate` 10/hr, `/refresh` 5/hr** per machine_id (skill defaults; not overridden) |
| Q6 | `order_created` webhook | **Handled, log-only** (+ `/pricing` counter bump); no license-state change (not overridden) |
