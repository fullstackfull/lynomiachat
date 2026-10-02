// Lynomia Flow Builder canvas performance (docs/flow-builder/09-performance.md): the real builder (production build, Vue
// Flow) in Chromium on 50, 100 and 200-node flows: initial render, zoom, pan, node select, config panel, editing a
// node, dragging a node, adding an edge, saving; then memory, idle re-renders, duplicates, console errors and input
// delay; then the 200-node flow in English and Arabic on desktop and at 390 px.
//
// usage: node canvas.js <out_dir>     env: ERUN (the E2E runner), CHROMIUM_PATH, PLAYWRIGHT_MODULE
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { execSync } = require('child_process');
const fs = require('fs');

const B = 'http://localhost:3100';
const [out] = process.argv.slice(2);
const SIZES = (process.env.SIZES || '50,100,200').split(',').map(Number);
const LOADS = 3;
const results = { sizes: {}, matrix: {} };
const consoleErrors = [];
let currentPage;
let phase = 'setup';

const ctl = args => JSON.parse(execSync(`${process.env.ERUN} "bundle exec rails runner docs/flow-builder/e2e/ctl.rb ${args} 2>/dev/null | grep '^SIM ' | tail -1"`)
  .toString().slice(4));
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const round = value => Math.round(value * 10) / 10;

