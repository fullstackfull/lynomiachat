/**
 * markdownSource.js is the editor's only crossing between Markdown source and the installed ProseMirror document
 * model, so what it guarantees is what ruling R3 point 2 is measured against: `corpusRoundTrip.spec.js` answers
 * "does the corpus survive a parse-and-serialize" THROUGH this module, and the answer is only as trustworthy as
 * the three functions underneath it.
 *
 * So this file tests the module itself rather than the corpus. Deliberately NOT repeated here: the five measured
 * defect classes and the per-construct corpus samples, which are `corpusRoundTrip.spec.js`'s subject. What is
 * here is the module's own contract -- the shape `parseMarkdown` produces, the string `serializeDoc` writes from a
 * document nothing parsed, and the round-trip properties that file does not state: stability under a second pass,
 * and the two inputs where the pair loses or moves content that the corpus does not currently contain but the
 * operator upload path produces today.
 */
import { fullSchema } from '@chatwoot/prosemirror-schema';
import { parseMarkdown, serializeDoc, roundTrip } from './markdownSource';

// The exact string Documentation::MediaUpload#create! returns for an upload (custom/app/services/documentation/
// media_upload.rb:139-145) -- the only image form the editor ever inserts, and an operator key rather than a
// seeded one, because `uploads/` is the namespace this path allocates in (R2-MEDIA-INTERFACE.md section 9.1).
const UPLOADED = '![Step two](media:uploads/8f3a1c2b5d7e9a04-step-two.png)';

const typesOf = doc => doc.content.content.map(node => node.type.name);

describe('parseMarkdown', () => {
  it('returns a document in the schema the serializer writes back', () => {
    const doc = parseMarkdown('# Title');

    expect(doc.type.name).toBe('doc');
    expect(doc.type.schema).toBe(fullSchema);
  });

  it('models the source as block nodes, not as text', () => {
    const doc = parseMarkdown('# Title\n\nsome prose');

    expect(typesOf(doc)).toEqual(['heading', 'paragraph']);
    expect(doc.firstChild.attrs.level).toBe(1);
  });

  // The property the whole media grammar rests on: a `media:` key is NOT a URL the parser may normalise. If it
  // ever arrived percent-encoded, lowercased differently or stripped of its scheme, the resolver would answer nil
  // and the renderer would emit an unresolved-key comment instead of an image.
  it('keeps a media: key and its alt exactly as written', () => {
    const image = parseMarkdown(UPLOADED).firstChild.firstChild;

    expect(image.type.name).toBe('image');
    expect(image.attrs.src).toBe('media:uploads/8f3a1c2b5d7e9a04-step-two.png');
    expect(image.attrs.alt).toBe('Step two');
  });

  // isolateImagesInDoc, which the live editor also applies: an image never shares a paragraph with prose.
  it('isolates an inline image into a node of its own', () => {
    const doc = parseMarkdown('before ![Alt](media:a/b.png) after');

    expect(typesOf(doc)).toEqual(['paragraph', 'paragraph', 'paragraph']);
    expect(doc.child(1).childCount).toBe(1);
    expect(doc.child(1).firstChild.type.name).toBe('image');
  });

  // The caller strips front matter before handing the body over (corpusRoundTrip.spec.js does, and
  // Documentation::ContentSeeder does the same thing server-side). This is what happens if one forgets: the `---`
  // fence reads as a thematic break plus a setext heading, so the metadata is published as prose rather than
  // failing visibly.
  it('does not understand front matter, and mangles it rather than refusing it', () => {
    expect(roundTrip('---\ntitle: T\n---\n\nbody')).toBe(
      '---\n\n## title: T\n\nbody'
    );
  });
});

describe('serializeDoc', () => {
  // No parse involved: a document assembled the way an editing session assembles one still has to come out as the
  // single accepted image form (R2-MEDIA-INTERFACE.md section 1.1), because that is what gets saved.
  it('writes the accepted image form from a document nothing parsed', () => {
    const { doc, paragraph, image } = fullSchema.nodes;
    const built = doc.create(null, [
      paragraph.create(null, [
        image.create({
          src: 'media:uploads/abcdef0123456789-hand-built.png',
          alt: 'Hand built alt',
          title: null,
        }),
      ]),
    ]);

    expect(serializeDoc(built)).toBe(
      '![Hand built alt](media:uploads/abcdef0123456789-hand-built.png)'
    );
  });

  it('is the half roundTrip composes, not a second code path', () => {
    ['# Title', UPLOADED, '| a | b |\n|---|---|\n| 1 | 2 |'].forEach(source => {
      expect(roundTrip(source)).toBe(serializeDoc(parseMarkdown(source)));
    });
  });
});

