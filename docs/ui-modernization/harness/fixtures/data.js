import { FLOW_TEMPLATES } from 'dashboard/recipes/flowTemplates';

// The fixture account every surface renders against. One WooCommerce store, three teams, labels, a WhatsApp inbox,
// a shared audience referenced by a rule and a scheduled campaign, and a personal filter. Deliberately small but
// never empty, so density and alignment are visible; surfaces that also need an empty variant get one via ?state=.
export const ACCOUNT_ID = 1;

export const TEAMS = [
  { id: 1, name: 'Customer Care', description: 'First line support', allow_auto_assign: true },
  { id: 2, name: 'Orders', description: 'Order and delivery questions', allow_auto_assign: true },
  { id: 3, name: 'Products', description: 'Product specialists', allow_auto_assign: false },
];

export const LABELS = [
  { id: 1, title: 'vip', description: 'High value customer', color: '#1f93ff', show_on_sidebar: true },
  { id: 2, title: 'refund', description: 'Refund requested', color: '#d32f2f', show_on_sidebar: true },
  { id: 3, title: 'shipped', description: 'Order on the way', color: '#43a047', show_on_sidebar: false },
];

export const INBOXES = [
  {
    id: 5,
    name: 'WhatsApp',
    channel_type: 'Channel::Whatsapp',
    provider: 'whatsapp_cloud',
    phone_number: '+966500000000',
  },
  { id: 6, name: 'Website', channel_type: 'Channel::WebWidget' },
];

export const AGENTS = [
  { id: 11, name: 'Lina Haddad', email: 'lina@example.com', role: 'administrator', availability_status: 'online', confirmed: true },
  { id: 12, name: 'Omar Nasser', email: 'omar@example.com', role: 'agent', availability_status: 'busy', confirmed: true },
  { id: 13, name: 'Sara Khoury', email: 'sara@example.com', role: 'agent', availability_status: 'offline', confirmed: false },
];

export const CONTACT_VIEWS = [
  {
    id: 7,
    name: 'VIP buyers',
    filter_type: 'contact',
    shared: true,
    query: {
      payload: [
        {
          attribute_key: 'commerce_spend_sar',
          filter_operator: 'is_greater_than',
          attribute_model: 'commerce',
          values: ['1000'],
          query_operator: null,
        },
      ],
    },
    automation_rules_count: 2,
    active_automation_rules_count: 2,
    campaigns_count: 1,
  },
  { id: 8, name: 'My drafts', filter_type: 'contact', shared: false, query: { payload: [] } },
];

export const COMMERCE_STORES = [
  { id: 4, name: 'Syria Cosmetics', provider: 'woocommerce', status: 'active', base_url: 'https://shop.example.com', actions: true, carts: true },
  { id: 9, name: 'Damascus Outlet', provider: 'woocommerce', status: 'needs_reauth', base_url: 'https://outlet.example.com', actions: false, carts: false },
];

export const FLOWS = [
  {
    id: 1,
    name: 'Order tracking bot',
    description: 'Created from the Order tracking bot template (v1).',
    inboxes: [{ id: 5, name: 'WhatsApp', channel_type: 'Channel::Whatsapp' }],
    published: { id: 10, version: 3, status: 'published' },
    draft: { id: 11, version: 4, status: 'draft' },
    live_sessions: 12,
  },
  {
    id: 2,
    name: 'Department routing bot',
    description: 'Routes to the team that owns the topic.',
    inboxes: [{ id: 5, name: 'WhatsApp', channel_type: 'Channel::Whatsapp' }],
    published: { id: 20, version: 1, status: 'published' },
    draft: null,
    live_sessions: 0,
  },
  {
    id: 3,
    name: 'Arabic or English welcome',
    description: '',
    inboxes: [],
    published: null,
    draft: { id: 30, version: 1, status: 'draft' },
    live_sessions: 0,
  },
];

export const AUTOMATIONS = [
  {
    id: 41,
    name: 'Audience gets priority',
    description: 'Created from the Audience gets priority recipe (v1).',
    event_name: 'conversation_created',
    active: false,
    execution_delay: null,
    created_on: '2026-09-02T09:00:00.000Z',
    conditions: [{ attribute_key: 'contact_audience', filter_operator: 'equal_to', values: [7], query_operator: null }],
    actions: [{ action_name: 'change_priority', action_params: ['high'] }],
  },
  {
    id: 42,
    name: 'New order goes to a team',
    description: '',
    event_name: 'commerce_order_created',
    active: true,
    execution_delay: null,
    created_on: '2026-08-21T09:00:00.000Z',
    conditions: [{ attribute_key: 'commerce_event_store', filter_operator: 'equal_to', values: [4], query_operator: null }],
    actions: [{ action_name: 'assign_team', action_params: [1] }],
  },
  {
    id: 43,
    name: 'Follow up after an hour',
    description: 'Waits before nudging an unanswered conversation.',
    event_name: 'conversation_created',
    active: true,
    execution_delay: 60,
    created_on: '2026-07-11T09:00:00.000Z',
    conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: null }],
    actions: [{ action_name: 'add_label', action_params: ['vip'] }],
  },
];

