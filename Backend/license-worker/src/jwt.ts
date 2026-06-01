// Ed25519 (EdDSA) JWT mint + verify with `jose` v5 (Web Crypto — runs in Workers).
// Token shape is frozen by spec §3.1: claims iss, sub, machine, email, plan, iat, exp; NO nbf, NO aud.
// Header { alg:"EdDSA", typ:"JWT", kid:"qs-2026" }. exp = iat + 14 days.
//
// Security (spec §3.4 / D15): every verify path pins algorithms:['EdDSA'] so a tampered
// `alg` (none / RSA / HMAC confusion) is rejected — we NEVER read the alg from the token.

import { SignJWT, jwtVerify, compactVerify, importPKCS8, importJWK, type KeyLike } from 'jose';

// jose v5 keys are `CryptoKey | KeyLike`. Alias for readable signatures.
export type VerifyKey = CryptoKey | KeyLike;

export const JWT_TTL_SECONDS = 14 * 24 * 60 * 60; // 1209600 (spec §3.1)
export const CLOCK_LEEWAY_SECONDS = 60; // spec §3.2 / D7

export interface MintClaims {
  sub: string; // sha256(license_key) hex
  machine: string; // 32-hex machine id
  email: string;
  plan: string; // "lifetime"
}

export interface MintedToken {
  jwt: string;
  exp: number;
}

export interface VerifiedPayload {
  iss: string;
  sub: string;
  machine: string;
  email: string;
  plan: string;
  iat: number;
  exp: number;
}

export async function importPrivateKey(pkcs8Pem: string): Promise<VerifyKey> {
  return importPKCS8(pkcs8Pem, 'EdDSA');
}

/** Import the raw-32 base64url public key (from the ED25519_PUBLIC_KEY_X var) as an OKP JWK.
 *  `importJWK` is typed to also return `Uint8Array` (for symmetric `oct` keys); an OKP key always
 *  yields a CryptoKey/KeyLike, so the cast is safe. */
export async function importPublicKeyFromX(xBase64Url: string): Promise<VerifyKey> {
  return (await importJWK({ kty: 'OKP', crv: 'Ed25519', x: xBase64Url }, 'EdDSA')) as VerifyKey;
}

export async function mintJWT(
  privateKey: VerifyKey,
  kid: string,
  issuer: string,
  claims: MintClaims,
  nowSeconds: number = Math.floor(Date.now() / 1000),
  ttlSeconds: number = JWT_TTL_SECONDS,
): Promise<MintedToken> {
  const exp = nowSeconds + ttlSeconds;
  const jwt = await new SignJWT({ machine: claims.machine, email: claims.email, plan: claims.plan })
    .setProtectedHeader({ alg: 'EdDSA', typ: 'JWT', kid })
    .setIssuer(issuer)
    .setSubject(claims.sub)
    .setIssuedAt(nowSeconds)
    .setExpirationTime(exp)
    .sign(privateKey);
  return { jwt, exp };
}

export type VerifyOutcome =
  | { ok: true; payload: VerifiedPayload }
  | { ok: false; reason: 'bad_signature' | 'expired' };

/**
 * Full JWT verification for /validate: signature (alg-pinned) + issuer + exp (with leeway).
 * Distinguishes `expired` from `bad_signature` (covers bad sig, alg confusion, iss mismatch).
 */
export async function verifyJWT(
  publicKey: VerifyKey,
  issuer: string,
  token: string,
): Promise<VerifyOutcome> {
  try {
    const { payload } = await jwtVerify(token, publicKey, {
      algorithms: ['EdDSA'],
      issuer,
      clockTolerance: CLOCK_LEEWAY_SECONDS,
    });
    return { ok: true, payload: payload as unknown as VerifiedPayload };
  } catch (err) {
    // Use jose's stable error `code` rather than `instanceof` (robust across module realms/bundling).
    if ((err as { code?: string })?.code === 'ERR_JWT_EXPIRED') return { ok: false, reason: 'expired' };
    return { ok: false, reason: 'bad_signature' };
  }
}

export type SigCheckOutcome =
  | { ok: true; payload: VerifiedPayload }
  | { ok: false; reason: 'bad_signature' };

/**
 * Signature-only verification for /refresh (does NOT reject on exp — an expired-but-in-grace
 * token is exactly what /refresh re-signs). alg is still pinned to EdDSA. iss is checked here.
 */
export async function verifySignatureOnly(
  publicKey: VerifyKey,
  issuer: string,
  token: string,
): Promise<SigCheckOutcome> {
  try {
    const { payload: bytes } = await compactVerify(token, publicKey, { algorithms: ['EdDSA'] });
    const payload = JSON.parse(new TextDecoder().decode(bytes)) as VerifiedPayload;
    if (payload.iss !== issuer) return { ok: false, reason: 'bad_signature' };
    return { ok: true, payload };
  } catch {
    return { ok: false, reason: 'bad_signature' };
  }
}
