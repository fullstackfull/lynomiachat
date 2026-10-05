// Setup recipes: one answer that needs more than one object (docs/product-enablement/18-setup-recipes.md).
//
// Every other catalogue builds one object. Some of what a merchant actually asks for does not fit in one: "route my
// best customers to a dedicated team" is a shared audience AND an automation rule that references it, and today that
// is two galleries in two modules, in an order nobody is told. So the recipe contract gains an optional `steps`
// array, and nothing else changes: each step is still an ordinary payload created through that object's ordinary
// endpoint, in order, with a later step able to read the id an earlier one produced.
//
// What this is NOT: an orchestrator, a transaction, or a link between the created objects. The page runs the steps
// one after another with the same store actions it already uses. If a later step fails, the earlier objects exist and
// are ordinary objects — the page says which were created, because a half-finished setup the user cannot see is
// worse than a failed one they can.
//
// These live in the automation gallery rather than one of their own: somebody who wants their VIPs routed is looking
// for the routing, not for the audience it needs. Creating a shared audience and an automation rule are both
// administrator-only, and the automation page is administrator-only, so the permissions line up at the entry point.

import { CATEGORIES, INPUT_TYPES, REQUIREMENTS, joinConditions } from './index';

const PREFIX = 'RECIPES.SETUP';

const condition = (attributeKey, filterOperator, values) => ({
  attribute_key: attributeKey,
  filter_operator: filterOperator,
  values,
});

const action = (actionName, actionParams) => ({
  action_name: actionName,
  action_params: actionParams,
});

const setup = ({ id, category, requires, inputs, steps }) => ({
  id,
  type: 'setup',
  version: 1,
  name: `${PREFIX}.${id.toUpperCase()}.NAME`,
  description: `${PREFIX}.${id.toUpperCase()}.DESCRIPTION`,
  category,
  requires: [REQUIREMENTS.AUTOMATIONS, ...requires],
  inputs,
  // In order. Each step names the object it creates, the i18n key for its name, and a pure `build` that receives the
  // wizard's values and the steps already created, keyed by their own `key`.
  steps: steps.map(step => ({
    ...step,
    name: `${PREFIX}.${id.toUpperCase()}.${step.key.toUpperCase()}_NAME`,
  })),
});

export const SETUP_RECIPES = [
  setup({
    id: 'spend_audience_routing',
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
      { key: 'team', type: INPUT_TYPES.TEAM, required: true },
      {
        key: 'priority',
        type: INPUT_TYPES.PRIORITY,
        required: true,
        default: 'high',
      },
    ],
    steps: [
      {
        key: 'audience',
        type: 'audience',
        // The same conditions the `high_value_buyers` preset saves, and the same shape the filter builder writes.
        // Spend is per currency and never converted, which is why the currency is asked for.
        build: ({ currency, amount }) => ({
          shared: true,
          query: {
            payload: joinConditions([
              {
                ...condition(
                  `commerce_spend_${String(currency).toLowerCase()}`,
                  'is_greater_than',
                  [String(amount)]
                ),
                attribute_model: 'commerce',
              },
            ]),
          },
        }),
      },
      {
        key: 'rule',
        type: 'automation',
        // The audience the first step created, by the id the server gave it. Nothing is guessed: if the first step
        // did not return an id, the page never gets here.
        build: (values, created) => ({
          event_name: 'conversation_created',
          conditions: joinConditions([
            condition('contact_audience', 'equal_to', [created.audience.id]),
          ]),
          actions: [
            action('change_priority', [values.priority]),
            action('assign_team', [values.team]),
          ],
          // Reviewed before it runs, as every recipe-built rule is.
          active: false,
        }),
      },
    ],
  }),
];
