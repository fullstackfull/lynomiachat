const INBOX_SORT_OPTIONS = {
  newest: 'desc',
  oldest: 'asc',
};

const sortConfig = {
  newest: (a, b) => b.created_at - a.created_at,
  oldest: (a, b) => a.created_at - b.created_at,
};

export const sortComparator = (a, b, sortOrder) => {
  const sortDirection = INBOX_SORT_OPTIONS[sortOrder];
  if (sortOrder === 'newest' || sortOrder === 'oldest') {
    return sortConfig[sortOrder](a, b, sortDirection);
  }
  return 0;
};

/**
 * Primary actor types the Inbox feed cannot render, and must not try to.
 *
 * The feed is conversation-shaped from the list down: `InboxList.vue` destructures
 * `primaryActor: { inboxId, id: conversationId }` and pushes `inbox_view_conversation` with them, and
 * `InboxCard.vue` reads `primaryActor.meta.sender` for the avatar. A `PlatformSupport::Ticket` row carries
 * none of that, so rendering one would either throw or -- worse -- route to `inbox_view_conversation` with an
 * undefined inbox and a TICKET id in the conversation slot, which is a wrong destination rather than an error.
 *
 * Excluding the row here, in the store, is the whole fix: the list, the active-row lookup in `InboxView.vue`
 * and the click handler all read these getters, so the row never reaches a renderer or a route. The BADGE is
 * unaffected -- it reads `meta.unreadCount`, which the server supplies from its own count query -- so a
 * Platform Support reply still raises the bell, and the ticket is read on the Platform Support surface, which
 * is where its thread lives.
 */
export const FEED_EXCLUDED_PRIMARY_ACTOR_TYPES = ['PlatformSupport::Ticket'];

export const isRenderableInFeed = notification =>
  !FEED_EXCLUDED_PRIMARY_ACTOR_TYPES.includes(notification?.primary_actor_type);
