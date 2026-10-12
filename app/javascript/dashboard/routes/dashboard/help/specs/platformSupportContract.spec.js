import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

import en from 'dashboard/i18n/locale/en/platformSupport.json';
import ar from 'dashboard/i18n/locale/ar/platformSupport.json';
import { DOC_ARTICLES } from 'dashboard/helper/documentationLinks';
import {
  PLATFORM_SUPPORT_CATEGORIES,
  PLATFORM_SUPPORT_CLOSED_STATUSES,
  PLATFORM_SUPPORT_OPEN_STATUSES,
  PLATFORM_SUPPORT_PRIORITIES,
  PLATFORM_SUPPORT_STATUSES,
} from '../constants';

// The frozen contract, asserted against the bundle rather than against a reviewer's memory
// (docs/platform-support/12-refresh-against-product-refinement.md §2, §4, §7, §9 and
// docs/platform-support/04-customer-ux.md §4, §5).
//
// Four of these are security or product rules that a future edit could break silently, in a file nobody
// thought to re-read: the absence of internal notes from the tenant bundle, the absence of any blob URL, the
// absence of a physical-direction utility, and the two locales staying in step.

const MODULE_ROOT = join(__dirname, '..');

const sourceFiles = (dir = MODULE_ROOT) =>
  readdirSync(dir).flatMap(entry => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      return entry === 'specs' ? [] : sourceFiles(path);
    }

    return /\.(js|vue)$/.test(entry) ? [path] : [];
  });

// Comments are stripped before the three absence rules are checked. The rules are about what this bundle can
// REACH, and a comment stating that internal notes have no tenant surface is the documentation of that rule,
// not a violation of it.
const withoutComments = body =>
  body
    .replace(/<!--[\s\S]*?-->/g, '')
    .split('\n')
    .filter(line => !/^\s*(\/\/|\/\*|\*)/.test(line))
    .join('\n');

const sources = sourceFiles().map(path => ({
  path,
  body: readFileSync(path, 'utf8'),
  code: withoutComments(readFileSync(path, 'utf8')),
}));

const vueSources = sources.filter(source => source.path.endsWith('.vue'));

const flatKeys = (object, prefix = '') =>
  Object.entries(object).flatMap(([key, value]) =>
    value && typeof value === 'object'
      ? flatKeys(value, `${prefix}${key}.`)
      : [`${prefix}${key}`]
  );

