#!/usr/bin/env node
// scripts/dev/mint-dev-license.mjs — LOCAL DEVELOPER tool. Mints an Ed25519 (EdDSA)
// license JWT that QuickSay verifies OFFLINE with its bundled qs-2026 public key.
// This is the owner's "free developer key": no LemonSqueezy, no Worker, no purchase.
//
// It signs the exact token shape lib/license.ahk verifies (spec §3.1): header
// {alg:EdDSA,typ:JWT,kid:qs-2026}, claims {iss,sub,machine,email,plan,iat,exp}.
// The signature is over base64url(header)."."base64url(payload) — the app verifies
// over the literal segments it receives, so no JSON canonicalization is required
// (unlike version.json).
//
// Usage:
//   node scripts/dev/mint-dev-license.mjs --machine <32hex> [--email me@x] [--years 10]
// Prints the JWT to stdout (nothing else), so it can be redirected to a file.

import { readFileSync } from 'node:fs';
import { createPrivateKey, createPublicKey, sign } from 'node:crypto';
import { homedir } from 'node:os';
import { join } from 'node:path';

const b64url = (b) =>
  Buffer.from(b).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

const args = process.argv.slice(2);
const opt = (flag, def) => {
  const i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : def;
};

const machine = opt('--machine');
if (!machine || !/^[a-f0-9]{32}$/i.test(machine)) {
  console.error('error: --machine <32 hex chars> is required (run dev-license.ahk machineid)');
  process.exit(1);
}
const email = opt('--email', 'dev@quicksay.app');
const years = Number(opt('--years', '10'));
const keyPath = opt('--key', join(homedir(), '.quicksay-keys', 'qs-2026-ed25519-private.pem'));

// Trust anchor compiled into the app (lib/license.ahk LICENSE_TRUSTED_KEYS["qs-2026"]).
const APP_TRUST = 'UmeruJlXQ1tyEX5fPzixUMjQD__Lm0NqIPSWReHRsw8';
const ISSUER = 'license.quicksay.app';
const KID = 'qs-2026';

const priv = createPrivateKey(readFileSync(keyPath, 'utf8'));

// Fail loudly if this private key isn't the one the app trusts — otherwise the
// minted token would just be silently rejected (LICENSE_REVOKED).
const der = createPublicKey(priv).export({ type: 'spki', format: 'der' });
const derivedPub = b64url(der.subarray(der.length - 32));
if (derivedPub !== APP_TRUST) {
  console.error(`error: private key public half (${derivedPub}) != app trust anchor (${APP_TRUST}).`);
  console.error('The app would reject this JWT. Wrong key file?');
  process.exit(2);
}

const now = Math.floor(Date.now() / 1000);
const exp = now + Math.round(years * 365 * 24 * 60 * 60);
const header = { alg: 'EdDSA', typ: 'JWT', kid: KID };
const payload = {
  iss: ISSUER,
  sub: 'dev-' + machine.slice(0, 12),
  machine,
  email,
  plan: 'developer', // marks an offline dev license — exempts it from the worker /refresh path
  iat: now,
  exp,
};

const signingInput = b64url(JSON.stringify(header)) + '.' + b64url(JSON.stringify(payload));
const sig = sign(null, Buffer.from(signingInput), priv); // Ed25519 → 64-byte signature
const jwt = signingInput + '.' + b64url(sig);

process.stdout.write(jwt);
