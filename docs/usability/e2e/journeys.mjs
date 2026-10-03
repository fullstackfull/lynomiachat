// Usability journeys (docs/usability/07-e2e.md), in a real Chromium against the real components, in English and
// Arabic, at desktop and at 390px. Every click is counted by the runner, not estimated: `press` and `click` below are
// the only ways the script touches the page.
//
// usage: node journeys.mjs <out_dir>
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync, mkdirSync } from 'node:fs';
import { extname, join, resolve } from 'node:path';
import { writeFileSync } from 'node:fs';

const OUT = resolve(process.argv[2] || 'results');
const DIST = resolve(import.meta.dirname, 'harness/dist');
const SHOTS = join(OUT, 'screenshots');
// A CommonJS Playwright install exposes everything on `default`.
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
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
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

const results = { journeys: [], checks: [], screenshots: [] };
let clicks = 0;

const click = async (page, selector) => {
  await page.locator(selector).first().click();
  clicks += 1;
};
const press = async (page, key) => {
  await page.keyboard.press(key);
  clicks += 1;
};

const record = (name, steps, note = '') =>
  results.journeys.push({ name, clicks: steps, note });

const check = (name, pass, detail = '') => {
  results.checks.push({ name, pass, detail });
  if (!pass) process.exitCode = 1;
};

const shot = async (page, name) => {
  const file = `${name}.png`;
  await page.screenshot({ path: join(SHOTS, file), fullPage: false });
  results.screenshots.push(file);
};

if (!existsSync(SHOTS)) mkdirSync(SHOTS, { recursive: true });

const server = await serve();
const base = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH,
  args: ['--no-sandbox'],
});

const open = async (page, query) => {
  await page.goto(`${base}/index.html?${query}`);
  await page.waitForSelector('#app > div');
};

const DESKTOP = { width: 1280, height: 900 };
const MOBILE = { width: 390, height: 844 };

