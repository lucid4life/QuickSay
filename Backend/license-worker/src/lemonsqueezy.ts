// Thin client for the LemonSqueezy License API. This is the ONLY module that reads
// LEMONSQUEEZY_API_KEY (spec §2 / §8.2). It never logs the key, the license key, or responses.
//
// LS License API: https://docs.lemonsqueezy.com/api/license-api
//   POST /v1/licenses/activate    { license_key, instance_name }
//   POST /v1/licenses/deactivate  { license_key, instance_id }
// Timeout: 10s (spec §2.4) — on timeout/5xx/network the caller maps to 503 upstream_unavailable.

const LS_BASE = 'https://api.lemonsqueezy.com/v1/licenses';
const LS_TIMEOUT_MS = 10_000;

export type ActivateResult =
  | { kind: 'activated'; instanceId: string | null; orderId: number | null; email: string; activationLimit: number }
  | { kind: 'already_activated' }
  | { kind: 'invalid' }
  | { kind: 'upstream' };

export type DeactivateResult = { kind: 'deactivated' } | { kind: 'invalid' } | { kind: 'upstream' };

interface LsClient {
  activate(licenseKey: string, instanceName: string): Promise<ActivateResult>;
  deactivate(licenseKey: string, instanceId: string): Promise<DeactivateResult>;
}

async function lsFetch(apiKey: string, path: string, form: Record<string, string>): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), LS_TIMEOUT_MS);
  try {
    return await fetch(`${LS_BASE}${path}`, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        Authorization: `Bearer ${apiKey}`,
      },
      body: new URLSearchParams(form).toString(),
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

/** Build the real LS client bound to the env's API key. license.ts depends on the LsClient interface
 *  (not this concretely) so unit tests inject a fake without hitting the network. */
export function makeLemonSqueezyClient(apiKey: string): LsClient {
  return {
    async activate(licenseKey, instanceName) {
      let res: Response;
      try {
        res = await lsFetch(apiKey, '/activate', { license_key: licenseKey, instance_name: instanceName });
      } catch {
        return { kind: 'upstream' }; // abort/timeout/network
      }
      if (res.status >= 500) return { kind: 'upstream' };

      let body: any = {};
      try {
        body = await res.json();
      } catch {
        return res.ok ? { kind: 'invalid' } : { kind: 'invalid' };
      }

      if (res.ok && body?.activated === true && body?.license_key?.status === 'active') {
        return {
          kind: 'activated',
          instanceId: body?.instance?.id ?? null,
          orderId: body?.meta?.order_id ?? null,
          email: body?.meta?.customer_email ?? '',
          activationLimit: Number(body?.license_key?.activation_limit ?? 1) || 1,
        };
      }

      // Distinguish "valid key but at activation limit" from "no such / disabled key".
      const errText = String(body?.error ?? '').toLowerCase();
      if (res.status === 400 && /activation limit|already.*activat/.test(errText)) {
        return { kind: 'already_activated' };
      }
      return { kind: 'invalid' };
    },

    async deactivate(licenseKey, instanceId) {
      let res: Response;
      try {
        res = await lsFetch(apiKey, '/deactivate', { license_key: licenseKey, instance_id: instanceId });
      } catch {
        return { kind: 'upstream' };
      }
      if (res.status >= 500) return { kind: 'upstream' };
      let body: any = {};
      try {
        body = await res.json();
      } catch {
        return { kind: 'invalid' };
      }
      if (res.ok && body?.deactivated === true) return { kind: 'deactivated' };
      return { kind: 'invalid' };
    },
  };
}

export type { LsClient };
