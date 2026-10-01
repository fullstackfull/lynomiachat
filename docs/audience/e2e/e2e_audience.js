// Lynomia Audience E2E (docs/audience/05-performance.md §E2E): Commerce and conversation conditions in Chatwoot's contact
// filter, saved as audiences (contact segments), through the browser and the API, on the production configuration.
// The store is the disposable local WooCommerce test store A1, read with its Read key (nothing is written to it); its
// access log proves that evaluating audiences never calls it. Salla stays switched off.
//
// usage: node e2e_audience.js <out_dir> <keys_json>   (keys_json: {"s1":{"ck","cs"}})
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
const ctl = args => JSON.parse(execSync(`${ERUN} "bundle exec rails runner docs/audience/e2e/ctl.rb ${args} 2>/dev/null | grep '^SIM ' | tail -1"`)
  .toString().slice(4));
// Requests the WooCommerce test store has answered (its access log; only counted, never kept: it names the key).
const storeCalls = () => Number(execSync("docker logs woo-wp 2>&1 | grep -c '/wp-json/wc/v3' || true").toString().trim());
const clean = text => (text || '').replace(/\s+/g, ' ').trim();
const shot = (page, name) => page.screenshot({ path: `${out}/${name}.png` });

let browser;
const login = async (email, viewport = { width: 1440, height: 900 }) => {
  const page = await (await browser.newContext({ viewport })).newPage();
  page.on('pageerror', error => pageErrors.push(`${email}: ${error.message}`));
  page.on('response', async response => {
    if (response.url().startsWith(B) && !response.url().includes('/vite/')) responses.push(await response.text().catch(() => ''));
  });
  await page.goto(`${B}/app/login`, { waitUntil: 'networkidle' });
  await page.fill('input[name="email_address"]', email);
  await page.fill('input[type="password"]', PASSWORD);
  await page.keyboard.press('Enter');
  await page.waitForURL(/\/app\/accounts\/\d+/, { timeout: 60000 });
  return page;
};
const api = (page, url, method = 'GET', body) => page.evaluate(async ([u, m, b]) => {
  const raw = document.cookie.split('; ').find(c => c.startsWith('cw_d_session_info='));
  const info = JSON.parse(decodeURIComponent(raw.slice('cw_d_session_info='.length)));
  const response = await fetch(u, { method: m, headers: { 'access-token': info['access-token'], client: info.client, uid: info.uid,
    'Content-Type': 'application/json' }, body: b ? JSON.stringify(b) : undefined });
  return { status: response.status, body: await response.json().catch(() => null) };
}, [url, method, body]);
const condition = (key, operator, values, queryOperator) => ({ attribute_key: key, filter_operator: operator, values, query_operator: queryOperator });
const filterNames = async (page, account, ...conditions) => {
  const response = await api(page, `${B}/api/v1/accounts/${account}/contacts/filter`, 'POST', { payload: conditions });
  return { status: response.status, names: (response.body?.payload || []).map(contact => contact.name).sort(), body: response.body };
};

// The contact filter: pick a field through the attribute picker's search, then fill the value.
const openFilter = async page => {
  await page.locator('#toggleContactsFilterButton').click();
  await page.waitForTimeout(700);
};
const chooseField = async (page, rowIndex, currentLabel, search, option) => {
  await page.locator('div.z-40 ul > li').nth(rowIndex).getByRole('button', { name: currentLabel, exact: true }).click();
  await page.waitForTimeout(300);
  await page.keyboard.type(search);
  await page.waitForTimeout(300);
  await page.locator('li.n-dropdown-item', { hasText: option }).first().click();
  await page.waitForTimeout(400);
};