describe('the Platform Support tenant bundle', () => {
  it('found its own source files', () => {
    expect(sources.length).toBeGreaterThan(10);
  });

  // The secrecy rule that is NOT a front-end rule, asserted here anyway: the server has no tenant route and no
  // serializer key for an internal note, and this bundle must never grow one -- not a hidden surface, not a
  // filtered one.
  it('never mentions internal notes, in any spelling', () => {
    const offenders = sources.filter(source =>
      /internal[_\s]?note/i.test(source.code)
    );

    expect(offenders.map(source => source.path)).toEqual([]);
  });

  // Blob URLs do not expire in this installation, so a signed id rendered into a page is a permanent bearer
  // token (§B-10). Every attachment is reached through the authorized download route instead.
  it('never builds or renders an ActiveStorage blob URL', () => {
    const offenders = sources.filter(source =>
      /rails_blob|rails_storage_proxy|rails\/active_storage|signed_id/.test(
        source.code
      )
    );

    expect(offenders.map(source => source.path)).toEqual([]);
  });

  // RTL from the first commit, not a later pass: the status chips, the unread dot, the attachment rows and the
  // tree lines are all direction-sensitive, and a physical utility is the one mistake that looks fine in
  // English (docs/platform-support/04-customer-ux.md §5).
  it('uses only logical Tailwind utilities, so Arabic mirrors', () => {
    const physical =
      /(?:^|[\s"'`:[{])-?(?:m[lr]|p[lr])-|(?:^|[\s"'`:[{])(?:left|right)-|text-(?:left|right)|border-[lr]-|rounded-(?:[lr]|[tb][lr])-/;

    const offenders = vueSources.filter(source => physical.test(source.code));

    expect(offenders.map(source => source.path)).toEqual([]);
  });

  it('declares no feature flag anywhere: the desk is never gated', () => {
    const offenders = sources.filter(source => /featureFlag/.test(source.code));

    expect(offenders.map(source => source.path)).toEqual([]);
  });
});

describe('the Platform Support vocabulary', () => {
  it('is the six statuses, in the order the partial indexes depend on', () => {
    expect(PLATFORM_SUPPORT_STATUSES).toEqual([
      'open',
      'in_progress',
      'waiting_on_customer',
      'waiting_on_lynomia',
      'resolved',
      'closed',
    ]);
    expect([
      ...PLATFORM_SUPPORT_OPEN_STATUSES,
      ...PLATFORM_SUPPORT_CLOSED_STATUSES,
    ]).toEqual(PLATFORM_SUPPORT_STATUSES);
  });

  it('is the eleven categories and the four priorities', () => {
    expect(PLATFORM_SUPPORT_CATEGORIES).toHaveLength(11);
    expect(PLATFORM_SUPPORT_CATEGORIES).toContain('other');
    expect(PLATFORM_SUPPORT_PRIORITIES).toEqual([
      'low',
      'medium',
      'high',
      'urgent',
    ]);
  });

  it('has a label in both locales for every status, priority and category', () => {
    [
      ['STATUS', PLATFORM_SUPPORT_STATUSES],
      ['PRIORITY', PLATFORM_SUPPORT_PRIORITIES],
      ['CATEGORY', PLATFORM_SUPPORT_CATEGORIES],
    ].forEach(([group, values]) => {
      values.forEach(value => {
        const key = value.toUpperCase();
        expect(en.PLATFORM_SUPPORT.ENUMS[group][key]).toBeTruthy();
        expect(ar.PLATFORM_SUPPORT.ENUMS[group][key]).toBeTruthy();
      });
    });
  });

  it('has a plain-language sentence for every status, in both locales', () => {
    PLATFORM_SUPPORT_STATUSES.forEach(status => {
      const key = status.toUpperCase();
      expect(en.PLATFORM_SUPPORT.STATUS_SENTENCE[key]).toBeTruthy();
      expect(ar.PLATFORM_SUPPORT.STATUS_SENTENCE[key]).toBeTruthy();
    });
  });
});

describe('the Platform Support locale files', () => {
  it('hang off the one root key the contract reserves', () => {
    expect(Object.keys(en)).toEqual(['PLATFORM_SUPPORT']);
    expect(Object.keys(ar)).toEqual(['PLATFORM_SUPPORT']);
  });

  it('are in step: the same keys, in the same order', () => {
    expect(flatKeys(ar)).toEqual(flatKeys(en));
  });

  it('are actually translated, not English copied into the Arabic file', () => {
    const arabic = /[؀-ۿ]/;
    const untranslated = flatKeys(ar).filter(key => {
      const value = key.split('.').reduce((node, segment) => node[segment], ar);

      return !arabic.test(value);
    });

    expect(untranslated).toEqual([]);
  });
});

describe('the Platform Support contextual help', () => {
  it('registers its article by stable slug, so no Vue file carries a URL', () => {
    expect(DOC_ARTICLES.contactLynomiaSupport).toBe('contact-lynomia-support');

    const offenders = sources.filter(source => /https?:\/\//.test(source.code));
    expect(offenders.map(source => source.path)).toEqual([]);
  });

  it('renders every link through DocsLink, which renders nothing without a DOCUMENTATION_URL', () => {
    const usesArticleKey = vueSources.filter(source =>
      /article-key=/.test(source.body)
    );
    const importsDocsLink = vueSources.filter(source =>
      /components-next\/docs-link\/DocsLink\.vue/.test(source.body)
    );

    expect(usesArticleKey.length).toBeGreaterThan(0);
    expect(usesArticleKey.map(source => source.path).sort()).toEqual(
      importsDocsLink.map(source => source.path).sort()
    );
  });
});
