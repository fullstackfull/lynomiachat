import types from '../../mutation-types';
import * as Sentry from '@sentry/vue';

export const mutations = {
  [types.SET_CONTACT_UI_FLAG]($state, data) {
    $state.uiFlags = {
      ...$state.uiFlags,
      ...data,
    };
  },

  [types.CLEAR_CONTACTS]: $state => {
    $state.records = {};
    $state.sortOrder = [];
  },

  [types.SET_CONTACT_META]: ($state, data) => {
    const { count, current_page: currentPage, has_more: hasMore } = data;
    $state.meta.count = count;
    $state.meta.currentPage = currentPage;
    if (hasMore !== undefined) {
      $state.meta.hasMore = hasMore;
    }
  },

  [types.APPEND_CONTACTS]: ($state, data) => {
    data.forEach(contact => {
      $state.records[contact.id] = {
        ...($state.records[contact.id] || {}),
        ...contact,
      };
      if (!$state.sortOrder.includes(contact.id)) {
        $state.sortOrder.push(contact.id);
      }
    });
  },

  [types.SET_CONTACTS]: ($state, data) => {
    const sortOrder = data.map(contact => {
      $state.records[contact.id] = {
        ...($state.records[contact.id] || {}),
        ...contact,
      };
      return contact.id;
    });
    $state.sortOrder = sortOrder;
  },

  [types.SET_CONTACT_ITEM]: ($state, data) => {
    $state.records[data.id] = {
      ...($state.records[data.id] || {}),
      ...data,
    };

    if (!$state.sortOrder.includes(data.id)) {
      $state.sortOrder.push(data.id);
    }
  },

  // The same write without joining the rendered list. `sortOrder` IS the list (getters.js:5), and it is the
  // server that decides both whether a contact belongs in the current view — /contacts itself only returns
  // contacts with an email, phone or identifier (Contact.resolved_contacts) — and where it sorts, since a new
  // contact has no last_activity_at and the order is NULLS LAST. So a contact the client has just learned
  // about goes into `records`, and the list is refreshed from the server rather than guessed at.
  [types.SET_CONTACT_RECORD]: ($state, data) => {
    $state.records[data.id] = {
      ...($state.records[data.id] || {}),
      ...data,
    };
  },

  // Merged, not replaced. This mutation is driven by the `contact.updated` websocket push, whose payload is
  // `Contact#push_event_data` — which carries no `last_activity_at`, no `availability_status`, no `created_at`
  // and no `labels`. Replacing the record wholesale therefore deleted all four from a row the list was already
  // showing, so a labelled contact lost its sort timestamp the moment anything touched it.
  [types.EDIT_CONTACT]: ($state, data) => {
    $state.records[data.id] = {
      ...($state.records[data.id] || {}),
      ...data,
    };
  },

  [types.SET_CONTACT_ATTACHMENTS]: ($state, { id, data }) => {
    if (!$state.records[id]) $state.records[id] = {};
    $state.records[id].attachments = data;
  },

  [types.DELETE_CONTACT]: ($state, id) => {
    // `findIndex` returns -1 for a contact that is not in the rendered list, and `splice(-1, 1)` removes the
    // LAST entry — so deleting a contact the current page does not show used to silently drop an unrelated row
    // from it. A websocket `contact.deleted` for any contact in the account reaches this.
    const index = $state.sortOrder.indexOf(id);
    if (index !== -1) $state.sortOrder.splice(index, 1);
    delete $state.records[id];
  },

  [types.UPDATE_CONTACTS_PRESENCE]: ($state, data) => {
    Object.values($state.records).forEach(element => {
      let availabilityStatus;
      try {
        availabilityStatus = data[element.id];
      } catch (error) {
        Sentry.setContext('contact is undefined', {
          records: $state.records,
          data: data,
        });
        Sentry.captureException(error);

        return;
      }
      if (availabilityStatus) {
        $state.records[element.id].availability_status = availabilityStatus;
      } else {
        $state.records[element.id].availability_status = null;
      }
    });
  },

  [types.SET_CONTACT_FILTERS](_state, data) {
    _state.appliedFilters = data;
  },

  [types.CLEAR_CONTACT_FILTERS](_state) {
    _state.appliedFilters = [];
  },
};
