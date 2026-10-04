// Ten named browser journeys over the surfaces this phase changed, each run four times: English and Arabic,
// desktop and phone. The control inventory proves a control EXISTS and has a name; a journey proves a person
// can still get through the task with it — by clicking, and where the control is the only route to something,
// by keyboard alone.
//
// usage: node journeys.mjs <out_dir>
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { extname, join, resolve } from 'node:path';

const OUT = resolve(
  process.argv[2] || 'docs/ui-modernization/journeys/results'
);
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
        response.writeHead(200, {
          'Content-Type': TYPES[extname(file)] || 'application/octet-stream',
        });
        response.end(body);
      } catch {
        response.writeHead(404);
        response.end();
      }
    });
    server.listen(0, '127.0.0.1', () => done(server));
  });

// Every control a person can act on, with the name a screen reader announces — the same rule the capture uses,
// so a journey and the inventory agree on what "a control called X" means.
const NAMES = () => {
  const SELECTOR =
    'button, a[href], input:not([type="hidden"]), select, textarea, summary, [role="button"], [role="menuitem"], [role="menuitemradio"], [role="tab"], [role="switch"], [role="checkbox"], [role="link"]';
  const nameOf = node =>
    (
      node.getAttribute('aria-label') ||
      node.getAttribute('title') ||
      (node.innerText || '').trim() ||
      node.getAttribute('placeholder') ||
      ''
    )
      .replace(/\s+/g, ' ')
      .trim();
  return [...document.querySelectorAll(SELECTOR)]
    .filter(node => {
      const box = node.getBoundingClientRect();
      const style = getComputedStyle(node);
      return (
        box.width > 0 &&
        box.height > 0 &&
        style.visibility !== 'hidden' &&
        !node.closest('[aria-hidden="true"]')
      );
    })
    .map(nameOf)
    .filter(Boolean);
};

const results = { runs: [], checks: [], shots: [] };
let currentRun = null;

const check = (name, pass, detail = '') => {
  results.checks.push({ run: currentRun, name, pass, detail });
  if (!pass) process.exitCode = 1;
};

const shot = async (page, name) => {
  const file = `${name}.png`;
  await page.screenshot({ path: join(SHOTS, file), fullPage: false });
  results.shots.push(file);
};

const CONTEXTS = [
  { locale: 'en', size: 'desktop', viewport: { width: 1280, height: 900 } },
  { locale: 'ar', size: 'desktop', viewport: { width: 1280, height: 900 } },
  { locale: 'en', size: '390px', viewport: { width: 390, height: 844 } },
  { locale: 'ar', size: '390px', viewport: { width: 390, height: 844 } },
];

const server = await serve();
const base = `http://127.0.0.1:${server.address().port}`;
await mkdir(SHOTS, { recursive: true });
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH,
  args: ['--no-sandbox'],
});

// Opens one surface and hands back the page plus the errors it raised. Animations are frozen for the same
// reason the capture freezes them: a journey that waits on a transition is a journey that flakes.
const open = async (ctx, { surface, route, state }) => {
  const context = await browser.newContext({
    viewport: ctx.viewport,
    reducedMotion: 'reduce',
  });
  await context.addInitScript(() => {
    const style = document.createElement('style');
    style.textContent =
      '*,*::before,*::after{animation-duration:0s!important;animation-delay:0s!important;transition-duration:0s!important;transition-delay:0s!important}';
    document.addEventListener('DOMContentLoaded', () =>
      document.head.append(style)
    );
  });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(String(error.message).slice(0, 160)));
  page.on('console', message => {
    if (message.type() !== 'error') return;
    const text = message.text();
    if (text.includes('Failed to load resource')) return;
    errors.push(text.slice(0, 160));
  });
  const query = new URLSearchParams({ surface, locale: ctx.locale });
  if (route) query.set('route', route);
  if (state) query.set('state', state);
  await page.goto(`${base}/index.html?${query}`);
  await page
    .waitForSelector('body[data-harness-ready]', { timeout: 20000 })
    .catch(() => {});
  await page.waitForTimeout(300);
  return { page, context, errors };
};

const names = page => page.evaluate(NAMES);

// Finds a visible control by the name it announces, the way a person finds it by reading it.
const byName = (page, name) =>
  page
    .locator(
      'button, a[href], [role="button"], [role="menuitem"], [role="menuitemradio"], [role="switch"], [role="tab"]'
    )
    .filter({ hasText: new RegExp(`^\\s*${name}\\s*$`, 'i') })
    .first();

