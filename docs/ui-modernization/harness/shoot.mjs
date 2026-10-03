// Captures a surface gallery: a screenshot AND a control inventory for every surface, in English and Arabic, at four
// widths. The inventory is the point — a redesign is checked by diffing it, so a control that quietly disappears is
// a failed build rather than something a reviewer has to spot in a picture.
//
// usage: node shoot.mjs <out_dir>
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { extname, join, resolve } from 'node:path';

const OUT = resolve(process.argv[2] || 'docs/ui-modernization/baseline');
const DIST = resolve(import.meta.dirname, 'dist');
const SHOTS = join(OUT, 'screenshots');

const playwright = await import(
  process.env.PLAYWRIGHT_MODULE
    ? `${process.env.PLAYWRIGHT_MODULE.replace(/\/$/, '')}/index.js`
    : 'playwright'
);
const { chromium } = playwright.chromium ? playwright : playwright.default;

const TYPES = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.json': 'application/json',
};

const serve = () =>
  new Promise(done => {
    const server = createServer(async (request, response) => {
      const path = request.url.split('?')[0];
      const file = join(DIST, path === '/' ? 'index.html' : path);
      try {
        const body = await readFile(file);
        response.writeHead(200, { 'Content-Type': TYPES[extname(file)] || 'application/octet-stream' });
        response.end(body);
      } catch {
        response.writeHead(404);
        response.end();
      }
    });
    server.listen(0, '127.0.0.1', () => done(server));
  });

// Runs in the page: every control a person can act on, with the name a screen reader would announce.
const COLLECT = () => {
  const SELECTOR =
    'button, a[href], input:not([type="hidden"]), select, textarea, summary, [role="button"], [role="menuitem"], [role="tab"], [role="switch"], [role="checkbox"], [role="link"]';

  const labelFor = node => {
    if (node.id) {
      const label = document.querySelector(`label[for="${CSS.escape(node.id)}"]`);
      if (label?.innerText?.trim()) return label.innerText.trim();
    }
    const wrapping = node.closest('label');
    if (wrapping?.innerText?.trim()) return wrapping.innerText.trim();
    return '';
  };

  const iconOf = node => {
    const icon = node.matches('[class*="i-lucide-"],[class*="i-ph-"],[class*="i-woot-"]')
      ? node
      : node.querySelector('[class*="i-lucide-"],[class*="i-ph-"],[class*="i-woot-"]');
    if (!icon) return '';
    return (
      [...icon.classList].find(name => name.startsWith('i-lucide-') || name.startsWith('i-ph-') || name.startsWith('i-woot-')) || ''
    );
  };

  const nameOf = node =>
    (
      node.getAttribute('aria-label') ||
      node.getAttribute('title') ||
      labelFor(node) ||
      (node.innerText || '').trim() ||
      node.getAttribute('placeholder') ||
      node.value ||
      ''
    )
      .replace(/\s+/g, ' ')
      .trim();

  const visible = node => {
    const box = node.getBoundingClientRect();
    const style = getComputedStyle(node);
    return box.width > 0 && box.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
  };

  return [...document.querySelectorAll(SELECTOR)].map(node => ({
    tag: node.tagName.toLowerCase(),
    role: node.getAttribute('role') || '',
    testId: node.getAttribute('data-test-id') || '',
    name: nameOf(node),
    icon: iconOf(node),
    type: node.getAttribute('type') || '',
    disabled: node.disabled === true || node.getAttribute('aria-disabled') === 'true',
    visible: visible(node),
    // A control with neither a name nor a tooltip is unusable by a screen reader; the audit counts these.
    unnamed: !nameOf(node) && !node.getAttribute('aria-label') && !node.getAttribute('title'),
  }));
};

const VIEWPORTS = [
  ['390', { width: 390, height: 844 }],
  ['768', { width: 768, height: 1024 }],
  ['1024', { width: 1024, height: 768 }],
  ['1280', { width: 1280, height: 900 }],
];
// Screenshots at every width would be 8 per surface per locale; two widths are the evidence, four are measured.
const SHOOT_AT = new Set(['390', '1280']);

