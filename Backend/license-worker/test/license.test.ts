import { describe, it, expect, beforeEach } from 'vitest';
import {
  handleActivate,
  handleValidate,
  handleRefresh,
  handleDeactivate,
  handlePricing,
  __resetKeyCacheForTests,
} from '../src/license';
import { sha256Hex, readLicense, writeLicense } from '../src/kv';
import { verifyJWT, importPublicKeyFromX } from '../src/jwt';
import type { Env, LicenseCacheEntry } from '../src/types';
import { makeTestEnv, fakeLs, MACHINE_A, MACHINE_B, LICENSE_KEY } from './helpers';

beforeEach(() => __resetKeyCacheForTests());

async function activate(env: Env, ls = fakeLs()) {
  const res = await handleActivate(env, { license_key: LICENSE_KEY, machine_id: MACHINE_A }, ls);
  return res;
}

describe('POST /activate', () => {
  it('activates → 200 { jwt, email, exp }, writes active cache, mints a verifiable JWT', async () => {
    const env = await makeTestEnv();
    const res = await activate(env);
    expect(res.status).toBe(200);
    const body = await res.json<any>();
    expect(body.email).toBe('buyer@x.com');
    expect(typeof body.jwt).toBe('string');
    expect(typeof body.exp).toBe('number');

    const sub = await sha256Hex(LICENSE_KEY);
    const entry = await readLicense(env, sub);
    expect(entry?.status).toBe('active');
    expect(entry?.orderId).toBe(1001);
    expect(entry?.instanceId).toBe('inst-1');

    const pub = await importPublicKeyFromX(env.ED25519_PUBLIC_KEY_X);
    const out = await verifyJWT(pub, env.ISSUER, body.jwt);
    expect(out.ok).toBe(true);
    if (out.ok) {
      expect(out.payload.sub).toBe(sub);
      expect(out.payload.machine).toBe(MACHINE_A);
    }
  });

  it('rejects a malformed license key / machine id → 400', async () => {
    const env = await makeTestEnv();
    const r1 = await handleActivate(env, { license_key: 'nope', machine_id: MACHINE_A }, fakeLs());
    expect(r1.status).toBe(400);
    const r2 = await handleActivate(env, { license_key: LICENSE_KEY, machine_id: 'short' }, fakeLs());
    expect(r2.status).toBe(400);
  });

  it('already-activated → 403 already_activated', async () => {
    const env = await makeTestEnv();
    const res = await handleActivate(env, { license_key: LICENSE_KEY, machine_id: MACHINE_A }, fakeLs({ activate: { kind: 'already_activated' } }));
    expect(res.status).toBe(403);
    expect((await res.json<any>()).code).toBe('already_activated');
  });

  it('not-found/disabled → 403 invalid (no key-validity oracle)', async () => {
    const env = await makeTestEnv();
    const res = await handleActivate(env, { license_key: LICENSE_KEY, machine_id: MACHINE_A }, fakeLs({ activate: { kind: 'invalid' } }));
    expect(res.status).toBe(403);
    expect((await res.json<any>()).code).toBe('invalid');
  });

  it('LS down → 503 + Retry-After (never lock out)', async () => {
    const env = await makeTestEnv();
    const res = await handleActivate(env, { license_key: LICENSE_KEY, machine_id: MACHINE_A }, fakeLs({ activate: { kind: 'upstream' } }));
    expect(res.status).toBe(503);
    expect(res.headers.get('Retry-After')).toBe('30');
  });

  it('rate-limits at 10/hr per machine_id → 429 + Retry-After', async () => {
    const env = await makeTestEnv();
    for (let i = 0; i < 10; i++) {
      const ok = await activate(env);
      expect(ok.status).toBe(200);
    }
    const limited = await activate(env);
    expect(limited.status).toBe(429);
    expect(limited.headers.get('Retry-After')).toBe('3600');
  });
});

describe('POST /validate', () => {
  it('valid token → 200 { valid:true, exp }', async () => {
    const env = await makeTestEnv();
    const { jwt } = await (await activate(env)).json<any>();
    const res = await handleValidate(env, { jwt });
    expect(res.status).toBe(200);
    expect((await res.json<any>()).valid).toBe(true);
  });

  it('tampered/garbage token → 403 bad_signature', async () => {
    const env = await makeTestEnv();
    const res = await handleValidate(env, { jwt: 'not.a.jwt' });
    expect(res.status).toBe(403);
    expect((await res.json<any>()).code).toBe('bad_signature');
  });

  it('revoked (cache disabled) → 403 revoked', async () => {
    const env = await makeTestEnv();
    const { jwt } = await (await activate(env)).json<any>();
    const sub = await sha256Hex(LICENSE_KEY);
    const entry = (await readLicense(env, sub))!;
    await writeLicense(env, sub, { ...entry, status: 'disabled', disabledAt: 1 });
    const res = await handleValidate(env, { jwt });
    expect(res.status).toBe(403);
    expect((await res.json<any>()).code).toBe('revoked');
  });
});

