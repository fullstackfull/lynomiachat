// Opening a contact keeps the list it was opened from: the detail view has a route per context
// (dashboard/routes/dashboard/contacts/routes.js), and pushing the plain `contacts_edit` from a label or
// segment page drops the param that context depends on.

const DETAIL_ROUTES = {
  contacts_dashboard_segments_index: ['contacts_edit_segment', 'segmentId'],
  contacts_dashboard_labels_index: ['contacts_edit_label', 'label'],
};

/**
 * The route to a contact's detail page, in the context of the list currently shown.
 * @param {number|string} contactId - The contact to open.
 * @param {Object} route - The current `vue-router` route.
 * @returns {Object} A location for `router.push`.
 */
export const contactDetailRoute = (contactId, route) => {
  const [name, paramKey] = DETAIL_ROUTES[route.name] || ['contacts_edit'];

  return {
    name,
    params: {
      contactId,
      ...(paramKey && { [paramKey]: route.params[paramKey] }),
    },
    query: route.query,
  };
};
