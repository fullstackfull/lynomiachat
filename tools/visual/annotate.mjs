// THE ANNOTATION LAYER.
//
// Takes a GENUINE screenshot and draws product-education annotations over it: numbered markers,
// curved arrows, highlight rings, a dim outside the region that matters, and cropped details. The
// source PNG is never modified — the annotated image is written somewhere else — so the unannotated
// capture stays the source of truth and can be re-captured when the UI changes.
//
//   node tools/visual/annotate.mjs --spec docs/screenshots/specs/inbox-tour.en.json
//   node tools/visual/annotate.mjs --spec <file> --out <path.png>
//
// WHY HTML AND NOT A DRAWING LIBRARY. The annotations carry words, in two languages, one of which is
// Arabic. Laying that out means a real text engine with the real fonts and real bidi — which is a
// browser. So the layer is an HTML document with the screenshot as its background, rendered by the
// same Chromium that took the screenshot, and photographed. It also means the annotation styling is
// CSS: the same tokens the product uses, changeable in one place.
//
// ACCESSIBILITY IS NOT IN THE IMAGE. Every marker's text lives in the spec as data. The spec is what
// the documentation and marketing templates render as a real ordered list beside the picture, so the
// instructions exist as selectable, translatable, screen-readable text and the image is the
// illustration rather than the content. `--emit-text` prints that list for embedding.
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';

const { chromium } = createRequire(import.meta.url)('playwright');

const args = process.argv.slice(2);
const arg = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};

const specPath = arg('spec');
if (!specPath) throw new Error('--spec <file.json> is required');

const spec = JSON.parse(await readFile(specPath, 'utf8'));
const specSource = spec.source;

// ── The Lynomia annotation palette ────────────────────────────────────────────────────────────────
// Indigo is the product's action colour, so a marker reads as "this is the thing to act on". Magenta
// is reserved for the one result marker a sequence ends on, because a different job needs a different
// colour, and this is the only place the redesign spends magenta on the dashboard's imagery.
const TOKENS = {
  indigo: '#5B5BF0',
  indigoDeep: '#4038C9',
  magenta: '#D6246E',
  ink: '#0A1733',
  paper: '#FFFFFF',
  dim: 'rgba(10, 23, 51, 0.55)',
};

const dir = spec.dir || (spec.locale === 'ar' ? 'rtl' : 'ltr');
const isRtl = dir === 'rtl';

/** Percentages, so a spec survives the screenshot being re-captured at another scale. */
const pc = v => `${v}%`;

function markerHtml(step, index) {
  const n = step.n ?? index + 1;
  const tone = step.tone === 'result' ? TOKENS.magenta : TOKENS.indigo;
  // The label sits on the side with room for it. `side` is explicit in the spec when the automatic
  // choice would run the label off the edge.
  const side = step.side || (step.x > 55 ? 'start' : 'end');
  const labelOnLeft = side === 'start' ? !isRtl : isRtl;

  // Clamped away from the frame edge: a marker at 2% puts half its dot and all of its label outside
  // the picture, and the label is the part that carries the meaning.
  const x = Math.min(94, Math.max(6, step.x));
  const y = Math.min(96, Math.max(4, step.y));

  // The DOT is what sits on (x, y) -- it is the thing pointing at the control -- and the label hangs off it.
  // Centring the whole row on the point instead pushed the dot sideways by half the label's width, which put
  // every marker next to the control rather than on it.
  return `
  <div class="marker" style="left:${pc(x)};top:${pc(y)}">
    <div class="dot" style="background:${tone}">${n}</div>
    ${step.label ? `<div class="label ${labelOnLeft ? 'label-left' : 'label-right'}" style="--tone:${tone}">${escapeHtml(step.label)}</div>` : ''}
  </div>`;
}

