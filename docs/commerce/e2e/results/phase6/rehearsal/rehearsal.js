// Container staging rehearsal: UI, WebSocket and Super Admin checks against http://localhost:3100.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const B = 'http://localhost:3100';
const out = process.argv[2];
const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  -- ${detail}` : ''}`); };

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const frames = [];
  page.on('websocket', ws => ws.on('framereceived', f => frames.push(String(f.payload))));
  const inboxBodies = [];
  page.on('response', async r => { if (/\/api\/v1\/accounts\/\d+\/inboxes(\/\d+)?(\?|$)/.test(r.url())) inboxBodies.push(await r.text().catch(() => '')); });
  const consoleErrors = [];
  page.on('pageerror', e => consoleErrors.push(e.message));

  await page.goto(`${B}/app/login`, { waitUntil: 'networkidle' });
  await page.fill('input[name="email_address"], input[type="email"]', 'admin_a@staging.lynomia.local');
  await page.fill('input[type="password"]', 'Password1!x');
  await page.keyboard.press('Enter');
  await page.waitForURL(/\/app\/accounts\/\d+/, { timeout: 60000 });
  const accountId = page.url().match(/accounts\/(\d+)/)[1];
  await page.waitForTimeout(4000);
  await page.screenshot({ path: `${out}/img-01-dashboard.png` });
  check('dashboard login', true, `account ${accountId}`);
  check('websocket welcome', frames.some(f => f.includes('"welcome"')));
  check('websocket RoomChannel subscribed', frames.some(f => f.includes('confirm_subscription') && f.includes('RoomChannel')));
  const navText = await page.locator('nav, aside').first().innerText();
  check('Calls hidden from sidebar', !/\bCalls\b|المكالمات/.test(navText));

  await page.goto(`${B}/app/accounts/${accountId}/settings/inboxes/new/whatsapp`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${out}/img-02-whatsapp-picker.png` });
  const pickerText = await page.innerText('body');
  check('WhatsApp Business option listed', /WhatsApp Business|واتساب بزنس/.test(pickerText));
  check('no "WhatsApp QR" naming', !/WhatsApp QR/i.test(pickerText));

  check('inbox API responses have provider_config but no api_key', inboxBodies.length > 0 && inboxBodies.some(b => b.includes('provider_config')) && inboxBodies.every(b => !b.includes('"api_key"')), `responses=${inboxBodies.length}`);

  await page.goto(`${B}/app/accounts/${accountId}/settings/inboxes/1?tab=configuration`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${out}/img-03-manual-inbox-configuration.png` });

  await page.goto(`${B}/app/accounts/${accountId}/settings/subscription`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${out}/img-04-lynomia-subscription.png` });
  check('Lynomia subscription page renders', (await page.innerText('body')).length > 50, page.url());
  check('no uncaught page errors', consoleErrors.length === 0, consoleErrors.slice(0, 3).join(' | '));

  const sa = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await sa.goto(`${B}/super_admin/sign_in`, { waitUntil: 'networkidle' });
  await sa.fill('input[type="email"], input[name="email"]', 'superadmin@staging.lynomia.local');
  await sa.fill('input[type="password"]', 'Password1!x');
  await Promise.all([sa.waitForNavigation({ waitUntil: 'networkidle' }), sa.keyboard.press('Enter')]);
  check('super admin signed in', !sa.url().includes('sign_in'), sa.url());
  for (const [path, name] of [['/super_admin', 'img-05-super-admin'], ['/super_admin/app_config?config=whatsapp_embedded', 'img-06-sa-whatsapp-app-secret'],
    ['/super_admin/billing_plans/settings', 'img-07-sa-billing-settings'], ['/super_admin/billing_plans', 'img-08-sa-billing-plans'],
    ['/super_admin/app_config?config=salla', 'img-09-sa-salla'], ['/super_admin/app_config?config=zid', 'img-10-sa-zid'],
    ['/super_admin/app_config?config=shopify_commerce', 'img-11-sa-shopify-commerce']]) {
    const r = await sa.goto(`${B}${path}`, { waitUntil: 'networkidle' });
    await sa.waitForTimeout(800);
    await sa.screenshot({ path: `${out}/${name}.png` });
    check(`super admin ${path}`, r.status() === 200 && !sa.url().includes('sign_in'), `http=${r.status()} url=${sa.url().replace(B, '')}`);
    if (/salla|zid|shopify_commerce/.test(path)) {
      const html = await sa.content();
      check(`${path}: client secret is a password field`, /type="password"[^>]*CLIENT_SECRET|CLIENT_SECRET[^>]*type="password"/.test(html));
      check(`${path}: stored client secret not in page`, !html.includes(process.env.STAGING_COMMERCE_SECRET));
    }
    if (path.includes('whatsapp_embedded')) {
      const html = await sa.content();
      check('WHATSAPP_APP_SECRET field is a password field', /type="password"[^>]*WHATSAPP_APP_SECRET|WHATSAPP_APP_SECRET[^>]*type="password"/.test(html));
      check('stored WHATSAPP_APP_SECRET not in page', !html.includes(process.env.STAGING_APP_SECRET));
    }
  }
  await browser.close();
  require('fs').writeFileSync(`${out}/rehearsal_ui.json`, JSON.stringify(results, null, 2));
  const failed = results.filter(r => !r.ok).length;
  console.log(`${results.length - failed}/${results.length} UI checks passed`);
})().catch(e => { console.error(e); process.exit(1); });
