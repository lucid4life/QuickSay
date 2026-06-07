// Router for the QuickSay license-issuer Worker. Dispatches the eight endpoints from spec §2.3:
//   POST /activate  /validate  /refresh  /deactivate  /trial/report  /webhook/lemonsqueezy
//   GET  /pricing   /trial/status   /health
// CORS preflight + JSON 404 fallback. No stack traces ever leak to clients.

import type { Env } from './types';
import { json, corsPreflight } from './responses';
import { makeLemonSqueezyClient } from './lemonsqueezy';
import {
  handleActivate,
  handleValidate,
  handleRefresh,
  handleDeactivate,
  handlePricing,
} from './license';
import { handleTrialStatus, handleTrialReport } from './trial';
import { handleWebhook } from './webhook';

async function parseJsonBody(request: Request): Promise<{ ok: true; body: any } | { ok: false }> {
  try {
    return { ok: true, body: await request.json() };
  } catch {
    return { ok: false };
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === 'OPTIONS') return corsPreflight();

    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';
    const method = request.method;
    const ls = makeLemonSqueezyClient(env.LEMONSQUEEZY_API_KEY);

    try {
      // --- GET ---
      if (method === 'GET') {
        if (path === '/health') return json({ ok: true, service: 'quicksay-license-worker' }, 200);
        if (path === '/pricing') return handlePricing(env);
        if (path === '/trial/status') return handleTrialStatus(env, url.searchParams.get('machineId'));
        return json({ error: 'not_found' }, 404);
      }

      // --- POST ---
      if (method === 'POST') {
        // Webhook reads the RAW body itself (HMAC verify before parse) — do NOT pre-parse it.
        if (path === '/webhook/lemonsqueezy') return await handleWebhook(env, request, ls);

        const parsed = await parseJsonBody(request);
        if (!parsed.ok) return json({ error: 'bad_request', code: 'invalid_format' }, 400);

        switch (path) {
          case '/activate':
            return await handleActivate(env, parsed.body, ls);
          case '/validate':
            return await handleValidate(env, parsed.body);
          case '/refresh':
            return await handleRefresh(env, parsed.body);
          case '/deactivate':
            return await handleDeactivate(env, parsed.body);
          case '/trial/report':
            return await handleTrialReport(env, parsed.body);
          default:
            return json({ error: 'not_found' }, 404);
        }
      }

      return json({ error: 'method_not_allowed' }, 405);
    } catch {
      // Never leak internals. (Per-handler paths already map known failures to 4xx/5xx.)
      return json({ error: 'internal_error' }, 500);
    }
  },
};