describe('POST /refresh', () => {
  it('active cache → 200 re-signed { jwt, exp }', async () => {
    const env = await makeTestEnv();
    const { jwt } = await (await activate(env)).json<any>();
    const res = await handleRefresh(env, { jwt, machine_id: MACHINE_A });
    expect(res.status).toBe(200);
    const body = await res.json<any>();
    expect(typeof body.jwt).toBe('string');
    const pub = await importPublicKeyFromX(env.ED25519_PUBLIC_KEY_X);
    expect((await verifyJWT(pub, env.ISSUER, body.jwt)).ok).toBe(true);
  });

  it('machine mismatch → 403 machine_mismatch', async () => {
    const env = await makeTestEnv();
    const { jwt } = await (await activate(env)).json<any>();
    const res = await handleRefresh(env, { jwt, machine_id: MACHINE_B });
    expect(res.status).toBe(403);
    expect((await res.json<any>()).code).toBe('machine_mismatch');
  });

  it('disabled cache → 403 revoked', async () => {
    const env = await makeTestEnv();
    const { jwt } = await (await activate(env)).json<any>();
    const sub = await sha256Hex(LICENSE_KEY);
    const entry = (await readLicense(env, sub))!;
    await writeLicense(env, sub, { ...entry, status: 'disabled', disabledAt: 1 });
    const res = await handleRefresh(env, { jwt, machine_id: MACHINE_A });
    expect(res.status).toBe(403);
    expect((await res.json<any>()).code).toBe('revoked');
  });

  it('cache miss → 503 (fail-safe, never lock out)', async () => {
    const env = await makeTestEnv();
    const { jwt } = await (await activate(env)).json<any>();
    await env.LICENSE_CACHE.delete(`lic:${await sha256Hex(LICENSE_KEY)}`);
    const res = await handleRefresh(env, { jwt, machine_id: MACHINE_A });
    expect(res.status).toBe(503);
  });

  it('bad signature → 403 bad_signature', async () => {
    const env = await makeTestEnv();
    const res = await handleRefresh(env, { jwt: 'x.y.z', machine_id: MACHINE_A });
    expect(res.status).toBe(403);
    expect((await res.json<any>()).code).toBe('bad_signature');
  });
});

describe('POST /deactivate (local-only, spec gap flagged)', () => {
  it('valid jwt+machine → 200 { deactivated:true } and clears cached instanceId', async () => {
    const env = await makeTestEnv();
    const { jwt } = await (await activate(env)).json<any>();
    const res = await handleDeactivate(env, { jwt, machine_id: MACHINE_A });
    expect(res.status).toBe(200);
    expect((await res.json<any>()).deactivated).toBe(true);
    const entry = await readLicense(env, await sha256Hex(LICENSE_KEY));
    expect(entry?.instanceId).toBeNull();
  });

  it('machine mismatch → 403', async () => {
    const env = await makeTestEnv();
    const { jwt } = await (await activate(env)).json<any>();
    const res = await handleDeactivate(env, { jwt, machine_id: MACHINE_B });
    expect(res.status).toBe(403);
    expect((await res.json<any>()).code).toBe('machine_mismatch');
  });
});

describe('GET /pricing', () => {
  it('launch tier under the limit', async () => {
    const env = await makeTestEnv({ LAUNCH_LIMIT: '500' });
    const body = await (await handlePricing(env)).json<any>();
    expect(body).toMatchObject({ tier: 'launch', price: 39, currency: 'USD', ordersRemaining: 500, financingAvailable: false });
    expect(body.checkoutUrl).toBe('https://example.test/checkout');
  });

  it('regular tier once the order count reaches the limit', async () => {
    const env = await makeTestEnv({ LAUNCH_LIMIT: '3' });
    await env.LICENSE_CACHE.put('pricing:order_count', '3');
    const body = await (await handlePricing(env)).json<any>();
    expect(body).toMatchObject({ tier: 'regular', price: 74, ordersRemaining: null });
  });
});