// Long tasks, Event Timing (input delay) and animation frames, recorded in the page.
const INSTRUMENT = () => {
  window.perfLog = { longTasks: [], events: [] };
  new PerformanceObserver(list => list.getEntries().forEach(entry => window.perfLog.longTasks.push(entry.duration)))
    .observe({ type: 'longtask', buffered: true });
  new PerformanceObserver(list => list.getEntries().forEach(entry => window.perfLog.events.push(entry.duration)))
    .observe({ type: 'event', durationThreshold: 16, buffered: true });
};
const startFrames = page => page.evaluate(() => {
  window.frameLog = [];
  window.recording = true;
  let last = performance.now();
  const tick = now => {
    window.frameLog.push(now - last);
    last = now;
    if (window.recording) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
});
const stopFrames = page => page.evaluate(() => {
  window.recording = false;
  const frames = window.frameLog.slice(1).sort((a, b) => a - b);
  return { frames: frames.length, worstFrameMs: Math.round(frames[frames.length - 1] || 0),
           slowFrames: frames.filter(frame => frame > 50).length };
});
// Wall time of an interaction until `done` holds, with the frames drawn meanwhile.
const measure = async (page, act, done) => {
  await startFrames(page);
  const started = Date.now();
  await act();
  if (done) await page.waitForFunction(done.fn, done.arg, { timeout: 30000 });
  const ms = Date.now() - started;
  return { ms, ...(await stopFrames(page)) };
};

const scale = page => page.evaluate(() => {
  const transform = getComputedStyle(document.querySelector('.vue-flow__transformationpane')).transform;
  return transform === 'none' ? 1 : new DOMMatrix(transform).a;
});
const nodeBox = (page, id) => page.locator(`.vue-flow__node[data-id="${id}"]`).boundingBox();
// A point of the canvas where nothing but the pane is under the pointer.
const emptyPoint = page => page.evaluate(() => {
  const box = document.querySelector('.vue-flow').getBoundingClientRect();
  for (let y = box.top + 30; y < box.bottom - 60; y += 23) {
    for (let x = box.left + 60; x < box.right - 30; x += 29) {
      const element = document.elementFromPoint(x, y);
      if (element?.closest('.vue-flow__pane') && !element.closest('.vue-flow__node, .vue-flow__edge, .vue-flow__panel')) return { x, y };
    }
  }
  return null;
});
// A question node (n1, n6, n11…) inside the left half of the canvas, so the node after it stays in view once zoomed in
// around it: at 200 nodes the fitted view is at the minimum zoom and the first nodes are outside it.
const visibleQuestion = page => page.evaluate(() => {
  const area = document.querySelector('.vue-flow').getBoundingClientRect();
  const centre = { x: area.left + area.width * 0.3, y: area.top + area.height / 2 };
  return [...document.querySelectorAll('.vue-flow__node')]
    .filter(node => /^n\d+$/.test(node.dataset.id) && (Number(node.dataset.id.slice(1)) - 1) % 5 === 0)
    .map(node => ({ id: node.dataset.id, box: node.getBoundingClientRect() }))
    .filter(({ box }) => box.left > area.left + 20 && box.right < area.left + area.width * 0.45 && box.top > area.top + 40
      && box.bottom < area.bottom - 150)
    .sort((a, b) => Math.hypot(a.box.x - centre.x, a.box.y - centre.y) - Math.hypot(b.box.x - centre.x, b.box.y - centre.y))[0]?.id;
});
const fittedScale = async page => {
  await page.waitForFunction(() => {
    const transform = getComputedStyle(document.querySelector('.vue-flow__transformationpane')).transform;
    return transform !== 'none' && new DOMMatrix(transform).a < 0.99;
  }, null, { timeout: 15000 });
  return scale(page);
};
const heap = async page => {
  await page.evaluate(() => window.gc && window.gc());
  return page.evaluate(() => Math.round(performance.memory.usedJSHeapSize / 1048576 * 10) / 10);
};
const login = async (browser, viewport) => {
  const context = await browser.newContext({ viewport });
  await context.addInitScript(INSTRUMENT);
  const page = await context.newPage();
  page.on('console', message => message.type() === 'error' && consoleErrors.push(`${phase}: ${message.text().slice(0, 160)}`));
  page.on('pageerror', error => consoleErrors.push(`${phase}: uncaught ${error.message.slice(0, 160)}`));
  page.on('response', response => response.status() >= 400 && consoleErrors.push(`${phase}: ${response.status()} ${response.url().replace(B, '')}`));
  await page.goto(`${B}/app/login`, { waitUntil: 'networkidle' });
  await page.fill('input[name="email_address"]', 'admin_a@commerce.lynomia.local');
  await page.fill('input[type="password"]', 'Password1!x');
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/app\/accounts\/\d+/, { timeout: 60000 });
  return page;
};
const open = async (page, url, size) => {
  const started = Date.now();
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(n => document.querySelectorAll('.vue-flow__node').length === n
    && document.querySelectorAll('.vue-flow__edge').length > 0, size, { timeout: 60000 });
  return Date.now() - started;
};
const nodesOnCanvas = page => page.evaluate(() => {
  const ids = [...document.querySelectorAll('.vue-flow__node')].map(node => node.dataset.id);
  return { count: ids.length, unique: new Set(ids).size };
});
// DOM changes on the canvas while nobody touches it: a render loop would never stop changing it.
const idleMutations = page => page.evaluate(() => new Promise(resolve => {
  let count = 0;
  const observer = new MutationObserver(records => { count += records.length; });
  observer.observe(document.querySelector('.vue-flow'), { subtree: true, childList: true, attributes: true, characterData: true });
  setTimeout(() => { observer.disconnect(); resolve(count); }, 3000);
}));

