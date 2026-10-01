// Lynomia Commerce Phase 7–8 E2E (docs/commerce/27-phase7-8-e2e.md): Customer 360 across four providers and live order
// updates. WooCommerce is a real store that delivers its own signed webhooks; Salla, Zid and Shopify are the simulated
// stores of sims.rb, driven by ctl.rb. A server (server.rb) and a Sidekiq worker (worker.rb) run the app unchanged.
// usage: node e2e_realtime.js <out_dir> <keys_json>   (keys_json: {"rw":{"ck","cs"},"s2":{"ck","cs"}})
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { execSync } = require('child_process');
const fs = require('fs');

const B = 'http://localhost:3100';
const [out, keysJson] = process.argv.slice(2);
const keys = JSON.parse(keysJson);
const ERUN = process.env.ERUN;
const WP = process.env.WP; // wp-cli against the real WooCommerce store
const LOGS = { server: process.env.SERVER_LOG, worker: process.env.WORKER_LOG, ctl: process.env.CTL_LOG };
const results = [];
const timings = {};
const apiBodies = [];
const pageErrors = [];

const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  -- ${detail}` : ''}`);
};
const sh = command => execSync(command, { stdio: ['ignore', 'pipe', 'ignore'] }).toString();
const ctl = args => JSON.parse(sh(`${ERUN} "bundle exec rails runner docs/commerce/e2e/realtime/ctl.rb ${args} 2>/dev/null | grep '^SIM ' | tail -1"`).slice(4));
const rails = args => sh(`${ERUN} "bundle exec rails runner ${args} 2>/dev/null | tail -1"`).trim();
const wp = args => {
  try {
    return sh(`${WP} ${args} 2>/dev/null`);
  } catch (error) {
    return error.stdout ? error.stdout.toString() : '';
  }
};
const log = name => (LOGS[name] && fs.existsSync(LOGS[name]) ? fs.readFileSync(LOGS[name], 'utf8') : '');
const count = (name, pattern) => (log(name).match(pattern) || []).length;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const waitFor = async (predicate, timeout = 30000, step = 250, tick = null) => {
  const started = Date.now();
  while (Date.now() - started < timeout) {
    if (await predicate()) return Date.now() - started;
    if (tick) await tick();
    await sleep(step);
  }
  return null;
};

