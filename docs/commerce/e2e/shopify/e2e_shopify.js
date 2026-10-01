// Lynomia Commerce Shopify E2E with a simulated Shopify (docs/commerce/22-shopify-e2e.md).
// usage: E2E_SHOPIFY_CLIENT_SECRET=… ERUN=… node e2e_shopify.js <out_dir>
//
// Real: the Lynomia app (production build) and its OAuth start and callback, HMAC, state and shop checks, token exchange,
// refresh and storage, GraphQL provider, webhook endpoint and HMAC, Sidekiq queueing, Postgres, Redis, the browser UI,
// the legacy Shopify integration and the other providers' stores.
// Simulated: Shopify. Its hosts are answered by shopify_sim.rb (WebMock, 2026-07 shapes) inside the Lynomia server and
// job runner; its authorization page is Playwright answering <shop>/admin/oauth/authorize with Shopify's signed redirect
// back to the callback (HMAC computed here the way Shopify's official Node library verifies it); its webhook deliveries
// are signed and sent from here.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/opt/node22/lib/node_modules/playwright');
const { execSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const B = 'http://localhost:3100';
const REPO = path.resolve(__dirname, '../../../..');
const ERUN = process.env.ERUN;
const [out] = process.argv.slice(2);
const SECRET = process.env.E2E_SHOPIFY_CLIENT_SECRET;
const SHOP1 = 'lynomia-demo.myshopify.com';
const SHOP2 = 'lynomia-two.myshopify.com';
const results = [];
const apiBodies = [];
const pageErrors = [];
const authorizeUrls = [];
const navigations = [];
const secrets = new Set([SECRET]);

const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  -- ${detail}` : ''}`);
};
const sim = args => JSON.parse(execSync(`${ERUN} "bundle exec rails runner docs/commerce/e2e/shopify/sim.rb ${args} 2>/dev/null | grep '^SIM ' | tail -1 | cut -c5-"`).toString().trim());
const rails = args => execSync(`${ERUN} "bundle exec rails runner ${args} 2>/dev/null | tail -1"`).toString().trim();

// Shopify's callback signature, computed as @shopify/shopify-api verifies it: every parameter but hmac, sorted,
// URLSearchParams-encoded with '+' written as %20, HMAC-SHA256 hex with the app's client secret.
const signCallback = (params, secret = SECRET) => {
  const query = new URLSearchParams();
  Object.keys(params).sort((a, b) => a.localeCompare(b)).forEach(key => query.append(key, params[key]));
  return crypto.createHmac('sha256', secret).update(query.toString().replace(/\+/g, '%20')).digest('hex');
};
const callbackUrl = (redirectUri, params, secret) => {
  const url = new URL(redirectUri);
  Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, value));
  url.searchParams.set('hmac', signCallback(params, secret));
  return url.toString();
};
const now = () => String(Math.floor(Date.now() / 1000));
const host = shop => Buffer.from(`admin.shopify.com/store/${shop.split('.')[0]}`).toString('base64').replace(/=+$/, '');

// A webhook delivery as Shopify sends it: the raw JSON body signed with the app's client secret.
const deliver = async (topic, shop, payload, { secret = SECRET, id = crypto.randomUUID(), signature, endpoint = '/webhooks/shopify_commerce' } = {}) => {
  const body = JSON.stringify(payload);
  const headers = { 'Content-Type': 'application/json', 'X-Shopify-Topic': topic, 'X-Shopify-Shop-Domain': shop, 'X-Shopify-Webhook-Id': id,
    'X-Shopify-API-Version': '2026-07', 'X-Shopify-Triggered-At': new Date().toISOString() };
  const hmac = signature === undefined ? crypto.createHmac('sha256', secret).update(body).digest('base64') : signature;
  if (hmac !== null) headers['X-Shopify-Hmac-Sha256'] = hmac;
  return (await fetch(`${B}${endpoint}`, { method: 'POST', headers, body })).status;
};