function highlightHtml(step) {
  const h = step.highlight;
  if (!h) return '';
  const tone = step.tone === 'result' ? TOKENS.magenta : TOKENS.indigo;
  // `box-shadow` with a huge spread is what dims everything OUTSIDE the ring, in one element, with
  // the ring's own border-radius respected. A full-screen overlay with a cut-out needs a mask and
  // does not round.
  const dimming = step.dim ? `box-shadow: 0 0 0 9999px ${TOKENS.dim};` : '';
  return `
  <div class="ring" style="left:${pc(h.x)};top:${pc(h.y)};width:${pc(h.w)};height:${pc(h.h)};
       border-color:${tone}; border-radius:${h.radius ?? 10}px; ${dimming}"></div>`;
}

// COVERING SOMETHING THAT MUST NOT BE PUBLISHED.
//
// A screenshot of a real screen sometimes contains a real credential -- the website token in the widget's
// install snippet is the clearest case: it is on the screen, it belongs in the picture's composition, and
// it must not go into a published figure. The alternative to this is editing the screenshot, which is the
// one thing this pipeline does not do, or faking the screen, which is worse.
//
// So a redaction is drawn as part of the ANNOTATION LAYER, over the capture, with the source left
// untouched: a solid block in the ink colour carrying the word that says what was covered. It is visibly a
// redaction rather than a blur, because a blurred credential still looks like a credential a reader should
// go looking for.
//
// In SOURCE pixels, like the crop, because the thing being covered is at a place on the screen rather than
// at a place in the composition.
function redactionHtml(redaction, frame) {
  const x = ((redaction.x - frame.x) / frame.w) * 100;
  const y = ((redaction.y - frame.y) / frame.h) * 100;
  const w = (redaction.w / frame.w) * 100;
  const h = (redaction.h / frame.h) * 100;
  return `
  <div class="redaction" style="left:${pc(x)};top:${pc(y)};width:${pc(w)};height:${pc(h)}">
    ${redaction.label ? escapeHtml(redaction.label) : ''}
  </div>`;
}

function arrowSvg(steps, w, h) {
  const paths = steps
    .filter(s => s.arrow)
    .map(s => {
      const tone = s.tone === 'result' ? TOKENS.magenta : TOKENS.indigo;
      const x1 = (s.x / 100) * w;
      const y1 = (s.y / 100) * h;
      const x2 = (s.arrow.toX / 100) * w;
      const y2 = (s.arrow.toY / 100) * h;
      // A quadratic control point pushed perpendicular to the line gives a calm arc rather than a
      // straight technical pointer. The sign flips under RTL so arcs bow the same way relative to
      // the reading direction.
      const mx = (x1 + x2) / 2;
      const my = (y1 + y2) / 2;
      const bow = (s.arrow.bow ?? 18) * (isRtl ? -1 : 1);
      const dx = x2 - x1;
      const dy = y2 - y1;
      const len = Math.hypot(dx, dy) || 1;
      const cx = mx + (-dy / len) * bow;
      const cy = my + (dx / len) * bow;
      return `<path d="M ${x1} ${y1} Q ${cx} ${cy} ${x2} ${y2}" stroke="${tone}"
                    marker-end="url(#head-${s.tone === 'result' ? 'result' : 'step'})" />`;
    })
    .join('\n');

  return `
  <svg class="arrows" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}" aria-hidden="true">
    <defs>
      ${['step', 'result'].map(k => `
      <marker id="head-${k}" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
        <path d="M 0 0 L 10 5 L 0 10 z" fill="${k === 'result' ? TOKENS.magenta : TOKENS.indigo}"/>
      </marker>`).join('')}
    </defs>
    ${paths}
  </svg>`;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]
  );
}

// ── Resolving a spec against measured geometry ────────────────────────────────────────────────────
//
// `capture.mjs` writes `<shot>.boxes.json` beside any capture whose page declared `measure`, holding the
// bounding box of each named control in the shot's own pixels. A spec that carries `"box": "status-filter"`
// is resolved against it here, which is why these files are short and why none of their numbers were
// eyeballed off a PNG. A spec with no `box` anywhere never reads the file and keeps working exactly as it
// did -- the four figures written before this existed are unchanged by it.
const boxesPath =
  spec.boxes || specSource.replace(/\.png$/, '.boxes.json');

