/**
 * mediaUpload.js is the editor's only route to the media API, so what it has to get right is the wire: the two
 * URLs, the field names, the session credentials, the CSRF header and the shape of a refusal. Every one of those
 * is a contract with code in another language (R2-MEDIA-INTERFACE.md section 9.4,
 * custom/app/controllers/super_admin/documentation_media_controller.rb), which is why they are asserted here
 * rather than inferred from the component's behaviour.
 *
 * The server composes the Markdown and owns the key grammar, so there is nothing to test about either: what is
 * tested is that this module inserts what came back and never builds a key of its own.
 */
import fs from 'node:fs';
import path from 'node:path';
import {
  uploadMedia,
  replaceMedia,
  isAcceptedImage,
  ACCEPTED_TYPES,
  MediaUploadError,
} from './mediaUpload';

const ENDPOINT = '/super_admin/documentation_media';
const KEY = 'uploads/8f3a1c2b5d7e9a04-step-two.png';
const TOKEN = 'a-csrf-token';

// A 4x3 PNG, the same bytes the Ruby specs upload. Built here rather than read from the corpus: the corpus media
// tree is the corpus, and an upload fixture is not part of it.
const PNG_BASE64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAAAAACRn/EaAAAAC0lEQVR4nGNgQAEAAA8AAbVWKT4AAAAASUVORK5CYII=';

const pngFile = (name = 'Step Two.png') =>
  new File(
    [Uint8Array.from(atob(PNG_BASE64), character => character.charCodeAt(0))],
    name,
    { type: 'image/png' }
  );

const withCsrfToken = token => {
  const meta = document.createElement('meta');
  meta.setAttribute('name', 'csrf-token');
  meta.setAttribute('content', token);
  document.head.appendChild(meta);
};

const respondWith = ({ ok = true, statusText = '', json }) => {
  global.fetch = vi.fn().mockResolvedValue({ ok, statusText, json });
};

const lastRequest = () => {
  const [url, options] = global.fetch.mock.calls.at(-1);
  return { url, options, body: options.body };
};

