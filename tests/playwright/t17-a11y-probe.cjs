// T1.7 a11y verification (CommonJS) — settings.html in headless Chromium + axe-core.
const { chromium } = require('playwright-core');
const { readFileSync } = require('fs');
const { pathToFileURL } = require('url');

const HTML = 'C:/QuickSay/Development/gui/settings.html';
const AXE = './node_modules/axe-core/axe.min.js';

let pass = 0, fail = 0;
const ok  = (m) => { console.log('  PASS  ' + m); pass++; };
const bad = (m) => { console.log('  FAIL  ' + m); fail++; };

(async () => {
  const exe = (process.env.LOCALAPPDATA + '/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-win64/chrome-headless-shell.exe');
  const browser = await chromium.launch({ headless: true, executablePath: exe });
  const page = await browser.newPage({ viewport: { width: 900, height: 700 } });
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));

  await page.goto(pathToFileURL(HTML).href, { waitUntil: 'load' });
  await page.waitForTimeout(300);

  console.log('\n=== Fix (a) — structural DOM assertions ===');
  const skip = await page.$('a.skip-to-main[href="#main-content"]');
  skip ? ok('skip-to-main link present, targets #main-content') : bad('skip link missing');
  const mainId = await page.$('#main-content');
  mainId ? ok('<main id="main-content"> present') : bad('#main-content missing');
  const pwBtn = await page.$('button#btnTogglePass');
  pwBtn ? ok('password toggle is a <button>') : bad('password toggle not a button');
  const pwLabel = pwBtn ? await pwBtn.getAttribute('aria-label') : null;
  (pwLabel && /password/i.test(pwLabel)) ? ok(`password toggle aria-label="${pwLabel}"`) : bad('password aria-label missing');
  const apiLive = await page.getAttribute('#apiStatusMessage', 'aria-live');
  apiLive === 'polite' ? ok('#apiStatusMessage aria-live="polite"') : bad(`#apiStatusMessage aria-live=${apiLive}`);
  const hkLive = await page.getAttribute('#hotkeyTestMessage', 'aria-live');
  hkLive === 'polite' ? ok('#hotkeyTestMessage aria-live="polite"') : bad(`#hotkeyTestMessage aria-live=${hkLive}`);
  const legalRows = await page.$$('.legal-link-row[role="button"][tabindex="0"]');
  legalRows.length >= 3 ? ok(`${legalRows.length} legal rows keyboard-operable`) : bad(`only ${legalRows.length} legal rows keyboard-operable`);
  const skipBefore = await page.$eval('a.skip-to-main', el => getComputedStyle(el).top);
  await page.focus('a.skip-to-main');
  await page.waitForTimeout(300); // allow the 0.15s top transition to settle
  const skipAfter = await page.$eval('a.skip-to-main', el => getComputedStyle(el).top);
  (skipAfter === '0px') ? ok(`skip link reveals on focus (${skipBefore} → ${skipAfter})`) : bad(`skip link top after focus = ${skipAfter} (expected 0px)`);

  console.log('\n=== Fix (a) — computed token ===');
  const tertiary = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--text-tertiary').trim());
  tertiary.toLowerCase() === '#8b8b9e' ? ok(`--text-tertiary = ${tertiary}`) : bad(`--text-tertiary = ${tertiary} (expected #8b8b9e)`);

  console.log('\n=== Fix (c) — conflict banner ===');
  const hidden = await page.$eval('#hotkeyConflictBanner', el => getComputedStyle(el).display);
  hidden === 'none' ? ok('conflict banner hidden by default') : bad(`banner display=${hidden}`);
  await page.evaluate(() => {
    const b = document.getElementById('hotkeyConflictBanner');
    b.style.display = 'flex';
    document.getElementById('hotkeyConflictDetail').textContent = 'test';
  });
  const shown = await page.$eval('#hotkeyConflictBanner', el => getComputedStyle(el).display);
  shown === 'flex' ? ok('conflict banner renders when shown') : bad('banner did not render');
  const role = await page.getAttribute('#hotkeyConflictBanner', 'role');
  role === 'alert' ? ok('conflict banner role="alert"') : bad(`banner role=${role}`);

  console.log('\n=== axe-core scan (wcag2a/2aa/21a/21aa) ===');
  const axeSrc = readFileSync(AXE, 'utf8');
  await page.evaluate(axeSrc);
  const results = await page.evaluate(async () => await window.axe.run(document, {
    runOnly: { type: 'tag', values: ['wcag2a','wcag2aa','wcag21a','wcag21aa'] }
  }));
  const sev = { critical:0, serious:0, moderate:0, minor:0 };
  for (const v of results.violations) sev[v.impact] = (sev[v.impact]||0) + v.nodes.length;
  console.log('  Violations by impact:', JSON.stringify(sev));
  for (const v of results.violations)
    console.log(`    [${v.impact}] ${v.id}: ${v.nodes.length} node(s) — ${v.help}`);
  sev.critical === 0 ? ok('axe-core: 0 critical (GATE)') : bad(`axe-core: ${sev.critical} critical`);
  const cc = results.violations.filter(v => v.id === 'color-contrast');
  cc.length === 0 ? ok('axe-core: 0 color-contrast violations') : bad(`axe-core color-contrast: ${cc[0].nodes.length} nodes`);

  if (errors.length) console.log('\n  page errors:', errors.slice(0,5));
  console.log(`\n${pass} passed, ${fail} failed`);
  await browser.close();
  process.exit(fail > 0 ? 1 : 0);
})();
