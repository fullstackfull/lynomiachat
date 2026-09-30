// Lynomia Commerce Salla E2E with a simulated Salla (docs/commerce/13-salla-e2e.md).
// usage: E2E_SALLA_WEBHOOK_SECRET=… node e2e_salla.js <out_dir>
//
// Real: the Lynomia app (production build), its webhook endpoint, signature checks, Sidekiq queueing, Postgres, Redis,
// the browser UI and the WooCommerce stores next to Salla. Simulated: Salla itself. Its signed events are built here
// from Salla's documented payloads and signed with the installation's webhook secret, and its API answers come from
// sim.rb (WebMock, documented shapes).
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/opt/node22/lib/node_modules/playwright');
const { execSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const B = 'http://localhost:3100';
const REPO = path.resolve(__dirname, '../../../..');
const ERUN = process.env.ERUN;
const [out] = process.argv.slice(2);
const SECRET = process.env.E2E_SALLA_WEBHOOK_SECRET;
const M1 = 1234509876;
const M2 = 1234509877;
const TOKENS = ['e2e-access-m1', 'e2e-refresh-m1', 'e2e-access-m1-new', 'e2e-refresh-m1-new', 'e2e-access-m2', 'e2e-refresh-m2',
  'e2e-access-m1-refreshed', 'e2e-refresh-m1-refreshed', SECRET, process.env.E2E_SALLA_CLIENT_SECRET];
const results = [];
const apiBodies = [];
const pageErrors = [];
const codes = [];

const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  -- ${detail}` : ''}`);
};
const sim = args => JSON.parse(execSync(`${ERUN} "bundle exec rails runner docs/commerce/e2e/salla/sim.rb ${args} 2>/dev/null | grep '^SIM ' | tail -1 | cut -c5-"`).toString().trim());
const rails = args => execSync(`${ERUN} "bundle exec rails runner ${args} 2>/dev/null | tail -1"`).toString().trim();
const fixture = name => JSON.parse(fs.readFileSync(`${REPO}/spec/fixtures/files/commerce/salla/${name}`, 'utf8'));

// A Salla app event, as Salla delivers it: raw JSON body + X-Salla-Signature (hex HMAC-SHA256 of the body).
const deliver = async (payload, { signature, strategy = 'Signature', body } = {}) => {
  const raw = body ?? JSON.stringify(payload);
  const headers = { 'Content-Type': 'application/json' };
  if (strategy) headers['X-Salla-Security-Strategy'] = strategy;
  const sig = signature === undefined ? crypto.createHmac('sha256', SECRET).update(raw).digest('hex') : signature;
  if (sig) headers['X-Salla-Signature'] = sig;
  const response = await fetch(`${B}/webhooks/salla`, { method: 'POST', headers, body: raw });
  return response.status;
};
const authorize = (merchant, access, refresh) => {
  const event = fixture('app_store_authorize.json');
  event.merchant = merchant;
  event.created_at = new Date().toISOString();
  Object.assign(event.data, { access_token: access, refresh_token: refresh, expires: Math.floor(Date.now() / 1000) + 14 * 86400 });
  return event;
};
const settings = (merchant, code) => {
  const event = fixture('app_settings_updated.json');
  event.merchant = merchant;
  event.created_at = new Date().toISOString();
  event.data.settings.lynomia_connection_code = code;
  return event;
};
const uninstalled = merchant => ({ ...fixture('app_uninstalled.json'), merchant, created_at: new Date().toISOString() });

