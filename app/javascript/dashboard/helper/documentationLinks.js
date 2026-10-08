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
  // getting started
  gettingStarted: 'welcome-to-lynomia-chat',
  accountSetup: 'set-up-your-account',
  inviteYourTeam: 'invite-your-team',
  firstChannel: 'connect-your-first-channel',
  firstConversation: 'your-first-conversation',
  // conversations
  conversations: 'work-in-the-inbox',
  assignAndPrioritise: 'assign-and-prioritise',
  labels: 'labels',
  cannedResponses: 'canned-responses',
  macros: 'macros',
  macrosOrAutomation: 'macros-or-automation',
  // contacts
  contacts: 'contacts',
  customAttributes: 'custom-attributes',
  contactImport: 'import-contacts',
  bulkActions: 'bulk-actions',
  // audiences and campaigns
  sharedAudiences: 'shared-audiences',
  labelsOrAudiences: 'labels-or-shared-audiences',
  campaigns: 'whatsapp-campaigns',
  // whatsapp
  whatsapp: 'connect-whatsapp',
  whatsappCoexistence: 'whatsapp-business-coexistence',
  whatsappWindow: 'the-whatsapp-24-hour-window',
  whatsappTemplates: 'whatsapp-templates',
  whatsappTemplateLifecycle: 'whatsapp-template-lifecycle',
  whatsappTroubleshooting: 'whatsapp-troubleshooting',
  // whatsapp, when something is refused. The five coded ones are the codes this installation classifies
  // (custom/app/services/whatsapp/delivery_failure.rb and the call sites that name them); there is deliberately
  // no article for a code nobody here has seen.
  whatsappError131049: 'whatsapp-error-131049',
  whatsappError131042: 'whatsapp-error-131042',
  whatsappError131053: 'whatsapp-error-131053',
  whatsappError131060: 'whatsapp-error-131060',
  whatsappError190: 'whatsapp-error-190',
  whatsappNumberStatus: 'whatsapp-number-status',
  whatsappQualityAndLimits: 'whatsapp-quality-and-limits',
  whatsappDisplayName: 'whatsapp-display-name',
  whatsappNothingArrives: 'whatsapp-nothing-arrives',
  whatsappReconnect: 'whatsapp-reconnect-a-number',
  whatsappNumberTaken: 'whatsapp-number-already-connected',
  whatsappContactInfoRequests: 'whatsapp-contact-info-requests',
  whatsappBusinessScopedContacts: 'whatsapp-business-scoped-contacts',
  whatsappFindAFailedMessage: 'whatsapp-find-a-failed-message',
  // automation and bots
  automation: 'automation-rules',
  flows: 'flow-builder',
  automationOrFlows: 'automation-or-flow-builder',
  agentBots: 'agent-bots',
  // commerce
  commerce: 'commerce-overview',
  commerceProviders: 'commerce-provider-support',
  commerceWoocommerce: 'connect-woocommerce',
  commerceSalla: 'connect-salla',
  commerceZid: 'connect-zid',
  commerceShopify: 'connect-shopify',
  customer360: 'customer-360',
  // workspace and team
  inboxes: 'set-up-an-inbox',
  teams: 'teams-and-agents',
  permissions: 'roles-and-permissions',
  // platform
  integrations: 'integrations',
  webhooks: 'webhooks',
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

/**
 * The registry key for one WhatsApp error code, for a surface that has the code and wants the article about it.
 *
 * Only codes with an article resolve. That is the same rule the server's classifier follows: a code this
 * installation has never seen gets no explanation invented for it, and the caller falls back to the general
 * troubleshooting article rather than linking somewhere that does not answer the question.
 * @param {number|string} code - the provider's numeric error code
 * @returns {keyof typeof DOC_ARTICLES | undefined} the registry key, or undefined when there is no article
 */
export function whatsappErrorArticle(code) {
  if (code === null || code === undefined || code === '') return undefined;

  const key = `whatsappError${code}`;
  return key in DOC_ARTICLES ? key : undefined;
}
