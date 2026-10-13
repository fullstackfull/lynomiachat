import { getters } from '../../notifications/getters';

describe('#getters', () => {
  it('getFilteredNotifications', () => {
    const state = {
      records: {
        1: { id: 1, read_at: '2024-02-07T11:42:39.988Z', snoozed_until: null },
        2: { id: 2, read_at: null, snoozed_until: null },
        3: {
          id: 3,
          read_at: '2024-02-07T11:42:39.988Z',
          snoozed_until: '2024-02-07T11:42:39.988Z',
        },
      },
    };
    const filters = {
      type: 'read',
      status: 'snoozed',
      sortOrder: 'desc',
    };
    expect(getters.getFilteredNotifications(state)(filters)).toEqual([
      { id: 1, read_at: '2024-02-07T11:42:39.988Z', snoozed_until: null },
      { id: 2, read_at: null, snoozed_until: null },
      {
        id: 3,
        read_at: '2024-02-07T11:42:39.988Z',
        snoozed_until: '2024-02-07T11:42:39.988Z',
      },
    ]);
  });

  it('getNotificationById', () => {
    const state = {
      records: {
        1: { id: 1 },
      },
    };
    expect(getters.getNotificationById(state)(1)).toEqual({ id: 1 });
    expect(getters.getNotificationById(state)(2)).toEqual({});
  });

  it('getUIFlags', () => {
    const state = {
      uiFlags: {
        isFetching: true,
      },
    };
    expect(getters.getUIFlags(state)).toEqual({
      isFetching: true,
    });
  });

  it('getNotification', () => {
    const state = {
      records: {
        1: { id: 1 },
      },
    };
    expect(getters.getNotification(state)(1)).toEqual({ id: 1 });
    expect(getters.getNotification(state)(2)).toEqual({});
  });

  it('getMeta', () => {
    const state = {
      meta: { unreadCount: 1 },
    };
    expect(getters.getMeta(state)).toEqual({ unreadCount: 1 });
  });

  it('getNotificationFilters', () => {
    const state = {
      notificationFilters: {
        page: 1,
        status: 'unread',
        type: 'all',
        sortOrder: 'desc',
      },
    };
    expect(getters.getNotificationFilters(state)).toEqual(
      state.notificationFilters
    );
  });

  describe('getHasUnreadNotifications', () => {
    it('should return true when there are unread notifications', () => {
      const state = {
        meta: { unreadCount: 5 },
      };
      expect(getters.getHasUnreadNotifications(state)).toBe(true);
    });

    it('should return false when there are no unread notifications', () => {
      const state = {
        meta: { unreadCount: 0 },
      };
      expect(getters.getHasUnreadNotifications(state)).toBe(false);
    });

    it('should return false when meta is empty', () => {
      const state = {
        meta: {},
      };
      expect(getters.getHasUnreadNotifications(state)).toBe(false);
    });
  });

  // PLATFORM SUPPORT ROWS ARE NOT FEED ROWS. The Inbox feed is conversation-shaped: the list destructures
  // `primaryActor: { inboxId, id: conversationId }` and routes to `inbox_view_conversation` with them, and
  // the card reads `primaryActor.meta.sender`. A ticket row carries none of that, so it is dropped here --
  // before any renderer or click handler can see it -- while the unread badge, which reads the
  // server-supplied `meta.unreadCount`, still counts it.
  describe('feed rows the Inbox cannot render', () => {
    const state = {
      records: {
        1: {
          id: 1,
          created_at: 2,
          primary_actor_type: 'Conversation',
          primary_actor_id: 7,
        },
        2: {
          id: 2,
          created_at: 1,
          primary_actor_type: 'PlatformSupport::Ticket',
          primary_actor_id: 7,
        },
      },
      meta: { unreadCount: 2 },
    };

    it('excludes a PlatformSupport::Ticket row from getFilteredNotifications', () => {
      expect(
        getters.getFilteredNotifications(state)({ sortOrder: 'desc' })
      ).toEqual([state.records[1]]);
    });

    it('excludes it from getFilteredNotificationsV4 as well', () => {
      expect(
        getters
          .getFilteredNotificationsV4(state)({ sortOrder: 'desc' })
          .map(record => record.id)
      ).toEqual([1]);
    });

    it('still counts it in the unread badge', () => {
      expect(getters.getUnreadCount(state)).toBe(2);
      expect(getters.getHasUnreadNotifications(state)).toBe(true);
    });
  });
});
