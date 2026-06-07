import { describe, it, expect } from 'vitest';
import { handleTrialStatus, handleTrialReport } from '../src/trial';
import { makeTestEnv, MACHINE_A } from './helpers';

describe('GET /trial/status', () => {
  it('unknown machine → { blocked:false }', async () => {
    const env = await makeTestEnv();
    const res = await handleTrialStatus(env, MACHINE_A);
    expect(res.status).toBe(200);
    expect((await res.json<any>()).blocked).toBe(false);
  });

  it('blocked after a report → { blocked:true }', async () => {
    const env = await makeTestEnv();
    await handleTrialReport(env, { trialMachineId: MACHINE_A });
    const res = await handleTrialStatus(env, MACHINE_A);
    expect((await res.json<any>()).blocked).toBe(true);
  });

  it('malformed machineId → 400', async () => {
    const env = await makeTestEnv();
    expect((await handleTrialStatus(env, 'nope')).status).toBe(400);
    expect((await handleTrialStatus(env, null)).status).toBe(400);
  });

  it('rate-limits at 5/hr → 429', async () => {
    const env = await makeTestEnv();
    for (let i = 0; i < 5; i++) expect((await handleTrialStatus(env, MACHINE_A)).status).toBe(200);
    expect((await handleTrialStatus(env, MACHINE_A)).status).toBe(429);
  });
});

describe('POST /trial/report', () => {
  it('records → 202 { recorded:true }', async () => {
    const env = await makeTestEnv();
    const res = await handleTrialReport(env, { trialMachineId: MACHINE_A });
    expect(res.status).toBe(202);
    expect((await res.json<any>()).recorded).toBe(true);
  });

  it('malformed → 400', async () => {
    const env = await makeTestEnv();
    expect((await handleTrialReport(env, { trialMachineId: 'x' })).status).toBe(400);
  });

  it('rate-limits at 2/hr → 429 (and never blocks a paid activation — separate path)', async () => {
    const env = await makeTestEnv();
    expect((await handleTrialReport(env, { trialMachineId: MACHINE_A })).status).toBe(202);
    expect((await handleTrialReport(env, { trialMachineId: MACHINE_A })).status).toBe(202);
    expect((await handleTrialReport(env, { trialMachineId: MACHINE_A })).status).toBe(429);
  });
});
