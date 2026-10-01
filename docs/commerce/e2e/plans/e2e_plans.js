// Lynomia Commerce: stores on plans (docs/commerce/35-stores-on-plans.md), through the browser as a merchant's
// administrator and the super admin use them, on the production configuration (WooCommerce only; Salla, Zid and Shopify
// switched off). The stores are the disposable local WooCommerce test stores A2 and A3 with their Read keys; nothing is
// written to them.
//
// usage: node e2e_plans.js <out_dir> <keys_json>   (keys_json: {"s2":{"ck","cs"},"s3":{"ck","cs"}})
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { execSync } = require('child_process');
const fs = require('fs');

const B = 'http://localhost:3100';
const [out, keysJson] = process.argv.slice(2);
const keys = JSON.parse(keysJson);
const ERUN = process.env.ERUN;
const PASSWORD = 'Password1!x';
const results = [];
const responses = [];
const pageErrors = [];

const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  -- ${detail}` : ''}`);
};
const ctl = args => JSON.parse(execSync(`${ERUN} "bundle exec rails runner docs/commerce/e2e/plans/ctl.rb ${args} 2>/dev/null | grep '^SIM ' | tail -1"`)
  .toString().slice(4));
const clean = text => (text || '').replace(/\s+/g, ' ').trim();
const shot = (page, name) => page.screenshot({ path: `${out}/${name}.png` });

let browser;
const newPage = async (viewport = { width: 1440, height: 900 }) => {
  const page = await (await browser.newContext({ viewport })).newPage();
  page.on('pageerror', error => pageErrors.push(error.message));
  page.on('response', async response => {
    if (response.url().startsWith(B) && !response.url().includes('/vite/')) responses.push(await response.text().catch(() => ''));
  });
  return page;
};
const login = async (viewport) => {
  const page = await newPage(viewport);
  await page.goto(`${B}/app/login`, { waitUntil: 'networkidle' });
  await page.fill('input[name="email_address"]', 'admin_p@commerce.lynomia.local');
  await page.fill('input[type="password"]', PASSWORD);
  await page.keyboard.press('Enter');
  await page.waitForURL(/\/app\/accounts\/\d+/, { timeout: 60000 });
  return page;
};
const superAdminLogin = async () => {
  const page = await newPage({ width: 1440, height: 1000 });
  await page.goto(`${B}/super_admin/sign_in`, { waitUntil: 'networkidle' });
  await page.fill('input[type="email"]', 'super@commerce.lynomia.local');
  await page.fill('input[type="password"]', PASSWORD);
  await page.getByRole('button', { name: /login/i }).click();
  await page.waitForURL(url => url.pathname.startsWith('/super_admin') && !url.pathname.includes('sign_in'), { timeout: 60000 });
  return page;
};
const api = (page, url, method = 'GET', body) => page.evaluate(async ([u, m, b]) => {
  const raw = document.cookie.split('; ').find(c => c.startsWith('cw_d_session_info='));
  const info = JSON.parse(decodeURIComponent(raw.slice('cw_d_session_info='.length)));
  const response = await fetch(u, { method: m, headers: { 'access-token': info['access-token'], client: info.client, uid: info.uid,
    'Content-Type': 'application/json' }, body: b ? JSON.stringify(b) : undefined });
  return { status: response.status, body: await response.json().catch(() => null) };
}, [url, method, body]);

