/**
 * The two things the editor refuses to let an operator publish, checked on the Markdown source.
 *
 * Both are enforced server-side as well and that is deliberate -- these are the better message, not the
 * enforcement. Alt text is checked at the seed boundary (R2-MEDIA-INTERFACE.md section 5.2) and a `data:` image
 * destination is stripped by the renderer's sanitizer (lib/markdown_renderer_url_sanitizer.rb:14-19).
 */

const FENCE = /^[ \t]*(```|~~~)/;

// `![alt](destination)`. The destination stops at the first `)` because neither a `media:` key (interface
// section 1.2 excludes every bracket character) nor a documentation URL in this corpus contains one.
const IMAGE = /!\[([^\]]*)\]\(([^)]*)\)/g;

const DATA_IMAGE = /^\s*data:/i;

// The scheme token of R2-MEDIA-INTERFACE.md section 1.1, which is NOT the key grammar: this reads back a
// destination the server wrote, so that a replacement can name the key the operator's caret is sitting on. The
// grammar itself stays in one constant on Documentation::MediaResolver (section 1.5) and nothing here validates
// a key -- an unknown one is the server's 404.
const MEDIA_SCHEME = 'media:';

// Lines outside fenced code blocks, with their 1-based numbers. A fence's contents are literal text: an image
// written inside one is sample source an article is explaining, not an image, and flagging it would be wrong.
const proseLines = source =>
  source.split('\n').reduce(
    (state, line, index) => {
      if (FENCE.test(line)) return { ...state, inFence: !state.inFence };
      if (state.inFence) return state;
      return { ...state, lines: [...state.lines, { number: index + 1, line }] };
    },
    { inFence: false, lines: [] }
  ).lines;

const imagesIn = source =>
  proseLines(source).flatMap(({ number, line }) =>
    [...line.matchAll(IMAGE)].map(match => ({
      line: number,
      alt: match[1],
      destination: match[2],
    }))
  );

/**
 * Alt text is a PUBLIC field, not only an accessibility attribute: `render_markdown_to_plain_text`
 * (lib/chatwoot_markdown_renderer.rb:21-23) emits an image's alt and discards its destination, and it feeds the
 * public search payload (app/views/public/api/v1/models/_search_article.json.jbuilder:1) and
 * PortalHelper#render_category_content (app/helpers/portal_helper.rb:97). So an empty alt degrades the search
 * snippet as well as the screen reader, which is why a missing one blocks publication rather than warning.
 */
export const imagesMissingAlt = source =>
  imagesIn(source).filter(({ alt }) => alt.trim() === '');

/**
 * A `data:image/*` destination in article content. The editor refuses it on paste and on publish rather than
 * storing it: R2-MEDIA-INTERFACE.md section 8.2 names writing one into `content` as out of bounds, and an inline
 * base64 image is unreviewable, uncacheable and invisible to the media seeder's orphan pass.
 */
export const dataImageDestinations = source =>
  imagesIn(source).filter(({ destination }) => DATA_IMAGE.test(destination));

/**
 * The `media:` key of the image on the caret's line, or null. This is what lets "Replace image" name a key
 * without the operator pasting one: the caret is already on the image they mean.
 */
export const mediaKeyOnLine = (source, caret) => {
  const start = source.lastIndexOf('\n', Math.max(caret - 1, 0)) + 1;
  const lineEnd = source.indexOf('\n', caret);
  const line = source.slice(start, lineEnd === -1 ? source.length : lineEnd);

  const match = [...line.matchAll(IMAGE)]
    .map(found => found[2])
    .find(destination => destination.startsWith(MEDIA_SCHEME));

  return match ? match.slice(MEDIA_SCHEME.length) : null;
};
