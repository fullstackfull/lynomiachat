import {
  EMPTY_STATE_KEYS,
  conversationListEmptyStateKey,
} from '../emptyStateHelper';

const context = overrides => ({
  hasActiveFolders: false,
  hasAppliedFilters: false,
  activeStatus: 'all',
  ...overrides,
});

describe('conversationListEmptyStateKey', () => {
  it('reports a genuinely empty account only when nothing is narrowing the list', () => {
    expect(conversationListEmptyStateKey(context())).toBe(
      EMPTY_STATE_KEYS.NO_CONVERSATIONS
    );
  });

  // The default status filter is `open`, so this is the case an agent actually hits: conversations exist,
  // they are just resolved, pending or snoozed.
  it.each(['open', 'resolved', 'pending', 'snoozed'])(
    'reports the status filter as the reason when it is set to %s',
    activeStatus => {
      expect(conversationListEmptyStateKey(context({ activeStatus }))).toBe(
        EMPTY_STATE_KEYS.STATUS_FILTERED
      );
    }
  );

  it('reports the applied filters ahead of the status filter', () => {
    expect(
      conversationListEmptyStateKey(
        context({ hasAppliedFilters: true, activeStatus: 'open' })
      )
    ).toBe(EMPTY_STATE_KEYS.FILTERED);
  });

  // A folder is reached by its own route and carries its own saved query, so it names itself even though
  // applying it also sets the ad-hoc filter flag.
  it('reports the folder ahead of everything else', () => {
    expect(
      conversationListEmptyStateKey(
        context({
          hasActiveFolders: true,
          hasAppliedFilters: true,
          activeStatus: 'open',
        })
      )
    ).toBe(EMPTY_STATE_KEYS.FOLDER);
  });
});
