// Lynomia Campaigns browser E2E (docs/campaigns/07-e2e.md): an administrator creates a WhatsApp campaign in Chatwoot's
// campaign builder with a label and a shared audience as recipients, sees the server's count (each contact once), and
// the campaign stores the two references. The audience then says it is used by a campaign and cannot be deleted; once
// the campaign is deleted (Chatwoot's cancel) it is free. Then the builder in Arabic and at phone width. Production build
// and configuration. Nothing is sent: the campaign is scheduled for tomorrow and deleted.
//
// usage: node e2e_campaigns.js <out_dir>     env: ERUN (the E2E runner)
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
let current;

const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  -- ${detail}` : ''}`);
};
const ctl = args => JSON.parse(execSync(`${ERUN} "bundle exec rails runner docs/campaigns/e2e/ctl.rb ${args} 2>/dev/null | grep '^SIM ' | tail -1"`)
  .toString().slice(4));
const shot = (page, name) => page.screenshot({ path: `${out}/${name}.png` });
const clean = text => text.replace(/\s+/g, ' ').trim();

const login = async (browser, viewport = { width: 1440, height: 900 }) => {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  page.on('pageerror', error => pageErrors.push(error.message));
  page.on('response', response => {
    if (/campaigns|custom_filters/.test(response.url()) && response.status() >= 500) failedResponses.push(`${response.status()} ${response.url()}`);
  });
  await page.goto(`${B}/app/login`, { waitUntil: 'networkidle' });
  await page.fill('input[name="email_address"]', 'admin_a@commerce.lynomia.local');
  await page.fill('input[type="password"]', PASSWORD);
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/app\/accounts\/\d+/, { timeout: 60000 });
  return page;
};

const pick = async (page, root, option) => {
  await page.locator(`${root} button, ${root} .cursor-pointer`).first().click();
  await page.locator(`${root} li[role="option"]`, { hasText: option }).first().click();
};
const form = page => page.locator('form:has([data-test-id="campaign-recipients"])');
const openForm = async (page, account) => {
  await page.goto(`${B}/app/accounts/${account}/campaigns/whatsapp`, { waitUntil: 'networkidle' });
  await page.getByRole('button', { name: /create campaign|إنشاء حملة/i }).first().click();
  await page.locator('[data-test-id="campaign-recipients"]').waitFor();
};
const countText = async page => {
  const count = page.locator('[data-test-id="campaign-recipient-count"]');
  await page.waitForFunction(() => {
    const element = document.querySelector('[data-test-id="campaign-recipient-count"]');
    return element && !/Counting|جارٍ/.test(element.textContent);
  }, null, { timeout: 15000 }).catch(() => {});
  return clean(await count.innerText().catch(() => ''));
};
const tomorrow = () => {
  const date = new Date(Date.now() + 24 * 3600 * 1000 - new Date().getTimezoneOffset() * 60000);
  return date.toISOString().slice(0, 16);
};

