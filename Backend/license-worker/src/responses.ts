// Response helpers with permissive CORS (the app is a desktop client; spec §2.3 bodies are JSON).

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, X-Signature, X-Event-Name',
  'Access-Control-Max-Age': '86400',
};

export function json(body: unknown, status = 200, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS, ...extraHeaders },
  });
}

export function rateLimited(retryAfter: number): Response {
  return json({ error: 'rate_limited' }, 429, { 'Retry-After': String(retryAfter) });
}

export function upstreamUnavailable(retryAfter = 30): Response {
  return json({ error: 'upstream_unavailable' }, 503, { 'Retry-After': String(retryAfter) });
}

export function corsPreflight(): Response {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

/** Empty-body 401 — used by the webhook for a bad/missing signature (spec §4.1, reject before parse). */
export function unauthorizedEmpty(): Response {
  return new Response(null, { status: 401, headers: CORS_HEADERS });
}
