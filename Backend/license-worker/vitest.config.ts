import { defineConfig } from 'vitest/config';

// Committed unit suite runs under plain Vitest (Node) with an in-memory KV fake (test/helpers.ts).
// It exercises the REAL jose Ed25519 + Web Crypto HMAC (Node 18+ globalThis.crypto) and the full
// handler/KV logic — portably, on any OS.
//
// NOTE: @cloudflare/vitest-pool-workers (in devDependencies) is the intended in-workerd harness, but
// version 0.5.46 fails to resolve its test-runner on this Windows + Node 24 toolchain
// ("Cannot find module .../test-runner/index.mjs"). The in-memory-KV suite below is the working,
// CI-portable equivalent; switch to the workers pool on a supported toolchain if you want the
// tests to run inside the real Workers runtime.
export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    environment: 'node',
  },
});
