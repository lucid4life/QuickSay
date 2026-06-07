#!/usr/bin/env node
// Ed25519 keypair generator — ROTATION / DISASTER-RECOVERY utility ONLY.
//
// IMPORTANT (spec §8.1): QuickSay already has its production keypair `qs-2026`. T2.2 *uses* that key
// (the private PEM lives in ~/.quicksay-keys + the CF secret store; the public key is committed in
// wrangler.toml and baked into the app). DO NOT run this to "make a staging key" — that would fork the
// trust anchor. This script exists only for a forced rotation (compromise) per spec §7.4.
//
// Output: the PRIVATE key (PKCS#8 PEM) — NEVER commit, NEVER log, NEVER paste into chat.
//         the PUBLIC key (SPKI PEM + raw-32 base64url) — safe to commit / bake into the app.
//         the suggested kid = first 8 hex of sha256(raw-32 public key).
//
// Usage:  node scripts/generate-keypair.mjs [--kid qs-2027]
// Then:   wrangler secret put ED25519_PRIVATE_KEY --env staging   (paste the private PEM)
//         update wrangler.toml ED25519_PUBLIC_KEY_X + JWT_KID, and the app's TRUSTED_KEYS map.

import { generateKeyPairSync, createHash } from 'node:crypto';

function b64url(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

const kidArgIdx = process.argv.indexOf('--kid');
const explicitKid = kidArgIdx !== -1 ? process.argv[kidArgIdx + 1] : null;

const { publicKey, privateKey } = generateKeyPairSync('ed25519');

const privatePem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString().trim();
const spkiPem = publicKey.export({ type: 'spki', format: 'pem' }).toString().trim();
const spkiDer = publicKey.export({ type: 'spki', format: 'der' });
const rawPub = spkiDer.subarray(spkiDer.length - 32); // last 32 bytes of the SPKI DER = the raw Ed25519 pubkey
const rawB64Url = b64url(rawPub);
const sha256Hex = createHash('sha256').update(rawPub).digest('hex');
const kid = explicitKid ?? `qs-${sha256Hex.slice(0, 8)}`;

console.log('=== QuickSay Ed25519 keypair (ROTATION/DR) ===\n');
console.log('kid (suggested)        :', kid);
console.log('publicKeySha256        :', sha256Hex);
console.log('public raw-32 base64url :', rawB64Url, '  <- wrangler.toml ED25519_PUBLIC_KEY_X + app TRUSTED_KEYS');
console.log('\n--- PUBLIC KEY (SPKI PEM, safe to commit) ---');
console.log(spkiPem);
console.log('\n--- PRIVATE KEY (PKCS#8 PEM) — DO NOT COMMIT / DO NOT LOG / paste into wrangler secret put only ---');
console.log(privatePem);
console.log('\nNext: wrangler secret put ED25519_PRIVATE_KEY --env staging   (paste the PRIVATE PEM above)');
