// Lynomia Automation E2E (docs/automation/08-e2e.md): a shared audience saved in Contacts, a Commerce rule built in
// Chatwoot's rule builder (Settings → Automation), and a real order change on the disposable local WooCommerce test store
// A1 running that rule through Commerce's existing read, Chatwoot's dispatcher, a Sidekiq worker and the existing actions
// (a label, and a webhook to a local catcher standing in for n8n). Production configuration; Salla/Zid/Shopify stay off.
//
// usage: node e2e_automation.js <out_dir> <keys_json>   (keys_json: {"s1":{"ck","cs"}})
// env:   ERUN (the E2E runner), WP (wp-cli of the test store), WORKER (worker.sh), SCRATCH, WORKER_LOG
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { execSync } = require('child_process');
const http = require('http');
const fs = require('fs');

const B = 'http://localhost:3100';
const [out, keysJson] = process.argv.slice(2);
const keys = JSON.parse(keysJson);
const { ERUN, WP, WORKER, SCRATCH, WORKER_LOG } = process.env;
const PASSWORD = 'Password1!x';
const HOOK = 'http://127.0.0.1:3901/n8n/lynomia';
const ORDER = '23';
const COOLDOWN_MS = 31000;
const results = [];
const responses = [];
const pageErrors = [];

const check = (name, ok, detail = '') => {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  -- ${detail}` : ''}`);
};
const ctl = args => JSON.parse(execSync(`${ERUN} "bundle exec rails runner docs/automation/e2e/ctl.rb ${args} 2>/dev/null | grep '^SIM ' | tail -1"`)
  .toString().slice(4));
const wp = args => execSync(`${WP} ${args} 2>/dev/null`).toString().trim();
const worker = mode => execSync(`${WORKER} ${mode} ${SCRATCH}`);
// Requests the WooCommerce test store has answered (its access log; only counted, never kept: it names the key).
const storeCalls = () => Number(execSync("docker logs woo-wp 2>&1 | grep -c '/wp-json/wc/v3' || true").toString().trim());
// The worker's Lynomia Automation log lines (Automation::ExecutionLog), parsed.
const ruleLog = () => fs.readFileSync(WORKER_LOG, 'utf8').split('\n')
  .map(line => line.match(/\[Lynomia::Automation\] (\{.*\})\s*$/)).filter(Boolean).map(match => JSON.parse(match[1]));
const clean = text => (text || '').replace(/\s+/g, ' ').trim();
const sleep = ms => new Promise(resolve => { setTimeout(resolve, ms); });
const waitFor = async (probe, timeout = 60000) => {
  const until = Date.now() + timeout;
  while (Date.now() < until) {
    if (probe()) return true;
    await sleep(1000); // eslint-disable-line no-await-in-loop
  }
  return false;
};
const shot = (page, name) => page.screenshot({ path: `${out}/${name}.png` });

// The local stand-in for n8n: records what it receives.
const hooks = [];
const catcher = http.createServer((request, response) => {
  let body = '';
  request.on('data', chunk => { body += chunk; });
  request.on('end', () => {
    hooks.push({ path: request.url, body });
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end('{}');
  });
});

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
const condition = (key, operator, values, queryOperator = null) => ({ attribute_key: key, filter_operator: operator, values,
  query_operator: queryOperator });

// Chatwoot's filter rows (Contacts → Filter, and the rule builder's conditions): pick a field through the picker's search.
const pickField = async (page, row, currentLabel, search, option) => {
  await row.getByRole('button', { name: currentLabel, exact: true }).first().click();
  await page.waitForTimeout(300);
  const listed = clean(await page.locator('li.n-dropdown-item, li.select-none').allInnerTexts().then(list => list.join(' | ')));
  await page.keyboard.type(search);
  await page.waitForTimeout(300);
  await page.locator('li.n-dropdown-item', { hasText: option }).first().click();
  await page.waitForTimeout(400);
  return listed;
};
const pickValue = async (page, row, option) => {
  await row.locator('button:has(.i-lucide-plus)').first().click();
  await page.waitForTimeout(300);
  const listed = clean(await page.locator('li.n-dropdown-item').allInnerTexts().then(list => list.join(' | ')));
  await page.locator('li.n-dropdown-item', { hasText: option }).first().click();
  // Close the multi-select by clicking outside it (Escape would close the rule builder's side panel).
  await page.locator('section > label').first().click();
  await page.waitForTimeout(300);
  return listed;
};
const openRuleBuilder = async (page, account) => {
  await page.goto(`${B}/app/accounts/${account}/settings/automation/list`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1200);
  await page.getByRole('button', { name: /create automation|إنشاء/i }).first().click();
  await page.waitForTimeout(1200);
  return page.locator('select').first();
};

