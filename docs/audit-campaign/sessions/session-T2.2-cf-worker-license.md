# Session T2.2 — Build CF Worker License Issuer (BUILD)

> **Model:** Sonnet 4.6
> **Effort:** high
> **Switch commands:** `/model sonnet` then `/effort high`
> **Branch:** `audit/T2.2-cf-worker-license`
> **Parallel-safe with:** T2.3, T2.4, T2.5, T2.6, all of Track 1 (different files / different repo subtree)
> **Depends on:** T2.1 (backend design spec — this session implements §2 / §3 / §4 of that spec). Do not start until the spec is approved.
> **Blocks:** M.1 (integration needs the worker live on staging for the paywall activation flow). Also unblocks T2.3's end-to-end activation test against staging.
>
> Before pasting this prompt: confirm `/model sonnet` and `/effort high`. The scope is bounded and spec-driven — Opus is not needed. The design thinking already happened in T2.1.

---

## Prompt to paste

You are building the QuickSay license-issuer Cloudflare Worker. This is the server that turns a LemonSqueezy license key into an Ed25519-signed JWT the app verifies offline, and that receives LemonSqueezy webhooks to keep its license cache current. You implement the contracts the T2.1 spec already defined — you do not redesign them.

### Context

QuickSay sells a one-time / lifetime license through LemonSqueezy (**$39 launch for the first 500 orders → $74 regular, with installment financing on the $74 tier**). LemonSqueezy's own License API forces a live HTTPS call on every validation, which is brittle on flaky networks and during LS outages. The Worker you build wraps LS: on activation it mints an **Ed25519-signed JWT** (14-day exp, 7-day grace) that the app verifies locally with a bundled public key — no network round-trip per recording. The Worker also receives LS webhooks to keep a KV cache of license status current, so activations stay fast and revocations propagate.

