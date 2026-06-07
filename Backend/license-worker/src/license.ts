// Business logic for /activate, /validate, /refresh, /deactivate, /pricing (spec §2.3/§2.4/§3).
// Handlers take a parsed body + an LsClient (injected so tests run without network) and return a Response.

import type { Env } from './types';
import type { LicenseCacheEntry } from './types';
import type { LsClient } from './lemonsqueezy';
import { json, rateLimited, upstreamUnavailable } from './responses';
import { checkRateLimit } from './ratelimit';
import { sha256Hex, readLicense, writeLicense, getOrderCount } from './kv';
import {
  importPrivateKey,
  importPublicKeyFromX,
  mintJWT,
  verifyJWT,
  verifySignatureOnly,
  type VerifyKey,
} from './jwt';

const LICENSE_KEY_RE = /^[A-Za-z0-9]{8}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{12}$/;
const MACHINE_ID_RE = /^[a-f0-9]{32}$/i;

function badRequest(): Response {
  return json({ error: 'bad_request', code: 'invalid_format' }, 400);
}

// Lazily import + memoize the keys per isolate (importing is async; key material doesn't change).
let privateKeyPromise: Promise<VerifyKey> | null = null;
let publicKeyPromise: Promise<VerifyKey> | null = null;

function getPrivateKey(env: Env) {
  if (!privateKeyPromise) privateKeyPromise = importPrivateKey(env.ED25519_PRIVATE_KEY);
  return privateKeyPromise;
}
function getPublicKey(env: Env) {
  if (!publicKeyPromise) publicKeyPromise = importPublicKeyFromX(env.ED25519_PUBLIC_KEY_X);
  return publicKeyPromise;
}

// --- POST /activate ---
export async function handleActivate(env: Env, body: any, ls: LsClient): Promise<Response> {
  const licenseKey = body?.license_key;
  const machineId = body?.machine_id;
  if (typeof licenseKey !== 'string' || typeof machineId !== 'string') return badRequest();
  if (!LICENSE_KEY_RE.test(licenseKey) || !MACHINE_ID_RE.test(machineId)) return badRequest();

  const rl = await checkRateLimit(env, 'activate', machineId);
  if (!rl.allowed) return rateLimited(rl.retryAfter);

  const result = await ls.activate(licenseKey, machineId);
  if (result.kind === 'upstream') return upstreamUnavailable(30);
  if (result.kind === 'already_activated') return json({ error: 'already_activated', code: 'already_activated' }, 403);
  if (result.kind === 'invalid') return json({ error: 'invalid', code: 'invalid' }, 403);

  // Activated → cache (status active) + mint JWT.
  const sub = await sha256Hex(licenseKey);
  const now = Math.floor(Date.now() / 1000);
  const entry: LicenseCacheEntry = {
    status: 'active',
    email: result.email,
    plan: 'lifetime',
    orderId: result.orderId,
    instanceId: result.instanceId,
    activationLimit: result.activationLimit,
    updatedAt: now,
    disabledAt: null,
  };
  await writeLicense(env, sub, entry);

  const key = await getPrivateKey(env);
  const { jwt, exp } = await mintJWT(key, env.JWT_KID, env.ISSUER, {
    sub,
    machine: machineId,
    email: result.email,
    plan: 'lifetime',
  }, now);

  return json({ jwt, email: result.email, exp }, 200);
}

// --- POST /validate --- body { jwt }
export async function handleValidate(env: Env, body: any): Promise<Response> {
  const token = body?.jwt;
  if (typeof token !== 'string' || token.length === 0) return json({ valid: false, code: 'bad_signature' }, 403);

  const pub = await getPublicKey(env);
  const outcome = await verifyJWT(pub, env.ISSUER, token);
  if (!outcome.ok) return json({ valid: false, code: outcome.reason }, 403);

  // Revocation check against the webhook-maintained cache.
  const entry = await readLicense(env, outcome.payload.sub);
  if (entry && entry.status === 'disabled') return json({ valid: false, code: 'revoked' }, 403);

  return json({ valid: true, exp: outcome.payload.exp }, 200);
}

