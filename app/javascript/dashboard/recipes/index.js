// Lynomia starter recipes (docs/usability/10-recipe-architecture.md).
//
// A recipe is a ready-made configuration for an object the product already has: a flow bot's graph, an automation
// rule, or a shared audience's conditions. It is source code, not a record: the catalogues live in this folder, are
// versioned with the repository, and are created through the same APIs, the same policies and the same server-side
// validation as a hand-built object. There is no recipes table, no recipes endpoint, and no runtime link between a
// created object and the recipe it came from — once created it is an ordinary object with no restrictions.
//
// The manifest contract every recipe satisfies:
//
//   id            stable, snake_case, unique within its type; used in test names and in a created flow's description
//   type          'audience' | 'automation' | 'flow'
//   version       bumped when `build` changes. Objects already created are never touched (§18 of the brief)
//   name          i18n key for the title shown in the gallery
//   description   i18n key for the one-line explanation
//   category      one of CATEGORIES
//   requires      REQUIREMENT keys the account must satisfy before the recipe can be used
//   providerNote  optional i18n key, for a starter whose usefulness depends on what the store platform reports. The
//                 four platforms do not report the same things — WooCommerce has no shipped or delivered order status
//                 at all, Shopify has no cancelled one, Salla cannot look an order up by its number — so a starter
//                 that depends on one says which platforms report it, where the choice is made. Shown, never enforced:
//                 an account can connect a second platform tomorrow, and the created object keeps working.
//   inputs        the account-specific values the wizard asks for, in order (see INPUT_TYPES)
//   build         (values, context) -> the payload for that type's own create call. Pure: no requests, no ids but the
//                 ones the user chose from their own account
//
// Adding an AI, CRM or SLA recipe later needs a new `requires` key and, for a flow, nodes that exist by then. The
// contract itself does not change.

export const CATEGORIES = {
  SUPPORT: 'support',
  ECOMMERCE: 'ecommerce',
  RETENTION: 'retention',
  OPERATIONS: 'operations',
  INTEGRATIONS: 'integrations',
};

// What an account must have. Each is answered from data the dashboard already holds — see `useRecipeContext`.
export const REQUIREMENTS = {
  COMMERCE: 'commerce',
  COMMERCE_STORE: 'commerce_store',
  COMMERCE_CURRENCY: 'commerce_currency',
  FLOW_BUILDER: 'flow_builder',
  AUTOMATIONS: 'automations',
  CONTACT_FILTER: 'contact_filter',
  SHARED_AUDIENCE: 'shared_audience',
  TEAM: 'team',
  LABEL: 'label',
  WEBHOOKS: 'webhooks',
};

// The controls the wizard knows how to render. Every option list comes from the current account.
export const INPUT_TYPES = {
  TEAM: 'team',
  LABELS: 'labels',
  AUDIENCE: 'audience',
  STORE: 'store',
  CURRENCY: 'currency',
  NUMBER: 'number',
  PRIORITY: 'priority',
  LANGUAGE: 'language',
  COMMERCE_EVENT: 'commerce_event',
  URL: 'url',
};

export const RECIPE_STATUS = {
  AVAILABLE: 'available',
  REQUIRES_SETUP: 'requires_setup',
};

/**
 * Finishes a contact-filter or automation condition list the way the builders save one: every condition joins with
 * the next through `and`, and the last one carries no operator.
 * @param {Array} conditions - Conditions without their `query_operator`.
 * @returns {Array} The conditions, ready to save.
 */
export const joinConditions = conditions =>
  conditions.map((condition, index) => ({
    ...condition,
    query_operator: index === conditions.length - 1 ? null : 'and',
  }));
