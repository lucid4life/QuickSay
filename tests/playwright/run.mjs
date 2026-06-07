/**
 * QuickSay P0.2 — Playwright/CDP smoke harness for WebView2 UIs
 *
 * Connects to the settings or onboarding WebView2 window via Chrome DevTools
 * Protocol (CDP). Attaches to the existing WebView2 Chromium — no separate
 * browser download required.
 *
 * Usage:
 *   node run.mjs settings     # settings window smoke test
 *   node run.mjs onboarding   # onboarding wizard smoke test
 *
 * Reusable exports (launchUI, connect, screenshot, teardown) are consumed by
 * T1.2 and T1.4 audit sessions — import this file rather than re-implementing.
 */

import { chromium } from 'playwright';
import { spawn } from 'child_process';
import { mkdtempSync, rmSync, existsSync, mkdirSync } from 'fs';
import { tmpdir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

/** Absolute path to Development/ directory */
export const DEV_DIR = join(__dirname, '..', '..');

/** AutoHotkey v2 executable path (per CLAUDE.md "Debugging" section) */
const AHK_EXE = 'C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe';

/** CDP remote-debugging port */
export const DEBUG_PORT = 9222;

/** How long to poll for CDP before giving up */
const BOOT_TIMEOUT_MS = 15_000;

/** Where to write screenshots */
export const ARTIFACTS_DIR = join(__dirname, 'artifacts');

/**
 * Spawn the requested QuickSay UI under AutoHotkey64.exe.
 *
 * Injects WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS so WebView2 opens its CDP
 * endpoint on DEBUG_PORT.  Sets a unique WEBVIEW2_USER_DATA_FOLDER so
 * concurrent test runs don't share state.
 *
 * @param {'settings'|'onboarding'} target
 * @returns {{ child: import('child_process').ChildProcess, userDataFolder: string }}
 */
export function launchUI(target) {
  const userDataFolder = mkdtempSync(join(tmpdir(), 'qs-test-'));

  const env = {
    ...process.env,
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: `--remote-debugging-port=${DEBUG_PORT}`,
    WEBVIEW2_USER_DATA_FOLDER: userDataFolder,
  };

  let scriptFile, extraArgs;
  if (target === 'settings') {
    scriptFile = join(DEV_DIR, 'QuickSay.ahk');
    extraArgs = ['--settings'];
  } else if (target === 'onboarding') {
    scriptFile = join(DEV_DIR, 'onboarding_ui.ahk');
    extraArgs = [];
  } else {
    throw new Error(`Unknown target "${target}". Use "settings" or "onboarding".`);
  }

  const child = spawn(AHK_EXE, [scriptFile, ...extraArgs], {
    env,
    detached: false,
    stdio: 'ignore',
    windowsHide: false,
  });

  child.on('error', (err) => {
    throw new Error(`AHK process failed to start: ${err.message}\nCheck that ${AHK_EXE} exists.`);
  });

  return { child, userDataFolder };
}

/**
 * Poll http://localhost:{port}/json until at least one page is listed or
 * the timeout expires.
 *
 * @param {number} port
 * @param {number} timeoutMs
 * @returns {Promise<object[]>} CDP page list
 */
export async function pollForCDP(port, timeoutMs = BOOT_TIMEOUT_MS) {
  const deadline = Date.now() + timeoutMs;
  let lastErr = null;

  while (Date.now() < deadline) {
    try {
      const res = await fetch(`http://localhost:${port}/json`);
      const pages = await res.json();
      if (Array.isArray(pages) && pages.length > 0) return pages;
    } catch (err) {
      lastErr = err;
    }
    await new Promise(r => setTimeout(r, 500));
  }

  throw new Error(
    `CDP not ready on port ${port} after ${timeoutMs}ms.\n` +
    `Last error: ${lastErr?.message ?? 'none'}\n` +
    `Troubleshooting:\n` +
    `  1. Confirm WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS was set before AHK launched.\n` +
    `  2. If the env-var path fails, see "The one allowed source touch" in P0.2-baseline.md.\n` +
    `  3. Allow up to ${timeoutMs / 1000}s for WebView2 COM init on slow machines.`
  );
}

/**
 * Connect Playwright over CDP to the WebView2 process on the given port.
 *
 * @param {number} port
 * @returns {Promise<{ browser: import('playwright').Browser, page: import('playwright').Page }>}
 */
export async function connect(port = DEBUG_PORT) {
  const browser = await chromium.connectOverCDP(`http://localhost:${port}`);
  const context = browser.contexts()[0];
  if (!context) throw new Error('No browser context found after CDP connect');
  const page = context.pages()[0];
  if (!page) throw new Error('No page found in WebView2 CDP session');
  return { browser, page };
}

/**
 * Take a screenshot and save it to the artifacts directory.
 *
 * @param {import('playwright').Page} page
 * @param {string} name  base filename (without extension)
 * @returns {Promise<string>} absolute path of written PNG
 */
export async function screenshot(page, name) {
  if (!existsSync(ARTIFACTS_DIR)) mkdirSync(ARTIFACTS_DIR, { recursive: true });
  const screenshotPath = join(ARTIFACTS_DIR, `${name}-smoke.png`);
  await page.screenshot({ path: screenshotPath, fullPage: true });
  console.log(`  Screenshot saved: ${screenshotPath}`);
  return screenshotPath;
}

/**
 * Close the CDP connection, kill the AHK child process, and remove the
 * temporary user-data folder.
 *
 * @param {import('playwright').Browser|undefined} browser
 * @param {import('child_process').ChildProcess|undefined} child
 * @param {string|undefined} userDataFolder
 */
export async function teardown(browser, child, userDataFolder) {
  try { await browser?.close(); } catch {}
  try { child?.kill(); } catch {}
  // Brief pause so WebView2 releases its lock on the user-data folder
  await new Promise(r => setTimeout(r, 800));
  try { if (userDataFolder) rmSync(userDataFolder, { recursive: true, force: true }); } catch {}
}

// ---------------------------------------------------------------------------
// Smoke runner
// ---------------------------------------------------------------------------

async function runSmoke(target) {
  console.log(`\n[QuickSay P0.2] Playwright/CDP smoke test — target: ${target}`);

  let child, userDataFolder, browser, page;

  try {
    console.log('  Launching AHK process...');
    ({ child, userDataFolder } = launchUI(target));

    console.log(`  Polling for CDP on port ${DEBUG_PORT} (timeout ${BOOT_TIMEOUT_MS / 1000}s)...`);
    await pollForCDP(DEBUG_PORT, BOOT_TIMEOUT_MS);
    console.log('  CDP endpoint ready.');

    console.log('  Connecting over CDP...');
    ({ browser, page } = await connect(DEBUG_PORT));
    console.log('  Connected. Waiting for DOM...');
    await page.waitForLoadState('domcontentloaded');

    if (target === 'settings') {
      const el = page.locator('h2', { hasText: 'General Settings' }).first();
      await el.waitFor({ state: 'visible', timeout: 8000 });
      const text = await el.textContent();
      if (!text.includes('General Settings')) {
        throw new Error(`Expected "General Settings" heading, got: "${text}"`);
      }
      console.log('  ✓ Assertion: "General Settings" heading present');
    } else if (target === 'onboarding') {
      const el = page.locator('h1', { hasText: 'Welcome to QuickSay' }).first();
      await el.waitFor({ state: 'visible', timeout: 8000 });
      const text = await el.textContent();
      if (!text.includes('Welcome to QuickSay')) {
        throw new Error(`Expected "Welcome to QuickSay" heading, got: "${text}"`);
      }
      console.log('  ✓ Assertion: "Welcome to QuickSay" heading present');
    }

    await screenshot(page, target);
    console.log(`\n  ✅ PASS — ${target} smoke test`);
  } catch (err) {
    if (browser && page) {
      try { await screenshot(page, `${target}-failure`); } catch {}
    }
    console.error(`\n  ❌ FAIL — ${target}: ${err.message}`);
    throw err;
  } finally {
    await teardown(browser, child, userDataFolder);
  }
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

const target = process.argv[2];
if (!target) {
  console.error('Usage: node run.mjs <settings|onboarding>');
  process.exit(1);
}

runSmoke(target).then(() => process.exit(0)).catch(() => process.exit(1));
