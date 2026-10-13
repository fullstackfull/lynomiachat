/**
 * Toolbar commands as pure source transforms.
 *
 * Each command takes the textarea's value and selection and returns a replacement:
 * `{ from, to, text, selectionStart, selectionEnd }` -- the span to replace, what to put there, and where the
 * caret should end up. Nothing here touches the DOM, so every command is tested on strings alone.
 *
 * They edit MARKDOWN SOURCE rather than a document model, and that is the whole design: a parse-and-serialize
 * round trip through the installed ProseMirror pair rewrites all 126 corpus files
 * (corpusRoundTrip.spec.js), so orchestrator ruling R3 point 2 keeps the editor off `content` until that is
 * fixed. Source edits cannot have a round-trip problem: the stored bytes are the bytes the operator sees.
 */

// The article renderer parses with CommonMarker `:DEFAULT` plus `:table` only
// (lib/chatwoot_markdown_renderer.rb:15), so there is no strikethrough and no autolink in an article even though
// the message renderer has both (:8). Offering a strikethrough button would store syntax the published page
// renders as literal tildes, so the toolbar does not have one.
const BULLET = '- ';
const QUOTE = '> ';
const FENCE = '```';

const lineBoundsAt = (value, index) => {
  const start = value.lastIndexOf('\n', Math.max(index - 1, 0)) + 1;
  const end = value.indexOf('\n', index);
  return { start, end: end === -1 ? value.length : end };
};

// The whole lines the selection touches. A line-oriented command (heading, list, quote) rewrites lines, not the
// selected substring, which is what makes it idempotent when the caret sits mid-word.
const selectedLines = (value, from, to) => {
  const first = lineBoundsAt(value, from);
  const last = lineBoundsAt(value, to);
  const start = first.start;
  const end = Math.max(last.end, start);
  return { start, end, lines: value.slice(start, end).split('\n') };
};

const replacement = (from, to, text, caretOffset = text.length) => ({
  from,
  to,
  text,
  selectionStart: from + caretOffset,
  selectionEnd: from + caretOffset,
});

const selecting = (from, to, text, innerStart, innerEnd) => ({
  from,
  to,
  text,
  selectionStart: from + innerStart,
  selectionEnd: from + innerEnd,
});

// --- inline marks -------------------------------------------------------------------------------------------

// Toggling rather than always wrapping: an operator who hits bold twice expects the bold gone, and a second
// wrap would store `****text****`, which CommonMark renders as literal asterisks.
const toggleWrap = (marker, value, from, to) => {
  const selected = value.slice(from, to);
  const before = value.slice(Math.max(from - marker.length, 0), from);
  const after = value.slice(to, to + marker.length);

  if (
    selected.startsWith(marker) &&
    selected.endsWith(marker) &&
    selected.length > marker.length * 2
  ) {
    const inner = selected.slice(marker.length, -marker.length);
    return selecting(from, to, inner, 0, inner.length);
  }
  if (before === marker && after === marker) {
    return selecting(
      from - marker.length,
      to + marker.length,
      selected,
      0,
      selected.length
    );
  }
  const wrapped = `${marker}${selected}${marker}`;
  return selecting(
    from,
    to,
    wrapped,
    marker.length,
    marker.length + selected.length
  );
};

export const bold = (value, from, to) => toggleWrap('**', value, from, to);
export const italic = (value, from, to) => toggleWrap('*', value, from, to);
export const inlineCode = (value, from, to) => toggleWrap('`', value, from, to);

// --- line-oriented blocks ----------------------------------------------------------------------------------

/**
 * `prefix` is what the button applies; `pattern` is the wider family it replaces. The two are deliberately
 * different: toggling off requires every line to carry THIS prefix, while replacing strips any member of the
 * family. That is what makes H2 -> H3 a change of level rather than a removal, and `* item` -> `- item` a
 * change of marker rather than an unindent.
 */
const togglePrefix = (prefix, pattern, value, from, to) => {
  const { start, end, lines } = selectedLines(value, from, to);
  const content = lines.filter(line => line.trim() !== '');
  const allPrefixed =
    content.length > 0 && content.every(line => line.startsWith(prefix));
  const next = lines.map(line => {
    if (line.trim() === '') return line;
    return allPrefixed
      ? line.replace(pattern, '')
      : `${prefix}${line.replace(pattern, '')}`;
  });
  const text = next.join('\n');
  return selecting(start, end, text, 0, text.length);
};

