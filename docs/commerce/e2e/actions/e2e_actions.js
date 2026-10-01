// Lynomia Commerce Phase 9–10 E2E (docs/commerce/33-phase9-10-e2e.md): order actions, abandoned carts and recovery
// messages, through the browser as agents and administrators use them.
//
//   gate  the production configuration: WooCommerce is a real, disposable test store (its own orders, created here,
//         never a merchant's) with a test-only refund gateway (../woocommerce/lynomia-e2e-gateway.php); Salla, Zid and
//         Shopify are connected (simulated) and switched on, and must stay without actions and carts before their UAT
//   sim   the same app restarted with COMMERCE_ALLOW_PRE_UAT_PROVIDERS (staging and simulations only): Zid and Shopify
//         actions, the Shopify write-scope reconnect, Salla/Zid/Shopify abandoned carts and recovery messages
//
// usage: node e2e_actions.js <gate|sim> <out_dir> <keys_json>   (keys_json: {"rw":{"ck","cs"},"s2":{"ck","cs"}})
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { execSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');

const B = 'http://localhost:3100';
const [phase, out, keysJson] = process.argv.slice(2);
const keys = JSON.parse(keysJson);
const ERUN = process.env.ERUN;
const WP = process.env.WP;
const SHOPIFY_SECRET = process.env.E2E_SHOPIFY_CLIENT_SECRET;
const LOGS = { server: process.env.SERVER_LOG, worker: process.env.WORKER_LOG, ctl: process.env.CTL_LOG };
const OMAR = { first_name: 'Omar', last_name: 'Khalil', phone: '0551112233', email: 'omar.khalil@example.com', country: 'SA' };
const results = [];
const apiBodies = [];
const pageErrors = [];
const frames = {};
const navigations = [];
const authorizeUrls = [];

const check = (name, ok, detail = '') => {
  results.push({ phase, name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  [${phase}] ${name}${detail ? `  -- ${detail}` : ''}`);
};
const sh = (command, input) => execSync(command, { input, stdio: [input ? 'pipe' : 'ignore', 'pipe', 'ignore'] }).toString();
const ctl = args => JSON.parse(sh(`${ERUN} "bundle exec rails runner docs/commerce/e2e/actions/ctl.rb ${args} 2>/dev/null | grep '^SIM ' | tail -1"`).slice(4));
const wp = args => {
  try {
    return sh(`${WP} ${args} 2>/dev/null`);
  } catch (error) {
    return error.stdout ? error.stdout.toString() : '';
  }
};
const wooPhp = (php, args = '') => JSON.parse(sh(`${WP} eval-file - ${args} 2>/dev/null`, php) || 'null');
const ORDER_PHP = `<?php
$o = wc_get_order( (int) $args[0] );
echo wp_json_encode( array(
  'status' => $o->get_status(), 'total' => $o->get_total(),
  'refunds' => array_map( function ( $r ) { return array( 'id' => $r->get_id(), 'amount' => $r->get_amount(),
    'key' => $r->get_meta( 'lynomia_action_key' ), 'payment' => $r->get_refunded_payment() ); }, $o->get_refunds() ),
  'notes' => array_map( function ( $n ) { return $n->content; }, wc_get_order_notes( array( 'order_id' => $o->get_id() ) ) ),
) );`;
const wooOrder = id => wooPhp(ORDER_PHP, id);
const gatewayCalls = () => wooPhp("<?php echo wp_json_encode( get_option( 'lynomia_e2e_gateway_calls', array() ) );");
const wooMails = () => wooPhp("<?php echo wp_json_encode( get_option( 'lynomia_e2e_mails', array() ) );");
const createWooOrder = ({ status, paid, method, title, product, quantity = 1 }) => wp(`wc shop_order create --user=1 --status=${status} --customer_id=0 `
  + `--set_paid=${paid} --payment_method=${method} --payment_method_title='${title}' --porcelain --billing='${JSON.stringify(OMAR)}' `
  + `--line_items='${JSON.stringify([{ product_id: product, quantity }])}'`).trim();
const runWooQueue = async () => { wp('action-scheduler run --hooks=woocommerce_deliver_webhook_async --batch-size=20'); };
const log = name => (LOGS[name] && fs.existsSync(LOGS[name]) ? fs.readFileSync(LOGS[name], 'utf8') : '');
const count = (name, pattern) => (log(name).match(pattern) || []).length;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const waitFor = async (predicate, timeout = 30000, step = 500, tick = null) => {
  const started = Date.now();
  while (Date.now() - started < timeout) {
    if (await predicate()) return Date.now() - started;
    if (tick) await tick();
    await sleep(step);
  }
  return null;
};
const clean = text => (text || '').replace(/\s+/g, ' ').trim();

// ---- Browser ----------------------------------------------------------------------------------------------------------------
let browser;
const newPage = async (email, viewport = { width: 1440, height: 1100 }) => {
  const context = await browser.newContext({ viewport });
  await context.addInitScript(() => {
    try {
      window.localStorage.setItem('lynomia.commerce.view', 'store');
    } catch {
      // documents without storage
    }
  });
  const page = await context.newPage();
  const key = frames[email] ? `${email} (${Object.keys(frames).length})` : email;
  frames[key] = [];
  page.on('pageerror', e => pageErrors.push(`${email}: ${e.message}`));
  page.on('framenavigated', frame => frame === page.mainFrame() && navigations.push(frame.url()));
  page.on('response', async r => {
    if (r.url().includes('/api/')) apiBodies.push({ url: r.url(), status: r.status(), body: await r.text().catch(() => '') });
  });
  page.on('websocket', ws => ws.on('framereceived', f => {
    if (String(f.payload).includes('commerce.customer.updated')) frames[key].push(String(f.payload));
  }));
  await page.goto(`${B}/app/login`, { waitUntil: 'networkidle' });
  await page.fill('input[name="email_address"], input[type="email"]', email);
  await page.fill('input[type="password"]', 'Password1!x');
  await page.keyboard.press('Enter');
  await page.waitForURL(/\/app\/accounts\/\d+/, { timeout: 60000 });
  return page;
};
const shot = (page, name) => page.screenshot({ path: `${out}/${name}.png`, fullPage: false });
const api = (page, url, method = 'GET', body) => page.evaluate(async ([u, m, b]) => {
  const raw = document.cookie.split('; ').find(c => c.startsWith('cw_d_session_info='));
  const info = JSON.parse(decodeURIComponent(raw.slice('cw_d_session_info='.length)));
  const response = await fetch(u, { method: m, headers: { 'access-token': info['access-token'], client: info.client, uid: info.uid,
    'Content-Type': 'application/json' }, body: b ? JSON.stringify(b) : undefined });
  return { status: response.status, body: await response.json().catch(() => null) };
}, [url, method, body]);
const both = (page, url, bodies) => page.evaluate(async ([u, list]) => {
  const raw = document.cookie.split('; ').find(c => c.startsWith('cw_d_session_info='));
  const info = JSON.parse(decodeURIComponent(raw.slice('cw_d_session_info='.length)));
  const headers = { 'access-token': info['access-token'], client: info.client, uid: info.uid, 'Content-Type': 'application/json' };
  return Promise.all(list.map(async b => {
    const response = await fetch(u, { method: 'POST', headers, body: JSON.stringify(b) });
    return { status: response.status, body: await response.json().catch(() => null) };
  }));
}, [url, bodies]);

const panel = page => page.locator('[data-test-id="commerce-panel"]');
const panelText = async page => clean(await panel(page).innerText({ timeout: 2000 }).catch(() => ''));
const orderCard = (page, number) => panel(page).locator('[data-test-id="commerce-order"]', { hasText: new RegExp(`#${number}(?!\\d)`) }).first();
const cardText = async (page, number) => clean(await orderCard(page, number).innerText({ timeout: 1000 }).catch(() => ''));
const openConversation = async (page, id = 1) => {
  await page.goto(`${B}/app/accounts/1/conversations/${id}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(3500);
};
const selectStore = async (page, name) => {
  if (await page.locator('[data-test-id="commerce-view-store"]').count()) await page.locator('[data-test-id="commerce-view-store"]').click();
  await page.waitForTimeout(1500);
  await panel(page).locator('select').first().selectOption({ label: name });
  await page.waitForTimeout(3500);
};
// The Overview lists every store's abandoned carts; a reload reads them again (Refresh reads orders only).
const openOverview = async page => {
  await openConversation(page);
  if (await page.locator('[data-test-id="commerce-view-overview"]').count()) await page.locator('[data-test-id="commerce-view-overview"]').click();
  await page.locator('[data-test-id="commerce-overview"]').waitFor({ timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(3000);
};
const refreshPanel = async page => {
  await panel(page).locator('[data-test-id="commerce-refresh"]').click();
  await page.waitForTimeout(3500);
};
const settingsPage = async page => {
  await page.goto(`${B}/app/accounts/1/settings/commerce`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(2500);
};
const storeRow = (page, name) => page.locator('[data-test-id="commerce-store-row"]', { hasText: name });
const rowText = async (page, name) => clean(await storeRow(page, name).innerText().catch(() => ''));
const addStore = async (page, { url, name, ck, cs }) => {
  await page.getByRole('button', { name: /add store|إضافة متجر/i }).click();
  await page.waitForTimeout(600);
  if (await page.locator('[data-test-id="commerce-provider-woocommerce"]').count()) {
    await page.locator('[data-test-id="commerce-provider-woocommerce"]').click();
    await page.waitForTimeout(500);
  }
  await page.getByLabel(/Store URL|رابط المتجر/).fill(url);
  if (name) await page.getByLabel(/Display name|اسم العرض/).fill(name);
  await page.getByLabel('Consumer key').fill(ck);
  await page.getByLabel('Consumer secret').fill(cs);
  await page.getByRole('button', { name: /test and connect|اختبار وربط/i }).click();
  await page.waitForTimeout(4000);
};

// ---- The order actions dialog -------------------------------------------------------------------------------------------------
const dialog = page => page.locator('dialog[open]').last();
const dialogText = async page => clean(await dialog(page).innerText().catch(() => ''));
const openActions = async (page, number) => {
  await orderCard(page, number).locator('[data-test-id="commerce-order-actions"]').click();
  await dialog(page).locator('[data-test-id="commerce-action-dialog"]').waitFor({ timeout: 10000 });
  await waitFor(async () => !(await dialogText(page)).includes('Reading the order from the store'), 30000, 250);
  return dialogText(page);
};
const choose = (page, type) => dialog(page).locator(`[data-test-id="commerce-action-${type}"]`).click();
const amountInput = page => dialog(page).locator('[data-test-id="commerce-action-amount"] input, input[data-test-id="commerce-action-amount"]').first();
const review = async page => {
  await dialog(page).locator('[data-test-id="commerce-action-review-button"]').click();
  await page.waitForTimeout(300);
};
const confirm = async (page, { double = false } = {}) => {
  const button = dialog(page).locator('[data-test-id="commerce-action-confirm"]');
  if (double) await button.dblclick();
  else await button.click();
};
const resultText = async page => clean(await dialog(page).locator('[data-test-id="commerce-action-result"]').innerText().catch(() => ''));
const waitResult = async (page, pattern, timeout = 60000) => {
  const ms = await waitFor(async () => pattern.test(await resultText(page)), timeout, 500);
  return { ms, text: await resultText(page) };
};
const closeDialog = async page => {
  if (!(await page.locator('dialog[open]').count())) return;
  const close = dialog(page).getByRole('button', { name: /^(Close|إغلاق)$/ });
  if (await close.count()) await close.click().catch(() => {});
  else await page.keyboard.press('Escape');
  await page.waitForTimeout(500);
};
// One action through the dialog: open, choose, fill, review, confirm; returns the review and the final result.
const act = async (page, number, type, { amount, select, double = false, beforeConfirm, expect = /Done\.|didn’t|refused|changed|can’t|isn’t|answer in time/, timeout = 60000 } = {}) => {
  const menu = await openActions(page, number);
  await choose(page, type);
  await page.waitForTimeout(400);
  if (amount !== undefined) await amountInput(page).fill(amount);
  if (select) await dialog(page).locator('select').first().selectOption(select);
  if (await dialog(page).locator('[data-test-id="commerce-action-review-button"]').count()) await review(page);
  const reviewText = clean(await dialog(page).locator('[data-test-id="commerce-action-review"]').innerText().catch(() => ''));
  const consequence = clean(await dialog(page).locator('[data-test-id="commerce-action-consequence"]').innerText().catch(() => ''));
  if (beforeConfirm) await beforeConfirm();
  await confirm(page, { double });
  const result = await waitResult(page, expect, timeout);
  return { menu, review: reviewText, consequence, ...result };
};
const actionsUrl = (storeId, orderId) => `${B}/api/v1/accounts/1/conversations/1/commerce/stores/${storeId}/orders/${orderId}/actions`;
const availability = async (page, storeId, orderId) => (await api(page, actionsUrl(storeId, orderId))).body;
const runs = () => ctl('runs').runs;
const runByKey = key => runs().find(run => run.idempotency_key === key);
const waitRun = async (key, statuses, timeout = 60000) => {
  let run;
  await waitFor(async () => {
    run = runByKey(key);
    return run && statuses.includes(run.status);
  }, timeout, 2000);
  return run;
};
const newKey = () => `commerce-action:${crypto.randomUUID()}`;

// ---- Shopify's authorization page (as in ../shopify/e2e_shopify.js): approve and redirect back with a signed query ----------
const signCallback = params => {
  const query = new URLSearchParams();
  Object.keys(params).sort((a, b) => a.localeCompare(b)).forEach(key => query.append(key, params[key]));
  return crypto.createHmac('sha256', SHOPIFY_SECRET).update(query.toString().replace(/\+/g, '%20')).digest('hex');
};
const shopifyAuthorizes = context => context.route(/^https:\/\/[a-z0-9-]+\.myshopify\.com\/admin\/oauth\/authorize/, route => {
  const url = new URL(route.request().url());
  authorizeUrls.push(url.toString());
  const params = { code: `e2e-shopify-code-${Date.now()}`, host: Buffer.from(`admin.shopify.com/store/${url.host.split('.')[0]}`).toString('base64').replace(/=+$/, ''),
    shop: url.host, state: url.searchParams.get('state'), timestamp: String(Math.floor(Date.now() / 1000)) };
  const back = new URL(url.searchParams.get('redirect_uri'));
  Object.entries(params).forEach(([key, value]) => back.searchParams.set(key, value));
  back.searchParams.set('hmac', signCallback(params));
  return route.fulfill({ status: 302, headers: { Location: back.toString() } });
});

// ---- gate: WooCommerce for real, the other providers held back ----------------------------------------------------------------
const gate = async () => {
  wp('option delete lynomia_e2e_gateway_calls');
  wp('option delete lynomia_e2e_mails');
  console.log(JSON.stringify(ctl('reset')));
  const defaults = ctl('defaults');
  check('production defaults: WooCommerce read on, order actions switch on (each store still opts in), Salla/Zid/Shopify off',
    defaults.read.woocommerce && !defaults.read.salla && !defaults.read.zid && !defaults.read.shopify && defaults.actions.woocommerce
      && !defaults.actions.salla && !defaults.actions.zid && !defaults.actions.shopify, JSON.stringify(defaults.actions));
  check('production defaults: recovery off everywhere (WooCommerce has no abandoned-cart API), no pre-UAT override',
    Object.values(defaults.recovery).every(value => value === false) && defaults.pre_uat_override === null
      && JSON.stringify(defaults.configured) === JSON.stringify(defaults.defaults), JSON.stringify(defaults.recovery));

  // Disposable orders of the test store's guest customer Omar, made for this run. The two checked through the API only
  // come first: the panel shows a customer's latest 5 orders, the ones the dialog is used on.
  const card = { method: 'lynomia_e2e', title: 'Lynomia E2E Card' };
  const cash = { method: 'cod', title: 'Cash on delivery' };
  const bank = { method: 'bacs', title: 'Direct bank transfer' };
  const o = {};
  // One order per API check, so the per-order rate limit (5 requests in 10 minutes) of one check never blocks another.
  o.api = createWooOrder({ status: 'processing', paid: true, ...card, product: 12 });
  o.limit = createWooOrder({ status: 'processing', paid: true, ...cash, product: 11 });
  o.status = createWooOrder({ status: 'processing', paid: true, ...card, product: 11 });
  o.cancel = createWooOrder({ status: 'pending', paid: false, ...card, product: 12 });
  o.refund = createWooOrder({ status: 'processing', paid: true, ...card, product: 10, quantity: 2 });
  o.manual = createWooOrder({ status: 'processing', paid: true, ...bank, product: 13 });
  o.lost = createWooOrder({ status: 'processing', paid: true, ...card, product: 10 });
  check('disposable WooCommerce orders created for this run (never a merchant order)', Object.values(o).every(id => /^\d+$/.test(id)), JSON.stringify(o));
  fs.writeFileSync(`${out}/woo_orders.json`, JSON.stringify(o));

  // ---- A. Settings: capabilities shown separately --------------------------------------------------------------------------
  const adminA = await newPage('admin_a@commerce.lynomia.local', { width: 1440, height: 1000 });
  await settingsPage(adminA);
  await addStore(adminA, { url: 'http://localhost:8081', name: 'Syria Cosmetics', ck: keys.rw.ck, cs: keys.rw.cs });
  await addStore(adminA, { url: 'http://localhost:8082', name: 'Damascus Perfumes', ck: keys.s2.ck, cs: keys.s2.cs });
  await waitFor(async () => {
    await adminA.reload({ waitUntil: 'networkidle' });
    return (await rowText(adminA, 'Syria Cosmetics')).includes('Live order updates on');
  }, 40000, 2500);
  let syria = await rowText(adminA, 'Syria Cosmetics');
  const damascus = await rowText(adminA, 'Damascus Perfumes');
  check('Read/Write key: Read-only Commerce, live updates and order actions shown separately; actions off until opted in',
    syria.includes('Read-only Commerce: on') && syria.includes('Live order updates on') && syria.includes('Order actions: off')
      && syria.includes('Turn on order actions') && syria.includes('Refunds and cancellations stay limited to administrators.'), syria);
  check('Read key: "Order actions require a Read/Write WooCommerce API key." and nothing to turn on; the key is not upgraded',
    damascus.includes('Read-only Commerce: on') && damascus.includes('Order actions require a Read/Write WooCommerce API key.')
      && !damascus.includes('Turn on order actions'), damascus);
  await shot(adminA, 'a01-settings-capabilities-en');

  // ---- B. Salla, Zid and Shopify switched on by Super Admin: still nothing before their UAT ---------------------------------
  console.log(JSON.stringify(ctl('connect')));
  ['SALLA_ACTIONS_ENABLED', 'ZID_ACTIONS_ENABLED', 'SHOPIFY_COMMERCE_ACTIONS_ENABLED', 'SALLA_RECOVERY_ENABLED', 'ZID_RECOVERY_ENABLED',
    'SHOPIFY_COMMERCE_RECOVERY_ENABLED'].forEach(name => ctl(`switch ${name} true`));
  const held = ctl('defaults');
  check('switches on for Salla/Zid/Shopify, yet their actions and carts stay off: providers before UAT are held back',
    !held.actions.salla && !held.actions.zid && !held.actions.shopify && !held.recovery.salla && !held.recovery.zid && !held.recovery.shopify,
    JSON.stringify({ actions: held.actions, recovery: held.recovery }));
  await settingsPage(adminA);
  const zidRow = await rowText(adminA, 'متجر الياسمين');
  const shopifyRow = await rowText(adminA, 'Lynomia Demo');
  const sallaRow = await rowText(adminA, 'متجر الورد');
  check('settings: Zid and Shopify say order actions are switched off on this installation; Salla offers none',
    zidRow.includes('Order actions are switched off on this installation.') && shopifyRow.includes('Order actions are switched off on this installation.')
      && !zidRow.includes('Turn on order actions') && !shopifyRow.includes('Turn on order actions') && !sallaRow.includes('Order actions'),
    `${zidRow.slice(0, 120)} | ${shopifyRow.slice(0, 120)}`);
  check('no abandoned-cart queue while no store offers carts', await adminA.locator('[data-test-id="commerce-cart-queue"]').count() === 0);

  // ---- C. The administrator opts the store in ---------------------------------------------------------------------------------
  await storeRow(adminA, 'Syria Cosmetics').locator('[data-test-id="commerce-store-order-actions-toggle"]').click();
  await adminA.waitForTimeout(2500);
  syria = await rowText(adminA, 'Syria Cosmetics');
  check('the administrator turns order actions on for the Read/Write store', syria.includes('Order actions: on') && syria.includes('Turn off order actions'), syria);
  await shot(adminA, 'a02-settings-actions-on-en');

  // ---- D. Customer 360: who sees actions ---------------------------------------------------------------------------------------
  await runWooQueue();
  const agentA = await newPage('agent_a@commerce.lynomia.local');
  await openConversation(adminA);
  await selectStore(adminA, 'Syria Cosmetics');
  await refreshPanel(adminA);
  await openConversation(agentA);
  await selectStore(agentA, 'Syria Cosmetics');
  await agentA.evaluate(() => { window.lynomiaNoReload = true; });
  const stores = (await api(adminA, `${B}/api/v1/accounts/1/conversations/1/commerce/stores`)).body;
  const storeList = Array.isArray(stores) ? stores : stores.payload || stores.stores || [];
  const syriaId = storeList.find(store => store.name === 'Syria Cosmetics').id;
  const damascusId = storeList.find(store => store.name === 'Damascus Perfumes').id;
  check('the administrator sees the order actions menu on the opted-in store\'s orders', await orderCard(adminA, o.status).locator('[data-test-id="commerce-order-actions"]').count() === 1,
    await cardText(adminA, o.status));
  check('an agent without the order permission sees no actions menu at all', await cardText(agentA, o.status) !== ''
    && await orderCard(agentA, o.status).locator('[data-test-id="commerce-order-actions"]').count() === 0, await cardText(agentA, o.status));

  // ---- E. Status change ---------------------------------------------------------------------------------------------------------
  const framesBefore = frames['agent_a@commerce.lynomia.local'].length;
  let menu = await openActions(adminA, o.status);
  check('menu of a paid processing order: status, resend, refunds; cancel explained as "refund it first"; never trash',
    menu.includes('Change status') && menu.includes('Refund in full') && menu.includes('The order is paid: refund it first.')
      && !/trash|delete/i.test(menu), menu.slice(0, 260));
  await shot(adminA, 'a03-actions-menu-en');
  await closeDialog(adminA);
  const statusOptions = [];
  let res = await act(adminA, o.status, 'update_order_status', {
    beforeConfirm: async () => { await shot(adminA, 'a04-status-review-en'); },
    select: undefined,
  }).catch(error => ({ text: error.message }));
  const statusRun = runs().filter(run => run.action_type === 'update_order_status').at(-1);
  check('status change: the review names store, provider, order and the change; done after the store confirms',
    /Syria Cosmetics · WooCommerce/.test(res.review || '') && (res.review || '').includes(`#${o.status}`)
      && /from Processing to Completed/.test(res.consequence || '') && /Done\./.test(res.text), `${res.consequence} | ${res.text}`);
  check('WooCommerce has the order completed, written once', wooOrder(o.status).status === 'completed' && statusRun?.status === 'succeeded',
    `${wooOrder(o.status).status} run=${statusRun?.status}`);
  await closeDialog(adminA);
  const liveMs = await waitFor(async () => (await cardText(agentA, o.status)).includes('Completed'), 30000, 500, runWooQueue);
  check('another agent\'s open panel shows the new status live, without a reload', liveMs !== null
    && await agentA.evaluate(() => window.lynomiaNoReload === true) && frames['agent_a@commerce.lynomia.local'].length > framesBefore,
  `ms=${liveMs} frames=${frames['agent_a@commerce.lynomia.local'].length - framesBefore}`);
  statusOptions.push(...(await availability(adminA, syriaId, o.status)).actions.update_order_status?.targets || []);

  // ---- F. Resend invoice ---------------------------------------------------------------------------------------------------------
  const mailsBefore = wooMails().length;
  res = await act(adminA, o.status, 'resend_invoice');
  const mails = wooMails().slice(mailsBefore);
  check('resend invoice: WooCommerce emails the order details once, to the order\'s billing email',
    /Done\./.test(res.text) && mails.length === 1 && String(mails[0].to).includes(OMAR.email) && mails[0].subject.includes(`#${o.status}`)
      && wooOrder(o.status).notes.some(note => note.includes('Order details sent to')), `${res.consequence} | mails=${JSON.stringify(mails)}`);
  await closeDialog(adminA);

  // ---- G. Cancel (unpaid) ---------------------------------------------------------------------------------------------------------
  await refreshPanel(adminA);
  res = await act(adminA, o.cancel, 'cancel_order');
  check('cancel an unpaid order: the review says cancelling refunds nothing; WooCommerce cancels it, no refund, no gateway call',
    res.consequence.includes('Cancelling does not refund any payment.') && /Done\./.test(res.text) && wooOrder(o.cancel).status === 'cancelled'
      && wooOrder(o.cancel).refunds.length === 0 && gatewayCalls().length === 0, `${res.consequence} | ${wooOrder(o.cancel).status}`);
  await closeDialog(adminA);

  // ---- H. Partial refund: two-phase, no Enter, one refund for a double click ------------------------------------------------------
  menu = await openActions(adminA, o.refund);
  await choose(adminA, 'refund_partial');
  await amountInput(adminA).fill('9999');
  await review(adminA);
  const tooMuch = await dialogText(adminA);
  await amountInput(adminA).fill('10.00');
  await amountInput(adminA).press('Enter');
  await adminA.waitForTimeout(800);
  const afterEnter = await dialogText(adminA);
  await review(adminA);
  const refundReview = await dialogText(adminA);
  await shot(adminA, 'a05-refund-review-en');
  const runsBeforeEnter = runs().length;
  await adminA.keyboard.press('Enter');
  await adminA.waitForTimeout(1200);
  const runsAfterEnter = runs().length;
  check('refund form: an amount above the refundable maximum is refused before review', tooMuch.includes('Enter an amount above 0 and up to'), tooMuch.slice(0, 200));
  check('Enter submits nothing: not in the amount field, not on the review', afterEnter.includes('Reason') && !afterEnter.includes('Check before confirming')
    && runsAfterEnter === runsBeforeEnter, `runs ${runsBeforeEnter}→${runsAfterEnter}`);
  check('refund review: store, order, amount and currency, the gateway and "can’t be undone"', refundReview.includes('Syria Cosmetics · WooCommerce')
    && refundReview.includes(`#${o.refund}`) && /10\.00/.test(refundReview) && /SAR|ر\.س/.test(refundReview)
    && refundReview.includes('through Lynomia E2E Card') && refundReview.includes('can’t be undone'), refundReview.slice(0, 300));
  await confirm(adminA, { double: true });
  res = await waitResult(adminA, /Done\.|didn’t|refused/, 60000);
  let state = wooOrder(o.refund);
  const partialRun = runs().filter(run => run.action_type === 'refund_partial').at(-1);
  check('a double-clicked Confirm makes one run and one refund of 10.00 through the gateway', /Done\./.test(res.text)
    && state.refunds.length === 1 && state.refunds[0].amount === '10.00' && state.refunds[0].payment === true
    && gatewayCalls().filter(call => String(call.order_id) === o.refund).length === 1 && runs().filter(run => run.action_type === 'refund_partial').length === 1,
  JSON.stringify(state.refunds));
  check('the refund carries the run\'s idempotency key in WooCommerce (how a lost answer is reconciled)', state.refunds[0]?.key === partialRun?.idempotency_key
    && /^commerce-action:[0-9a-f-]{36}$/.test(partialRun?.idempotency_key || ''), partialRun?.idempotency_key);
  await closeDialog(adminA);

  // ---- I. Idempotency through the API ---------------------------------------------------------------------------------------------
  let avail = await availability(adminA, syriaId, o.refund);
  const replay = await api(adminA, actionsUrl(syriaId, o.refund), 'POST', { action_type: 'refund_partial', version: avail.version,
    idempotency_key: partialRun.idempotency_key, params: { amount: '10.00', currency: 'SAR', reason: 'customer_request' } });
  const conflict = await api(adminA, actionsUrl(syriaId, o.refund), 'POST', { action_type: 'refund_partial', version: avail.version,
    idempotency_key: partialRun.idempotency_key, params: { amount: '11.00', currency: 'SAR', reason: 'customer_request' } });
  check('the same key again answers the same run; with other values it is refused (IDEMPOTENCY_CONFLICT)', replay.status === 202 && replay.body.id === partialRun.id
    && conflict.status === 422 && conflict.body.error.code === 'IDEMPOTENCY_CONFLICT', `${replay.status} ${conflict.status} ${JSON.stringify(conflict.body)}`);
  const sameKey = newKey();
  avail = await availability(adminA, syriaId, o.api);
  const twin = { action_type: 'refund_partial', version: avail.version, idempotency_key: sameKey, params: { amount: '1.00', currency: 'SAR', reason: 'duplicate' } };
  const pair = await both(adminA, actionsUrl(syriaId, o.api), [twin, twin]);
  await waitRun(sameKey, ['succeeded', 'failed', 'unknown']);
  state = wooOrder(o.api);
  check('two simultaneous requests with one key: one run, one refund in WooCommerce', pair.every(r => r.status === 202) && pair[0].body.id === pair[1].body.id
    && state.refunds.length === 1 && state.refunds[0].key === sameKey && gatewayCalls().filter(call => String(call.order_id) === o.api).length === 1,
  `${pair.map(r => r.status)} refunds=${state.refunds.length}`);

  // ---- J. The order changed after review: nothing is sent ---------------------------------------------------------------------------
  await refreshPanel(adminA);
  const callsBefore = gatewayCalls().length;
  res = await act(adminA, o.refund, 'refund_partial', { amount: '5.00', beforeConfirm: async () => { wp(`wc shop_order update ${o.refund} --status=on-hold --user=1`); } });
  state = wooOrder(o.refund);
  check('the order changed in the store after review: the action stops, nothing is sent (ORDER_CHANGED)', res.text.includes('The order changed in the store')
    && state.refunds.length === 1 && gatewayCalls().length === callsBefore, res.text);
  await closeDialog(adminA);
  wp(`wc shop_order update ${o.refund} --status=processing --user=1`);

  // ---- K. The gateway declines; an answer is lost and reconciled by reading -------------------------------------------------------
  await refreshPanel(adminA);
  res = await act(adminA, o.lost, 'refund_partial', { amount: '13.13' });
  check('the gateway declines: the dialog says so and no refund exists', res.text.includes('The payment gateway refused the refund') && wooOrder(o.lost).refunds.length === 0, res.text);
  await closeDialog(adminA);
  res = await act(adminA, o.lost, 'refund_partial', { amount: '7.77', expect: /answer in time|Done\.|Still being processed/, timeout: 70000 });
  await shot(adminA, 'a06-refund-unknown-en');
  const lostRun = runs().filter(run => run.action_type === 'refund_partial' && run.external_resource_id === o.lost).at(-1);
  check('no answer within the timeout: the run is unknown and the dialog says not to try again', res.text.includes('The store didn’t answer in time')
    && lostRun.status === 'unknown', `${res.text} run=${lostRun.status}`);
  await closeDialog(adminA);
  avail = await availability(adminA, syriaId, o.lost);
  check('while unknown, no other action on the order is possible', avail.actions.refund_partial.available === false
    && avail.actions.refund_partial.reason === 'action_in_progress' && avail.last_run.status === 'unknown', JSON.stringify(avail.actions.refund_partial));
  const settled = await waitRun(lostRun.idempotency_key, ['succeeded', 'failed'], 150000);
  state = wooOrder(o.lost);
  check('reconciled by reading WooCommerce: the refund made after the timeout is found by its key; nothing was sent again',
    settled?.status === 'succeeded' && settled.metadata.reconcile_attempts >= 1 && state.refunds.length === 1 && state.refunds[0].key === lostRun.idempotency_key
      && gatewayCalls().filter(call => call.amount === '7.77').length === 1, `run=${settled?.status} ${JSON.stringify(settled?.metadata)} refunds=${state.refunds.length}`);

  // ---- L. Full refund, manual refund, over-refund -----------------------------------------------------------------------------------
  await refreshPanel(adminA);
  menu = await openActions(adminA, o.refund);
  await choose(adminA, 'refund_full');
  const fullAmount = await amountInput(adminA).inputValue();
  const fullDisabled = await amountInput(adminA).isDisabled();
  await review(adminA);
  await confirm(adminA);
  res = await waitResult(adminA, /Done\.|didn’t|refused/, 60000);
  state = wooOrder(o.refund);
  const refundedTotal = state.refunds.reduce((sum, refund) => sum + Number(refund.amount), 0);
  check('refund in full: the remaining refundable amount, fixed; WooCommerce marks the order refunded', fullDisabled && fullAmount === '230.00'
    && /Done\./.test(res.text) && state.status === 'refunded' && Math.abs(refundedTotal - Number(state.total)) < 0.001, `amount=${fullAmount} status=${state.status}`);
  await closeDialog(adminA);
  menu = await openActions(adminA, o.refund);
  check('nothing is left to refund afterwards', menu.includes('Nothing is left to refund.') || menu.includes('The order isn’t paid.'), menu.slice(0, 200));
  await closeDialog(adminA);

  const cod = (await availability(adminA, syriaId, o.limit)).actions.refund_partial;
  check('cash on delivery in processing is not paid yet (WooCommerce sets no payment date): no refund offered',
    cod.available === false && cod.reason === 'not_paid', JSON.stringify(cod));
  const callsBeforeManual = gatewayCalls().length;
  res = await act(adminA, o.manual, 'refund_partial', { amount: '20.00' });
  state = wooOrder(o.manual);
  check('a gateway without refunds: the review says the refund is recorded only; WooCommerce records it, no money moves',
    res.consequence.includes('The store will record a refund of') && res.consequence.includes('No money is sent to the customer') && /Done\./.test(res.text)
      && state.refunds.length === 1 && state.refunds[0].payment === false && gatewayCalls().length === callsBeforeManual, res.consequence);
  await closeDialog(adminA);
  avail = await availability(adminA, syriaId, o.manual);
  const overKey = newKey();
  const over = await api(adminA, actionsUrl(syriaId, o.manual), 'POST', { action_type: 'refund_partial', version: avail.version, idempotency_key: overKey,
    params: { amount: '500.00', currency: 'SAR', reason: 'other' } });
  const overRun = over.status === 202 ? await waitRun(overKey, ['failed', 'succeeded']) : null;
  check('more than the provider-confirmed refundable amount is never sent (INVALID_AMOUNT)', (over.status === 422 && over.body.error.code === 'INVALID_AMOUNT')
    || (overRun?.status === 'failed' && overRun.error_code === 'INVALID_AMOUNT'), `${over.status} ${overRun?.error_code}`);
  check('…and WooCommerce has no new refund', wooOrder(o.manual).refunds.length === 1);

  // ---- M. Permissions, cross-store and rate limits ---------------------------------------------------------------------------------
  const agentTry = await api(agentA, actionsUrl(syriaId, o.manual), 'POST', { action_type: 'refund_partial', version: avail.version, idempotency_key: newKey(),
    params: { amount: '1.00', currency: 'SAR', reason: 'other' } });
  check('an agent cannot refund through the API either', [401, 403].includes(agentTry.status) && wooOrder(o.manual).refunds.length === 1, `${agentTry.status}`);
  const readKeyTry = await api(adminA, actionsUrl(damascusId, o.manual));
  check('the Read-key store refuses actions (and does not know the other store\'s order)', readKeyTry.status === 422 || readKeyTry.status === 404,
    `${readKeyTry.status} ${JSON.stringify(readKeyTry.body)}`);
  avail = await availability(adminA, syriaId, o.limit);
  const burst = [];
  for (let i = 0; i < 6; i += 1) {
    burst.push(await api(adminA, actionsUrl(syriaId, o.limit), 'POST', { action_type: 'cancel_order', version: avail.version, idempotency_key: newKey(),
      params: { reason: 'other' } }));
  }
  await sleep(4000);
  const limited = burst.at(-1);
  check('rate limit: the sixth request on one order within 10 minutes gets 429 with Retry-After; refused runs wrote nothing',
    burst[0].status === 202 && burst.slice(1, 5).every(r => r.status === 202 || (r.status === 422 && r.body.error.code === 'ACTION_IN_PROGRESS'))
      && limited.status === 429 && limited.body.error.retry_after > 0 && wooOrder(o.limit).status === 'processing'
      && runs().filter(run => run.external_resource_id === o.limit).every(run => run.status === 'failed' && run.error_code === 'ACTION_UNAVAILABLE'),
    `${burst.map(r => r.status)} ${JSON.stringify(limited.body)}`);

  // ---- N. Kill switch -------------------------------------------------------------------------------------------------------------
  ctl('switch COMMERCE_ACTIONS_ENABLED false');
  await openConversation(adminA);
  await selectStore(adminA, 'Syria Cosmetics');
  const switchedOff = await api(adminA, actionsUrl(syriaId, o.manual), 'POST', { action_type: 'update_order_status', version: avail.version, idempotency_key: newKey(),
    params: { target_status: 'completed' } });
  check('COMMERCE_ACTIONS_ENABLED=false: no actions menu, requests refused (ACTIONS_DISABLED), orders still shown read-only',
    await panel(adminA).locator('[data-test-id="commerce-order-actions"]').count() === 0 && (await cardText(adminA, o.manual)).includes(`#${o.manual}`)
      && switchedOff.status === 422 && switchedOff.body.error.code === 'ACTIONS_DISABLED', `${switchedOff.status} ${JSON.stringify(switchedOff.body)}`);
  ctl('switch COMMERCE_ACTIONS_ENABLED true');

  // ---- O. A key that loses its write permission ------------------------------------------------------------------------------------
  wp("db query \"UPDATE wp_woocommerce_api_keys SET permissions='read' WHERE description='Lynomia Commerce Realtime E2E'\"");
  await openConversation(adminA);
  await selectStore(adminA, 'Syria Cosmetics');
  res = await act(adminA, o.manual, 'update_order_status', { select: 'on_hold' });
  check('WooCommerce refuses the write (the key became read-only): the dialog says the credentials can\'t change orders',
    res.text.includes('can’t change orders') && wooOrder(o.manual).status === 'processing', res.text);
  await closeDialog(adminA);
  await settingsPage(adminA);
  syria = await rowText(adminA, 'Syria Cosmetics');
  check('settings now ask for a Read/Write key; nothing was upgraded or retried silently', syria.includes('Order actions require a Read/Write WooCommerce API key.'), syria);
  wp("db query \"UPDATE wp_woocommerce_api_keys SET permissions='read_write' WHERE description='Lynomia Commerce Realtime E2E'\"");
  await storeRow(adminA, 'Syria Cosmetics').getByRole('button', { name: 'Replace keys' }).click();
  await adminA.waitForTimeout(600);
  await adminA.getByLabel('Consumer key').fill(keys.rw.ck);
  await adminA.getByLabel('Consumer secret').fill(keys.rw.cs);
  await dialog(adminA).getByRole('button', { name: 'Test and save' }).click();
  await waitFor(async () => {
    await adminA.reload({ waitUntil: 'networkidle' });
    return (await rowText(adminA, 'Syria Cosmetics')).includes('Order actions: on');
  }, 40000, 2500);
  syria = await rowText(adminA, 'Syria Cosmetics');
  check('the administrator replaces the key with a Read/Write one: order actions on again (the opt-in was kept)', syria.includes('Order actions: on'), syria);

  // ---- P. WooCommerce has no abandoned carts ---------------------------------------------------------------------------------------
  const carts = (await api(adminA, `${B}/api/v1/accounts/1/conversations/1/commerce/carts`)).body;
  check('WooCommerce: no abandoned carts (no merchant-wide API in WooCommerce core); none shown, nothing else asked of the store',
    !(carts.stores || []).some(view => view.store.provider === 'woocommerce' && view.state === 'ok')
      && !(carts.stores || []).some(view => view.state === 'ok') && await adminA.locator('[data-test-id="commerce-carts"]').count() === 0,
    JSON.stringify((carts.stores || []).map(view => [view.store.provider, view.state, view.error])));

  // ---- Q. Audit, what runs keep, Arabic and mobile -----------------------------------------------------------------------------
  const audit = ctl('audit').audit;
  const events = new Set(audit.map(entry => entry.event));
  check('audit trail: requested, succeeded, failed, reconciled, order actions changed', ['commerce.action.requested', 'commerce.action.succeeded',
    'commerce.action.failed', 'commerce.action.reconciled', 'commerce.order_actions_changed'].every(event => events.has(event)), [...events].join(','));
  const allRuns = runs();
  const runJson = JSON.stringify(allRuns);
  const metadataKeys = new Set(allRuns.flatMap(run => Object.keys(run.metadata || {})));
  check('action runs keep no addresses, contact details, tokens, payment data or order JSON', !/omar\.khalil|0551112233|King Fahd|billing|address|ck_|cs_|line_items/i.test(runJson)
    && [...metadataKeys].every(key => ['order_number', 'amount', 'currency', 'target_status', 'from_status', 'mode', 'reason', 'result', 'reconcile', 'restock',
      'reconcile_attempts', 'version'].includes(key)), [...metadataKeys].join(','));
  check('audit entries carry no contact details or credentials', !/omar\.khalil|0551112233|ck_|cs_|access_token/i.test(JSON.stringify(audit)));

  execSync(`${ERUN} "bundle exec rails runner docs/commerce/e2e/rails/set.rb 1 locale=ar 2>/dev/null | tail -1"`);
  await openConversation(adminA);
  await selectStore(adminA, 'Syria Cosmetics');
  await openActions(adminA, o.manual);
  await choose(adminA, 'refund_partial');
  await amountInput(adminA).fill('5.00');
  await review(adminA);
  await shot(adminA, 'a07-refund-review-ar');
  const arabic = await dialogText(adminA);
  check('Arabic: the review in Arabic, right to left', /[؀-ۿ]/.test(arabic) && await dialog(adminA).evaluate(element => getComputedStyle(element).direction) === 'rtl',
    arabic.slice(0, 120));
  await closeDialog(adminA);
  const mobile = await newPage('admin_a@commerce.lynomia.local', { width: 390, height: 844 });
  await openConversation(mobile);
  await mobile.waitForTimeout(1500);
  await shot(mobile, 'a08-mobile-ar');
  execSync(`${ERUN} "bundle exec rails runner docs/commerce/e2e/rails/set.rb 1 locale=en 2>/dev/null | tail -1"`);
  await mobile.reload({ waitUntil: 'networkidle' });
  await mobile.waitForTimeout(3000);
  await shot(mobile, 'a09-mobile-en');
  check('mobile: the conversation renders at 390 px', (await mobile.locator('body').innerText()).length > 0);
  return { o, statusOptions };
};

// ---- sim: Zid and Shopify actions, carts and recovery (simulated stores, pre-UAT override) -------------------------------------
const sim = async () => {
  const defaults = ctl('defaults');
  check('staging override set: Zid and Shopify actions, Salla/Zid/Shopify carts available for this run only', defaults.pre_uat_override === 'true'
    && defaults.actions.zid && defaults.actions.shopify && defaults.recovery.salla && defaults.recovery.zid && defaults.recovery.shopify,
  JSON.stringify({ actions: defaults.actions, recovery: defaults.recovery }));
  console.log(JSON.stringify(ctl('window open')), JSON.stringify(ctl('carts')));

  const adminA = await newPage('admin_a@commerce.lynomia.local', { width: 1440, height: 1000 });
  await settingsPage(adminA);
  let zidRow = await rowText(adminA, 'متجر الياسمين');
  let shopifyRow = await rowText(adminA, 'Lynomia Demo');
  check('Zid: order actions available to opt in', zidRow.includes('Order actions: off') && zidRow.includes('Turn on order actions'), zidRow);
  check('Shopify connected read-only: "Additional Shopify permissions are required. Reconnect Shopify to enable order actions."',
    shopifyRow.includes('Additional Shopify permissions are required. Reconnect Shopify to enable order actions.')
      && shopifyRow.includes('Reconnect for order actions') && !shopifyRow.includes('Turn on order actions'), shopifyRow);
  await shot(adminA, 's01-settings-pre-uat-override-en');

  // ---- A. Shopify write scope, only through an explicit reconnect ----------------------------------------------------------------
  const scopeBefore = ctl('stores').stores.find(store => store.provider === 'shopify').scope;
  ctl('shopify_grant ok');
  await shopifyAuthorizes(adminA.context());
  await storeRow(adminA, 'Lynomia Demo').locator('[data-test-id="commerce-store-reconnect-actions"]').click();
  await adminA.waitForTimeout(700);
  await adminA.locator('[data-test-id="shopify-connect"]').click();
  await adminA.waitForTimeout(4000);
  const asked = new URL(authorizeUrls.at(-1)).searchParams.get('scope');
  let shopifyStore = ctl('stores').stores.find(store => store.provider === 'shopify');
  check('read-only until now: the connection never held write_orders', scopeBefore === 'read_customers,read_orders', scopeBefore);
  check('Reconnect for order actions asks Shopify for write_orders explicitly', asked === 'read_customers,read_orders,write_orders', asked);
  check('the merchant approves fewer permissions than asked: refused, the read-only connection is kept as it was',
    navigations.some(url => url.includes('shopify_error=')) && shopifyStore.scope === scopeBefore && shopifyStore.actions_status === 'missing_scope',
    `${navigations.filter(url => url.includes('shopify')).at(-1)} ${shopifyStore.scope}`);
  ctl('shopify_grant write_scope');
  await settingsPage(adminA);
  await storeRow(adminA, 'Lynomia Demo').locator('[data-test-id="commerce-store-reconnect-actions"]').click();
  await adminA.waitForTimeout(700);
  await adminA.locator('[data-test-id="shopify-connect"]').click();
  await adminA.waitForTimeout(4500);
  await adminA.context().unroute(/^https:\/\/[a-z0-9-]+\.myshopify\.com\/admin\/oauth\/authorize/);
  await settingsPage(adminA);
  shopifyStore = ctl('stores').stores.find(store => store.provider === 'shopify');
  shopifyRow = await rowText(adminA, 'Lynomia Demo');
  check('approved: the same store now holds write_orders and can be opted in (still off until the administrator turns it on)',
    shopifyStore.scope === 'read_customers,read_orders,write_orders' && shopifyRow.includes('Order actions: off') && shopifyRow.includes('Turn on order actions'),
    `${shopifyStore.scope} | ${shopifyRow.slice(0, 160)}`);
  for (const name of ['Lynomia Demo', 'متجر الياسمين']) {
    await storeRow(adminA, name).locator('[data-test-id="commerce-store-order-actions-toggle"]').click();
    await adminA.waitForTimeout(2000);
  }
  zidRow = await rowText(adminA, 'متجر الياسمين');
  shopifyRow = await rowText(adminA, 'Lynomia Demo');
  check('Zid and Shopify opted in', zidRow.includes('Order actions: on') && shopifyRow.includes('Order actions: on'));

  const storeList = (await api(adminA, `${B}/api/v1/accounts/1/conversations/1/commerce/stores`)).body;
  const list = Array.isArray(storeList) ? storeList : storeList.payload || storeList.stores || [];
  const ids = Object.fromEntries(list.map(store => [store.provider === 'woocommerce' ? store.name : store.provider, store.id]));

  // ---- B. Zid status changes -------------------------------------------------------------------------------------------------
  ctl('zid_order 41000101 ready');
  await openConversation(adminA);
  await selectStore(adminA, 'متجر الياسمين');
  let res = await act(adminA, 41000101, 'update_order_status');
  let changes = ctl('sims').zid_status_changes;
  check('Zid: ready → shipped through change-order-status, once', /Done\./.test(res.text) && changes.length === 1 && changes[0].body.order_status === 'indelivery',
    `${res.consequence} | ${JSON.stringify(changes)}`);
  await closeDialog(adminA);
  res = await act(adminA, 41000102, 'update_order_status');
  changes = ctl('sims').zid_status_changes;
  check('Zid: in delivery → delivered', /Done\./.test(res.text) && changes.length === 2 && changes[1].body.order_status === 'delivered', res.text);
  await closeDialog(adminA);
  let menu = await openActions(adminA, 41000103);
  check('Zid offers nothing else (no refunds, no cancellation through Lynomia)', !menu.includes('Refund') && !menu.includes('Cancel order'), menu.slice(0, 200));
  await closeDialog(adminA);
  ctl('zid_order 41000101 ready');
  ctl('zid_write forbidden');
  await refreshPanel(adminA);
  res = await act(adminA, 41000101, 'update_order_status');
  await closeDialog(adminA);
  await settingsPage(adminA);
  zidRow = await rowText(adminA, 'متجر الياسمين');
  check('Zid refuses the write (403): Lynomia learns the authorization lacks the permission and asks for a reconnect',
    res.text.includes('can’t change orders') && zidRow.includes('Additional Zid permissions are required. Reconnect Zid to enable order actions.'), `${res.text} | ${zidRow.slice(0, 200)}`);
  ctl('zid_write ok');
  ctl('zid_reauthorize');
  await settingsPage(adminA);
  check('after the administrator authorizes Zid again, order actions are back on', (await rowText(adminA, 'متجر الياسمين')).includes('Order actions: on'));

  // ---- C. Shopify refunds and cancellation ------------------------------------------------------------------------------------
  await openConversation(adminA);
  await selectStore(adminA, 'Lynomia Demo');
  menu = await openActions(adminA, 1006);
  check('Shopify paid order: refunds through its payment, no cancellation ("refund it first")', menu.includes('Refund in full')
    && menu.includes('The order is paid: refund it first.') && !menu.includes('Change status'), menu.slice(0, 220));
  await closeDialog(adminA);
  res = await act(adminA, 1006, 'refund_partial', { amount: '50.00' });
  let mutations = ctl('sims').shopify_mutations;
  const refunds = mutations.filter(m => m.name === 'refundCreate');
  const firstRefund = runs().filter(run => run.provider === 'shopify' && run.action_type === 'refund_partial').at(-1);
  check('Shopify refund: refundCreate once, with @idempotent and the run\'s key, through Shopify Payments, notify off',
    /Done\./.test(res.text) && res.consequence.includes('through Shopify Payments') && refunds.length === 1 && refunds[0].key === firstRefund.idempotency_key
      && refunds[0].variables.input.notify === false && refunds[0].variables.input.transactions[0].amount === '50.00', `${res.consequence} | ${JSON.stringify(refunds)}`);
  await closeDialog(adminA);
  let avail = await availability(adminA, ids.shopify, 6001006);
  const twinKey = newKey();
  const twin = { action_type: 'refund_partial', version: avail.version, idempotency_key: twinKey, params: { amount: '1.00', currency: 'SAR', reason: 'other' } };
  const pair = await both(adminA, actionsUrl(ids.shopify, 6001006), [twin, twin]);
  await waitRun(twinKey, ['succeeded', 'failed', 'unknown']);
  mutations = ctl('sims').shopify_mutations;
  check('Shopify: two simultaneous requests with one key send one refundCreate', pair[0].body.id === pair[1].body.id
    && mutations.filter(m => m.name === 'refundCreate' && m.key === twinKey).length === 1, `${pair.map(r => r.status)}`);
  await refreshPanel(adminA);
  res = await act(adminA, 1006, 'refund_partial', { amount: '13.13' });
  check('Shopify userErrors: the store refused, nothing refunded', res.text.includes('The store refused this change.'), res.text);
  await closeDialog(adminA);
  res = await act(adminA, 1006, 'refund_partial', { amount: '7.77', expect: /answer in time|Done\./, timeout: 60000 });
  const lost = runs().filter(run => run.provider === 'shopify' && run.action_type === 'refund_partial').at(-1);
  await closeDialog(adminA);
  const reconciled = await waitRun(lost.idempotency_key, ['succeeded', 'failed'], 120000);
  mutations = ctl('sims').shopify_mutations;
  check('Shopify lost answer: unknown, then found by its note when reconciling; refundCreate was sent once',
    res.text.includes('The store didn’t answer in time') && reconciled?.status === 'succeeded'
      && mutations.filter(m => m.name === 'refundCreate' && m.key === lost.idempotency_key).length === 1, `${res.text} | ${reconciled?.status}`);

  ctl('shopify_order 1005 PENDING UNFULFILLED');
  await refreshPanel(adminA);
  res = await act(adminA, 1005, 'cancel_order', { expect: /Done\.|didn’t|Still being processed/, timeout: 70000 });
  mutations = ctl('sims').shopify_mutations;
  const cancel = mutations.find(m => m.name === 'orderCancel');
  check('Shopify cancel of an unpaid order: orderCancel (refund false, customer not notified), followed through its Job until the order shows it',
    res.consequence.includes('Cancelling does not refund any payment.') && /Done\./.test(res.text) && cancel && cancel.variables.staffNote.startsWith('Lynomia commerce-action:'),
    `${res.text} | ${JSON.stringify(cancel?.variables)}`);
  await closeDialog(adminA);
  await waitFor(async () => (await cardText(adminA, 1005)).includes('Cancelled'), 20000);
  check('the cancelled order reads back as cancelled', (await cardText(adminA, 1005)).includes('Cancelled'), await cardText(adminA, 1005));

  await selectStore(adminA, 'متجر الورد');
  check('Salla: no order actions (no verified write contract)', await panel(adminA).locator('[data-test-id="commerce-order-actions"]').count() === 0);

  // ---- D. Abandoned carts in Customer 360 ---------------------------------------------------------------------------------------
  const agentA = await newPage('agent_a@commerce.lynomia.local');
  await openOverview(agentA);
  await agentA.locator('[data-test-id="commerce-carts"]').waitFor({ timeout: 30000 }).catch(() => {});
  const cartsBody = (await api(agentA, `${B}/api/v1/accounts/1/conversations/1/commerce/carts`)).body;
  const shown = (cartsBody.stores || []).flatMap(view => view.carts.map(cart => `${view.store.provider}:${cart.external_cart_id}:${cart.match}`));
  const cartCards = async () => (await agentA.locator('[data-test-id="commerce-cart"]').allInnerTexts()).map(clean);
  let cards = await cartCards();
  await shot(agentA, 's02-carts-en');
  check('only Omar\'s carts: Zid by his linked customer, Shopify by customer id, Salla by linked customer',
    shown.length === 4 && shown.includes('zid:c0ffee01-0000-4000-8000-000000000001:linked_customer') && shown.includes('shopify:9101:linked_customer')
      && shown.includes('salla:551100:linked_customer') && shown.includes('zid:c0ffee02-0000-4000-8000-000000000002:linked_customer'), JSON.stringify(shown));
  check('never another customer\'s cart (same phone), a masked one, a recovered or an expired one, or a guest checkout',
    !shown.some(entry => /c0ffee0[3456]|9102|9103|9104|551101/.test(entry)));
  check('the cart list carries no email, phone or recovery link', !/omar\.khalil|551112233|recover\/|checkouts\/ac|checkout_url|recovery_url/.test(JSON.stringify(cartsBody)));
  check('the Customer 360 section shows them with store, provider, total and items', cards.length === 4 && cards.some(text => text.includes('Zid') && /185\.50/.test(text))
    && cards.some(text => text.includes('Shopify') && /410/.test(text)), JSON.stringify(cards.map(text => text.slice(0, 90))));

  // ---- E. Prepare, send, cooldown ----------------------------------------------------------------------------------------------
  const sentBefore = ctl('sims').whatsapp_sent.length;
  const zidCart = agentA.locator('[data-test-id="commerce-cart"]', { hasText: '185.50' }).first();
  await zidCart.locator('[data-test-id="commerce-cart-prepare"]').click();
  await agentA.waitForTimeout(2500);
  const editor = agentA.locator('.ProseMirror').first();
  const draft = clean(await editor.innerText().catch(() => ''));
  let recovery = runs().filter(run => run.action_type === 'recovery_message');
  check('prepare: the message lands in the reply box with the store\'s own link; nothing is sent', draft.includes('https://jasmine.zid.store/cart/recover/1?key=e2e1')
    && draft.startsWith('Hi Omar') && recovery.length === 1 && recovery[0].status === 'pending' && ctl('sims').whatsapp_sent.length === sentBefore, draft);
  cards = await cartCards();
  check('the cart says the message is prepared, not sent', cards.some(text => text.includes('not sent yet')));
  await shot(agentA, 's03-recovery-prepared-en');
  await agentA.getByRole('button', { name: /^send \(/i }).first().click(); // the reply box's "Send (Ctrl + ↵)", not the panel's "Send tracking"
  await waitFor(async () => runs().find(run => run.action_type === 'recovery_message')?.status === 'succeeded', 30000, 1500);
  recovery = runs().filter(run => run.action_type === 'recovery_message');
  check('sent by the agent: the outgoing message with the link marks it sent', recovery[0].status === 'succeeded' && recovery[0].metadata.message_id
    && ctl('sims').whatsapp_sent.length === sentBefore + 1, JSON.stringify(recovery[0]));
  await waitFor(async () => (await cartCards()).some(text => text.includes('Recovery message sent')), 30000, 1000, async () => openOverview(agentA));
  cards = await cartCards();
  check('the cart shows it sent, and the cooldown; the agent has no Prepare (and no override)', cards.some(text => text.includes('Recovery message sent')
    && text.includes('Another recovery message is possible')) && await zidCart.locator('[data-test-id="commerce-cart-prepare"]').count() === 0
    && await zidCart.locator('[data-test-id="commerce-cart-override"]').count() === 0, JSON.stringify(cards.map(text => text.slice(0, 140))));
  await shot(agentA, 's04-recovery-sent-cooldown-en');
  const agentForce = await api(agentA, `${B}/api/v1/accounts/1/conversations/1/commerce/stores/${ids.zid}/carts/c0ffee01-0000-4000-8000-000000000001/recovery`, 'POST',
    { override_cooldown: true });
  const agentAgain = await api(agentA, `${B}/api/v1/accounts/1/conversations/1/commerce/stores/${ids.zid}/carts/c0ffee01-0000-4000-8000-000000000001/recovery`, 'POST', {});
  check('cooldown: an agent is refused (RECOVERY_COOLDOWN), and cannot override', agentAgain.status === 422 && agentAgain.body.error.code === 'RECOVERY_COOLDOWN'
    && [401, 403].includes(agentForce.status), `${agentAgain.status} ${agentForce.status}`);
  await openOverview(adminA);
  const adminZidCart = adminA.locator('[data-test-id="commerce-cart"]', { hasText: '185.50' }).first();
  await adminZidCart.locator('[data-test-id="commerce-cart-override"]').click();
  await adminA.waitForTimeout(2500);
  recovery = runs().filter(run => run.action_type === 'recovery_message');
  check('an administrator can override the cooldown for one message (recorded)', recovery.length === 2 && recovery[1].metadata.override_cooldown === true,
    JSON.stringify(recovery[1]?.metadata));

  // ---- F. Unsafe link, messaging window, protected data ---------------------------------------------------------------------------
  const evil = agentA.locator('[data-test-id="commerce-cart"]', { hasText: /99\.00/ }).first();
  await evil.locator('[data-test-id="commerce-cart-prepare"]').click();
  await agentA.waitForTimeout(2500);
  check('a recovery link outside the store\'s hosts is refused: nothing prepared', clean(await evil.innerText()).includes('isn’t safe to send')
    && runs().filter(run => run.action_type === 'recovery_message').length === 2);
  console.log(JSON.stringify(ctl('window closed')));
  await openOverview(agentA);
  const shopifyCart = agentA.locator('[data-test-id="commerce-cart"]', { hasText: 'Shopify' }).first();
  await shopifyCart.locator('[data-test-id="commerce-cart-prepare"]').click();
  await agentA.waitForTimeout(2500);
  const windowText = clean(await shopifyCart.innerText());
  await shot(agentA, 's05-window-closed-en');
  check('outside the 24-hour window nothing is prepared and the reason is shown (a template is needed)', windowText.includes('can’t receive a free-form message now')
    && runs().filter(run => run.action_type === 'recovery_message').length === 2, windowText);
  console.log(JSON.stringify(ctl('window open')));
  await openOverview(agentA);
  await agentA.locator('[data-test-id="commerce-cart"]', { hasText: 'Shopify' }).first().locator('[data-test-id="commerce-cart-prepare"]').click();
  await agentA.waitForTimeout(2500);
  check('back inside the window, the Shopify checkout\'s myshopify.com link is prepared', clean(await agentA.locator('.ProseMirror').first().innerText())
    .includes('https://lynomia-demo.myshopify.com/68210001/checkouts/ac/9101/recover?key=e2e9101'));
  ctl('shopify_checkouts denied');
  ctl('drop_carts');
  await openOverview(agentA);
  const deniedText = clean(await agentA.locator('[data-test-id="commerce-carts"]').innerText().catch(() => ''));
  const deniedApi = (await api(agentA, `${B}/api/v1/accounts/1/conversations/1/commerce/carts`)).body;
  check('Shopify protected customer data refused: no checkout shown, the store is reported unreadable', deniedText.includes('Couldn’t read Lynomia Demo’s abandoned carts')
    && deniedApi.stores.find(view => view.store.provider === 'shopify').error === 'PROTECTED_DATA_NOT_APPROVED', deniedText.slice(0, 200));
  ctl('shopify_checkouts ok');
  ctl('drop_carts');

  // ---- G. Cart events through the realtime core ------------------------------------------------------------------------------------
  await openOverview(agentA);
  await agentA.evaluate(() => { window.lynomiaNoReload = true; });
  const event = ctl('salla_cart 551102 145');
  const liveMs = await waitFor(async () => (await cartCards()).some(text => /145\.00/.test(text)), 30000, 500);
  check('Salla abandoned.cart event: the new cart appears live, without a reload', event.status === 200 && liveMs !== null
    && await agentA.evaluate(() => window.lynomiaNoReload === true), `status=${event.status} ms=${liveMs}`);

  // ---- H. Admin queue -------------------------------------------------------------------------------------------------------------
  await settingsPage(adminA);
  await adminA.locator('[data-test-id="commerce-cart-queue"]').scrollIntoViewIfNeeded();
  await waitFor(async () => (await adminA.locator('[data-test-id="commerce-cart-queue-row"]').count()) > 0, 20000);
  const rows = (await adminA.locator('[data-test-id="commerce-cart-queue-row"]').allInnerTexts()).map(clean);
  const queueBody = apiBodies.filter(entry => /\/commerce\/carts(\?|$)/.test(entry.url) && entry.url.includes('/accounts/1/commerce/')).at(-1);
  const queue = JSON.parse(queueBody?.body || '{}');
  await shot(adminA, 's06-cart-queue-en');
  check('admin queue: the stores\' recent carts, linked contacts first, deterministic', queue.payload?.length >= 6 && queue.payload[0].contact
    && queue.payload.findIndex(row => !row.contact) > queue.payload.findLastIndex(row => row.contact), JSON.stringify(queue.payload?.map(row => [row.store.provider, row.external_cart_id, !!row.contact])));
  check('the queue shows no contact details or recovery links, and has no bulk send', !/recover\/|checkouts\/ac|checkout_url|recovery_url|omar\.khalil|551112233/.test(queueBody?.body || '')
    && !/send to all|send all|bulk|broadcast/i.test(await adminA.locator('[data-test-id="commerce-cart-queue"]').innerText()) && rows.length >= 6, rows.slice(0, 3).join(' | '));

  // ---- I. Arabic, mobile, tenants, secrets --------------------------------------------------------------------------------------
  execSync(`${ERUN} "bundle exec rails runner docs/commerce/e2e/rails/set.rb 1 locale=ar 2>/dev/null | tail -1"`);
  await openOverview(agentA);
  await shot(agentA, 's07-carts-ar');
  check('Arabic: the abandoned carts section in Arabic', /[؀-ۿ]/.test(await agentA.locator('[data-test-id="commerce-carts"]').innerText().catch(() => '')));
  const mobile = await newPage('agent_a@commerce.lynomia.local', { width: 390, height: 844 });
  await openOverview(mobile);
  await shot(mobile, 's08-carts-mobile-ar');
  execSync(`${ERUN} "bundle exec rails runner docs/commerce/e2e/rails/set.rb 1 locale=en 2>/dev/null | tail -1"`);
  const adminB = await newPage('admin_b@commerce.lynomia.local', { width: 1280, height: 800 });
  const crossQueue = await api(adminB, `${B}/api/v1/accounts/1/commerce/carts`);
  const crossRun = await api(adminB, `${B}/api/v1/accounts/1/conversations/1/commerce/action_runs/${recovery[0].id}`);
  check('another account cannot read this account\'s cart queue or runs', [401, 403, 404].includes(crossQueue.status) && [401, 403, 404].includes(crossRun.status),
    `${crossQueue.status} ${crossRun.status}`);
};

(async () => {
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });
  try {
    if (phase === 'gate') await gate();
    else await sim();
  } catch (error) {
    console.log(`ERROR ${error.stack}`);
    results.push({ phase, name: 'run completed', ok: false, detail: error.message });
  }
  const secrets = ctl('secrets').secrets.concat([keys.rw.ck, keys.rw.cs, keys.s2.ck, keys.s2.cs]);
  const haystacks = { server: log('server'), worker: log('worker'), ctl: log('ctl'), api: JSON.stringify(apiBodies), frames: JSON.stringify(frames) };
  const leaks = Object.entries(haystacks).flatMap(([name, body]) => secrets.filter(secret => body.includes(secret)).map(() => name));
  check('no credential, token or secret in logs, API responses or socket frames', leaks.length === 0, `secrets=${secrets.length} leaks=${leaks}`);
  check('no raw provider error reached the browser', !apiBodies.some(entry => /woocommerce_rest_|userErrors|graphql|lynomia_e2e_declined|card issuer/i.test(entry.body)));
  check('no page errors', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));
  await browser.close();
  fs.writeFileSync(`${out}/results-${phase}.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed`);
})();
