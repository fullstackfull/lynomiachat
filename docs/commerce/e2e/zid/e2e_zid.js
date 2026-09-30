// Lynomia Commerce Zid E2E with a simulated Zid (docs/commerce/17-zid-e2e.md).
// usage: E2E_ZID_CLIENT_SECRET=… ERUN=… node e2e_zid.js <out_dir>
//
// Real: the Lynomia app (production build) and its OAuth start and callback, state checks, token exchange and storage,
// webhook endpoint and Basic Auth, Sidekiq queueing, Postgres, Redis, the browser UI and the other providers' stores.
// Simulated: Zid. Its hosts are answered by zid_sim.rb (WebMock, documented shapes) inside the Lynomia server and job
// runner; its authorization page is Playwright answering oauth.zid.sa/oauth/authorize with Zid's redirect back to the
// registered callback; its webhook deliveries are sent from here with the Basic Auth pair Lynomia registered.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/opt/node22/lib/node_modules/playwright');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const B = 'http://localhost:3100';
const REPO = path.resolve(__dirname, '../../../..');
const ERUN = process.env.ERUN;
const [out] = process.argv.slice(2);
const CLIENT_SECRET = process.env.E2E_ZID_CLIENT_SECRET;
const Z1 = '318001';
const Z2 = '318002';
const results = [];
const apiBodies = [];
const pageErrors = [];
const oauthUrls = [];
const navigations = [];
const secrets = new Set([CLIENT_SECRET]);

const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  -- ${detail}` : ''}`);
};
const sim = args => JSON.parse(execSync(`${ERUN} "bundle exec rails runner docs/commerce/e2e/zid/sim.rb ${args} 2>/dev/null | grep '^SIM ' | tail -1 | cut -c5-"`).toString().trim());
const rails = args => execSync(`${ERUN} "bundle exec rails runner ${args} 2>/dev/null | tail -1"`).toString().trim();
const basic = (user, password) => `Basic ${Buffer.from(`${user}:${password}`).toString('base64')}`;
const fixtureOrder = id => JSON.parse(fs.readFileSync(`${REPO}/spec/fixtures/files/commerce/zid/orders.json`, 'utf8')).orders.find(o => o.id === id);

// A webhook delivery as Zid sends it: the order JSON, with the Basic Auth pair Lynomia gave Zid when subscribing.
const deliver = async (store, body, authorization) => {
  const headers = { 'Content-Type': 'application/json' };
  if (authorization) headers.Authorization = authorization;
  return (await fetch(`${B}/webhooks/zid/${store}`, { method: 'POST', headers, body })).status;
};
const zidSide = store => {
  const side = sim(`zid_side ${store}`);
  if (side.password) secrets.add(side.password);
  return side;
};

