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

// Generous, because this runs against a DEVELOPMENT server: Vite builds each dashboard route's chunk the
// first time that route is asked for, and the reports screen pulls the chart library with it. The default
// 30s is a production figure and was timing the first visit out.
const PAGE_TIMEOUT_MS = Number(process.env.CAPTURE_TIMEOUT_MS || 150000);

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
// The conversation list's assignee tabs are the third item in their own list; addressed by position rather
// than by label so the same shot can be taken in Arabic, where the label is not "All".
const ALL_TAB = '.conversations-list-wrap ul > li:nth-child(3) button';

// The conversation header's side-panel toggle, addressed by the icon it carries rather than by its
// `aria-label`, which is translated. Three other buttons on this screen also expose `aria-pressed`
// (the composer's reply/note toggle and its quoted-reply button), so that attribute is not an address.
const SIDEPANEL_OPEN = 'button[aria-pressed="false"]:has(.i-lucide-user-round)?';
const SIDEPANEL_CLOSE = 'button[aria-pressed="true"]:has(.i-lucide-user-round)?';
const CONVERSATION_ACTIONS_OPEN = '.conversation--actions button[aria-expanded="false"] >> nth=0?';

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
      // "Mine" is the default tab and the seed assigns nothing to the signed-in agent, so these two press
      // "All" first; the second then opens the first row to shoot the message timeline and the composer.
      'conversation-list': {
        path: '/app/accounts/1/dashboard',
        click: [ALL_TAB],
      },
      'conversation-open': {
        path: '/app/accounts/1/dashboard',
        click: [ALL_TAB, '.conversations-list div.conversation', SIDEPANEL_CLOSE],
      },
      // The first row is an email thread, whose bubbles are full-width by design; this one opens further down
      // the seeded list to catch an ordinary chat channel, where the bubbles are the capped kind.
      'conversation-chat': {
        path: '/app/accounts/1/dashboard',
        click: [ALL_TAB, '.conversations-list div.conversation >> nth=3', SIDEPANEL_CLOSE],
      },
      // The side panel -- assignee, team, priority, labels, the contact's details -- is CLOSED until an agent
      // opens it: `is_contact_sidebar_open` is absent from a new user's ui_settings and absent is false
      // (components-next/Conversation/SidepanelSwitch.vue:9-12). So the one screen the assignment
      // documentation is about does not exist in a shot of the conversation alone. This opens it through the
      // real control, addressed by its icon rather than its label, so the same line works in Arabic -- and
      // then opens the Conversation Actions accordion, which holds the assignee, the team and the priority
      // and is collapsed too. `.conversation--actions` is also the participants item's class, so the first
      // one is addressed by position; it is first in the panel's default order.
      'conversation-assignment': {
        path: '/app/accounts/1/dashboard',
        click: [
          ALL_TAB,
          '.conversations-list div.conversation',
          SIDEPANEL_OPEN,
          CONVERSATION_ACTIONS_OPEN,
        ],
      },
      contacts: '/app/accounts/1/contacts',
      reports: '/app/accounts/1/reports/overview',
      // `ongoing` and `one_off` redirect to the live-chat and SMS pages; the WhatsApp one has no alias.
      campaigns: '/app/accounts/1/campaigns/ongoing',
      'campaigns-one-off': '/app/accounts/1/campaigns/one_off',
      'campaigns-whatsapp': '/app/accounts/1/campaigns/whatsapp',
      // Creating a campaign and editing a rule are the two screens behind a button, so a shot of the list
      // pages alone says nothing about either. The campaign header holds exactly one button.
      'campaign-create': {
        path: '/app/accounts/1/campaigns/whatsapp',
        click: ['header button'],
      },
      automations: '/app/accounts/1/settings/automation/list',
      'automation-editor': {
        path: '/app/accounts/1/settings/automation/list',
        click: ['[data-test-id="automation-add-button"]'],
      },
      labels: '/app/accounts/1/settings/labels',
      // The contacts list's rows expand in place into an editor. Shooting the list alone would not
      // show it, and "it still exists" is the whole point of capturing it.
      'contact-expanded': {
        path: '/app/accounts/1/contacts',
        // Every card's expand control is a bare chevron, and so is the sidebar's account switcher --
        // which comes first in the document. Excluding it by id is locale-stable; the button's own name is
        // translated, so it is not an address.
        click: [
          'button:not(#sidebar-account-switcher):has(.i-lucide-chevron-down) >> nth=0',
        ],
      },
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
if (!set)
  throw new Error(
    `unknown set: ${setName} (have: ${Object.keys(SETS).join(', ')})`
  );

// The dashboard has no locale in its URL -- it reads the account's, from the database -- so shooting it in
// Arabic means setting that column, running this with `--locale ar`, and setting it back. The marketing site
// does carry a prefix, so there this just narrows the run to one of the set's own locales.
// The dashboard's default appearance is "auto": App.vue reads `prefers-color-scheme` and puts `.dark` on
// the root, which is what the whole `n-*` token set resolves against. Playwright can set that media query,
// so shooting the dark palette needs no setting change and no second account.
const darkMode = args.includes('--dark');

const localeOverride = arg('locale');
if (localeOverride) {
  const prefix = set.locales[localeOverride];
  set.locales = { [localeOverride]: prefix ?? '' };
}

const browser = await chromium.launch();
let captured = 0;
const failures = [];