const settings = async (page, account) => {
  await page.goto(`${B}/app/accounts/${account}/settings/commerce`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1500);
};
const planLine = async page => clean(await page.locator('[data-test-id="commerce-store-plan"]').innerText({ timeout: 2000 }).catch(() => ''));
const addStoreButton = page => page.locator('[data-test-id="commerce-add-store"]');
const connectWoo = async (page, { url, name, ck, cs }) => {
  await addStoreButton(page).click();
  await page.waitForTimeout(600);
  await page.locator('[data-test-id="commerce-provider-woocommerce"]').click();
  await page.waitForTimeout(500);
  await page.locator('[data-test-id="commerce-store-access-read"]').click();
  await page.getByLabel(/Store URL|رابط المتجر/).fill(url);
  await page.getByLabel(/Display name|اسم العرض/).fill(name);
  await page.getByLabel('Consumer key').fill(ck);
  await page.getByLabel('Consumer secret').fill(cs);
  await page.getByRole('button', { name: /test and connect|اختبار وربط/i }).click();
  await page.waitForTimeout(4000);
};

(async () => {
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });
  const setup = ctl('setup');
  const account = setup.account_id;
  check('setup: a separate account on a manual "Commerce Starter" subscription (1 store), "Commerce Growth" (3 stores) offered',
    setup.plan === 'Commerce Starter' && setup.limits.stores === 1 && setup.connected === 0, JSON.stringify(setup));

  // ---- The merchant: which platform, which connection ----------------------------------------------------------------------
  const admin = await login();
  await settings(admin, account);
  check('Commerce settings show the plan: "Stores on your plan: 0 of 1", Add store available',
    (await planLine(admin)) === 'Stores on your plan: 0 of 1' && await addStoreButton(admin).isEnabled(), await planLine(admin));

  await addStoreButton(admin).click();
  await admin.waitForTimeout(600);
  await shot(admin, 'plans-01-picker');
  const picker = clean(await admin.locator('dialog[open]').innerText());
  const disabled = {};
  const badged = {};
  for (const provider of ['woocommerce', 'salla', 'zid', 'shopify']) {
    const option = admin.locator(`[data-test-id="commerce-provider-${provider}"]`);
    disabled[provider] = await option.isDisabled();
    badged[provider] = (await option.innerText()).includes('Not available yet');
  }
  check('Add store first asks for the platform: all four listed, each with how it connects',
    picker.includes('Choose the platform your store runs on') && picker.includes('REST API key')
      && picker.includes('Salla App Store') && picker.includes('Authorize the Lynomia app on Zid')
      && picker.includes('Lynomia Commerce app on your Shopify store'), picker);
  check('production configuration: WooCommerce can be chosen; Salla, Zid and Shopify say "Not available yet" and cannot be chosen',
    !disabled.woocommerce && disabled.salla && disabled.zid && disabled.shopify
      && !badged.woocommerce && badged.salla && badged.zid && badged.shopify, JSON.stringify({ disabled, badged }));

  await admin.locator('[data-test-id="commerce-provider-woocommerce"]').click();
  await admin.waitForTimeout(600);
  const steps = async () => clean(await admin.locator('[data-test-id="commerce-store-steps"]').innerText());
  const pressed = async value => admin.locator(`[data-test-id="commerce-store-access-${value}"]`).getAttribute('aria-pressed');
  const readWriteSteps = await steps();
  check('WooCommerce asks what Lynomia may do; Read/Write (recommended) is chosen and the steps ask for a Read/Write key',
    await pressed('read_write') === 'true' && readWriteSteps.includes('set Permissions to “Read/Write”'), readWriteSteps);
  await admin.locator('[data-test-id="commerce-store-access-read"]').click();
  await shot(admin, 'plans-02-woocommerce-access-read');
  const readSteps = await steps();
  check('choosing Read changes the steps to a Read key',
    await pressed('read') === 'true' && await pressed('read_write') === 'false' && readSteps.includes('set Permissions to “Read”'), readSteps);
  await admin.getByRole('button', { name: /test and connect/i }).scrollIntoViewIfNeeded();
  const button = await admin.getByRole('button', { name: /test and connect/i }).boundingBox();
  check('the dialog scrolls: "Test and connect" is reachable on a 900 px high screen', button && button.y + button.height <= 900,
    JSON.stringify(button));
  await admin.keyboard.press('Escape');
  await admin.waitForTimeout(500);

  // ---- The plan's limit -----------------------------------------------------------------------------------------------------
  await connectWoo(admin, { url: 'http://localhost:8083', name: 'Aleppo Soap', ...keys.s3 });
  await settings(admin, account);
  await shot(admin, 'plans-03-limit-reached');
  const reached = await planLine(admin);
  check('the first store connects; the plan is full: "1 of 1", Add store off, a note with a link to the plans',
    reached.startsWith('Stores on your plan: 1 of 1') && reached.includes('You’ve reached your plan’s store limit (1).')
      && await addStoreButton(admin).isDisabled() && await admin.getByRole('link', { name: 'View plans' }).count() === 1, reached);

  const bypass = await api(admin, `${B}/api/v1/accounts/${account}/commerce/stores`, 'POST',
    { provider: 'woocommerce', base_url: 'http://localhost:8082', consumer_key: keys.s2.ck, consumer_secret: keys.s2.cs });
  check('the server decides, not the button: an API call past the limit answers 422 STORE_LIMIT_REACHED and saves nothing',
    bypass.status === 422 && bypass.body?.error?.code === 'STORE_LIMIT_REACHED' && ctl('state').connected === 1, JSON.stringify(bypass));

  await admin.getByRole('link', { name: 'View plans' }).click();
  await admin.waitForURL(/settings\/subscription/, { timeout: 30000 });
  await admin.waitForTimeout(2000);
  await shot(admin, 'plans-04-subscription');
  const subscription = clean(await admin.locator('main, body').first().innerText());
  check('the subscription page shows Commerce stores "1 / 1" next to agents and inboxes, and each plan\'s store count',
    subscription.includes('Commerce stores 1 / 1') && subscription.includes('Commerce stores: 1') && subscription.includes('Commerce stores: 3'),
    subscription.slice(0, 400));

  // ---- The super admin -------------------------------------------------------------------------------------------------------
  const superAdmin = await superAdminLogin();
  await superAdmin.goto(`${B}/super_admin/billing_plans/${setup.plans.starter}/edit`, { waitUntil: 'networkidle' });
  const form = clean(await superAdmin.locator('form').first().innerText());
  check('Super Admin → plan: "Commerce stores" sits with Agents and Inboxes, with what it counts',
    form.includes('Agents') && form.includes('Inboxes') && form.includes('Commerce stores')
      && form.includes('disconnected stores do not count') && await superAdmin.locator('#billing_plan_limits_stores').inputValue() === '1', form.slice(0, 300));
  await superAdmin.fill('#billing_plan_limits_stores', '2');
  await superAdmin.locator('#billing_plan_limits_stores').scrollIntoViewIfNeeded();
  await shot(superAdmin, 'plans-05-super-admin-plan-form');
  await superAdmin.locator('form input[type="submit"], form button[type="submit"]').first().click();
  await superAdmin.waitForLoadState('networkidle');
  check('the super admin raises Commerce Starter to 2 stores', ctl('state').limits.stores === 2);

  await superAdmin.goto(`${B}/super_admin/billing_subscriptions/${setup.subscription_id}`, { waitUntil: 'networkidle' });
  await shot(superAdmin, 'plans-06-super-admin-subscription');
  const usage = clean(await superAdmin.locator('body').innerText());
  check('Super Admin → subscription shows the account\'s usage against its plan: "Commerce stores: 1 / 2"',
    usage.includes('Agents: 1 / 5') && usage.includes('Inboxes: 0 / 3') && usage.includes('Commerce stores: 1 / 2'), usage.slice(0, 400));

  // ---- Back to the merchant --------------------------------------------------------------------------------------------------
  await settings(admin, account);
  check('after the upgrade the merchant can add a store again: "1 of 2"',
    (await planLine(admin)) === 'Stores on your plan: 1 of 2' && await addStoreButton(admin).isEnabled(), await planLine(admin));
  await connectWoo(admin, { url: 'http://localhost:8082', name: 'Damascus Perfumes', ...keys.s2 });
  await settings(admin, account);
  check('a second store connects: "2 of 2", Add store off again',
    (await planLine(admin)).startsWith('Stores on your plan: 2 of 2') && await addStoreButton(admin).isDisabled() && ctl('state').connected === 2,
    await planLine(admin));

  const row = admin.locator('[data-test-id="commerce-store-row"]', { hasText: 'Damascus Perfumes' });
  await row.getByRole('button', { name: 'Disconnect' }).click();
  await admin.waitForTimeout(500);
  await admin.locator('dialog[open]').getByRole('button', { name: /disconnect/i }).click();
  await admin.waitForTimeout(2500);
  await settings(admin, account);
  check('a disconnected store does not count: "1 of 2", Add store available',
    (await planLine(admin)) === 'Stores on your plan: 1 of 2' && await addStoreButton(admin).isEnabled(), await planLine(admin));

  ctl('stripe_price starter off');
  await admin.goto(`${B}/app/accounts/${account}/settings/subscription`, { waitUntil: 'networkidle' });
  await admin.waitForTimeout(2000);
  const granted = clean(await admin.locator('body').innerText());
  check('a plan granted without a Stripe price still shows its own limits to the merchant (not "Unlimited")',
    granted.includes('Agents 1 / 5') && granted.includes('Inboxes 0 / 3') && granted.includes('Commerce stores 1 / 2'), granted.slice(0, 400));

  // ---- Arabic and mobile -----------------------------------------------------------------------------------------------------
  await api(admin, `${B}/api/v1/accounts/${account}`, 'PATCH', { locale: 'ar' });
  const mobile = await login({ width: 390, height: 844 });
  await settings(mobile, account);
  await mobile.locator('[data-test-id="commerce-add-store"]').click();
  await mobile.waitForTimeout(600);
  await shot(mobile, 'plans-07-ar-mobile-picker');
  const arPicker = clean(await mobile.locator('dialog[open]').innerText());
  check('Arabic, 390 px: the platform picker in Arabic', arPicker.includes('اختر المنصة') && arPicker.includes('غير متاح بعد'), arPicker.slice(0, 200));
  await mobile.locator('[data-test-id="commerce-provider-woocommerce"]').click();
  await mobile.waitForTimeout(600);
  await shot(mobile, 'plans-08-ar-mobile-woocommerce');
  await mobile.getByRole('button', { name: /اختبار وربط/ }).scrollIntoViewIfNeeded();
  const arButton = await mobile.getByRole('button', { name: /اختبار وربط/ }).boundingBox();
  check('Arabic, 390 px: the WooCommerce dialog asks for the access and scrolls to "Test and connect"',
    clean(await mobile.locator('[data-test-id="commerce-store-steps"]').innerText()).includes('قراءة/كتابة') && arButton && arButton.y + arButton.height <= 844);
  await api(admin, `${B}/api/v1/accounts/${account}`, 'PATCH', { locale: 'en' });

  // ---- Safety ------------------------------------------------------------------------------------------------------------------
  const secrets = [keys.s2.ck, keys.s2.cs, keys.s3.ck, keys.s3.cs];
  check('no consumer key or secret in any response the browser received', !responses.some(body => secrets.some(secret => body.includes(secret))),
    `responses=${responses.length}`);
  check('no uncaught page errors', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));

  const teardown = ctl('teardown');
  check('teardown: the account, its stores and both plans removed', !teardown.account && teardown.plans === 0, JSON.stringify(teardown));
  await browser.close();
  fs.writeFileSync(`${out}/plans_e2e_results.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed`);
})().catch(async error => {
  console.log(`ERROR ${error.message}`);
  fs.writeFileSync(`${out}/plans_e2e_results.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed (aborted)`);
  if (browser) await browser.close();
  process.exit(1);
});