let browser;
const frames = {};
const newPage = async (email, viewport = { width: 1440, height: 1600 }) => {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  const key = frames[email] ? `${email} (${Object.keys(frames).length})` : email;
  frames[key] = [];
  page.on('pageerror', e => pageErrors.push(`${email}: ${e.message}`));
  page.on('response', async r => {
    if (r.url().includes('/api/')) apiBodies.push({ url: r.url(), body: await r.text().catch(() => '') });
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
const panel = page => page.locator('[data-test-id="commerce-panel"]');
const panelText = async page => (await panel(page).innerText({ timeout: 2000 }).catch(() => '')).replace(/\s+/g, ' ');
const orderCard = (page, number) => panel(page).locator('[data-test-id="commerce-order"]', { hasText: `#${number}` }).first();
const cardText = async (page, number) => (await orderCard(page, number).innerText({ timeout: 1000 }).catch(() => '')).replace(/\s+/g, ' ');
const openConversation = async (page, id) => {
  await page.goto(`${B}/app/accounts/1/conversations/${id}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(3500);
};
const markNoReload = page => page.evaluate(() => { window.__lynomiaNoReload = true; });
const notReloaded = page => page.evaluate(() => window.__lynomiaNoReload === true);
const selectStore = async (page, name) => {
  await page.locator('[data-test-id="commerce-view-store"]').click();
  await page.waitForTimeout(2500);
  await panel(page).locator('select').selectOption({ label: name });
  await page.waitForTimeout(3000);
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
const storeRow = (page, name) => page.locator('[data-test-id="commerce-store-row"]', { hasText: name });
const lynomiaWebhooks = storeId => JSON.parse(wp('wc webhook list --user=1 --format=json --fields=id,name,status,topic,delivery_url') || '[]')
  .filter(hook => hook.name === 'Lynomia Commerce' && hook.delivery_url.endsWith(`/webhooks/woocommerce/${storeId}`));
// WooCommerce queues its deliveries in Action Scheduler; on a live site WP-Cron runs them, here wp-cli does.
const runWooQueue = async () => { wp('action-scheduler run --hooks=woocommerce_deliver_webhook_async --batch-size=20'); };
const percentile = (values, p) => {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted.length ? sorted[Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1)] : null;
};

(async () => {
  // The real store keeps its state between runs: the order this run changes starts unpaid again (no Lynomia webhook yet).
  wp('wc shop_order update 23 --status=pending --user=1');
  console.log(JSON.stringify(ctl('reset')));
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });

  // ---- A. WooCommerce: Lynomia registers its webhooks with a Read/Write key; a read-only key keeps working without them -----
  const adminA = await newPage('admin_a@commerce.lynomia.local', { width: 1440, height: 900 });
  await adminA.goto(`${B}/app/accounts/1/settings/commerce`, { waitUntil: 'networkidle' });
  const rejectedBefore = count('server', /metric=commerce\.webhook\.rejected provider=woocommerce/g);
  await addStore(adminA, { url: 'http://localhost:8081', name: 'Syria Cosmetics', ck: keys.rw.ck, cs: keys.rw.cs });
  await addStore(adminA, { url: 'http://localhost:8082', name: 'Damascus Perfumes', ck: keys.s2.ck, cs: keys.s2.cs });
  await waitFor(async () => {
    await adminA.reload({ waitUntil: 'networkidle' });
    return (await storeRow(adminA, 'Syria Cosmetics').innerText()).includes('Live order updates on');
  }, 30000, 2000);
  await shot(adminA, '01-settings-realtime-status');
  const s1Row = await storeRow(adminA, 'Syria Cosmetics').innerText();
  const s2Row = await storeRow(adminA, 'Damascus Perfumes').innerText();
  check('Read/Write key: Lynomia registers its webhooks, settings say live updates are on', s1Row.includes('Live order updates on'), s1Row.replace(/\s+/g, ' '));
  check('read-only key: store connected and active, live updates off with the reason', s2Row.includes('Active') && s2Row.includes('this key is read-only'),
    s2Row.replace(/\s+/g, ' '));
  const state = ctl('state');
  const s1 = state.stores.find(store => store.name === 'Syria Cosmetics');
  const hooks = lynomiaWebhooks(s1.id);
  check('WooCommerce holds one active Lynomia webhook per order topic, to this store\'s URL',
    hooks.length === 3 && hooks.every(hook => hook.status === 'active' && hook.delivery_url.endsWith(`/webhooks/woocommerce/${s1.id}`))
      && ['order.created', 'order.updated', 'order.deleted'].every(topic => hooks.some(hook => hook.topic === topic)),
    JSON.stringify(hooks.map(hook => [hook.topic, hook.status])));
  check('WooCommerce\'s unsigned creation pings were refused', count('server', /metric=commerce\.webhook\.rejected provider=woocommerce/g) - rejectedBefore >= 3,
    `rejected=${count('server', /metric=commerce\.webhook\.rejected provider=woocommerce/g) - rejectedBefore}`);

  // ---- B. Salla, Zid and Shopify connected (simulated stores) ---------------------------------------------------------------
  const connected = ctl('connect');
  check('Salla, Zid and Shopify stores connected to account A', connected.stores.length === 5 && connected.zid_webhooks > 0, JSON.stringify(connected.stores));

  // ---- C. Customer 360: one contact, four providers -------------------------------------------------------------------------
  const agentA = await newPage('agent_a@commerce.lynomia.local');
  const adminB = await newPage('admin_b@commerce.lynomia.local', { width: 1280, height: 800 });
  await adminB.goto(`${B}/app/accounts/2/dashboard`, { waitUntil: 'networkidle' });
  // First visit: nothing is linked yet, so the store view opens; the overview reads (and links) every store.
  await openConversation(agentA, 1);
  check('first visit, contact not linked anywhere yet: the store view opens', await agentA.locator('[data-test-id="commerce-overview"]').count() === 0
    && await agentA.locator('[data-test-id="commerce-view-overview"]').count() === 1);
  await agentA.locator('[data-test-id="commerce-view-overview"]').click();
  await agentA.locator('[data-test-id="commerce-overview"]').waitFor({ timeout: 30000 });
  await agentA.waitForTimeout(3000);
  await agentA.evaluate(() => window.localStorage.removeItem('lynomia.commerce.view'));
  const overviewMs = [];
  const timedOverview = async () => {
    const started = Date.now();
    await agentA.reload({ waitUntil: 'networkidle' });
    await agentA.locator('[data-test-id="commerce-overview"]').waitFor({ timeout: 30000 });
    overviewMs.push(Date.now() - started);
  };
  await timedOverview();
  await agentA.waitForTimeout(1500);
  await shot(agentA, '02-customer360-en');
  let text = await panelText(agentA);
  const storeEntries = await panel(agentA).locator('[data-test-id="commerce-overview-store"]').allInnerTexts();
  check('Overview opens first for a contact linked in several stores', await agentA.locator('[data-test-id="commerce-overview"]').count() === 1);
  check('Customer 360: linked in one store of each provider, each with its provider; the store without the customer says so',
    storeEntries.length === 5 && storeEntries.filter(entry => entry.includes('Linked')).length === 4
      && ['WooCommerce', 'Salla', 'Zid', 'Shopify'].every(provider => storeEntries.some(entry => entry.includes(provider) && entry.includes('Linked')))
      && storeEntries.some(entry => entry.includes('Damascus Perfumes') && entry.includes('Customer not linked')),
    JSON.stringify(storeEntries.map(entry => entry.replace(/\s+/g, ' ').slice(0, 70))));
  check('figures: 5 connected · 4 linked, visible orders (not lifetime), last purchase, no partial banner',
    text.includes('5 connected') && text.includes('4 linked') && /\d+ visible/.test(text) && !text.includes('No orders found')
      && await agentA.locator('[data-test-id="commerce-overview-partial"]').count() === 0, text.slice(0, 300));
  const spend = await agentA.locator('[data-test-id="commerce-overview-spend"]').allInnerTexts();
  check('spend per currency, never converted into one figure', spend.length >= 1 && spend.every(line => /SAR|USD|ر\.س|\$/.test(line)), JSON.stringify(spend));
  const latest = await panel(agentA).locator('[data-test-id="commerce-order"]').count();
  const latestStores = await panel(agentA).locator('[data-test-id="commerce-order-store"]').allInnerTexts();
  check('latest orders across stores: at most 10, each naming its store and provider', latest > 0 && latest <= 10 && latestStores.length === latest
    && new Set(latestStores.map(line => line.split('·').pop().trim())).size >= 3, `orders=${latest} providers=${[...new Set(latestStores.map(line => line.split('·').pop().trim()))]}`);
  check('no LTV, average order value or predictions', !/lifetime|average order|predicted/i.test(text));
  for (let i = 0; i < 4; i += 1) await timedOverview();

  // ---- D. Live updates, one provider at a time (no reload) ------------------------------------------------------------------
  await markNoReload(agentA);
  const live = async (label, storeName, number, expected, trigger, tick = null) => {
    await selectStore(agentA, storeName);
    const before = await cardText(agentA, number);
    const started = Date.now();
    const result = await trigger();
    const ms = await waitFor(async () => (await cardText(agentA, number)).includes(expected), 45000, 100, tick);
    timings[label] = ms === null ? null : Date.now() - (result?.delivered_at || started);
    await shot(agentA, `03-live-${label}`);
    check(`${label}: the open store view shows the change live, without a reload`, ms !== null && await notReloaded(agentA),
      `before="${before.slice(0, 60)}" after="${(await cardText(agentA, number)).slice(0, 60)}" ms=${timings[label]}`);
  };
  check('WooCommerce order #23 starts unpaid', (await (async () => { await selectStore(agentA, 'Syria Cosmetics'); return cardText(agentA, 23); })()).includes('Pending payment'));
  await live('woocommerce-real', 'Syria Cosmetics', 23, 'Processing', async () => { wp('wc shop_order update 23 --status=processing --user=1'); }, runWooQueue);
  check('WooCommerce delivery: signed by the store, accepted, applied to the store', count('server', /metric=commerce\.webhook\.accepted provider=woocommerce/g) >= 1
    && count('worker', /metric=commerce\.webhook\.applied provider=woocommerce/g) >= 1);
  await live('zid', 'متجر الياسمين', 41000101, 'Delivered', async () => ctl('deliver zid 41000101 delivered paid'));
  await live('shopify', 'Lynomia Demo', 1005, 'Shipped', async () => ctl('deliver shopify 1005 PAID FULFILLED'));
  await live('salla', 'متجر الورد', 30013, 'Delivered', async () => ctl('deliver salla 1861092003 delivered Delivered'));

  // A new WooCommerce order for the same guest appears live.
  await selectStore(agentA, 'Syria Cosmetics');
  const createdId = wp('wc shop_order create --user=1 --status=processing --customer_id=0 --set_paid=true --porcelain '
    + `--billing='${JSON.stringify({ first_name: 'Omar', last_name: 'Khalil', phone: '0551112233', email: 'omar.khalil@example.com', country: 'SA' })}'`
    + ` --line_items='${JSON.stringify([{ product_id: 11, quantity: 1 }])}'`).trim();
  const createdMs = await waitFor(async () => (await panelText(agentA)).includes(`#${createdId}`), 45000, 250, runWooQueue);
  timings['woocommerce-created'] = createdMs;
  check('WooCommerce: a new order of the same guest appears live', /^\d+$/.test(createdId) && createdMs !== null && await notReloaded(agentA),
    `order=${createdId} ms=${createdMs}`);

  // ---- E. Duplicates, bursts, out-of-order events ---------------------------------------------------------------------------
  const applied = provider => count('worker', new RegExp(`metric=commerce\\.webhook\\.applied provider=${provider}`, 'g'));
  const refreshes = () => count('worker', /Performed Commerce::RefreshJob/g);
  await sleep(4000);
  let appliedBefore = applied('zid');
  const duplicatesBefore = count('server', /metric=commerce\.webhook\.duplicate provider=zid/g);
  const replay = ctl('replay zid');
  await sleep(5000);
  check('a replayed Zid delivery is acknowledged and not applied again', replay.status === 200 && applied('zid') === appliedBefore
    && count('server', /metric=commerce\.webhook\.duplicate provider=zid/g) === duplicatesBefore + 1);
  const shopifyReplay = ctl('replay shopify');
  await sleep(5000);
  check('a replayed Shopify delivery (same X-Shopify-Webhook-Id) is acknowledged once', shopifyReplay.status === 200
    && count('server', /metric=commerce\.webhook\.duplicate provider=shopify/g) >= 1);

  appliedBefore = applied('zid');
  const refreshesBefore = refreshes();
  const coalescedBefore = count('worker', /metric=commerce\.refresh\.coalesced/g);
  const burst = ctl('burst zid 41000102 10');
  await sleep(9000);
  check('a burst of 10 Zid events for one customer: all applied, refreshed at most twice (coalesced)',
    burst.statuses['200'] === 10 && applied('zid') - appliedBefore === 10 && refreshes() - refreshesBefore <= 2
      && count('worker', /metric=commerce\.refresh\.coalesced/g) - coalescedBefore >= 8,
    `applied=${applied('zid') - appliedBefore} refreshes=${refreshes() - refreshesBefore} coalesced=${count('worker', /metric=commerce\.refresh\.coalesced/g) - coalescedBefore}`);

  await selectStore(agentA, 'Lynomia Demo');
  ctl('event shopify 1005 UNFULFILLED');
  await sleep(6000);
  check('an out-of-order event claiming an older state changes nothing: the store is read again', (await cardText(agentA, 1005)).includes('Shipped'),
    await cardText(agentA, 1005));

  // ---- F. Outage and revoked access -------------------------------------------------------------------------------------------
  await selectStore(agentA, 'متجر الورد');
  const sallaBefore = await cardText(agentA, 30015);
  ctl('outage salla on');
  ctl('deliver salla 1861092005 delivered Delivered');
  const staleMs = await waitFor(async () => agentA.locator('[data-test-id="commerce-stale"]').isVisible(), 30000);
  await shot(agentA, '04-outage-stale-salla');
  check('Salla outage during an event: the last orders stay, marked stale with their time', staleMs !== null
    && (await agentA.locator('[data-test-id="commerce-stale"]').innerText()).includes('Last updated') && (await cardText(agentA, 30015)) === sallaBefore,
  (await agentA.locator('[data-test-id="commerce-stale"]').innerText().catch(() => '')).replace(/\s+/g, ' '));
  ctl('outage salla off');
  await agentA.locator('[data-test-id="commerce-view-overview"]').click();
  await agentA.waitForTimeout(3000);
  await shot(agentA, '05-overview-partial');

  ctl('revoke shopify');
  ctl('deliver shopify 1004 PAID FULFILLED');
  const reauthMs = await waitFor(async () => {
    const entries = await panel(agentA).locator('[data-test-id="commerce-overview-store"]').allInnerTexts();
    return entries.some(entry => entry.includes('Shopify') && entry.includes('needs re-authorization'));
  }, 45000);
  await shot(agentA, '06-overview-shopify-revoked');
  const latestAfter = await panel(agentA).locator('[data-test-id="commerce-order-store"]').allInnerTexts();
  check('Shopify access revoked: the store shows it needs re-authorization, live, and none of its orders remain', reauthMs !== null
    && !latestAfter.some(line => line.includes('Shopify')), `ms=${reauthMs}`);

  // ---- G. Kill switch, manual refresh, store-level invalidation ---------------------------------------------------------------
  ctl('realtime off');
  await selectStore(agentA, 'متجر الياسمين');
  const beforeSwitch = await cardText(agentA, 41000103);
  ctl('deliver zid 41000103 delivered paid');
  await sleep(8000);
  const beforeRefresh = await cardText(agentA, 41000103);
  check('COMMERCE_REALTIME_ENABLED=false: no live update', beforeRefresh.includes('#41000103') && !beforeRefresh.includes('Delivered')
    && beforeRefresh === beforeSwitch, beforeRefresh);
  await panel(agentA).locator('[data-test-id="commerce-refresh"]').click();
  const refreshedMs = await waitFor(async () => (await cardText(agentA, 41000103)).includes('Delivered'), 15000);
  check('manual Refresh reads the store again even though its cache was fresh', refreshedMs !== null);
  await panel(agentA).locator('[data-test-id="commerce-refresh"]').click();
  await agentA.waitForTimeout(1500);
  const notice = await agentA.locator('[data-test-id="commerce-refresh-notice"]').innerText().catch(() => '');
  await shot(agentA, '07-refresh-cooldown');
  check('a second Refresh within the cooldown is refused with the wait', /Just refreshed\. Try again in \d+ s\./.test(notice), notice);
  ctl('realtime on');

  await selectStore(agentA, 'Syria Cosmetics');
  const namesNobody = () => count('worker', /metric=commerce\.webhook\.applied provider=woocommerce store_id=\d+ customers=0/g);
  const namesNobodyBefore = namesNobody();
  wp(`wc shop_order delete ${createdId} --user=1`); // to the trash: WooCommerce's order.deleted fires on trash, not on a forced delete
  await waitFor(async () => namesNobody() > namesNobodyBefore, 30000, 1000, runWooQueue);
  check('WooCommerce order.deleted names no customer: the store\'s cached orders are outdated, nobody refreshed', namesNobody() > namesNobodyBefore);
  await panel(agentA).locator('[data-test-id="commerce-refresh"]').click();
  const goneMs = await waitFor(async () => !(await panelText(agentA)).includes(`#${createdId}`), 15000);
  check('after a store-level invalidation the next read no longer shows the deleted order', goneMs !== null);

  // ---- H. Order search and unlink suppression ---------------------------------------------------------------------------------
  await agentA.locator('[data-test-id="commerce-view-overview"]').click();
  await agentA.waitForTimeout(3000);
  await agentA.locator('[data-test-id="commerce-order-search-toggle"]').click();
  await agentA.locator('[data-test-id="commerce-order-search-input"] input, input[data-test-id="commerce-order-search-input"]').first().fill('24');
  await agentA.locator('[data-test-id="commerce-order-search-submit"]').click();
  await agentA.waitForTimeout(4000);
  const searchText = (await agentA.locator('[data-test-id="commerce-order-search"]').innerText()).replace(/\s+/g, ' ');
  await shot(agentA, '08-order-search');
  check('order search by number across stores: WooCommerce #24 found, Salla reported as not searchable, no Send tracking',
    searchText.includes('#24') && searchText.includes('Syria Cosmetics') && searchText.includes("order search isn't available") && !searchText.includes('Send tracking'),
    searchText.slice(0, 240));

  await selectStore(agentA, 'متجر الياسمين');
  await panel(agentA).getByRole('button', { name: 'Unlink' }).click();
  await agentA.waitForTimeout(3000);
  await agentA.reload({ waitUntil: 'networkidle' });
  await agentA.waitForTimeout(3000);
  await selectStore(agentA, 'متجر الياسمين');
  text = await panelText(agentA);
  check('unlinked store stays unlinked: the matched customer is offered, not linked again', text.includes('Possible match') && !text.includes('Linked customer'),
    text.slice(0, 200));
  await panel(agentA).getByRole('button', { name: 'Link', exact: true }).first().click();
  await agentA.waitForTimeout(3500);
  check('the agent can link the customer again by hand', (await panelText(agentA)).includes('Linked customer'));

  // ---- I. Arabic, mobile ---------------------------------------------------------------------------------------------------------
  rails('docs/commerce/e2e/rails/set.rb 1 locale=ar');
  await agentA.evaluate(() => window.localStorage.removeItem('lynomia.commerce.view'));
  await openConversation(agentA, 1);
  await agentA.waitForTimeout(2000);
  await shot(agentA, '09-customer360-ar');
  text = await panelText(agentA);
  check('Arabic: Customer 360 in Arabic, right to left', text.includes('نظرة عامة') && text.includes('أحدث الطلبات')
    && await panel(agentA).evaluate(element => getComputedStyle(element).direction) === 'rtl');
  const mobile = await newPage('agent_a@commerce.lynomia.local', { width: 390, height: 844 });
  await openConversation(mobile, 1);
  await mobile.waitForTimeout(2000);
  await shot(mobile, '10-customer360-mobile-ar');
  rails('docs/commerce/e2e/rails/set.rb 1 locale=en');
  await mobile.reload({ waitUntil: 'networkidle' });
  await mobile.waitForTimeout(4000);
  await shot(mobile, '11-customer360-mobile-en');
  check('mobile: the conversation and its Commerce section render at 390 px', (await mobile.locator('body').innerText()).length > 0);

  // ---- J. Tenants, payloads, secrets ------------------------------------------------------------------------------------------------
  const received = frames['agent_a@commerce.lynomia.local'].map(raw => JSON.parse(raw).message);
  check('agents of account A received commerce.customer.updated over the existing ActionCable connection', received.length >= 5, `frames=${received.length}`);
  check('each event carries ids only: account, contact, store, time', received.every(message => message.event === 'commerce.customer.updated'
    && Object.keys(message.data).sort().join(',') === 'account_id,contact_id,store_id,updated_at' && message.data.account_id === 1));
  check('account B received no commerce event of account A', frames['admin_b@commerce.lynomia.local'].length === 0,
    `frames=${frames['admin_b@commerce.lynomia.local'].length}`);

  await adminA.goto(`${B}/app/accounts/1/settings/commerce`, { waitUntil: 'networkidle' });
  await storeRow(adminA, 'Syria Cosmetics').getByRole('button', { name: 'Disconnect' }).click();
  await adminA.waitForTimeout(800);
  await adminA.locator('dialog[open]').getByRole('button', { name: /disconnect/i }).click();
  await adminA.waitForTimeout(5000);
  check('disconnecting removes Lynomia\'s webhooks from WooCommerce', lynomiaWebhooks(s1.id).length === 0, JSON.stringify(lynomiaWebhooks(s1.id)));

  const secrets = ctl('secrets').secrets.concat([keys.rw.ck, keys.rw.cs, keys.s2.ck, keys.s2.cs]);
  const haystacks = { server: log('server'), worker: log('worker'), ctl: log('ctl'), api: JSON.stringify(apiBodies), frames: JSON.stringify(frames) };
  const leaks = Object.entries(haystacks).flatMap(([name, body]) => secrets.filter(secret => body.includes(secret)).map(() => name));
  check('no credential, webhook secret or token in logs, API responses or socket frames', leaks.length === 0, `secrets=${secrets.length} leaks=${leaks}`);
  check('no page errors', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));

  // ---- K. Measurements -------------------------------------------------------------------------------------------------------------
  const hits = count('server', /metric=commerce\.cache\.hit/g);
  const misses = count('server', /metric=commerce\.cache\.miss/g);
  const loads = (log('server').match(/metric=commerce\.customer360\.load [^\n]*ms=(\d+)/g) || []).map(line => Number(line.match(/ms=(\d+)/)[1]));
  const measurements = {
    overview_browser_ms: { samples: overviewMs, p50: percentile(overviewMs, 50), p95: percentile(overviewMs, 95) },
    customer360_server_ms: { samples: loads.length, p50: percentile(loads, 50), p95: percentile(loads, 95) },
    cache: { hits, misses, hit_ratio: hits + misses ? Number((hits / (hits + misses)).toFixed(2)) : null },
    provider_requests: count('server', /metric=commerce\.provider\.request/g) + count('worker', /metric=commerce\.provider\.request/g),
    provider_errors: count('server', /metric=commerce\.provider\.error/g) + count('worker', /metric=commerce\.provider\.error/g),
    webhooks: ['accepted', 'rejected', 'duplicate'].reduce((acc, kind) => ({ ...acc, [kind]: count('server', new RegExp(`metric=commerce\\.webhook\\.${kind}`, 'g')) }), {}),
    refresh_coalesced: count('worker', /metric=commerce\.refresh\.coalesced/g),
    live_update_ms: timings,
    simulated_requests: ctl('state').requests,
  };
  fs.writeFileSync(`${out}/measurements.json`, JSON.stringify(measurements, null, 2));
  console.log(JSON.stringify(measurements));

  await browser.close();
  fs.writeFileSync(`${out}/results.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed`);
})().catch(async error => {
  console.log(`ERROR ${error.stack}`);
  fs.writeFileSync(`${out}/results.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed (aborted)`);
  if (browser) await browser.close();
});