export const CONTACTS = [
  {
    id: 101,
    name: 'Rania Mansour',
    email: 'rania@example.com',
    phone_number: '+966500000001',
    thumbnail: '',
    availability_status: 'offline',
    last_activity_at: 1759400000,
    created_at: 1757000000,
    additional_attributes: { city: 'Riyadh', country: 'Saudi Arabia', country_code: 'SA', company_name: 'Mansour Trading' },
    custom_attributes: {},
    labels: ['vip'],
  },
  {
    id: 102,
    name: 'Khaled Aziz',
    email: 'khaled@example.com',
    phone_number: '+966500000002',
    thumbnail: '',
    availability_status: 'online',
    last_activity_at: 1759300000,
    created_at: 1757100000,
    additional_attributes: { city: 'Jeddah', country: 'Saudi Arabia', country_code: 'SA' },
    custom_attributes: {},
    labels: [],
  },
  {
    id: 103,
    name: 'Noor Al-Sayed',
    email: '',
    phone_number: '+966500000003',
    thumbnail: '',
    availability_status: 'offline',
    last_activity_at: 1759200000,
    created_at: 1757200000,
    additional_attributes: {},
    custom_attributes: {},
    labels: ['refund'],
  },
];

export const CAMPAIGNS = [
  {
    id: 201,
    title: 'Eid announcement',
    campaign_type: 'one_off',
    campaign_status: 'active',
    message: 'Our Eid hours are now live.',
    scheduled_at: '2026-10-20T09:00:00.000Z',
    inbox: { id: 5, name: 'WhatsApp', channel_type: 'Channel::Whatsapp' },
    audience: [{ type: 'Audience', id: 7 }],
    enabled: true,
  },
  {
    id: 202,
    title: 'Winter restock',
    campaign_type: 'one_off',
    campaign_status: 'completed',
    message: 'The winter range is back in stock.',
    scheduled_at: '2026-09-01T09:00:00.000Z',
    inbox: { id: 5, name: 'WhatsApp', channel_type: 'Channel::Whatsapp' },
    audience: [{ type: 'Label', id: 1 }],
    enabled: true,
  },
];

export const CURRENCIES = ['SAR', 'AED'];

export const AUDIENCE_FIELDS = {
  stores: COMMERCE_STORES.filter(store => store.status === 'active').map(({ id, name, provider }) => ({ id, name, provider })),
  currencies: CURRENCIES,
  unread_contacts: 14,
};

export const CANNED_RESPONSES = [
  { id: 301, short_code: 'hours', content: 'We are open 9am to 6pm, Sunday to Thursday.' },
  { id: 302, short_code: 'refund', content: 'Refunds reach your card within 5 to 7 working days.' },
  { id: 303, short_code: 'tracking', content: 'Here is your tracking link: {{order.tracking_url}}' },
];

export const MACROS = [
  {
    id: 401,
    name: 'Escalate to Orders',
    visibility: 'global',
    created_by: { id: 11, name: 'Lina Haddad' },
    updated_by: { id: 11, name: 'Lina Haddad' },
    actions: [{ action_name: 'assign_team', action_params: [2] }],
  },
  {
    id: 402,
    name: 'Close as resolved',
    visibility: 'personal',
    created_by: { id: 12, name: 'Omar Nasser' },
    updated_by: { id: 12, name: 'Omar Nasser' },
    actions: [{ action_name: 'change_status', action_params: ['resolved'] }],
  },
];

export const CUSTOM_ATTRIBUTES = [
  {
    id: 501,
    attribute_display_name: 'Order number',
    attribute_key: 'order_number',
    attribute_display_type: 'text',
    attribute_description: 'Store order reference',
    attribute_model: 'conversation_attribute',
  },
  {
    id: 502,
    attribute_display_name: 'Loyalty tier',
    attribute_key: 'loyalty_tier',
    attribute_display_type: 'list',
    attribute_description: 'Bronze, Silver or Gold',
    attribute_model: 'contact_attribute',
    attribute_values: ['Bronze', 'Silver', 'Gold'],
  },
];