Working directory for this session: `C:\QuickSay\Backend\license-worker\` — **this directory does not exist yet; you create it.** It is a NEW subtree of the monorepo at `C:\QuickSay\`, separate from `Development/` (the app) and `Website/`. Confirm `C:\QuickSay\Backend\` is the right home before scaffolding (the MASTER-PLAN §5 references `C:\QuickSay\Backend\license-worker\` as the worker's home).

**Read these first, in this order:**
1. `C:\QuickSay\CLAUDE.md` — repo layout (monorepo vs Development nested repo), so you commit to the right place.
2. `C:\QuickSay\docs\audit-campaign\MASTER-PLAN.md` — §6 (topology, KV names, secret names), §7 (risk: webhook outage must not lock out paying users; cached check survives 14-day LS outage).
3. `C:\QuickSay\docs\audit-campaign\specs\T2-production-systems-design.md` — **the authoritative contract.** §2 (Worker endpoints), §3 (JWT claim shape + Ed25519 details), §4 (webhook events + HMAC verification). If anything in the spec is ambiguous, STOP and ask the user — do not improvise a contract that T2.3 (the app) is also building against.
4. The `quicksay-go-to-paid` skill — invoke it. It has the LemonSqueezy License API endpoint contracts, the webhook event list, the staging-vs-prod env split, and the "CF Worker is the only place the LS API key lives" rule.
5. `C:\QuickSay\docs\audit-campaign\research\competitor-backend-research.md` — §4 (the wrapper rationale) and §6 (LS has no built-in offline tokens — that's why this Worker exists).

Use `context7` (`resolve-library-id` → `query-docs`) to pull current docs for **`jose` v5**, **Wrangler v3+**, and the **Cloudflare Workers KV** API before writing code — the APIs shift between versions and your training data may be stale.

### Scope — files you create (all under `C:\QuickSay\Backend\license-worker\`)

| File | Purpose |
|---|---|
| `wrangler.toml` | Worker config: name, compatibility date, KV namespace bindings (`LICENSE_CACHE`, `TRIAL_BLOCKLIST`), `[env.staging]` + `[env.production]` with the two hostnames |
| `package.json` | Deps: `jose` v5, `wrangler` (dev), `vitest` + `@cloudflare/vitest-pool-workers` (test), `typescript` |
| `tsconfig.json` | Workers-targeted TS config |
| `src/index.ts` | Router: dispatches `POST /activate`, `POST /validate`, `POST /webhook` (+ `/refresh`, `/deactivate` if the spec includes them); CORS; 404 fallback |
| `src/jwt.ts` | Ed25519 JWT mint + verify using `jose` (NOT `jsonwebtoken`); claim shape exactly per spec §3 |
| `src/lemonsqueezy.ts` | Thin client for LS License API (`activate-license-key`, `validate-license-key`, `deactivate-license-key`); the ONLY module that uses `LEMONSQUEEZY_API_KEY` |
| `src/license.ts` | Business logic: activation flow, validation flow, KV cache read/write, trial blocklist checks, rate limiting |
| `src/webhook.ts` | LS webhook handler: HMAC-SHA256 signature verify (constant-time, on raw body, before parse), event dispatch, idempotency |
| `tests/jwt.test.ts` | JWT mint→verify round-trip; tampered-signature rejection; wrong-key rejection; exp/grace boundary |
| `tests/license.test.ts` | `/activate` success → JWT; already-activated → 403; rate-limit → 429; LS-down → 503 fallback per spec |
| `tests/webhook.test.ts` | Valid signature accepted; bad signature → 401 (rejected before parse); redelivery idempotent; KV mutated correctly per event |
| `README.md` | Setup: secrets to put, how to deploy staging, how to run tests, how to generate the keypair (pointer only — see below) |
| `.gitignore` | `node_modules/`, `.dev.vars`, `.wrangler/`, any local key material |

**Secrets — set via `wrangler secret put`, NEVER committed:**
- `ED25519_PRIVATE_KEY` (PEM or raw per spec §3)
- `LEMONSQUEEZY_API_KEY`
- `LEMONSQUEEZY_WEBHOOK_SECRET`

**Forbidden:**
- ❌ Anything under `C:\QuickSay\Development\` — that's the app (T2.3 owns `lib/license.ahk`).
- ❌ Anything under `C:\QuickSay\Website\`.
- ❌ Committing any key material, `.dev.vars`, or LS API key into git.
- ❌ Re-deriving the JWT claim shape, endpoint contracts, or webhook handling — those are frozen in the T2.1 spec.

### Endpoint contracts (must match the T2.1 spec exactly — this is the summary, the spec is authoritative)

```
POST /activate
  body: { license_key: string, machine_id: string }
  → 200 { jwt: string, email: string, exp: number }   (LS says active, JWT minted)
  → 403 { error: "...", code: "already_activated" | "not_found" | "disabled" }
  → 429 { error: "rate_limited" } + Retry-After header
  → 503 { error: "upstream_unavailable" } + Retry-After   (LS API down; app keeps current state)

POST /validate
  body: { jwt: string }
  → 200 { valid: true, exp: number }
  → 403 { valid: false, code: "revoked" | "expired" | "bad_signature" }

POST /webhook         (LemonSqueezy → us)
  headers: X-Signature: <hmac-sha256 hex/base64 per LS>
  body: raw JSON LS event
  → 200 (verified + processed, or unknown-event-ignored)
  → 401 (bad signature — no body, rejected before JSON parse)
  → 500 (KV write failed — so LS retries)
