// CROPPING A SOURCE CAPTURE INTO A FIGURE.
//
// WHY THIS EXISTS. `capture.mjs` photographs whole screens at 1440x900, which is the right thing for a
// source: it is the screen, entire, and every later use is a decision made from it. But a whole screen is
// almost never the right thing to PUBLISH. Dropped into half a 72rem measure it renders about 520px wide --
// 36% of life size -- and every label in it turns to grey mush. The page then carries a picture of the
// product that proves nothing about the product, which is the one failure a screenshot cannot afford.
//
// So a figure is a crop: the part of the screen the sentence beside it is about, published near enough to
// life size to read. The source stays untouched, under `docs/screenshots/sources/`, and the crop is written
// to `docs/screenshots/figures/` -- which is the separation `docs/screenshots/README.md` already draws
// between what the camera produced and what the page shows.
//
//   node tools/visual/crop.mjs                      # every figure in the manifest
//   node tools/visual/crop.mjs --key home/inbox     # one
//   node tools/visual/crop.mjs --check              # write nothing; fail if any figure is missing or stale
//
// `--check` is what makes this safe to depend on: a figure whose source has been recaptured, or whose crop
// box has been edited, is out of date, and a run that silently published the old one would be publishing a
// picture of a screen that no longer exists.
//
// NO IMAGE LIBRARY. The crop is done by the browser that took the capture in the first place: the source is
// loaded at natural size in a blank page and `clip` is screenshotted out of it. That is one fewer native
// dependency to install in CI, and the pixels come back identical because nothing is resampled.

import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile, stat } from 'node:fs/promises';
import path from 'node:path';

const { chromium } = createRequire(import.meta.url)('playwright');

const ROOT = path.resolve(import.meta.dirname, '../..');
const MANIFEST = path.join(ROOT, 'docs/screenshots/figures.json');

const args = process.argv.slice(2);
const arg = name => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? undefined : args[i + 1];
};
const only = arg('key');
const checkOnly = args.includes('--check');

const manifest = JSON.parse(await readFile(MANIFEST, 'utf8'));
const figures = manifest.figures.filter(figure => !only || figure.key === only);
if (!figures.length) throw new Error(`no figure matches --key ${only}`);

// A FIGURE IS STALE IF ITS SOURCE IS NEWER THAN IT. Modification time is enough here and a content hash is
// not worth the bookkeeping: these files are produced by this script from a file produced by `capture.mjs`,
// and both are committed, so a source that moved after its figure did is exactly the case to catch.
async function state(figure) {
  const source = path.join(ROOT, figure.source);
  const out = path.join(ROOT, figure.out);
  const sourceStat = await stat(source).catch(() => null);
  if (!sourceStat) return { status: 'source-missing' };

  const outStat = await stat(out).catch(() => null);
  if (!outStat) return { status: 'missing' };
  if (outStat.mtimeMs < sourceStat.mtimeMs) return { status: 'stale' };
  return { status: 'current' };
}

const problems = [];
let written = 0;

if (checkOnly) {
  for (const figure of figures) {
    const { status } = await state(figure);
    if (status !== 'current') problems.push(`${figure.key}: ${status}`);
  }
} else {
  const browser = await chromium.launch();
  // One context at a device scale of 1: the sources are 1x captures and a 2x context would double every
  // figure's pixels without adding any detail that is in the source.
  const context = await browser.newContext({ deviceScaleFactor: 1 });
  const page = await context.newPage();

  for (const figure of figures) {
    const source = path.join(ROOT, figure.source);
    if (!(await stat(source).catch(() => null))) {
      problems.push(`${figure.key}: source-missing (${figure.source})`);
      continue;
    }

    const out = path.join(ROOT, figure.out);
    await mkdir(path.dirname(out), { recursive: true });

    // The image is laid out at its natural size against nothing, so the clip box is in the source's own
    // pixels -- which is what the crop in the manifest is written in, and what a reader measures off the
    // source in an image viewer.
    //
    // A DATA URL, NOT `file://`. `setContent` leaves the page on `about:blank`, and Chromium refuses a
    // `file://` subresource from any other origin -- the image never loads and the wait for its natural
    // width times out after thirty seconds with nothing to say about why.
    const bytes = await readFile(source);
    await page.setContent(
      `<body style="margin:0"><img id="s" src="data:image/png;base64,${bytes.toString('base64')}" style="display:block"></body>`
    );
    await page.waitForFunction(() => {
      const img = document.getElementById('s');
      return img && img.complete && img.naturalWidth > 0;
    });
    const natural = await page.evaluate(() => {
      const img = document.getElementById('s');
      return { width: img.naturalWidth, height: img.naturalHeight };
    });
    await page.setViewportSize(natural);

    const { x, y, width, height } = figure.crop;
    if (x + width > natural.width || y + height > natural.height) {
      problems.push(
        `${figure.key}: crop ${x},${y} ${width}x${height} falls outside the ${natural.width}x${natural.height} source`
      );
      continue;
    }

    await page.screenshot({ path: out, clip: { x, y, width, height } });
    written += 1;
    process.stdout.write(`${figure.out}  ${width}x${height} from ${figure.source}\n`);
  }

  await browser.close();
}

// The manifest is also the record of why each crop is the shape it is, so a regenerated figure is reviewable
// as a decision rather than as a binary that changed.
if (!checkOnly) {
  await writeFile(
    path.join(ROOT, 'docs/screenshots/figures/README.md'),
    [
      '<!-- GENERATED by tools/visual/crop.mjs. Do not edit: edit docs/screenshots/figures.json. -->',
      '',
      '# Figures',
      '',
      'Crops of the captures in `../sources/`, published on the marketing site and in the documentation.',
      'A figure is a crop because a whole 1440px screen rendered into half a page measure is unreadable;',
      'each one below says which part of which screen it is, and why that part.',
      '',
      ...manifest.figures.flatMap(f => [
        `## \`${f.key}\``,
        '',
        `- **file** \`${f.out}\``,
        `- **from** \`${f.source}\` at ${f.crop.x},${f.crop.y}, ${f.crop.width}x${f.crop.height}`,
        `- **why** ${f.why}`,
        '',
      ]),
    ].join('\n')
  );
}

console.log(checkOnly ? `checked ${figures.length} figures` : `wrote ${written} figures`);
if (problems.length) {
  problems.forEach(problem => console.error(`  ${problem}`));
  process.exit(1);
}
