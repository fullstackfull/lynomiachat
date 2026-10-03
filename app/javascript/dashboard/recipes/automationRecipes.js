// Automation recipes (docs/usability/12-automation-recipes.md). Each builds the payload of a normal Chatwoot
// automation rule, created through the ordinary `automation_rules` call and therefore validated by the ordinary rule
// validation — including Lynomia's own checks that an audience is a shared one of this account and a store is this
// account's. The rule is created **disabled**: nothing runs until someone reads it and turns it on.
//
// Only triggers, conditions and actions the engine really has. Two of the brief's examples are therefore absent and
// recorded in docs/usability/09a-recipe-opportunity-study.md §7: there is no "order issue" event (the seven
// commerce_order_* transitions are the whole set), and a Commerce trigger may not send a customer message
// (Custom::AutomationRule::CUSTOMER_MESSAGE_ACTIONS), because a store event is not a customer message and the
// conversation may be outside WhatsApp's 24-hour window.

import { CATEGORIES, INPUT_TYPES, REQUIREMENTS, joinConditions } from './index';

const PREFIX = 'RECIPES.AUTOMATION';

// An automation condition carries only the keys the create endpoint permits.
const condition = (attributeKey, filterOperator, values) => ({
  attribute_key: attributeKey,
  filter_operator: filterOperator,
  values,
});

const action = (actionName, actionParams) => ({
  action_name: actionName,
  action_params: actionParams,
});

// A label the user did not choose adds no action at all, rather than an action with nothing in it.
const labelAction = labels =>
  labels?.length ? [action('add_label', labels)] : [];

const recipe = ({
  id,
  category,
  requires,
  inputs,
  event,
  conditions,
  actions,
}) => ({
  id,
  type: 'automation',
  version: 1,
  name: `${PREFIX}.${id.toUpperCase()}.NAME`,
  description: `${PREFIX}.${id.toUpperCase()}.DESCRIPTION`,
  category,
  requires: [REQUIREMENTS.AUTOMATIONS, ...requires],
  inputs,
  // The mechanical parts of the rule. The page that creates it adds the name and the description, as the flow list
  // does for a template.
  build: values => ({
    event_name: event(values),
    conditions: joinConditions(conditions(values)),
    actions: actions(values),
    // Reviewed before it runs: §20 of the brief, and the only safe default for a rule nobody has read yet.
    active: false,
  }),
});

const STORE_INPUT = { key: 'store', type: INPUT_TYPES.STORE, required: true };
const TEAM_INPUT = { key: 'team', type: INPUT_TYPES.TEAM, required: true };
const LABELS_INPUT = {
  key: 'labels',
  type: INPUT_TYPES.LABELS,
  required: false,
};
// Which store's events the rule handles. A single-store account has this filled in for it; a multi-store one must say.
const eventStore = ({ store }) => [
  condition('commerce_event_store', 'equal_to', [store]),
];

export const AUTOMATION_RECIPES = [
  recipe({
    id: 'commerce_new_order_routing',
    category: CATEGORIES.ECOMMERCE,
    requires: [
      REQUIREMENTS.COMMERCE,
      REQUIREMENTS.COMMERCE_STORE,
      REQUIREMENTS.TEAM,
    ],
    inputs: [STORE_INPUT, TEAM_INPUT, LABELS_INPUT],
    event: () => 'commerce_order_created',
    conditions: eventStore,
    actions: ({ team, labels }) => [
      ...labelAction(labels),
      action('assign_team', [team]),
    ],
  }),
  recipe({
    id: 'commerce_order_shipped_label',
    category: CATEGORIES.OPERATIONS,
    requires: [
      REQUIREMENTS.COMMERCE,
      REQUIREMENTS.COMMERCE_STORE,
      REQUIREMENTS.LABEL,
    ],
    inputs: [
      STORE_INPUT,
      { key: 'labels', type: INPUT_TYPES.LABELS, required: true },
    ],
    event: () => 'commerce_order_shipped',
    conditions: eventStore,
    actions: ({ labels }) => [action('add_label', labels)],
  }),
  recipe({
    id: 'commerce_refund_escalation',
    category: CATEGORIES.ECOMMERCE,
    requires: [
      REQUIREMENTS.COMMERCE,
      REQUIREMENTS.COMMERCE_STORE,
      REQUIREMENTS.TEAM,
    ],
    inputs: [STORE_INPUT, TEAM_INPUT, LABELS_INPUT],
    event: () => 'commerce_order_refunded',
    conditions: eventStore,
    actions: ({ team, labels }) => [
      action('change_priority', ['high']),
      action('assign_team', [team]),
      ...labelAction(labels),
    ],
  }),
  recipe({
    id: 'commerce_event_webhook',
    category: CATEGORIES.INTEGRATIONS,
    requires: [
      REQUIREMENTS.COMMERCE,
      REQUIREMENTS.COMMERCE_STORE,
      REQUIREMENTS.WEBHOOKS,
    ],
    inputs: [
      { key: 'event', type: INPUT_TYPES.COMMERCE_EVENT, required: true },
      STORE_INPUT,
      { key: 'url', type: INPUT_TYPES.URL, required: true },
    ],
    event: ({ event }) => event,
    conditions: eventStore,
    actions: ({ url }) => [action('send_webhook_event', [url])],
  }),
  recipe({
    id: 'vip_audience_priority',
    category: CATEGORIES.SUPPORT,
    requires: [REQUIREMENTS.SHARED_AUDIENCE, REQUIREMENTS.TEAM],
    inputs: [
      { key: 'audience', type: INPUT_TYPES.AUDIENCE, required: true },
      TEAM_INPUT,
      {
        key: 'priority',
        type: INPUT_TYPES.PRIORITY,
        required: true,
        default: 'high',
      },
      LABELS_INPUT,
    ],
    event: () => 'conversation_created',
    conditions: ({ audience }) => [
      condition('contact_audience', 'equal_to', [audience]),
    ],
    actions: ({ team, priority, labels }) => [
      action('change_priority', [priority]),
      action('assign_team', [team]),
      ...labelAction(labels),
    ],
  }),
  recipe({
    id: 'high_value_spend_routing',
    category: CATEGORIES.RETENTION,
    requires: [
      REQUIREMENTS.COMMERCE,
      REQUIREMENTS.COMMERCE_CURRENCY,
      REQUIREMENTS.TEAM,
    ],
    inputs: [
      { key: 'currency', type: INPUT_TYPES.CURRENCY, required: true },
      {
        key: 'amount',
        type: INPUT_TYPES.NUMBER,
        required: true,
        default: 1000,
        min: 0,
      },
      TEAM_INPUT,
      LABELS_INPUT,
    ],
    event: () => 'conversation_created',
    conditions: ({ currency, amount }) => [
      condition(
        `commerce_spend_${String(currency).toLowerCase()}`,
        'is_greater_than',
        [String(amount)]
      ),
    ],
    actions: ({ team, labels }) => [
      ...labelAction(labels),
      action('assign_team', [team]),
    ],
  }),
  recipe({
    id: 'active_order_routing',
    category: CATEGORIES.ECOMMERCE,
    requires: [REQUIREMENTS.COMMERCE, REQUIREMENTS.TEAM],
    inputs: [TEAM_INPUT, LABELS_INPUT],
    event: () => 'conversation_created',
    conditions: () => [
      condition('commerce_active_order', 'equal_to', ['true']),
    ],
    actions: ({ team, labels }) => [
      ...labelAction(labels),
      action('assign_team', [team]),
    ],
  }),
];
