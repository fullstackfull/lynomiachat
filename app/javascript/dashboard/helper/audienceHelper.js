// Lynomia shared audiences across modules (docs/usability/04-implemented-productivity-features.md §cross-module
// actions). An audience is a shared contact filter (`CustomFilter`, `filter_type: contact`, `shared: true`), so
// "use this audience over there" needs no new record and no new API: the target page's route carries the audience id,
// reads it, prefills its own form and clears the query. Nothing is created on the way, and the target page keeps its
// own permissions, its own validation and the server's.

export const AUDIENCE_QUERY_PARAM = 'audience';

/**
 * The audience id a route query names, when it names one at all.
 * @param {Object} query - A route query object.
 * @returns {number|null} The id, or null when the query has none or it is not a positive integer.
 */
export const audienceIdFromQuery = query => {
  const raw = query?.[AUDIENCE_QUERY_PARAM];
  // A repeated query parameter arrives as an array, and `Number(['3'])` is 3: only a single value counts.
  if (typeof raw !== 'string' && typeof raw !== 'number') return null;

  const id = Number(raw);
  return Number.isInteger(id) && id > 0 ? id : null;
};

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