(async () => {
  catcher.listen(3901, '127.0.0.1');
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });
  const setup = ctl(`setup ${keys.s1.ck} ${keys.s1.cs}`);
  const account = setup.account_id;
  check('setup: store A1 connected (real WooCommerce, Read key); Demo B has its own audience, store and team', setup.store_id
    && setup.audience_b && setup.store_b && setup.team_b, JSON.stringify({ store: setup.store_id, b: [setup.audience_b, setup.store_b, setup.team_b] }));
  worker('default');

  // ---- Baseline: an agent opens Omar's conversation, the existing Commerce read --------------------------------------------
  const agent = await login('agent_a@commerce.lynomia.local');
  const panelUrl = `${B}/api/v1/accounts/${account}/conversations/${setup.conversation}/commerce/stores/${setup.store_id}`;
  const orderOf = panel => (panel.body?.orders || []).find(order => String(order.external_order_id) === ORDER);
  const baseline = await api(agent, panelUrl);
  check('baseline: the agent\'s Commerce read of Omar\'s orders (order 23 pending, unpaid) emits nothing',
    baseline.status === 200 && orderOf(baseline)?.status === 'pending' && ruleLog().length === 0,
    JSON.stringify({ status: baseline.status, order: orderOf(baseline)?.status, payment: orderOf(baseline)?.payment_status }));

  // ---- Shared audience: saved by an administrator in Contacts ----------------------------------------------------------------
  const admin = await login('admin_a@commerce.lynomia.local');
  await admin.goto(`${B}/app/accounts/${account}/contacts`, { waitUntil: 'networkidle' });
  await admin.waitForTimeout(1500);
  await admin.locator('#toggleContactsFilterButton').click();
  await admin.waitForTimeout(700);
  await pickField(admin, admin.locator('div.z-40 ul > li').nth(0), 'Name', 'Visible spend', 'Visible spend (SAR)');
  await admin.getByPlaceholder('Enter value').fill('1');
  await admin.getByRole('button', { name: /apply filters/i }).click();
  await admin.waitForTimeout(2000);
  await admin.locator('button:has(.i-lucide-save)').click();
  await admin.waitForTimeout(500);
  await admin.locator('dialog[open] input[type="text"], dialog[open] input:not([type])').first().fill('VIP buyers');
  const share = admin.locator('[data-test-id="share-audience"]');
  const shareText = clean(await share.innerText().catch(() => ''));
  await share.locator('button, input').first().click();
  await shot(admin, 'automation-01-share-audience');
  await admin.locator('dialog[open]').getByRole('button', { name: /save audience/i }).click();
  await admin.waitForURL(/\/contacts\/segments\/\d+/, { timeout: 30000 });
  await admin.waitForTimeout(1500);
  const vip = ctl('audiences').audiences.find(audience => audience.name === 'VIP buyers');
  const adminSidebar = clean(await admin.locator('nav, aside').first().innerText().catch(() => ''));
  check('an administrator saves "VIP buyers" as a shared audience (account-level) from Contacts → Filter',
    shareText.includes('Share with the whole account') && vip?.shared === true && adminSidebar.includes('VIP buyers · Shared'),
    JSON.stringify(vip && { shared: vip.shared, query: vip.query.payload }));
  const personal = await api(admin, `${B}/api/v1/accounts/${account}/custom_filters`, 'POST',
    { custom_filter: { name: 'My follow-ups', filter_type: 'contact', query: { payload: [condition('email', 'contains', ['example'])] } } });

  const agentShare = await api(agent, `${B}/api/v1/accounts/${account}/custom_filters`, 'POST',
    { custom_filter: { name: 'Agent share', filter_type: 'contact', shared: true, query: { payload: [condition('email', 'contains', ['x'])] } } });
  const agentEdit = await api(agent, `${B}/api/v1/accounts/${account}/custom_filters/${vip.id}`, 'PATCH', { custom_filter: { name: 'Hijacked' } });
  const agentDelete = await api(agent, `${B}/api/v1/accounts/${account}/custom_filters/${vip.id}`, 'DELETE');
  await agent.goto(`${B}/app/accounts/${account}/contacts/segments/${vip.id}`, { waitUntil: 'networkidle' });
  await agent.waitForTimeout(1500);
  const agentSidebar = clean(await agent.locator('nav, aside').first().innerText().catch(() => ''));
  const agentTrash = await agent.locator('button:has(.i-lucide-trash)').count();
  await agent.locator('#toggleContactsFilterButton').click();
  await agent.waitForTimeout(800);
  const agentNote = clean(await agent.locator('[data-test-id="shared-audience-note"]').innerText().catch(() => ''));
  await shot(agent, 'automation-02-agent-shared-audience');
  check('agents see the shared audience read-only: listed as shared, no delete, and cannot share, rename or delete',
    agentSidebar.includes('VIP buyers · Shared') && agentTrash === 0 && agentNote.includes('Only administrators can change it')
      && [agentShare, agentEdit, agentDelete].every(response => response.status === 401)
      && ctl('audiences').audiences.find(audience => audience.id === vip.id)?.name === 'VIP buyers',
    `${agentShare.status}/${agentEdit.status}/${agentDelete.status} trash=${agentTrash}`);

  // ---- The rule builder: Commerce trigger, audience and Commerce conditions, existing actions -----------------------------
  const select = await openRuleBuilder(admin, account);
  await admin.getByPlaceholder('Enter rule name').fill('Paid VIP order');
  await admin.getByPlaceholder('Enter rule description').fill('Label paid orders of VIP buyers and tell n8n');
  const groups = await select.locator('optgroup').evaluateAll(list => list.map(group => ({ label: group.label,
    options: [...group.querySelectorAll('option')].map(option => option.value) })));
  await select.selectOption('commerce_order_paid');
  await admin.waitForTimeout(600);
  const note = clean(await admin.locator('[data-test-id="commerce-trigger-note"]').innerText().catch(() => ''));
  check('the trigger list keeps the Conversation events and adds a Commerce group; a Commerce trigger says when it runs',
    groups.length === 2 && groups[0].label === 'Conversations' && groups[0].options.includes('conversation_created')
      && groups[1].label === 'Commerce' && ['commerce_order_created', 'commerce_order_paid', 'commerce_order_shipped',
      'commerce_order_cancelled', 'commerce_order_refunded'].every(event => groups[1].options.includes(event))
      && note.includes('latest conversation') && note.includes('Messages to the customer'),
    JSON.stringify(groups.map(group => `${group.label}:${group.options.length}`)));

  const conditionRows = () => admin.locator('section > ul.grid').nth(0).locator(':scope > li');
  const fields = await pickField(admin, conditionRows().nth(0), 'Status', 'audience', 'Contact audience');
  const operator = clean(await conditionRows().nth(0).innerText());
  const audienceOptions = await pickValue(admin, conditionRows().nth(0), 'VIP buyers');
  await admin.getByRole('button', { name: 'Add Condition' }).click();
  await admin.waitForTimeout(400);
  await pickField(admin, conditionRows().nth(1), 'Status', 'platform', 'Order store platform');
  await pickValue(admin, conditionRows().nth(1), 'WooCommerce');
  await shot(admin, 'automation-03-conditions');
  check('conditions: the existing fields plus Audience and Commerce groups; "Contact audience" reads "Is in" and offers only shared audiences',
    ['Audience', 'Contact audience', 'Commerce', 'Order store', 'Order store platform', 'Linked store', 'Visible spend (SAR)', 'Status',
      'Priority'].every(text => fields.includes(text)) && operator.includes('Is in') && audienceOptions.includes('VIP buyers')
      && !audienceOptions.includes('My follow-ups'), `${fields.slice(0, 200)} || ${audienceOptions}`);

  const actionRows = () => admin.locator('section > ul.grid').nth(1).locator(':scope > li');
  await actionRows().nth(0).getByRole('button', { name: 'Assign to Agent' }).first().click();
  await admin.waitForTimeout(300);
  const actionList = clean(await admin.locator('li.n-dropdown-item').allInnerTexts().then(list => list.join(' | ')));
  await shot(admin, 'automation-04-actions');
  await admin.locator('li.n-dropdown-item', { hasText: 'Add a Label' }).first().click();
  await admin.waitForTimeout(300);
  await pickValue(admin, actionRows().nth(0), 'paid-vip');
  await admin.getByRole('button', { name: 'Add Action' }).click();
  await admin.waitForTimeout(300);
  await actionRows().nth(1).getByRole('button', { name: 'Assign to Agent' }).first().click();
  await admin.waitForTimeout(300);
  await admin.locator('li.n-dropdown-item', { hasText: 'Send Webhook Event' }).first().click();
  await admin.waitForTimeout(300);
  await actionRows().nth(1).locator('input[type="url"]').fill(HOOK);
  check('actions are Chatwoot\'s own; a Commerce trigger offers no customer message (send message / attachment)',
    ['Add a Label', 'Send Webhook Event', 'Add a Private Note', 'Assign a Team'].every(text => actionList.includes(text))
      && !actionList.includes('Send a Message') && !actionList.includes('Send Attachment'), actionList);
  await shot(admin, 'automation-05-rule');
  await admin.getByRole('button', { name: 'Create', exact: true }).click();
  await admin.waitForTimeout(2000);
  await shot(admin, 'automation-06-rule-list');
  const created = ctl('state').rules.find(rule => rule.name === 'Paid VIP order');
  check('the rule is saved as an ordinary automation rule: commerce_order_paid, audience + platform conditions, label + webhook',
    created?.event_name === 'commerce_order_paid' && created.active
      && JSON.stringify(created.conditions.map(row => [row.attribute_key, row.filter_operator, row.values]))
        === JSON.stringify([['contact_audience', 'equal_to', [vip.id]], ['commerce_event_provider', 'equal_to', ['woocommerce']]])
      && JSON.stringify(created.actions) === JSON.stringify([{ action_name: 'add_label', action_params: ['paid-vip'] },
        { action_name: 'send_webhook_event', action_params: [HOOK] }]), JSON.stringify(created));

  // ---- The API: what the builder cannot send is refused too ------------------------------------------------------------------
  const rules = `${B}/api/v1/accounts/${account}/automation_rules`;
  const rule = (name, event, conditions, actions) => ({ name, event_name: event, conditions, actions });
  const notVip = await api(admin, rules, 'POST', rule('Not VIP (probe)', 'commerce_order_paid',
    [condition('contact_audience', 'not_equal_to', [vip.id])], [{ action_name: 'add_private_note', action_params: ['Not a VIP order'] }]));
  const foreignTeam = await api(admin, rules, 'POST', rule('Foreign team (probe)', 'commerce_order_paid',
    [condition('commerce_event_provider', 'equal_to', ['woocommerce'])],
    [{ action_name: 'assign_team', action_params: [setup.team_b] }, { action_name: 'assign_agent', action_params: [setup.agent_b] }]));
  const refused = await Promise.all([
    api(admin, rules, 'POST', rule('x', 'commerce_order_paid', [condition('contact_audience', 'equal_to', [personal.body?.id])], [])),
    api(admin, rules, 'POST', rule('x', 'commerce_order_paid', [condition('contact_audience', 'equal_to', [setup.audience_b])], [])),
    api(admin, rules, 'POST', rule('x', 'commerce_order_paid', [condition('commerce_event_store', 'equal_to', [setup.store_b])], [])),
    api(admin, rules, 'POST', rule('x', 'commerce_order_paid', [condition('commerce_event_provider', 'equal_to', ['woocommerce'])],
      [{ action_name: 'send_message', action_params: ['Thanks for paying!'] }])),
    api(admin, rules, 'POST', rule('x', 'conversation_created', [condition('commerce_event_provider', 'equal_to', ['woocommerce'])], [])),
    api(admin, rules, 'POST', rule('x', 'commerce_order_paid', [condition('commerce_event_provider', 'equal_to', ["woocommerce' OR 1=1 --"])], [])),
  ]);
  check('the API refuses a personal audience, Demo B\'s audience, Demo B\'s store, a customer message on a Commerce trigger, '
    + 'an event condition without a Commerce trigger and an injected platform (422)', personal.status === 200 && personal.body?.shared === false
    && notVip.status === 200 && foreignTeam.status === 200 && refused.every(response => response.status === 422),
  refused.map(response => `${response.status}:${clean(JSON.stringify(response.body?.message || response.body?.error || '')).slice(0, 60)}`).join(' | '));
  const agentRule = await api(agent, rules, 'POST', rule('x', 'commerce_order_paid', [condition('commerce_event_provider', 'equal_to', ['woocommerce'])], []));
  const adminB = await login('admin_b@commerce.lynomia.local');
  const crossRead = await api(adminB, `${rules}/${created.id}`);
  const crossFilter = await api(adminB, `${B}/api/v1/accounts/${setup.account_b_id}/automation_rules`, 'POST', rule('x', 'commerce_order_paid',
    [condition('contact_audience', 'equal_to', [vip.id])], []));
  check('agents cannot create rules; Demo B can neither read Demo A\'s rule nor use Demo A\'s audience',
    agentRule.status === 401 && crossRead.status === 401 && crossFilter.status === 422, `${agentRule.status}/${crossRead.status}/${crossFilter.status}`);

  // ---- The real flow, worker as shipped (SSRF guard on): order 23 paid on the store → refresh → rule -------------------------
  const callsBefore = storeCalls();
  wp(`wc shop_order update ${ORDER} --status=processing --user=1`);
  const refresh = () => api(agent, `${B}/api/v1/accounts/${account}/conversations/${setup.conversation}/commerce/refresh?store_id=${setup.store_id}`, 'POST');
  const paid = await refresh();
  const firstRefreshAt = Date.now();
  const ran = ruleId => ruleLog().filter(entry => entry.rule_id === ruleId);
  await waitFor(() => ran(created.id).length === 1 && ran(notVip.body.id).length === 1 && ran(foreignTeam.body.id).length === 1);
  const afterPaid = ctl('state');
  check('the store\'s order 23 → processing; the agent\'s Refresh reads it as paid (one store call) and the worker runs the rule: '
    + 'label on Omar\'s latest conversation', paid.status === 200 && orderOf(paid)?.payment_status === 'paid' && storeCalls() > callsBefore
    && ran(created.id)[0]?.outcome === 'executed' && afterPaid.labels.includes('paid-vip'),
  JSON.stringify({ refresh: paid.status, payment: orderOf(paid)?.payment_status, outcome: ran(created.id)[0]?.outcome, labels: afterPaid.labels }));
  check('the same event, the audience condition the other way: "is not in VIP buyers" is skipped',
    ran(notVip.body.id)[0]?.outcome === 'skipped', JSON.stringify(ran(notVip.body.id)[0]));
  check('Demo B\'s team and agent in a rule are never applied: the conversation keeps its team and assignee',
    ran(foreignTeam.body.id)[0]?.outcome === 'executed' && afterPaid.team_id === setup.team_id && afterPaid.assignee_id === setup.assignee_id,
    JSON.stringify({ team: afterPaid.team_id, assignee: afterPaid.assignee_id }));
  await waitFor(() => fs.readFileSync(WORKER_LOG, 'utf8').includes(`Invalid webhook URL ${HOOK}`), 30000);
  check('the webhook goes through the existing SSRF guard: a private address is refused as shipped (nothing reached the catcher)',
    hooks.length === 0 && fs.readFileSync(WORKER_LOG, 'utf8').includes(`Invalid webhook URL ${HOOK}`), `hooks=${hooks.length}`);
  const entry = ran(created.id)[0];
  check('one log line per rule and event: ids, trigger, outcome, duration, actions; no contact data',
    entry && Object.keys(entry).sort().join() === 'account_id,actions,correlation_id,duration_ms,event,outcome,rule_id,trigger'
      && entry.trigger === 'commerce_order_paid' && !JSON.stringify(ruleLog()).match(/omar|khalil|@example|\+9/i), JSON.stringify(entry));

  // Back to pending (an update with no rule: nothing runs), then the worker as an operator runs it for a private n8n.
  wp(`wc shop_order update ${ORDER} --status=pending --user=1`);
  await sleep(Math.max(0, firstRefreshAt + COOLDOWN_MS - Date.now()));
  const linesBefore = ruleLog().length;
  const pending = await refresh();
  const secondRefreshAt = Date.now();
  await sleep(4000);
  check('order 23 back to pending: an update no rule listens to runs nothing', pending.status === 200 && orderOf(pending)?.status === 'pending'
    && ruleLog().length === linesBefore, `lines ${linesBefore} → ${ruleLog().length}`);

  worker('private-network');
  wp(`wc shop_order update ${ORDER} --status=processing --user=1`);
  await sleep(Math.max(0, secondRefreshAt + COOLDOWN_MS - Date.now()));
  const paidAgain = await refresh();
  await waitFor(() => ran(created.id).length === 2 && hooks.length === 1);
  await sleep(2000);
  const hook = hooks[0] ? JSON.parse(hooks[0].body) : {};
  check('paid again, with SAFE_FETCH_ALLOW_PRIVATE_NETWORK (self-hosted n8n): the webhook carries the conversation and the Commerce event',
    paidAgain.status === 200 && hooks.length === 1 && hook.event === 'automation_event.commerce_order_paid'
      && hook.commerce?.event === 'commerce_order_paid' && hook.commerce?.provider === 'woocommerce' && hook.commerce?.store_id === setup.store_id
      && hook.commerce?.order?.number === ORDER && hook.commerce?.order?.payment_status === 'paid' && hook.id === afterPaid.conversation,
    JSON.stringify(hook.commerce));
  check('the webhook carries no store key or secret', hooks.every(item => !item.body.includes(keys.s1.ck) && !item.body.includes(keys.s1.cs)));

  const linesAfter = ruleLog().length;
  const cached = await api(agent, panelUrl);
  await sleep(5000);
  check('a cached read of the same orders emits nothing: no new run, no new webhook', cached.status === 200 && ruleLog().length === linesAfter
    && hooks.length === 1, `lines=${ruleLog().length} hooks=${hooks.length}`);
  wp(`wc shop_order update ${ORDER} --status=pending --user=1`);
  check('the test store\'s order 23 is back to pending', wp(`wc shop_order get ${ORDER} --field=status --user=1`) === 'pending');

  // ---- An audience in use cannot be deleted or unshared --------------------------------------------------------------------
  await admin.goto(`${B}/app/accounts/${account}/contacts/segments/${vip.id}`, { waitUntil: 'networkidle' });
  await admin.waitForTimeout(1500);
  await admin.locator('#toggleContactsFilterButton').click();
  await admin.waitForTimeout(800);
  const adminNote = clean(await admin.locator('[data-test-id="shared-audience-note"]').innerText().catch(() => ''));
  await shot(admin, 'automation-07-audience-in-use');
  await admin.goto(`${B}/app/accounts/${account}/contacts/segments/${vip.id}`, { waitUntil: 'networkidle' });
  await admin.waitForTimeout(1500);
  await admin.locator('button:has(.i-lucide-trash)').first().click();
  await admin.waitForTimeout(400);
  await admin.locator('dialog[open]').getByRole('button', { name: /yes, delete/i }).click();
  await admin.waitForTimeout(800);
  const toast = clean(await admin.locator('body').innerText());
  await shot(admin, 'automation-08-delete-refused');
  const apiDelete = await api(admin, `${B}/api/v1/accounts/${account}/custom_filters/${vip.id}`, 'DELETE');
  const apiUnshare = await api(admin, `${B}/api/v1/accounts/${account}/custom_filters/${vip.id}`, 'PATCH', { custom_filter: { shared: false } });
  check('deleting or unsharing an audience rules use is refused with "This audience is used by 2 automation rules"',
    adminNote.includes('used by 2 active automation rules') && toast.includes('This audience is used by 2 automation rules')
      && apiDelete.status === 422 && apiUnshare.status === 422 && ctl('audiences').audiences.some(audience => audience.id === vip.id && audience.shared),
    `${adminNote.slice(0, 90)} | ${apiDelete.status}/${apiUnshare.status}`);

  // ---- The kill switch: only Lynomia's additions stop -------------------------------------------------------------------------
  ctl('extensions off');
  const offLynomia = await api(admin, rules, 'POST', rule('x', 'conversation_created', [condition('contact_audience', 'equal_to', [vip.id])], []));
  const offPlain = await api(admin, rules, 'POST', rule('Plain rule', 'conversation_created', [condition('status', 'equal_to', ['open'])],
    [{ action_name: 'add_label', action_params: ['paid-vip'] }]));
  ctl('extensions on');
  check('LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED=false refuses audience/Commerce conditions; plain Chatwoot rules save as before',
    offLynomia.status === 422 && offPlain.status === 200, `${offLynomia.status}/${offPlain.status}`);
  await api(admin, `${rules}/${offPlain.body?.id}`, 'DELETE');

  // ---- Arabic and mobile ---------------------------------------------------------------------------------------------------------
  await api(admin, `${B}/api/v1/accounts/${account}`, 'PATCH', { locale: 'ar' });
  const arSelect = await openRuleBuilder(admin, account);
  await arSelect.selectOption('commerce_order_paid');
  await admin.waitForTimeout(600);
  const arGroups = await arSelect.locator('optgroup').evaluateAll(list => list.map(group => group.label));
  const arNote = clean(await admin.locator('[data-test-id="commerce-trigger-note"]').innerText().catch(() => ''));
  await admin.locator('section > ul.grid').nth(0).locator(':scope > li').nth(0).getByRole('button').nth(0).click();
  await admin.waitForTimeout(400);
  const arFields = clean(await admin.locator('li.n-dropdown-item, li.select-none').allInnerTexts().then(list => list.join(' | ')));
  await admin.locator('li.n-dropdown-item', { hasText: 'منصة متجر الطلب' }).first().scrollIntoViewIfNeeded();
  await shot(admin, 'automation-09-ar-desktop');
  check('Arabic: the trigger groups, the Commerce note and the Audience / Commerce conditions in Arabic (Commerce is the product name)',
    arGroups.join() === 'المحادثات,Commerce' && arNote.includes('آخر محادثة لجهة الاتصال') && arFields.includes('الجمهور')
      && arFields.includes('جمهور جهة الاتصال') && arFields.includes('منصة متجر الطلب'), `${arGroups.join(' / ')} | ${arNote.slice(0, 60)}`);

  const mobile = await login('admin_a@commerce.lynomia.local', { width: 390, height: 844 });
  const mobileSelect = await openRuleBuilder(mobile, account);
  await mobileSelect.selectOption('commerce_order_paid');
  await mobile.waitForTimeout(600);
  const dir = await mobile.evaluate(() => document.querySelector('[dir]')?.getAttribute('dir'));
  const box = await mobile.locator('[data-test-id="commerce-trigger-note"]').boundingBox();
  await shot(mobile, 'automation-10-ar-mobile');
  check('Arabic at 390 px: right to left, the rule builder and its Commerce note inside the screen',
    dir === 'rtl' && box && box.x >= 0 && box.x + box.width <= 390, JSON.stringify(box));
  await api(admin, `${B}/api/v1/accounts/${account}`, 'PATCH', { locale: 'en' });

  const phone = await login('admin_a@commerce.lynomia.local', { width: 390, height: 844 });
  const phoneSelect = await openRuleBuilder(phone, account);
  await phoneSelect.selectOption('commerce_order_paid');
  await phone.waitForTimeout(600);
  const phoneBox = await phone.locator('[data-test-id="commerce-trigger-note"]').boundingBox();
  await shot(phone, 'automation-11-en-mobile');
  check('English at 390 px: the rule builder and its Commerce note inside the screen',
    phoneBox && phoneBox.x >= 0 && phoneBox.x + phoneBox.width <= 390, JSON.stringify(phoneBox));

  // ---- Safety ------------------------------------------------------------------------------------------------------------------
  const secrets = [keys.s1.ck, keys.s1.cs];
  check('no store key or secret in any response the browser received', !responses.some(body => secrets.some(secret => body.includes(secret))),
    `responses=${responses.length}`);
  check('no uncaught page errors', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));

  const teardown = ctl('teardown');
  check('teardown: stores, audiences, rules and the run\'s label removed', teardown.stores === 0 && teardown.audiences === 0
    && teardown.rules === 0 && teardown.labels === 0, JSON.stringify(teardown));
  await browser.close();
  catcher.close();
  fs.writeFileSync(`${out}/automation_e2e_results.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed`);
})().catch(async error => {
  console.log(`ERROR ${error.message}`);
  fs.writeFileSync(`${out}/automation_e2e_results.json`, JSON.stringify(results, null, 2));
  console.log(`${results.filter(r => r.ok).length}/${results.length} passed (aborted)`);
  if (browser) await browser.close();
  catcher.close();
  process.exit(1);
});