(async () => {
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });
  const setup = ctl(`setup ${keys.s1.ck} ${keys.s1.cs}`);
  const account = setup.account_id;
  check('setup: store A1 connected (real WooCommerce, Read key), Salla switched off', setup.store_id && setup.salla_enabled === false,
    JSON.stringify({ store: setup.store_id, salla: setup.salla_enabled }));

  // ---- Commerce data reaches the audience summaries through the existing reads -------------------------------------------
  const agent = await login('agent_a@commerce.lynomia.local');
  const before = storeCalls();
  const panel = await api(agent, `${B}/api/v1/accounts/${account}/conversations/${setup.conversations['Omar Khalil']}/commerce/stores/${setup.store_id}`);
  const orders = panel.body?.orders || [];
  const summaries = ctl('summaries').summaries;
  const omar = summaries.find(row => row.contact === 'Omar Khalil');
  const paidSar = orders.filter(order => order.payment_status === 'paid' && order.currency === 'SAR')
    .reduce((sum, order) => sum + Number(order.total), 0);
  check('an agent opening Omar\'s conversation reads his orders from the store, as before', panel.status === 200 && panel.body?.state === 'linked'
    && orders.length > 0 && storeCalls() > before, `orders=${orders.length}`);
  check('that read also wrote Omar\'s audience summary: the same orders, spend per currency, no order data',
    omar && omar.provider === 'woocommerce' && omar.orders === orders.length && Number(omar.spend.SAR || 0) === paidSar
      && Object.keys(omar).sort().join() === 'contact,last_purchase_at,order_statuses,orders,provider,spend', JSON.stringify(omar));

  // ---- The filter builder: the same picker, two more groups ------------------------------------------------------------------
  const admin = await login('admin_a@commerce.lynomia.local');
  const callsBeforeAudiences = storeCalls();
  await admin.goto(`${B}/app/accounts/${account}/contacts`, { waitUntil: 'networkidle' });
  await admin.waitForTimeout(1500);
  await openFilter(admin);
  await admin.getByRole('button', { name: 'Name', exact: true }).click();
  await admin.waitForTimeout(400);
  const picker = clean(await admin.locator('.n-dropdown-item, li.select-none').allInnerTexts().then(list => list.join(' | ')));
  await shot(admin, 'audience-01-picker');
  check('Contacts → Filter offers Conversation and Commerce groups next to the existing fields',
    ['Conversations', 'Commerce', 'Conversation status', 'Assigned agent', 'Linked store', 'Store platform', 'Visible orders',
      'Visible spend (SAR)', 'Last visible purchase', 'Has an active order', 'Order status', 'Payment status', 'Shipment status',
      'Email', 'Labels'].every(text => picker.includes(text)), picker.slice(0, 300));
  await admin.keyboard.press('Escape');

  await chooseField(admin, 0, 'Name', 'Visible spend', 'Visible spend (SAR)');
  const operator = clean(await admin.getByRole('button', { name: /greater than/i }).first().innerText().catch(() => ''));
  await admin.getByPlaceholder('Enter value').fill('1');
  const notes = clean(await admin.locator('[data-test-id="audience-notes"]').innerText().catch(() => ''));
  await shot(admin, 'audience-02-spend-condition');
  check('a Commerce field uses the existing operators ("Is greater than") and says what "visible" means',
    /greater than/i.test(operator) && notes.includes('not lifetime totals') && notes.includes('per currency'), notes);
  check('the builder says how many linked contacts have no orders read yet (Layla), instead of hiding them',
    notes.includes('haven’t been read yet for 1 linked contacts'), notes);
  await admin.getByRole('button', { name: /apply filters/i }).click();
  await admin.waitForTimeout(2000);
  const listed = clean(await admin.locator('main, body').first().innerText());
  await shot(admin, 'audience-03-matching-contacts');
  check('applying shows the matching contacts with their count (Omar only)', listed.includes('Omar Khalil') && listed.includes('of 1 contact'),
    listed.match(/Showing[^\n]*/)?.[0] || '');

  // ---- Save, open, edit and delete through the existing segment flow ------------------------------------------------------
  await admin.locator('button:has(.i-lucide-save)').click();
  await admin.waitForTimeout(500);
  const saveDialog = clean(await admin.locator('dialog[open]').innerText());
  await admin.locator('dialog[open] input').fill('Big spenders');
  await shot(admin, 'audience-04-save');
  await admin.locator('dialog[open]').getByRole('button', { name: /save audience/i }).click();
  await admin.waitForURL(/\/contacts\/segments\/\d+/, { timeout: 30000 });
  await admin.waitForTimeout(1500);
  const saved = ctl('audiences').audiences;
  const sidebar = clean(await admin.locator('nav, aside').first().innerText().catch(() => ''));
  await shot(admin, 'audience-05-saved');
  check('"Save audience" stores it as a contact segment with the same conditions, listed under Audiences',
    saveDialog.includes('Save these filters as an audience?') && saved.length === 1 && saved[0].name === 'Big spenders'
      && saved[0].query.payload[0].attribute_key === 'commerce_spend_sar' && sidebar.includes('Audiences') && sidebar.includes('Big spenders'),
    JSON.stringify(saved.map(row => row.query)));
  const opened = clean(await admin.locator('main, body').first().innerText());
  check('opening the audience evaluates it now: Omar', opened.includes('Omar Khalil') && opened.includes('of 1 contact'));

  await admin.locator('#toggleContactsFilterButton').click();
  await admin.waitForTimeout(800);
  const editor = clean(await admin.locator('h3', { hasText: 'Edit audience' }).locator('..').innerText().catch(() => ''));
  await admin.getByRole('button', { name: /add filter/i }).click();
  await admin.waitForTimeout(300);
  await chooseField(admin, 1, 'Name', 'Linked store', 'Linked store');
  // The new row's store picker (MultiSelect), inside the filter panel.
  await admin.locator('div.z-40 ul > li').nth(1).locator('button:has(.i-lucide-plus)').first().click();
  await admin.waitForTimeout(300);
  await admin.locator('li.n-dropdown-item', { hasText: 'Syria Cosmetics' }).first().click();
  await admin.keyboard.press('Escape');
  await shot(admin, 'audience-06-edit');
  await admin.getByRole('button', { name: /update audience/i }).click();
  await admin.waitForTimeout(2000);
  const updated = ctl('audiences').audiences[0];
  check('editing rebuilds the saved condition ("Visible spend (SAR)" … 1) and adds a store condition by name',
    editor.includes('Visible spend (SAR)') && updated.query.payload.length === 2
      && updated.query.payload[1].attribute_key === 'commerce_store' && updated.query.payload[1].values[0] === setup.store_id,
    JSON.stringify(updated.query.payload));

  // ---- Semantics and safety through the API ----------------------------------------------------------------------------------
  const unknownLess = await filterNames(admin, account, condition('commerce_orders_count', 'is_less_than', ['100']));
  check('unknown is never zero: "fewer than 100 visible orders" matches Omar, not Layla whose orders were never read',
    unknownLess.names.join() === 'Omar Khalil', unknownLess.names.join());
  const salla = await filterNames(admin, account, condition('commerce_spend_sar', 'is_greater_than', ['50000']));
  check('a store of a switched-off provider never counts (Hana\'s Salla summary of SAR 99,999)', salla.status === 200 && salla.names.length === 0);
  const usd = await filterNames(admin, account, condition('commerce_spend_usd', 'is_greater_than', ['0']));
  check('spend is per currency: nobody has USD spend, whatever their SAR spend', usd.status === 200 && usd.names.length === 0);
  const open = await filterNames(admin, account, condition('conversation_status', 'equal_to', ['open']));
  const outsider = await login('outsider_a@commerce.lynomia.local');
  const outsiderOpen = await filterNames(outsider, account, condition('conversation_status', 'equal_to', ['open']));
  check('conversation conditions only see the conversations the user may see (an agent without inboxes sees none)',
    open.names.length >= 3 && outsiderOpen.status === 200 && outsiderOpen.names.length === 0, `admin=${open.names.length}`);
  const combined = await filterNames(admin, account, condition('commerce_store', 'is_present', [], 'AND'),
    condition('conversation_inbox', 'equal_to', [1], 'OR'), condition('email', 'equal_to', ['family@example.com']));
  check('Commerce, conversation and contact conditions combine through the existing AND / OR chain', combined.status === 200
    && combined.names.includes('Omar Khalil') && combined.names.includes('Hana Saeed'), combined.names.join());
  check('evaluating audiences never called the store: its access log is unchanged', storeCalls() === callsBeforeAudiences,
    `before=${callsBeforeAudiences} after=${storeCalls()}`);

  const malformed = await Promise.all([
    filterNames(admin, account, condition('commerce_spend_sar', 'is_greater_than', [{ x: 1 }])),
    filterNames(admin, account, condition('commerce_provider', 'equal_to', ["woocommerce' OR 1=1 --"])),
    filterNames(admin, account, condition('commerce_lifetime_value', 'is_greater_than', ['1'])),
    filterNames(admin, account, condition('commerce_spend_sar', 'contains', ['1'])),
    filterNames(admin, account, ...Array.from({ length: 11 }, (_, index) => condition('commerce_store', 'is_present', [], index < 10 ? 'AND' : undefined))),
  ]);
  check('malformed, injected, unknown, wrong-operator and oversized conditions answer 422', malformed.every(result => result.status === 422),
    malformed.map(result => result.status).join(','));
  const adminB = await login('admin_b@commerce.lynomia.local');
  const forged = await filterNames(adminB, account, condition('commerce_store', 'is_present', []));
  const foreign = await api(adminB, `${B}/api/v1/accounts/${setup.account_b_id}/custom_filters/${updated.id}`);
  check('another account can neither evaluate this account\'s contacts nor read its audience', forged.status === 401 && foreign.status === 404,
    `${forged.status}/${foreign.status}`);

  const unlink = await api(agent, `${B}/api/v1/accounts/${account}/conversations/${setup.conversations['Omar Khalil']}/commerce/stores/${setup.store_id}/link`, 'DELETE');
  const afterUnlink = await filterNames(admin, account, ...updated.query.payload);
  check('an agent removing Omar\'s link drops him from the audience at once (the link is suppressed, its summary deleted)',
    unlink.status === 200 && afterUnlink.names.length === 0 && !ctl('summaries').summaries.some(row => row.contact === 'Omar Khalil'),
    `unlink=${unlink.status} names=${afterUnlink.names.join()}`);

  const contactsBefore = (await api(admin, `${B}/api/v1/accounts/${account}/contacts`)).body.meta.count;
  await admin.goto(`${B}/app/accounts/${account}/contacts/segments/${updated.id}`, { waitUntil: 'networkidle' });
  await admin.waitForTimeout(1200);
  await admin.locator('button:has(.i-lucide-trash)').first().click();
  await admin.waitForTimeout(400);
  const deleteDialog = clean(await admin.locator('dialog[open]').innerText());
  await shot(admin, 'audience-07-delete');
  await admin.locator('dialog[open]').getByRole('button', { name: /yes, delete/i }).click();
  await admin.waitForTimeout(1500);
  const contactsAfter = (await api(admin, `${B}/api/v1/accounts/${account}/contacts`)).body.meta.count;
  check('deleting the audience deletes only its conditions; every contact stays',
    deleteDialog.includes('the contacts stay') && ctl('audiences').audiences.length === 0 && contactsAfter === contactsBefore,
    `${contactsBefore} → ${contactsAfter}`);

  // ---- Arabic, right to left, 390 px -----------------------------------------------------------------------------------------
  await api(admin, `${B}/api/v1/accounts/${account}`, 'PATCH', { locale: 'ar' });
  const mobile = await login('agent_a@commerce.lynomia.local', { width: 390, height: 844 });
  await mobile.goto(`${B}/app/accounts/${account}/contacts`, { waitUntil: 'networkidle' });
  await mobile.waitForTimeout(1500);
  await openFilter(mobile);
  await mobile.locator('button', { hasText: 'الاسم' }).first().click();
  await mobile.waitForTimeout(300);
  await mobile.keyboard.type('الطلبات');
  await mobile.waitForTimeout(300);
  await shot(mobile, 'audience-08-ar-mobile-picker');
  await mobile.locator('li.n-dropdown-item', { hasText: 'الطلبات الظاهرة' }).first().click();
  await mobile.waitForTimeout(400);
  const arNotes = clean(await mobile.locator('[data-test-id="audience-notes"]').innerText().catch(() => ''));
  const dir = await mobile.evaluate(() => document.querySelector('[dir]')?.getAttribute('dir'));
  await shot(mobile, 'audience-09-ar-mobile-condition');
  // The filter panel itself; the page's off-canvas sidebar overflows in RTL before any filter opens (pre-existing).
  const panelBox = await mobile.locator('[data-test-id="audience-notes"]').locator('xpath=..').boundingBox();
  const inside = panelBox && panelBox.x >= 0 && panelBox.x + panelBox.width <= 390;
  check('Arabic at 390 px: right to left, the Commerce field and its notes in Arabic, the filter panel inside the screen',
    dir === 'rtl' && arNotes.includes('ليست إجماليات مدى الحياة') && inside, `dir=${dir} panel=${JSON.stringify(panelBox)}`);
  await admin.goto(`${B}/app/accounts/${account}/contacts`, { waitUntil: 'networkidle' });
  await admin.waitForTimeout(1500);
  await openFilter(admin);
  await admin.getByRole('button', { name: 'الاسم', exact: true }).click();
  await admin.waitForTimeout(300);
  await admin.keyboard.type('الطلبات');
  await admin.waitForTimeout(300);
  await admin.locator('li.n-dropdown-item', { hasText: 'الطلبات الظاهرة' }).first().click();
  await admin.waitForTimeout(400);
  const arDesktop = clean(await admin.locator('[data-test-id="audience-notes"]').innerText().catch(() => ''));
  await shot(admin, 'audience-10-ar-desktop');
  check('Arabic on a desktop screen: the same builder right to left, the Commerce notes in Arabic',
    arDesktop.includes('ليست إجماليات مدى الحياة'), arDesktop.slice(0, 120));
  await api(admin, `${B}/api/v1/accounts/${account}`, 'PATCH', { locale: 'en' });

  // ---- English, 390 px -----------------------------------------------------------------------------------------------------------
  const phone = await login('agent_a@commerce.lynomia.local', { width: 390, height: 844 });
  await phone.goto(`${B}/app/accounts/${account}/contacts`, { waitUntil: 'networkidle' });
  await phone.waitForTimeout(1500);
  await openFilter(phone);
  await phone.getByRole('button', { name: 'Name', exact: true }).first().click();
  await phone.waitForTimeout(300);
  await phone.keyboard.type('Visible orders');
  await phone.waitForTimeout(300);
  await phone.locator('li.n-dropdown-item', { hasText: 'Visible orders' }).first().click();
  await phone.waitForTimeout(400);
  const phoneBox = await phone.locator('[data-test-id="audience-notes"]').locator('xpath=..').boundingBox();
  await shot(phone, 'audience-11-en-mobile-condition');
  check('English at 390 px: the Commerce field and its notes, the filter panel inside the screen',
    phoneBox && phoneBox.x >= 0 && phoneBox.x + phoneBox.width <= 390, JSON.stringify(phoneBox));

  // ---- Safety ------------------------------------------------------------------------------------------------------------------
  const secrets = [keys.s1.ck, keys.s1.cs];
  check('no store key or secret in any response the browser received', !responses.some(body => secrets.some(secret => body.includes(secret))),
    `responses=${responses.length}`);
  check('no uncaught page errors', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));

  const teardown = ctl('teardown');
  check('teardown: stores, links, summaries and audiences of the run removed', teardown.stores === 0 && teardown.audiences === 0);
  await browser.close();
  fs.writeFileSync(`${out}/audience_e2e_results.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed`);
})().catch(async error => {
  console.log(`ERROR ${error.message}`);
  fs.writeFileSync(`${out}/audience_e2e_results.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed (aborted)`);
  if (browser) await browser.close();
  process.exit(1);
});