const runSize = async (page, base, size, flowId) => {
  const url = `${base}/${flowId}`;
  const loads = [];
  for (let i = 0; i < LOADS; i += 1) loads.push(await open(page, url, size));
  await page.waitForTimeout(500);
  const heapLoaded = await heap(page);
  const r = { nodes: size, initialRenderMs: { first: loads[0], median: median(loads.slice(1)) }, heapAfterLoadMb: heapLoaded,
              fitScale: round(await fittedScale(page)) };

  // Zoom in on a question with the wheel, as a person does, until the nodes are at their real size.
  const q = await visibleQuestion(page);
  const next = `n${Number(q.slice(1)) + 1}`;
  r.nodesUsed = [q, next];
  let steps = 0;
  r.zoom = await measure(page, async () => {
    while ((await scale(page)) < 0.9 && steps < 12) {
      const box = await nodeBox(page, q);
      await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
      await page.mouse.wheel(0, -240);
      await page.waitForTimeout(60);
      steps += 1;
    }
  });
  r.zoom.steps = steps;
  r.zoom.scale = round(await scale(page));

  // Pan: drag the empty canvas and back (each drag starts where only the canvas is under the pointer).
  r.pan = await measure(page, async () => {
    for (const dx of [160, -160]) {
      const point = await emptyPoint(page);
      await page.mouse.move(point.x, point.y);
      await page.mouse.down();
      await page.mouse.move(point.x + dx, point.y + dx / 4, { steps: 20 });
      await page.mouse.up();
    }
  });

  // Select a node: selected, then its settings open.
  const n1 = await nodeBox(page, q);
  const select = await measure(page, () => page.mouse.click(n1.x + 30, n1.y + 12),
    { fn: id => document.querySelector(`.vue-flow__node[data-id="${id}"]`)?.classList.contains('selected'), arg: q });
  r.nodeSelect = select;
  r.openConfigPanel = await measure(page, async () => {},
    { fn: () => !!document.querySelector('[data-test-id="flow-config-panel"] textarea') });
  r.openConfigPanel.ms += select.ms;

  // Edit the node: typed text reaches the node on the canvas.
  const textarea = page.locator('[data-test-id="flow-config-panel"] textarea').first();
  await textarea.click();
  await page.keyboard.press('End');
  r.modifyNode = await measure(page, () => page.keyboard.type(' edited', { delay: 30 }),
    { fn: id => document.querySelector(`.vue-flow__node[data-id="${id}"]`)?.innerText.includes('edited'), arg: q });
  await page.locator('[data-test-id="flow-config-panel"] header button').last().click();
  await page.waitForTimeout(300);

  // Drag a node by its header.
  const n2 = await nodeBox(page, next);
  const n2Before = await page.locator(`.vue-flow__node[data-id="${next}"]`).getAttribute('style');
  r.nodeDrag = await measure(page, async () => {
    await page.mouse.move(n2.x + 40, n2.y + 10);
    await page.mouse.down();
    await page.mouse.move(n2.x + 40, n2.y + 90, { steps: 20 });
    await page.mouse.up();
  }, { fn: ([id, style]) => document.querySelector(`.vue-flow__node[data-id="${id}"]`).getAttribute('style') !== style, arg: [next, n2Before] });

  // Add an edge: the question's "invalid" output to the next node.
  const edgesBefore = await page.locator('.vue-flow__edge').count();
  const source = await page.locator(`.vue-flow__node[data-id="${q}"] .vue-flow__handle.source`).nth(1).boundingBox();
  const target = await page.locator(`.vue-flow__node[data-id="${next}"] .vue-flow__handle.target`).boundingBox();
  r.addEdge = await measure(page, async () => {
    await page.mouse.move(source.x + source.width / 2, source.y + source.height / 2);
    await page.mouse.down();
    await page.mouse.move(target.x + target.width / 2, target.y + target.height / 2, { steps: 12 });
    await page.mouse.up();
  }, { fn: count => document.querySelectorAll('.vue-flow__edge').length === count + 1, arg: edgesBefore });

  // Save the draft: the whole graph sent and validated, the builder back to "saved".
  const saved = page.waitForResponse(response => response.url().includes(`/flows/${flowId}/draft`) && response.request().method() === 'PUT');
  r.save = await measure(page, () => page.click('[data-test-id="flow-save-button"]'),
    { fn: () => !document.querySelector('[data-test-id="flow-status"]')?.innerText.includes('Unsaved') });
  r.save.status = (await saved).status();

  // Stress: zoom and pan back and forth, then memory, re-renders at rest, duplicates.
  for (let i = 0; i < 10; i += 1) {
    const point = await emptyPoint(page);
    await page.mouse.move(point.x, point.y);
    await page.mouse.wheel(0, i % 2 ? -400 : 400);
    await page.mouse.down();
    await page.mouse.move(point.x + (i % 2 ? -120 : 120), point.y, { steps: 8 });
    await page.mouse.up();
  }
  await page.waitForTimeout(500);
  r.heapAfterInteractionsMb = await heap(page);
  r.idleMutations3s = await idleMutations(page);
  r.canvas = await nodesOnCanvas(page);
  const log = await page.evaluate(() => window.perfLog);
  r.longTasks = { count: log.longTasks.length, worstMs: Math.round(Math.max(0, ...log.longTasks)) };
  r.inputDelay = { slowEvents: log.events.length, worstMs: Math.round(Math.max(0, ...log.events)) };
  await page.screenshot({ path: `${out}/canvas-${size}.png` });
  return r;
};