// `#{1,6} ` and nothing else: the renderer's heading comes from CommonMark ATX headings, and a level above 6 is
// not a heading at all.
export const heading = level => (value, from, to) =>
  togglePrefix('#'.repeat(level) + ' ', /^#{1,6} /, value, from, to);

export const bulletList = (value, from, to) =>
  togglePrefix(BULLET, /^[-*+] /, value, from, to);

export const blockquote = (value, from, to) =>
  togglePrefix(QUOTE, /^> /, value, from, to);

// Numbering is rewritten from 1 so a reordered list is not left with 1. 1. 1.; CommonMark would render that
// correctly but the source is what a reviewer reads.
export const orderedList = (value, from, to) => {
  const { start, end, lines } = selectedLines(value, from, to);
  const pattern = /^\d+\. /;
  const allNumbered = lines.every(
    line => line.trim() === '' || pattern.test(line)
  );
  let n = 0;
  const next = lines.map(line => {
    if (line.trim() === '') return line;
    if (allNumbered) return line.replace(pattern, '');
    n += 1;
    return `${n}. ${line.replace(pattern, '')}`;
  });
  const text = next.join('\n');
  return selecting(start, end, text, 0, text.length);
};

// --- fenced blocks and tables -------------------------------------------------------------------------------

/**
 * A fence keeps its info string. The renderer puts it in `class="language-..."` after escaping it
 * (lib/markdown_renderer_fence_info_escaping.rb:39-52), so the language is a real, security-reviewed field --
 * and the ProseMirror serializer DROPS it (measured: ```json round-trips to ```), which is the fifth reason the
 * editor does not re-serialize.
 */
export const codeBlock =
  (language = '') =>
  (value, from, to) => {
    const selected = value.slice(from, to);
    const open = `${FENCE}${language}\n`;
    const text = `${open}${selected}\n${FENCE}`;
    return selecting(
      from,
      to,
      text,
      open.length,
      open.length + selected.length
    );
  };

/**
 * A minimal GFM table. The delimiter row is `|---|` per column, matching the corpus's own style
 * (custom/db/documentation/**: every table is written this way), rather than the padded `| --- |` the
 * ProseMirror serializer emits.
 */
export const table =
  (columns = 3, rows = 2) =>
  (value, from, to) => {
    const header = `|${' Column |'.repeat(columns)}`;
    const delimiter = `|${'---|'.repeat(columns)}`;
    const body = Array.from(
      { length: rows },
      () => `|${'  |'.repeat(columns)}`
    );
    const text = [header, delimiter, ...body].join('\n');
    const { start } = lineBoundsAt(value, from);
    const atLineStart = start === from;
    const prefix = atLineStart ? '' : '\n\n';
    return replacement(from, to, `${prefix}${text}\n`, prefix.length + 2);
  };

export const link = url => (value, from, to) => {
  const selected = value.slice(from, to);
  const text = `[${selected}](${url})`;
  // Caret inside the destination when there is nothing to label, inside the label otherwise.
  return selected
    ? replacement(from, to, text)
    : selecting(from, to, text, 1, 1);
};

/**
 * Inserts a block the editor did not compose -- today, the `![alt](media:<key>)` string that
 * `Documentation::MediaUpload#create!` returns (R2-MEDIA-INTERFACE.md section 9.2).
 *
 * The editor deliberately does NOT build that string. The server owns the key grammar and the alt escaping, so
 * there is no `media:` regex, no key validation and no alt escaping in JS -- which is what interface section 8.2
 * asks for. Three things that follow, and they are all measured rather than assumed:
 *
 *   - no `?cw_image_width=`. Interface section 0.4: `URI.parse` puts a `media:` key's whole remainder in
 *     `opaque`, so `.query` is nil and CustomMarkdownRenderer#extract_image_width never reads a width. The
 *     editor's drag-resize convention does not work on a media key, and appending one would also break the
 *     key's grammar (section 1.4). Dimensions come from the resolver.
 *   - no `<figure>`/`<figcaption>` and no caption convention. `render_article` parses with `:DEFAULT`, so raw
 *     HTML renders as literally nothing -- a caption would vanish on publish while looking right in the editor
 *     (interface section 5.4, R2-O2).
 *   - an image is its own block, matching the live editor's isolateImagesPlugin. So a blank line opens before
 *     it unless the caret already starts one, and closes after it only when prose follows on the same line.
 */
export const insertBlock = text => (value, from, to) => {
  const { start, end } = lineBoundsAt(value, from);
  const prefix = start === from ? '' : '\n\n';
  const suffix = end === to ? '' : '\n\n';
  return replacement(from, to, `${prefix}${text}${suffix}`);
};
