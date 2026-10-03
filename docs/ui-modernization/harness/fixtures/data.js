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
