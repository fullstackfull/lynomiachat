/**
 * Orchestrator ruling R3 point 2 as an executable gate.
 *
 * The ruling: adoption of the installed ProseMirror editor for `content` is gated on a parse-and-serialize of the
 * corpus coming back byte-identical, and until that passes the editor does not touch `content`.
 *
 * MEASURED, 2026-10-13, over all 126 files of custom/db/documentation: 0 byte-identical, 126 changed, 0 parse
 * errors. So the gate is CLOSED and the editor edits Markdown source instead (ArticleEditor.vue). This file
 * pins both halves of that measurement -- the sampled corpus files still differ, and each defect class still
 * behaves exactly as measured -- so that fixing the serializer turns these tests red and forces the adoption
 * decision to be retaken by a human rather than drifting.
 *
 * Sampled rather than exhaustive: P2-WORKSTREAM-OWNERSHIP.md section C forbids running the whole corpus through a
 * suite on a 4-CPU box, and one file per construct answers the same question.
 */
import fs from 'node:fs';
import path from 'node:path';
import { roundTrip } from './markdownSource';

// vitest runs with the repository root as cwd (vitest.config.ts), so this is stable from any spec.
const CORPUS = path.resolve(process.cwd(), 'custom/db/documentation');
const FRONT_MATTER = /^---\s*\n[\s\S]*?\n---\s*\n/;

// The body as Documentation::ContentSeeder stores it: front matter removed, then stripped
// (custom/app/services/documentation/content_seeder.rb:126-131).
const bodyOf = file =>
  fs.readFileSync(file, 'utf-8').replace(FRONT_MATTER, '').trim();

const markdownUnder = dir =>
  fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return markdownUnder(full);
    return entry.name.endsWith('.md') ? [full] : [];
  });

const corpusFiles = () => markdownUnder(CORPUS).sort();

// Every construct the corpus uses, counted: table 108 files, bullet 126, ordered 75, heading 126, link 116,
// inline code 70, strong 126, blockquote 8, fenced code 2. No images (R2-MEDIA-INTERFACE.md 0.1) and no thematic
// breaks. `rtl` is its own row because Arabic is half the corpus and the serializer is not direction-aware.
const CONSTRUCTS = {
  table: /^\|/m,
  fence: /^```/m,
  bullet: /^\s*[-*] /m,
  ordered: /^\s*\d+\. /m,
  blockquote: /^> /m,
  heading: /^#{1,6} /m,
  link: /\[[^\]]+\]\([^)]+\)/,
  inlineCode: /`[^`]+`/,
  strong: /\*\*/,
  rtl: /[؀-ۿ]/,
};

// One file per construct: the first in sorted order that uses it. Deterministic, and it names real files so a
// failure points at something a human can open.
const sample = () => {
  const files = corpusFiles();
  return new Map(
    Object.entries(CONSTRUCTS)
      .map(([construct, pattern]) => [
        construct,
        files.find(f => pattern.test(bodyOf(f))),
      ])
      .filter(([, file]) => file)
  );
};

describe('the ProseMirror round-trip gate (ruling R3 point 2)', () => {
  const picked = sample();

  it('samples every construct the corpus uses', () => {
    expect([...picked.keys()].sort()).toEqual(Object.keys(CONSTRUCTS).sort());
  });

  describe.each([...picked.entries()])('%s', (construct, file) => {
    it(`still does NOT round-trip ${path.relative(CORPUS, file)}, so the gate stays closed`, () => {
      const source = bodyOf(file);
      expect(roundTrip(source)).not.toEqual(source);
    });
  });

  // The five classes, each as the minimal input that exhibits it. Measured outputs, not predictions.
  describe('the measured defect classes', () => {
    it('turns a soft line wrap into a hard break (2,315 of these across the corpus)', () => {
      expect(roundTrip('a line that wraps\nonto a second line')).toEqual(
        'a line that wraps\\\nonto a second line'
      );
    });

    it('rewrites the bullet marker and loosens a tight list', () => {
      expect(roundTrip('- one\n- two\n- three')).toEqual(
        '* one\n\n* two\n\n* three'
      );
    });

    it('loosens a tight ordered list', () => {
      expect(roundTrip('1. one\n2. two')).toEqual('1. one\n\n2. two');
    });

    it('repads table cells and widens the delimiter row', () => {
      expect(roundTrip('| a | b |\n|---|---|\n| 1 | 2 |')).toEqual(
        '| a   | b   |\n| --- | --- |\n| 1   | 2   |\n'
      );
    });

    // The one class that loses meaning rather than formatting: the language is gone, so the renderer emits
    // `<pre><code>` with no `class="language-..."` -- and that attribute is a security-reviewed field
    // (lib/markdown_renderer_fence_info_escaping.rb).
    it('DROPS a fenced code block info string', () => {
      expect(roundTrip('```json\n{"a":1}\n```')).toEqual('```\n{"a":1}\n```');
    });
  });

  // The editor writes exactly one image string (markdownCommands.image), and it survives the pair unchanged --
  // but ONLY for an alt containing none of `[`, `]` or a backslash. `Documentation::MediaUpload#markdown_for`
  // (custom/app/services/documentation/media_upload.rb:143) escapes those, and prosemirror-markdown reads an
  // image alt from the first inline token only, so everything from the first escape onward is LOST. That class
  // is pinned both ways in markdownSource.spec.js; this example is the unescaped case, which is the one a
  // future WYSIWYG adoption would find already safe.
  it('round-trips the one image form the editor writes, when the alt needs no escaping', () => {
    const source =
      '![Step two: paste the token](media:whatsapp/connect-number/step-2.png)';
    expect(roundTrip(source)).toEqual(source);
  });

  // Constructs that are already clean, so a regression in them is visible.
  describe.each([
    ['an ATX heading', '## A heading'],
    ['inline code', 'use `rails db:seed` now'],
    ['a link', 'see [the page](work-in-the-inbox)'],
    ['strong and emphasis', '**bold** and *em*'],
    ['a blockquote', '> quoted line'],
  ])('already round-trips: %s', (_name, source) => {
    it('unchanged', () => {
      expect(roundTrip(source)).toEqual(source);
    });
  });
});
