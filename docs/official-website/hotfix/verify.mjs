/**
 * Browser verification for the P0 hotfix page.
 *
 * Run:  node docs/official-website/hotfix/verify.mjs
 *
 * It serves docs/official-website/hotfix/ over http (localStorage is restricted on file://, and the
 * language preference is the single most important thing to prove), loads index.html in Chromium, and
 * asserts the behaviour each audit finding required. Every assertion prints PASS or FAIL and the process
 * exits non-zero on any failure, so this is a gate rather than a demo.
 *
 * Screenshots are written next to this file for the before/after record.
 */
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { dirname, join, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

// playwright ships a CommonJS entry with no ESM export map, so a bare `import` of it fails in this repo.
const { chromium } = createRequire(import.meta.url)('playwright');

const HERE = dirname(fileURLToPath(import.meta.url));
const TYPES = { '.html': 'text/html; charset=utf-8', '.png': 'image/png', '.js': 'text/javascript' };

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
};

const server = createServer(async (req, res) => {
  const path = req.url.split('?')[0];
  const file = path === '/' ? 'index.html' : path.slice(1);
  try {
    const body = await readFile(join(HERE, file));
    res.writeHead(200, { 'Content-Type': TYPES[extname(file)] || 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;

const browser = await chromium.launch();
const errors = [];
const blocked = [];
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
const page = await context.newPage();
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
// Resource-load failures are this harness's own doing: the route handler below aborts the cross-origin
// brand images and Google Fonts so the run needs no network. Real JS exceptions arrive via 'pageerror'.
page.on('console', (m) => {
  if (m.type() !== 'error') return;
  if (/net::ERR_FAILED|Failed to load resource/.test(m.text())) { blocked.push(m.text()); return; }
  errors.push(`console.error: ${m.text()}`);
});

// Block the two cross-origin brand images and Google Fonts so the run does not depend on the network.
await page.route(/^https:\/\/(lynomia\.com|fonts\.(googleapis|gstatic)\.com)\//, (route) => route.abort());

await page.goto(`${base}/index.html`, { waitUntil: 'load' });
await page.waitForTimeout(1500); // give any DOMContentLoaded hook time to act

// ---- F4: the page must stay Arabic ---------------------------------------------------------------------
const lang1 = await page.getAttribute('html', 'lang');
const dir1 = await page.getAttribute('html', 'dir');
check('loads and stays Arabic (no forced flip)', lang1 === 'ar' && dir1 === 'rtl', `lang=${lang1} dir=${dir1}`);
const h1 = (await page.textContent('h1'))?.trim().slice(0, 40);
check('the Arabic H1 is rendered', /[؀-ۿ]/.test(h1 || ''), h1);

await page.screenshot({ path: join(HERE, 'screenshot-ar-desktop.png'), fullPage: false });

// ---- the language switch must still work, and persist --------------------------------------------------
await page.click('#langBtn');
await page.waitForTimeout(400);
const lang2 = await page.getAttribute('html', 'lang');
const dir2 = await page.getAttribute('html', 'dir');
check('the language button switches to English', lang2 === 'en' && dir2 === 'ltr', `lang=${lang2} dir=${dir2}`);
await page.screenshot({ path: join(HERE, 'screenshot-en-desktop.png'), fullPage: false });

// The English dictionary rewrites the DOM on switch, so a claim corrected only in Arabic would come back
// here. This is a real defect that the first build had: the Arabic text was fixed and the EN keys were not.
const enText = await page.evaluate(() => document.body.innerText);
const enForbidden = [
  'Auto-replies 24/7', 'Resolved automatically', 'AI agent learns', 'Free trial', 'no credit card',
  'fewer repetitive tickets', 'faster average reply', 'Every account action is recorded',
  'Full encryption', 'daily backups', 'we reply in minutes', 'AI that answers repetitive',
  'AI-powered auto-replies', '-60%', '99.98',
];
const enPresent = enForbidden.filter((f) => enText.includes(f));
check('the English version restores no corrected claim', enPresent.length === 0, enPresent.join(', ') || 'none');
const enLinks = await page.evaluate(() =>
  [...document.querySelectorAll('a')].map((a) => a.getAttribute('href')).filter((h) => !h || h === '#')
);
check('no dead links in English either', enLinks.length === 0, `${enLinks.length} found`);

await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(1200);
const lang3 = await page.getAttribute('html', 'lang');
check('the English choice survives a reload', lang3 === 'en', `lang=${lang3}`);

await page.evaluate(() => localStorage.clear());
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(1200);
const lang4 = await page.getAttribute('html', 'lang');
check('a visitor with no stored choice gets Arabic', lang4 === 'ar', `lang=${lang4}`);

// ---- F5: no fabricated status values anywhere in the rendered text -------------------------------------
const text = await page.evaluate(() => document.body.innerText);
const forbidden = ['99.98', 'daily 03:00', 'TLS 1.3 + AES-256', 'system status', 'دقيقتين', 'تجربة مجانية'];
const present = forbidden.filter((f) => text.includes(f));
check('no fabricated status or trial claim is rendered', present.length === 0, present.join(', ') || 'none');

// ---- F2/F3: every control resolves somewhere real ------------------------------------------------------
const links = await page.evaluate(() =>
  [...document.querySelectorAll('a')].map((a) => ({ href: a.getAttribute('href'), text: a.innerText.trim().slice(0, 28) }))
);
const dead = links.filter((l) => !l.href || l.href === '#' || l.href === '');
check('no dead links', dead.length === 0, dead.map((d) => d.text).join(' | ') || 'none');
const inlineJs = await page.evaluate(
  () => [...document.querySelectorAll('a[onclick]')].map((a) => a.getAttribute('onclick')).length
);
check('no anchor depends on inline JS to do its job', inlineJs === 0, `${inlineJs} found`);

// ---- the contact card must open and contain working actions -------------------------------------------
await page.click('#fab');
await page.waitForTimeout(500);
const widgetOpen = await page.evaluate(() => document.getElementById('widget').classList.contains('open'));
const widgetLinks = await page.evaluate(() =>
  [...document.querySelectorAll('#widget .w-foot a')].map((a) => a.getAttribute('href'))
);
check('the contact card opens', widgetOpen);
check(
  'the contact card offers a mailto: and the docs',
  widgetLinks.some((h) => h?.startsWith('mailto:')) && widgetLinks.includes('/docs'),
  widgetLinks.join(', ')
);
const noInput = await page.evaluate(() => document.querySelectorAll('#widget input').length === 0);
check('the contact card has no message box that goes nowhere', noInput);

// ---- head tags (F8) ------------------------------------------------------------------------------------
const head = await page.evaluate(() => ({
  description: document.querySelector('meta[name="description"]')?.content?.length || 0,
  canonical: document.querySelector('link[rel="canonical"]')?.href || '',
  og: [...document.querySelectorAll('meta[property^="og:"]')].length,
  icon: document.querySelector('link[rel="icon"]')?.href || '',
}));
check('a meta description is present', head.description > 80, `${head.description} chars`);
check('canonical points at the real home', head.canonical === 'https://chat.lynomia.com/', head.canonical);
check('Open Graph tags are present', head.og >= 5, `${head.og} tags`);
check('a favicon is declared', head.icon.length > 0);

// ---- mobile RTL ----------------------------------------------------------------------------------------
const mobile = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
const mp = await mobile.newPage();
mp.on('pageerror', (e) => errors.push(`mobile pageerror: ${e.message}`));
await mp.route(/^https:\/\/(lynomia\.com|fonts\.(googleapis|gstatic)\.com)\//, (r) => r.abort());
await mp.goto(`${base}/index.html`, { waitUntil: 'load' });
await mp.waitForTimeout(1200);
const overflow = await mp.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
check('no horizontal overflow at 390px', overflow <= 1, `${overflow}px`);
await mp.screenshot({ path: join(HERE, 'screenshot-ar-mobile.png'), fullPage: false });

check('no JavaScript errors in any run', errors.length === 0, errors.slice(0, 3).join(' / ') || 'none');
console.log(`\n(${blocked.length} resource loads were blocked by this harness on purpose: the two cross-origin brand images and Google Fonts.)`);

await browser.close();
server.close();

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
process.exit(failed.length ? 1 : 0);
