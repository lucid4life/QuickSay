# QuickSay license-issuer Worker

Cloudflare Worker that wraps the **LemonSqueezy License API** and mints **offline-verifiable
Ed25519 JWTs**, so the QuickSay app doesn't make a live HTTPS call on every recording. It also
receives LemonSqueezy webhooks to keep a KV cache of license status current (so activations are
fast and revocations propagate).

This is the **T2.2** build of the QuickSay beta→paid campaign. It implements the frozen **T2.1
spec** — `../../docs/audit-campaign/specs/T2-production-systems-design.md` — §2 (endpoints),
§3 (JWT), §4 (webhook), plus the additive `/trial/status` + `/trial/report` (§5.4). The spec is
authoritative; this README is operational.

> **Status: STAGING ONLY.** Production (`license.quicksay.app`) is deferred to M.1/M.3. Do **not**
> run `wrangler deploy --env production` from this session.

---

## Endpoints (spec §2.3)

| Method | Path | Purpose |
|---|---|---|
| POST | `/activate` | `{license_key, machine_id}` → live LS activate → cache + mint JWT → `200 {jwt,email,exp}` |
| POST | `/validate` | `{jwt}` → `200 {valid:true,exp}` / `403 {valid:false,code}` |
| POST | `/refresh` | `{jwt, machine_id}` → re-sign a fresh 14-day token from the cache (survives LS outage) |
| POST | `/deactivate` | `{jwt, machine_id}` → clear our cached instance (device-transfer) — see **Design notes** |
| GET | `/pricing` | `200 {tier,price,currency,ordersRemaining,financingAvailable,checkoutUrl}` |
| GET | `/trial/status?machineId=<32hex>` | `200 {blocked}` — fail-open trial-start gate (§5.4) |
| POST | `/trial/report` | `{trialMachineId}` → `202 {recorded:true}` — populate blocklist on trial expiry |
| POST | `/webhook/lemonsqueezy` | LS webhook — HMAC verify-before-parse, then KV mutation (§4) |
| GET | `/health` | `200 {ok:true}` liveness (operational, not in the spec) |

JWT claim shape (spec §3.1, minted by `src/jwt.ts`):

```json
{ "iss":"license.quicksay.app", "sub":"<sha256(license_key) hex>", "machine":"<32hex>",
  "email":"buyer@x.com", "plan":"lifetime", "iat":<unix>, "exp":<iat+1209600> }
```
Header: `{ "alg":"EdDSA", "typ":"JWT", "kid":"qs-2026" }`. No `nbf`, no `aud`. 14-day `exp`,
60 s clock leeway, 7-day grace handled app-side (spec §3.2).

---

## Source layout

| File | Role |
|---|---|
| `src/index.ts` | Router + CORS + JSON 404. Webhook reads the raw body itself (verify before parse). |
| `src/jwt.ts` | Ed25519 mint/verify with `jose` v5. `algorithms:['EdDSA']` pinned everywhere (no `alg:none`). |
| `src/lemonsqueezy.ts` | LS License API client — the **only** module that reads `LEMONSQUEEZY_API_KEY`. |
| `src/license.ts` | `/activate /validate /refresh /deactivate /pricing` business logic. |
| `src/trial.ts` | `/trial/status` + `/trial/report`. |
| `src/webhook.ts` | LS webhook: HMAC-SHA256 (constant-time, raw body) → dedup → timestamp gate → KV. |
| `src/kv.ts` | KV helpers + `sha256Hex` (license keys are stored only as their hash). |
| `src/ratelimit.ts` | Per-machine_id hourly KV counters (spec §2.5). |
| `scripts/generate-keypair.mjs` | **Rotation/DR only** — QuickSay already has `qs-2026`; do not run for normal setup. |
| `test/*.test.ts` | Vitest unit suite (44 tests). |

---

## Run the tests

```bash
npm install
npm test          # 44 tests: jwt(8) license(18) trial(7) webhook(11)
npm run typecheck # tsc --noEmit, clean
```