for (const locale of ['en', 'ar']) {
  for (const [sizeName, viewport] of [
    ['desktop', DESKTOP],
    ['390px', MOBILE],
  ]) {
    const context = await browser.newContext({ viewport });
    const page = await context.newPage();
    const tag = `${locale}-${sizeName}`;

    // ── Journey A · act on a shared audience from the audience itself ───────────────────────────────────────────
    await open(page, `panel=audience-menu&locale=${locale}`);
    clicks = 0;
    await click(page, '[data-test-id="contact-more-actions"]');
    const menu = page.locator('[data-test-id="contact-more-actions"] + div');
    await menu.waitFor();
    const items = await menu.locator('button').allInnerTexts();
    await shot(page, `journey-a-audience-menu-${tag}`);

    if (locale === 'en') {
      check(
        'A · the audience section offers both cross-module actions, the duplicate, the link and the preset',
        [
          'Use in a new automation rule',
          'Use in a new WhatsApp campaign',
          'Duplicate this audience',
          'Copy link to this audience',
          'New audience from a preset',
        ].every(label => items.some(item => item.includes(label))),
        items.join(' | ')
      );
      check(
        'A · what already references the audience is visible where it is acted on',
        items.some(item =>
          item.includes('Used by 2 automation rules · 1 campaign')
        ),
        items.join(' | ')
      );
    }
    await click(page, '[data-test-id="dropdown-item-use-in-automation"]');
    record(
      `A · open a shared audience's menu and choose "use in a new rule" (${tag})`,
      clicks,
      'before: leave the audience, Settings → Automation → Add → event → attribute → Audience group → operator → find it by name (≈11)'
    );

    // The overflow button must have an accessible name, and the menu must be reachable by keyboard.
    await open(page, `panel=audience-menu&locale=${locale}`);
    const label = await page
      .locator('[data-test-id="contact-more-actions"]')
      .getAttribute('aria-label');
    check(
      `accessibility · the overflow button has an accessible name (${tag})`,
      Boolean(label && label.trim()),
      String(label)
    );
    await page.keyboard.press('Tab');
    const focused = await page.evaluate(
      () => document.activeElement?.dataset?.testId || document.activeElement?.tagName
    );
    check(
      `accessibility · the overflow button takes focus from the keyboard (${tag})`,
      focused === 'contact-more-actions',
      String(focused)
    );
    await page.keyboard.press('Enter');
    check(
      `accessibility · Enter opens the menu (${tag})`,
      await page.locator('[data-test-id="contact-more-actions"] + div').isVisible()
    );

    // ── Journey B · a personal audience offers neither cross-module action ──────────────────────────────────────
    await open(page, `panel=audience-menu&segment=personal&locale=${locale}`);
    await click(page, '[data-test-id="contact-more-actions"]');
    const personal = await page
      .locator('[data-test-id="contact-more-actions"] + div button')
      .allInnerTexts();
    if (locale === 'en') {
      check(
        'B · a personal audience offers no rule or campaign action, since neither module may reference one',
        !personal.some(
          item =>
            item.includes('Use in a new automation rule') ||
            item.includes('Use in a new WhatsApp campaign')
        ) && personal.some(item => item.includes('Duplicate this audience')),
        personal.join(' | ')
      );
    }
    check(
      `B · neither cross-module item is in a personal audience's menu (${tag})`,
      (await page
        .locator('[data-test-id="dropdown-item-use-in-automation"]')
        .count()) === 0 &&
        (await page
          .locator('[data-test-id="dropdown-item-use-in-campaign"]')
          .count()) === 0 &&
        (await page
          .locator('[data-test-id="dropdown-item-duplicate-segment"]')
          .count()) === 1
    );

    // ── Journey C · audience preset → conditions built, nothing created yet ─────────────────────────────────────
    await open(page, `panel=audience-presets&locale=${locale}`);
    clicks = 0;
    await click(page, '#harness-open');
    await page.waitForSelector('[data-test-id="recipe-high_value_buyers"]');
    await shot(page, `journey-c-audience-presets-${tag}`);
    await click(page, '[data-test-id="recipe-high_value_buyers-use"]');
    await page.waitForSelector('[data-test-id="recipe-input-currency"]');
    await shot(page, `journey-c-audience-wizard-${tag}`);
    await page
      .locator('[data-test-id="recipe-input-currency"] select')
      .selectOption('SAR');
    clicks += 1;
    await click(page, '[data-test-id="recipe-create"]');
    const preset = await page.evaluate(() => window.harness?.created?.value);
    record(
      `C · high-value buyers from a preset (${tag})`,
      clicks,
      'before: Filter → attribute picker → Commerce group → Visible spend → operator → amount → Apply → Save → name → share → Save (≈11)'
    );
    if (locale === 'en') {
      check(
        'C · the preset built the condition the engine expects, for the currency chosen',
        preset?.payload?.payload?.[0]?.attribute_key === 'commerce_spend_sar' &&
          preset.payload.payload[0].filter_operator === 'is_greater_than' &&
          preset.payload.payload[0].values[0] === '1000',
        JSON.stringify(preset?.payload)
      );
    }

    // ── Journey D · flow template → a full graph, unpublished ───────────────────────────────────────────────────
    await open(page, `panel=flow-templates&locale=${locale}`);
    clicks = 0;
    await click(page, '#harness-open');
    await page.waitForSelector('[data-test-id="recipe-commerce_order_tracking"]');
    await shot(page, `journey-d-flow-templates-${tag}`);
    await click(page, '[data-test-id="recipe-commerce_order_tracking-use"]');
    await page.waitForSelector('[data-test-id="recipe-input-team"]');
    await shot(page, `journey-d-flow-wizard-${tag}`);
    await page
      .locator('[data-test-id="recipe-input-team"] select')
      .selectOption('1');
    clicks += 1;
    await click(page, '[data-test-id="recipe-create"]');
    const flow = await page.evaluate(() => window.harness?.created?.value);
    record(
      `D · order tracking bot from a template (${tag})`,
      clicks,
      'before: New flow → name → create → 12 palette clicks → ≈25 fields → 19 edge drags (≈59)'
    );
    if (locale === 'en') {
      check(
        'D · the template produced the whole graph, with the chosen team on its handoff',
        flow?.payload?.nodes?.length === 12 &&
          flow.payload.edges.length === 19 &&
          flow.payload.nodes.find(node => node.type === 'handoff').data
            .team_id === 1,
        `${flow?.payload?.nodes?.length} nodes / ${flow?.payload?.edges?.length} edges`
      );
    }

    // ── Journey E · automation recipe → a disabled rule, and "requires setup" is honest ─────────────────────────
    await open(page, `panel=automation-recipes&locale=${locale}`);
    clicks = 0;
    await click(page, '#harness-open');
    await page.waitForSelector('[data-test-id="recipe-active_order_routing"]');
    await shot(page, `journey-e-automation-recipes-${tag}`);
    await click(page, '[data-test-id="recipe-active_order_routing-use"]');
    await page.waitForSelector('[data-test-id="recipe-input-team"]');
    await page
      .locator('[data-test-id="recipe-input-team"] select')
      .selectOption('1');
    clicks += 1;
    await click(page, '[data-test-id="recipe-create"]');
    const rule = await page.evaluate(() => window.harness?.created?.value);
    record(
      `E · "customer with an open order" from a recipe (${tag})`,
      clicks,
      'before: Add → event → attribute → Commerce group → operator → value → add action → assign team → team → Save (≈15)'
    );
    if (locale === 'en') {
      check(
        'E · the rule arrives switched off',
        rule?.payload?.active === false,
        JSON.stringify(rule?.payload)
      );
      check(
        'E · the rule carries the condition and the chosen team',
        rule?.payload?.conditions?.[0]?.attribute_key ===
          'commerce_active_order' &&
          rule.payload.actions.some(
            action =>
              action.action_name === 'assign_team' &&
              action.action_params[0] === 1
          ),
        JSON.stringify(rule?.payload)
      );
    }

    // ── Layout and direction ───────────────────────────────────────────────────────────────────────────────────
    const direction = await page.evaluate(() =>
      getComputedStyle(document.documentElement).direction
    );
    check(
      `direction · the page renders ${locale === 'ar' ? 'right to left' : 'left to right'} (${tag})`,
      direction === (locale === 'ar' ? 'rtl' : 'ltr'),
      direction
    );
    const overflow = await page.evaluate(
      () =>
        document.documentElement.scrollWidth -
        document.documentElement.clientWidth
    );
    check(
      `layout · no horizontal overflow at ${viewport.width}px (${tag})`,
      overflow <= 1,
      `${overflow}px`
    );

    await context.close();
  }
}

await browser.close();
server.close();

writeFileSync(join(OUT, 'journeys.json'), `${JSON.stringify(results, null, 2)}\n`);
const failed = results.checks.filter(item => !item.pass);
console.log(
  `journeys: ${results.journeys.length}  checks: ${results.checks.length}  failed: ${failed.length}  screenshots: ${results.screenshots.length}`
);
failed.forEach(item => console.log(`FAIL ${item.name} — ${item.detail}`));
results.journeys.forEach(item => console.log(`${item.clicks} clicks · ${item.name}`));
