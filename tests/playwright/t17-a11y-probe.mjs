// T1.7 a11y verification — loads settings.html in headless Chromium, runs axe-core,
// and asserts the structural fixes are present in the live DOM.
// Usage: node t17-a11y-probe.mjs
import { chromium } from 'playwright-core';
import { readFileSync } from 'fs';
import { pathToFileURL } from 'url';

const HTML = 'C:/QuickSay/Development/gui/settings.html';
const AXE = './node_modules/axe-core/axe.min.js';

let pass = 0, fail = 0;
const ok   = (m) => { console.log('  PASS  ' + m); pass++; };
const bad  = (m) => { console.log('  FAIL  ' + m); fail++; };

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 900, height: 700 } });

const errors = [];
page.on('pageerror', e => errors.push(e.message));

await page.goto(pathToFileURL(HTML).href, { waitUntil: 'load' });
await page.waitForTimeout(300); // let inline JS run

// ── Structural assertions (Fix a) ────────────────────────────────────────────
console.log('\n=== Fix (a) — structural DOM assertions ===');

const skip = await page.$('a.skip-to-main[href="#main-content"]');
skip ? ok('skip-to-main link present, targets #main-content') : bad('skip link missing');

const mainId = await page.$('#main-content');
mainId ? ok('<main id="main-content"> target present') : bad('#main-content missing');

const pwBtn = await page.$('button#btnTogglePass');
pwBtn ? ok('password toggle is a <button>') : bad('password toggle not a button');
const pwLabel = pwBtn ? await pwBtn.getAttribute('aria-label') : null;
(pwLabel && /password/i.test(pwLabel)) ? ok(`password toggle aria-label="${pwLabel}"`) : bad('password toggle aria-label missing');

const apiLive = await page.getAttribute('#apiStatusMessage', 'aria-live');
apiLive === 'polite' ? ok('#apiStatusMessage aria-live="polite"') : bad(`#apiStatusMessage aria-live=${apiLive}`);
const hkLive = await page.getAttribute('#hotkeyTestMessage', 'aria-live');
hkLive === 'polite' ? ok('#hotkeyTestMessage aria-live="polite"') : bad(`#hotkeyTestMessage aria-live=${hkLive}`);

// Legal rows keyboard-operable
const legalRows = await page.$$('.legal-link-row[role="button"][tabindex="0"]');
legalRows.length >= 3 ? ok(`${legalRows.length} legal rows are keyboard-operable (role=button tabindex=0)`) : bad(`only ${legalRows.length} legal rows keyboard-operable`);

// Skip link should be visually hidden until focused (top negative), then visible on focus
const skipTopBefore = await page.$eval('a.skip-to-main', el => getComputedStyle(el).top);
await page.focus('a.skip-to-main');
const skipTopAfter = await page.$eval('a.skip-to-main', el => getComputedStyle(el).top);
(skipTopBefore !== skipTopAfter) ? ok(`skip link reveals on focus (${skipTopBefore} → ${skipTopAfter})`) : bad('skip link does not reveal on focus');

// ── Computed contrast of the fixed token (Fix a) ─────────────────────────────
console.log('\n=== Fix (a) — computed token value ===');
const tertiary = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--text-tertiary').trim());
tertiary.toLowerCase() === '#8b8b9e' ? ok(`--text-tertiary computed = ${tertiary}`) : bad(`--text-tertiary = ${tertiary} (expected #8b8b9e)`);

// ── Hotkey conflict banner (Fix c surface) ───────────────────────────────────
console.log('\n=== Fix (c) — conflict banner render ===');
const bannerHiddenInitially = await page.$eval('#hotkeyConflictBanner', el => getComputedStyle(el).display);
bannerHiddenInitially === 'none' ? ok('conflict banner hidden by default') : bad(`banner display=${bannerHiddenInitially} (expected none)`);
// Simulate populateForm showing it
await page.evaluate(() => {
  const b = document.getElementById('hotkeyConflictBanner');
  b.style.display = 'flex';
  document.getElementById('hotkeyConflictDetail').textContent = 'Ctrl+Win didn\'t respond — another app may be using it.';
});
const bannerShown = await page.$eval('#hotkeyConflictBanner', el => getComputedStyle(el).display);
bannerShown === 'flex' ? ok('conflict banner renders when shown') : bad('banner did not render');
const bannerRole = await page.getAttribute('#hotkeyConflictBanner', 'role');
bannerRole === 'alert' ? ok('conflict banner role="alert"') : bad(`banner role=${bannerRole}`);

// ── axe-core scan ────────────────────────────────────────────────────────────
console.log('\n=== axe-core scan ===');
const axeSrc = readFileSync(AXE, 'utf8');
await page.evaluate(axeSrc);
const results = await page.evaluate(async () => {
  return await window.axe.run(document, {
    runOnly: { type: 'tag', values: ['wcag2a','wcag2aa','wcag21a','wcag21aa'] }
  });
});

const bySeverity = { critical:0, serious:0, moderate:0, minor:0 };
for (const v of results.violations) {
  bySeverity[v.impact] = (bySeverity[v.impact]||0) + v.nodes.length;
}
console.log('  Violations by impact:', JSON.stringify(bySeverity));
for (const v of results.violations) {
  console.log(`    [${v.impact}] ${v.id}: ${v.nodes.length} node(s) — ${v.help}`);
}
bySeverity.critical === 0 ? ok('axe-core: 0 critical violations (GATE)') : bad(`axe-core: ${bySeverity.critical} critical violations`);

// Contrast-specific check
const contrastViol = results.violations.filter(v => v.id === 'color-contrast');
contrastViol.length === 0 ? ok('axe-core: 0 color-contrast violations') : bad(`axe-core: color-contrast failures: ${contrastViol[0].nodes.length} nodes`);

if (errors.length) console.log('\n  page errors:', errors.slice(0,5));

console.log(`\n${pass} passed, ${fail} failed`);
await browser.close();
process.exit(fail > 0 ? 1 : 0);
