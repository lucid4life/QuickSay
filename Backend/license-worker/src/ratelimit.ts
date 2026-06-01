// Per-machine_id fixed-window rate limiting via KV counters (spec §2.5).
//
// Why KV and not the native CF rate-limiting binding: the native [[unsafe.bindings]] ratelimit
// binding only supports 10s/60s windows, but the spec requires PER-HOUR limits. So a KV counter
// is the correct tool here (and the spec's documented mechanism — RATE_LIMIT namespace,
// key `rl:<endpoint>:<machineId>`, 3600s TTL). Per-IP limits are layered on top via Cloudflare
// WAF rate rules configured in the dashboard (spec §2.5) — out of band of this code.
//
// KV is eventually consistent, so the cap is approximate under a burst — acceptable per spec.

import type { Env, RateWindow } from './types';

const WINDOW_SECONDS = 3600;

// Per-endpoint hourly caps (spec §2.5).
export const RATE_LIMITS: Record<string, number> = {
  activate: 10,
  refresh: 5,
  'trial-status': 5,
  'trial-report': 2,
};

export interface RateResult {
  allowed: boolean;
  retryAfter: number; // seconds
}

/**
 * Increment and check the hourly counter for (endpoint, machineId).
 * Returns allowed=false with a Retry-After when the cap is exceeded.
 */
export async function checkRateLimit(env: Env, endpoint: string, machineId: string): Promise<RateResult> {
  const limit = RATE_LIMITS[endpoint];
  if (limit === undefined) return { allowed: true, retryAfter: 0 };

  const key = `rl:${endpoint}:${machineId}`;
  const now = Math.floor(Date.now() / 1000);
  const win = await env.RATE_LIMIT.get<RateWindow>(key, 'json');

  if (!win || now >= win.resetAt) {
    // Start a fresh window.
    await env.RATE_LIMIT.put(key, JSON.stringify({ count: 1, resetAt: now + WINDOW_SECONDS }), {
      expirationTtl: WINDOW_SECONDS,
    });
    return { allowed: true, retryAfter: 0 };
  }

  if (win.count >= limit) {
    return { allowed: false, retryAfter: Math.max(1, win.resetAt - now) };
  }

  // Preserve the original window expiry (don't slide it forward on each hit).
  await env.RATE_LIMIT.put(key, JSON.stringify({ count: win.count + 1, resetAt: win.resetAt }), {
    expirationTtl: Math.max(1, win.resetAt - now),
  });
  return { allowed: true, retryAfter: 0 };
}