describe('uploadMedia', () => {
  beforeEach(() => {
    document.head.innerHTML = '';
    withCsrfToken(TOKEN);
    respondWith({
      json: async () => ({
        key: KEY,
        markdown: `![Step two](media:${KEY})`,
        width: 4,
        height: 3,
        replaced: false,
      }),
    });
  });

  it('posts the file, the portal and the alt to the endpoint it was given', async () => {
    const file = pngFile();

    await uploadMedia(file, {
      endpoint: ENDPOINT,
      portalId: '7',
      alt: 'Paste the token',
    });

    const { url, options, body } = lastRequest();
    expect(url).toBe(ENDPOINT);
    expect(options.method).toBe('POST');
    expect(body.get('portal_id')).toBe('7');
    expect(body.get('alt')).toBe('Paste the token');
    expect(body.get('file').name).toBe('Step Two.png');
    expect(body.get('file').type).toBe('image/png');
    expect(body.get('file').size).toBe(file.size);
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  // The Super Admin session cookie is the authorization here -- there is no token, because
  // `authenticate_super_admin!` is the whole check -- so the cookie has to be sent and the CSRF header has to be
  // the page's own, or Rails answers the upload with a redirect to the sign-in page.
  it('sends the session cookie, the page CSRF token and asks for JSON', async () => {
    await uploadMedia(pngFile(), {
      endpoint: ENDPOINT,
      portalId: '7',
      alt: 'A',
    });

    const { options } = lastRequest();
    expect(options.credentials).toBe('same-origin');
    expect(options.headers['X-CSRF-Token']).toBe(TOKEN);
    expect(options.headers.Accept).toBe('application/json');
  });

  // A hand-set Content-Type would be sent without a boundary, so Rails would parse no params at all and the
  // upload would come back "A file is required." The absence is the behaviour.
  it('sets no Content-Type, so the browser writes the multipart boundary', async () => {
    await uploadMedia(pngFile(), {
      endpoint: ENDPOINT,
      portalId: '7',
      alt: 'A',
    });

    expect(Object.keys(lastRequest().options.headers)).toEqual([
      'X-CSRF-Token',
      'Accept',
    ]);
  });

  it('sends an empty token rather than the string "undefined" when the page has no csrf meta', async () => {
    document.head.innerHTML = '';

    await uploadMedia(pngFile(), {
      endpoint: ENDPOINT,
      portalId: '7',
      alt: 'A',
    });

    expect(lastRequest().options.headers['X-CSRF-Token']).toBe('');
  });

  // The server writes the Markdown (interface section 9.2) and the editor inserts it verbatim, so the payload has
  // to come back whole. A module that rebuilt the string from `key` would be transcribing the grammar into JS.
  it('resolves with the server payload, the markdown included', async () => {
    const result = await uploadMedia(pngFile(), {
      endpoint: ENDPOINT,
      portalId: '7',
      alt: 'Step two',
    });

    expect(result.key).toBe(KEY);
    expect(result.markdown).toBe(`![Step two](media:${KEY})`);
    expect([result.width, result.height]).toEqual([4, 3]);
  });

  describe('a refusal', () => {
    it('throws MediaUploadError carrying the operator-readable reason', async () => {
      respondWith({
        ok: false,
        statusText: 'Unprocessable Entity',
        json: async () => ({ error: 'Alt text is required.' }),
      });

      const failure = uploadMedia(pngFile(), {
        endpoint: ENDPOINT,
        portalId: '7',
        alt: ' ',
      });

      await expect(failure).rejects.toBeInstanceOf(MediaUploadError);
      await expect(failure).rejects.toThrow('Alt text is required.');
    });

    it('falls back to the status text when the body carries no reason', async () => {
      respondWith({
        ok: false,
        statusText: 'Not Found',
        json: async () => ({}),
      });

      await expect(
        uploadMedia(pngFile(), { endpoint: ENDPOINT, portalId: '0', alt: 'A' })
      ).rejects.toThrow('Not Found');
    });

    // What an HTML error page or a dropped connection looks like from here: `json()` rejects. The operator still
    // has to be told something, and it must not be an unhandled SyntaxError.
    it('falls back to the status text when the refusal is not JSON at all', async () => {
      respondWith({
        ok: false,
        statusText: 'Internal Server Error',
        json: async () => {
          throw new SyntaxError('Unexpected token <');
        },
      });

      await expect(
        uploadMedia(pngFile(), { endpoint: ENDPOINT, portalId: '7', alt: 'A' })
      ).rejects.toThrow('Internal Server Error');
    });
  });
});

describe('replaceMedia', () => {
  beforeEach(() => {
    document.head.innerHTML = '';
    withCsrfToken(TOKEN);
    respondWith({
      json: async () => ({ key: KEY, width: 6, height: 2, replaced: true }),
    });
  });

  // The replace route is a glob (`patch 'documentation_media/*key'`, config/routes/documentation.rb) with
  // `format: false`, so the key's slash and its extension have to arrive intact. An encoded slash would be a path
  // the route cannot match.
  it('patches the key onto the endpoint path with its slash and extension intact', async () => {
    await replaceMedia(pngFile('b.png'), {
      endpoint: ENDPOINT,
      portalId: '7',
      key: KEY,
    });

    const { url, options } = lastRequest();
    expect(url).toBe(`${ENDPOINT}/${KEY}`);
    expect(url).toContain('/uploads/');
    expect(url.endsWith('.png')).toBe(true);
    expect(options.method).toBe('PATCH');
  });

  it('sends no alt, because the reference in the article keeps the one it has', async () => {
    await replaceMedia(pngFile('b.png'), {
      endpoint: ENDPOINT,
      portalId: '7',
      key: KEY,
    });

    const { body } = lastRequest();
    expect(body.get('alt')).toBeNull();
    expect(body.get('portal_id')).toBe('7');
    expect(body.get('file').name).toBe('b.png');
  });

  it('resolves with the replaced flag and the new dimensions, and no markdown', async () => {
    const result = await replaceMedia(pngFile('b.png'), {
      endpoint: ENDPOINT,
      portalId: '7',
      key: KEY,
    });

    expect(result.replaced).toBe(true);
    expect([result.width, result.height]).toEqual([6, 2]);
    expect(result.markdown).toBeUndefined();
  });

  // The refusal an operator actually meets: the corpus is the source of truth for corpus content, so a seeded
  // key cannot be replaced from the database. The message has to reach them unchanged.
  it('surfaces the service refusal for a key the seeder owns', async () => {
    respondWith({
      ok: false,
      statusText: 'Unprocessable Entity',
      json: async () => ({
        error:
          'whatsapp/step-2.png is seeded from the corpus; change the file in the repository instead.',
      }),
    });

    await expect(
      replaceMedia(pngFile('b.png'), {
        endpoint: ENDPOINT,
        portalId: '7',
        key: 'whatsapp/step-2.png',
      })
    ).rejects.toThrow(/seeded from the corpus/);
  });
});

describe('the accepted-type gate', () => {
  it.each(ACCEPTED_TYPES)('accepts %s', type => {
    expect(isAcceptedImage({ type })).toBe(true);
  });

  // SVG is absent on purpose (contract item 5, raster only): the blob servable readers would force it to a binary
  // type and an attachment disposition, so one would never render even if it were stored.
  it.each([
    ['image/svg+xml', 'the raster-only rule'],
    ['application/pdf', 'not an image'],
    ['text/html', 'not an image'],
    ['', 'a file the browser could not type'],
  ])('refuses %s (%s)', type => {
    expect(isAcceptedImage({ type })).toBe(false);
  });

  it('refuses a missing file rather than throwing on it', () => {
    expect(isAcceptedImage(null)).toBe(false);
    expect(isAcceptedImage(undefined)).toBe(false);
  });

  // The server identifies the type from the BYTES and is the enforcement; this list only keeps the file picker and
  // the error message honest. Honest means equal to the server's list -- so this reads the server's own constant,
  // and a type added on one side without the other turns it red.
  it('mirrors Documentation::MediaUpload::CONTENT_TYPES exactly', () => {
    const source = fs.readFileSync(
      path.resolve(
        process.cwd(),
        'custom/app/services/documentation/media_upload.rb'
      ),
      'utf-8'
    );
    const literal = source.match(/CONTENT_TYPES = \{([^}]*)\}/)[1];
    const serverTypes = [...literal.matchAll(/'([^']+)'\s*=>/g)].map(
      match => match[1]
    );

    expect([...ACCEPTED_TYPES].sort()).toEqual(serverTypes.sort());
  });
});
