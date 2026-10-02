// Lynomia Flow Builder E2E, the builder (docs/flow-builder/10-e2e.md): an administrator creates a flow, builds the
// WhatsApp menu of scenario A on the canvas (buttons routed by option id, a reply, a handoff to Customer Care), sees the
// server's validation, publishes, connects the WhatsApp inbox, and runs both branches in Test Mode. Then the builder in
// Arabic and at phone width. Production build and configuration.
//
// usage: node e2e_builder.js <out_dir>     env: ERUN (the E2E runner)
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { execSync } = require('child_process');
const fs = require('fs');

const B = 'http://localhost:3100';
const [out] = process.argv.slice(2);
const { ERUN } = process.env;
const PASSWORD = 'Password1!x';
const results = [];
const pageErrors = [];
const failedResponses = [];

const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  -- ${detail}` : ''}`);
};
const ctl = args => JSON.parse(execSync(`${ERUN} "bundle exec rails runner docs/flow-builder/e2e/ctl.rb ${args} 2>/dev/null | grep '^SIM ' | tail -1"`)
  .toString().slice(4));
const shot = (page, name) => page.screenshot({ path: `${out}/${name}.png` });
const node = (page, text) => page.locator('.vue-flow__node', { hasText: text }).first();

// Drag from an output connector to another node's input connector, as a person does with the mouse.
const wire = async (page, from, output, to) => {
  const source = from.locator('.vue-flow__handle.source').nth(output);
  const target = to.locator('.vue-flow__handle.target');
  const a = await source.boundingBox();
  const b = await target.boundingBox();
  await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
  await page.mouse.down();
  await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2, { steps: 12 });
  await page.mouse.up();
};

const login = async (browser, viewport = { width: 1440, height: 900 }) => {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  page.on('pageerror', error => pageErrors.push(error.message));
  page.on('response', response => {
    if (response.url().includes('/flows') && response.status() >= 500) failedResponses.push(`${response.status()} ${response.url()}`);
  });
  await page.goto(`${B}/app/login`, { waitUntil: 'networkidle' });
  await page.fill('input[name="email_address"]', 'admin_a@commerce.lynomia.local');
  await page.fill('input[type="password"]', PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/app\/accounts\/\d+/, { timeout: 60000 });
  return page;
};

// A node from the palette, dragged onto the canvas at (x, y) from the canvas' top-left corner.
const placeOnCanvas = async (page, type, x, y) => {
  const canvas = await page.locator('.vue-flow').boundingBox();
  await page.locator(`[data-test-id="flow-palette-${type}"]`).dragTo(page.locator('.vue-flow'), {
    targetPosition: { x, y },
  });
  await page.locator('.vue-flow__node.selected').waitFor();
  return canvas;
};