let browser;
// Zid's authorization page: the merchant approves (or declines) and Zid redirects to the registered callback URL.
const zidAuthorizes = (context, { store, decline = false, hold = false }) => context.route('https://oauth.zid.sa/**', route => {
  const url = new URL(route.request().url());
  oauthUrls.push(url.toString());
  if (hold) return route.abort();
  const back = new URL(url.searchParams.get('redirect_uri'));
  back.searchParams.set('state', url.searchParams.get('state'));
  if (decline) back.searchParams.set('error', 'access_denied');
  else back.searchParams.set('code', `e2e-zid-code-${store}-${Date.now()}`);
  return route.fulfill({ status: 302, headers: { Location: back.toString() } });
});
const newPage = async (email, { viewport = { width: 1440, height: 1500 }, superAdmin = false } = {}) => {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  page.on('pageerror', e => pageErrors.push(`${email}: ${e.message}`));
  page.on('framenavigated', frame => frame === page.mainFrame() && navigations.push(frame.url()));
  page.on('response', async r => {
    if (r.url().startsWith(B) && !r.url().includes('/vite/')) apiBodies.push({ url: r.url(), body: await r.text().catch(() => '') });
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
const storeRow = (page, name) => page.locator('[data-test-id="commerce-store-row"]', { hasText: name });
// Where Zid's redirect back to Lynomia finally landed: Settings → Commerce with zid=connected or zid_error=<code>.
const landed = () => navigations.filter(url => url.includes('/settings/commerce?zid')).at(-1) || '';
// "Add store" → Zid → "Connect with Zid"; Zid answers as `zidAuthorizes` says and the browser lands back in settings.
const connectZid = async (page, options) => {
  await zidAuthorizes(page.context(), options);
  await page.getByRole('button', { name: /add store|إضافة متجر/i }).click();
  await page.waitForTimeout(700);
  await page.locator('[data-test-id="commerce-provider-zid"]').click();
  await page.waitForTimeout(600);
  await page.locator('[data-test-id="zid-connect"]').click();
  await page.waitForTimeout(options.hold ? 1500 : 2500);
  await page.context().unroute('https://oauth.zid.sa/**');
};
// An API call with the page's own session (the dashboard keeps its auth headers in the cw_d_session_info cookie).
const api = (page, url, method = 'GET') => page.evaluate(async ([u, m]) => {
  const raw = document.cookie.split('; ').find(c => c.startsWith('cw_d_session_info='));
  const info = JSON.parse(decodeURIComponent(raw.slice('cw_d_session_info='.length)));
  const response = await fetch(u, { method: m, headers: { 'access-token': info['access-token'], client: info.client, uid: info.uid } });
  return { status: response.status, body: await response.json().catch(() => null) };
}, [url, method]);
const stores = async (page, account, conversation) => (await api(page, `/api/v1/accounts/${account}/conversations/${conversation}/commerce/stores`)).body;
const tokenRequests = () => sim('requests')['POST /oauth/token'] || 0;

(async () => {
  console.log(sim('configure on'), sim('reset'));
  console.log(execSync(`${ERUN} "bundle exec rails runner docs/commerce/e2e/salla/sim.rb configure on 2>/dev/null | grep '^SIM '; bundle exec rails runner docs/commerce/e2e/salla/sim.rb super_admin 2>/dev/null | grep '^SIM '"`).toString().trim());
  console.log(rails(`'Account.find(1).update!(locale: :en); Account.find(2).update!(locale: :en); Account.find(2).enable_features!(%w[lynomia_commerce]); puts :ok'`));
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });

  // ---- A. Super Admin: the Zid app settings ---------------------------------------------------------------------------
  const superAdmin = await newPage('super@commerce.lynomia.local', { superAdmin: true });
  await superAdmin.goto(`${B}/super_admin/app_config?config=zid`, { waitUntil: 'networkidle' });
  const superHtml = await superAdmin.content();
  await shot(superAdmin, 'zid-01-super-admin');
  check('Super Admin shows Enable Zid, Client ID and a masked, empty Client Secret; no merchant token field',
    ['ZID_ENABLED', 'ZID_CLIENT_ID', 'ZID_CLIENT_SECRET'].every(f => superHtml.includes(`app_config[${f}]`)) && superHtml.includes('type="password"')
      && !superHtml.includes(CLIENT_SECRET) && !/app_config\[ZID_[A-Z_]*TOKEN/.test(superHtml));

  // ---- B. An administrator connects Zid with OAuth ---------------------------------------------------------------------
  const adminA = await newPage('admin_a@commerce.lynomia.local');
  await settingsPage(adminA, 1);
  await adminA.getByRole('button', { name: /add store/i }).click();
  await adminA.waitForTimeout(700);
  await shot(adminA, 'zid-02-provider-picker');
  check('Add store offers WooCommerce, Salla and Zid', await adminA.locator('[data-test-id="commerce-provider-zid"]').count() === 1
    && await adminA.locator('[data-test-id="commerce-provider-salla"]').count() === 1
    && await adminA.locator('[data-test-id="commerce-provider-woocommerce"]').count() === 1);
  await adminA.locator('[data-test-id="commerce-provider-zid"]').click();
  await adminA.waitForTimeout(600);
  await shot(adminA, 'zid-03-connect-dialog');
  check('Connect with Zid asks for nothing secret', (await adminA.locator('dialog[open]').innerText()).includes('Connect with Zid')
    && await adminA.locator('dialog[open] input').count() === 0);
  await adminA.keyboard.press('Escape');
  await adminA.waitForTimeout(400);
  const before = tokenRequests();
  await connectZid(adminA, { store: Z1 });
  const authorizeUrl = new URL(oauthUrls.at(-1));
  check('the browser is sent to Zid\'s authorization page with client_id, the registered callback, response_type=code and a state',
    authorizeUrl.origin + authorizeUrl.pathname === 'https://oauth.zid.sa/oauth/authorize' && authorizeUrl.searchParams.get('client_id') === '4821'
      && authorizeUrl.searchParams.get('redirect_uri') === `${B}/commerce/zid/callback` && authorizeUrl.searchParams.get('response_type') === 'code'
      && (authorizeUrl.searchParams.get('state') || '').length > 40 && !authorizeUrl.toString().includes(CLIENT_SECRET), authorizeUrl.origin);
  await shot(adminA, 'zid-04-connected');
  let state = sim('state');
  const zid1 = state.stores.find(s => s.external_store_id === Z1);
  check('back in Settings → Commerce: store connected to account A with Zid\'s store id, name, URL and time zone',
    landed().endsWith('/app/accounts/1/settings/commerce?zid=connected') && !adminA.url().includes('zid=') && zid1?.account_id === 1 && zid1.status === 'active'
      && zid1.name === 'متجر الياسمين' && zid1.base_url === 'https://jasmine.zid.store' && zid1.time_zone === 'Asia/Riyadh', JSON.stringify(zid1));
  check('one code exchange, done server-side', tokenRequests() - before === 1);
  check('tokens stored as Zid sends them (encrypted): authorization, access_token, refresh_token, token_type, expires_at',
    JSON.stringify(zid1.credential_fields) === JSON.stringify(['authorization', 'access_token', 'refresh_token', 'token_type', 'expires_at']),
    JSON.stringify(zid1.credential_fields));
  const rowText = (await storeRow(adminA, 'متجر الياسمين').innerText()).replace(/\s+/g, ' ');
  check('the settings list shows the store as Connected: name, Zid, Active', rowText.includes('Zid') && rowText.includes('Active'), rowText);
  check('webhook registration queued', (sim('queue')['Commerce::Zid::WebhookRegistrationJob'] || 0) === 1);
  console.log(sim('jobs'));
  let side = zidSide(Z1);
  check('Zid holds three order subscriptions to this store\'s URL with a random Basic Auth pair',
    JSON.stringify(side.events) === JSON.stringify(['order.create', 'order.status.update', 'order.payment_status.update'])
      && JSON.stringify(side.target_urls) === JSON.stringify([`${B}/webhooks/zid/${Z1}`]) && side.username?.length === 32 && side.password?.length >= 64,
    `${side.events} ${side.target_urls}`);
  state = sim('state');
  check('webhook credentials stored encrypted with the store, subscription ids in metadata',
    state.stores.find(s => s.external_store_id === Z1).credential_fields.includes('webhook_password') && state.stores.find(s => s.external_store_id === Z1).webhook_ids === 3);

  // ---- C. OAuth state security --------------------------------------------------------------------------------------
  const callbackUrl = `${B}/commerce/zid/callback?code=e2e-zid-code-${Z1}-replay&state=${encodeURIComponent(authorizeUrl.searchParams.get('state'))}`;
  let requestsBefore = tokenRequests();
  await adminA.goto(callbackUrl, { waitUntil: 'networkidle' });
  check('a replayed callback (state already used) changes nothing and names no account',
    !adminA.url().includes('/accounts/1/settings') && tokenRequests() === requestsBefore, adminA.url());
  await adminA.goto(`${B}/commerce/zid/callback?code=e2e-zid-code-${Z1}-forged&state=forged`, { waitUntil: 'networkidle' });
  check('a forged state is refused before any code exchange', tokenRequests() === requestsBefore);
  await settingsPage(adminA, 1);
  await connectZid(adminA, { store: Z2, hold: true });
  const heldState = new URL(oauthUrls.at(-1)).searchParams.get('state');
  const agentA = await newPage('agent_a@commerce.lynomia.local');
  await agentA.goto(`${B}/commerce/zid/callback?code=e2e-zid-code-${Z2}-agent&state=${encodeURIComponent(heldState)}`, { waitUntil: 'networkidle' });
  check('a valid state used from another browser (an agent\'s) is refused: no exchange, no store', tokenRequests() === requestsBefore
    && !sim('state').stores.some(s => s.external_store_id === Z2));
  const agentStart = await api(agentA, '/api/v1/accounts/1/commerce/zid_connection', 'POST');
  check('an agent cannot start a Zid authorization', agentStart.status === 401, `status=${agentStart.status}`);
  await settingsPage(adminA, 1);
  await connectZid(adminA, { store: Z2, decline: true });
  check('the merchant declining on Zid connects nothing and says why', !sim('state').stores.some(s => s.external_store_id === Z2)
    && tokenRequests() === requestsBefore && landed().endsWith('zid_error=AUTH_INVALID'), landed());
  const adminB = await newPage('admin_b@commerce.lynomia.local');
  await settingsPage(adminB, 2);
  await connectZid(adminB, { store: Z1 });
  await shot(adminB, 'zid-05-already-connected');
  state = sim('state');
  check('account B authorizing A\'s Zid store: refused as already connected; the store stays with A',
    state.stores.filter(s => s.external_store_id === Z1).length === 1 && state.stores.find(s => s.external_store_id === Z1).account_id === 1
      && landed().endsWith('/app/accounts/2/settings/commerce?zid_error=STORE_ALREADY_CONNECTED'), landed());

  // ---- D. A second Zid store and every provider in one account ------------------------------------------------------
  await settingsPage(adminA, 1);
  await connectZid(adminA, { store: Z2 });
  console.log(sim('jobs'));
  state = sim('state');
  const zid2 = state.stores.find(s => s.external_store_id === Z2);
  check('a second Zid store connects to the same account', zid2?.account_id === 1 && zid2.status === 'active' && zid2.webhook_ids === 3);
  await shot(adminA, 'zid-06-settings-all-providers');
  const list = await stores(agentA, 1, 1);
  const providers = list.payload.map(s => s.provider);
  check('one conversation lists WooCommerce, Salla and both Zid stores', providers.includes('woocommerce') && providers.includes('salla')
    && providers.filter(p => p === 'zid').length === 2, list.payload.map(s => `${s.provider}:${s.name}`).join(', '));

  // ---- E. The conversation panel with a Zid store ---------------------------------------------------------------------
  await openConversation(agentA, 1, 1);
  await selectStore(agentA, 'متجر الياسمين');
  let text = await panelText(agentA);
  await shot(agentA, 'zid-07-panel-orders');
  check('Zid customer linked by the verified WhatsApp phone, latest orders newest first',
    text.includes('Omar Khalil') && text.includes('verified phone') && text.indexOf('#41000102') < text.indexOf('#41000101')
      && text.indexOf('#41000101') < text.indexOf('#41000103'), text.slice(0, 220));
  const inDelivery = (await panel(agentA).locator('[data-test-id="commerce-order"]', { hasText: '#41000102' }).innerText()).replace(/\s+/g, ' ');
  check('order in delivery: Shipped, Paid, courier, In transit, Track shipment and Send tracking',
    inDelivery.includes('Shipped') && inDelivery.includes('Paid') && inDelivery.includes('kwickbox') && inDelivery.includes('In transit')
      && inDelivery.includes('Track shipment') && inDelivery.includes('Send tracking'), inDelivery);
  const newOrder = (await panel(agentA).locator('[data-test-id="commerce-order"]', { hasText: '#41000101' }).innerText()).replace(/\s+/g, ' ');
  const reversed = (await panel(agentA).locator('[data-test-id="commerce-order"]', { hasText: '#41000103' }).innerText()).replace(/\s+/g, ' ');
  check('status and payment only as Zid states them: new → Processing + Unpaid; reversed → Other + not confirmed',
    newOrder.includes('Processing') && newOrder.includes('Unpaid') && reversed.includes('Other') && reversed.includes('Payment not confirmed'),
    `${newOrder} | ${reversed}`);
  const trackHref = await panel(agentA).locator('[data-test-id="commerce-order"]', { hasText: '#41000102' }).getByRole('link', { name: 'Track shipment' }).getAttribute('href');
  check('tracking link is the https link Zid gave', trackHref === 'https://track.kwickbox.example/KWB123456789SA', trackHref);
  await panel(agentA).locator('[data-test-id="commerce-order"]', { hasText: '#41000102' }).getByRole('button', { name: 'Send tracking' }).click();
  await agentA.waitForTimeout(800);
  const editor = await agentA.locator('.ProseMirror').first().innerText().catch(() => '');
  check('Send tracking puts the tracking message in the reply box (nothing sent)', editor.includes('KWB123456789SA'), editor.slice(0, 120));
  await openConversation(agentA, 1, 2);
  await selectStore(agentA, 'متجر الياسمين');
  text = await panelText(agentA);
  await shot(agentA, 'zid-08-marketplace-not-linked');
  check('a marketplace order found by Layla\'s phone comes back masked: never matched, never linked',
    text.includes('Customer not found in this store') && !text.includes('Unlink') && !text.includes('J***'), text.slice(0, 200));

  // ---- F. Webhooks with Basic Auth ----------------------------------------------------------------------------------
  side = zidSide(Z1);
  const side2 = zidSide(Z2);
  const event = payment => JSON.stringify({ ...fixtureOrder(41000101), store_id: Number(Z1), customer: { ...fixtureOrder(41000101).customer, id: 90001 },
    order_status: { name: 'Delivered', code: 'delivered' }, payment_status: payment });
  const changed = event('paid');
  const refused = {
    missing: await deliver(Z1, changed, null),
    wrongUsername: await deliver(Z1, changed, basic('x'.repeat(32), side.password)),
    wrongPassword: await deliver(Z1, changed, basic(side.username, 'not-the-password')),
    otherStore: await deliver(Z1, changed, basic(side2.username, side2.password)),
    bearer: await deliver(Z1, changed, `Bearer ${side.password}`)
  };
  check('deliveries without credentials, with a wrong username or password, another store\'s pair or a bearer token get 401',
    Object.values(refused).every(status => status === 401), JSON.stringify(refused));
  check('nothing queued for refused deliveries', !sim('queue')['Commerce::Zid::WebhookJob']);
  console.log(sim(`order ${Z1} 41000101 delivered paid`));
  const accepted = await deliver(Z1, changed, basic(side.username, side.password));
  const replayed = await deliver(Z1, changed, basic(side.username, side.password));
  check('the correct pair is accepted, and the replay is acknowledged but queued once',
    accepted === 200 && replayed === 200 && sim('queue')['Commerce::Zid::WebhookJob'] === 1);
  console.log(sim('jobs'));
  await openConversation(agentA, 1, 1);
  await selectStore(agentA, 'متجر الياسمين');
  const updated = (await panel(agentA).locator('[data-test-id="commerce-order"]', { hasText: '#41000101' }).innerText()).replace(/\s+/g, ' ');
  await shot(agentA, 'zid-09-after-webhook');
  check('the order event dropped the cached orders: the panel shows Zid\'s new status at once', updated.includes('Delivered') && updated.includes('Paid'), updated);

  // ---- G. Token lifecycle -------------------------------------------------------------------------------------------
  const race = sim(`refresh_race ${zid1.id}`);
  check('10 concurrent readers of expiring tokens: one refresh request, one set of new tokens saved',
    race.token_requests === 1 && race.distinct_tokens === 1 && race.saved, JSON.stringify(race));
  console.log(sim('refresh_mode invalid_grant'), sim(`expire ${zid1.id}`), sim(`age ${zid1.id}`));
  await openConversation(agentA, 1, 1);
  await selectStore(agentA, 'متجر الياسمين').catch(() => {});
  text = await panelText(agentA);
  state = sim('state');
  check('Zid refuses the refresh token: the store needs re-authorization, its tokens are removed and nothing stale is shown',
    state.stores.find(s => s.id === zid1.id).status === 'needs_reauth' && !state.stores.find(s => s.id === zid1.id).credential_fields?.includes('refresh_token')
      && !text.includes('#41000102'), text.slice(0, 160));
  console.log(sim('refresh_mode ok'));
  await settingsPage(adminA, 1);
  await shot(adminA, 'zid-10-needs-reauth');
  const reauthRow = (await storeRow(adminA, 'متجر الياسمين').innerText()).replace(/\s+/g, ' ');
  check('settings explain re-authorization and offer Reconnect', reauthRow.includes('Needs re-authorization') && reauthRow.includes('Reconnect'), reauthRow);
  check('a store needing re-authorization is not offered in conversations', !(await stores(agentA, 1, 1)).payload.some(s => s.name === 'متجر الياسمين'));
  const oldPassword = side.password;
  await zidAuthorizes(adminA.context(), { store: Z1 });
  await storeRow(adminA, 'متجر الياسمين').getByRole('button', { name: 'Reconnect' }).click();
  await adminA.waitForTimeout(600);
  await adminA.locator('[data-test-id="zid-connect"]').click();
  await adminA.waitForTimeout(4000);
  await adminA.context().unroute('https://oauth.zid.sa/**');
  console.log(sim('jobs'));
  state = sim('state');
  side = zidSide(Z1);
  check('Reconnect re-authorizes the same store in place', state.stores.filter(s => s.external_store_id === Z1).length === 1
    && state.stores.find(s => s.external_store_id === Z1).id === zid1.id && state.stores.find(s => s.external_store_id === Z1).status === 'active');
  check('re-registration rotates the webhook credentials without duplicating subscriptions: the old pair is refused',
    side.events.length === 3 && side.password !== oldPassword && await deliver(Z1, event('refunded'), basic(side.username, oldPassword)) === 401
      && await deliver(Z1, event('refunded'), basic(side.username, side.password)) === 200);
  console.log(sim('jobs'));
  console.log(sim(`revoke ${Z2}`), sim(`age ${zid2.id}`));
  await openConversation(agentA, 1, 1);
  await selectStore(agentA, 'Zid Demo Two').catch(() => {});
  text = await panelText(agentA);
  check('an authorization revoked in Zid (uninstall): the store needs re-authorization, nothing stale is shown',
    sim('state').stores.find(s => s.id === zid2.id).status === 'needs_reauth' && !text.includes('#41000102'), text.slice(0, 160));

  // ---- H. Disconnect ------------------------------------------------------------------------------------------------
  const contactsBefore = rails(`'puts Contact.where(account_id: 1).count'`);
  const conversationsBefore = rails(`'puts Conversation.where(account_id: 1).count'`);
  await settingsPage(adminA, 1);
  await storeRow(adminA, 'متجر الياسمين').getByRole('button', { name: 'Disconnect' }).click();
  await adminA.waitForTimeout(600);
  await shot(adminA, 'zid-11-disconnect-confirm');
  await adminA.locator('dialog[open]').getByRole('button', { name: 'Disconnect' }).click();
  await adminA.waitForTimeout(2500);
  state = sim('state');
  const gone = state.stores.find(s => s.id === zid1.id);
  check('disconnect deletes the Zid subscriptions, tokens, webhook credentials, links and cache; contacts and conversations stay',
    zidSide(Z1).events.length === 0 && gone.status === 'disconnected' && gone.credential_fields === null && gone.links === 0
      && rails(`'puts Contact.where(account_id: 1).count'`) === contactsBefore && rails(`'puts Conversation.where(account_id: 1).count'`) === conversationsBefore,
    JSON.stringify(gone));
  check('deliveries for a disconnected store are refused', await deliver(Z1, changed, basic(side.username, side.password)) === 401);

  // ---- I. Zid switched off, Commerce switched off --------------------------------------------------------------------
  console.log(sim('configure off'));
  await settingsPage(adminA, 1);
  await shot(adminA, 'zid-12-provider-off');
  const offRow = (await storeRow(adminA, 'Zid Demo Two').innerText()).replace(/\s+/g, ' ');
  check('Zid off: Zid stores kept and explained', offRow.includes('Zid is turned off'), offRow);
  await adminA.getByRole('button', { name: /add store/i }).click();
  await adminA.waitForTimeout(700);
  check('Zid off: no Zid in Add store', await adminA.locator('[data-test-id="commerce-provider-zid"]').count() === 0);
  const startOff = (await api(adminA, '/api/v1/accounts/1/commerce/zid_connection', 'POST')).body;
  check('Zid off: no authorization can start', startOff.error?.code === 'PROVIDER_DISABLED', JSON.stringify(startOff));
  console.log(sim('configure on'));
  console.log(rails('docs/commerce/e2e/rails/set.rb 2 feature=off'));
  await settingsPage(adminB, 2);
  const nav = await adminB.locator('aside').first().innerText();
  const startNoCommerce = (await api(adminB, '/api/v1/accounts/2/commerce/zid_connection', 'POST')).status;
  check('Commerce off for the account: no Commerce in settings and no Zid authorization', !nav.includes('Commerce') && startNoCommerce === 401);
  console.log(rails('docs/commerce/e2e/rails/set.rb 2 feature=on'));

  // ---- J. Arabic and mobile -----------------------------------------------------------------------------------------
  console.log(rails('docs/commerce/e2e/rails/set.rb 1 locale=ar'));
  await settingsPage(adminA, 1);
  await adminA.getByRole('button', { name: /إضافة متجر/ }).click();
  await adminA.waitForTimeout(700);
  await shot(adminA, 'zid-13-picker-arabic');
  await adminA.locator('[data-test-id="commerce-provider-zid"]').click();
  await adminA.waitForTimeout(600);
  await shot(adminA, 'zid-14-connect-dialog-arabic');
  check('Arabic: زد in the picker and الربط مع زد', (await adminA.locator('dialog[open]').innerText()).includes('الربط مع زد'));
  console.log(rails('docs/commerce/e2e/rails/set.rb 1 locale=en'));
  const mobile = await newPage('admin_a@commerce.lynomia.local', { viewport: { width: 390, height: 844 } });
  await settingsPage(mobile, 1);
  await mobile.getByRole('button', { name: /add store/i }).click();
  await mobile.waitForTimeout(700);
  await mobile.locator('[data-test-id="commerce-provider-zid"]').click();
  await mobile.waitForTimeout(600);
  await shot(mobile, 'zid-15-mobile-connect-dialog');
  const overflow = await mobile.evaluate(() => {
    const dialog = document.querySelector('dialog[open]');
    return dialog ? dialog.scrollWidth > dialog.clientWidth + 1 : true;
  });
  check('mobile: the Connect with Zid dialog fits the screen', !overflow);

  // ---- K. Secrets and audit -----------------------------------------------------------------------------------------
  state = sim('state');
  const events = state.audit.map(([comment]) => comment);
  check('audit trail: connected, token_refreshed, needs_reauth, reauthorized, store_disconnected',
    ['commerce.zid.connected', 'commerce.zid.token_refreshed', 'commerce.zid.needs_reauth', 'commerce.zid.reauthorized', 'commerce.store_disconnected']
      .every(e => events.includes(e)), [...new Set(events)].join(', '));
  const tokens = /e2e-zid-(manager|auth|refresh)-\d+-\d+|e2e-zid-code-\d+-\w+/;
  check('audit entries carry no token, code or secret', !tokens.test(JSON.stringify(state.audit)) && ![...secrets].some(s => JSON.stringify(state.audit).includes(s)));
  const leaked = apiBodies.filter(({ body }) => tokens.test(body) || [...secrets].some(s => body.includes(s)) || body.includes('"credentials"'));
  check('no Zid token, code, client secret or webhook password in any browser response', leaked.length === 0,
    `responses=${apiBodies.length} ${leaked.map(l => l.url).join(',')}`);
  const log = ['tmp/e2e_server.log', 'tmp/e2e_sim.log'].map(file => fs.readFileSync(`${REPO}/${file}`, 'utf8')).join('\n');
  const states = oauthUrls.map(u => new URL(u).searchParams.get('state'));
  check('no token, code, state, client secret or webhook password in the server or job logs',
    !tokens.test(log) && ![...secrets].some(s => log.includes(s)) && !states.some(s => log.includes(s)), `log bytes=${log.length}`);
  check('no uncaught page errors', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));

  fs.writeFileSync(`${out}/zid_e2e_results.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed`);
  await browser.close();
})().catch(async error => {
  console.error(error);
  fs.writeFileSync(`${out}/zid_e2e_results.json`, JSON.stringify(results, null, 2));
  process.exit(1);
});
