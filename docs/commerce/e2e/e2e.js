// Lynomia Commerce real WooCommerce E2E (docs/commerce/09-woocommerce-e2e.md).
// usage: node e2e.js <out_dir> <keys_json>   (keys_json: {"s1":{"ck","cs"},"s2":…,"s3":…})
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { execSync } = require('child_process');
const fs = require('fs');

const B = 'http://localhost:3100';
const E = __dirname; // erun.sh: runs a command in the Rails image with the E2E environment (e2e.env)
const [out, keysJson] = process.argv.slice(2);
const keys = JSON.parse(keysJson);
const secrets = Object.values(keys).flatMap(k => [k.ck, k.cs]);
const results = [];
const apiBodies = [];
const pageErrors = [];

const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  -- ${detail}` : ''}`);
};
const rails = args => execSync(`${E}/erun.sh "bundle exec rails runner ${args} 2>/dev/null | tail -1"`).toString().trim();

let browser;
const newPage = async (email, viewport = { width: 1440, height: 1500 }) => {
  const context = await browser.newContext({ viewport });
  // Since Phase 7–8 the Commerce section may open on Customer 360; these checks are about the store view, the agent's
  // saved choice here (docs/commerce/27-phase7-8-e2e.md §4).
  await context.addInitScript(() => {
    try {
      window.localStorage.setItem('lynomia.commerce.view', 'store');
    } catch {
      // documents without storage (about:blank, other origins)
    }
  });
  const page = await context.newPage();
  page.on('pageerror', e => pageErrors.push(`${email}: ${e.message}`));
  page.on('response', async r => {
    if (r.url().includes('/api/')) apiBodies.push({ url: r.url(), body: await r.text().catch(() => '') });
  });
  await page.goto(`${B}/app/login`, { waitUntil: 'networkidle' });
  await page.fill('input[name="email_address"], input[type="email"]', email);
  await page.fill('input[type="password"]', 'Password1!x');
  await page.keyboard.press('Enter');
  await page.waitForURL(/\/app\/accounts\/\d+/, { timeout: 60000 });
  return page;
};
const shot = (page, name) => page.screenshot({ path: `${out}/${name}.png` });
const panel = page => page.locator('[data-test-id="commerce-panel"]');
const panelText = async page => (await panel(page).innerText().catch(() => '')).replace(/\s+/g, ' ');
const openConversation = async (page, account, id) => {
  await page.goto(`${B}/app/accounts/${account}/conversations/${id}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(3500);
};
const addStore = async (page, { url, name, ck, cs }) => {
  await page.getByRole('button', { name: /add store|إضافة متجر/i }).click();
  await page.waitForTimeout(600);
  await page.getByLabel(/Store URL|رابط المتجر/).fill(url);
  if (name) await page.getByLabel(/Display name|اسم العرض/).fill(name);
  await page.getByLabel('Consumer key').fill(ck);
  await page.getByLabel('Consumer secret').fill(cs);
  await page.getByRole('button', { name: /test and connect|اختبار وربط/i }).click();
  await page.waitForTimeout(4000);
};
const dialogError = async page => (await page.locator('[data-test-id="commerce-store-error"]').innerText().catch(() => '')).trim();
const cancelDialog = async page => {
  await page.getByRole('button', { name: /^cancel$/i }).click();
  await page.waitForTimeout(500);
};

(async () => {
  console.log(rails('docs/commerce/e2e/rails/reset.rb'));
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });

  // ---- A. Administrator of account A connects stores through the UI --------------------------------------------------
  const adminA = await newPage('admin_a@commerce.lynomia.local', { width: 1440, height: 900 });
  await adminA.goto(`${B}/app/accounts/1/settings/commerce`, { waitUntil: 'networkidle' });
  await adminA.waitForTimeout(1200);
  await shot(adminA, '01-settings-no-stores');
  check('settings: no stores state', (await adminA.innerText('body')).includes('No store connected yet.'));

  await addStore(adminA, { url: 'http://localhost:8081', ck: keys.s1.ck, cs: 'cs_0000000000000000000000000000000000000000' });
  await shot(adminA, '02-connect-wrong-secret');
  check('connect refused with a wrong secret (AUTH_INVALID)', (await dialogError(adminA)).includes("rejected Lynomia's credentials"), await dialogError(adminA));
  await cancelDialog(adminA);

  await addStore(adminA, { url: 'https://10.0.0.5', ck: keys.s1.ck, cs: keys.s1.cs });
  check('connect refused for an IP address URL', (await dialogError(adminA)).includes('not an IP address'), await dialogError(adminA));
  await cancelDialog(adminA);
  await addStore(adminA, { url: 'http://shop.example.com', ck: keys.s1.ck, cs: keys.s1.cs });
  check('connect refused for plain http (untrusted host)', (await dialogError(adminA)).includes('must use https'), await dialogError(adminA));
  await cancelDialog(adminA);
  await addStore(adminA, { url: 'https://localtest.me', ck: keys.s1.ck, cs: keys.s1.cs });
  await shot(adminA, '03-connect-private-dns');
  check('connect refused for a public name resolving to loopback (or unresolvable here)',
    /private network|not reachable/.test(await dialogError(adminA)), await dialogError(adminA));
  await cancelDialog(adminA);

  await addStore(adminA, { url: 'http://localhost:8081', name: 'Syria Cosmetics', ck: keys.s1.ck, cs: keys.s1.cs });
  await addStore(adminA, { url: 'http://localhost:8082', name: 'Damascus Perfumes', ck: keys.s2.ck, cs: keys.s2.cs });
  await shot(adminA, '04-settings-two-stores');
  const settingsText = await adminA.innerText('body');
  check('A1 and A2 connected and active', settingsText.includes('Syria Cosmetics') && settingsText.includes('Damascus Perfumes')
    && (settingsText.match(/Active/g) || []).length >= 2);

  // ---- B. Account B connects its own store; A1 cannot be claimed -----------------------------------------------------
  const adminB = await newPage('admin_b@commerce.lynomia.local', { width: 1440, height: 900 });
  await adminB.goto(`${B}/app/accounts/2/settings/commerce`, { waitUntil: 'networkidle' });
  await adminB.waitForTimeout(1000);
  await addStore(adminB, { url: 'http://localhost:8081', ck: keys.s1.ck, cs: keys.s1.cs });
  await shot(adminB, '05-account-b-cannot-claim-a1');
  check('account B cannot connect store A1 (already connected)', (await dialogError(adminB)).includes('already connected'), await dialogError(adminB));
  await cancelDialog(adminB);
  await addStore(adminB, { url: 'http://localhost:8083', name: 'Aleppo Soap', ck: keys.s3.ck, cs: keys.s3.cs });
  check('account B connected B1', (await adminB.innerText('body')).includes('Aleppo Soap'));

  // ---- C. Agent A in conversations --------------------------------------------------------------------------------------
  const agentA = await newPage('agent_a@commerce.lynomia.local');
  await openConversation(agentA, 1, 1);
  await shot(agentA, '06-whatsapp-verified-phone-guest');
  let text = await panelText(agentA);
  check('WhatsApp phone auto-links the guest (0551112233 stored locally in Woo)', text.includes('Matched by the verified phone')
    && text.includes('Omar Khalil') && ['#25', '#24', '#23'].every(n => text.includes(n)), text.slice(0, 200));
  check('payment statuses: failed / paid (virtual, no shipping) / unpaid', text.includes('Payment failed') && text.includes('Paid') && text.includes('Unpaid'));

  await openConversation(agentA, 1, 2);
  await shot(agentA, '07-registered-five-orders-store-a1');
  text = await panelText(agentA);
  const orderCount = await agentA.locator('[data-test-id="commerce-order"]').count();
  check('registered customer: latest 5 of 7 orders, never "paid" without evidence', orderCount === 5 && text.includes('#22')
    && !text.includes('#15') && text.includes('Payment not confirmed') && text.includes('Partially refunded') && text.includes('Refunded'), `orders=${orderCount}`);
  check('store selector present with two stores', await panel(agentA).locator('select').count() === 1);
  const viewOrder = await panel(agentA).locator('a', { hasText: 'View order' }).first().getAttribute('href');
  check('View order = trusted store URL + numeric id', viewOrder === 'http://localhost:8081/wp-admin/admin.php?action=edit&id=22&page=wc-orders', viewOrder);
  check('no tracking controls (WooCommerce core has no tracking; plugin meta ignored)', !text.includes('Track shipment') && !text.includes('Send tracking'));

  await panel(agentA).locator('select').selectOption({ label: 'Damascus Perfumes' });
  await agentA.waitForTimeout(3500);
  await shot(agentA, '08-registered-store-a2');
  text = await panelText(agentA);
  check('switching to A2 shows only A2 orders', text.includes('#12') && text.includes('#11') && !text.includes('#22')
    && await agentA.locator('[data-test-id="commerce-order"]').count() === 2);

  await openConversation(agentA, 1, 3);
  await shot(agentA, '09-duplicate-phone-manual-selection');
  text = await panelText(agentA);
  check('duplicate phone: both customers offered, masked, nothing linked', text.includes('Several store customers match')
    && text.includes('Sara Ali') && text.includes('Noor Ali') && text.includes('+966*******11') && !text.includes('550000111'));
  const saraRow = panel(agentA).locator('li', { hasText: 'Sara Ali' });
  await saraRow.getByRole('button', { name: 'Link' }).click();
  await agentA.waitForTimeout(3500);
  await shot(agentA, '10-duplicate-phone-linked');
  text = await panelText(agentA);
  check('agent picks Sara: linked manually with her order', text.includes('Linked by Agent A') && text.includes('#26'));

  await openConversation(agentA, 1, 4);
  await shot(agentA, '11-email-suggestion');
  text = await panelText(agentA);
  check('widget contact email only suggests (no auto-link)', text.includes('Possible match') && text.includes('منى صالح') && text.includes('mo***@example.com'));
  await panel(agentA).getByRole('button', { name: 'Link', exact: true }).click();
  await agentA.waitForTimeout(3500);
  await shot(agentA, '12-linked-no-orders');
  check('linked customer without orders', (await panelText(agentA)).includes('No orders yet.'));

  await openConversation(agentA, 1, 6);
  await shot(agentA, '13-duplicate-email');
  text = await panelText(agentA);
  check('duplicate billing email: two candidates', text.includes('Several store customers match') && text.includes('Hana Saeed') && text.includes('Rami Saeed'));

  await openConversation(agentA, 1, 7);
  await shot(agentA, '14-not-found');
  text = await panelText(agentA);
  check('not found state with link action', text.includes('Customer not found in this store') && /link customer/i.test(text));
  await panel(agentA).getByRole('button', { name: 'Link customer' }).click();
  await panel(agentA).locator('input').fill('Omar Khalil');
  await panel(agentA).getByRole('button', { name: 'Search' }).click();
  await agentA.waitForTimeout(1500);
  check('search by name refused', (await panelText(agentA)).includes('Enter an exact email'));
  await panel(agentA).locator('input').fill('+966551112233');
  await panel(agentA).getByRole('button', { name: 'Search' }).click();
  await agentA.waitForTimeout(3000);
  await shot(agentA, '15-manual-search');
  text = await panelText(agentA);
  check('manual search by international phone finds the guest', text.includes('Omar Khalil') && text.includes('Guest checkout'));

  // ---- D. Store down: stale fallback and unavailable ---------------------------------------------------------------------
  execSync('docker stop woo-wp >/dev/null');
  console.log('store 1 stopped; waiting past the 120 s fresh window');
  await agentA.waitForTimeout(125000);
  await openConversation(agentA, 1, 2);
  await shot(agentA, '16-store-down-stale');
  text = await panelText(agentA);
  check('store down: last fetched orders shown as stale with their age', text.includes("Couldn't refresh store data right now.")
    && /Last updated \d+ minutes? ago/.test(text) && text.includes('#22'), text.slice(0, 160));
  await openConversation(agentA, 1, 5);
  await shot(agentA, '17-store-down-nothing-cached');
  text = await panelText(agentA);
  check('store down with nothing cached: safe message only', text.includes('not reachable') && !/Errno|Faraday|Net::|exception/i.test(text), text.slice(0, 160));
  execSync('docker start woo-wp >/dev/null');
  await agentA.waitForTimeout(5000);

  // ---- E. Arabic ------------------------------------------------------------------------------------------------------
  console.log(rails('docs/commerce/e2e/rails/set.rb 1 locale=ar'));
  await openConversation(agentA, 1, 2);
  await agentA.waitForTimeout(1500);
  await shot(agentA, '18-arabic-linked-orders');
  text = await panelText(agentA);
  check('Arabic: panel title and order labels', (await agentA.innerText('body')).includes('المتجر') && text.includes('العميل المربوط') && text.includes('مسترد جزئيًا'));
  await openConversation(agentA, 1, 7);
  await shot(agentA, '19-arabic-not-found');
  text = await panelText(agentA);
  check('Arabic: not found + link customer', text.includes('لم يتم العثور على العميل في هذا المتجر') && text.includes('ربط العميل'));
  await adminA.goto(`${B}/app/accounts/1/settings/commerce`, { waitUntil: 'networkidle' });
  await adminA.waitForTimeout(1500);
  await shot(adminA, '20-arabic-settings');

  // ---- F. Mobile ------------------------------------------------------------------------------------------------------
  const mobile = await newPage('agent_a@commerce.lynomia.local', { width: 390, height: 844 });
  await openConversation(mobile, 1, 2);
  await shot(mobile, '21-mobile-arabic');
  // Only the Commerce panel is measured: in RTL the stock off-canvas sidebar already widens the page (also on the dashboard).
  const outside = await mobile.evaluate(() => [...document.querySelectorAll('[data-test-id="commerce-panel"] *')]
    .filter(el => el.getBoundingClientRect().right > window.innerWidth + 1 || el.getBoundingClientRect().left < -1).length);
  check('mobile (Arabic): panel renders inside the viewport', (await panelText(mobile)).includes('#22') && outside === 0, `elements outside=${outside}`);
  console.log(rails('docs/commerce/e2e/rails/set.rb 1 locale=en'));
  await mobile.reload({ waitUntil: 'networkidle' });
  await mobile.waitForTimeout(3500);
  await shot(mobile, '22-mobile-english');
  const outsideEn = await mobile.evaluate(() => [...document.querySelectorAll('[data-test-id="commerce-panel"] *')]
    .filter(el => el.getBoundingClientRect().right > window.innerWidth + 1 || el.getBoundingClientRect().left < -1).length);
  const pageOverflowEn = await mobile.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  check('mobile (English): panel inside the viewport, no page overflow', outsideEn === 0 && !pageOverflowEn);

  // ---- G. Agent without access, and feature off ----------------------------------------------------------------------
  const outsider = await newPage('outsider_a@commerce.lynomia.local', { width: 1440, height: 900 });
  await openConversation(outsider, 1, 2);
  check('agent without inbox access sees no store data', !(await panelText(outsider)).includes('#22'));

  console.log(rails('docs/commerce/e2e/rails/set.rb 1 feature=off'));
  await openConversation(agentA, 1, 2);
  await shot(agentA, '23-feature-off-conversation');
  check('feature off: no Commerce section', (await panel(agentA).count()) === 0 && !(await agentA.innerText('body')).includes('Linked customer'));
  await adminA.goto(`${B}/app/accounts/1/settings/commerce`, { waitUntil: 'networkidle' });
  await adminA.waitForTimeout(1500);
  await shot(adminA, '24-feature-off-settings');
  const nav = await adminA.locator('aside').first().innerText();
  check('feature off: no Commerce in settings navigation', !nav.includes('Commerce'));
  console.log(rails('docs/commerce/e2e/rails/set.rb 1 feature=on'));

  // ---- G2. Store and link lifecycle (audited) --------------------------------------------------------------------------
  await adminA.goto(`${B}/app/accounts/1/settings/commerce`, { waitUntil: 'networkidle' });
  await adminA.waitForTimeout(1500);
  const row = () => adminA.locator('[data-test-id="commerce-store-row"]', { hasText: 'Damascus Perfumes' });
  await row().getByRole('button', { name: 'Disable' }).click();
  await adminA.waitForTimeout(2000);
  check('admin disables A2', (await row().innerText()).includes('Disabled'));
  await openConversation(agentA, 1, 2);
  check('disabled store leaves the agent store list', await panel(agentA).locator('select').count() === 0 && !(await panelText(agentA)).includes('Damascus'));
  await row().getByRole('button', { name: 'Enable' }).click();
  await adminA.waitForTimeout(3000);
  check('admin re-enables A2 after a fresh health check', (await row().innerText()).includes('Active'));
  await row().getByRole('button', { name: 'Replace keys' }).click();
  await adminA.waitForTimeout(600);
  await adminA.getByLabel('Consumer key').fill(keys.s2.ck);
  await adminA.getByLabel('Consumer secret').fill(keys.s2.cs);
  await adminA.getByRole('button', { name: /test and save/i }).click();
  await adminA.waitForTimeout(3500);
  check('admin replaces A2 keys (health-checked)', (await row().innerText()).includes('Active') && !(await adminA.locator('dialog[open]').count()));
  await row().getByRole('button', { name: 'Disconnect' }).click();
  await adminA.waitForTimeout(600);
  await shot(adminA, '25-disconnect-confirm');
  await adminA.locator('dialog[open]').getByRole('button', { name: /disconnect/i }).click();
  await adminA.waitForTimeout(2500);
  await shot(adminA, '26-settings-after-lifecycle');
  check('admin disconnects A2', (await row().innerText()).includes('Disconnected') && (await row().innerText()).includes('Reconnect'));

  await openConversation(agentA, 1, 3);
  await panel(agentA).getByRole('button', { name: 'Change' }).click();
  await panel(agentA).locator('input').fill('+966550000111');
  await panel(agentA).getByRole('button', { name: 'Search' }).click();
  await agentA.waitForTimeout(3000);
  await panel(agentA).locator('li', { hasText: 'Noor Ali' }).getByRole('button', { name: 'Link' }).click();
  await agentA.waitForTimeout(3500);
  text = await panelText(agentA);
  check('agent changes the link to Noor (her order shown)', text.includes('#27') && !text.includes('#26'));
  await openConversation(agentA, 1, 4);
  await panel(agentA).getByRole('button', { name: 'Unlink' }).click();
  await agentA.waitForTimeout(3500);
  check('agent unlinks Mona: back to a suggestion', (await panelText(agentA)).includes('Possible match'));
  console.log(rails('docs/commerce/e2e/rails/audit.rb'));

  // ---- H. Nothing secret reached the browser -------------------------------------------------------------------------
  const leaked = apiBodies.filter(({ body }) => secrets.some(secret => body.includes(secret)) || body.includes('"credentials"'));
  check('no consumer key/secret or credentials field in any API response', leaked.length === 0, `responses=${apiBodies.length} leaked=${leaked.map(l => l.url).join(',')}`);
  check('no uncaught page errors', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));

  fs.writeFileSync(`${out}/e2e_results.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed`);
  await browser.close();
})().catch(async error => {
  console.error(error);
  execSync('docker start woo-wp >/dev/null 2>&1 || true');
  fs.writeFileSync(`${out}/e2e_results.json`, JSON.stringify(results, null, 2));
  process.exit(1);
});
