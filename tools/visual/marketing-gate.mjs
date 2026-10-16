// THE MARKETING ACCEPTANCE GATE.
//
// A screenshot shows what a page looks like. This checks what a screenshot cannot: that the page
// answered at all, that it is in the right language and the right direction, that it has exactly one
// top-level heading and a title for a search engine, that no string fell through to "Translation
// missing", and that nothing on it is wider than the phone it is being read on.
//
//   node tools/visual/marketing-gate.mjs
//
// It needs the dev server running. Every page is visited in both locales at phone, tablet and desktop
// width, and the run exits non-zero listing each problem, so it is usable as a gate rather than a report.

// Playwright is a container tool rather than a project dependency, so it is outside this repository's
// node_modules. ESM `import` ignores NODE_PATH and would not find it; CommonJS resolution does.
import { createRequire } from 'node:module';

const { chromium } = createRequire(import.meta.url)('playwright');

const BASE = 'http://localhost:3000';
const PAGES = ['/', '/features', '/pricing', '/channels', '/solutions', '/integrations', '/about',
  '/contact', '/faq', '/support', '/features/unified-inbox', '/channels/whatsapp',
  '/features/whatsapp-campaigns', '/channels/instagram', '/integrations/salla', '/solutions/ecommerce'];
const LOCALES = { ar: { prefix: '', dir: 'rtl' }, en: { prefix: '/en', dir: 'ltr' } };
// PHONE, TABLET AND DESKTOP. The tablet column is not decoration: at 820px the header's full navigation
// row was shown and did not fit, so every marketing page was 52px wider than its viewport -- a horizontal
// scrollbar on every iPad, invisible to a gate that only looked at 390 and 1440.
const VIEWPORTS = {
  mobile: { width: 390, height: 844 },
  tablet: { width: 820, height: 1180 },
  desktop: { width: 1440, height: 900 },
};

const browser = await chromium.launch();
let checked = 0;
const problems = [];

for (const [vpName, viewport] of Object.entries(VIEWPORTS)) {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  for (const [locale, { prefix, dir }] of Object.entries(LOCALES)) {
    for (const path of PAGES) {
      const url = `${BASE}${(prefix + path).replace(/\/$/, '') || '/'}`;
      const where = `${vpName} ${locale} ${path}`;
      const res = await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
      if (!res || res.status() !== 200) { problems.push(`${where}: HTTP ${res ? res.status() : 'none'}`); continue; }
      const facts = await page.evaluate(() => ({
        dir: document.documentElement.dir,
        lang: document.documentElement.lang,
        h1: document.querySelectorAll('h1').length,
        missing: document.body.innerText.includes('Translation missing'),
        overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        title: document.title.trim().length,
      }));
      if (facts.dir !== dir) problems.push(`${where}: dir=${facts.dir}, expected ${dir}`);
      if (facts.lang !== locale) problems.push(`${where}: lang=${facts.lang}, expected ${locale}`);
      if (facts.h1 !== 1) problems.push(`${where}: ${facts.h1} h1 elements`);
      if (facts.missing) problems.push(`${where}: "Translation missing" on the page`);
      if (facts.overflow > 1) problems.push(`${where}: ${facts.overflow}px wider than the viewport`);
      if (!facts.title) problems.push(`${where}: empty <title>`);
      checked += 1;
    }
  }
  await context.close();
}
await browser.close();
console.log(`checked ${checked} page renders`);
if (problems.length) { problems.forEach(p => console.error(`  ${p}`)); process.exit(1); }
console.log('all clean: 200, correct dir and lang, exactly one h1, a title, no missing translation, no horizontal overflow');
