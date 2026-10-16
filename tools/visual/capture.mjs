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
import { mkdir, writeFile } from 'node:fs/promises';
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

// THE SAME TOGGLE, READ RATHER THAN PRESSED. A shot whose whole subject is a panel being shut must not be
// allowed to come out with the panel open: `docs/screenshots/sources/marketing/en/conversation-open.png`
// was byte-identical to `conversation-assignment.png` -- the same screen, published on the homepage under a
// caption describing a different one -- because the optional close silently did nothing and nothing
// afterwards looked. These are `expect` selectors: present after the clicks, or the shot fails.
const SIDEPANEL_IS_CLOSED = 'button[aria-pressed="false"]:has(.i-lucide-user-round)';
const SIDEPANEL_IS_OPEN = 'button[aria-pressed="true"]:has(.i-lucide-user-round)';

// A CONVERSATION ON A NAMED CHANNEL, rather than whichever one happens to be at the top of the list.
// Inbox names are DATA, not translation: `rails db:seed` calls them "PaperLayer Line", "PaperLayer Website"
// and so on in every locale, so a card can be addressed by the channel it came in on and the same line works
// in Arabic. It fixes a real defect in the shot that used `nth=0`: the top of this seeded list is a Facebook
// thread, which carries the "you cannot reply due to 24 hour message window restriction" banner and a
// composer locked to Private Note. That is a true screen and a terrible hero.
//
// It is NOT enough on its own to find one particular conversation -- see `widget-arrival` below, which
// needs a specific one and addresses it by id.
const conversationOn = inbox =>
  `.conversations-list div.conversation:has-text("${inbox}") >> nth=0`;

// The composer's reply/note switch. Selecting the mode it is already in is a no-op in the component
// (EditorModeToggle.vue `select`), so this is safe to press on every run; without it the composer keeps
// whatever the last run left in `ui_settings` and the shot comes out amber, in Private Note, with the
// placeholder "this will be visible only to Agents" across the box.
const REPLY_MODE = '[role="group"]:has(button[aria-pressed]) button >> nth=0';
const REPLY_MODE_IS_ON = '[role="group"] button[aria-pressed="true"]:nth-child(1)';

// The seeded website channel, which the documentation's website-chat tutorial is written about. An id
// rather than a lookup because this set is a list of URLs; `rails db:seed` creates the inboxes in a fixed
// order and this one is the web widget (`Seeders::AccountSeeder`).
const WEBSITE_INBOX = 2;

// The widget preview beside the website inbox's settings. Addressed by the one class that is its own --
// a 45rem floor nothing else on the page sets -- because its tabs ("Preview", "Script") carry translated
// labels and the panel itself has no test id.
const PREVIEW_PANEL = '[class*="min-h-[45rem]"]';

