// Trial-reset gate endpoints (spec §2.3 / §5.4 / D17). These gate trial START only — they are
// NEVER consulted for a paid /activate. The client treats any non-200 as fail-open.
//
//   GET  /trial/status?machineId=<32hex>  -> 200 { blocked }            (rate limit 5/hr)
//   POST /trial/report  { trialMachineId } -> 202 { recorded: true }     (rate limit 2/hr)

import type { Env, TrialBlockEntry } from './types';
import { json, rateLimited } from './responses';
import { checkRateLimit } from './ratelimit';
import { readTrialBlock, writeTrialBlock } from './kv';

const MACHINE_ID_RE = /^[a-f0-9]{32}$/i;

export async function handleTrialStatus(env: Env, machineId: string | null): Promise<Response> {
  if (!machineId || !MACHINE_ID_RE.test(machineId)) {
    return json({ error: 'bad_request', code: 'invalid_format' }, 400);
  }
  const rl = await checkRateLimit(env, 'trial-status', machineId);
  if (!rl.allowed) return rateLimited(rl.retryAfter);

  const entry = await readTrialBlock(env, machineId);
  return json({ blocked: entry !== null }, 200);
}

export async function handleTrialReport(env: Env, body: any): Promise<Response> {
  const trialMachineId = body?.trialMachineId;
  if (typeof trialMachineId !== 'string' || !MACHINE_ID_RE.test(trialMachineId)) {
    return json({ error: 'bad_request', code: 'invalid_format' }, 400);
  }
  const rl = await checkRateLimit(env, 'trial-report', trialMachineId);
  if (!rl.allowed) return rateLimited(rl.retryAfter);

  const now = Math.floor(Date.now() / 1000);
  const existing = await readTrialBlock(env, trialMachineId);
  const entry: TrialBlockEntry = {
    blockedAt: existing?.blockedAt ?? now,
    reason: 'trial_consumed',
    count: (existing?.count ?? 0) + 1,
  };
  await writeTrialBlock(env, trialMachineId, entry);
  return json({ recorded: true }, 202);
}