export const SLA_POLICIES = [
  {
    id: 601,
    name: 'VIP first reply',
    description: 'Fifteen minutes for VIP buyers',
    first_response_time_threshold: 900,
    next_response_time_threshold: 1800,
    resolution_time_threshold: 14400,
    only_during_business_hours: false,
  },
  {
    id: 602,
    name: 'Standard',
    description: 'One hour during business hours',
    first_response_time_threshold: 3600,
    next_response_time_threshold: null,
    resolution_time_threshold: 86400,
    only_during_business_hours: true,
  },
];

export const CUSTOM_ROLES = [
  { id: 701, name: 'Order desk', description: 'Reads conversations, manages orders', permissions: ['conversation_manage'] },
  { id: 702, name: 'Reporting only', description: 'Reports and nothing else', permissions: ['report_manage'] },
];

// Three statuses on purpose: approved shows no chip, pending and rejected are the two tones the
// status badge has to render, so a badge change is visible in the capture instead of invisible.
export const WHATSAPP_TEMPLATES = [
  {
    id: 801,
    name: 'order_shipped',
    status: 'approved',
    category: 'UTILITY',
    language: 'en',
    components: [{ type: 'BODY', text: 'Your order {{1}} has shipped.' }],
  },
  {
    id: 802,
    name: 'eid_offer',
    status: 'pending',
    category: 'MARKETING',
    language: 'ar',
    components: [{ type: 'BODY', text: 'عرض العيد متاح الآن.' }],
  },
  {
    id: 803,
    name: 'cart_reminder',
    status: 'rejected',
    category: 'MARKETING',
    language: 'en',
    components: [{ type: 'BODY', text: 'You left something in your cart.' }],
  },
];

export const INTEGRATION_APPS = [
  { id: 'slack', name: 'Slack', description: 'Send conversations to a Slack channel', enabled: false, hooks: [] },
  { id: 'webhook', name: 'Webhooks', description: 'Post events to your own endpoint', enabled: true, hooks: [] },
];

// One open conversation, so the workspace surfaces (header, contact panel, Commerce) render against a real chat
// instead of an empty object: a VIP buyer on WhatsApp, assigned, labelled, with an SLA applied.
export const CONVERSATION = {
  id: 91,
  account_id: ACCOUNT_ID,
  inbox_id: 5,
  status: 'open',
  priority: 'high',
  unread_count: 2,
  can_reply: true,
  muted: false,
  snoozed_until: null,
  labels: ['vip', 'refund'],
  agent_last_seen_at: 1759400000,
  last_activity_at: 1759400000,
  created_at: 1759300000,
  waiting_since: 1759399000,
  first_reply_created_at: 1759350000,
  timestamp: 1759400000,
  applied_sla: { id: 601, name: 'VIP first reply', first_response_time_threshold: 900 },
  sla_events: [],
  custom_attributes: { order_number: '1234' },
  additional_attributes: { browser: { browser_name: 'Chrome' } },
  meta: {
    channel: 'Channel::Whatsapp',
    sender: CONTACTS[0],
    assignee: AGENTS[0],
    team: TEAMS[1],
    hmac_verified: true,
  },
  messages: [
    {
      id: 9101,
      content: 'Where is my order 1234?',
      message_type: 0,
      content_type: 'text',
      created_at: 1759399000,
      conversation_id: 91,
      inbox_id: 5,
      status: 'sent',
      private: false,
      sender: CONTACTS[0],
      attachments: [],
    },
    {
      id: 9102,
      content: 'It shipped this morning — here is the tracking link.',
      message_type: 1,
      content_type: 'text',
      created_at: 1759399500,
      conversation_id: 91,
      inbox_id: 5,
      status: 'delivered',
      private: false,
      sender: AGENTS[0],
      attachments: [],
    },
  ],
};

export const CONTACT_NOTES = [
  {
    id: 1001,
    content: 'Prefers Arabic. Calls before 11am.',
    created_at: 1759200000,
    user: { id: 11, name: 'Lina Haddad', available_name: 'Lina', thumbnail: '' },
  },
];

const COMMERCE_ORDER = (number, attributes = {}) => ({
  provider: 'woocommerce',
  external_order_id: number,
  order_number: number,
  status: 'processing',
  provider_status: 'processing',
  payment_status: 'paid',
  shipment_status: null,
  currency: 'SAR',
  total: '420.00',
  created_at: '2026-09-29T08:00:00.000Z',
  updated_at: '2026-09-29T08:00:00.000Z',
  items: [{ name: 'Rose water toner', quantity: 2, total: '120.00' }],
  item_count: 2,
  customer: { external_id: '2', name: 'Rania Mansour' },
  shipping: null,
  shipments: [],
  tracking: null,
  admin_order_url: `https://shop.example.com/wp-admin/order/${number}`,
  customer_order_url: null,
  ...attributes,
});