let browser;
// Shopify's authorization page: the merchant approves and Shopify redirects to the redirect URL with a signed query.
const shopifyAuthorizes = (context, { hold = false, tamper } = {}) => context.route(/^https:\/\/[a-z0-9-]+\.myshopify\.com\/admin\/oauth\/authorize/, route => {
  const url = new URL(route.request().url());
  authorizeUrls.push(url.toString());
  if (hold) return route.abort();
  const params = { code: `e2e-shopify-code-${Date.now()}`, host: host(url.host), shop: url.host, state: url.searchParams.get('state'), timestamp: now() };
  let back = callbackUrl(url.searchParams.get('redirect_uri'), params);
  if (tamper) back = tamper(back);
  return route.fulfill({ status: 302, headers: { Location: back } });
});
const newPage = async (email, { viewport = { width: 1440, height: 1500 }, superAdmin = false } = {}) => {
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
const order = async (page, number) => (await panel(page).locator('[data-test-id="commerce-order"]', { hasText: `#${number}` }).innerText()).replace(/\s+/g, ' ');
const storeRow = (page, name) => page.locator('[data-test-id="commerce-store-row"]', { hasText: name });
const landed = () => navigations.filter(url => url.includes('/settings/commerce?shopify')).at(-1) || '';
// "Add store" → Shopify → domain → "Connect with Shopify"; Shopify answers as `shopifyAuthorizes` says.
const connectShopify = async (page, shop, options = {}) => {
  await shopifyAuthorizes(page.context(), options);
  await page.getByRole('button', { name: /add store|إضافة متجر/i }).click();
  await page.waitForTimeout(700);
  await page.locator('[data-test-id="commerce-provider-shopify"]').click();
  await page.waitForTimeout(600);
  await page.locator('dialog[open] input').fill(shop);
  await page.locator('[data-test-id="shopify-connect"]').click();
  await page.waitForTimeout(options.hold ? 1500 : 3000);
  await page.context().unroute(/^https:\/\/[a-z0-9-]+\.myshopify\.com\/admin\/oauth\/authorize/);
};
const api = (page, url, method = 'GET', body) => page.evaluate(async ([u, m, b]) => {
  const raw = document.cookie.split('; ').find(c => c.startsWith('cw_d_session_info='));
  const info = JSON.parse(decodeURIComponent(raw.slice('cw_d_session_info='.length)));
  const response = await fetch(u, { method: m, headers: { 'access-token': info['access-token'], client: info.client, uid: info.uid,
    'Content-Type': 'application/json' }, body: b ? JSON.stringify(b) : undefined });
  return { status: response.status, body: await response.json().catch(() => null) };
}, [url, method, body]);
const stores = async (page, account, conversation) => (await api(page, `/api/v1/accounts/${account}/conversations/${conversation}/commerce/stores`)).body;
const requests = () => sim('requests');
const tokenRequests = () => requests().requests['POST /admin/oauth/access_token'] || 0;

(async () => {
  console.log(sim('configure on'), sim('reset'), sim('refresh_mode ok'), sim('gql_mode ok'), sim('grant_mode ok'));
  console.log(execSync(`${ERUN} "bundle exec rails runner docs/commerce/e2e/salla/sim.rb configure on 2>/dev/null | grep '^SIM '; bundle exec rails runner docs/commerce/e2e/salla/sim.rb super_admin 2>/dev/null | grep '^SIM '"`).toString().trim());
  console.log(rails(`'Account.find(1).update!(locale: :en); Account.find(2).update!(locale: :en); Account.find(2).enable_features!(%w[lynomia_commerce]); puts :ok'`));
  const conv = JSON.parse(rails(`'puts Conversation.where(account_id: 1).joins(:contact).pluck(%q(contacts.name), :display_id).to_h.to_json'`));
  const OMAR = conv['Omar Khalil'];
  const LAYLA = conv['ليلى حداد'];
  const MONA = conv['منى صالح'];
  const VISITOR = conv['Website visitor'];
  const NOBODY = conv['New lead'];
  const legacyBefore = sim('legacy_config');
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });

  // ---- A. Super Admin: the Shopify Commerce app settings, apart from the legacy integration's ---------------------
  const superAdmin = await newPage('super@commerce.lynomia.local', { superAdmin: true });
  await superAdmin.goto(`${B}/super_admin/app_config?config=shopify_commerce`, { waitUntil: 'networkidle' });
  const superHtml = await superAdmin.content();
  await shot(superAdmin, 'shopify-01-super-admin');
  check('Super Admin shows Enable Shopify Commerce, Client ID and a masked, empty Client Secret; no merchant token field',
    ['SHOPIFY_COMMERCE_ENABLED', 'SHOPIFY_COMMERCE_CLIENT_ID', 'SHOPIFY_COMMERCE_CLIENT_SECRET'].every(f => superHtml.includes(`app_config[${f}]`))
      && superHtml.includes('type="password"') && !superHtml.includes(SECRET) && !/app_config\[SHOPIFY_COMMERCE_[A-Z_]*TOKEN/.test(superHtml));
  await superAdmin.goto(`${B}/super_admin/app_config?config=shopify`, { waitUntil: 'networkidle' });
  const legacyHtml = await superAdmin.content();
  check('the legacy Shopify settings page is unchanged and separate: no Commerce field on it',
    legacyHtml.includes('app_config[SHOPIFY_CLIENT_ID]') && !legacyHtml.includes('SHOPIFY_COMMERCE'));

  // ---- B. An administrator connects Shopify with OAuth --------------------------------------------------------------
  const adminA = await newPage('admin_a@commerce.lynomia.local');
  await settingsPage(adminA, 1);
  await adminA.getByRole('button', { name: /add store/i }).click();
  await adminA.waitForTimeout(700);
  await shot(adminA, 'shopify-02-provider-picker');
  check('Add store offers WooCommerce, Salla, Zid and Shopify', await adminA.locator('[data-test-id="commerce-provider-shopify"]').count() === 1
    && await adminA.locator('[data-test-id="commerce-provider-salla"]').count() === 1
    && await adminA.locator('[data-test-id="commerce-provider-woocommerce"]').count() === 1);
  await adminA.locator('[data-test-id="commerce-provider-shopify"]').click();
  await adminA.waitForTimeout(600);
  await shot(adminA, 'shopify-03-connect-dialog');
  check('Connect with Shopify asks only for the myshopify.com domain', (await adminA.locator('dialog[open]').innerText()).includes('Connect with Shopify')
    && await adminA.locator('dialog[open] input').count() === 1 && await adminA.locator('dialog[open] input[type="password"]').count() === 0);
  const rejected = [];
  for (const bad of ['evil.example.com', 'https://lynomia-demo.myshopify.com', 'lynomia-demo.myshopify.com.evil.com', '127.0.0.1', 'user@lynomia-demo.myshopify.com']) {
    await adminA.locator('dialog[open] input').fill(bad);
    await adminA.locator('[data-test-id="shopify-connect"]').click();
    await adminA.waitForTimeout(700);
    rejected.push((await adminA.locator('[data-test-id="shopify-connection-error"]').innerText().catch(() => '')).includes('myshopify.com domain'));
  }
  await shot(adminA, 'shopify-04-invalid-domain');
  check('a host that is not a myshopify.com domain is refused, before any redirect', rejected.every(Boolean) && authorizeUrls.length === 0, JSON.stringify(rejected));
  await adminA.keyboard.press('Escape');
  await adminA.waitForTimeout(400);
  console.log(sim(`legacy_hook 1 ${SHOP1} on`));
  await connectShopify(adminA, SHOP1, { hold: true });
  const legacyMessage = await adminA.locator('[data-test-id="shopify-connection-error"]').innerText().catch(() => '');
  await shot(adminA, 'shopify-05-legacy-conflict');
  check('a shop this account shows through the legacy Shopify integration is refused, the legacy hook untouched',
    legacyMessage.includes("already connected through this account's Shopify integration") && authorizeUrls.length === 0
      && JSON.stringify(sim(`legacy_hook 1 ${SHOP1} off`).legacy_hooks) === '[]', legacyMessage);
  await adminA.keyboard.press('Escape');
  const before = tokenRequests();
  await settingsPage(adminA, 1);
  await connectShopify(adminA, SHOP1);
  const authorizeUrl = new URL(authorizeUrls.at(-1));
  check("the browser is sent to the shop's authorization page: client_id, read-only scopes, redirect URL, state, offline (no per-user)",
    authorizeUrl.origin + authorizeUrl.pathname === `https://${SHOP1}/admin/oauth/authorize` && authorizeUrl.searchParams.get('client_id') === 'e2e-shopify-commerce-client'
      && authorizeUrl.searchParams.get('scope') === 'read_customers,read_orders' && authorizeUrl.searchParams.get('redirect_uri') === `${B}/commerce/shopify/callback`
      && (authorizeUrl.searchParams.get('state') || '').length > 40 && !authorizeUrl.searchParams.has('grant_options[]') && !authorizeUrl.toString().includes(SECRET),
    authorizeUrl.search.slice(0, 120));
  await shot(adminA, 'shopify-06-connected');
  let state = sim('state');
  const shop1 = state.stores.find(s => s.external_store_id === '68210001');
  check("back in Settings → Commerce: store connected to account A with Shopify's shop id, name and myshopify.com URL",
    landed().endsWith('/app/accounts/1/settings/commerce?shopify=connected') && !adminA.url().includes('shopify=') && shop1?.account_id === 1
      && shop1.status === 'active' && shop1.name === 'Lynomia Demo' && shop1.base_url === `https://${SHOP1}`, JSON.stringify(shop1));
  let reqs = requests();
  check('one code exchange, server-side, with expiring=1', tokenRequests() - before === 1 && JSON.stringify(reqs.expiring) === '["1"]', JSON.stringify(reqs.expiring));
  const accessExpiry = new Date(shop1.expires[0]).getTime() - Date.now();
  const refreshExpiry = new Date(shop1.expires[1]).getTime() - Date.now();
  check('the expiring offline token is stored encrypted as Shopify sent it: token pair, both expiry times from its answer, scope',
    JSON.stringify(shop1.credential_fields) === JSON.stringify(['access_token', 'access_token_expires_at', 'refresh_token', 'refresh_token_expires_at', 'scope'])
      && accessExpiry > 55 * 60e3 && accessExpiry <= 3600e3 && refreshExpiry > 89 * 86400e3 && shop1.scope === 'read_customers,read_orders',
    `${shop1.expires} ${shop1.scope}`);
  check('the shop identity is confirmed with a GraphQL query, and no mutation is ever sent',
    reqs.operations.includes('query LynomiaShop') && !reqs.operations.some(o => o.startsWith('mutation')), reqs.operations.join(','));
  const rowText = (await storeRow(adminA, 'Lynomia Demo').innerText()).replace(/\s+/g, ' ');
  check('the settings list shows the store: name, Shopify, Active', rowText.includes('Shopify') && rowText.includes('Active'), rowText);

  // ---- C. Callback security: HMAC, state, shop --------------------------------------------------------------------
  const held = async () => {
    await settingsPage(adminA, 1);
    await connectShopify(adminA, SHOP2, { hold: true });
    await adminA.keyboard.press('Escape');
    return new URL(authorizeUrls.at(-1)).searchParams.get('state');
  };
  const redirect = `${B}/commerce/shopify/callback`;
  let requestsBefore = tokenRequests();
  const usedState = authorizeUrl.searchParams.get('state');
  await adminA.goto(callbackUrl(redirect, { code: 'e2e-shopify-code-replay', host: host(SHOP1), shop: SHOP1, state: usedState, timestamp: now() }), { waitUntil: 'networkidle' });
  check('a replayed callback (state already used) changes nothing and names no account', !adminA.url().includes('/settings/commerce') && tokenRequests() === requestsBefore, adminA.url());
  let pending = await held();
  const base = { code: 'e2e-shopify-code-sec', host: host(SHOP2), shop: SHOP2, state: pending, timestamp: now() };
  const attempts = {
    unsigned: `${redirect}?${new URLSearchParams(base)}`,
    wrongSecret: callbackUrl(redirect, base, 'legacy-shopify-app-secret'),
    modifiedCode: callbackUrl(redirect, base).replace('code=e2e-shopify-code-sec', 'code=e2e-shopify-code-other'),
    stale: callbackUrl(redirect, { ...base, timestamp: String(Number(now()) - 300) }),
    otherShop: callbackUrl(redirect, { ...base, shop: SHOP1, host: host(SHOP1) })
  };
  const outcomes = {};
  for (const [name, url] of Object.entries(attempts)) {
    await adminA.goto(url, { waitUntil: 'networkidle' });
    outcomes[name] = !adminA.url().includes('/settings/commerce') && tokenRequests() === requestsBefore;
  }
  check('unsigned, wrong-secret, modified, stale (5 min) and other-shop callbacks are refused before any code exchange',
    Object.values(outcomes).every(Boolean), JSON.stringify(outcomes));
  await adminA.goto(callbackUrl(redirect, { ...base, state: 'forged' }), { waitUntil: 'networkidle' });
  check('a forged state is refused before any code exchange', tokenRequests() === requestsBefore);
  const agentA = await newPage('agent_a@commerce.lynomia.local');
  pending = await held();
  await agentA.goto(callbackUrl(redirect, { ...base, state: pending, timestamp: now() }), { waitUntil: 'networkidle' });
  check("a valid, signed callback from another browser (an agent's) is refused: no exchange, no store", tokenRequests() === requestsBefore
    && !sim('state').stores.some(s => s.external_store_id === '68210002'));
  const agentStart = await api(agentA, '/api/v1/accounts/1/commerce/shopify_connection', 'POST', { shop: SHOP2 });
  check('an agent cannot start a Shopify authorization', agentStart.status === 401, `status=${agentStart.status}`);
  console.log(sim('grant_mode non_expiring'));
  await settingsPage(adminA, 1);
  await connectShopify(adminA, SHOP2);
  const nonExpiring = landed();
  console.log(sim('grant_mode write_scope'));
  await settingsPage(adminA, 1);
  await connectShopify(adminA, SHOP2);
  const writeScope = landed();
  console.log(sim('grant_mode ok'));
  check('a non-expiring token and a token with write scopes are refused; nothing is stored',
    nonExpiring.endsWith('shopify_error=INVALID_RESPONSE') && writeScope.endsWith('shopify_error=PERMISSION_DENIED')
      && !sim('state').stores.some(s => s.external_store_id === '68210002'), `${nonExpiring} | ${writeScope}`);
  const adminB = await newPage('admin_b@commerce.lynomia.local');
  await settingsPage(adminB, 2);
  await connectShopify(adminB, SHOP1);
  await shot(adminB, 'shopify-07-already-connected');
  state = sim('state');
  check("account B authorizing A's shop: refused as already connected; the shop stays with A",
    state.stores.filter(s => s.external_store_id === '68210001').length === 1 && state.stores.find(s => s.external_store_id === '68210001').account_id === 1
      && landed().endsWith('/app/accounts/2/settings/commerce?shopify_error=STORE_ALREADY_CONNECTED'), landed());

  // ---- D. A second shop and every provider in one account --------------------------------------------------------
  await settingsPage(adminA, 1);
  await connectShopify(adminA, SHOP2);
  state = sim('state');
  const shop2 = state.stores.find(s => s.external_store_id === '68210002');
  check('a second Shopify shop connects to the same account', shop2?.account_id === 1 && shop2.status === 'active');
  await shot(adminA, 'shopify-08-settings-all-providers');
  const list = await stores(agentA, 1, OMAR);
  const providers = list.payload.map(s => s.provider);
  check('one conversation lists WooCommerce, Salla and both Shopify shops', providers.includes('woocommerce') && providers.includes('salla')
    && providers.filter(p => p === 'shopify').length === 2, list.payload.map(s => `${s.provider}:${s.name}`).join(', '));

  // ---- E. The conversation panel with a Shopify store ---------------------------------------------------------------
  await openConversation(agentA, 1, OMAR);
  await selectStore(agentA, 'Lynomia Demo');
  let text = await panelText(agentA);
  await shot(agentA, 'shopify-09-panel-orders');
  check('Shopify customer linked by the verified WhatsApp phone; the last five orders, newest first',
    text.includes('verified phone') && text.indexOf('#1006') < text.indexOf('#1005') && text.indexOf('#1005') < text.indexOf('#1002')
      && !text.includes('#1001') && !text.includes('#999'), text.slice(0, 220));
  const delivered = await order(agentA, 1006);
  check('multi-fulfillment order delivered: Delivered, Paid, Aramex, Track shipment and Send tracking',
    delivered.includes('Delivered') && delivered.includes('Paid') && delivered.includes('Aramex') && delivered.includes('Track shipment')
      && delivered.includes('Send tracking'), delivered);
  const partial = await order(agentA, 1005);
  const noTracking = await order(agentA, 1004);
  const cancelled = await order(agentA, 1003);
  const partlyPaid = await order(agentA, 1002);
  check('partially fulfilled + pending: Processing, Unpaid, In transit with DHL tracking', partial.includes('Processing') && partial.includes('Unpaid')
    && partial.includes('In transit') && partial.includes('Track shipment'), partial);
  check('fulfilled without tracking: Shipped, Partially refunded, Out for delivery, nothing to track', noTracking.includes('Shipped')
    && noTracking.includes('Partially refunded') && noTracking.includes('Out for delivery') && !noTracking.includes('Track shipment'), noTracking);
  check('payment only from displayFinancialStatus: cancelled + refunded; on hold + partially paid',
    cancelled.includes('Cancelled') && cancelled.includes('Refunded') && partlyPaid.includes('On hold') && partlyPaid.includes('Partially paid'),
    `${cancelled} | ${partlyPaid}`);
  const orderLinks = panel(agentA).locator('[data-test-id="commerce-order"]', { hasText: '#1006' });
  const trackHref = await orderLinks.getByRole('link', { name: 'Track shipment' }).getAttribute('href');
  const adminHref = await orderLinks.getByRole('link', { name: 'View order' }).getAttribute('href').catch(() => null);
  check('tracking link is the https link Shopify gave; the admin link is built from the shop domain',
    trackHref === 'https://www.aramex.com/track/ARX100' && adminHref === `https://${SHOP1}/admin/orders/6001006`, `${trackHref} ${adminHref}`);
  await orderLinks.getByRole('button', { name: 'Send tracking' }).click();
  await agentA.waitForTimeout(800);
  const editor = await agentA.locator('.ProseMirror').first().innerText().catch(() => '');
  check('Send tracking puts the tracking message in the reply box (nothing sent)', editor.includes('ARX100'), editor.slice(0, 120));
  await openConversation(agentA, 1, MONA);
  await selectStore(agentA, 'Lynomia Demo');
  text = await panelText(agentA);
  await shot(agentA, 'shopify-10-guest-suggested');
  check('a guest checkout found by the contact email is suggested, never linked automatically',
    text.includes('Possible match') && text.includes('Guest checkout') && text.includes('mo***@example.com'), text.slice(0, 220));
  await panel(agentA).getByRole('button', { name: 'Link', exact: true }).first().click();
  await agentA.waitForTimeout(3000);
  const guest = await order(agentA, 1010).catch(() => '');
  check('the linked guest shows its checkout: Shipped, tracking from the active fulfillment only', guest.includes('Shipped') && guest.includes('Track shipment'), guest);
  await openConversation(agentA, 1, VISITOR);
  await selectStore(agentA, 'Lynomia Demo');
  text = await panelText(agentA);
  await shot(agentA, 'shopify-11-multiple-matches');
  check('the same email as a registered customer and as a guest: several matches, the agent chooses',
    text.includes('Several store customers match') && text.includes('Registered customer') && text.includes('Guest checkout'), text.slice(0, 220));
  await openConversation(agentA, 1, NOBODY);
  await selectStore(agentA, 'Lynomia Demo');
  check('no match: customer not found', (await panelText(agentA)).includes('Customer not found in this store'));
  await openConversation(agentA, 1, LAYLA);
  await selectStore(agentA, 'Lynomia Demo');
  check('a phone with no Shopify customer: not found, no guest guessed by phone', (await panelText(agentA)).includes('Customer not found in this store'));

  // ---- F. Protected customer data and throttling -------------------------------------------------------------------
  console.log(sim('gql_mode denied'), sim(`age ${shop1.id}`));
  await openConversation(agentA, 1, NOBODY);
  await selectStore(agentA, 'Lynomia Demo');
  text = await panelText(agentA);
  await shot(agentA, 'shopify-12-protected-data');
  check('protected customer data not approved: the panel says so and invents no match', text.includes('has not approved Lynomia to read')
    && !text.includes('Registered customer'), text.slice(0, 200));
  console.log(sim('gql_mode throttled'), sim(`age ${shop1.id}`));
  await openConversation(agentA, 1, OMAR);
  await selectStore(agentA, 'Lynomia Demo');
  text = await panelText(agentA);
  await shot(agentA, 'shopify-13-throttled-stale');
  check('throttled by Shopify: cached orders are served, marked as not refreshed', text.includes("Couldn't refresh store data") && text.includes('#1006'), text.slice(0, 200));
  console.log(sim('gql_mode ok'));

  // ---- G. Webhooks with HMAC ----------------------------------------------------------------------------------------
  const event = { id: 6001005, name: '#1005', email: 'omar.khalil@example.com', customer: { id: 7001, email: 'omar.khalil@example.com' } };
  const refused = {
    missing: await deliver('orders/updated', SHOP1, event, { signature: null }),
    wrong: await deliver('orders/updated', SHOP1, event, { signature: 'bm90LXRoZS1zaWduYXR1cmU=' }),
    otherSecret: await deliver('orders/updated', SHOP1, event, { secret: 'legacy-shopify-app-secret' }),
    hex: await deliver('orders/updated', SHOP1, event, { signature: crypto.createHmac('sha256', SECRET).update(JSON.stringify(event)).digest('hex') })
  };
  check('deliveries without a signature, with a wrong one, signed with another secret or hex-encoded get 401',
    Object.values(refused).every(status => status === 401), JSON.stringify(refused));
  check('nothing queued for refused deliveries', !sim('queue')['Commerce::Shopify::WebhookJob']);
  console.log(sim(`order ${SHOP1} 1005 PAID FULFILLED`));
  const id = crypto.randomUUID();
  const accepted = await deliver('orders/updated', SHOP1, event, { id });
  const replayed = await deliver('orders/updated', SHOP1, event, { id });
  check('a signed delivery is accepted, and its retry (same webhook id) is acknowledged but queued once',
    accepted === 200 && replayed === 200 && sim('queue')['Commerce::Shopify::WebhookJob'] === 1);
  console.log(sim('jobs'));
  await openConversation(agentA, 1, OMAR);
  await selectStore(agentA, 'Lynomia Demo');
  const updated = await order(agentA, 1005);
  await shot(agentA, 'shopify-14-after-webhook');
  check("the order event dropped the cached orders: the panel shows Shopify's new status at once", updated.includes('Paid') && updated.includes('Shipped')
    && !updated.includes('Unpaid'), updated);
  check('the legacy webhook endpoint refuses a Commerce-signed delivery', await deliver('shop/redact', SHOP1, { shop_id: 68210001 }, { endpoint: '/webhooks/shopify' }) === 401);

  // ---- H. Token lifecycle -------------------------------------------------------------------------------------------
  const race = sim(`refresh_race ${shop1.id}`);
  check('10 concurrent readers of an expired token: one refresh request, one new token pair saved',
    race.token_requests === 1 && race.distinct_tokens === 1 && race.saved, JSON.stringify(race));
  let generation = sim('state').stores.find(s => s.id === shop1.id).token_generation;
  console.log(sim(`expire ${shop1.id}`), sim(`age ${shop1.id}`));
  await openConversation(agentA, 1, OMAR);
  await selectStore(agentA, 'Lynomia Demo');
  state = sim('state');
  check('an expired access token is refreshed before use: new access and refresh token stored, orders shown',
    state.stores.find(s => s.id === shop1.id).token_generation !== generation && (await panelText(agentA)).includes('#1006'));
  generation = state.stores.find(s => s.id === shop1.id).token_generation;
  console.log(sim(`invalidate_access ${SHOP1}`), sim(`age ${shop1.id}`));
  await openConversation(agentA, 1, OMAR);
  await selectStore(agentA, 'Lynomia Demo');
  state = sim('state');
  check('Shopify rejecting the token early (401): one controlled refresh and retry, orders shown',
    state.stores.find(s => s.id === shop1.id).token_generation !== generation && state.stores.find(s => s.id === shop1.id).status === 'active'
      && (await panelText(agentA)).includes('#1006'));
  const refreshesBefore = tokenRequests();
  console.log(sim('refresh_mode timeout_once'), sim(`expire ${shop1.id}`), sim(`age ${shop1.id}`));
  await openConversation(agentA, 1, OMAR);
  await selectStore(agentA, 'Lynomia Demo');
  state = sim('state');
  check('a refresh lost to a timeout is sent again with the same refresh token and Shopify returns the same pair',
    tokenRequests() - refreshesBefore === 2 && state.stores.find(s => s.id === shop1.id).status === 'active' && (await panelText(agentA)).includes('#1006'),
    `requests=${tokenRequests() - refreshesBefore}`);
  console.log(sim('refresh_mode invalid'), sim(`expire ${shop1.id}`), sim(`age ${shop1.id}`));
  await openConversation(agentA, 1, OMAR);
  await selectStore(agentA, 'Lynomia Demo').catch(() => {});
  text = await panelText(agentA);
  state = sim('state');
  check('Shopify refuses the refresh token: the store needs re-authorization, its tokens are removed and nothing stale is shown',
    state.stores.find(s => s.id === shop1.id).status === 'needs_reauth' && state.stores.find(s => s.id === shop1.id).credential_fields === null
      && !text.includes('#1006'), text.slice(0, 160));
  console.log(sim('refresh_mode ok'));
  await settingsPage(adminA, 1);
  await shot(adminA, 'shopify-15-needs-reauth');
  const reauthRow = (await storeRow(adminA, 'Lynomia Demo').innerText()).replace(/\s+/g, ' ');
  check('settings explain re-authorization and offer Reconnect', reauthRow.includes('Needs re-authorization') && reauthRow.includes('Reconnect'), reauthRow);
  await shopifyAuthorizes(adminA.context());
  await storeRow(adminA, 'Lynomia Demo').getByRole('button', { name: 'Reconnect' }).click();
  await adminA.waitForTimeout(600);
  const prefilled = await adminA.locator('dialog[open] input').inputValue();
  await adminA.locator('[data-test-id="shopify-connect"]').click();
  await adminA.waitForTimeout(4000);
  await adminA.context().unroute(/^https:\/\/[a-z0-9-]+\.myshopify\.com\/admin\/oauth\/authorize/);
  state = sim('state');
  check('Reconnect (domain prefilled) re-authorizes the same store in place', prefilled === SHOP1
    && state.stores.filter(s => s.external_store_id === '68210001').length === 1 && state.stores.find(s => s.external_store_id === '68210001').id === shop1.id
    && state.stores.find(s => s.id === shop1.id).status === 'active');

  // ---- I. Privacy webhooks and uninstall ----------------------------------------------------------------------------
  await openConversation(agentA, 1, OMAR);
  await selectStore(agentA, 'Lynomia Two');
  const contactsBefore = rails(`'puts Contact.where(account_id: 1).count'`);
  const conversationsBefore = rails(`'puts Conversation.where(account_id: 1).count'`);
  const customer = { id: 7001, email: 'omar.khalil@example.com', phone: '+966551112233' };
  const compliance = [
    await deliver('customers/data_request', SHOP2, { shop_id: 68210002, shop_domain: SHOP2, customer, orders_requested: [6001006], data_request: { id: 9999 } }),
    await deliver('customers/redact', SHOP2, { shop_id: 68210002, shop_domain: SHOP2, customer, orders_to_redact: [6001006] })
  ];
  console.log(sim('jobs'));
  state = sim('state');
  check('customers/data_request and customers/redact: 200; the customer\'s links in that shop are removed, recorded without personal data',
    compliance.every(status => status === 200) && state.stores.find(s => s.id === shop2.id).links.length === 0
      && state.audit.some(([comment, changes]) => comment === 'commerce.shopify.customer_data_requested' && changes.data_request_id === 9999)
      && state.audit.some(([comment]) => comment === 'commerce.shopify.customer_redacted') && !JSON.stringify(state.audit).includes('omar.khalil'),
    JSON.stringify(compliance));
  console.log(sim(`revoke ${SHOP2}`));
  const uninstall = await deliver('app/uninstalled', SHOP2, { id: 68210002, name: 'Lynomia Two', myshopify_domain: SHOP2 });
  console.log(sim('jobs'));
  state = sim('state');
  const gone = state.stores.find(s => s.id === shop2.id);
  check('app/uninstalled disconnects the store: token, links and cache removed; contacts and conversations stay',
    uninstall === 200 && gone.status === 'disconnected' && gone.credential_fields === null
      && rails(`'puts Contact.where(account_id: 1).count'`) === contactsBefore && rails(`'puts Conversation.where(account_id: 1).count'`) === conversationsBefore,
    JSON.stringify(gone));
  await settingsPage(adminA, 1);
  await shot(adminA, 'shopify-16-uninstalled');
  const redact = await deliver('shop/redact', SHOP2, { shop_id: 68210002, shop_domain: SHOP2 });
  console.log(sim('jobs'));
  state = sim('state');
  check('shop/redact deletes the store row; the account audit keeps the store id only', redact === 200 && !state.stores.some(s => s.id === shop2.id)
    && state.audit.some(([comment, changes]) => comment === 'commerce.shopify.shop_redacted' && changes.store_id === shop2.id)
    && rails(`'puts Conversation.where(account_id: 1).count'`) === conversationsBefore);

  // ---- J. Provider off, Commerce off, legacy untouched -------------------------------------------------------------
  console.log(sim('configure off'));
  await settingsPage(adminA, 1);
  await shot(adminA, 'shopify-17-provider-off');
  const offRow = (await storeRow(adminA, 'Lynomia Demo').innerText()).replace(/\s+/g, ' ');
  check('Shopify off: Shopify stores kept and explained', offRow.includes('Shopify is turned off'), offRow);
  await adminA.getByRole('button', { name: /add store/i }).click();
  await adminA.waitForTimeout(700);
  check('Shopify off: Add store shows Shopify as not available yet', await adminA.locator('[data-test-id="commerce-provider-shopify"]').isDisabled());
  await adminA.keyboard.press('Escape');
  const startOff = (await api(adminA, '/api/v1/accounts/1/commerce/shopify_connection', 'POST', { shop: SHOP2 })).body;
  check('Shopify off: no authorization can start', startOff.error?.code === 'PROVIDER_DISABLED', JSON.stringify(startOff));
  check('Shopify off: a privacy webhook is still accepted', await deliver('customers/redact', SHOP1, { shop_id: 68210001, shop_domain: SHOP1, customer: { id: 1 } }) === 200);
  console.log(sim('jobs'), sim('configure on'));
  console.log(rails('docs/commerce/e2e/rails/set.rb 2 feature=off'));
  await settingsPage(adminB, 2);
  const nav = await adminB.locator('aside').first().innerText();
  const startNoCommerce = (await api(adminB, '/api/v1/accounts/2/commerce/shopify_connection', 'POST', { shop: SHOP2 })).status;
  check('Commerce off for the account: no Commerce in settings and no Shopify authorization', !nav.includes('Commerce') && startNoCommerce === 401);
  console.log(rails('docs/commerce/e2e/rails/set.rb 2 feature=on'));
  const legacyAfter = sim('legacy_config');
  check('the legacy Shopify integration settings and hooks are exactly as before', JSON.stringify(legacyAfter) === JSON.stringify(legacyBefore),
    `${JSON.stringify(legacyBefore)} → ${JSON.stringify(legacyAfter)}`);

  // ---- K. Arabic and mobile -----------------------------------------------------------------------------------------
  console.log(rails('docs/commerce/e2e/rails/set.rb 1 locale=ar'));
  await settingsPage(adminA, 1);
  await adminA.getByRole('button', { name: /إضافة متجر/ }).click();
  await adminA.waitForTimeout(700);
  await shot(adminA, 'shopify-18-picker-arabic');
  await adminA.locator('[data-test-id="commerce-provider-shopify"]').click();
  await adminA.waitForTimeout(600);
  await shot(adminA, 'shopify-19-connect-dialog-arabic');
  check('Arabic: Shopify in the picker and الربط مع Shopify', (await adminA.locator('dialog[open]').innerText()).includes('الربط مع Shopify'));
  await openConversation(agentA, 1, OMAR);
  await selectStore(agentA, 'Lynomia Demo').catch(() => {});
  await shot(agentA, 'shopify-20-panel-arabic');
  console.log(rails('docs/commerce/e2e/rails/set.rb 1 locale=en'));
  const mobile = await newPage('admin_a@commerce.lynomia.local', { viewport: { width: 390, height: 844 } });
  await settingsPage(mobile, 1);
  await mobile.getByRole('button', { name: /add store/i }).click();
  await mobile.waitForTimeout(700);
  await mobile.locator('[data-test-id="commerce-provider-shopify"]').click();
  await mobile.waitForTimeout(600);
  await shot(mobile, 'shopify-21-mobile-connect-dialog');
  const overflow = await mobile.evaluate(() => {
    const dialog = document.querySelector('dialog[open]');
    return dialog ? dialog.scrollWidth > dialog.clientWidth + 1 : true;
  });
  check('mobile: the Connect with Shopify dialog fits the screen', !overflow);

  // ---- L. Secrets, audit, read-only ---------------------------------------------------------------------------------
  state = sim('state');
  reqs = requests();
  const events = state.audit.map(([comment]) => comment);
  check('audit trail: connected, token_refreshed, needs_reauth, reauthorized, uninstalled, shop_redacted',
    ['commerce.shopify.connected', 'commerce.shopify.token_refreshed', 'commerce.shopify.needs_reauth', 'commerce.shopify.reauthorized',
      'commerce.shopify.uninstalled', 'commerce.shopify.shop_redacted'].every(e => events.includes(e)), [...new Set(events)].join(', '));
  check('only queries were sent to Shopify: no mutation in any GraphQL request', reqs.operations.length > 0 && reqs.operations.every(o => o.startsWith('query ')),
    [...new Set(reqs.operations)].join(','));
  const tokens = /e2e-shp-(access|refresh)-\d+-\d+|e2e-shopify-code-\w+/;
  check('audit entries carry no token, code or secret', !tokens.test(JSON.stringify(state.audit)) && ![...secrets].some(s => JSON.stringify(state.audit).includes(s)));
  const leaked = apiBodies.filter(({ body }) => tokens.test(body) || [...secrets].some(s => body.includes(s)) || body.includes('"credentials"'));
  check('no Shopify token, code or client secret in any browser response', leaked.length === 0, `responses=${apiBodies.length} ${leaked.map(l => l.url).join(',')}`);
  const log = ['tmp/e2e_server.log', 'tmp/e2e_sim.log'].map(file => fs.readFileSync(`${REPO}/${file}`, 'utf8')).join('\n');
  const states = authorizeUrls.map(u => new URL(u).searchParams.get('state'));
  check('no token, code, state or client secret in the server or job logs', !tokens.test(log) && ![...secrets].some(s => log.includes(s))
    && !states.some(s => log.includes(s)), `log bytes=${log.length}`);
  check('no uncaught page errors', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));

  fs.writeFileSync(`${out}/shopify_e2e_results.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed`);
  await browser.close();
})().catch(async error => {
  console.error(error);
  fs.writeFileSync(`${out}/shopify_e2e_results.json`, JSON.stringify(results, null, 2));
  process.exit(1);
});
