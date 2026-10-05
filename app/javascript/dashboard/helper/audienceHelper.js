// Lynomia shared audiences across modules (docs/usability/04-implemented-productivity-features.md §cross-module
// actions). An audience is a shared contact filter (`CustomFilter`, `filter_type: contact`, `shared: true`), so
// "use this audience over there" needs no new record and no new API: the target page's route carries the audience id,
// reads it, prefills its own form and clears the query. Nothing is created on the way, and the target page keeps its
// own permissions, its own validation and the server's.

export const AUDIENCE_QUERY_PARAM = 'audience';
// A label is the other recipient source a campaign accepts (`{ type: 'Label', id }`), so "use this over there"
// works the same way for one: the target page's route carries the id, reads it, prefills its own form and keeps
// its own permissions and validation. Nothing is created on the way.
export const LABEL_QUERY_PARAM = 'label';

// The other direction: a page that needs a shared audience sends the user to Contacts to build one, and names
// itself so Contacts can send them back. Only a route NAME travels, never a path or a URL, so the parameter
// cannot be used to point someone at somewhere else.
export const RETURN_TO_QUERY_PARAM = 'returnTo';

// The routes a Contacts return trip may land on. An unknown name is ignored and the user simply stays in
// Contacts with the audience they built.
const RETURN_ROUTES = ['campaigns_whatsapp_index', 'campaigns_sms_index'];

/**
 * The route that sends someone to Contacts to build an audience, remembering where they came from.
 * @param {string} returnRouteName - The route to come back to.
 * @returns {Object} A router location.
 */
export const audienceReturnRoute = returnRouteName => ({
  name: 'contacts_dashboard_index',
  query: { [RETURN_TO_QUERY_PARAM]: returnRouteName },
});

/**
 * The route name a Contacts visit should return to, when it is one this helper knows.
 * @param {Object} query - A route query object.
 * @returns {string|null} The route name, or null.
 */
export const returnRouteFromQuery = query => {
  const raw = query?.[RETURN_TO_QUERY_PARAM];
  return RETURN_ROUTES.includes(raw) ? raw : null;
};

const idFromQuery = (query, key) => {
  const raw = query?.[key];
  // A repeated query parameter arrives as an array, and `Number(['3'])` is 3: only a single value counts.
  if (typeof raw !== 'string' && typeof raw !== 'number') return null;

  const id = Number(raw);
  return Number.isInteger(id) && id > 0 ? id : null;
};

/**
 * The audience id a route query names, when it names one at all.
 * @param {Object} query - A route query object.
 * @returns {number|null} The id, or null when the query has none or it is not a positive integer.
 */
export const audienceIdFromQuery = query =>
  idFromQuery(query, AUDIENCE_QUERY_PARAM);

/**
 * The label id a route query names, when it names one at all.
 * @param {Object} query - A route query object.
 * @returns {number|null} The id, or null when the query has none or it is not a positive integer.
 */
export const labelIdFromQuery = query => idFromQuery(query, LABEL_QUERY_PARAM);

/**
 * One label of this account by id. An id that is not one of its labels resolves to undefined, so a prefill built
 * from it simply does not happen and the campaign form opens empty.
 * @param {Array} labels - The `labels/getLabels` records.
 * @param {number} id - The label id.
 * @returns {Object|undefined} The label.
 */
export const findAccountLabel = (labels, id) =>
  (labels || []).find(label => label.id === id);

/**
 * The account's shared audiences, from the contact filters the store already holds.
 * @param {Array} contactViews - The `customViews/getContactCustomViews` records.
 * @returns {Array} The shared ones.
 */
export const sharedAudiences = contactViews =>
  (contactViews || []).filter(view => view.shared);

/**
 * One shared audience of this account by id. An id that is not one — another account's, a personal filter, a guess —
 * resolves to undefined, so a prefill built from it simply does not happen.
 * @param {Array} contactViews - The `customViews/getContactCustomViews` records.
 * @param {number} id - The audience id.
 * @returns {Object|undefined} The audience.
 */
export const findSharedAudience = (contactViews, id) =>
  sharedAudiences(contactViews).find(view => view.id === id);

/**
 * The automation condition that means "the contact is in this shared audience", in the rule builder's own form shape
 * (a multi select condition holds its chosen options, and `filterQueryGenerator` turns them into ids on save).
 * @param {Object} audience - A shared audience record.
 * @returns {Object} The condition.
 */
export const audienceConditionFor = audience => ({
  attribute_key: 'contact_audience',
  filter_operator: 'equal_to',
  values: [{ id: audience.id, name: audience.name }],
  query_operator: 'and',
  custom_attribute_type: '',
});
