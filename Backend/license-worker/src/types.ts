// Shared types for the QuickSay license-issuer Worker.
// Contracts are frozen by the T2.1 spec (specs/T2-production-systems-design.md §2/§3/§4).

export interface Env {
  // --- KV namespaces (wrangler.toml; spec §2.1) ---
  LICENSE_CACHE: KVNamespace; // sha256(license_key) -> LicenseCacheEntry ; also evt:<id> dedup + pricing counter
  TRIAL_BLOCKLIST: KVNamespace; // trialMachineId -> TrialBlockEntry
  RATE_LIMIT: KVNamespace; // rl:<endpoint>:<machineId> -> RateWindow

  // --- Secrets (wrangler secret put; spec §2.1 / §8.2) ---
  ED25519_PRIVATE_KEY: string; // PKCS#8 PEM — signs JWTs (qs-2026)
  LEMONSQUEEZY_API_KEY: string; // server-to-server; ONLY src/lemonsqueezy.ts reads it
  LEMONSQUEEZY_WEBHOOK_SECRET: string; // HMAC-SHA256 webhook verification

  // --- Non-secret vars (wrangler.toml [vars]) ---
  ISSUER: string; // "license.quicksay.app" (spec §3.1, same for staging+prod)
  JWT_KID: string; // "qs-2026"
  ED25519_PUBLIC_KEY_X: string; // raw-32 Ed25519 public key, base64url (verify our own JWTs)
  CHECKOUT_URL: string; // LS checkout link surfaced by GET /pricing
  LAUNCH_LIMIT?: string; // order count at which $39 launch -> $74 regular (default 500)
}

// LICENSE_CACHE[ sha256(license_key) ]  (spec §2.2). Persistent (no TTL) so terminal-disable is sticky.
export interface LicenseCacheEntry {
  status: 'active' | 'disabled';
  email: string;
  plan: string; // "lifetime"
  orderId: number | null;
  instanceId: string | null;
  activationLimit: number;
  updatedAt: number; // unix seconds — the monotonic gate (spec §4.3)
  disabledAt: number | null;
}

// TRIAL_BLOCKLIST[ trialMachineId ]  (spec §2.2)
export interface TrialBlockEntry {
  blockedAt: number;
  reason: string; // "trial_consumed"
  count: number;
}

export interface RateWindow {
  count: number;
  resetAt: number; // unix seconds
}

// Minimal JSON helpers with the exact response envelopes from spec §2.3.
export const JSON_HEADERS = { 'Content-Type': 'application/json' } as const;
