import wootConstants from 'dashboard/constants/globals';

// The conversation list can come back empty for reasons that call for different answers, so the empty state
// names the reason rather than saying "no conversations" four different times. Each key resolves to its own
// CHAT_LIST.LIST.EMPTY.<key> block of copy, and to the way out of that particular emptiness.
export const EMPTY_STATE_KEYS = {
  FOLDER: 'FOLDER',
  FILTERED: 'FILTERED',
  STATUS_FILTERED: 'STATUS_FILTERED',
  NO_CONVERSATIONS: 'NO_CONVERSATIONS',
};

// A folder is a saved query reached by its own route, so it is reported ahead of the ad-hoc filters it is
// built from. The status filter is checked last because it is the one that is always on -- `open` by
// default -- which is how a queue of resolved conversations stays invisible to an agent who has never
// opened the filter panel.
export function conversationListEmptyStateKey({
  hasActiveFolders,
  hasAppliedFilters,
  activeStatus,
}) {
  if (hasActiveFolders) return EMPTY_STATE_KEYS.FOLDER;
  if (hasAppliedFilters) return EMPTY_STATE_KEYS.FILTERED;
  if (activeStatus !== wootConstants.STATUS_TYPE.ALL) {
    return EMPTY_STATE_KEYS.STATUS_FILTERED;
  }
  return EMPTY_STATE_KEYS.NO_CONVERSATIONS;
}