> **Test harness note.** The committed suite runs under plain **Vitest (Node)** with an in-memory
> KV fake (`test/helpers.ts`), exercising the **real** `jose` Ed25519 + Web Crypto HMAC. The
> intended in-runtime harness (`@cloudflare/vitest-pool-workers`, in devDependencies) failed to
> initialize on this Windows + Node 24 toolchain (it requires `compatibilityFlags:["nodejs_compat"]`,
> which this Worker doesn't otherwise need, and its test-runner resolution was flaky). The Node suite
> is the working, CI-portable equivalent. To run inside real `workerd`, switch `vitest.config.ts`
> back to `defineWorkersConfig` (add `nodejs_compat`) on a supported toolchain.

---

## Deploy to staging (already done this session — runbook for re-deploys)

```bash
# 1. KV namespaces (already created; ids are in wrangler.toml [env.staging]):
#    LICENSE_CACHE   = f35093ba25e947daa7ded178396958ae
#    TRIAL_BLOCKLIST = fb76e5ba864e44b589d34a8913a4e60e
#    RATE_LIMIT      = 1cf40ca0db5b499094eaa278d3447c5c
#    (to recreate: wrangler kv namespace create LICENSE_CACHE, etc., then paste the id)

# 2. Secrets (NEVER committed):
cat "$USERPROFILE/.quicksay-keys/qs-2026-ed25519-private.pem" | wrangler secret put ED25519_PRIVATE_KEY --env staging
wrangler secret put LEMONSQUEEZY_WEBHOOK_SECRET --env staging   # staging used: qs_staging_webhook_secret_2026
wrangler secret put LEMONSQUEEZY_API_KEY        --env staging   # ⚠ currently a PLACEHOLDER — see below

# 3. Deploy
wrangler deploy --env staging
```

Live URL (staging): **`https://license-staging.quicksay.app`** (custom domain; cert provisioned).
Cloudflare account `64160bcc0d04cc3f0c13c3f32b663bf7`; zone `quicksay.app`.

### ⚠ Before the `/activate` end-to-end works you MUST set a real LS test key

`LEMONSQUEEZY_API_KEY` is currently a **placeholder**, so `/activate` returns `403 invalid`
(LemonSqueezy rejects the placeholder bearer token). To complete the real activation chain:

1. In the LemonSqueezy dashboard (**test mode**), create the QuickSay product + a test license key.
2. `wrangler secret put LEMONSQUEEZY_API_KEY --env staging` with the **test-mode** API key.
3. Set `CHECKOUT_URL` in `wrangler.toml` to the real test-store checkout link and redeploy.
4. Record the **test license key** here for T2.3's end-to-end test:

   ```
   LS test license key:  <FILL IN — e.g. XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX>
   Activation smoke:
   curl -sX POST https://license-staging.quicksay.app/activate \
     -H 'Content-Type: application/json' \
     -d '{"license_key":"<TEST_KEY>","machine_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
   # → 200 { jwt, email, exp }
   ```

> **Test-mode gotcha (skill §2):** LS test keys don't work against the live store and vice-versa.
> Staging uses the **test** key; production (M.3) uses the **live** key — never commit either.

---

## Handoff to T2.3 (the app side)

T2.3 verifies these JWTs offline and bakes in the **public** key. Use exactly:

```
keyId            : qs-2026
raw-32 base64url : UmeruJlXQ1tyEX5fPzixUMjQD__Lm0NqIPSWReHRsw8     ← TRUSTED_KEYS["qs-2026"]
SPKI PEM         : MCowBQYDK2VwAyEAUmeruJlXQ1tyEX5fPzixUMjQD//Lm0NqIPSWReHRsw8=
publicKeySha256  : 761d22dfcc2302fe1364bc36ec76b7aa488c666adc828f0247e866bf80fde09b   ← I-c build-time assert
iss constant     : license.quicksay.app
```

This is the **T2.1-generated `qs-2026` key** (spec §8.1) — T2.2 *uses* it, it does not generate a
new one. T2.3 + T2.5 must agree byte-for-byte on these values.

---

## Design notes / spec deviations (flagged for the user + T2.3)

1. **`/deactivate` is local-only (LS seat NOT actually freed).** The frozen contract is
   `{jwt, machine_id}` — but LS `deactivate-license-key` needs the **raw license key**, which the
   Worker never holds (the JWT carries only `sub = sha256(key)`, spec §3.1/§8.4). So `/deactivate`
   verifies the token + machine, clears **our** cached `instanceId` (so our records permit
   re-activation), and returns the spec's `{deactivated:true}`. **Caveat:** transferring to a 2nd
   machine may hit the LS `activation_limit` until the `order_refunded` webhook (which carries the
   raw key) or support frees the LS-side seat. *User-approved 2026-05-31: "local-only + flag", no
   contract change.* If real device-transfer is needed pre-launch, T2.3 would store the
   DPAPI-encrypted raw key and the `/deactivate` body would gain `license_key` (a spec change).

2. **`/refresh` cache-miss → 503, not a live LS validate.** Spec §2.4 says refresh falls back to a
   live LS `validate-license-key` on cache miss — but that also needs the raw key the JWT doesn't
   carry, so it's structurally unreachable here. We fail **safe** (503, never lock out — MASTER-PLAN
   §7); the happy path is fully cache-driven (the webhook populates `LICENSE_CACHE`), so a miss only
   occurs if an entry never existed. No paying user is locked out.

