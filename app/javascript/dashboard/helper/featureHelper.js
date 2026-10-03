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
  return FEATURE_HELP_URLS[String(featureName).replace(/-/g, '_')];
}