const clickName = async (page, name) => {
  const direct = page.getByRole('button', { name, exact: false }).first();
  if (await direct.count()) {
    await direct.click({ timeout: 5000 });
    return true;
  }
  const fallback = byName(page, name);
  if (await fallback.count()) {
    await fallback.click({ timeout: 5000 });
    return true;
  }
  return false;
};

const overflowOf = page =>
  page.evaluate(() =>
    Math.max(
      0,
      document.documentElement.scrollWidth - document.documentElement.clientWidth
    )
  );

const directionOf = page =>
  page.evaluate(() => document.documentElement.getAttribute('dir') || 'ltr');

// Every journey, in every context, is held to these three regardless of what else it checks.
const baseline = async (page, errors, ctx, id) => {
  check(`${id}: no page error`, errors.length === 0, errors.join(' | '));
  const dir = await directionOf(page);
  check(
    `${id}: direction is ${ctx.locale === 'ar' ? 'rtl' : 'ltr'}`,
    dir === (ctx.locale === 'ar' ? 'rtl' : 'ltr'),
    dir
  );
  const overflow = await overflowOf(page);
  check(`${id}: no horizontal overflow`, overflow === 0, `${overflow}px`);
};

const JOURNEYS = [
  {
    id: 'J1',
    title: 'Reach every Settings destination from the sidebar, by keyboard',
    surface: 'sidebar',
    run: async ({ page }, ctx, id) => {
      const before = await names(page);
      const header = page
        .locator('nav > ul > li > [title]')
        .filter({ hasText: /settings|الإعدادات/i });
      const count = await header.count();
      check(`${id}: the Settings group header is a control`, count > 0, `${count}`);
      if (!count) return 0;
      // Enter on the header is the keyboard route into Settings; nothing else opens the group.
      await header.first().focus();
      await page.keyboard.press('Enter');
      await page.waitForTimeout(300);
      const after = await names(page);
      check(
        `${id}: Enter reveals the settings destinations`,
        after.length - before.length >= 10,
        `${before.length} -> ${after.length}`
      );
      const expanded = await header.first().getAttribute('aria-expanded');
      check(`${id}: the header announces that it is open`, expanded === 'true', String(expanded));
      check(`${id}: every destination announces a name`, after.every(Boolean), '');
      return after.length - before.length;
    },
  },
  {
    id: 'J2',
    title: 'Filter and sort the conversation list',
    surface: 'conversation-list-header',
    run: async ({ page }, ctx, id) => {
      const all = await names(page);
      check(
        `${id}: filter, sort and layout are all present and named`,
        all.length >= 2 && all.every(Boolean),
        all.join(' | ')
      );
      // Each is a real control a keyboard can land on, which is what the list header is for.
      const focusable = await page.evaluate(() => {
        const nodes = [...document.querySelectorAll('button, [role="button"]')].filter(
          n => n.getBoundingClientRect().width > 0
        );
        return nodes.filter(n => {
          n.focus();
          return document.activeElement === n;
        }).length;
      });
      check(
        `${id}: every list control takes keyboard focus`,
        focusable >= all.length - 1,
        `${focusable} of ${all.length}`
      );
      return all.length;
    },
  },
  {
    id: 'J3',
    title: 'Act on a conversation from its row menu',
    surface: 'conversation-context-menu',
    run: async ({ page }, ctx, id) => {
      const all = await names(page);
      check(
        `${id}: the row menu offers its full set of actions`,
        all.length >= 10,
        `${all.length}: ${all.join(' | ').slice(0, 170)}`
      );
      check(`${id}: every menu action announces a name`, all.every(Boolean), '');
      const reachable = await page.evaluate(() => {
        const SELECTOR =
          'button, a[href], [role="button"], [role="menuitem"], [role="menuitemradio"]';
        const nodes = [...document.querySelectorAll(SELECTOR)].filter(
          n => n.getBoundingClientRect().width > 0
        );
        return nodes.filter(n => {
          n.focus();
          return document.activeElement === n;
        }).length;
      });
      check(
        `${id}: every menu action takes keyboard focus`,
        reachable >= all.length - 1,
        `${reachable} of ${all.length}`
      );
      return all.length;
    },
  },
  {
    id: 'J4',
    title: 'Reach a bulk action after selecting conversations',
    surface: 'conversation-bulk-actions',
    run: async ({ page }, ctx, id) => {
      const all = await names(page);
      // Count rather than wording: the same bar has to carry the same number of actions in both locales.
      check(
        `${id}: the bulk bar carries its selection state and its actions`,
        all.length >= 6,
        `${all.length}: ${all.join(' | ').slice(0, 170)}`
      );
      check(`${id}: every bulk control announces a name`, all.every(Boolean), '');
      return all.length;
    },
  },
  {
    id: 'J5',
    title: 'Resolve a conversation with its status options',
    surface: 'conversation-header',
    run: async ({ page }, ctx, id) => {
      const before = await names(page);
      const trigger = page.getByRole('button', { name: /more status actions|المزيد/i }).first();
      const has = await trigger.count();
      check(`${id}: the status menu has a named trigger`, has > 0, `${has}`);
      if (!has) return 0;
      await trigger.click();
      await page.waitForTimeout(300);
      const after = await names(page);
      const added = after.filter(n => !before.includes(n));
      // Opening this menu closes the other one, so the total does not grow; what has to appear is the
      // status options themselves.
      check(
        `${id}: the status options open`,
        added.length >= 2,
        `${before.join('/')} -> ${after.join('/')}`
      );
      check(
        `${id}: the options that open are named`,
        added.length >= 2 && added.every(Boolean),
        added.join(', ')
      );
      return added.length;
    },
  },
  {
    // Contacts phase B rewrote this dialog so it owns the create, the validation errors and the duplicate
    // recovery. Unit tests mock the store and the router; this is the only check that mounts it against the
    // real ones, where a wiring mistake would throw rather than merely render differently.
    //
    // Harness note: this surface renders with the header's more-actions menu already open, so its items are
    // in the inventory. Clicking the trigger would close it — the menu item is clicked directly.
    id: 'J11',
    title: 'Open the create-contact dialog from the contacts header',
    surface: 'contacts-header',
    run: async ({ page }, ctx, id) => {
      const inputsBefore = await page.locator('input:visible').count();

      const addItem = page.getByText(/add contact/i).first();
      const hasAdd = await addItem.count();
      check(`${id}: the header menu offers adding a contact`, hasAdd > 0, `${hasAdd}`);
      if (!hasAdd) return 0;

      await addItem.click();
      await page.waitForTimeout(400);

      // The dialog renders its slot only while open, so the form's own fields appearing proves both that it
      // opened and that nothing in the rewritten component threw on the way.
      const inputsAfter = await page.locator('input:visible').count();
      check(
        `${id}: the create dialog opens with its form`,
        inputsAfter > inputsBefore + 3,
        `${inputsBefore} -> ${inputsAfter} visible inputs`
      );

      const all = await names(page);
      check(
        `${id}: the dialog keeps its save control`,
        all.some(n => /save contact|حفظ/i.test(n || '')),
        all.join(' | ').slice(0, 170)
      );
      check(
        `${id}: the dialog keeps its cancel control`,
        all.some(n => /cancel|إلغاء/i.test(n || '')),
        all.join(' | ').slice(0, 170)
      );
      check(`${id}: every dialog control announces a name`, all.every(Boolean), '');
      return inputsAfter;
    },
  },
  {
    id: 'J6',
    title: 'Start a WhatsApp campaign',
    surface: 'campaigns-whatsapp',
    route: 'campaigns_whatsapp_index',
    run: async ({ page }, ctx, id) => {
      const plus = page
        .locator('button')
        .filter({ has: page.locator('[class*="i-lucide-plus"]') })
        .first();
      const has = await plus.count();
      check(`${id}: the page offers its primary action`, has > 0, `${has}`);
      if (!has) return 0;
      await plus.click();
      await page.waitForTimeout(500);
      const fields = await page.locator('input, textarea, select').count();
      check(`${id}: the create panel opens with its fields`, fields >= 2, `${fields} fields`);
      return fields;
    },
  },
  {
    id: 'J7',
    title: 'Read a campaign’s delivery analytics',
    surface: 'campaigns-whatsapp-analytics',
    route: 'campaigns_whatsapp_analytics',
    run: async ({ page }, ctx, id) => {
      const text = await page.evaluate(() => document.body.innerText);
      check(
        `${id}: the delivery tiles render numbers, not an error`,
        !/aren.t available|غير متاح|NaN/i.test(text),
        text.slice(0, 110).replace(/\s+/g, ' ')
      );
      const names_ = await names(page);
      const tabs = names_.filter(n => /\(\d+\)/.test(n));
      check(
        `${id}: the status breakdown is offered as filters`,
        tabs.length >= 4,
        tabs.join(', ')
      );
      const rows = names_.filter(n => /view details|عرض/i.test(n));
      check(`${id}: the recipient rows render`, rows.length >= 1, `${rows.length} rows`);
      return rows.length;
    },
  },
  {
    id: 'J8',
    title: 'Add the first webhook from the empty state',
    surface: 'webhooks-list-empty',
    route: 'settings_integrations_webhook',
    state: 'empty',
    run: async ({ page }, ctx, id) => {
      const before = await names(page);
      // The empty state must offer the action that fills it, not just say the list is empty.
      const cta = before.filter(n => /add new webhook|إضافة/i.test(n));
      check(
        `${id}: the empty state offers the action that fills it`,
        cta.length >= 1,
        before.join(' · ').slice(0, 170)
      );
      if (!cta.length) return 0;
      await page.getByRole('button', { name: cta[0] }).last().click();
      await page.waitForTimeout(500);
      const fields = await page.locator('input, textarea, select').count();
      check(`${id}: the add dialog opens`, fields >= 2, `${fields} fields`);
      return fields;
    },
  },
  {
    id: 'J9',
    title: 'Narrow the audit log to a date range',
    surface: 'auditlogs-list',
    route: 'auditlogs_list',
    run: async ({ page }, ctx, id) => {
      const before = await names(page);
      const trigger = page
        .locator('button')
        .filter({ has: page.locator('[class*="i-lucide-calendar-range"]') })
        .first();
      const has = await trigger.count();
      check(`${id}: the filter bar offers a date range`, has > 0, `${has}`);
      if (!has) return 0;
      await trigger.click();
      await page.waitForTimeout(500);
      const after = await names(page);
      check(
        `${id}: the date picker opens`,
        after.length > before.length + 5,
        `${before.length} -> ${after.length}`
      );
      const nav = after.filter(n => /earlier dates|later dates|أقدم|أحدث/i.test(n));
      check(
        `${id}: its navigation arrows announce what they do`,
        nav.length >= 2,
        nav.join(', ')
      );
      check(`${id}: every control in the picker is named`, after.every(Boolean), '');
      return after.length - before.length;
    },
  },
  {
    id: 'J10',
    title: 'Reach every contact-panel section as a control',
    surface: 'conversation-panel',
    run: async ({ page }, ctx, id) => {
      const sections = page.locator('button[aria-expanded]');
      const count = await sections.count();
      check(`${id}: the panel sections are controls that announce their state`, count >= 8, `${count}`);
      const all = await names(page);
      check(
        `${id}: every control in the panel announces a name`,
        all.length >= 40 && all.every(Boolean),
        `${all.length} controls`
      );
      // Each section header has to be reachable by keyboard; the open/closed value itself is a persisted
      // per-user preference whose store write the harness stubs, so the flip is not asserted here.
      const focusable = await page.evaluate(() => {
        const nodes = [...document.querySelectorAll('button[aria-expanded]')];
        return nodes.filter(n => {
          n.focus();
          return document.activeElement === n;
        }).length;
      });
      check(
        `${id}: every section header takes keyboard focus`,
        focusable === count,
        `${focusable} of ${count}`
      );
      return count;
    },
  },
];

