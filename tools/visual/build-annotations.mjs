// THE SCREENSHOT LIBRARY BUILD.
//
// `docs/screenshots/library.json` is the index of every product screenshot we publish. This turns it
// into the annotated images the documentation and the marketing CMS consume, by running
// `annotate.mjs` once per annotation declared there.
//
//   node tools/visual/build-annotations.mjs
//   node tools/visual/build-annotations.mjs --key conversations/assign-agent
//
// WHY A BUILD AND NOT A ONE-OFF. A source capture is never edited and an annotated output is never
// edited: when a screen is redesigned, the source is re-captured and this regenerates every output
// that used it with its markers intact. An image painted once by hand would have to be redrawn by
// hand, which is how documentation screenshots drift away from the product.
//
// It fails on the first problem instead of skipping it. A missing source, a spec pointing at a
// different capture, or a documentation key the seeder would reject are all setup mistakes that must
// surface here, not as a 404 in production.
import { access, readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const LIBRARY = path.join(ROOT, 'docs/screenshots/library.json');
const ANNOTATE = path.join(ROOT, 'tools/visual/annotate.mjs');
const DOC_MEDIA = 'custom/db/documentation/media/';

// Documentation::MediaResolver::KEY, so a key the seeder would refuse is refused here instead.
const DOC_KEY = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\/[a-z0-9](?:[a-z0-9-]*[a-z0-9])?){1,4}\.(?:png|jpe?g|gif|webp)$/;

const args = process.argv.slice(2);
const only = args.indexOf('--key') === -1 ? null : args[args.indexOf('--key') + 1];

const exists = async p => access(p).then(() => true, () => false);

const run = (file, argv) =>
  new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [file, ...argv], { cwd: ROOT, stdio: ['ignore', 'pipe', 'inherit'] });
    let out = '';
    child.stdout.on('data', d => { out += d; });
    child.on('error', reject);
    child.on('close', code =>
      code === 0 ? resolve(out) : reject(new Error(`annotate.mjs exited ${code}`))
    );
  });

const library = JSON.parse(await readFile(LIBRARY, 'utf8'));
const assets = only ? library.assets.filter(a => a.key === only) : library.assets;

if (only && assets.length === 0) {
  throw new Error(`no asset with key ${only} in docs/screenshots/library.json`);
}

let built = 0;

for (const asset of assets) {
  if (!(await exists(path.join(ROOT, asset.source)))) {
    throw new Error(`${asset.key}: source capture is missing: ${asset.source}`);
  }

  for (const annotation of asset.annotations ?? []) {
    const spec = JSON.parse(await readFile(path.join(ROOT, annotation.spec), 'utf8'));

    // The library declares which genuine capture backs this output. A spec that quietly points
    // somewhere else would publish an image whose provenance the library misstates.
    if (spec.source !== asset.source) {
      throw new Error(
        `${annotation.spec}: annotates ${spec.source} but ${asset.key} is captured from ${asset.source}`
      );
    }

    if (annotation.out.startsWith(DOC_MEDIA)) {
      const key = annotation.out.slice(DOC_MEDIA.length);
      if (!DOC_KEY.test(key)) throw new Error(`${annotation.out}: not a media key the seeder accepts`);
    }

    await run(ANNOTATE, ['--spec', annotation.spec, '--out', annotation.out]);
    console.log(`${asset.key} ${spec.locale} -> ${annotation.out}`);
    built += 1;
  }
}

console.log(`\n${built} annotated image${built === 1 ? '' : 's'} from ${assets.length} capture${assets.length === 1 ? '' : 's'}.`);
if (built) {
  console.log('Documentation outputs are published by: bundle exec rails documentation:content');
}
