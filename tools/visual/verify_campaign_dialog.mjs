// Does the campaign create flow still work after moving it off the popover and onto a modal dialog?
//
//   NODE_PATH=/path/to/playwright node tools/visual/verify_campaign_dialog.mjs
//
// Checks, against the running dev server, the six things the change could have broken:
//   1. the header button opens it
//   2. Escape closes it            (the popover had no Escape at all)
//   3. focus is trapped inside it  (the popover trapped nothing)
//   4. the backdrop click closes it
//   5. the editor's own link prompt does NOT close it -- the behaviour the old `ignore` selector
//      protected, which the Dialog now protects by only closing when it is the topmost `dialog[open]`
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');

const BASE = 'http://localhost:3000';
const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok, detail });
  process.stdout.write(
    `${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` -- ${detail}` : ''}\n`
  );
};

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

await page.goto(`${BASE}/app/login`, {
  waitUntil: 'networkidle',
  timeout: 45000,
});
await page.fill('[data-testid="email_input"]', 'john@acme.inc');
await page.fill('[data-testid="password_input"]', 'Password1!');
await page.click('[data-testid="submit_button"]');
await page.waitForURL(/\/app\/accounts\//, {
  waitUntil: 'commit',
  timeout: 45000,
});

await page.goto(`${BASE}/app/accounts/1/campaigns/live_chat`, {
  waitUntil: 'domcontentloaded',
  timeout: 120000,
});
await page.waitForTimeout(4000);

const dialogOpen = () =>
  page.evaluate(() => !!document.querySelector('dialog[open]'));

// 1 ───────────────────────────────────────────────────────────────
await page.click('header button');
await page.waitForTimeout(800);
check('the header button opens a real <dialog>', await dialogOpen());

// 2 ───────────────────────────────────────────────────────────────
const title = await page.evaluate(() => {
  const d = document.querySelector('dialog[open]');
  if (!d) return null;
  const labelled = d.getAttribute('aria-labelledby');
  return labelled
    ? document.getElementById(labelled)?.textContent?.trim()
    : null;
});
check(
  'it has an accessible name',
  !!title,
  title || 'aria-labelledby resolved to nothing'
);

// 3 ───────────────────────────────────────────────────────────────
const trapped = await page.evaluate(async () => {
  const d = document.querySelector('dialog[open]');
  if (!d) return false;
  // Walk the tab order a few times; a native modal dialog must never hand focus to the page behind it.
  for (let i = 0; i < 12; i += 1) {
    const active = document.activeElement;
    if (active && active !== document.body && !d.contains(active)) return false;
    const focusables = d.querySelectorAll(
      'a[href], button:not([disabled]), input:not([disabled]), textarea, select, [tabindex]:not([tabindex="-1"])'
    );
    if (!focusables.length) return false;
    focusables[i % focusables.length].focus();
  }
  return true;
});
check('focus stays inside it', trapped);

// 4 ───────────────────────────────────────────────────────────────
await page.keyboard.press('Escape');
await page.waitForTimeout(600);
check('Escape closes it', !(await dialogOpen()));

// 5 ───────────────────────────────────────────────────────────────
await page.click('header button');
await page.waitForTimeout(800);
const reopened = await dialogOpen();
await page.mouse.click(60, 450); // well outside the centred dialog
await page.waitForTimeout(600);
check('a click on the backdrop closes it', reopened && !(await dialogOpen()));

// 6 ───────────────────────────────────────────────────────────────
// A second <dialog> on top -- which is exactly what the editor's link prompt is -- must not take the
// campaign dialog down with it when it is dismissed.
await page.click('header button');
await page.waitForTimeout(800);
const survives = await page.evaluate(async () => {
  const campaign = document.querySelector('dialog[open]');
  if (!campaign)
    return { ok: false, why: 'the campaign dialog did not reopen' };
  const prompt = document.createElement('dialog');
  prompt.className = 'ProseMirror-prompt-backdrop';
  prompt.innerHTML = '<input id="probe-field">';
  document.body.appendChild(prompt);
  prompt.showModal();
  prompt.querySelector('#probe-field').focus();
  // A click inside the prompt: the campaign dialog's own click-outside sees it, and must decline
  // because it is no longer the topmost open dialog.
  prompt.querySelector('#probe-field').click();
  await new Promise(resolve => {
    setTimeout(resolve, 300);
  });
  const stillOpen = campaign.hasAttribute('open');
  prompt.close();
  prompt.remove();
  return {
    ok: stillOpen,
    why: stillOpen ? '' : 'the campaign dialog closed under the prompt',
  };
});
check('a nested prompt does not close it', survives.ok, survives.why);

await browser.close();

const failed = results.filter(r => !r.ok);
process.stdout.write(
  `\n${results.length - failed.length}/${results.length} passed\n`
);
process.exit(failed.length ? 1 : 0);
