import types from '../../mutation-types';
import NotificationsAPI from '../../../api/notifications';

export const actions = {
  index: async ({ commit }, { page = 1, status, type, sortOrder } = {}) => {
    commit(types.SET_NOTIFICATIONS_UI_FLAG, { isFetching: true });
    try {
      const {
        data: {
          data: { payload, meta },
        },
      } = await NotificationsAPI.get({
        page,
        status,
        type,
        sortOrder,
      });
      commit(types.SET_NOTIFICATIONS, payload);
      commit(types.SET_NOTIFICATIONS_META, meta);
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isFetching: false });
      if (payload.length < 15) {
        commit(types.SET_ALL_NOTIFICATIONS_LOADED);
      }
    } catch (error) {
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isFetching: false });
    }
  },
  unReadCount: async ({ commit } = {}) => {
    commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdatingUnreadCount: true });
    try {
      const { data } = await NotificationsAPI.getUnreadCount();
      commit(types.SET_NOTIFICATIONS_UNREAD_COUNT, data);
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdatingUnreadCount: false });
    } catch (error) {
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdatingUnreadCount: false });
    }
  },
  // The unread count is this module's OWN state, so it is read from state here rather than accepted from
  // the caller. Asking callers to hand the counter back in is what broke the badge twice: InboxView read
  // `primary_actor.meta.unreadCount`, a key the conversation payload has never carried, and `delete` read
  // `unreadCount` from callers that send `unread_count`. Both arrived `undefined`, `undefined - 1` is NaN,
  // and the clamp tests `count < 0`, which is false for NaN -- so NaN reached meta and the badge vanished.
  //
  // Whether the notification was unread is read from the stored record, not from the caller's copy: the
  // Inbox list renders camelCased notifications (`readAt`) while the websocket path stores raw ones
  // (`read_at`), and only the record in `records` is in one known shape.
  read: async (
    { commit, state, getters },
    { id, primaryActorType, primaryActorId }
  ) => {
    commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: true });
    try {
      await NotificationsAPI.read(primaryActorType, primaryActorId);
      // Re-reading an already-read notification used to decrement anyway, under-counting until the next
      // refetch -- and the Inbox conversation view never refetches.
      if (!getters.getNotification(id).read_at) {
        commit(
          types.SET_NOTIFICATIONS_UNREAD_COUNT,
          state.meta.unreadCount - 1
        );
      }
      commit(types.READ_NOTIFICATION, { id, read_at: new Date() });
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false });
    } catch (error) {
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false });
    }
  },
  unread: async ({ commit }, { id }) => {
    commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: true });
    try {
      await NotificationsAPI.unRead(id);
      commit(types.READ_NOTIFICATION, { id, read_at: null });
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false });
    } catch (error) {
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false });
    }
  },
  readAll: async ({ commit }) => {
    commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: true });
    try {
      await NotificationsAPI.readAll();
      commit(types.SET_NOTIFICATIONS_UNREAD_COUNT, 0);
      commit(types.UPDATE_ALL_NOTIFICATIONS);
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false });
    } catch (error) {
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false });
      throw new Error(error);
    }
  },

  delete: async ({ commit, state, getters }, { notification }) => {
    commit(types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: true });
    try {
      await NotificationsAPI.delete(notification.id);
      const wasUnread = !getters.getNotification(notification.id).read_at;
      // One commit, with the keys DELETE_NOTIFICATION actually reads: it writes both meta values itself,
      // so a separate SET_NOTIFICATIONS_UNREAD_COUNT before it would simply be overwritten. The floors
      // matter because the counts come from the server and the list is paginated: deleting a row the
      // server has already stopped counting must not push the badge below zero.
      commit(types.DELETE_NOTIFICATION, {
        notification,
        unread_count: wasUnread
          ? Math.max(state.meta.unreadCount - 1, 0)
          : state.meta.unreadCount,
        count: Math.max(state.meta.count - 1, 0),
      });
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: false });
    } catch (error) {
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: false });
    }
  },

  deleteAllRead: async ({ commit }) => {
    commit(types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: true });
    try {
      await NotificationsAPI.deleteAll({
        type: 'read',
      });
      commit(types.DELETE_READ_NOTIFICATIONS);
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: false });
    } catch (error) {
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: false });
    }
  },
  deleteAll: async ({ commit }) => {
    commit(types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: true });
    try {
      await NotificationsAPI.deleteAll({
        type: 'all',
      });
      commit(types.DELETE_ALL_NOTIFICATIONS);
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: false });
    } catch (error) {
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isDeleting: false });
    }
  },

  snooze: async ({ commit }, { id, snoozedUntil }) => {
    commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: true });
    try {
      const response = await NotificationsAPI.snooze({
        id,
        snoozedUntil,
      });

      const {
        data: { snoozed_until = null },
      } = response;
      commit(types.SNOOZE_NOTIFICATION, {
        id,
        snoozed_until,
      });
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false });
    } catch (error) {
      commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false });
    }
  },

  updateNotification: async ({ commit }, data) => {
    commit(types.UPDATE_NOTIFICATION, data);
  },

  addNotification({ commit }, data) {
    commit(types.ADD_NOTIFICATION, data);
  },
  deleteNotification({ commit }, data) {
    commit(types.DELETE_NOTIFICATION, data);
  },
  clear({ commit }) {
    commit(types.CLEAR_NOTIFICATIONS);
  },

  setNotificationFilters: ({ commit }, filters) => {
    commit(types.SET_NOTIFICATION_FILTERS, filters);
  },
  updateNotificationFilters: ({ commit }, filters) => {
    commit(types.UPDATE_NOTIFICATION_FILTERS, filters);
  },
};