// Its "Preview" / "Script" switch, which is the control the install article tells a reader to press.
const PREVIEW_TABS = `${PREVIEW_PANEL} div.relative.flex.items-center.h-8`;

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
        click: [ALL_TAB, conversationOn('PaperLayer Line'), SIDEPANEL_CLOSE, REPLY_MODE],
        expect: [SIDEPANEL_IS_CLOSED, REPLY_MODE_IS_ON],
      },
      // The first row is an email thread, whose bubbles are full-width by design; this one opens further down
      // the seeded list to catch an ordinary chat channel, where the bubbles are the capped kind.
      'conversation-chat': {
        path: '/app/accounts/1/dashboard',
        click: [ALL_TAB, '.conversations-list div.conversation >> nth=3', SIDEPANEL_CLOSE],
        expect: [SIDEPANEL_IS_CLOSED],
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
        expect: [SIDEPANEL_IS_OPEN],
      },
      // THE AGENT'S HALF OF THE WIDGET PAIR. `tools/visual/capture-widget.mjs` sends a real message from the
      // real widget on a demo shop; this shoots where it lands, which is the half of "connect website chat"
      // that no picture of the widget alone can show.
      //
      // ADDRESSED BY ITS OWN URL, not by clicking a row. Two attempts to pick it out of the list failed for
      // the same reason: the list is live. "The first row" moved when the next seeded conversation arrived,
      // and "the first row on the website channel" opened a SEEDED website conversation instead of the new
      // one -- the published figure showed a different customer from the one the widget half shows. The
      // conversation's own display id is the only address that cannot drift, so the runner that follows the
      // widget capture reads it out of the database and puts it in WIDGET_CONVERSATION.
      'widget-arrival': {
        path: process.env.WIDGET_CONVERSATION
          ? `/app/accounts/1/conversations/${process.env.WIDGET_CONVERSATION}`
          : '/app/accounts/1/dashboard',
        click: [SIDEPANEL_CLOSE],
        expect: [SIDEPANEL_IS_CLOSED],
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

  // THE DOCUMENTATION'S CAMERA ROLL, on the same seeded account as `dashboard` and under the same rule:
  // local seed only, never a production host. Where that set exists to feed the marketing site a handful of
  // hero images, this one exists to photograph the WHOLE product, screen by screen, because an article that
  // describes a screen the reader cannot see is a worse article.
  //
  // One page per screen a published article refers to. `measure` names the controls a figure rings or
  // numbers, so the annotation spec can say `"box": "status-filter"` instead of carrying a coordinate
  // somebody eyeballed; see the block that writes `<name>.boxes.json` below.
  //
  //   node tools/visual/capture.mjs --set docs --viewports desktop --out docs/screenshots/sources/app
  //   node tools/visual/capture.mjs --set docs --locale ar --only analytics-overview --viewports desktop
  docs: {
    signIn: { email: 'john@acme.inc', password: 'Password1!' },
    locales: { en: '' },
    pages: {
      // ── Channels: the inbox list, the channel picker, and the website channel end to end ──────────
      'inbox-list': {
        path: '/app/accounts/1/settings/inboxes',
        measure: { page: 'main, .settings-box, [class*="max-w"]' },
      },
      'inbox-new': '/app/accounts/1/settings/inboxes/new',
      'website-settings': {
        path: `/app/accounts/1/settings/inboxes/${WEBSITE_INBOX}`,
        measure: { preview: PREVIEW_PANEL, tabs: PREVIEW_TABS },
      },
      // The same page with the preview panel showing the INSTALL SNIPPET instead of the widget. This is
      // the one screen an administrator has to find to put chat on their site, and it is behind a tab
      // inside a panel, which is exactly the kind of thing a screenshot earns its place by showing.
      'website-script': {
        path: `/app/accounts/1/settings/inboxes/${WEBSITE_INBOX}`,
        click: [`${PREVIEW_PANEL} button >> nth=1`],
        // THE TOKEN, SO THE FIGURE CAN COVER IT. The snippet on this screen carries a real website token,
        // and a published figure must not. It is addressed by its SHAPE rather than its position -- the one
        // syntax-highlighted string in the block that is a long bare alphanumeric in quotes -- so the same
        // line finds it under `dir=rtl`, where the panel is on the other side of the screen.
        measure: {
          preview: PREVIEW_PANEL,
          tabs: PREVIEW_TABS,
          token: `${PREVIEW_PANEL} :text-matches("^'[A-Za-z0-9_-]{16,}',?$")`,
        },
      },
      'website-prechat': `/app/accounts/1/settings/inboxes/${WEBSITE_INBOX}/pre-chat-form`,
      'website-configuration': `/app/accounts/1/settings/inboxes/${WEBSITE_INBOX}/configuration`,
      'website-business-hours': `/app/accounts/1/settings/inboxes/${WEBSITE_INBOX}/business-hours`,
      'website-csat': `/app/accounts/1/settings/inboxes/${WEBSITE_INBOX}/csat`,
      'website-collaborators': `/app/accounts/1/settings/inboxes/${WEBSITE_INBOX}/collaborators`,
      'email-settings': '/app/accounts/1/settings/inboxes/7',
      'whatsapp-settings': '/app/accounts/1/settings/inboxes/5',
      'telegram-settings': '/app/accounts/1/settings/inboxes/9',
      'api-configuration': '/app/accounts/1/settings/inboxes/8/configuration',

      // ── Analytics: the Lynomia module, one shot per tab ───────────────────────────────────────────
      'analytics-overview': '/app/accounts/1/analytics',
      'analytics-whatsapp': '/app/accounts/1/analytics/whatsapp',
      'analytics-campaigns': '/app/accounts/1/analytics/campaigns',
      'analytics-automations': '/app/accounts/1/analytics/automations',
      'analytics-flows': '/app/accounts/1/analytics/flows',
      'analytics-commerce': '/app/accounts/1/analytics/commerce',
      'analytics-tickets': '/app/accounts/1/analytics/tickets',

      // ── Reports: the Chatwoot-lineage reporting screens, which are a different thing from Analytics
      //    and the difference is the first thing the article has to explain ───────────────────────────
      'reports-overview': '/app/accounts/1/reports/overview',
      'reports-conversation': '/app/accounts/1/reports/conversation',
      'reports-csat': '/app/accounts/1/reports/csat',
      'reports-agent': '/app/accounts/1/reports/agent',
      'reports-inboxes': '/app/accounts/1/reports/inboxes',
      'reports-label': '/app/accounts/1/reports/label',
      'reports-teams': '/app/accounts/1/reports/teams',

      // ── Support desk ──────────────────────────────────────────────────────────────────────────────
      'support-cases': '/app/accounts/1/support/cases',
      'sla-policies': '/app/accounts/1/settings/support/sla-policies',

      // ── Workspace and administration ──────────────────────────────────────────────────────────────
      'settings-agents': '/app/accounts/1/settings/agents',
      'settings-teams': '/app/accounts/1/settings/teams',
      'settings-canned': '/app/accounts/1/settings/canned-response',
      'settings-macros': '/app/accounts/1/settings/macros',
      'settings-attributes': '/app/accounts/1/settings/custom-attributes',
      'settings-assignment-policy': '/app/accounts/1/settings/assignment-policy',
      'settings-custom-roles': '/app/accounts/1/settings/custom-roles',
      'settings-audit-logs': '/app/accounts/1/settings/audit-logs',
      'settings-billing': '/app/accounts/1/settings/billing',
      'settings-integrations': '/app/accounts/1/settings/integrations',
      'settings-general': '/app/accounts/1/settings/general',
      'settings-data-import': '/app/accounts/1/settings/data',
      'profile-settings': '/app/accounts/1/profile/settings',
      'profile-mfa': '/app/accounts/1/profile/settings/mfa',

      // ── Contacts and audiences ────────────────────────────────────────────────────────────────────
      'contacts-list': '/app/accounts/1/contacts',
      'contacts-audiences': '/app/accounts/1/contacts/audiences',
      'global-search': '/app/accounts/1/search',
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
      const { path: suffixPath, click = [], expect = [], measure = {} } =
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

        // THE SHOT IS OF THE SCREEN IT CLAIMS TO BE OF. A toggle whose state is saved to the signed-in
        // user's `ui_settings` carries over between runs, so a click that addresses the state the control is
        // in is a no-op when the run before left it the other way round -- correct, and indistinguishable
        // from a selector that stopped matching. `expect` is what tells the two apart: the state the screen
        // must be in once the clicks are done, read back from the page.
        for (const selector of expect) {
          await page.waitForSelector(selector, { state: 'attached', timeout: 10000 });
        }

        // LAZY IMAGES DO NOT LOAD FOR A FULL-PAGE SCREENSHOT UNLESS THE PAGE IS SCROLLED.
        //
        // `fullPage` resizes the capture viewport, it does not visit the page: an `<img loading="lazy">`
        // below the fold never enters the viewport, never fetches, and lands in the PNG as an empty box.
        // The first marketing page to carry real product screenshots came out with three blank grey
        // rectangles where the product was -- evidence that looked like a rendering bug and was in fact the
        // camera. Everything on this site that matters is a lazy image, so this runs for every page.
        //
        // Scroll to the bottom in viewport-sized steps, wait for every `<img>` to report complete, then
        // return to the top so the shot still starts where the reader does.
        await page.evaluate(async () => {
          const step = window.innerHeight;
          for (let y = 0; y < document.body.scrollHeight; y += step) {
            window.scrollTo(0, y);
            await new Promise(resolve => setTimeout(resolve, 120));
          }
          window.scrollTo(0, 0);
        });
        await page
          .waitForFunction(
            () => [...document.images].every(img => img.complete),
            { timeout: 15000 }
          )
          .catch(() => {});
        await page.waitForTimeout(400);

        // WHERE THE CONTROLS ARE, MEASURED OFF THE LIVE PAGE.
        //
        // A figure's rings and numbered markers are percentages of the published crop, and reading those
        // off the PNG by eye is both slow and wrong by a few pixels every time. The browser already knows
        // exactly where every control is, so a page may declare `measure: { key: selector }` and this
        // writes `<name>.boxes.json` beside the shot. `annotate.mjs` then resolves `"box": "key"` against
        // it, so a spec names a control instead of guessing at a coordinate, and a redesign that moves the
        // control is picked up by the next capture rather than silently mis-pointing the arrow.
        //
        // In the SHOT'S OWN PIXELS: the page is back at the top by now and a signed-in set is captured at
        // viewport size, so a bounding box and the PNG share an origin.
        const measured = {};
        for (const [key, selector] of Object.entries(measure)) {
          const box = await page
            .locator(selector)
            .first()
            .boundingBox()
            .catch(() => null);
          if (!box) {
            failures.push(`${url} -> measure ${key}: no element for ${selector}`);
            continue;
          }
          measured[key] = {
            x: Math.round(box.x),
            y: Math.round(box.y),
            width: Math.round(box.width),
            height: Math.round(box.height),
          };
        }
        if (Object.keys(measure).length) {
          await writeFile(
            file.replace(/\.png$/, '.boxes.json'),
            `${JSON.stringify({ viewport, boxes: measured }, null, 2)}\n`
          );
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
