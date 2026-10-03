// window.axios, answered from fixtures. Every ApiClient in the dashboard goes through the global axios, so this is
// the whole network layer for the harness: no Rails, no database, and a deterministic response for every surface.
import {
  AGENTS,
  AUDIENCE_FIELDS,
  AUTOMATIONS,
  CAMPAIGNS,
  COMMERCE_STORES,
  CANNED_RESPONSES,
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

const EMPTY = new URLSearchParams(window.location.search).get('state') === 'empty';
const list = rows => (EMPTY ? [] : rows);

// Longest match wins, so a specific path beats its prefix.
const ROUTES = [
  [/\/flows\/\d+$/, () => ({ ...FLOWS[0], graph: { nodes: [], edges: [] }, errors: [], capabilities: {}, node_types: {}, variables: [] })],
  [/\/flows$/, () => ({ payload: list(FLOWS) })],
  [/\/automation_rules$/, () => ({ payload: list(AUTOMATIONS) })],
  [/\/commerce\/audience_fields$/, () => AUDIENCE_FIELDS],
  [/\/commerce\/stores$/, () => ({ payload: list(COMMERCE_STORES) })],
  [/\/commerce\/carts$/, () => ({ payload: [] })],
  [/\/custom_filters/, () => list(CONTACT_VIEWS)],
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
