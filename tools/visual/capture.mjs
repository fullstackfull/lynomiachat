// THE REDESIGN'S CAMERA.
//
// A visual change is only honest if you looked at it, so this takes real screenshots of real pages from a
// real running server -- the same loop before and after a change, at the same URLs and the same widths, so
// the two sets can be put side by side. Nothing here fabricates, stitches or edits an image.
//
//   node tools/visual/capture.mjs --set marketing --out docs/redesign/evidence/before
//   node tools/visual/capture.mjs --set marketing --only home --out /tmp/after
//
// It needs the dev server running (bin/rails s -p 3000 and bin/vite dev). Chromium comes from
// PLAYWRIGHT_BROWSERS_PATH, which this container sets.
import { mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';

// Playwright is a container tool rather than a project dependency, so it is outside this repository's
// node_modules. ESM `import` ignores NODE_PATH and would not find it; CommonJS resolution does.
const { chromium } = createRequire(import.meta.url)('playwright');

const BASE = process.env.CAPTURE_BASE_URL || 'http://localhost:3000';

// Phone, tablet and desktop. The marketing site's own breakpoints are Tailwind's, so these sit either side
// of `sm` (640), `md` (768) and `lg` (1024) rather than on them.
const VIEWPORTS = {
  // Scale factor 1 throughout. A retina shot of a full page is four times the bytes for a review these are
  // read at, and this evidence is committed.
  mobile: { width: 390, height: 844, isMobile: true, deviceScaleFactor: 1 },
  tablet: { width: 820, height: 1180, deviceScaleFactor: 1 },
  desktop: { width: 1440, height: 900, deviceScaleFactor: 1 },
};

// Each page is captured in both locales, because Arabic is the primary market and a layout that only works
// left-to-right is a defect this project exists to fix.
const SETS = {
  marketing: {
    locales: { ar: '', en: '/en' },
    pages: {
      home: '/',
      features: '/features',
      pricing: '/pricing',
      channels: '/channels',
      solutions: '/solutions',
      integrations: '/integrations',
      about: '/about',
      contact: '/contact',
      faq: '/faq',
      support: '/support',
      'feature-detail': '/features/unified-inbox',
      'channel-detail': '/channels/whatsapp',
    },
  },

  // The authenticated dashboard, on LOCAL SEEDED DATA ONLY. Everything in these shots comes from
  // `rails db:seed` and Seeders::AccountSeeder -- there is no customer conversation, address or token in
  // them, and this set must never be pointed at a production host.
  dashboard: {
    signIn: { email: 'john@acme.inc', password: 'Password1!' },
    locales: { en: '' },
    pages: {
      conversations: '/app/accounts/1/dashboard',
      contacts: '/app/accounts/1/contacts',
      reports: '/app/accounts/1/reports/overview',
      campaigns: '/app/accounts/1/campaigns/ongoing',
      'settings-inboxes': '/app/accounts/1/settings/inboxes',
      'settings-labels': '/app/accounts/1/settings/labels',
      'settings-profile': '/app/accounts/1/profile/settings',
    },
  },
};

const args = process.argv.slice(2);
const arg = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};

const setName = arg('set', 'marketing');
const outDir = arg('out', 'docs/redesign/evidence/latest');
const only = arg('only');
const viewportNames = (arg('viewports') || 'mobile,desktop').split(',');

const set = SETS[setName];
if (!set) throw new Error(`unknown set: ${setName} (have: ${Object.keys(SETS).join(', ')})`);

const browser = await chromium.launch();
let captured = 0;
const failures = [];

// The dashboard is a single-page app behind a session, so a set that declares `signIn` signs in through the
// real form once per browser context and reuses the cookie for the rest of its pages.
async function signIn(page, credentials) {
  await page.goto(`${BASE}/app/login`, { waitUntil: 'networkidle', timeout: 45000 });
  await page.fill('[data-testid="email_input"]', credentials.email);
  await page.fill('[data-testid="password_input"]', credentials.password);
  await page.click('[data-testid="submit_button"]');
  // `commit`, not the default `load`: the dashboard holds open a websocket and a poll, so the load event
  // never fires and waiting for it times out on a page that is already there.
  await page.waitForURL(/\/app\/accounts\//, { waitUntil: 'commit', timeout: 45000 });
}

for (const [viewportName, viewport] of Object.entries(VIEWPORTS)) {
  if (!viewportNames.includes(viewportName)) continue;

  const context = await browser.newContext({ viewport, deviceScaleFactor: viewport.deviceScaleFactor });
  const page = await context.newPage();

  if (set.signIn) await signIn(page, set.signIn);

  for (const [locale, prefix] of Object.entries(set.locales)) {
    for (const [name, suffix] of Object.entries(set.pages)) {
      if (only && name !== only) continue;

      // `/en` + `/` would be `/en/`, which is a different URL from `/en`.
      const url = `${BASE}${(prefix + suffix).replace(/\/$/, '') || '/'}`;
      const file = path.join(outDir, setName, locale, viewportName, `${name}.png`);
      await mkdir(path.dirname(file), { recursive: true });

      const response = await page.goto(url, {
        waitUntil: set.signIn ? 'domcontentloaded' : 'networkidle',
        timeout: 45000,
      });
      if (!response || !response.ok()) {
        failures.push(`${url} -> ${response ? response.status() : 'no response'}`);
        continue;
      }

      // A single-page app paints after its first data fetch, which `networkidle` can precede.
      if (set.signIn) await page.waitForTimeout(2500);

      await page.screenshot({ path: file, fullPage: !set.signIn });
      captured += 1;
      process.stdout.write(`${file}\n`);
    }
  }

  await context.close();
}

await browser.close();

console.log(`\ncaptured ${captured} screenshots into ${outDir}`);
if (failures.length) {
  console.error(`\n${failures.length} page(s) did not answer:`);
  failures.forEach(f => console.error(`  ${f}`));
  process.exit(1);
}