// --- POST /refresh --- body { jwt, machine_id }
export async function handleRefresh(env: Env, body: any): Promise<Response> {
  const token = body?.jwt;
  const machineId = body?.machine_id;
  if (typeof token !== 'string' || typeof machineId !== 'string' || !MACHINE_ID_RE.test(machineId)) {
    return json({ error: 'bad_signature', code: 'bad_signature' }, 403);
  }

  const rl = await checkRateLimit(env, 'refresh', machineId);
  if (!rl.allowed) return rateLimited(rl.retryAfter);

  const pub = await getPublicKey(env);
  const sig = await verifySignatureOnly(pub, env.ISSUER, token); // does NOT reject on exp (grace re-sign)
  if (!sig.ok) return json({ error: 'bad_signature', code: 'bad_signature' }, 403);
  if (sig.payload.machine !== machineId) return json({ error: 'machine_mismatch', code: 'machine_mismatch' }, 403);

  const entry = await readLicense(env, sig.payload.sub);
  if (entry && entry.status === 'disabled') return json({ error: 'revoked', code: 'revoked' }, 403);
  if (!entry) {
    // Cache miss: the Worker can't do a live LS validate (the JWT carries only sub=sha256(key), not the
    // raw key — spec §3.1/§8.4), so we cannot confirm status right now. Fail SAFE: 503, never lock out a
    // legitimate user (MASTER-PLAN §7). The app stays in grace and retries. (Internal deviation from
    // §2.4's "live LS validate" fallback, which is structurally unreachable here; happy path is fully
    // cache-driven, so this only fires if the cache entry never existed — see README "Design notes".)
    return upstreamUnavailable(30);
  }

  // Active → re-sign a fresh 14-day token and keep the cache entry warm.
  const now = Math.floor(Date.now() / 1000);
  await writeLicense(env, sig.payload.sub, { ...entry, updatedAt: now });
  const key = await getPrivateKey(env);
  const { jwt, exp } = await mintJWT(key, env.JWT_KID, env.ISSUER, {
    sub: sig.payload.sub,
    machine: sig.payload.machine,
    email: sig.payload.email,
    plan: sig.payload.plan,
  }, now);
  return json({ jwt, exp }, 200);
}

// --- POST /deactivate --- body { jwt, machine_id }
// LIMITATION (flagged): the LS-side activation seat is NOT actually freed here, because LS
// deactivate-license-key needs the raw license key, which the Worker never holds (spec §3.1/§8.4).
// We verify the token, clear our cached instanceId (so our records permit re-activation), and return
// the spec's {deactivated:true}. Real device-transfer seat free-up runs via the order_refunded webhook
// (which carries the raw key) or support. See README "Design notes" / the T2.2 handoff.
export async function handleDeactivate(env: Env, body: any): Promise<Response> {
  const token = body?.jwt;
  const machineId = body?.machine_id;
  if (typeof token !== 'string' || typeof machineId !== 'string' || !MACHINE_ID_RE.test(machineId)) {
    return json({ error: 'bad_signature', code: 'bad_signature' }, 403);
  }
  const pub = await getPublicKey(env);
  const sig = await verifySignatureOnly(pub, env.ISSUER, token);
  if (!sig.ok) return json({ error: 'bad_signature', code: 'bad_signature' }, 403);
  if (sig.payload.machine !== machineId) return json({ error: 'machine_mismatch', code: 'machine_mismatch' }, 403);

  const entry = await readLicense(env, sig.payload.sub);
  if (entry && entry.instanceId !== null) {
    await writeLicense(env, sig.payload.sub, { ...entry, instanceId: null, updatedAt: Math.floor(Date.now() / 1000) });
  }
  return json({ deactivated: true }, 200);
}

// --- GET /pricing ---
export async function handlePricing(env: Env): Promise<Response> {
  const limit = Number.parseInt(env.LAUNCH_LIMIT ?? '500', 10) || 500;
  const count = await getOrderCount(env);
  const launch = count < limit;
  return json(
    {
      tier: launch ? 'launch' : 'regular',
      price: launch ? 39 : 74,
      currency: 'USD',
      ordersRemaining: launch ? Math.max(0, limit - count) : null,
      // Conservative default: no financing claim unless verified at checkout (spec §2.4 / D13 —
      // PayPal-surfaced pay-later is region/buyer-driven; M.3 verifies, paywall degrades to "lifetime").
      financingAvailable: false,
      checkoutUrl: env.CHECKOUT_URL,
    },
    200,
  );
}

// Test seam: reset the per-isolate key cache (so a test can swap ED25519_PRIVATE_KEY).
export function __resetKeyCacheForTests(): void {
  privateKeyPromise = null;
  publicKeyPromise = null;
}