const COMMERCE_STORE_REF = { id: 4, name: 'Syria Cosmetics', provider: 'woocommerce' };

// Both stores linked, so the panel opens on Customer 360 and the store view is one click away: every control of
// both views lands in the inventory.
export const COMMERCE_CONVERSATION_STORES = [
  { ...COMMERCE_STORE_REF, linked: true, actions: true, carts: true },
  { id: 9, name: 'Damascus Outlet', provider: 'woocommerce', linked: true, actions: false, carts: false },
];

export const COMMERCE_PANEL = {
  store: COMMERCE_STORE_REF,
  state: 'linked',
  link: { match_source: 'verified_phone', customer_type: 'registered', linked_at: '2026-09-20T08:00:00.000Z', confirmed_by: null },
  orders: [COMMERCE_ORDER('1234'), COMMERCE_ORDER('1198', { status: 'completed', shipment_status: 'delivered' })],
  candidates: [],
  fetched_at: '2026-09-29T08:30:00.000Z',
  stale: false,
  error: null,
};

export const COMMERCE_OVERVIEW = {
  contact: { id: 101 },
  stores_count: 2,
  linked_stores_count: 2,
  orders_count_visible: 3,
  total_spend_visible: [
    { currency: 'SAR', amount: '2450.00' },
    { currency: 'AED', amount: '380.00' },
  ],
  currencies: CURRENCIES,
  last_order_at: '2026-09-29T08:00:00.000Z',
  active_orders_count: 1,
  shipped_orders_count: 1,
  latest_orders: [
    { ...COMMERCE_ORDER('1234'), store: COMMERCE_STORE_REF },
    { ...COMMERCE_ORDER('8891', { currency: 'AED', total: '95.00', status: 'shipped' }), store: COMMERCE_CONVERSATION_STORES[1] },
  ],
  stores: [
    {
      store: COMMERCE_STORE_REF,
      state: 'linked',
      link: { match_source: 'verified_phone', customer_type: 'registered' },
      fetched_at: '2026-09-29T08:30:00.000Z',
      stale: false,
      error: null,
      orders_count: 2,
    },
    {
      store: { id: 9, name: 'Damascus Outlet', provider: 'woocommerce' },
      state: 'linked',
      link: { match_source: 'manual', customer_type: 'guest' },
      fetched_at: '2026-09-29T08:10:00.000Z',
      stale: false,
      error: null,
      orders_count: 1,
    },
  ],
  partial: false,
};

// One abandoned cart with recovery still open, so the cart section and its recovery control are captured.
export const COMMERCE_CARTS = [
  {
    store: COMMERCE_STORE_REF,
    state: 'ok',
    error: null,
    carts: [
      {
        external_cart_id: 'c0ffee01',
        created_at: '2026-09-29T06:00:00.000Z',
        updated_at: '2026-09-29T07:00:00.000Z',
        currency: 'SAR',
        total: '120.50',
        items: [{ name: 'Oud perfume', quantity: 2 }],
        status: 'abandoned',
        match: 'verified_phone',
        recovery: { prepared_at: null, sent_at: null, cooldown_until: null },
      },
    ],
  },
];

// The audience whose conditions the chip strip renders: three on purpose, so the strip shows two chips, the
// `and` connector and its "+1 more" overflow — the three controls that pass is about.
export const AUDIENCE_SEGMENT = {
  ...CONTACT_VIEWS[0],
  query: {
    payload: [
      { attribute_key: 'name', filter_operator: 'equal_to', attribute_model: 'standard', values: ['Rania'], query_operator: 'and' },
      { attribute_key: 'conversation_status', filter_operator: 'equal_to', attribute_model: 'conversation', values: ['open'], query_operator: 'and' },
      { attribute_key: 'commerce_spend_sar', filter_operator: 'is_greater_than', attribute_model: 'commerce', values: ['1000'], query_operator: null },
    ],
  },
};

