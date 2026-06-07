// Shared test helpers. The committed suite runs under plain Vitest (Node), so we provide an
// in-memory KV fake that implements the small slice of the KVNamespace API the Worker uses.
// jose + crypto.subtle (Ed25519, HMAC) are the REAL implementations (Node 18+ Web Crypto).

import { generateKeyPair, exportPKCS8, exportJWK } from 'jose';
import type { Env } from '../src/types';
import type { LsClient, ActivateResult, DeactivateResult } from '../src/lemonsqueezy';

/** Faithful in-memory stand-in for KVNamespace (get/get-json/put/delete). TTLs are ignored. */
export class MiniKV {
  private store = new Map<string, string>();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  async get(key: string, type?: 'json'): Promise<any> {
    const v = this.store.get(key);
    if (v === undefined) return null;
    return type === 'json' ? JSON.parse(v) : v;
  }
  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
  async delete(key: string): Promise<void> {
    this.store.delete(key);
  }
}

/** Build a test Env with a fresh, self-consistent Ed25519 keypair (private PEM + public X match). */
export async function makeTestEnv(overrides: Partial<Env> = {}): Promise<Env> {
  const { publicKey, privateKey } = await generateKeyPair('EdDSA', { extractable: true });
  const pem = await exportPKCS8(privateKey);
  const jwk = await exportJWK(publicKey);
  return {
    LICENSE_CACHE: new MiniKV() as unknown as KVNamespace,
    TRIAL_BLOCKLIST: new MiniKV() as unknown as KVNamespace,
    RATE_LIMIT: new MiniKV() as unknown as KVNamespace,
    ED25519_PRIVATE_KEY: pem,
    ED25519_PUBLIC_KEY_X: jwk.x as string,
    LEMONSQUEEZY_API_KEY: 'test_ls_api_key',
    LEMONSQUEEZY_WEBHOOK_SECRET: 'test_webhook_secret',
    ISSUER: 'license.quicksay.app',
    JWT_KID: 'qs-2026',
    LAUNCH_LIMIT: '500',
    CHECKOUT_URL: 'https://example.test/checkout',
    ...overrides,
  };
}

/** A fake LsClient so license/webhook tests never touch the network. */
export function fakeLs(opts: {
  activate?: ActivateResult;
  deactivate?: DeactivateResult;
  onDeactivate?: (key: string, instance: string) => void;
} = {}): LsClient {
  return {
    async activate() {
      return opts.activate ?? { kind: 'activated', instanceId: 'inst-1', orderId: 1001, email: 'buyer@x.com', activationLimit: 1 };
    },
    async deactivate(key, instance) {
      opts.onDeactivate?.(key, instance);
      return opts.deactivate ?? { kind: 'deactivated' };
    },
  };
}

export async function hmacHex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body));
  return [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export const MACHINE_A = 'a'.repeat(32);
export const MACHINE_B = 'b'.repeat(32);
export const LICENSE_KEY = 'ABCD1234-EFGH-5678-IJKL-MNOPQRSTUVWX';
