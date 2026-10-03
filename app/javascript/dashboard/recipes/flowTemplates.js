// Flow templates (docs/usability/11-flow-templates.md). Each builds the graph of a normal flow bot — the same shape the
// builder saves and `Flows::GraphValidator` checks — from the teams, labels, audiences and language the user chose.
// Nothing here is a new engine: the created object is `AgentBot(bot_type: flow)` with one draft version, and it is
// published, tested, edited and connected to an inbox exactly like a hand-built flow.
//
// What the graphs may contain is fixed by the backend's own contract (`Flows::NodeTypes`): the node types, their
// outputs, which outputs must be connected, and each node's allowed data keys. An output left unconnected hands the
// conversation to humans when the runner takes it, which is why the optional ones are left alone on purpose.

import { CATEGORIES, INPUT_TYPES, REQUIREMENTS } from './index';
import { COPY, body, title } from './starterCopy';

const PREFIX = 'RECIPES.FLOW';
const COLUMN = 320;
const ROW = 170;

// Node ids are stable and readable, so a template's graph is the same every time and reviewable in the builder.
const node = (id, type, [column, row], data = {}) => ({
  id,
  type,
  position: { x: column * COLUMN, y: row * ROW },
  data,
});

const edge = (source, sourceHandle, target) => ({
  id: `${source}-${sourceHandle}`,
  source,
  sourceHandle,
  target,
});

const option = (id, language, pair) => ({ id, title: title(language, pair) });

const handoff = (id, position, { team, labels, reason }) =>
  node(id, 'handoff', position, {
    ...(team ? { team_id: team } : {}),
    ...(labels?.length ? { labels } : {}),
    reason,
  });

const template = ({
  id,
  category,
  requires,
  inputs,
  build,
  nodeCount,
  edgeCount,
}) => ({
  id,
  type: 'flow',
  version: 1,
  name: `${PREFIX}.${id.toUpperCase()}.NAME`,
  description: `${PREFIX}.${id.toUpperCase()}.DESCRIPTION`,
  category,
  requires: [REQUIREMENTS.FLOW_BUILDER, ...requires],
  inputs,
  build,
  // What the gallery and the docs quote as the work this template saves. Asserted against `build` in the specs.
  nodeCount,
  edgeCount,
});

const LANGUAGE_INPUT = {
  key: 'language',
  type: INPUT_TYPES.LANGUAGE,
  required: true,
  default: 'both',
};
const team = key => ({ key, type: INPUT_TYPES.TEAM, required: true });