3. **`financingAvailable` defaults to `false`** (spec §2.4/D13): LS has no native BNPL; PayPal
   pay-later is region/buyer-driven and surfaces at checkout. M.3 verifies; paywall degrades to
   "lifetime access".

4. **Webhook license-key extraction** reads `data.attributes.key` / `.license_key` (and
   `meta.custom_data.license_key` as a fallback). Confirm against the real LS webhook payloads when
   the LS test store is wired (step 2 above) — the dispatch logic is correct, but the exact field
   name should be eyeballed against a real `license_key_created` delivery.

---

## Live smoke results (this session, staging — `license-staging.quicksay.app`)

| Check | Result |
|---|---|
| `GET /health` | `200 {ok:true}` |
| `GET /pricing` | `200 {tier:"launch",price:39,ordersRemaining:500,financingAvailable:false}` |
| `GET /trial/status` | `200 {blocked:false}` |
| `POST /validate` (tampered jwt) | `403 {valid:false,code:"bad_signature"}` |
| `POST /activate` (placeholder LS key) | `403 {error:"invalid",code:"invalid"}` (no key oracle) |
| `POST /webhook` (bad signature) | `401`, empty body |
| `POST /webhook` (valid HMAC, `license_key_created`) | `200 {received:true}`; KV mutated to `status:"active"` |
| `POST /webhook` (redelivery) | `200 {received:true,deduped:true}` |
| `wrangler tail` during the above (6157 lines) | **0** matches for JWT / license key / private key / LS key / webhook secret |

The one check that needs real LS test credentials — the `/activate` → JWT → `/validate` 200 chain —
is documented above for whoever wires the LS test store. (Staging KV was cleaned after the smoke; the
namespaces are empty.)

## Cross-session dependencies (also added to MASTER-PLAN)

- **M.1/M.3:** `wrangler deploy --env production`, re-put the **same** secrets for prod, set the
  production LS webhook URL, fill the prod KV ids in `wrangler.toml`, flip the app's
  `LICENSE_WORKER_URL` to `license.quicksay.app`. Same `qs-2026` key → rc1 needs no rebuild (§8.3).
- **M.1 (I-a, mandatory):** verify the local private key copy in `~/.quicksay-keys/` is deleted and
  exists only in the CF secret store + offline backup before rc1.
- **T2.3:** bake in the public key above; build-time assert its sha256 == `761d22df…fde09b` (I-c).
