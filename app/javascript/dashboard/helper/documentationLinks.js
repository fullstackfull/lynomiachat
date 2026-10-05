/**
 * Lynomia contextual help (docs/global-documentation/12-contextual-help.md).
 *
 * One registry, so a documentation link lives in exactly one place and a Vue file never carries a URL. A key names
 * the product moment; its value is the article's stable slug, which is the contract between the product and the
 * documentation — never a database id, which would change the moment an article is reseeded.
 *
 * The destination is the installation's own DOCUMENTATION_URL. A branded installation that has configured none gets
 * an empty string, and the caller renders no link at all — the behaviour every other product link already has.
 */
export const DOC_ARTICLES = Object.freeze({
  gettingStarted: 'welcome-to-lynomia-chat',
  inboxes: 'set-up-an-inbox',
  conversations: 'work-in-the-inbox',
  contacts: 'contacts',
  contactImport: 'import-contacts',
  labels: 'labels',
  sharedAudiences: 'shared-audiences',
  labelsVsAudiences: 'labels-or-shared-audiences',
  campaigns: 'whatsapp-campaigns',
  whatsapp: 'connect-whatsapp',
  whatsappCoexistence: 'whatsapp-business-coexistence',
  whatsappTemplates: 'whatsapp-templates',
  whatsappTemplateLifecycle: 'whatsapp-template-lifecycle',
  whatsappWindow: 'the-whatsapp-24-hour-window',
  automation: 'automation-rules',
  flows: 'flow-builder',
  automationVsFlows: 'automation-or-flow-builder',
  macros: 'macros',
  agentBots: 'agent-bots',
  commerce: 'commerce-overview',
  commerceProviders: 'commerce-provider-support',
  commerceWoocommerce: 'connect-woocommerce',
  commerceSalla: 'connect-salla',
  commerceZid: 'connect-zid',
  commerceShopify: 'connect-shopify',
  customer360: 'customer-360',
  teams: 'teams-and-agents',
  integrations: 'integrations',
  permissions: 'roles-and-permissions',
  auditLogs: 'audit-logs',
  troubleshooting: 'troubleshooting',
});

/**
 * Builds the address of a documentation article from a registry key.
 * @param {string} base - the installation's documentation URL, or '' when it has none
 * @param {keyof typeof DOC_ARTICLES} key - the registry key for the product moment
 * @returns {string} the article URL, or '' when there is no documentation to link to
 */
export function documentationArticleUrl(base, key) {
  const slug = DOC_ARTICLES[key];
  if (!base || !slug) return '';

  return `${base.replace(/\/+$/, '')}/${slug}`;
}
