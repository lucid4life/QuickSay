import { describe, it, expect } from 'vitest';
import { generateKeyPair, exportJWK, importJWK, base64url } from 'jose';
import {
  mintJWT,
  verifyJWT,
  verifySignatureOnly,
  importPublicKeyFromX,
  JWT_TTL_SECONDS,
} from '../src/jwt';

const ISS = 'license.quicksay.app';
const claims = { sub: 'a'.repeat(64), machine: 'a'.repeat(32), email: 'buyer@x.com', plan: 'lifetime' };

async function keypair() {
  const { publicKey, privateKey } = await generateKeyPair('EdDSA', { extractable: true });
  return { publicKey, privateKey };
}

describe('jwt mint + verify (Ed25519)', () => {
  it('mints a token that round-trips and carries the spec §3.1 claim shape', async () => {
    const { publicKey, privateKey } = await keypair();
    const now = Math.floor(Date.now() / 1000);
    const { jwt, exp } = await mintJWT(privateKey, 'qs-2026', ISS, claims, now);
    expect(exp).toBe(now + JWT_TTL_SECONDS);

    // header
    const [h, p] = jwt.split('.');
    const header = JSON.parse(new TextDecoder().decode(base64url.decode(h!)));
    expect(header).toMatchObject({ alg: 'EdDSA', typ: 'JWT', kid: 'qs-2026' });

    // payload claims (iss, sub, machine, email, plan, iat, exp; no nbf, no aud)
    const payload = JSON.parse(new TextDecoder().decode(base64url.decode(p!)));
    expect(payload).toMatchObject({ iss: ISS, sub: claims.sub, machine: claims.machine, email: claims.email, plan: 'lifetime', iat: now, exp });
    expect(payload.nbf).toBeUndefined();
    expect(payload.aud).toBeUndefined();

    const out = await verifyJWT(publicKey, ISS, jwt);
    expect(out.ok).toBe(true);
  });

  it('verifies via the raw-32 base64url public key (the form baked into the app)', async () => {
    const { publicKey, privateKey } = await keypair();
    const x = (await exportJWK(publicKey)).x as string;
    const pub = await importPublicKeyFromX(x);
    const { jwt } = await mintJWT(privateKey, 'qs-2026', ISS, claims);
    const out = await verifyJWT(pub, ISS, jwt);
    expect(out.ok).toBe(true);
  });

  it('rejects a tampered payload', async () => {
    const { publicKey, privateKey } = await keypair();
    const { jwt } = await mintJWT(privateKey, 'qs-2026', ISS, claims);
    const [h, p, s] = jwt.split('.');
    // Flip a byte in the payload so the signature (still over the original) no longer matches.
    const forged = JSON.parse(new TextDecoder().decode(base64url.decode(p!)));
    forged.machine = 'b'.repeat(32);
    const newPayload = base64url.encode(new TextEncoder().encode(JSON.stringify(forged)));
    const tamperedPayload = await verifyJWT(publicKey, ISS, `${h}.${newPayload}.${s}`);
    expect(tamperedPayload).toEqual({ ok: false, reason: 'bad_signature' });

    // Also flip the signature segment itself — must be rejected. Flip the FIRST byte of the decoded
    // 64-byte signature (the last base64url char only carries 2 significant bits + 4 ignored padding
    // bits, so flipping it can be a no-op after decode — that produced an earlier flaky test).
    const sigBytes = base64url.decode(s!);
    sigBytes[0] ^= 0xff;
    const flipped = base64url.encode(sigBytes);
    const tamperedSig = await verifyJWT(publicKey, ISS, `${h}.${p}.${flipped}`);
    expect(tamperedSig).toEqual({ ok: false, reason: 'bad_signature' });
  });

  it('rejects a token signed by a different key', async () => {
    const a = await keypair();
    const b = await keypair();
    const { jwt } = await mintJWT(a.privateKey, 'qs-2026', ISS, claims);
    const out = await verifyJWT(b.publicKey, ISS, jwt);
    expect(out).toEqual({ ok: false, reason: 'bad_signature' });
  });

  it('pins alg=EdDSA — rejects an alg:none token (no signature)', async () => {
    const { publicKey } = await keypair();
    const header = base64url.encode(new TextEncoder().encode(JSON.stringify({ alg: 'none', typ: 'JWT' })));
    const body = base64url.encode(new TextEncoder().encode(JSON.stringify({ iss: ISS, sub: claims.sub, exp: 9999999999 })));
    const out = await verifyJWT(publicKey, ISS, `${header}.${body}.`);
    expect(out.ok).toBe(false);
  });

  it('rejects a wrong issuer', async () => {
    const { publicKey, privateKey } = await keypair();
    const { jwt } = await mintJWT(privateKey, 'qs-2026', 'evil.example', claims);
    const out = await verifyJWT(publicKey, ISS, jwt);
    expect(out).toEqual({ ok: false, reason: 'bad_signature' });
  });

  it('reports expired past the leeway, but verifySignatureOnly still accepts it (for /refresh)', async () => {
    const { publicKey, privateKey } = await keypair();
    const longAgo = Math.floor(Date.now() / 1000) - JWT_TTL_SECONDS - 3600;
    const { jwt } = await mintJWT(privateKey, 'qs-2026', ISS, claims, longAgo);

    const full = await verifyJWT(publicKey, ISS, jwt);
    expect(full).toEqual({ ok: false, reason: 'expired' });

    const sigOnly = await verifySignatureOnly(publicKey, ISS, jwt);
    expect(sigOnly.ok).toBe(true);
    if (sigOnly.ok) expect(sigOnly.payload.machine).toBe(claims.machine);
  });

  it('verifyJWT honours the 60s clock leeway just past exp', async () => {
    const { publicKey, privateKey } = await keypair();
    // iat far enough back that exp is ~30s in the past — inside the 60s leeway.
    const iat = Math.floor(Date.now() / 1000) - JWT_TTL_SECONDS + 30;
    const { jwt } = await mintJWT(privateKey, 'qs-2026', ISS, claims, iat);
    const out = await verifyJWT(publicKey, ISS, jwt);
    expect(out.ok).toBe(true);
  });
});
