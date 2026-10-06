// A readable one-line answer to "who is in this audience?" (docs/product-enablement/13-audience-ux-implementation.md).
//
// A shared audience is a saved contact filter: its whole definition is the `query` the serializer already sends with
// every record (`app/views/api/v1/models/_custom_filter.json.jbuilder:4`). So a summary costs no request — it is the
// stored conditions read back through the same attribute and operator vocabulary the filter builder uses, which is
// where the translated names already live. Nothing here fetches, counts, or asks a provider anything.

const MAX_LISTED_VALUES = 3;

/**
 * The conditions of a saved filter's query, whatever shape it arrived in.
 * A query is `{ payload: [...] }`, but a record that has never been saved through the builder can carry a bare array.
 * @param {Object|Array} query - A custom filter's `query`.
 * @returns {Array} The conditions.
 */
export const conditionsOf = query => {
  if (Array.isArray(query)) return query;
  return Array.isArray(query?.payload) ? query.payload : [];
};

/**
 * How many conditions an audience asks about. This is the honest measure of "how complicated is this one?", and it is
 * the only number available without evaluating the filter.
 * @param {Object|Array} query - A custom filter's `query`.
 * @returns {number} The condition count.
 */
export const conditionCount = query => conditionsOf(query).length;

const valueLabel = (value, attribute) => {
  // A multi-select condition stores plain ids; the builder's own option list is what turns one back into a name.
  const option = (attribute?.options || []).find(
    item => String(item.id ?? item.value) === String(value?.id ?? value)
  );
  if (option) return option.name ?? option.label ?? String(value);

  if (value && typeof value === 'object') {
    return String(value.name ?? value.title ?? value.id ?? '');
  }
  return String(value);
};

/**
 * One condition, as a sentence fragment: the attribute's name, the operator's name, then its values.
 * An attribute the builder does not know (a custom attribute that has since been deleted, say) keeps its raw key
 * rather than disappearing — a summary that silently drops a condition would misdescribe the audience.
 * @param {Object} condition - A stored condition.
 * @param {Array} filterTypes - The builder's attribute vocabulary.
 * @returns {string} The fragment.
 */
export const summariseCondition = (condition, filterTypes = []) => {
  const attribute = filterTypes.find(
    type => type.attributeKey === condition?.attribute_key
  );
  const name = attribute?.attributeName || condition?.attribute_key || '';

  const operator = (attribute?.filterOperators || []).find(
    item => item.value === condition?.filter_operator
  );
  const operatorName = operator?.label || condition?.filter_operator || '';

  const values = Array.isArray(condition?.values)
    ? condition.values
    : [condition?.values].filter(value => value !== undefined && value !== '');

  const named = values
    .filter(value => value !== null && value !== undefined && value !== '')
    .map(value => valueLabel(value, attribute));

  const shown = named.slice(0, MAX_LISTED_VALUES).join(', ');
  const rest = named.length - MAX_LISTED_VALUES;
  const listed = rest > 0 ? `${shown} +${rest}` : shown;

  return [name, operatorName, listed].filter(Boolean).join(' ');
};

/**
 * The whole audience in one line.
 * @param {Object|Array} query - A custom filter's `query`.
 * @param {Array} filterTypes - The builder's attribute vocabulary.
 * @param {Object} [options]
 * @param {number} [options.limit] - Summarise at most this many conditions, then say how many are left.
 * @param {string} [options.andLabel] - The translated word joining two conditions.
 * @param {Function} [options.moreLabel] - (count) => the translated "+N more" tail.
 * @returns {string} The summary, or '' when the audience has no conditions at all.
 */
export const summariseAudience = (query, filterTypes = [], options = {}) => {
  const { limit, andLabel = 'and', moreLabel } = options;
  const conditions = conditionsOf(query);
  if (!conditions.length) return '';

  const shown = limit ? conditions.slice(0, limit) : conditions;
  const summary = shown
    .map(condition => summariseCondition(condition, filterTypes))
    .filter(Boolean)
    .join(` ${andLabel} `);

  const rest = conditions.length - shown.length;
  if (rest > 0 && moreLabel) return `${summary} ${moreLabel(rest)}`;
  return summary;
};