```

KV namespaces: `LICENSE_CACHE` (license_key_hash → {status, email, plan, instance_id}), `TRIAL_BLOCKLIST` (trial_machine_id → 1, for trials already consumed). Use exactly the names the spec/MASTER-PLAN specify.

### Phase 1 — Pull current docs, scaffold, confirm the contract

1. `git pull origin main` and confirm the T2.1 spec is present and approved (check the MASTER-PLAN Status Tracker shows T2.1 ✅). If the spec is missing or unapproved, STOP and tell the user.
2. Pull current `jose` v5, Wrangler v3+, and Workers KV docs via `context7`.
3. Scaffold the directory and `package.json` / `wrangler.toml` / `tsconfig.json`. Run `npm install`.
4. Re-read spec §2/§3/§4 and write a one-paragraph confirmation of the exact JWT claim names and the exact endpoint shapes you'll implement. If any ambiguity, ask the user now — before writing handlers — because T2.3 is building the app side against the same spec and the two MUST agree byte-for-byte on claim names.

### Phase 2 — Keypair generation (one-time setup, documented not automated)

The Ed25519 keypair is generated ONCE and lives in the CF secret store + an offline backup (1Password or equivalent per MASTER-PLAN risk register) — **never in git**. Write a small `scripts/generate-keypair.mjs` (Node, using `jose` `generateKeyPair('EdDSA', { crv: 'Ed25519' })` or `node:crypto`) that prints the private key (PEM/raw per spec) and the public key. The script is committed; its OUTPUT is not. The public key gets baked into the AHK app in T2.3 — print it in a copy-paste-ready form and note in the README that T2.3 needs it.

**Do not commit any generated key.** Generate a key for staging, `wrangler secret put ED25519_PRIVATE_KEY --env staging`, and record the public key in the README handoff section (public keys are safe to commit).

### Phase 3 — Implement, test-first per module

Invoke `superpowers:test-driven-development`. Build in this order, tests before implementation for each module:

1. `src/jwt.ts` + `tests/jwt.test.ts` — mint with the spec's claim shape; verify; reject tampered + wrong-key; exp/grace boundary math matches spec §3 exactly. Get this green first — everything depends on it.
2. `src/lemonsqueezy.ts` — the LS License API client. Mock LS responses in tests (don't hit live LS in unit tests). Handle LS 200/403/500 → your contract's 200/403/503.
3. `src/license.ts` + `tests/license.test.ts` — `/activate` and `/validate` business logic: LS call → KV cache → JWT mint; rate limiting (per-machine_id cap from spec, 429 + Retry-After); LS-down fallback (503, never lock out per MASTER-PLAN §7). Use the KV cache to serve activations during an LS outage where the spec allows.
4. `src/webhook.ts` + `tests/webhook.test.ts` — **verify HMAC-SHA256 over the RAW body using `LEMONSQUEEZY_WEBHOOK_SECRET`, in constant time, BEFORE JSON-parsing.** Bad signature → 401, no body. Then dispatch `license_key_created` / `license_key_updated` / `license_key_deleted` (+ `order_created` if the spec said yes) to KV mutations. Idempotent on redelivery per spec §4.
5. `src/index.ts` — wire the router, CORS, 404 fallback.

Security must-haves (the skill's anti-patterns list — enforce them):
- The LS API key appears ONLY in `src/lemonsqueezy.ts`, read from the env binding. Never in a response, never logged.
- Never log the JWT, the license key, or the private key. If you log for debugging, scrub.
- Webhook signature verified before parse, constant-time compare.
- Store license keys in KV hashed (per spec) — not raw — so a KV dump isn't a key dump.

### Phase 4 — Deploy to staging + live smoke

1. `wrangler deploy --env staging` → `license-staging.quicksay.app` (production deploy is deferred to M.1 — do NOT deploy `--env production` this session).
2. Confirm the route resolves. Set up at least one **test license key** in LemonSqueezy test mode (document the gotcha from the skill: test keys don't work against the live store and vice versa). Record the test key + the staging activation command in the README so T2.3 can use the same key for its end-to-end test.
3. Live smoke against staging:
   - `POST /activate` with the test key + a fake machine_id → 200 with a JWT. Decode the JWT (jose or jwt.io) and confirm the claim shape matches spec §3.
   - `POST /validate` with that JWT → 200.
   - `POST /validate` with a tampered JWT → 403.
   - `POST /activate` a second time with a different machine_id if the key's activation limit is 1 → 403 `already_activated` (or per the spec's instance policy).
   - Send a webhook with a **valid** HMAC signature → 200 + KV mutated (verify with `wrangler kv key get`). Send one with a **bad** signature → 401.
4. Confirm `wrangler tail` shows NO logging of the JWT, license key, or API key during any of the above.

### Phase 5 — Verification

Invoke `verification-before-completion`. Verifiable gates:
- [ ] `npm test` — all unit tests pass (jwt + license + webhook). Paste the summary.
- [ ] Staging deploy live; all five Phase 4 live-smoke checks pass.
- [ ] `wrangler tail` confirms no secret/JWT/key leakage in logs.
- [ ] `git status` shows NO key material, `.dev.vars`, or LS API key staged.
- [ ] Invoke `code-review` on the diff; address every P0/P1.

### Done When

- [ ] `C:\QuickSay\Backend\license-worker\` scaffolded with all files listed in Scope.
- [ ] `/activate`, `/validate`, `/webhook` (+ `/refresh` / `/deactivate` if in spec) implemented exactly per T2.1 spec §2/§3/§4.
- [ ] Ed25519 JWT minting uses `jose` v5 (NOT `jsonwebtoken`); claim shape byte-for-byte matches spec §3.
- [ ] Webhook HMAC-SHA256 verified on raw body, constant-time, before parse.
- [ ] All unit tests pass.
- [ ] Worker deployed to `license-staging.quicksay.app`; all five live-smoke checks pass against a real LS test key.
- [ ] Test license key + activation command recorded in README for T2.3 to reuse.
- [ ] Ed25519 **public** key recorded in README handoff section (T2.3 bakes it into the AHK app).
- [ ] No secrets committed; `.gitignore` covers key material + `.dev.vars` + `.wrangler/`.
- [ ] `docs/audit-campaign/MASTER-PLAN.md` Status Tracker updated: T2.2 → ✅, noting "staging only — prod deploy in M.1".
- [ ] Branch `audit/T2.2-cf-worker-license` committed (use `commit-commands:commit`). PR opened against `main`.

### What NOT to do

- ❌ Do not deploy to production (`--env production` / `license.quicksay.app`). That's M.1.
- ❌ Do not use `jsonwebtoken` or any Node-only crypto that doesn't run in Workers. Use `jose` v5 (Web Crypto).
- ❌ Do not commit ANY key material, `.dev.vars`, or the LS API key.
- ❌ Do not put the LemonSqueezy API key anywhere except the Worker secret store, read only in `src/lemonsqueezy.ts`.
- ❌ Do not redesign the endpoint or JWT contracts. They are frozen in the T2.1 spec — if they're wrong, raise it with the user, don't fork them.
- ❌ Do not log the JWT, license key, machine id (unhashed), or any secret.
- ❌ Do not touch the app (`Development/`) or the website. T2.3 builds the app side; it bakes in the public key you publish in the README.
- ❌ Do not skip the LS-outage fallback path — a paying user must not be locked out by an LS API blip (MASTER-PLAN §7).

### Estimated time

Phase 1 (docs + scaffold + contract confirm): 30–45 min. Phase 2 (keypair script): 20 min. Phase 3 (TDD all modules): 2–3 hours. Phase 4 (deploy + live smoke): 45–60 min. Phase 5 (verification): 30 min. **Total wall-clock: ~4–5 hours.**

### When you're done

Report back with:
- The staging URL and the exact `curl` for a successful `/activate` against the test key.
- The decoded JWT claim shape (proving it matches spec §3).
- The Ed25519 public key (so the user can hand it to T2.3 if T2.3 runs in another window).
- Unit test pass summary.
- Any place the T2.1 spec turned out ambiguous or wrong, and how you handled it — flag for the user since T2.3 builds against the same spec.
- Any cross-session dependency to add to MASTER-PLAN (e.g. "M.1 must `wrangler deploy --env production` and re-put secrets for prod; T2.3 must use the public key from this README").
