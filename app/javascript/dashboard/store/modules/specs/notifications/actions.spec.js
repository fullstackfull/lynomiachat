import axios from 'axios';
import { actions } from '../../notifications/actions';
import types from '../../../mutation-types';
const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  describe('#index', () => {
    it('sends correct actions if API is success', async () => {
      axios.get.mockResolvedValue({
        data: {
          data: {
            payload: [{ id: 1 }],
            meta: { count: 3, current_page: 1, unread_count: 2 },
          },
        },
      });
      await actions.index({ commit });
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isFetching: true }],
        [types.SET_NOTIFICATIONS, [{ id: 1 }]],
        [
          types.SET_NOTIFICATIONS_META,
          { count: 3, current_page: 1, unread_count: 2 },
        ],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isFetching: false }],
        [types.SET_ALL_NOTIFICATIONS_LOADED],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await actions.index({ commit });
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isFetching: true }],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#unReadCount', () => {
    it('sends correct actions if API is success', async () => {
      axios.get.mockResolvedValue({ data: 1 });
      await actions.unReadCount({ commit });
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdatingUnreadCount: true }],
        [types.SET_NOTIFICATIONS_UNREAD_COUNT, 1],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdatingUnreadCount: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await actions.unReadCount({ commit });
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdatingUnreadCount: true }],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdatingUnreadCount: false }],
      ]);
    });
  });

  describe('#read', () => {
    it('sends correct actions if API is success', async () => {
      axios.post.mockResolvedValue({});
      await actions.read(
        {
          commit,
          state: { meta: { count: 3, currentPage: 1, unreadCount: 2 } },
          getters: { getNotification: () => ({ id: 1, read_at: null }) },
        },
        { id: 1, primaryActorId: 1 }
      );
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: true }],
        [types.SET_NOTIFICATIONS_UNREAD_COUNT, 1],
        [types.READ_NOTIFICATION, { id: 1, read_at: expect.any(Date) }],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false }],
      ]);
    });

    // Re-reading an already-read notification used to decrement regardless, under-counting the badge
    // until something refetched -- and the Inbox conversation view never refetches.
    it('leaves the unread count alone when the notification was already read', async () => {
      axios.post.mockResolvedValue({});
      await actions.read(
        {
          commit,
          state: { meta: { count: 3, currentPage: 1, unreadCount: 2 } },
          getters: {
            getNotification: () => ({ id: 1, read_at: '2026-10-12T00:00:00Z' }),
          },
        },
        { id: 1, primaryActorId: 1 }
      );
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: true }],
        [types.READ_NOTIFICATION, { id: 1, read_at: expect.any(Date) }],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false }],
      ]);
    });

    // The count comes from state, so a caller that knows nothing about it cannot corrupt it. The Inbox
    // conversation view used to read `primary_actor.meta.unreadCount`, a key the conversation payload
    // has never carried, and committed `undefined - 1` -- NaN, which the `count < 0` clamp let through.
    it('ignores an unread count handed in by the caller', async () => {
      axios.post.mockResolvedValue({});
      await actions.read(
        {
          commit,
          state: { meta: { count: 3, currentPage: 1, unreadCount: 7 } },
          getters: { getNotification: () => ({ id: 1, read_at: null }) },
        },
        { id: 1, primaryActorId: 1, unreadCount: undefined }
      );
      expect(commit).toHaveBeenCalledWith(
        types.SET_NOTIFICATIONS_UNREAD_COUNT,
        6
      );
    });

    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.read({ commit })).rejects.toThrow(Error);
      await actions.read(
        {
          commit,
          state: { meta: { count: 3, currentPage: 1, unreadCount: 2 } },
          getters: { getNotification: () => ({ id: 1, read_at: null }) },
        },
        { id: 1, primaryActorId: 1 }
      );
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: true }],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false }],
      ]);
    });
  });

  describe('#unread', () => {
    it('sends correct actions if API is success', async () => {
      axios.post.mockResolvedValue({});
      await actions.unread({ commit }, { id: 1 });
      expect(commit.mock.calls).toEqual([
        ['SET_NOTIFICATIONS_UI_FLAG', { isUpdating: true }],
        ['READ_NOTIFICATION', { id: 1, read_at: null }],
        ['SET_NOTIFICATIONS_UI_FLAG', { isUpdating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.unread({ commit })).rejects.toThrow(Error);
      await actions.unread({ commit }, { id: 1 });
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: true }],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false }],
      ]);
    });
  });

  describe('#delete', () => {
    // The payload keys here ARE the regression: DELETE_NOTIFICATION reads `unread_count`, and the action
    // used to hand it `unreadCount`, so the mutation wrote `undefined` straight into meta and the badge
    // disappeared while unread notifications remained.
    it('sends correct actions if API is success', async () => {
      axios.delete.mockResolvedValue({});
      await actions.delete(
        {
          commit,
          state: { meta: { count: 2, currentPage: 1, unreadCount: 1 } },
          getters: { getNotification: () => ({ id: 1, read_at: null }) },
        },
        { notification: { id: 1 } }
      );

      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: true }],
        [
          types.DELETE_NOTIFICATION,
          { notification: { id: 1 }, unread_count: 0, count: 1 },
        ],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: false }],
      ]);
    });

    it('lowers the total but not the unread count when the notification was read', async () => {
      axios.delete.mockResolvedValue({});
      await actions.delete(
        {
          commit,
          state: { meta: { count: 4, currentPage: 1, unreadCount: 2 } },
          getters: {
            getNotification: () => ({ id: 1, read_at: '2026-10-12T00:00:00Z' }),
          },
        },
        { notification: { id: 1 } }
      );

      expect(commit).toHaveBeenCalledWith(types.DELETE_NOTIFICATION, {
        notification: { id: 1 },
        unread_count: 2,
        count: 3,
      });
    });

    // The list is paginated and the counts are the server's, so deleting a row the server has already
    // stopped counting must not push either number negative.
    it('floors both counts at zero', async () => {
      axios.delete.mockResolvedValue({});
      await actions.delete(
        {
          commit,
          state: { meta: { count: 0, currentPage: 1, unreadCount: 0 } },
          getters: { getNotification: () => ({ id: 1, read_at: null }) },
        },
        { notification: { id: 1 } }
      );

      expect(commit).toHaveBeenCalledWith(types.DELETE_NOTIFICATION, {
        notification: { id: 1 },
        unread_count: 0,
        count: 0,
      });
    });

    // The deleted record's own copy is not consulted: the Inbox list renders camelCased notifications
    // (`readAt`), so reading `read_at` off the caller's object would call every deleted row unread.
    it('reads the read state from the store, not from the caller object', async () => {
      axios.delete.mockResolvedValue({});
      await actions.delete(
        {
          commit,
          state: { meta: { count: 2, currentPage: 1, unreadCount: 1 } },
          getters: {
            getNotification: () => ({ id: 1, read_at: '2026-10-12T00:00:00Z' }),
          },
        },
        { notification: { id: 1, readAt: '2026-10-12T00:00:00Z' } }
      );

      expect(commit).toHaveBeenCalledWith(types.DELETE_NOTIFICATION, {
        notification: { id: 1, readAt: '2026-10-12T00:00:00Z' },
        unread_count: 1,
        count: 1,
      });
    });

    it('sends correct actions if API is error', async () => {
      axios.delete.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.delete({ commit })).rejects.toThrow(Error);
      await actions.delete(
        {
          commit,
          state: { meta: { count: 2, currentPage: 1, unreadCount: 1 } },
          getters: { getNotification: () => ({ id: 1, read_at: null }) },
        },
        { notification: { id: 1 } }
      );
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: true }],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: false }],
      ]);
    });
  });
  describe('#readAll', () => {
    it('sends correct actions if API is success', async () => {
      axios.post.mockResolvedValue({ data: 1 });
      await actions.readAll({ commit });
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: true }],
        [types.SET_NOTIFICATIONS_UNREAD_COUNT, 0],
        [types.UPDATE_ALL_NOTIFICATIONS],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.readAll({ commit })).rejects.toThrow(Error);
    });
  });
  describe('#addNotification', () => {
    it('sends correct actions if API is success', async () => {
      await actions.addNotification({ commit }, { data: 1 });
      expect(commit.mock.calls).toEqual([
        [types.ADD_NOTIFICATION, { data: 1 }],
      ]);
    });
  });

  describe('#deleteNotification', () => {
    it('sends correct actions', async () => {
      await actions.deleteNotification({ commit }, { data: 1 });
      expect(commit.mock.calls).toEqual([
        [types.DELETE_NOTIFICATION, { data: 1 }],
      ]);
    });
  });

  describe('clear', () => {
    it('sends correct actions', async () => {
      await actions.clear({ commit });
      expect(commit.mock.calls).toEqual([[types.CLEAR_NOTIFICATIONS]]);
    });
  });

  describe('deleteAllRead', () => {
    it('sends correct actions if API is success', async () => {
      axios.delete.mockResolvedValue({});
      await actions.deleteAllRead({ commit });
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: true }],
        [types.DELETE_READ_NOTIFICATIONS],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.delete.mockRejectedValue({ message: 'Incorrect header' });
      await actions.deleteAllRead({ commit });
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: true }],
        [types.DELETE_READ_NOTIFICATIONS],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: false }],
      ]);
    });
  });

  describe('deleteAll', () => {
    it('sends correct actions if API is success', async () => {
      axios.delete.mockResolvedValue({});
      await actions.deleteAll({ commit });
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: true }],
        [types.DELETE_ALL_NOTIFICATIONS],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.delete.mockRejectedValue({ message: 'Incorrect header' });
      await actions.deleteAll({ commit });
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: true }],
        [types.DELETE_ALL_NOTIFICATIONS],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: false }],
      ]);
    });
  });

  describe('snooze', () => {
    it('sends correct actions if API is success', async () => {
      axios.post.mockResolvedValue({
        data: { snoozed_until: '20 Jan, 5.04pm' },
      });
      await actions.snooze({ commit }, { id: 1, snoozedUntil: 1703057715 });
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: true }],
        [types.SNOOZE_NOTIFICATION, { id: 1, snoozed_until: '20 Jan, 5.04pm' }],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await actions.snooze({ commit }, { id: 1, snoozedUntil: 1703057715 });

      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: true }],
        [types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false }],
      ]);
    });
  });

  describe('setNotificationFilters', () => {
    it('set notification filters', async () => {
      const filters = {
        page: 1,
        status: 'read',
        type: 'all',
        sortOrder: 'desc',
      };
      await actions.setNotificationFilters({ commit }, filters);
      expect(commit.mock.calls).toEqual([
        [types.SET_NOTIFICATION_FILTERS, filters],
      ]);
    });
  });

  describe('updateNotificationFilters', () => {
    it('update notification filters', async () => {
      const filters = {
        page: 1,
        status: 'unread',
        type: 'all',
        sortOrder: 'desc',
      };
      await actions.updateNotificationFilters({ commit }, filters);
      expect(commit.mock.calls).toEqual([
        [types.UPDATE_NOTIFICATION_FILTERS, filters],
      ]);
    });
  });
});