// The dashboard is a single-page app behind a session, so a set that declares `signIn` signs in through the
// real form once per browser context and reuses the cookie for the rest of its pages.
async function signIn(page, credentials) {
  // The same generous budget as a page: signing in is a navigation into the dashboard bundle, and on a
  // development server that bundle is built on first request -- a 45s budget was timing out on a cold
  // route while Vite was still compiling it.
  await page.goto(`${BASE}/app/login`, {
    waitUntil: 'networkidle',
    timeout: PAGE_TIMEOUT_MS,
  });
  await page.fill('[data-testid="email_input"]', credentials.email);
  await page.fill('[data-testid="password_input"]', credentials.password);
  await page.click('[data-testid="submit_button"]');
  // `commit`, not the default `load`: the dashboard holds open a websocket and a poll, so the load event
  // never fires and waiting for it times out on a page that is already there.
  await page.waitForURL(/\/app\/accounts\//, {
    waitUntil: 'commit',
    timeout: PAGE_TIMEOUT_MS,
  });
}

for (const [viewportName, viewport] of Object.entries(VIEWPORTS)) {
  if (!viewportNames.includes(viewportName)) continue;

  const context = await browser.newContext({
    viewport,
    deviceScaleFactor: viewport.deviceScaleFactor,
    colorScheme: darkMode ? 'dark' : 'light',
  });
  const page = await context.newPage();

  // DEV CHROME MUST NOT BE IN THE EVIDENCE. `rack-mini-profiler` paints a timing badge into the top
  // corner of every development response -- "167.2 ms", "17052.8 ms x32" -- and it was being
  // photographed into committed screenshots that go on the marketing site and into documentation.
  // It does not exist in production. Hidden at the browser rather than switched off in the app, so
  // the capture is of the same page a developer sees and nothing in the application changes.
  await page.addStyleTag({ content: '.profiler-results, #profiler-results { display: none !important; }' })
    .catch(() => {});
  await page.addInitScript(() => {
    const hide = () => {
      const s = document.createElement('style');
      s.textContent = '.profiler-results,#profiler-results{display:none !important}';
      document.documentElement.appendChild(s);
    };
    if (document.documentElement) hide();
    else document.addEventListener('DOMContentLoaded', hide);
  });

  if (set.signIn) await signIn(page, set.signIn);

  for (const [locale, prefix] of Object.entries(set.locales)) {
    for (const [name, suffix] of Object.entries(set.pages)) {
      if (only && name !== only) continue;

      // A page is either a path, or `{ path, click }` where `click` is a list of selectors pressed in
      // order after the page settles -- the conversation list defaults to the "Mine" tab, so a shot of
      // the inbox taken without pressing "All" is a shot of an empty list.
      const { path: suffixPath, click = [] } =
        typeof suffix === 'string' ? { path: suffix } : suffix;

      // `/en` + `/` would be `/en/`, which is a different URL from `/en`.
      const url = `${BASE}${(prefix + suffixPath).replace(/\/$/, '') || '/'}`;
      const file = path.join(
        outDir,
        setName,
        locale,
        viewportName,
        `${name}.png`
      );
      await mkdir(path.dirname(file), { recursive: true });

      // ONE SLOW PAGE MUST NOT COST THE WHOLE RUN. A dev server compiles the dashboard's route chunks on
      // first request, so the first visit to a heavy screen can take minutes, and a throw here used to
      // discard every shot already taken. A page that fails is recorded and the run moves on; the exit
      // status at the end still reports it, so a missing shot cannot pass unnoticed.
      try {
        const response = await page.goto(url, {
          waitUntil: set.signIn ? 'domcontentloaded' : 'networkidle',
          timeout: PAGE_TIMEOUT_MS,
        });
        if (!response || !response.ok()) {
          failures.push(
            `${url} -> ${response ? response.status() : 'no response'}`
          );
          continue;
        }

        // A single-page app paints after its first data fetch, which `networkidle` can precede. The dashboard
        // makes several in sequence -- account, inboxes, then the conversation list -- and a shot taken before
        // the last one lands shows skeletons, which is not what the screen looks like.
        if (set.signIn) {
          await page.waitForTimeout(1000);
          await page
            .waitForFunction(
              () => !document.body.innerText.includes('Loading inboxes'),
              { timeout: 20000 }
            )
            .catch(() => {});
          await page.waitForTimeout(3500);
        }

        // A selector ending in `?` is clicked only if it is there. The side panel and the accordion inside
        // it are TOGGLES whose state is saved to the signed-in user's `ui_settings`, so a plain click is not
        // idempotent: the second run of the same shot closes what the first opened. Addressing the state the
        // control is in -- `aria-pressed="false"`, `aria-expanded="false"` -- and tolerating its absence
        // makes a page's shot the same whatever the run before it left behind.
        for (const selector of click) {
          const optional = selector.endsWith('?');
          const target = optional ? selector.slice(0, -1) : selector;
          try {
            await page.click(target, { timeout: optional ? 4000 : 15000 });
          } catch (error) {
            if (!optional) throw error;
            continue;
          }
          await page.waitForTimeout(2500);
        }

        await page.screenshot({ path: file, fullPage: !set.signIn });
        captured += 1;
        process.stdout.write(`${file}\n`);
      } catch (error) {
        failures.push(`${url} -> ${error.name}: ${error.message.split('\n')[0]}`);
      }
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
