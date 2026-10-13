import { sortComparator, isRenderableInFeed } from './helpers';
import camelcaseKeys from 'camelcase-keys';

// Both feed getters drop the rows the feed cannot render, BEFORE camelCasing, because the filter reads the
// raw `primary_actor_type` the API sends. See `isRenderableInFeed` for why exclusion is the fix and why the
// unread badge is deliberately not affected by it.
const renderableRecords = $state =>
  Object.values($state.records).filter(isRenderableInFeed);

export const getters = {
  getFilteredNotifications: $state => filters => {
    const sortOrder = filters.sortOrder === 'desc' ? 'newest' : 'oldest';
    const sortedNotifications = renderableRecords($state).sort((n1, n2) =>
      sortComparator(n1, n2, sortOrder)
    );
    return sortedNotifications;
  },
  getFilteredNotificationsV4: $state => filters => {
    const sortOrder = filters.sortOrder === 'desc' ? 'newest' : 'oldest';
    const sortedNotifications = renderableRecords($state).sort((n1, n2) =>
      sortComparator(n1, n2, sortOrder)
    );
    return camelcaseKeys(sortedNotifications, { deep: true });
  },
  getNotificationById: $state => id => {
    return $state.records[id] || {};
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getNotification: $state => id => {
    const notification = $state.records[id];
    return notification || {};
  },
  getMeta: $state => {
    return $state.meta;
  },
  getNotificationFilters($state) {
    return $state.notificationFilters;
  },
  getHasUnreadNotifications: $state => {
    return $state.meta.unreadCount > 0;
  },
  getUnreadCount: $state => {
    return $state.meta.unreadCount;
  },
};
