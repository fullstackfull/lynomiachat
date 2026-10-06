import enContact from 'dashboard/i18n/locale/en/contact.json';
import arContact from 'dashboard/i18n/locale/ar/contact.json';
import enFilters from 'dashboard/i18n/locale/en/contactFilters.json';
import arFilters from 'dashboard/i18n/locale/ar/contactFilters.json';

// The audience surfaces are the ones this product explains itself on, and half the accounts read them in Arabic.
// Scoped to the blocks the audience UI owns rather than to whole files: a file-wide check would fail on gaps left
// by other work and would be switched off instead of fixed.
const BLOCKS = [
  ['CONTACTS_LAYOUT.AUDIENCES', enContact, arContact],
  ['CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE', enContact, arContact],
  ['CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS', enContact, arContact],
  ['CONTACTS_FILTER.AUDIENCE', enFilters, arFilters],
];

const at = (root, path) =>
  path.split('.').reduce((node, key) => node?.[key], root);

const flatten = (node, prefix = '') => {
  if (Array.isArray(node)) return { [prefix]: `list:${node.length}` };
  if (node && typeof node === 'object') {
    return Object.entries(node).reduce(
      (out, [key, value]) => ({
        ...out,
        ...flatten(value, prefix ? `${prefix}.${key}` : key),
      }),
      {}
    );
  }
  return { [prefix]: typeof node };
};

describe('audience copy', () => {
  it.each(BLOCKS)(
    'says the same things in both languages (%s)',
    (path, en, ar) => {
      const english = flatten(at(en, path));
      const arabic = flatten(at(ar, path));

      expect(Object.keys(english).length).toBeGreaterThan(0);
      expect(Object.keys(arabic).sort()).toEqual(Object.keys(english).sort());
    }
  );

  it.each(BLOCKS)(
    'keeps every placeholder a string carries (%s)',
    (path, en, ar) => {
      const english = flatten(at(en, path));
      const arabic = flatten(at(ar, path));
      // Compared as a set: a plural with a different number of forms carries the same placeholder a different
      // number of times, and that is not a mistake.
      const placeholders = value =>
        [...new Set(String(value).match(/\{[a-zA-Z_]+\}/g) || [])].sort();

      Object.keys(english).forEach(key => {
        expect(
          placeholders(at(ar, `${path}.${key}`)),
          `${path}.${key}`
        ).toEqual(placeholders(at(en, `${path}.${key}`)));
        expect(typeof arabic[key]).toBe(typeof english[key]);
      });
    }
  );

  // With no Arabic plural rule configured, vue-i18n reads the first three forms as 0 / 1 / many. A string with
  // more forms than that silently loses its number: six forms made every count above one read "two contacts".
  it('writes an Arabic plural the renderer can actually use', () => {
    const plurals = Object.entries(flatten(arContact.CONTACTS_LAYOUT.AUDIENCES))
      .filter(([, kind]) => kind === 'string')
      .map(([key]) => [key, at(arContact, `CONTACTS_LAYOUT.AUDIENCES.${key}`)])
      .filter(([, value]) => String(value).includes(' | '));

    expect(plurals.length).toBeGreaterThan(0);
    plurals.forEach(([key, value]) => {
      const forms = String(value).split(' | ');
      expect(forms.length, key).toBeLessThanOrEqual(3);
      // The "many" form is the one a real number lands in, so it has to carry the number.
      expect(forms[forms.length - 1], key).toContain('{count}');
    });
  });
});
