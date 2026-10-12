import { isNavigable, navigableEntries } from '../navigationContract';

// THE NAVIGATION CONTRACT, held explicitly.
//
// `Sidebar.vue` used to end the Help and Support group with `.filter(child => child.href)`. Correct for its
// two href-only entries, wrong as a rule: a `to`-based entry added to that group later would have been
// dropped silently, and the real rule lived somewhere else, written differently. These examples are the
// contract, so a change to either expression has to change them.
describe('the sidebar navigation contract', () => {
  describe('isNavigable', () => {
    it('accepts a route target', () => {
      expect(isNavigable({ to: 'conversations_index' })).toBe(true);
    });

    it('accepts a route location object, which is a valid `to`', () => {
      expect(
        isNavigable({ to: { name: 'conversations_index', params: { id: 1 } } })
      ).toBe(true);
    });

    it('accepts an external or server-rendered href', () => {
      expect(isNavigable({ href: 'https://docs.example.com' })).toBe(true);
    });

    // A branded installation that configured no documentation link gets '' from `brandLink`, which means
    // "render no link" -- not "link to nothing".
    it('refuses an empty href, which is how "no link" is expressed', () => {
      expect(isNavigable({ href: '' })).toBe(false);
      expect(isNavigable({ href: '   ' })).toBe(false);
    });

    it('refuses an empty route target for the same reason', () => {
      expect(isNavigable({ to: '' })).toBe(false);
    });

    it('refuses an entry that declares no routing form at all', () => {
      expect(isNavigable({ name: 'Decorative', label: 'Nothing here' })).toBe(
        false
      );
    });

    it('refuses nothing at all', () => {
      expect(isNavigable(undefined)).toBe(false);
      expect(isNavigable(null)).toBe(false);
    });

    it('accepts a group when any child reaches somewhere', () => {
      expect(
        isNavigable({
          name: 'Group',
          children: [{ name: 'Dead' }, { to: 'conversations_index' }],
        })
      ).toBe(true);
    });

    it('refuses a group where nothing reaches anywhere', () => {
      expect(
        isNavigable({
          name: 'Group',
          children: [{ name: 'Dead' }, { href: '' }],
        })
      ).toBe(false);
    });

    it('refuses an empty group', () => {
      expect(isNavigable({ name: 'Group', children: [] })).toBe(false);
    });
  });

  describe('navigableEntries', () => {
    // The regression this exists for. Both forms survive the same filter; before the contract, the Help and
    // Support group kept only the href one.
    it('keeps both routing forms, in order', () => {
      const entries = [
        { name: 'Documentation', href: 'https://docs.example.com' },
        { name: 'Support', href: '' },
        { name: 'Operations', to: 'operations_index' },
      ];

      expect(navigableEntries(entries).map(entry => entry.name)).toEqual([
        'Documentation',
        'Operations',
      ]);
    });

    it('drops every entry when an installation configured none of them', () => {
      expect(
        navigableEntries([{ href: '' }, { href: undefined }])
      ).toHaveLength(0);
    });

    it('answers for no entries at all', () => {
      expect(navigableEntries()).toEqual([]);
    });
  });
});
