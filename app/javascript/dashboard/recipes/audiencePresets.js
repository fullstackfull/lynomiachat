// Audience presets (docs/usability/13-audience-presets.md). Each builds the `query` of a normal contact filter —
// `{ payload: [conditions] }`, the same shape the filter builder saves — which is then created through the same
// `custom_filters` call as "save these filters as an audience". The audience stays dynamic: nothing is copied, no
// members are stored, and it is evaluated again every time it is opened, counted or sent to.
//
// Every preset here reads Commerce data Lynomia already holds locally (`commerce_customer_links` and their
// `commerce_contact_metrics`), so evaluating one makes no call to WooCommerce, Salla, Zid or Shopify.
//
// Money is per currency and never converted, so a spend preset asks which currency it means. Thresholds are the
// user's: "VIP" is not a number this file may choose (§10 of the brief).

import { CATEGORIES, INPUT_TYPES, REQUIREMENTS, joinConditions } from './index';

const PREFIX = 'RECIPES.AUDIENCE';

const commerceCondition = (attributeKey, filterOperator, values = []) => ({
  attribute_key: attributeKey,
  filter_operator: filterOperator,
  attribute_model: 'commerce',
  values,
});

const preset = ({ id, category, requires, inputs = [], conditions }) => ({
  id,
  type: 'audience',
  version: 1,
  name: `${PREFIX}.${id.toUpperCase()}.NAME`,
  description: `${PREFIX}.${id.toUpperCase()}.DESCRIPTION`,
  category,
  requires: [REQUIREMENTS.CONTACT_FILTER, ...requires],
  inputs,
  build: values => ({ payload: joinConditions(conditions(values)) }),
});

export const AUDIENCE_PRESETS = [
  preset({
    id: 'high_value_buyers',
    category: CATEGORIES.RETENTION,
    requires: [REQUIREMENTS.COMMERCE, REQUIREMENTS.COMMERCE_CURRENCY],
    inputs: [
      { key: 'currency', type: INPUT_TYPES.CURRENCY, required: true },
      {
        key: 'amount',
        type: INPUT_TYPES.NUMBER,
        required: true,
        default: 1000,
        min: 0,
      },
    ],
    conditions: ({ currency, amount }) => [
      commerceCondition(
        `commerce_spend_${String(currency).toLowerCase()}`,
        'is_greater_than',
        [String(amount)]
      ),
    ],
  }),
  preset({
    id: 'repeat_buyers',
    category: CATEGORIES.RETENTION,
    requires: [REQUIREMENTS.COMMERCE],
    inputs: [
      {
        key: 'orders',
        type: INPUT_TYPES.NUMBER,
        required: true,
        default: 1,
        min: 0,
      },
    ],
    conditions: ({ orders }) => [
      commerceCondition('commerce_orders_count', 'is_greater_than', [
        String(orders),
      ]),
    ],
  }),
  preset({
    id: 'recent_buyers',
    category: CATEGORIES.RETENTION,
    requires: [REQUIREMENTS.COMMERCE],
    inputs: [
      {
        key: 'days',
        type: INPUT_TYPES.NUMBER,
        required: true,
        default: 30,
        min: 1,
        max: 998,
      },
    ],
    conditions: ({ days }) => [
      commerceCondition('commerce_last_purchase_at', 'days_before', [
        String(days),
      ]),
    ],
  }),
  preset({
    id: 'customers_with_active_order',
    category: CATEGORIES.ECOMMERCE,
    requires: [REQUIREMENTS.COMMERCE],
    conditions: () => [
      commerceCondition('commerce_active_order', 'equal_to', ['true']),
    ],
  }),
  preset({
    id: 'customers_with_shipped_order',
    category: CATEGORIES.ECOMMERCE,
    requires: [REQUIREMENTS.COMMERCE],
    // The order's own status: the normalized shipment statuses are pending / in_transit / out_for_delivery /
    // delivered / failed / cancelled / returned / other, with no "shipped" among them.
    conditions: () => [
      commerceCondition('commerce_order_status', 'equal_to', ['shipped']),
    ],
  }),
  preset({
    id: 'store_customers',
    category: CATEGORIES.ECOMMERCE,
    requires: [REQUIREMENTS.COMMERCE, REQUIREMENTS.COMMERCE_STORE],
    inputs: [{ key: 'store', type: INPUT_TYPES.STORE, required: true }],
    conditions: ({ store }) => [
      commerceCondition('commerce_store', 'equal_to', [String(store)]),
    ],
  }),
  preset({
    id: 'linked_commerce_customers',
    category: CATEGORIES.ECOMMERCE,
    requires: [REQUIREMENTS.COMMERCE],
    conditions: () => [commerceCondition('commerce_store', 'is_present')],
  }),
];
