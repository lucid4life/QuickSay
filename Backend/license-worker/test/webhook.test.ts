import { describe, it, expect } from 'vitest';
import { handleWebhook } from '../src/webhook';
import { sha256Hex, readLicense, getOrderCount } from '../src/kv';
import type { Env } from '../src/types';
import { makeTestEnv, fakeLs, hmacHex, LICENSE_KEY } from './helpers';

const SECRET = 'test_webhook_secret';

function body(eventName: string, dataId: number, attributes: Record<string, unknown>, eventCreated: string | null): string {
  const meta: Record<string, unknown> = { event_name: eventName };
  if (eventCreated !== null) meta.event_created = eventCreated;
  return JSON.stringify({ meta, data: { id: dataId, attributes } });
}

async function signedReq(raw: string, sig?: string): Promise<Request> {
  const headers = new Headers({ 'Content-Type': 'application/json' });
  if (sig !== '') headers.set('X-Signature', sig ?? (await hmacHex(SECRET, raw)));
  return new Request('https://license.quicksay.app/webhook/lemonsqueezy', { method: 'POST', headers, body: raw });
}

async function post(env: Env, raw: string, sig?: string) {
  return handleWebhook(env, await signedReq(raw, sig), fakeLs());
}

describe('POST /webhook/lemonsqueezy — signature (spec §4.1)', () => {
  it('missing signature → 401 with empty body (rejected before parse)', async () => {
    const env = await makeTestEnv();
    const res = await post(env, body('license_key_created', 1, { key: LICENSE_KEY }, '2026-05-31T00:00:00Z'), '');
    expect(res.status).toBe(401);
    expect(await res.text()).toBe('');
  });

  it('bad signature → 401', async () => {
    const env = await makeTestEnv();
    const res = await post(env, body('license_key_created', 1, { key: LICENSE_KEY }, '2026-05-31T00:00:00Z'), 'deadbeef');
    expect(res.status).toBe(401);
  });
});

describe('POST /webhook/lemonsqueezy — events & idempotency (spec §4.2/§4.3)', () => {
  it('license_key_created → 200 + active cache', async () => {
    const env = await makeTestEnv();
    const raw = body('license_key_created', 1, { key: LICENSE_KEY, order_id: 1001, activation_limit: 1, user_email: 'b@x.com' }, '2026-05-31T00:00:00Z');
    const res = await post(env, raw);
    expect(res.status).toBe(200);
    const entry = await readLicense(env, await sha256Hex(LICENSE_KEY));
    expect(entry?.status).toBe('active');
    expect(entry?.orderId).toBe(1001);
    expect(entry?.email).toBe('b@x.com');
  });

  it('redelivery (identical body+sig) → 200 deduped, no double effect', async () => {
    const env = await makeTestEnv();
    const raw = body('order_created', 7, { order_id: 7 }, '2026-05-31T00:00:00Z');
    await post(env, raw);
    const res2 = await post(env, raw);
    expect(res2.status).toBe(200);
    expect((await res2.json<any>()).deduped).toBe(true);
    expect(await getOrderCount(env)).toBe(1); // counter bumped once, not twice
  });

  it('missing event timestamp → 400, KV untouched', async () => {
    const env = await makeTestEnv();
    const raw = body('license_key_created', 1, { key: LICENSE_KEY }, null); // no event_created, no updated_at
    const res = await post(env, raw);
    expect(res.status).toBe(400);
    expect(await readLicense(env, await sha256Hex(LICENSE_KEY))).toBeNull();
  });

  it('malformed JSON after a valid signature → 400', async () => {
    const env = await makeTestEnv();
    const raw = '{not json';
    const res = await post(env, raw);
    expect(res.status).toBe(400);
  });

  it('license_key_deleted → terminal disable', async () => {
    const env = await makeTestEnv();
    await post(env, body('license_key_created', 1, { key: LICENSE_KEY, order_id: 1001 }, '2026-05-31T00:00:00Z'));
    await post(env, body('license_key_deleted', 1, { key: LICENSE_KEY, order_id: 1001 }, '2026-05-31T01:00:00Z'));
    const entry = await readLicense(env, await sha256Hex(LICENSE_KEY));
    expect(entry?.status).toBe('disabled');
    expect(entry?.disabledAt).toBeGreaterThan(0);
  });

  it('a trailing license_key_updated MUST NOT resurrect a disabled key (F4)', async () => {
    const env = await makeTestEnv();
    await post(env, body('license_key_created', 1, { key: LICENSE_KEY, order_id: 1001 }, '2026-05-31T00:00:00Z'));
    await post(env, body('license_key_deleted', 1, { key: LICENSE_KEY, order_id: 1001 }, '2026-05-31T01:00:00Z'));
    await post(env, body('license_key_updated', 1, { key: LICENSE_KEY, order_id: 1001, activation_limit: 5 }, '2026-05-31T02:00:00Z'));
    const entry = await readLicense(env, await sha256Hex(LICENSE_KEY));
    expect(entry?.status).toBe('disabled'); // status sticky
    expect(entry?.activationLimit).toBe(5); // non-status merge still applied
  });

  it('same-order created replay does NOT resurrect; a new orderId re-grants (R1)', async () => {
    const env = await makeTestEnv();
    await post(env, body('license_key_created', 1, { key: LICENSE_KEY, order_id: 1001 }, '2026-05-31T00:00:00Z'));
    await post(env, body('license_key_deleted', 1, { key: LICENSE_KEY, order_id: 1001 }, '2026-05-31T01:00:00Z'));
    // stale created for the SAME order, newer ts → must stay disabled
    await post(env, body('license_key_created', 1, { key: LICENSE_KEY, order_id: 1001 }, '2026-05-31T02:00:00Z'));
    expect((await readLicense(env, await sha256Hex(LICENSE_KEY)))?.status).toBe('disabled');
    // genuinely new purchase (new orderId) → re-grant
    await post(env, body('license_key_created', 2, { key: LICENSE_KEY, order_id: 2002 }, '2026-05-31T03:00:00Z'));
    const entry = await readLicense(env, await sha256Hex(LICENSE_KEY));
    expect(entry?.status).toBe('active');
    expect(entry?.orderId).toBe(2002);
  });

  it('order_refunded disables and calls LS deactivate for the cached instance', async () => {
    const env = await makeTestEnv();
    await post(env, body('license_key_created', 1, { key: LICENSE_KEY, order_id: 1001 }, '2026-05-31T00:00:00Z'));
    // give it a cached instance (as /activate would)
    const sub = await sha256Hex(LICENSE_KEY);
    const e = (await readLicense(env, sub))!;
    await env.LICENSE_CACHE.put(`lic:${sub}`, JSON.stringify({ ...e, instanceId: 'inst-1' }));

    let deactivated = '';
    const req = await signedReq(body('order_refunded', 9, { key: LICENSE_KEY, order_id: 1001 }, '2026-05-31T04:00:00Z'));
    const res = await handleWebhook(env, req, fakeLs({ onDeactivate: (_k, inst) => { deactivated = inst; } }));
    expect(res.status).toBe(200);
    expect(deactivated).toBe('inst-1');
    expect((await readLicense(env, sub))?.status).toBe('disabled');
  });

  it('unknown event → 200 ignored', async () => {
    const env = await makeTestEnv();
    const res = await post(env, body('some_future_event', 1, {}, '2026-05-31T00:00:00Z'));
    expect(res.status).toBe(200);
  });
});