(async () => {
  const setup = ctl('setup');
  check('setup: account A has WhatsApp campaigns, a label, test contacts and the shared audience', setup.audience_id > 0, setup.inbox_name);
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });
  const page = await login(browser);
  current = page;
  const account = setup.account_id;

  // 1. The builder: Recipients = Labels + Shared audiences, with the server's count.
  await openForm(page, account);
  await form(page).locator('input').first().fill('E2E Eid offer');
  await pick(page, '#inbox', setup.inbox_name);
  await pick(page, '#template', 'Hello World');
  await pick(page, '[data-test-id="campaign-recipient-labels"]', 'e2e-eid');
  await page.locator('[data-test-id="campaign-recipients"] legend').click();
  const labelCount = await countText(page);
  await pick(page, '[data-test-id="campaign-recipient-audiences"]', 'E2E VIP buyers');
  await page.locator('[data-test-id="campaign-recipients"] legend').click();
  const bothCount = await countText(page);
  const audienceOptions = await page.locator('[data-test-id="campaign-recipient-audiences"] li[role="option"]').allInnerTexts();
  check('1 Recipients offers Labels and the account\'s shared audiences only', audienceOptions.map(clean).includes('E2E VIP buyers'),
    audienceOptions.map(clean).join(', '));
  check('1 the count is the server\'s, each contact once: label 2, label + audience 4 (Layla in both counted once)',
    labelCount.startsWith('2 contacts match now') && bothCount.startsWith('4 contacts match now'), `${labelCount} | ${bothCount}`);
  await form(page).locator('input[type="datetime-local"]').fill(tomorrow());
  await shot(page, 'campaign-01-recipients-en');
  await form(page).getByRole('button', { name: /^create$/i }).click();
  await page.waitForTimeout(1500);
  const stored = ctl('campaign');
  check('1 the campaign stores a Label and an Audience reference, scheduled, not sent',
    stored.campaign_status === 'active' && JSON.stringify(stored.audience) === JSON.stringify([
      { id: setup.label_id, type: 'Label' }, { id: setup.audience_id, type: 'Audience' }]), JSON.stringify(stored));
  await shot(page, 'campaign-02-list-en');

  // 2. The audience knows: "used by … 1 campaigns not yet sent", and refuses deletion.
  await page.goto(`${B}/app/accounts/${account}/contacts/segments/${setup.audience_id}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1500);
  await page.locator('#toggleContactsFilterButton').click();
  await page.waitForTimeout(800);
  const note = clean(await page.locator('[data-test-id="shared-audience-note"]').innerText().catch(() => ''));
  await shot(page, 'campaign-03-audience-in-use-en');
  await page.goto(`${B}/app/accounts/${account}/contacts/segments/${setup.audience_id}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1500);
  await page.locator('button:has(.i-lucide-trash)').first().click();
  await page.waitForTimeout(400);
  await page.locator('dialog[open]').getByRole('button', { name: /yes, delete/i }).click();
  await page.waitForTimeout(800);
  const toast = clean(await page.locator('body').innerText());
  await shot(page, 'campaign-04-delete-refused-en');
  check('2 the audience note says it is used by 1 campaign not yet sent', note.includes('used by 0 active automation rules and 1 campaigns not yet sent'), note);
  check('2 deleting it is refused: "This audience is used by 1 campaigns that have not been sent yet"',
    toast.includes('This audience is used by 1 campaigns that have not been sent yet') && ctl('usage').shared === true);

  // 3. Arabic, desktop and phone width.
  ctl('locale ar');
  await openForm(page, account);
  await pick(page, '[data-test-id="campaign-recipient-audiences"]', 'E2E VIP buyers');
  await page.locator('[data-test-id="campaign-recipients"] legend').click();
  const arabicCount = await countText(page);
  await shot(page, 'campaign-05-recipients-ar');
  check('3 Arabic: المستلمون, الجماهير المشتركة, and the count in Arabic',
    (await page.locator('[data-test-id="campaign-recipients"]').innerText()).includes('الجماهير المشتركة') && arabicCount.startsWith('3 جهة اتصال'),
    arabicCount);
  const mobile = await login(browser, { width: 390, height: 844 });
  await openForm(mobile, account);
  await pick(mobile, '[data-test-id="campaign-recipient-labels"]', 'e2e-eid');
  await mobile.locator('[data-test-id="campaign-recipients"] legend').click();
  await countText(mobile);
  const fits = await mobile.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
  await shot(mobile, 'campaign-06-recipients-mobile-ar');
  const block = await mobile.locator('[data-test-id="campaign-recipients"]').boundingBox();
  const panel = await form(mobile).boundingBox();
  check('3 phone width: no horizontal page scroll, and the recipients block stays inside the create panel (Chatwoot\'s fixed 25rem '
    + 'popover, unchanged, is wider than a 390px screen before and after this change)',
  fits && block.width <= panel.width, `block ${Math.round(block.width)}px, panel ${Math.round(panel.width)}px`);
  ctl('locale en');

  // 4. Deleting the campaign (Chatwoot's cancel) frees the audience.
  await page.goto(`${B}/app/accounts/${account}/campaigns/whatsapp`, { waitUntil: 'networkidle' });
  const card = page.locator('div', { hasText: 'E2E Eid offer' }).last();
  await card.locator('button:has(.i-lucide-trash), button:has(.i-lucide-trash-2)').first().click()
    .catch(() => page.locator('button:has(.i-lucide-trash), button:has(.i-lucide-trash-2)').first().click());
  await page.waitForTimeout(400);
  await page.locator('dialog[open]').getByRole('button', { name: /delete|حذف/i }).last().click();
  await page.waitForTimeout(1200);
  check('4 once the campaign is deleted, no campaign uses the audience', ctl('usage').campaigns === 0 && !ctl('campaign').title);

  check('no page errors', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));
  check('no 5xx from campaigns or saved filters', failedResponses.length === 0, failedResponses.join(' | '));
  await browser.close();
  ctl(`teardown ${setup.feature_was}`);
  fs.writeFileSync(`${out}/e2e_campaigns_results.json`, JSON.stringify(results, null, 2));
  const failed = results.filter(result => !result.ok).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch(async error => {
  console.error(error);
  if (current) await current.screenshot({ path: `${out}/campaign-failure.png` }).catch(() => {});
  try { ctl('teardown true'); } catch (_) { /* best effort */ }
  process.exit(1);
});
