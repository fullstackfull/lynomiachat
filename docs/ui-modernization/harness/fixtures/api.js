// window.axios, answered from fixtures. Every ApiClient in the dashboard goes through the global axios, so this is
// the whole network layer for the harness: no Rails, no database, and a deterministic response for every surface.
import {
  AGENTS,
  AUDIENCE_FIELDS,
  AUTOMATIONS,
  CAMPAIGNS,
  CAMPAIGN_DELIVERIES,
  CAMPAIGN_METRICS,
  COMMERCE_CARTS,
  COMMERCE_CONVERSATION_STORES,
  COMMERCE_OVERVIEW,
  COMMERCE_PANEL,
  COMMERCE_STORES,
  FLOW_GRAPH,
  FLOW_NODE_TYPES,
  CANNED_RESPONSES,
  CONTACT_NOTES,
  CONVERSATION,
  CONTACTS,
  CONTACT_VIEWS,
  CUSTOM_ATTRIBUTES,
  CUSTOM_ROLES,
  FLOWS,
  INBOXES,
  INTEGRATION_APPS,
  LABELS,
  MACROS,
  SLA_POLICIES,
  TEAMS,
  WHATSAPP_TEMPLATES,
} from './data';

const STATE = new URLSearchParams(window.location.search).get('state');
// `empty` and `loading` both answer with nothing: an empty account, and a first fetch still in flight.
const list = rows => (STATE === 'empty' || STATE === 'loading' ? [] : rows);

// Longest match wins, so a specific path beats its prefix.
const ROUTES = [
  [/\/flows\/\d+$/, () => ({
    ...FLOWS[0],
    graph: FLOW_GRAPH,
    errors: [],
    capabilities: { whatsapp: { buttons: true, list: true, template: true } },
    node_types: FLOW_NODE_TYPES,
    variables: [],
  })],
  [/\/flows$/, () => ({ payload: list(FLOWS) })],
  [/\/automation_rules$/, () => ({ payload: list(AUTOMATIONS) })],
  [/\/commerce\/audience_fields$/, () => AUDIENCE_FIELDS],
  // The conversation Commerce panel: both stores linked, so Customer 360 and the store view both render.
  [/\/conversations\/\d+\/commerce\/stores\/\d+\/customers$/, () => ({ candidates: [] })],
  [/\/conversations\/\d+\/commerce\/stores\/\d+$/, () => COMMERCE_PANEL],
  [/\/conversations\/\d+\/commerce\/stores$/, () => ({ payload: list(COMMERCE_CONVERSATION_STORES) })],
  [/\/conversations\/\d+\/commerce\/overview$/, () => COMMERCE_OVERVIEW],
  [/\/conversations\/\d+\/commerce\/orders$/, () => ({ orders: [], stores: [] })],
  [/\/conversations\/\d+\/commerce\/carts$/, () => ({ stores: list(COMMERCE_CARTS) })],
  [/\/conversations\/\d+\/messages/, () => ({ payload: list(CONVERSATION.messages), meta: {} })],
  [/\/conversations\/\d+$/, () => CONVERSATION],
  [/\/conversations\/filter|\/conversations$/, () => ({ data: { payload: list([CONVERSATION]), meta: {} } })],
  [/\/notes$/, () => list(CONTACT_NOTES)],
  [/\/commerce\/stores$/, () => ({ payload: list(COMMERCE_STORES) })],
  [/\/commerce\/carts$/, () => ({ payload: [] })],
  [/\/custom_filters/, () => list(CONTACT_VIEWS)],
  [/\/campaigns\/\d+\/analytics\/metrics$/, () => (STATE === 'empty' ? { audience: 0, sent: 0, delivered: 0, read: 0, failed: 0, skipped: 0, status_counts: {} } : CAMPAIGN_METRICS)],
  [/\/campaigns\/\d+\/analytics\/contacts/, () => ({
    payload: list(CAMPAIGN_DELIVERIES),
    meta: { current_page: 1, total_pages: 1, total_count: list(CAMPAIGN_DELIVERIES).length },
  })],
  [/\/campaigns$/, () => list(CAMPAIGNS)],
  [/\/labels$/, () => ({ payload: list(LABELS) })],
  [/\/inboxes$/, () => ({ payload: list(INBOXES) })],
  [/\/teams$/, () => list(TEAMS)],
  [/\/agents$/, () => list(AGENTS)],
  [/\/contacts/, () => ({ payload: list(CONTACTS), meta: { count: list(CONTACTS).length, current_page: 1 } })],
  [/\/canned_responses$/, () => list(CANNED_RESPONSES)],
  [/\/macros$/, () => ({ payload: list(MACROS) })],
  [/\/custom_attribute_definitions/, () => list(CUSTOM_ATTRIBUTES)],
  [/\/sla_policies$/, () => ({ payload: list(SLA_POLICIES) })],
  [/\/custom_roles$/, () => list(CUSTOM_ROLES)],
  [/\/message_templates$/, () => ({ payload: list(WHATSAPP_TEMPLATES) })],
  [/\/agent_bots$/, () => []],
  [/\/webhooks$/, () => ({ payload: { webhooks: [] } })],
  [/\/integrations\/apps$/, () => ({ payload: list(INTEGRATION_APPS) })],
];

const answer = url => {
  const match = ROUTES.find(([pattern]) => pattern.test(url));
  return match ? match[1]() : { payload: [] };
};

// Every answered request is recorded so a surface that renders empty can be told apart from one that never asked.
const resolve = url => {
  window.__fixtureCalls = window.__fixtureCalls || [];
  window.__fixtureCalls.push(String(url));
  return Promise.resolve({ data: answer(String(url)), status: 200 });
};

export const installFixtureAxios = () => {
  const axios = {
    get: resolve,
    post: url => resolve(url),
    patch: url => resolve(url),
    put: url => resolve(url),
    delete: url => resolve(url),
    request: config => resolve(config?.url || ''),
  };
  axios.defaults = { headers: { common: {} } };
  axios.interceptors = {
    request: { use: () => {} },
    response: { use: () => {} },
  };
  window.axios = axios;
  return axios;
};
