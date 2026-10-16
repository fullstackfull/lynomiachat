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

const W = spec.width;
const H = spec.height;
const steps = spec.steps || [];

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
  .shot { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: top ${isRtl ? 'right' : 'left'}; }
  .ring {
    position: absolute; border: 3px solid; z-index: 2; pointer-events: none;
  }
  .arrows { position: absolute; inset: 0; z-index: 3; pointer-events: none; }
  .arrows path { fill: none; stroke-width: 3; stroke-linecap: round;
                 filter: drop-shadow(0 1px 2px rgba(10,23,51,.35)); }
  .marker { position: absolute; z-index: 4; transform: translate(-50%, -50%); display: flex;
            align-items: center; gap: 10px; }
  .dot {
    width: 34px; height: 34px; border-radius: 999px; color: #fff; flex: none;
    display: grid; place-content: center; font-weight: 700; font-size: 17px;
    border: 3px solid rgba(255,255,255,.95);
    box-shadow: 0 2px 10px rgba(10,23,51,.35);
    font-variant-numeric: tabular-nums;
  }
  .label {
    background: ${TOKENS.paper}; color: ${TOKENS.ink};
    border: 1px solid rgba(10,23,51,.10);
    border-${isRtl ? 'right' : 'left'}: 4px solid var(--tone);
    padding: 7px 12px; border-radius: 9px; font-size: 15px; font-weight: 600;
    line-height: 1.35; max-width: 290px; white-space: pre-wrap;
    box-shadow: 0 4px 16px rgba(10,23,51,.18);
  }
  /* The label swaps sides by reordering the flex row, so it never runs off the frame. */
  .label-left { order: -1; }
</style></head>
<body>
  <div class="stage">
    <img class="shot" src="${sourceUrl}" alt="">
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
