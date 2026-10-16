// Acceptance probe for every marketing page, in both locales, at phone and desktop width.
// Checks what a screenshot cannot: the status, the direction, the language, a missing translation,
// a page with no heading or more than one, content wider than the viewport, and -- since the
// documentation link is now resolved per locale -- that no Arabic page links into an English article.
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');

const BASE = 'http://localhost:3000';

// All 48 slugs, which is the whole site: 10 standing pages and the 38 catalogue detail pages.
const PAGES = [
  '/', '/features', '/pricing', '/channels', '/solutions', '/integrations', '/about', '/contact',
  '/faq', '/support',
  '/channels/api-channel', '/channels/email', '/channels/facebook-messenger', '/channels/instagram',
  '/channels/line', '/channels/live-chat', '/channels/sms', '/channels/telegram', '/channels/whatsapp',
  '/features/agent-bots', '/features/ai-assist', '/features/analytics', '/features/api-webhooks',
  '/features/audiences', '/features/auto-assignment', '/features/automation', '/features/campaigns',
  '/features/canned-responses', '/features/commerce', '/features/contact-management', '/features/csat',
  '/features/flow-builder', '/features/security', '/features/support-desk',
  '/features/team-collaboration', '/features/translation', '/features/unified-inbox',
  '/features/whatsapp-campaigns', '/features/whatsapp-templates',
  '/integrations/salla', '/integrations/shopify', '/integrations/slack', '/integrations/woocommerce',
  '/integrations/zid',
  '/solutions/customer-support', '/solutions/ecommerce', '/solutions/sales-enquiries',
  '/solutions/whatsapp-first',
];

const LOCALES = { ar: { prefix: '', dir: 'rtl' }, en: { prefix: '/en', dir: 'ltr' } };
const VIEWPORTS = { mobile: { width: 390, height: 844 }, desktop: { width: 1440, height: 900 } };

const browser = await chromium.launch();
let checked = 0;
const problems = [];
const docsLinks = new Set();

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
        docs: [...document.querySelectorAll('a[href^="/docs/"]')].map(a => a.getAttribute('href')),
      }));
      if (facts.dir !== dir) problems.push(`${where}: dir=${facts.dir}, expected ${dir}`);
      if (facts.lang !== locale) problems.push(`${where}: lang=${facts.lang}, expected ${locale}`);
      if (facts.h1 !== 1) problems.push(`${where}: ${facts.h1} h1 elements`);
      if (facts.missing) problems.push(`${where}: "Translation missing" on the page`);
      if (facts.overflow > 1) problems.push(`${where}: ${facts.overflow}px wider than the viewport`);
      if (!facts.title) problems.push(`${where}: empty <title>`);
      for (const href of facts.docs) {
        docsLinks.add(href);
        const arabicArticle = href.endsWith('-ar');
        if (locale === 'ar' && !arabicArticle) problems.push(`${where}: Arabic page links to the English article ${href}`);
        if (locale === 'en' && arabicArticle) problems.push(`${where}: English page links to the Arabic article ${href}`);
      }
      checked += 1;
    }
  }
  await context.close();
}

// A documentation link that renders is not a documentation link that resolves, so every distinct one is
// checked against the article it names. /docs/:slug answers with a redirect to the portal's own article URL
// on the CONFIGURED BRAND HOST, so following it would leave this machine and probe the live site; the probe
// asks the local server for the article directly instead.
const context = await browser.newContext();
const page = await context.newPage();
for (const href of [...docsLinks].sort()) {
  const slug = href.replace(/^\/docs\//, '');
  const res = await page.goto(`${BASE}/hc/lynomia-docs/articles/${slug}`, { waitUntil: 'domcontentloaded', timeout: 60000 });
  if (!res || res.status() !== 200) problems.push(`docs link ${href}: article HTTP ${res ? res.status() : 'none'}`);
}
await context.close();
await browser.close();

console.log(`checked ${checked} page renders and ${docsLinks.size} distinct documentation links`);
if (problems.length) { problems.forEach(p => console.error(`  ${p}`)); process.exit(1); }
console.log('all clean: 200, correct dir and lang, exactly one h1, a title, no missing translation, no horizontal overflow, every documentation link in the reader\'s language and resolving');