async function loadBoxes() {
  try {
    return JSON.parse(await readFile(boxesPath, 'utf8')).boxes || {};
  } catch {
    return null;
  }
}

const needsBoxes =
  (spec.crop && spec.crop.around) || (spec.steps || []).some(step => step.box);
const boxes = needsBoxes ? await loadBoxes() : null;
if (needsBoxes && !boxes) {
  throw new Error(
    `${specPath} names measured boxes but ${boxesPath} is not there. Re-capture the source with a ` +
      '`measure` block on its page in tools/visual/capture.mjs.'
  );
}

function boxOf(name) {
  const box = boxes[name];
  if (!box) {
    throw new Error(`${specPath}: no measured box named ${JSON.stringify(name)} in ${boxesPath}`);
  }
  return box;
}

/** The union of several measured boxes, grown by `pad` and clamped to the source, in source pixels. */
function around(names, pad = 24) {
  const all = names.map(boxOf);
  const left = Math.min(...all.map(b => b.x)) - pad;
  const top = Math.min(...all.map(b => b.y)) - pad;
  const right = Math.max(...all.map(b => b.x + b.width)) + pad;
  const bottom = Math.max(...all.map(b => b.y + b.height)) + pad;
  return {
    x: Math.max(0, Math.round(left)),
    y: Math.max(0, Math.round(top)),
    w: Math.min(spec.width, Math.round(right)) - Math.max(0, Math.round(left)),
    h: Math.min(spec.height, Math.round(bottom)) - Math.max(0, Math.round(top)),
  };
}


// A step's `box` becomes the ring it already understood, plus a default position for its marker: the dot
// sits just outside the control on the reading-end side, which is where a hand would point at it. `at`
// overrides that for a control at the frame's edge.
function resolveStep(step, frame) {
  if (!step.box) return step;

  const box = boxOf(step.box);
  const pad = step.pad ?? 6;
  const x = ((box.x - pad - frame.x) / frame.w) * 100;
  const y = ((box.y - pad - frame.y) / frame.h) * 100;
  const w = ((box.width + pad * 2) / frame.w) * 100;
  const h = ((box.height + pad * 2) / frame.h) * 100;

  const at = step.at || 'end';
  const anchors = {
    start: { x: isRtl ? x + w : x, y: y + h / 2 },
    end: { x: isRtl ? x : x + w, y: y + h / 2 },
    top: { x: x + w / 2, y },
    bottom: { x: x + w / 2, y: y + h },
    center: { x: x + w / 2, y: y + h / 2 },
  };
  const anchor = anchors[at] || anchors.end;

  return {
    ...step,
    x: step.x ?? anchor.x,
    y: step.y ?? anchor.y,
    highlight: step.highlight ?? { x, y, w, h, radius: step.radius ?? 10 },
  };
}

// A CROP IS NOT AN EDIT. The source stays the whole screen, because that is what was photographed; the crop
// lives here so the published figure can be the part a reader needs. Without it a 1440-wide screenshot is
// 358px on a phone and its annotations are unreadable, which is the usual reason documentation screenshots
// are useless on the device most people read them on. In SOURCE pixels; the markers and rings are then
// percentages of the CROPPED frame.
const crop = spec.crop?.around ? around(spec.crop.around, spec.crop.pad) : spec.crop;
const W = crop ? crop.w : spec.width;
const H = crop ? crop.h : spec.height;
const frame = crop ? { ...crop } : { x: 0, y: 0, w: spec.width, h: spec.height };
const steps = (spec.steps || []).map(step => resolveStep(step, frame));

// The screenshot is referenced by path so nothing is re-encoded on the way in: the pixels under the
// annotations are the captured pixels. The layer is written to a real file beside nothing in
// particular and OPENED as file://, rather than pushed in with setContent -- a page served from
// about:blank may not load a file:// subresource, so setContent photographs a blank stage.
const sourceUrl = pathToFileURL(path.resolve(spec.source)).href;

