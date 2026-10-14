/**
 * The editor's only route to media, and the ONE place that knows the wire shape.
 *
 * Agent 1 owns the backend: `Documentation::MediaUpload` reached through
 * `SuperAdmin::DocumentationMediaController`, attaching to the same `portal.documentation_media` namespace,
 * addressed by the same `media:` key grammar and resolved by the same `Documentation::MediaResolver` as the
 * repository-seeded corpus (P2-WORKSTREAM-OWNERSHIP.md F1, R2-MEDIA-INTERFACE.md section 9). Seeded media and
 * operator-uploaded media are one abstraction, so this module is a client and not a second media system.
 *
 * THE SERVER WRITES THE MARKDOWN. `create!` takes the alt text, refuses a blank one, and returns the finished
 * `![alt](media:<key>)` string (interface section 9.2). So the editor sends the alt up and inserts what comes
 * back verbatim: the key grammar is never transcribed into JS, the alt requirement cannot be skipped
 * client-side, and the alt escaping that keeps `Step 2 [see note]` from producing a broken image node happens
 * once, on the server.
 *
 * Two things this must not become, both from interface section 8.2:
 *   - an ActiveStorage direct upload. The bare route answers 403 by design
 *     (config/initializers/active_storage.rb:52-63) and that guard is not relaxed or subclassed around.
 *   - a place that validates or builds a key. Those live on the resolver and the upload service.
 */

// Interface section 9.4:
//   POST  /super_admin/documentation_media         params: portal_id, file, alt   -> 201
//   PATCH /super_admin/documentation_media/:key    params: portal_id, file        -> 200
// A refusal is 422 (or 404 for an unknown portal) with { error: "<operator-readable reason>" }.
const CSRF_SELECTOR = 'meta[name="csrf-token"]';

const csrfToken = () => document.querySelector(CSRF_SELECTOR)?.content ?? '';

export class MediaUploadError extends Error {}

const send = async (url, method, body) => {
  const response = await fetch(url, {
    method,
    body,
    credentials: 'same-origin',
    headers: { 'X-CSRF-Token': csrfToken(), Accept: 'application/json' },
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok)
    throw new MediaUploadError(payload.error || response.statusText);

  return payload;
};

/**
 * @returns {Promise<{key: string, markdown: string, width: ?number, height: ?number}>} -- `markdown` is the
 *   exact string to insert at the caret.
 */
export const uploadMedia = (file, { endpoint, portalId, alt }) => {
  const body = new FormData();
  body.append('file', file);
  body.append('portal_id', portalId);
  body.append('alt', alt);

  return send(endpoint, 'POST', body);
};

/**
 * Same key, new bytes: the reference already in the article keeps working and its alt is untouched, so there is
 * no markdown to insert. The server refuses a key the SEEDER owns, because the corpus is the source of truth
 * for corpus content and a database-only change would be reverted by the next seed (interface section 9.2).
 */
export const replaceMedia = (file, { endpoint, portalId, key }) => {
  const body = new FormData();
  body.append('file', file);
  body.append('portal_id', portalId);

  return send(`${endpoint}/${key}`, 'PATCH', body);
};

// Mirrors Documentation::MediaUpload::CONTENT_TYPES. `image/svg+xml` is absent on purpose: contract item 5 is
// raster only, and the blob servable readers would force an SVG to a binary type and an attachment
// disposition, so one would never render. The server identifies the type from the BYTES and is the enforcement;
// this list only keeps the file picker and the error message honest.
export const ACCEPTED_TYPES = Object.freeze([
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
]);

export const isAcceptedImage = file => ACCEPTED_TYPES.includes(file?.type);
