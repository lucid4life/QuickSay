// T1.7 — onboarding hotkey-conflict banner + reduced-motion verification (headless Chromium).
const { chromium } = require('playwright-core');
const { pathToFileURL } = require('url');
const exe = process.env.LOCALAPPDATA + '/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-win64/chrome-headless-shell.exe';

let pass = 0, fail = 0;
const ok  = (m) => { console.log('  PASS  ' + m); pass++; };
const bad = (m) => { console.log('  FAIL  ' + m); fail++; };

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: exe });

  // ── Onboarding banner ──────────────────────────────────────────────────────
  const page = await browser.newPage({ viewport: { width: 720, height: 760 } });
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  // Shim the WebView2 bridge BEFORE page scripts run
  await page.addInitScript(() => {
    window.__sent = [];
    window.chrome = { webview: {
      postMessage: (s) => { window.__sent.push(s); },
      addEventListener: (type, fn) => { if (type === 'message') window.__msgHandler = fn; }
    }};
  });
  await page.goto(pathToFileURL('C:/QuickSay/Development/gui/onboarding.html').href, { waitUntil: 'load' });
  await page.waitForTimeout(300);

  console.log('=== onboarding load ===');
  errors.length === 0 ? ok('onboarding.html loaded with no page errors') : bad('page errors: ' + errors.slice(0,3).join(' | '));

  // Banner element exists and is hidden initially
  const exists = await page.$('#hotkeyConflictBannerOB');
  exists ? ok('#hotkeyConflictBannerOB present') : bad('banner element missing');
  const initDisplay = await page.$eval('#hotkeyConflictBannerOB', el => getComputedStyle(el).display);
  initDisplay === 'none' ? ok('banner hidden by default') : bad(`banner display=${initDisplay}`);

  // Navigate to the Done step (index 5) — should fire postToAHK('getHotkeyConflict')
  await page.evaluate(() => showStep(5));
  await page.waitForTimeout(150);
  const sent = await page.evaluate(() => window.__sent.map(s => { try { return JSON.parse(s).action; } catch { return s; } }));
  sent.includes('getHotkeyConflict') ? ok('Done step fires getHotkeyConflict to AHK') : bad('getHotkeyConflict not sent; sent=' + JSON.stringify(sent));

  // Simulate AHK responding with a conflict
  await page.evaluate(() => window.__msgHandler({ data: { action: 'receiveHotkeyConflict', data: { conflict: true, msg: 'Ctrl+Win did not respond — open Settings to change it.' } } }));
  await page.waitForTimeout(100);
  const shown = await page.$eval('#hotkeyConflictBannerOB', el => getComputedStyle(el).display);
  shown === 'flex' ? ok('banner shows when AHK reports conflict=true') : bad(`banner display after conflict=${shown}`);
  const detail = await page.$eval('#hotkeyConflictDetailOB', el => el.textContent);
  (detail && detail.includes('Settings')) ? ok(`detail message populated: "${detail.slice(0,40)}..."`) : bad('detail message not set');

  // Simulate AHK reporting no conflict → banner hides
  await page.evaluate(() => window.__msgHandler({ data: { action: 'receiveHotkeyConflict', data: { conflict: false, msg: '' } } }));
  await page.waitForTimeout(100);
  const hidden2 = await page.$eval('#hotkeyConflictBannerOB', el => getComputedStyle(el).display);
  hidden2 === 'none' ? ok('banner hides when conflict=false') : bad(`banner still ${hidden2} after conflict=false`);
  await page.close();

  // ── prefers-reduced-motion on settings.html ─────────────────────────────────
  console.log('\n=== reduced-motion (settings.html) ===');
  const rm = await browser.newPage({ viewport: { width: 900, height: 700 } });
  await rm.emulateMedia({ reducedMotion: 'reduce' });
  await rm.goto(pathToFileURL('C:/QuickSay/Development/gui/settings.html').href, { waitUntil: 'load' });
  await rm.waitForTimeout(200);
  // .tab-content.active animation should be suppressed under reduced motion
  const anim = await rm.$eval('.tab-content.active', el => getComputedStyle(el).animationName);
  (anim === 'none') ? ok(`tab-content animation suppressed under reduced-motion (animationName=${anim})`) : bad(`animationName=${anim} (expected none)`);
  await rm.close();

  console.log(`\n${pass} passed, ${fail} failed`);
  await browser.close();
  process.exit(fail > 0 ? 1 : 0);
})();