describe('roundTrip', () => {
  it('leaves an empty or blank source empty, so a new article gains no bytes', () => {
    expect(roundTrip('')).toBe('');
    expect(roundTrip('   \n  ')).toBe('');
  });

  it('carries the operator upload key byte for byte', () => {
    expect(roundTrip(UPLOADED)).toBe(UPLOADED);
  });

  // The editor's table sizing convention is an HTML comment the serializer has to re-emit, because
  // CustomMarkdownRenderer#html reads it back to size the published table (lib/custom_markdown_renderer.rb:37-42).
  it('keeps the colwidths marker a resized table is sized by', () => {
    expect(
      roundTrip('<!--cw-colwidths:120,80-->\n| a | b |\n|---|---|\n| 1 | 2 |')
    ).toBe(
      '<!--cw-colwidths:120,80-->\n| a   | b   |\n| --- | --- |\n| 1   | 2   |\n'
    );
  });

  // Reference style is not an accepted form (R2-MEDIA-INTERFACE.md section 1.1). The pair does not reject it -- it
  // rewrites it into the accepted one, which is worth knowing because it means a reference-style key in a corpus
  // file would change shape rather than be reported.
  it('rewrites a reference-style image into the one inline form', () => {
    expect(roundTrip('![alt][ref]\n\n[ref]: media:a/b.png')).toBe(
      '![alt](media:a/b.png)'
    );
  });

  // A bare URL is plain text in a published article: `render_article` passes only [:table], so :autolink is off
  // (P2-WORKSTREAM-OWNERSHIP.md G11). The pair linkifies it and serializes an autolink, which core CommonMark DOES
  // render as a link -- so this round trip changes what the page shows, not just how the source looks.
  it('turns a bare URL into an autolink, which changes the published output', () => {
    expect(roundTrip('see https://example.com/docs now')).toBe(
      'see <https://example.com/docs> now'
    );
  });

  // MEASURED DEFECT, and it is the one that touches the upload path: the alt the SERVER composes does not survive.
  // `markdown_for` backslash-escapes `[`, `]` and `\` in the alt (media_upload.rb:143) because CommonMark needs it
  // -- and prosemirror-markdown's image spec reads the alt from the first inline token only, so everything from
  // the first escape onwards is dropped. The unescaped form parses whole and comes back escaped, which is the
  // asymmetry: the pair can produce the server's string but cannot read it back.
  //
  // Not a live defect, because ruling R3's gate is closed and the editor edits Markdown source, which never goes
  // through this pair. It is a SIXTH defect class for the day that gate is re-opened, and it is why
  // corpusRoundTrip.spec.js's "round-trips the one image form the editor writes" is narrower than it reads -- an
  // alt with no bracket in it is the only one that holds.
  it('DROPS the rest of an alt after a backslash escape', () => {
    const fromServer =
      '![Step 2 \\[see note\\]](media:uploads/8f3a1c2b5d7e9a04-step-two.png)';

    expect(roundTrip(fromServer)).toBe(
      '![Step 2 ](media:uploads/8f3a1c2b5d7e9a04-step-two.png)'
    );
  });

  it('escapes a bracket in an alt it read unescaped, which is the other half of that', () => {
    expect(roundTrip('![Step 2 [see note]](media:a/b.png)')).toBe(
      '![Step 2 \\[see note\\]](media:a/b.png)'
    );
  });

  // Stability matters on its own: a WYSIWYG save that changes the bytes is a documented loss, but one that keeps
  // changing them on every save is an endless diff. Every class corpusRoundTrip.spec.js measures settles after one
  // pass...
  describe.each([
    ['a soft line wrap', 'a line that wraps\nonto a second line'],
    ['a tight bullet list', '- one\n- two\n- three'],
    ['a tight ordered list', '1. one\n2. two'],
    ['a table', '| a | b |\n|---|---|\n| 1 | 2 |'],
    ['a fenced block', '```json\n{"a":1}\n```'],
    ['the uploaded image form', UPLOADED],
    ['a heading', '## A heading'],
  ])('settles after one pass: %s', (_name, source) => {
    it('is unchanged by a second round trip', () => {
      const once = roundTrip(source);

      expect(roundTrip(once)).toBe(once);
    });
  });

  // ...except this one. Isolating an inline image leaves the prose's original spaces behind ("before " and
  // " after"), and the second pass trims them -- so two consecutive saves of one unedited article produce two
  // different files. The corpus has no images yet (R2-MEDIA-INTERFACE.md section 0.1), so the input this needs is
  // exactly what the upload path now writes into an article.
  it('does NOT settle after one pass when an image was inline with prose', () => {
    const once = roundTrip('before ![Alt](media:a/b.png) after');

    expect(once).toBe('before \n\n![Alt](media:a/b.png)\n\n after');
    expect(roundTrip(once)).toBe('before\n\n![Alt](media:a/b.png)\n\nafter');
  });
});