// An ad-hoc filter, camel-cased the way `contacts/getAppliedContactFiltersV4` hands it over. This is the only
// state in which the strip's clear-filters button and the header's save-as-audience button exist.
export const APPLIED_CONTACT_FILTERS = [
  {
    attributeKey: 'company_name',
    filterOperator: 'contains',
    attributeModel: 'standard',
    values: ['ACME Inc'],
    queryOperator: 'and',
  },
  {
    attributeKey: 'country',
    filterOperator: 'equal_to',
    attributeModel: 'standard',
    values: [{ id: 'SA', name: 'Saudi Arabia' }],
    queryOperator: 'and',
  },
];

// The flow builder's canvas, from a real template rather than a hand-drawn graph: `FLOW_TEMPLATES[0].build`
// produces the twelve nodes and nineteen edges its own spec asserts against the backend's graph contract, so
// the capture renders a flow the server would accept.
export const FLOW_GRAPH = FLOW_TEMPLATES[0].build({ team: 1, language: 'both' });

// `Flows::NodeTypes::TYPES`, as the flows API serves it. Transcribed from the backend the same way
// `recipes/specs/flowTemplates.spec.js` transcribes it, and for the same reason: the node's output handles
// and the palette both come from this, so a canvas without it has nodes and no connections.
export const FLOW_NODE_TYPES = {
  start: { outputs: ['next'], data: ['keywords', 'conditions'] },
  send_message: { outputs: ['next'], data: ['text'] },
  send_template: { outputs: ['next', 'failed'], optional: ['failed'], data: ['name', 'language', 'params'] },
  question: {
    outputs: ['reply', 'invalid', 'timeout'],
    optional: ['invalid', 'timeout'],
    wait: true,
    data: ['text', 'reply_type', 'keywords', 'store_as', 'max_attempts', 'retry_text', 'timeout_minutes'],
  },
  buttons: {
    outputs: 'options',
    extra: ['other', 'timeout'],
    optional: ['other', 'timeout'],
    wait: true,
    data: ['text', 'options', 'timeout_minutes'],
  },
  list: {
    outputs: 'options',
    extra: ['other', 'timeout'],
    optional: ['other', 'timeout'],
    wait: true,
    data: ['text', 'button_label', 'options', 'timeout_minutes'],
  },
  condition: { outputs: ['true', 'false'], data: ['conditions'] },
  audience_condition: { outputs: ['true', 'false'], data: ['conditions'] },
  commerce_condition: { outputs: ['true', 'false'], data: ['conditions'] },
  set_contact_attribute: { outputs: ['next'], data: ['key', 'value'] },
  set_conversation_attribute: { outputs: ['next'], data: ['key', 'value'] },
  add_label: { outputs: ['next'], data: ['labels'] },
  remove_label: { outputs: ['next'], data: ['labels'] },
  assign_agent: { outputs: ['next', 'failed'], optional: ['failed'], data: ['agent_id'] },
  assign_team: { outputs: ['next', 'failed'], optional: ['failed'], data: ['team_id'] },
  commerce_lookup: {
    outputs: ['found', 'not_found', 'unavailable'],
    optional: ['not_found', 'unavailable'],
    data: ['mode', 'number'],
  },
  webhook: { outputs: ['next'], data: ['url'] },
  delay: { outputs: ['next'], wait: true, data: ['seconds'] },
  handoff: { outputs: [], data: ['team_id', 'agent_id', 'priority', 'labels', 'reason'] },
  goto: { outputs: [], data: ['target'] },
  end: { outputs: [], data: ['resolve'] },
};

// A WhatsApp campaign's analytics: the counts the six metric tiles read, and three delivery rows that
// between them cover a clean send, a failure with a reason, and a skip — the three states the delivery
// table styles differently.
export const CAMPAIGN_METRICS = {
  status_counts: {
    audience: 240,
    queued: 12,
    sent: 36,
    delivered: 171,
    read: 118,
    failed: 9,
    skipped: 12,
  },
};

export const CAMPAIGN_DELIVERIES = [
  {
    id: 1,
    contact: { id: 101, name: 'Rania Mansour', phone_number: '+966500000001' },
    status: 'read',
    message_content: 'Our Eid hours are now live.',
    error_code: null,
    error_message: null,
    error_title: null,
  },
  {
    id: 2,
    contact: { id: 102, name: 'Khaled Aziz', phone_number: '+966500000002' },
    status: 'failed',
    message_content: 'Our Eid hours are now live.',
    error_code: '131047',
    error_title: 'Re-engagement message',
    error_message:
      'More than 24 hours have passed since the contact last replied, so this template could not be delivered.',
  },
  {
    id: 3,
    contact: { id: 103, name: 'Noor Al-Sayed', phone_number: '+966500000003' },
    status: 'skipped',
    message_content: null,
    error_code: null,
    error_title: null,
    error_message: null,
  },
];