export const FLOW_TEMPLATES = [
  template({
    id: 'commerce_order_tracking',
    category: CATEGORIES.ECOMMERCE,
    requires: [REQUIREMENTS.COMMERCE, REQUIREMENTS.TEAM],
    inputs: [team('team'), LANGUAGE_INPUT],
    nodeCount: 12,
    edgeCount: 19,
    build: ({ team: teamId, language }) => ({
      nodes: [
        node('start', 'start', [0, 2]),
        node('menu', 'buttons', [1, 2], {
          text: body(language, COPY.TRACKING.MENU),
          options: [
            option('track', language, COPY.TRACKING.TRACK),
            option('agent', language, COPY.TRACKING.TEAM),
          ],
          timeout_minutes: 60,
        }),
        node('lookup_latest', 'commerce_lookup', [2, 1], {
          mode: 'latest_order',
        }),
        node('show_latest', 'send_message', [3, 0], {
          text: body(language, COPY.TRACKING.LATEST),
        }),
        node('ask_more', 'buttons', [4, 0], {
          text: body(language, COPY.TRACKING.ANYTHING_ELSE),
          options: [
            option('done', language, COPY.TRACKING.DONE),
            option('more_help', language, COPY.TRACKING.TEAM),
          ],
          timeout_minutes: 60,
        }),
        node('say_bye', 'send_message', [5, 0], {
          text: body(language, COPY.TRACKING.BYE),
        }),
        node('finish', 'end', [6, 0], { resolve: true }),
        node('ask_number', 'question', [3, 2], {
          text: body(language, COPY.TRACKING.ASK_NUMBER),
          reply_type: 'any',
          store_as: { scope: 'context', key: 'order_number' },
          timeout_minutes: 180,
        }),
        node('lookup_number', 'commerce_lookup', [4, 2], {
          mode: 'order_number',
          number: '{{flow.order_number}}',
        }),
        node('show_found', 'send_message', [5, 2], {
          text: body(language, COPY.TRACKING.FOUND),
        }),
        node('say_not_found', 'send_message', [5, 3], {
          text: body(language, COPY.TRACKING.NOT_FOUND),
        }),
        handoff('to_team', [6, 3], {
          team: teamId,
          reason: COPY.TRACKING.NOTE,
        }),
      ],
      edges: [
        edge('start', 'next', 'menu'),
        edge('menu', 'track', 'lookup_latest'),
        edge('menu', 'agent', 'to_team'),
        edge('menu', 'timeout', 'to_team'),
        edge('lookup_latest', 'found', 'show_latest'),
        edge('lookup_latest', 'not_found', 'ask_number'),
        edge('lookup_latest', 'unavailable', 'to_team'),
        edge('show_latest', 'next', 'ask_more'),
        edge('ask_more', 'done', 'say_bye'),
        edge('ask_more', 'more_help', 'to_team'),
        edge('ask_more', 'timeout', 'say_bye'),
        edge('say_bye', 'next', 'finish'),
        edge('ask_number', 'reply', 'lookup_number'),
        edge('ask_number', 'timeout', 'to_team'),
        edge('lookup_number', 'found', 'show_found'),
        edge('lookup_number', 'not_found', 'say_not_found'),
        edge('lookup_number', 'unavailable', 'to_team'),
        edge('show_found', 'next', 'ask_more'),
        edge('say_not_found', 'next', 'to_team'),
      ],
    }),
  }),

  template({
    id: 'commerce_after_sales',
    category: CATEGORIES.ECOMMERCE,
    requires: [REQUIREMENTS.COMMERCE, REQUIREMENTS.TEAM],
    inputs: [
      team('team'),
      { key: 'labels', type: INPUT_TYPES.LABELS, required: false },
      LANGUAGE_INPUT,
    ],
    nodeCount: 10,
    edgeCount: 12,
    build: ({ team: teamId, labels = [], language }) => {
      const issue = (id, position, reason) =>
        handoff(id, position, { team: teamId, labels, reason });
      return {
        nodes: [
          node('start', 'start', [0, 1]),
          node('ask_number', 'question', [1, 1], {
            text: body(language, COPY.AFTER_SALES.ASK_NUMBER),
            reply_type: 'any',
            store_as: { scope: 'context', key: 'order_number' },
            timeout_minutes: 180,
          }),
          node('lookup', 'commerce_lookup', [2, 1], {
            mode: 'order_number',
            number: '{{flow.order_number}}',
          }),
          node('say_found', 'send_message', [3, 0], {
            text: body(language, COPY.AFTER_SALES.FOUND),
          }),
          node('ask_issue', 'buttons', [4, 0], {
            text: body(language, COPY.AFTER_SALES.WHICH_ISSUE),
            options: [
              option('wrong', language, COPY.AFTER_SALES.WRONG),
              option('damaged', language, COPY.AFTER_SALES.DAMAGED),
              option('late', language, COPY.AFTER_SALES.LATE),
            ],
            timeout_minutes: 180,
          }),
          issue('to_wrong', [5, 0], COPY.AFTER_SALES.NOTE_WRONG),
          issue('to_damaged', [5, 1], COPY.AFTER_SALES.NOTE_DAMAGED),
          issue('to_late', [5, 2], COPY.AFTER_SALES.NOTE_LATE),
          node('say_not_found', 'send_message', [3, 3], {
            text: body(language, COPY.AFTER_SALES.NOT_FOUND),
          }),
          issue('to_team', [5, 3], COPY.AFTER_SALES.NOTE_UNKNOWN),
        ],
        edges: [
          edge('start', 'next', 'ask_number'),
          edge('ask_number', 'reply', 'lookup'),
          edge('ask_number', 'timeout', 'to_team'),
          edge('lookup', 'found', 'say_found'),
          edge('lookup', 'not_found', 'say_not_found'),
          edge('lookup', 'unavailable', 'to_team'),
          edge('say_found', 'next', 'ask_issue'),
          edge('ask_issue', 'wrong', 'to_wrong'),
          edge('ask_issue', 'damaged', 'to_damaged'),
          edge('ask_issue', 'late', 'to_late'),
          edge('ask_issue', 'timeout', 'to_team'),
          edge('say_not_found', 'next', 'to_team'),
        ],
      };
    },
  }),

  template({
    id: 'support_department_routing',
    category: CATEGORIES.SUPPORT,
    requires: [REQUIREMENTS.TEAM],
    inputs: [
      team('orders_team'),
      team('products_team'),
      team('other_team'),
      LANGUAGE_INPUT,
    ],
    nodeCount: 8,
    edgeCount: 8,
    build: ({ orders_team, products_team, other_team, language }) => ({
      nodes: [
        node('start', 'start', [0, 1]),
        node('menu', 'buttons', [1, 1], {
          text: body(language, COPY.ROUTING.MENU),
          options: [
            option('orders', language, COPY.ROUTING.ORDERS),
            option('products', language, COPY.ROUTING.PRODUCTS),
            option('other', language, COPY.ROUTING.OTHER),
          ],
          timeout_minutes: 60,
        }),
        node('ack_orders', 'send_message', [2, 0], {
          text: body(language, COPY.ROUTING.ACK_ORDERS),
        }),
        handoff('to_orders', [3, 0], {
          team: orders_team,
          reason: COPY.ROUTING.NOTE_ORDERS,
        }),
        node('ack_products', 'send_message', [2, 1], {
          text: body(language, COPY.ROUTING.ACK_PRODUCTS),
        }),
        handoff('to_products', [3, 1], {
          team: products_team,
          reason: COPY.ROUTING.NOTE_PRODUCTS,
        }),
        node('ack_other', 'send_message', [2, 2], {
          text: body(language, COPY.CONNECTING),
        }),
        handoff('to_other', [3, 2], {
          team: other_team,
          reason: COPY.ROUTING.NOTE_OTHER,
        }),
      ],
      edges: [
        edge('start', 'next', 'menu'),
        edge('menu', 'orders', 'ack_orders'),
        edge('menu', 'products', 'ack_products'),
        edge('menu', 'other', 'ack_other'),
        edge('menu', 'timeout', 'to_other'),
        edge('ack_orders', 'next', 'to_orders'),
        edge('ack_products', 'next', 'to_products'),
        edge('ack_other', 'next', 'to_other'),
      ],
    }),
  }),

  template({
    id: 'vip_priority_routing',
    category: CATEGORIES.SUPPORT,
    requires: [REQUIREMENTS.SHARED_AUDIENCE, REQUIREMENTS.TEAM],
    inputs: [
      { key: 'audience', type: INPUT_TYPES.AUDIENCE, required: true },
      team('vip_team'),
      team('standard_team'),
      LANGUAGE_INPUT,
    ],
    nodeCount: 6,
    edgeCount: 5,
    build: ({ audience, vip_team, standard_team, language }) => ({
      nodes: [
        node('start', 'start', [0, 1]),
        node('check', 'audience_condition', [1, 1], {
          conditions: [
            {
              attribute_key: 'contact_audience',
              filter_operator: 'equal_to',
              values: [audience],
              query_operator: null,
            },
          ],
        }),
        node('vip_ack', 'send_message', [2, 0], {
          text: body(language, COPY.VIP.ACK),
        }),
        handoff('to_vip', [3, 0], {
          team: vip_team,
          reason: COPY.VIP.NOTE,
        }),
        node('standard_ack', 'send_message', [2, 2], {
          text: body(language, COPY.TEAM_WILL_REPLY),
        }),
        handoff('to_standard', [3, 2], {
          team: standard_team,
          reason: COPY.VIP.STANDARD_NOTE,
        }),
      ],
      edges: [
        edge('start', 'next', 'check'),
        edge('check', 'true', 'vip_ack'),
        edge('check', 'false', 'standard_ack'),
        edge('vip_ack', 'next', 'to_vip'),
        edge('standard_ack', 'next', 'to_standard'),
      ],
    }),
  }),

  template({
    id: 'bilingual_welcome',
    category: CATEGORIES.SUPPORT,
    requires: [REQUIREMENTS.TEAM],
    inputs: [team('arabic_team'), team('english_team')],
    nodeCount: 6,
    edgeCount: 6,
    build: ({ arabic_team, english_team }) => ({
      nodes: [
        node('start', 'start', [0, 1]),
        node('choose', 'buttons', [1, 1], {
          text: body('both', COPY.BILINGUAL.CHOOSE),
          options: [
            option('arabic', 'both', COPY.BILINGUAL.ARABIC),
            option('english', 'both', COPY.BILINGUAL.ENGLISH),
          ],
          timeout_minutes: 60,
        }),
        node('ack_arabic', 'send_message', [2, 0], {
          text: body('ar', COPY.BILINGUAL.ACK_AR),
        }),
        handoff('to_arabic', [3, 0], {
          team: arabic_team,
          reason: COPY.BILINGUAL.NOTE_AR,
        }),
        node('ack_english', 'send_message', [2, 2], {
          text: body('en', COPY.BILINGUAL.ACK_EN),
        }),
        handoff('to_english', [3, 2], {
          team: english_team,
          reason: COPY.BILINGUAL.NOTE_EN,
        }),
      ],
      edges: [
        edge('start', 'next', 'choose'),
        edge('choose', 'arabic', 'ack_arabic'),
        edge('choose', 'english', 'ack_english'),
        edge('choose', 'timeout', 'to_arabic'),
        edge('ack_arabic', 'next', 'to_arabic'),
        edge('ack_english', 'next', 'to_english'),
      ],
    }),
  }),

  template({
    id: 'whatsapp_welcome_menu',
    category: CATEGORIES.SUPPORT,
    requires: [REQUIREMENTS.TEAM],
    inputs: [team('team'), LANGUAGE_INPUT],
    nodeCount: 4,
    edgeCount: 4,
    build: ({ team: teamId, language }) => ({
      nodes: [
        node('start', 'start', [0, 0]),
        node('ask', 'question', [1, 0], {
          text: body(language, COPY.WELCOME.ASK),
          reply_type: 'any',
          store_as: { scope: 'context', key: 'request' },
          timeout_minutes: 180,
        }),
        node('thanks', 'send_message', [2, 0], {
          text: body(language, COPY.TEAM_WILL_REPLY),
        }),
        handoff('to_team', [3, 0], {
          team: teamId,
          reason: COPY.WELCOME.NOTE,
        }),
      ],
      edges: [
        edge('start', 'next', 'ask'),
        edge('ask', 'reply', 'thanks'),
        edge('ask', 'timeout', 'to_team'),
        edge('thanks', 'next', 'to_team'),
      ],
    }),
  }),
];