const html = `<!doctype html>
<html dir="${dir}" lang="${spec.locale || 'en'}">
<head><meta charset="utf-8">
<style>
  @font-face { font-family: 'LynSans'; src: local('Inter'), local('DejaVu Sans'); }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; background: transparent; }
  .stage {
    position: relative; width: ${W}px; height: ${H}px; overflow: hidden;
    font-family: 'Inter', 'IBM Plex Sans Arabic', 'Noto Naskh Arabic', system-ui, sans-serif;
  }
  .shot { position: absolute; left: ${crop ? -crop.x : 0}px; top: ${crop ? -crop.y : 0}px;
          width: ${spec.width}px; height: ${spec.height}px; max-width: none; }
  .ring {
    position: absolute; border: 3px solid; z-index: 2; pointer-events: none;
  }
  .redaction {
    position: absolute; z-index: 5; background: ${TOKENS.ink}; color: ${TOKENS.paper};
    border-radius: 4px; display: grid; place-content: center;
    font-size: 12px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase;
    overflow: hidden; white-space: nowrap;
  }
  .arrows { position: absolute; inset: 0; z-index: 3; pointer-events: none; }
  .arrows path { fill: none; stroke-width: 3; stroke-linecap: round;
                 filter: drop-shadow(0 1px 2px rgba(10,23,51,.35)); }
  /* A zero-size anchor at the point itself: the dot centres on it and the label hangs to one side, so the
     label's width can never move the dot off the control it is pointing at. */
  .marker { position: absolute; z-index: 4; width: 0; height: 0; }
  .dot {
    position: absolute; transform: translate(-50%, -50%);
    width: 34px; height: 34px; border-radius: 999px; color: #fff;
    display: grid; place-content: center; font-weight: 700; font-size: 17px;
    border: 3px solid rgba(255,255,255,.95);
    box-shadow: 0 2px 10px rgba(10,23,51,.35);
    font-variant-numeric: tabular-nums;
  }
  .label {
    position: absolute; top: 0; transform: translateY(-50%);
    background: ${TOKENS.paper}; color: ${TOKENS.ink};
    border: 1px solid rgba(10,23,51,.10);
    border-${isRtl ? 'right' : 'left'}: 4px solid var(--tone);
    padding: 7px 12px; border-radius: 9px; font-size: 15px; font-weight: 600;
    line-height: 1.35; width: max-content; max-width: 290px; white-space: pre-wrap;
    box-shadow: 0 4px 16px rgba(10,23,51,.18);
  }
  /* 27px clears the dot's 17px radius plus a 10px gap, whichever side the label is on. */
  .label-left { right: 27px; }
  .label-right { left: 27px; }
</style></head>
<body>
  <div class="stage">
    <img class="shot" src="${sourceUrl}" alt="">
    ${(spec.redact || []).map(r => redactionHtml(r, frame)).join('\n')}
    ${steps.map(highlightHtml).join('\n')}
    ${arrowSvg(steps, W, H)}
    ${steps.map(markerHtml).join('\n')}
  </div>
</body></html>`;

const outPath = arg('out', spec.out);
if (!outPath) throw new Error('no output path: pass --out or set "out" in the spec');
await mkdir(path.dirname(outPath), { recursive: true });

const layerFile = path.join(
  await mkdtemp(path.join(tmpdir(), 'lyn-annotate-')),
  'layer.html'
);
await writeFile(layerFile, html, 'utf8');

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(layerFile).href, { waitUntil: 'load' });
// The background image is a local file decoded by the real codec; give it a beat to land before the
// shutter, or the annotations are photographed over a blank stage.
await page.waitForFunction(() => {
  const img = document.querySelector('img.shot');
  return img && img.complete && img.naturalWidth > 0;
}, { timeout: 15000 });
await page.locator('.stage').screenshot({ path: outPath });
await browser.close();

console.log(outPath);

if (args.includes('--emit-text')) {
  const list = steps.map((s, i) => `${s.n ?? i + 1}. ${s.label ?? ''}`).join('\n');
  console.log('\n--- accessible text (render this beside the image, not inside it) ---');
  console.log(list);
}
