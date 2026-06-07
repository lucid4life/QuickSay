// KV access + crypto-hash helpers. The ONLY place license keys are turned into their
// sha256 cache key, so raw keys never land in KV (spec §8.4: "a KV dump is not a key dump").

import type { Env, LicenseCacheEntry, TrialBlockEntry } from './types';

const PRICING_COUNTER_KEY = 'pricing:order_count';
const EVT_TTL_SECONDS = 24 * 60 * 60; // dedup window (spec §4.3)

/** Lowercase hex SHA-256 of a UTF-8 string. Used for sub (= sha256(license_key)) and cache keys. */
export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function licenseCacheKey(licenseKeyHashHex: string): string {
  return `lic:${licenseKeyHashHex}`;
}

export async function readLicense(env: Env, licenseKeyHashHex: string): Promise<LicenseCacheEntry | null> {
  return env.LICENSE_CACHE.get<LicenseCacheEntry>(licenseCacheKey(licenseKeyHashHex), 'json');
}

/** Persistent (no TTL) so a terminal disable never silently evicts and resurrects (spec §4.3). */
export async function writeLicense(env: Env, licenseKeyHashHex: string, entry: LicenseCacheEntry): Promise<void> {
  await env.LICENSE_CACHE.put(licenseCacheKey(licenseKeyHashHex), JSON.stringify(entry));
}

// --- Trial blocklist (spec §2.2 / §5.4). TTL ~18 months. ---
const BLOCK_TTL_SECONDS = 18 * 30 * 24 * 60 * 60;

export async function readTrialBlock(env: Env, trialMachineId: string): Promise<TrialBlockEntry | null> {
  return env.TRIAL_BLOCKLIST.get<TrialBlockEntry>(trialMachineId, 'json');
}

export async function writeTrialBlock(env: Env, trialMachineId: string, entry: TrialBlockEntry): Promise<void> {
  await env.TRIAL_BLOCKLIST.put(trialMachineId, JSON.stringify(entry), { expirationTtl: BLOCK_TTL_SECONDS });
}

// --- Webhook event dedup (spec §4.3) ---
export async function eventAlreadyProcessed(env: Env, eventId: string): Promise<boolean> {
  return (await env.LICENSE_CACHE.get(`evt:${eventId}`)) !== null;
}

export async function markEventProcessed(env: Env, eventId: string): Promise<void> {
  await env.LICENSE_CACHE.put(`evt:${eventId}`, '1', { expirationTtl: EVT_TTL_SECONDS });
}

// --- Pricing order counter (spec §2.4 / §4.2 order_created). Maintained idempotently by webhooks. ---
export async function getOrderCount(env: Env): Promise<number> {
  const raw = await env.LICENSE_CACHE.get(PRICING_COUNTER_KEY);
  const n = raw === null ? 0 : Number.parseInt(raw, 10);
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

export async function bumpOrderCount(env: Env): Promise<void> {
  const n = await getOrderCount(env);
  await env.LICENSE_CACHE.put(PRICING_COUNTER_KEY, String(n + 1));
}