const SURFACES = JSON.parse(process.env.HARNESS_SURFACES || '[]');

await mkdir(SHOTS, { recursive: true });
const server = await serve();
const base = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH, args: ['--no-sandbox'] });

const inventory = {};
const problems = [];

for (const surface of SURFACES) {
  for (const locale of ['en', 'ar']) {
    for (const [widthName, viewport] of VIEWPORTS) {
      // Reduced motion plus a hard freeze: without it an in-flight entry animation lands in the
      // screenshot and two identical runs differ, which makes visual regression useless. This also
      // exercises the product's own `prefers-reduced-motion` path.
      const context = await browser.newContext({ viewport, reducedMotion: 'reduce' });
      await context.addInitScript(() => {
        const style = document.createElement('style');
        style.textContent =
          '*,*::before,*::after{animation-duration:0s!important;animation-delay:0s!important;animation-iteration-count:1!important;transition-duration:0s!important;transition-delay:0s!important;caret-color:transparent!important}';
        document.addEventListener('DOMContentLoaded', () => document.head.append(style));
      });
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', error => errors.push(String(error.message).slice(0, 200)));
      // Vue swallows a failing render into console.error, so a surface can lose a whole section and still
      // raise no page error. Parity depends on seeing those, so they count the same.
      page.on('console', message => {
        if (message.type() !== 'error') return;
        const text = message.text();
        if (text.includes('Failed to load resource')) return;
        errors.push(text.slice(0, 200));
      });

      const query = new URLSearchParams({ surface: surface.slug, locale });
      if (surface.route) query.set('route', surface.route);
      if (surface.state) query.set('state', surface.state);

      await page.goto(`${base}/index.html?${query}`);
      try {
        await page.waitForSelector('body[data-harness-ready]', { timeout: 20000 });
      } catch {
        problems.push(`${surface.slug}/${locale}/${widthName}: never became ready`);
      }
      await page.waitForTimeout(350);

      const controls = await page.evaluate(COLLECT);
      const overflow = await page.evaluate(
        () => document.documentElement.scrollWidth - document.documentElement.clientWidth
      );
      const direction = await page.evaluate(() => getComputedStyle(document.documentElement).direction);

      inventory[`${surface.slug}|${locale}|${widthName}`] = {
        surface: surface.slug,
        locale,
        width: widthName,
        direction,
        overflow,
        errors,
        controls: controls.filter(control => control.visible),
        hidden: controls.filter(control => !control.visible).length,
      };

      if (SHOOT_AT.has(widthName)) {
        await page.screenshot({
          path: join(SHOTS, `${surface.slug}-${locale}-${widthName}.png`),
          fullPage: false,
        });
      }
      await context.close();
    }
  }
}

await browser.close();
server.close();

await writeFile(join(OUT, 'inventory.json'), `${JSON.stringify(inventory, null, 2)}\n`);

const rows = Object.values(inventory);
const unnamed = rows.flatMap(row => row.controls.filter(control => control.unnamed));
const overflowing = rows.filter(row => row.overflow > 1);
const wrongDirection = rows.filter(row => row.direction !== (row.locale === 'ar' ? 'rtl' : 'ltr'));
const withErrors = rows.filter(row => row.errors.length);

console.log(
  `surfaces: ${SURFACES.length}  captures: ${rows.length}  controls: ${rows.reduce((sum, row) => sum + row.controls.length, 0)}`
);
console.log(`unnamed controls: ${unnamed.length}  horizontal overflow: ${overflowing.length}  wrong direction: ${wrongDirection.length}  page errors: ${withErrors.length}`);
overflowing.forEach(row => console.log(`  OVERFLOW ${row.surface} ${row.locale} ${row.width}px → ${row.overflow}px`));
wrongDirection.forEach(row => console.log(`  DIRECTION ${row.surface} ${row.locale} → ${row.direction}`));
withErrors.forEach(row => console.log(`  ERROR ${row.surface} ${row.locale} ${row.width}px → ${row.errors[0]}`));
problems.forEach(problem => console.log(`  ${problem}`));
