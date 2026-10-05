import { documentationArticleUrl } from 'dashboard/helper/documentationLinks';

// Which Lynomia Chat documentation article answers each feature's "Learn more". A feature with no entry has no
// article yet, and the caller renders no link rather than a broken one -- which is what every call site already does
// with an undefined result (docs/global-documentation/12-contextual-help.md).
const FEATURE_DOC_KEYS = {
  agent_bots: 'agentBots',
  agents: 'teams',
  audit_logs: 'auditLogs',
  automation: 'automation',
  bulk_actions: 'bulkActions',
  campaigns: 'campaigns',
  canned_responses: 'cannedResponses',
  channel_whatsapp: 'whatsapp',
  contacts: 'contacts',
  custom_attributes: 'customAttributes',
  custom_roles: 'permissions',
  flows: 'flows',
  help_center: 'ownHelpCentre',
  inboxes: 'inboxes',
  integrations: 'integrations',
  labels: 'labels',
  linear_integration: 'integrations',
  macros: 'macros',
  notion_integration: 'integrations',
  shared_audiences: 'sharedAudiences',
  shopify: 'commerceShopify',
  shopify_integration: 'commerceShopify',
  slack_integration: 'integrations',
  team_management: 'teams',
  webhook: 'webhooks',
  whatsapp_templates: 'whatsappTemplates',
};

// Upstream's own help centre, which is the right destination only on an unbranded installation.
const FEATURE_HELP_URLS = {
  agent_bots: 'https://chwt.app/hc/agent-bots',
  agents: 'https://chwt.app/hc/agents',
  audit_logs: 'https://chwt.app/hc/audit-logs',
  campaigns: 'https://chwt.app/hc/campaigns',
  canned_responses: 'https://chwt.app/hc/canned',
  automation: 'https://chwt.app/hc/automations',
  custom_roles: 'https://chwt.app/hc/custom-roles',
  channel_email: 'https://chwt.app/hc/email',
  channel_facebook: 'https://chwt.app/hc/fb',
  custom_attributes: 'https://chwt.app/hc/custom-attributes',
  dashboard_apps: 'https://chwt.app/hc/dashboard-apps',
  help_center: 'https://chwt.app/hc/help-center',
  inboxes: 'https://chwt.app/hc/inboxes',
  integrations: 'https://chwt.app/hc/integrations',
  labels: 'https://chwt.app/hc/labels',
  macros: 'https://chwt.app/hc/macros',
  reports: 'https://chwt.app/hc/reports',
  sla: 'https://chwt.app/hc/sla',
  team_management: 'https://chwt.app/hc/teams',
  webhook: 'https://chwt.app/hc/webhooks',
  whatsapp_templates:
    'https://www.chatwoot.com/hc/user-guide/articles/1754940076-whatsapp-templates',
  billing: 'https://chwt.app/pricing',
  saml: 'https://chwt.app/hc/saml',
  captain: 'https://chwt.app/captain-docs',
  captain_billing: 'https://chwt.app/hc/captain_billing',
  shopify: 'https://chwt.app/hc/shopify',
};

// Call sites spell a few feature names with hyphens; the table is keyed with underscores, and a
// mismatch silently removes the page's "Learn more" link rather than failing.
export function getHelpUrlForFeature(featureName) {
  if (!featureName) return undefined;

  const key = String(featureName).replace(/-/g, '_');
  const { INSTALLATION_NAME: name, DOCUMENTATION_URL: docs } =
    window.globalConfig || {};

  // A branded installation links to its own documentation, and to nothing where it has no article yet. Reading
  // window.globalConfig directly keeps this a plain function, which is what its twenty-five call sites expect.
  if (name && name !== 'Chatwoot') {
    return documentationArticleUrl(docs, FEATURE_DOC_KEYS[key]) || undefined;
  }

  return FEATURE_HELP_URLS[key];
}