let browser;
const newPage = async (email, { viewport = { width: 1440, height: 1500 }, superAdmin = false } = {}) => {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  page.on('pageerror', e => pageErrors.push(`${email}: ${e.message}`));
  page.on('response', async r => {
    if (r.url().includes('/api/') || r.url().includes('/super_admin')) apiBodies.push({ url: r.url(), body: await r.text().catch(() => '') });
  });
  if (superAdmin) {
    await page.goto(`${B}/super_admin/sign_in`, { waitUntil: 'networkidle' });
    await page.fill('input[type="email"]', email);
    await page.fill('input[type="password"]', 'Password1!x');
    await page.getByRole('button', { name: /login/i }).click();
    await page.waitForURL(url => url.pathname.startsWith('/super_admin') && !url.pathname.includes('sign_in'), { timeout: 60000 });
    return page;
  }
  await page.goto(`${B}/app/login`, { waitUntil: 'networkidle' });
  await page.fill('input[name="email_address"], input[type="email"]', email);
  await page.fill('input[type="password"]', 'Password1!x');
  await page.keyboard.press('Enter');
  await page.waitForURL(/\/app\/accounts\/\d+/, { timeout: 60000 });
  return page;
};
const shot = (page, name) => page.screenshot({ path: `${out}/${name}.png` });
const settingsPage = async (page, account) => {
  await page.goto(`${B}/app/accounts/${account}/settings/commerce`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1500);
};
const openConversation = async (page, account, id) => {
  await page.goto(`${B}/app/accounts/${account}/conversations/${id}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(3500);
};
const panel = page => page.locator('[data-test-id="commerce-panel"]');
const panelText = async page => (await panel(page).innerText().catch(() => '')).replace(/\s+/g, ' ');
const selectStore = async (page, name) => {
  await panel(page).locator('select').selectOption({ label: name });
  await page.waitForTimeout(3000);
};
const openSallaDialog = async page => {
  await page.getByRole('button', { name: /add store|إضافة متجر/i }).click();
  await page.waitForTimeout(600);
  await page.locator('[data-test-id="commerce-provider-salla"]').click();
  await page.waitForTimeout(600);
};
const createCode = async page => {
  await page.locator('[data-test-id="salla-create-code"]').click();
  await page.waitForTimeout(1500);
  const code = (await page.locator('[data-test-id="salla-connection-code"]').innerText()).trim();
  codes.push(code);
  return code;
};
const dialogStatus = async page => (await page.locator('[data-test-id="salla-connection-status"]').innerText().catch(() => '')).trim();
const storeRow = (page, name) => page.locator('[data-test-id="commerce-store-row"]', { hasText: name });
// An API call with the page's own session (the dashboard keeps its auth headers in the cw_d_session_info cookie).
const api = (page, url, method = 'GET') => page.evaluate(async ([u, m]) => {
  const raw = document.cookie.split('; ').find(c => c.startsWith('cw_d_session_info='));
  const info = JSON.parse(decodeURIComponent(raw.slice('cw_d_session_info='.length)));
  const response = await fetch(u, { method: m, headers: { 'access-token': info['access-token'], client: info.client, uid: info.uid } });
  return { status: response.status, body: await response.json().catch(() => null) };
}, [url, method]);
const stores = async (page, account, conversation) => (await api(page, `/api/v1/accounts/${account}/conversations/${conversation}/commerce/stores`)).body;

(async () => {
  console.log(sim('configure on'), sim('reset'), sim('super_admin'));
  console.log(rails(`'Account.find(1).update!(locale: :en); Account.find(2).update!(locale: :en); puts :ok'`));
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });

  // ---- A. Super Admin: the Salla app settings ---------------------------------------------------------------------
  const superAdmin = await newPage('super@commerce.lynomia.local', { superAdmin: true });
  await superAdmin.goto(`${B}/super_admin/app_config?config=salla`, { waitUntil: 'networkidle' });
  const superHtml = await superAdmin.content();
  await shot(superAdmin, 'salla-01-super-admin');
  check('Super Admin shows the Salla fields with the secrets masked and empty',
    ['SALLA_ENABLED', 'SALLA_APP_ID', 'SALLA_CLIENT_ID', 'SALLA_CLIENT_SECRET', 'SALLA_WEBHOOK_SECRET'].every(f => superHtml.includes(`app_config[${f}]`))
      && superHtml.includes('type="password"') && !superHtml.includes(SECRET) && !superHtml.includes(process.env.E2E_SALLA_CLIENT_SECRET));

  // ---- B. Account admin connects Salla -----------------------------------------------------------------------------
  const adminA = await newPage('admin_a@commerce.lynomia.local');
  await settingsPage(adminA, 1);
  await adminA.getByRole('button', { name: /add store/i }).click();
  await adminA.waitForTimeout(700);
  await shot(adminA, 'salla-02-provider-picker');
  check('Add store offers WooCommerce and Salla',
    await adminA.locator('[data-test-id="commerce-provider-woocommerce"]').count() === 1 && await adminA.locator('[data-test-id="commerce-provider-salla"]').count() === 1);
  await adminA.locator('[data-test-id="commerce-provider-salla"]').click();
  await adminA.waitForTimeout(600);
  const code = await createCode(adminA);
  await shot(adminA, 'salla-03-connection-code');
  const installHref = await adminA.locator('[data-test-id="salla-install-link"]').getAttribute('href');
  check('one-time code shown with the official install link, nothing secret asked', /^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$/.test(code)
    && installHref === 'https://s.salla.sa/apps/install/1234567890' && await adminA.locator('dialog[open] input').count() === 0, code);

  // ---- C. Webhook signature over HTTP --------------------------------------------------------------------------------
  const event = authorize(M1, 'e2e-access-m1', 'e2e-refresh-m1');
  const raw = JSON.stringify(event);
  const statuses = {
    unsigned: await deliver(event, { signature: null }),
    badSignature: await deliver(event, { signature: 'a'.repeat(64) }),
    otherSecret: await deliver(event, { signature: crypto.createHmac('sha256', 'not-the-secret').update(raw).digest('hex') }),
    tokenStrategy: await deliver(event, { strategy: 'Token' }),
    modifiedBody: await deliver(event, { body: raw.replace('e2e-access-m1', 'e2e-access-mX'), signature: crypto.createHmac('sha256', SECRET).update(raw).digest('hex') })
  };
  check('unsigned, badly signed, wrong-secret, token-strategy and modified deliveries get 401',
    Object.values(statuses).every(status => status === 401), JSON.stringify(statuses));
  check('nothing was queued for refused deliveries', sim('queue').queued === 0);
  const firstDelivery = await deliver(event, { body: raw });
  const redelivery = await deliver(event, { body: raw });
  check('a signed authorization is accepted, and its redelivery is queued once',
    firstDelivery === 200 && redelivery === 200 && sim('queue').queued === 1);
  console.log(sim('jobs'));
  check('an authorization alone connects nothing (no account is ever guessed)', sim('state').stores.length === 0
    && (await dialogStatus(adminA)).includes('Waiting'));

  // ---- D. The merchant enters the code in the app settings in Salla ------------------------------------------------
  check('signed app.settings.updated accepted', await deliver(settings(M1, code)) === 200);
  console.log(sim('jobs'));
  await adminA.waitForTimeout(6500);
  await shot(adminA, 'salla-04-connected-list');
  let state = sim('state');
  const store1 = state.stores[0];
  check('store connected to account A by the code: merchant id, Salla name, credentials stored',
    state.stores.length === 1 && store1.account_id === 1 && store1.external_store_id === String(M1) && store1.status === 'active'
      && JSON.stringify(store1.credential_fields) === JSON.stringify(['access_token', 'refresh_token', 'token_type', 'scope', 'access_token_expires_at', 'refresh_token_expires_at']),
    JSON.stringify(store1));
  check('settings list shows the Salla store as active, without key actions',
    (await storeRow(adminA, 'متجر الورد').innerText()).includes('Salla') && (await storeRow(adminA, 'متجر الورد').innerText()).includes('Active')
      && await storeRow(adminA, 'متجر الورد').getByRole('button', { name: /replace keys/i }).count() === 0);
  await deliver(authorize(M1, 'e2e-access-m1', 'e2e-refresh-m1'));
  console.log(sim('jobs'));
  check('a later authorization for the same merchant creates no second store', sim('state').stores.length === 1);

  // ---- E. Another account cannot take the store ----------------------------------------------------------------------
  const adminB = await newPage('admin_b@commerce.lynomia.local');
  await settingsPage(adminB, 2);
  await openSallaDialog(adminB);
  const codeB = await createCode(adminB);
  await deliver(settings(M1, codeB));
  console.log(sim('jobs'));
  await adminB.waitForTimeout(6500);
  await shot(adminB, 'salla-05-conflict');
  state = sim('state');
  check('a code from account B for A\'s store is a conflict; the store stays with A',
    (await dialogStatus(adminB)).includes('another Lynomia account') && state.stores.length === 1 && state.stores[0].account_id === 1);

  // ---- F. The conversation panel with Salla next to WooCommerce ----------------------------------------------------
  console.log(sim(`warm ${store1.id} 1 3 2 7`));
  const agentA = await newPage('agent_a@commerce.lynomia.local');
  await openConversation(agentA, 1, 1);
  const list = await stores(agentA, 1, 1);
  check('the conversation lists WooCommerce and Salla stores', list.payload.some(s => s.provider === 'salla') && list.payload.some(s => s.provider === 'woocommerce'),
    list.payload.map(s => `${s.provider}:${s.name}`).join(', '));
  await selectStore(agentA, 'متجر الورد');
  let text = await panelText(agentA);
  await shot(agentA, 'salla-06-panel-orders-en');
  check('Salla customer linked by the verified WhatsApp phone, latest orders newest first',
    text.includes('Omar Khalil') && text.includes('verified phone') && text.indexOf('#30013') < text.indexOf('#30012'), text.slice(0, 200));
  check('shipped order: carriers, shipment status, Track shipment and Send tracking',
    text.includes('Aramex, SMSA') && text.includes('In transit') && text.includes('Track shipment') && text.includes('Send tracking'));
  check('payment: unpaid only when Salla says so, otherwise "Payment not confirmed"', text.includes('Unpaid') && text.includes('Payment not confirmed'));
  const order30011 = await panel(agentA).locator('[data-test-id="commerce-order"]', { hasText: '#30011' }).innerText();
  check('an order whose shipment is not trackable shows no tracking actions', !order30011.includes('Track shipment') && !order30011.includes('Send tracking'), order30011.replace(/\s+/g, ' '));
  const trackHref = await panel(agentA).locator('[data-test-id="commerce-order"]', { hasText: '#30012' }).getByRole('link', { name: 'Track shipment' }).getAttribute('href');
  const viewHref = await panel(agentA).locator('[data-test-id="commerce-order"]', { hasText: '#30012' }).getByRole('link', { name: 'View order' }).getAttribute('href');
  check('tracking and admin links are Salla\'s https links', trackHref.startsWith('https://www.aramex.com/') && viewHref.startsWith('https://s.salla.sa/'), `${trackHref} ${viewHref}`);
  await panel(agentA).locator('[data-test-id="commerce-order"]', { hasText: '#30012' }).getByRole('button', { name: 'Send tracking' }).click();
  await agentA.waitForTimeout(800);
  const editor = await agentA.locator('.ProseMirror').first().innerText().catch(() => '');
  check('Send tracking puts the tracking message in the reply box (nothing sent)', editor.includes('AX123456789SA'), editor.slice(0, 120));
  await openConversation(agentA, 1, 3);
  await selectStore(agentA, 'متجر الورد');
  text = await panelText(agentA);
  await shot(agentA, 'salla-07-multiple-matches');
  check('two Salla customers share the phone: both offered, nothing linked', text.includes('Sara Ali') && text.includes('Noor Ali') && !text.includes('Unlink'));
  await openConversation(agentA, 1, 7);
  await selectStore(agentA, 'متجر الورد');
  text = await panelText(agentA);
  await shot(agentA, 'salla-08-not-found');
  check('no Salla customer for the contact: not found + Link customer', text.includes('Customer not found in this store') && /link customer/i.test(text), text.slice(0, 160));

  // ---- G. Failures: stale cache, rate limit, needs re-authorization ------------------------------------------------
  // This sandbox's egress answers every request to api.salla.dev with "403 Host not in allowlist", so an expired cache
  // entry makes the panel meet a real refusal: it must show the error, not pass old orders off as current.
  console.log(sim(`age ${store1.id}`));
  await openConversation(agentA, 1, 1);
  await selectStore(agentA, 'متجر الورد');
  text = await panelText(agentA);
  await shot(agentA, 'salla-09-access-refused');
  check('Salla refuses access (sandbox 403): the error is shown and no orders are presented as current',
    text.includes('refused access') && !text.includes('#30013'), text.slice(0, 200));
  console.log(sim(`warm ${store1.id} 1`), sim(`age ${store1.id}`), sim(`backoff ${M1}`));
  await openConversation(agentA, 1, 1);
  await selectStore(agentA, 'متجر الورد');
  text = await panelText(agentA);
  await shot(agentA, 'salla-09b-stale-rate-limited');
  check('rate limited by Salla: the last orders shown as stale with their age, no request',
    text.includes("Couldn't refresh") && text.includes('Last updated') && text.includes('#30013'), text.slice(0, 200));
  const refreshFail = sim(`refresh_fails ${store1.id}`);
  check('refresh token rejected: needs re-authorization, refresh token removed, one token request', refreshFail.status === 'needs_reauth'
    && refreshFail.refresh_token_kept === false && refreshFail.token_requests === 1, JSON.stringify(refreshFail));
  await settingsPage(adminA, 1);
  await shot(adminA, 'salla-10-needs-reauth');
  const reauthRow = await storeRow(adminA, 'متجر الورد').innerText();
  check('settings explain re-authorization in Salla', reauthRow.includes('Needs re-authorization') && reauthRow.includes('update or reinstall'), reauthRow.replace(/\s+/g, ' '));
  check('a store needing re-authorization is not offered in conversations', !(await stores(agentA, 1, 1)).payload.some(s => s.provider === 'salla'));
  await deliver(authorize(M1, 'e2e-access-m1-new', 'e2e-refresh-m1-new'));
  console.log(sim('jobs'));
  check('Salla re-authorizes (app updated): same store active again', sim('state').stores.find(s => s.id === store1.id).status === 'active');
  const race = sim(`refresh_race ${store1.id}`);
  check('10 concurrent readers of an expiring token: one refresh request, old refresh token sent once, new one saved',
    race.token_requests === 1 && race.old_refresh_token_sent_times === 1 && race.distinct_tokens === 1 && race.new_refresh_token_saved, JSON.stringify(race));

  // ---- H. A second Salla store in the same account ------------------------------------------------------------------
  await settingsPage(adminA, 1);
  await openSallaDialog(adminA);
  const code2 = await createCode(adminA);
  await deliver(settings(M2, code2));
  await deliver(authorize(M2, 'e2e-access-m2', 'e2e-refresh-m2'));
  console.log(sim('jobs'));
  await adminA.waitForTimeout(6500);
  state = sim('state');
  check('a second Salla store connects to the same account', state.stores.filter(s => s.account_id === 1).length === 2);
  await openConversation(agentA, 1, 1);
  const options = await panel(agentA).locator('select option').allInnerTexts();
  check('store selector lists WooCommerce and both Salla stores', options.includes('متجر الورد') && options.includes('Salla Demo Two'), options.join(', '));
  await shot(agentA, 'salla-11-multi-store');

  // ---- I. Arabic and mobile ----------------------------------------------------------------------------------------
  console.log(sim(`warm ${store1.id} 1`));
  console.log(rails(`docs/commerce/e2e/rails/set.rb 1 locale=ar`));
  await openConversation(agentA, 1, 1);
  await selectStore(agentA, 'متجر الورد');
  text = await panelText(agentA);
  await shot(agentA, 'salla-12-panel-arabic');
  check('Arabic panel: shipped status, shipment status and tracking actions', text.includes('تم الشحن') && text.includes('في الطريق') && text.includes('تتبع الشحنة'), text.slice(0, 160));
  await settingsPage(adminA, 1);
  await shot(adminA, 'salla-13-settings-arabic');
  await openSallaDialog(adminA);
  await shot(adminA, 'salla-14-connect-dialog-arabic');
  check('Arabic Connect with Salla dialog', (await adminA.locator('dialog[open]').innerText()).includes('الربط مع سلة'));
  const mobile = await newPage('agent_a@commerce.lynomia.local', { viewport: { width: 390, height: 844 } });
  await openConversation(mobile, 1, 1);
  await selectStore(mobile, 'متجر الورد').catch(() => {});
  await shot(mobile, 'salla-15-mobile-arabic');
  const outside = await mobile.evaluate(() => [...document.querySelectorAll('[data-test-id="commerce-panel"] *')]
    .filter(el => el.getBoundingClientRect().right > window.innerWidth + 1 || el.getBoundingClientRect().left < -1).length);
  check('mobile (Arabic): Salla orders render inside the viewport', (await panelText(mobile)).includes('#30013') && outside === 0, `elements outside=${outside}`);
  console.log(rails(`docs/commerce/e2e/rails/set.rb 1 locale=en`));
  const mobileEn = await newPage('admin_a@commerce.lynomia.local', { viewport: { width: 390, height: 844 } });
  await settingsPage(mobileEn, 1);
  await openSallaDialog(mobileEn);
  await createCode(mobileEn);
  await shot(mobileEn, 'salla-16-mobile-connect-dialog');
  const overflow = await mobileEn.evaluate(() => {
    const dialog = document.querySelector('dialog[open]');
    return dialog ? dialog.scrollWidth > dialog.clientWidth + 1 : true;
  });
  check('mobile: the Connect with Salla dialog fits the screen', !overflow);

  // ---- J. Salla switched off in Super Admin -------------------------------------------------------------------------
  console.log(sim('configure off'));
  await settingsPage(adminA, 1);
  await shot(adminA, 'salla-17-provider-off');
  const offRow = await storeRow(adminA, 'متجر الورد').innerText();
  check('Salla off: stores kept and explained', offRow.includes('turned off'), offRow.replace(/\s+/g, ' '));
  await adminA.getByRole('button', { name: /add store/i }).click();
  await adminA.waitForTimeout(700);
  check('Salla off: Add store goes straight to WooCommerce keys (no Salla option)',
    await adminA.locator('[data-test-id="commerce-provider-salla"]').count() === 0 && await adminA.getByLabel('Consumer key').count() === 1);
  check('Salla off: Salla stores are not offered in conversations', !(await stores(agentA, 1, 1)).payload.some(s => s.provider === 'salla'));
  const connectionOff = (await api(adminA, '/api/v1/accounts/1/commerce/salla_connection', 'POST')).body;
  check('Salla off: no connection code can be created', connectionOff.error?.code === 'PROVIDER_DISABLED', JSON.stringify(connectionOff));
  console.log(sim('configure on'));

  // ---- K. Uninstall ---------------------------------------------------------------------------------------------------
  const contactsBefore = rails(`'puts Contact.where(account_id: 1).count'`);
  check('signed app.uninstalled accepted', await deliver(uninstalled(M2)) === 200);
  console.log(sim('jobs'));
  state = sim('state');
  const uninstalledStore = state.stores.find(s => s.external_store_id === String(M2));
  check('uninstall disconnects the store: credentials and links removed, contacts kept', uninstalledStore.status === 'disconnected'
    && uninstalledStore.credential_fields === null && uninstalledStore.links === 0 && rails(`'puts Contact.where(account_id: 1).count'`) === contactsBefore);
  await settingsPage(adminA, 1);
  await shot(adminA, 'salla-18-after-uninstall');
  const goneRow = await storeRow(adminA, 'Salla Demo Two').innerText();
  check('settings show the uninstalled store as disconnected with Reconnect', goneRow.includes('Disconnected') && goneRow.includes('Reconnect'));

  // ---- L. Permissions and secrets ------------------------------------------------------------------------------------
  const agentCode = (await api(agentA, '/api/v1/accounts/1/commerce/salla_connection', 'POST')).status;
  check('an agent cannot start a Salla connection', agentCode === 401, `status=${agentCode}`);
  state = sim('state');
  const events = state.audit.map(([comment]) => comment);
  check('audit trail: connect_started, connected, reauthorized, token_refreshed, needs_reauth, disconnected',
    ['commerce.salla.connect_started', 'commerce.salla.connected', 'commerce.salla.reauthorized', 'commerce.salla.token_refreshed',
      'commerce.salla.needs_reauth', 'commerce.salla.disconnected'].every(e => events.includes(e)), [...new Set(events)].join(', '));
  check('audit entries carry no token or secret', !TOKENS.some(token => JSON.stringify(state.audit).includes(token)));
  const leaked = apiBodies.filter(({ body }) => TOKENS.some(token => body.includes(token)) || body.includes('"credentials"'));
  check('no Salla token, refresh token or secret in any browser response', leaked.length === 0, `responses=${apiBodies.length} ${leaked.map(l => l.url).join(',')}`);
  const log = ['tmp/e2e_server.log', 'tmp/e2e_sim.log'].map(file => fs.readFileSync(`${REPO}/${file}`, 'utf8')).join('\n');
  check('no token, secret or connection code in the server or job logs', !TOKENS.some(token => log.includes(token)) && !codes.some(c => log.includes(c)),
    `log bytes=${log.length}`);
  check('no uncaught page errors', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));

  fs.writeFileSync(`${out}/salla_e2e_results.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed`);
  await browser.close();
})().catch(async error => {
  console.error(error);
  fs.writeFileSync(`${out}/salla_e2e_results.json`, JSON.stringify(results, null, 2));
  process.exit(1);
});