// The 200-node flow in a language and viewport: render, select and settings, pan, and the page width.
const runMatrix = async (browser, base, flowId, name, viewport, locale) => {
  ctl(`locale ${locale}`);
  const page = await login(browser, viewport);
  const r = { initialRenderMs: await open(page, `${base}/${flowId}`, 200) };
  await page.waitForTimeout(500);
  r.rtl = await page.evaluate(() => document.querySelector('[dir="rtl"]') !== null);
  r.canvasLtr = await page.evaluate(() => document.querySelector('.vue-flow').closest('[dir]').getAttribute('dir') === 'ltr');
  r.paletteVisible = await page.locator('[data-test-id="flow-palette-send_message"]').isVisible();
  r.overflowPx = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  const point = await emptyPoint(page);
  r.pan = await measure(page, async () => {
    await page.mouse.move(point.x, point.y);
    await page.mouse.down();
    await page.mouse.move(point.x + 80, point.y + 40, { steps: 15 });
    await page.mouse.up();
  });
  // A node fully inside the canvas, selected: its settings open (over the canvas at phone width).
  const target = await page.evaluate(() => {
    const area = document.querySelector('.vue-flow').getBoundingClientRect();
    const inside = [...document.querySelectorAll('.vue-flow__node')].map(node => node.getBoundingClientRect())
      .find(box => box.left > area.left && box.right < area.right && box.top > area.top && box.bottom < area.bottom);
    return inside && { x: inside.left + inside.width / 2, y: inside.top + 6 };
  });
  r.select = await measure(page, () => page.mouse.click(target.x, target.y),
    { fn: () => !!document.querySelector('[data-test-id="flow-config-panel"]') });
  r.panelWidthPx = await page.evaluate(() => Math.round(document.querySelector('[data-test-id="flow-config-panel"]')?.getBoundingClientRect().width || 0));
  r.canvas = await nodesOnCanvas(page);
  await page.screenshot({ path: `${out}/canvas-200-${name}.png` });
  await page.context().close();
  results.matrix[name] = r;
};

(async () => {
  const setup = ctl('setup');
  const base = `${B}/app/accounts/${setup.account_id}/settings/flows`;
  const flows = Object.fromEntries(SIZES.map(size => [size, ctl(`perf_graph ${size}`)]));
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH,
                                          args: ['--js-flags=--expose-gc', '--enable-precise-memory-info'] });
  const page = await login(browser, { width: 1440, height: 900 });
  currentPage = page;
  for (const size of SIZES) {
    phase = `${size} nodes`;
    results.sizes[size] = { graph: flows[size], ...(await runSize(page, base, size, flows[size].flow_id)) };
    console.log(`${size} nodes: ${JSON.stringify(results.sizes[size])}`);
  }
  await page.context().close();
  // The saved 200-node draft gained an edge; the matrix opens it as it is now.
  for (const [name, viewport, locale] of [['desktop-en', { width: 1440, height: 900 }, 'en'], ['desktop-ar', { width: 1440, height: 900 }, 'ar'],
    ['mobile-en', { width: 390, height: 844 }, 'en'], ['mobile-ar', { width: 390, height: 844 }, 'ar']]) {
    phase = name;
    await runMatrix(browser, base, flows[200].flow_id, name, viewport, locale);
    console.log(`${name}: ${JSON.stringify(results.matrix[name])}`);
  }
  ctl('locale en');
  results.consoleErrors = consoleErrors;
  await browser.close();
  ctl('teardown');
  fs.writeFileSync(`${out}/canvas.json`, JSON.stringify(results, null, 2));
  console.log(`console errors: ${consoleErrors.length}`);
})().catch(async error => {
  console.error(error);
  if (currentPage) await currentPage.screenshot({ path: `${out}/failure.png` }).catch(() => {});
  fs.writeFileSync(`${out}/canvas.json`, JSON.stringify({ ...results, error: error.message }, null, 2));
  process.exit(1);
});