(async () => {
  const setup = ctl('setup');
  check('setup: account A has the Flow Builder and its WhatsApp inbox', setup.inbox_id > 0, setup.inbox_name);
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });
  const page = await login(browser);
  const base = `${B}/app/accounts/${setup.account_id}/settings/flows`;

  // 1. The list, and a new flow.
  await page.goto(base, { waitUntil: 'networkidle' });
  check('1 the Flow Builder is in Settings', await page.getByText('Flow Builder').first().isVisible());
  await shot(page, 'flow-01-list-empty');
  await page.click('[data-test-id="flow-new-button"]');
  await page.fill('[data-test-id="flow-name-input"] input, input[data-test-id="flow-name-input"]', 'E2E Welcome menu').catch(async () => {
    await page.locator('dialog[open] input').first().fill('E2E Welcome menu');
  });
  await page.locator('dialog[open]').getByRole('button', { name: 'Create' }).click();
  await page.waitForURL(/settings\/flows\/\d+$/, { timeout: 30000 });
  await page.waitForSelector('.vue-flow__node');
  check('2 a new flow opens on a Start → End starter', (await page.locator('.vue-flow__node').count()) === 2);

  // 2. Build scenario A: Start → Buttons (Track order / Customer care); Track → a reply → End; Care → handoff.
  await placeOnCanvas(page, 'buttons', 20, 40);
  const panel = page.locator('[data-test-id="flow-config-panel"]');
  await panel.locator('textarea').first().fill('Welcome to Syria Cosmetics! How can we help?');
  await panel.getByPlaceholder('Option title').first().fill('Track order');
  await panel.getByRole('button', { name: /Add option/ }).click();
  await panel.getByPlaceholder('Option title').nth(1).fill('Customer care');
  check('3 a Buttons node shows one connector per option', (await node(page, 'How can we help?').locator('.vue-flow__handle.source').count()) === 4);

  await placeOnCanvas(page, 'send_message', 20, 440);
  await panel.locator('textarea').first().fill('Please send your order number.');
  await placeOnCanvas(page, 'handoff', 20, 640);
  await panel.locator('textarea').first().fill('Customer asked for customer care');
  await panel.locator('header button').last().click();
  await page.click('[data-test-id="flow-fit-view"]');
  await page.waitForTimeout(500);
  await shot(page, 'flow-02-building');

  // Saved half-built: the server explains what is missing.
  await page.click('[data-test-id="flow-save-button"]');
  await page.waitForSelector('[data-test-id="flow-errors"]');
  const errorsText = await page.locator('[data-test-id="flow-errors"]').innerText();
  check('4 the server validates the draft: unconnected options and unreachable nodes are shown', /Connect the output|cannot be reached/.test(errorsText),
    errorsText.split('\n').slice(0, 3).join(' | '));
  await shot(page, 'flow-03-validation');

  const start = node(page, 'Start');
  const menu = node(page, 'How can we help?');
  await wire(page, start, 0, menu);
  await wire(page, menu, 0, node(page, 'Please send your order number.'));
  await wire(page, menu, 1, node(page, 'Customer asked for customer care'));
  await wire(page, node(page, 'Please send your order number.'), 0, node(page, 'End'));
  check('5 connections are drawn from each output', (await page.locator('.vue-flow__edge').count()) >= 4,
    `${await page.locator('.vue-flow__edge').count()} edges`);

  // 3. Publish.
  await page.click('[data-test-id="flow-publish-button"]');
  await page.waitForFunction(() => document.querySelector('[data-test-id="flow-status"]')?.innerText.includes('Published'), null, { timeout: 30000 });
  check('6 the flow publishes once valid (version 1)', (await page.locator('[data-test-id="flow-status"]').innerText()).includes('version 1'));
  const state = ctl('state');
  check('7 the draft became the published version', JSON.stringify(state.versions) === JSON.stringify([[1, 'published']]), JSON.stringify(state.versions));
  await shot(page, 'flow-04-published');

  // 4. Connect the WhatsApp inbox (Chatwoot's own bot connection).
  await page.locator('select').filter({ hasText: 'Connect a WhatsApp inbox' }).selectOption({ label: setup.inbox_name });
  await page.waitForTimeout(1500);
  check('8 the WhatsApp inbox answers with the flow', ctl('state').inbox_bot === state.flow_id);

  // 5. Test Mode, both branches, nothing kept.
  await page.click('[data-test-id="flow-test-button"]');
  const test = page.locator('[data-test-id="flow-test-panel"]');
  await test.locator('[data-test-id="flow-test-input"] input, input[data-test-id="flow-test-input"]').first().fill('hi');
  await test.locator('button[type="submit"]').click();
  await test.locator('[data-test-id="flow-test-bot"]').first().waitFor();
  check('9 Test Mode: the menu arrives with its buttons', (await test.locator('[data-test-id^="flow-test-option-"]').count()) === 2);
  await test.getByRole('button', { name: 'Track order' }).click();
  await page.waitForFunction(() => document.querySelector('[data-test-id="flow-test-state"]')?.innerText.includes('Completed'), null, { timeout: 30000 });
  check('10 Test Mode: tapping Track order follows its option to the reply', (await test.innerText()).includes('Please send your order number.'));
  await shot(page, 'flow-05-test-track');
  await test.getByRole('button', { name: 'Start over' }).click().catch(() => test.locator('header button').first().click());
  await test.locator('[data-test-id="flow-test-input"] input, input[data-test-id="flow-test-input"]').first().fill('hello');
  await test.locator('button[type="submit"]').click();
  await test.getByRole('button', { name: 'Customer care' }).click();
  await page.waitForFunction(() => document.querySelector('[data-test-id="flow-test-state"]')?.innerText.includes('Handed to the team'), null, { timeout: 30000 });
  check('11 Test Mode: Customer care hands off with the note for agents', (await test.innerText()).includes('Customer asked for customer care'));
  await shot(page, 'flow-06-test-handoff');
  check('12 Test Mode kept no session', ctl('state').sessions.length === 0);

  // 6. The inspector, Arabic, and phone width.
  await page.click('text=Sessions');
  await page.locator('[data-test-id="flow-sessions-panel"]').waitFor();
  check('13 the session inspector opens', true);
  ctl('locale ar');
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForSelector('.vue-flow__node');
  check('14 Arabic: the builder is right to left with translated nodes, and nothing is left unsaved',
    (await page.locator('[dir="rtl"]').count()) > 0 && (await page.getByText('أزرار').first().isVisible())
    && !(await page.locator('[data-test-id="flow-status"]').innerText()).includes('غير محفوظة'));
  await shot(page, 'flow-07-ar-desktop');
  const mobile = await login(browser, { width: 390, height: 844 });
  await mobile.goto(base, { waitUntil: 'networkidle' });
  await shot(mobile, 'flow-08-ar-mobile-list');
  await mobile.goto(`${base}/${state.flow_id}`, { waitUntil: 'networkidle' });
  await mobile.waitForSelector('.vue-flow__node');
  const overflow = await mobile.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  check('15 phone width: the builder has no page-wide horizontal scroll', overflow <= 1, `${overflow}px`);
  await shot(mobile, 'flow-09-ar-mobile-builder');
  ctl('locale en');

  check('16 no browser errors, no 5xx from the flows API', pageErrors.length === 0 && failedResponses.length === 0,
    [...pageErrors, ...failedResponses].slice(0, 3).join(' | '));
  await browser.close();
  ctl('teardown');
  fs.writeFileSync(`${out}/e2e_builder.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed`);
})().catch(error => {
  console.error(error);
  fs.writeFileSync(`${out}/e2e_builder.json`, JSON.stringify(results, null, 2));
  process.exit(1);
});