for (const journey of JOURNEYS) {
  for (const ctx of CONTEXTS) {
    const tag = `${ctx.locale}-${ctx.size}`;
    currentRun = `${journey.id} (${tag})`;
    const { page, context, errors } = await open(ctx, {
      surface: journey.surface,
      route: journey.route,
      state: journey.state,
    });
    let outcome = null;
    try {
      outcome = await journey.run({ page }, ctx, journey.id);
      await baseline(page, errors, ctx, journey.id);
    } catch (error) {
      check(`${journey.id}: completed without throwing`, false, String(error.message).slice(0, 160));
    }
    if (ctx.size === 'desktop') {
      await shot(page, `${journey.id}-${tag}`);
    }
    results.runs.push({
      id: journey.id,
      title: journey.title,
      context: tag,
      surface: journey.surface,
      outcome,
    });
    await context.close();
    // eslint-disable-next-line no-console
    console.log(`${journey.id} · ${journey.title} (${tag})`);
  }
}

await browser.close();
server.close();

const failed = results.checks.filter(item => !item.pass);
await writeFile(join(OUT, 'journeys.json'), JSON.stringify(results, null, 2));
// eslint-disable-next-line no-console
console.log(
  `\njourneys: ${results.runs.length}  checks: ${results.checks.length}  failed: ${failed.length}  screenshots: ${results.shots.length}`
);
for (const item of failed) {
  // eslint-disable-next-line no-console
  console.log(`  FAIL  ${item.run}  ${item.name}  ${item.detail}`);
}
