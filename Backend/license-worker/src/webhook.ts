// LemonSqueezy webhook handler — POST /webhook/lemonsqueezy (spec §4).
//
// Processing order is normative (spec §4.3): (1) HMAC verify on RAW body, constant-time, BEFORE parse
// -> (2) evt:<id> dedup -> (3) mandatory-timestamp gate -> (4) monotonic, status-monotone apply.
//   - Bad/missing signature -> 401, empty body (never parsed).
//   - Missing/unparseable event timestamp -> 400, KV untouched (never defaulted to now or 0).
//   - KV write failure -> 500 (so LS retries). Unknown event -> 200 ignored.

import type { Env, LicenseCacheEntry } from './types';
import type { LsClient } from './lemonsqueezy';
import { json, unauthorizedEmpty } from './responses';
import { sha256Hex, readLicense, writeLicense, eventAlreadyProcessed, markEventProcessed, bumpOrderCount } from './kv';

function hexToBytes(hex: string): Uint8Array | null {
  if (hex.length === 0 || hex.length % 2 !== 0 || /[^0-9a-fA-F]/.test(hex)) return null;
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

/** Constant-time HMAC-SHA256 verification via crypto.subtle.verify (spec §4.1). */
export async function verifyWebhookSignature(secret: string, rawBody: string, signatureHex: string): Promise<boolean> {
  const sigBytes = hexToBytes(signatureHex);
  if (!sigBytes) return false;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  return crypto.subtle.verify('HMAC', key, sigBytes, new TextEncoder().encode(rawBody));
}

/** Parse an LS event timestamp (ISO-8601 string or unix seconds) to unix seconds, or null. */
function parseEventTs(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return Math.floor(value);
  if (typeof value === 'string' && value.length > 0) {
    const ms = Date.parse(value);
    if (!Number.isNaN(ms)) return Math.floor(ms / 1000);
    const n = Number(value);
    if (Number.isFinite(n)) return Math.floor(n);
  }
  return null;
}

/** Best-effort license-key extraction across license-key events and (where present) order events. */
function extractLicenseKey(payload: any): string | null {
  const k =
    payload?.data?.attributes?.key ??
    payload?.data?.attributes?.license_key ??
    payload?.meta?.custom_data?.license_key ??
    null;
  return typeof k === 'string' && k.length > 0 ? k : null;
}

export async function handleWebhook(env: Env, request: Request, ls: LsClient): Promise<Response> {
  const raw = await request.text();
  const sig = request.headers.get('X-Signature');
  if (!sig) return unauthorizedEmpty();
  if (!(await verifyWebhookSignature(env.LEMONSQUEEZY_WEBHOOK_SECRET, raw, sig))) return unauthorizedEmpty();

  let payload: any;
  try {
    payload = JSON.parse(raw);
  } catch {
    return json({ error: 'bad_request' }, 400); // malformed JSON after a valid signature (spec §4.4)
  }

  const eventName: string = payload?.meta?.event_name ?? request.headers.get('X-Event-Name') ?? '';

  // Mandatory event timestamp (spec §4.3) — never defaulted.
  const eventTs = parseEventTs(payload?.meta?.event_created ?? payload?.data?.attributes?.updated_at);
  if (eventTs === null) return json({ error: 'bad_request', code: 'missing_timestamp' }, 400);

  // Dedup BEFORE the monotonic gate (spec §4.3). Stable id over event + entity + ts.
  const eventId = await sha256Hex(`${eventName}:${payload?.data?.id ?? ''}:${eventTs}`);
  if (await eventAlreadyProcessed(env, eventId)) return json({ received: true, deduped: true }, 200);

  try {
    await dispatch(env, eventName, payload, eventTs, ls);
  } catch {
    // KV write (or LS deactivate) failed → 500 so LS retries (spec §4.4). Marker NOT written.
    return json({ error: 'kv_write_failed' }, 500);
  }

  await markEventProcessed(env, eventId);
  return json({ received: true }, 200);
}

async function dispatch(env: Env, eventName: string, payload: any, eventTs: number, ls: LsClient): Promise<void> {
  const attrs = payload?.data?.attributes ?? {};

  switch (eventName) {
    case 'license_key_created': {
      const rawKey = extractLicenseKey(payload);
      if (!rawKey) return; // can't key the cache without the license key; ignore
      const keyHash = await sha256Hex(rawKey);
      const existing = await readLicense(env, keyHash);
      const newOrderId = attrs.order_id ?? null;

      // Status-monotone (spec §4.3): a disabled order is never resurrected by an event for the SAME order;
      // re-grant only via a created carrying a genuinely new orderId.
      if (existing?.status === 'disabled' && existing.orderId === newOrderId) return;
      if (existing && eventTs < existing.updatedAt) return; // stale

      const entry: LicenseCacheEntry = {
        status: 'active',
        email: attrs.user_email ?? attrs.customer_email ?? existing?.email ?? '',
        plan: 'lifetime',
        orderId: newOrderId,
        instanceId: existing?.instanceId ?? null,
        activationLimit: Number(attrs.activation_limit ?? existing?.activationLimit ?? 1) || 1,
        updatedAt: eventTs,
        disabledAt: null,
      };
      await writeLicense(env, keyHash, entry);
      return;
    }

    case 'license_key_updated': {
      const rawKey = extractLicenseKey(payload);
      if (!rawKey) return;
      const keyHash = await sha256Hex(rawKey);
      const existing = await readLicense(env, keyHash);
      if (!existing) return; // updates never create (only created does)
      if (eventTs < existing.updatedAt) return; // stale

      // Merge NON-STATUS fields only (spec §4.2/§4.3 — never resurrect a disabled key).
      const merged: LicenseCacheEntry = {
        ...existing,
        email: attrs.user_email ?? attrs.customer_email ?? existing.email,
        activationLimit: Number(attrs.activation_limit ?? existing.activationLimit) || existing.activationLimit,
        instanceId: existing.instanceId, // instance lifecycle is tracked via /activate + /deactivate
        updatedAt: eventTs,
      };
      await writeLicense(env, keyHash, merged);
      return;
    }

    case 'license_key_deleted': {
      const rawKey = extractLicenseKey(payload);
      if (!rawKey) return;
      await terminalDisable(env, await sha256Hex(rawKey), eventTs);
      return;
    }

    case 'order_refunded': {
      const rawKey = extractLicenseKey(payload);
      if (!rawKey) return; // order payloads may not carry the key; the license_key_* events cover disable
      const keyHash = await sha256Hex(rawKey);
      const existing = await readLicense(env, keyHash);
      await terminalDisable(env, keyHash, eventTs);
      // Free the LS seat for the cached instance, if any (spec §4.2). instanceId null → skip, still 200.
      if (existing?.instanceId) {
        const res = await ls.deactivate(rawKey, existing.instanceId);
        // 'upstream' is non-fatal here: the disable already landed; don't 500/retry forever on LS hiccup.
        void res;
      }
      return;
    }

    case 'order_created': {
      // Log-only + idempotent /pricing counter bump (guarded by the evt dedup, spec §4.2/§4.3).
      await bumpOrderCount(env);
      return;
    }

    case 'subscription_created':
      return; // reserved future tier — no-op
    default:
      return; // unknown event — 200 ignored
  }
}

async function terminalDisable(env: Env, keyHash: string, eventTs: number): Promise<void> {
  const existing = await readLicense(env, keyHash);
  if (existing) {
    if (existing.status === 'disabled') return; // already terminal (idempotent)
    if (eventTs < existing.updatedAt) return; // a strictly-newer state already applied
    await writeLicense(env, keyHash, { ...existing, status: 'disabled', disabledAt: eventTs, updatedAt: eventTs });
  } else {
    // No prior entry — record the disable so a later stale `created` replay can't grant it.
    await writeLicense(env, keyHash, {
      status: 'disabled',
      email: '',
      plan: 'lifetime',
      orderId: null,
      instanceId: null,
      activationLimit: 1,
      updatedAt: eventTs,
      disabledAt: eventTs,
    });
  }
}
