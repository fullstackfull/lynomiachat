// PHOTOGRAPHING THE OTHER END OF THE CONVERSATION.
//
// `capture.mjs` shoots the agent's screen, which is ours. This shoots the VISITOR'S: the website chat widget
// as it appears on a customer's own site, which is the half of "connect website chat" that no screenshot of
// the dashboard can show and that the documentation had no picture of at all.
//
// WHAT IS REAL. The widget is this installation's own `sdk.js`, run from the snippet
// `Channel::WebWidget#web_widget_script` generates, against a website token read out of the database. The
// conversation it starts is a real conversation: it appears in the agent's inbox, and
// `--also-agent` shoots it there in the same run, which is the whole point of the pair.
//
// THE PAGE AROUND IT IS A DEMO SHOP that does not exist, in `widget-host/index.html`, served here on its own
// port so the widget is embedded CROSS-ORIGIN exactly as it is on a real site. It is not a route and it
// ships nowhere.
//
//   WIDGET_TOKEN=... node tools/visual/capture-widget.mjs --out docs/screenshots/sources/widget
//   node tools/visual/capture-widget.mjs --locale ar --out ...
//
// EVERY TOKENLESS LOAD CREATES A CONTACT, so each run leaves one behind in the development database. That is
// why this is a separate script run deliberately rather than a set inside the main one, and why
// `docs/screenshots/README.md` says to run it last.

import { createRequire } from 'node:module';
import { mkdir, readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import path from 'node:path';

const { chromium } = createRequire(import.meta.url)('playwright');

const ROOT = path.resolve(import.meta.dirname, '../..');
const BASE = process.env.CAPTURE_BASE_URL || 'http://localhost:3000';
const TOKEN = process.env.WIDGET_TOKEN;
const HOST_PORT = Number(process.env.WIDGET_HOST_PORT || 4173);

const args = process.argv.slice(2);
const arg = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};
const outDir = arg('out', 'docs/screenshots/sources/widget');
const locale = arg('locale', 'en');

if (!TOKEN) {
  throw new Error(
    'WIDGET_TOKEN is required. Read it from the database:\n' +
      '  bin/rails runner \'puts Account.first.inboxes.find { |i| i.channel_type == "Channel::WebWidget" }.channel.website_token\''
  );
}

// The demo shop, with the token and base URL substituted. One file read, held in memory for the run.
const template = await readFile(path.join(ROOT, 'tools/visual/widget-host/index.html'), 'utf8');
const html = template.replaceAll('__WEBSITE_TOKEN__', TOKEN).replaceAll('__BASE_URL__', BASE);

const host = createServer((_req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(html);
});
await new Promise(resolve => host.listen(HOST_PORT, '127.0.0.1', resolve));

// `resolve`, not `join`: an absolute `--out` is a path somewhere else, and joining it onto ROOT buries it
// under the repository instead.
const out = path.resolve(ROOT, outDir, locale);
await mkdir(out, { recursive: true });

const browser = await chromium.launch();
// THE LOCALE IS THE BROWSER'S, not a setting. `useBrowserLanguage` is on in the snippet, so the widget reads
// `navigator.language` -- which is exactly how it decides on a real visitor's machine, and the only honest
// way to photograph the Arabic widget.
const context = await browser.newContext({
  viewport: { width: 1280, height: 860 },
  deviceScaleFactor: 1,
  locale: locale === 'ar' ? 'ar-SA' : 'en-GB',
});
const page = await context.newPage();

// DEV CHROME MUST NOT BE IN THE EVIDENCE. `rack-mini-profiler` paints a timing badge over the top corner of
// every development response, including the widget's own iframe. It does not exist in production.
await page.addInitScript(() => {
  const hide = () => {
    const style = document.createElement('style');
    style.textContent = '.profiler-results,#profiler-results{display:none !important}';
    document.documentElement.appendChild(style);
  };
  if (document.documentElement) hide();
  else document.addEventListener('DOMContentLoaded', hide);
});

const shot = async (name, target) => {
  const file = path.join(out, `${name}.png`);
  await (target || page).screenshot({ path: file });
  process.stdout.write(`${path.relative(ROOT, file)}\n`);
};

await page.goto(`http://127.0.0.1:${HOST_PORT}/`, { waitUntil: 'networkidle', timeout: 60000 });

// WAIT FOR THE BUTTON, NOT ITS HOLDER. `#cw-bubble-holder` is a zero-size positioning context whose child
// button is absolutely placed, so Playwright reports the holder "hidden" however well the widget is
// working. The button appearing is the only honest signal that the SDK ran and the token was accepted.
const bubbleButton = page.locator('button.woot-widget-bubble').first();
await bubbleButton.waitFor({ state: 'visible', timeout: 60000 });
await page.waitForTimeout(2500);

// 1. THE SHOP WITH THE WIDGET CLOSED. What a visitor sees before they do anything, which is the thing an
//    administrator is deciding about when they choose a position and a colour.
await shot('host-closed');

// 2. THE WIDGET OPEN. Click the real bubble rather than calling the SDK, because a reader clicks the bubble.
await bubbleButton.click({ timeout: 20000 });
await page.waitForTimeout(3500);
await shot('host-open');

// 3. THE PANEL ALONE, cropped to the widget, for the places a figure needs the widget and not the shop.
const panel = page.locator('.woot-widget-holder').first();
if (await panel.count()) await shot('panel', panel);

// 4. START CONVERSATION. The widget opens on a greeting and a button, not on a composer -- that is the
//    real first screen, and it is where the away message and the reply-time estimate are shown. A reader
//    following this article clicks it, so the capture clicks it.
const widget = page.frameLocator('.woot-widget-holder iframe').first();
const start = widget.locator('button, a').filter({ hasText: /start conversation|ابدأ|بدء/i }).first();
if (await start.count()) {
  await start.click({ timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(2500);
  await shot('host-started');
}

// 5. A REAL MESSAGE, typed into the real composer and sent. From here on this run has created a contact and
//    a conversation in the database, which the agent-side capture then photographs from the other end.
const composer = widget.locator('textarea, [contenteditable="true"]').first();
const message = locale === 'ar' ? 'مرحبًا! هل دفتر A5 المنقّط متوفر؟' : 'Hi! Is the A5 dotted notebook back in stock?';

try {
  await composer.waitFor({ timeout: 20000 });
  await composer.click();
  await composer.fill(message);
  await page.waitForTimeout(600);
  await shot('host-typed');

  await composer.press('Enter');
  await page.waitForTimeout(4000);
  await shot('host-sent');
  if (await panel.count()) await shot('panel-sent', panel);
} catch (error) {
  // A pre-chat form stands between the visitor and the composer when an administrator has switched one on.
  // That is a legitimate configuration and a different figure, so it is reported rather than treated as a
  // failure of the run.
  process.stdout.write(`composer not reached (${error.name}); shooting what is there instead\n`);
  await shot('host-prechat');
}

await browser.close();
host.close();
console.log(`widget captures written to ${outDir}/${locale}`);
