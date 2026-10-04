// The fixture account as Vuex getters, so every component reads it through the store it really uses.
import {
  ACCOUNT_ID,
  AGENTS,
  AUTOMATIONS,
  CAMPAIGNS,
  CANNED_RESPONSES,
  CONTACTS,
  CONTACT_NOTES,
  AGENT_BOTS,
  APPLIED_CONTACT_FILTERS,
  AUDIT_LOGS,
  DASHBOARD_APPS,
  CONTACT_VIEWS,
  CONVERSATION,
  CUSTOM_ATTRIBUTES,
  CUSTOM_ROLES,
  INBOXES,
  INTEGRATION_APPS,
  LABELS,
  MACROS,
  SLA_POLICIES,
  TEAMS,
  WEBHOOKS,
} from './data';
import camelcaseKeys from 'camelcase-keys';
import { DEFAULT_SIDEBAR_SORT_PREFERENCES } from 'dashboard/helper/sidebarSort';

const params = new URLSearchParams(window.location.search);
const EMPTY = params.get('state') === 'empty';
// `?state=loading` renders every list as if its first fetch were still in flight, so loading states
// are capturable. While loading, the lists are empty — a skeleton drawn over stale rows would lie.
const LOADING = params.get('state') === 'loading';
const RTL = params.get('locale') === 'ar';
// `?state=filtered` is an ad-hoc contact filter with nothing saved: the one state in which the chip strip's
// clear button and the header's save-as-audience button exist at all.
const FILTERED = params.get('state') === 'filtered';
const list = rows => (EMPTY || LOADING ? [] : rows);

const USER = {
  id: 11,
  name: 'Lina Haddad',
  display_name: 'Lina',
  email: 'lina@example.com',
  available_name: 'Lina',
  avatar_url: '',
  role: 'administrator',
  account_id: ACCOUNT_ID,
  accounts: [
    {
      id: ACCOUNT_ID,
      name: 'Lynomia Demo',
      role: 'administrator',
      permissions: ['administrator'],
      custom_role_id: null,
      status: 'active',
    },
  ],
};

const ACCOUNT = {
  id: ACCOUNT_ID,
  name: 'Lynomia Demo',
  locale: RTL ? 'ar' : 'en',
  features: {},
  custom_attributes: {},
};

// Pages read half a dozen different flag names for the same thing, so all of them are set.
const NO_FLAGS = LOADING
  ? {
      isFetching: true,
      isFetchingItems: true,
      fetchingList: true,
      isFetchingList: true,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
    }
  : {};

const OPEN_SIDEBAR_SECTIONS = {
  is_contact_sidebar_open: true,
  is_conv_actions_open: true,
  is_conv_details_open: true,
  is_conv_participants_open: true,
  is_contact_attributes_open: true,
  is_contact_notes_open: true,
  is_contact_labels_open: true,
  is_previous_conv_open: true,
  is_shared_files_open: true,
  is_macro_open: true,
  is_commerce_open: true,
  is_linear_issues_open: true,
  is_shopify_orders_open: true,
};

export const GETTERS = {
  getCurrentAccountId: () => ACCOUNT_ID,
  getCurrentUser: () => USER,
  getCurrentUserID: () => USER.id,
  getCurrentRole: () => 'administrator',
  getCurrentAccount: () => ACCOUNT,
  isLoggedIn: () => true,
  // Every conversation-sidebar accordion open, so the panel's own controls are inside the inventory rather than
  // behind a collapsed heading. An agent's real preference is per-section; open is the state worth measuring.
  getUISettings: () => OPEN_SIDEBAR_SECTIONS,
  getSelectedChat: () => CONVERSATION,
  getSelectedInbox: () => INBOXES[0],
  getSelectedChatAttachments: () => [],
  getSelectedChatAttachmentsLoaded: () => true,
  getConversationById: () => () => CONVERSATION,
  getAppliedContactFilter: () => null,
  'accounts/getAccount': () => () => ACCOUNT,
  'accounts/isRTL': () => RTL,
  'accounts/getUIFlags': () => NO_FLAGS,
  'accounts/isFeatureEnabledonAccount': () => () => true,
  'teams/getTeams': () => list(TEAMS),
  'teams/getMyTeams': () => list(TEAMS),
  'teams/getUIFlags': () => NO_FLAGS,
  'labels/getLabels': () => list(LABELS),
  'labels/getLabelsOnSidebar': () => list(LABELS).filter(label => label.show_on_sidebar),
  'labels/getUIFlags': () => NO_FLAGS,
  'inboxes/getInboxes': () => list(INBOXES),
  'inboxes/getWhatsAppInboxes': () => list(INBOXES).filter(inbox => inbox.channel_type === 'Channel::Whatsapp'),
  'inboxes/getSMSInboxes': () => [],
  'inboxes/getUIFlags': () => NO_FLAGS,
  'inboxes/getFilteredWhatsAppTemplates': () => () => [],
  'agents/getAgents': () => list(AGENTS),
  'agents/getVerifiedAgents': () => list(AGENTS).filter(agent => agent.confirmed),
  'agents/getUIFlags': () => NO_FLAGS,
  'customViews/getCustomViews': () => list(CONTACT_VIEWS),
  'customViews/getContactCustomViews': () => list(CONTACT_VIEWS),
  'customViews/getConversationCustomViews': () => [],
  'customViews/getUIFlags': () => ({ ...NO_FLAGS, isCreating: false }),
  'automations/getAutomations': () => list(AUTOMATIONS),
  'automations/getUIFlags': () => NO_FLAGS,
  'campaigns/getCampaigns': () => list(CAMPAIGNS),
  'campaigns/getAllCampaigns': () => list(CAMPAIGNS),
  'campaigns/getWhatsAppCampaigns': () => list(CAMPAIGNS),
  'campaigns/getSMSCampaigns': () => [],
  'campaigns/getLiveChatCampaigns': () => [],
  'campaigns/getUIFlags': () => NO_FLAGS,
  'contacts/getContactsList': () => list(CONTACTS),
  'contacts/getContact': () => id => CONTACTS.find(contact => contact.id === Number(id)) || CONTACTS[0],
  'contacts/getUIFlags': () => NO_FLAGS,
  'contacts/getMeta': () => ({ count: list(CONTACTS).length, currentPage: 1, hasMore: false }),
  'contacts/getAppliedContactFilters': () => [],
  'contacts/getAppliedContactFiltersV4': () => (FILTERED ? APPLIED_CONTACT_FILTERS : []),
  'attributes/getContactAttributes': () =>
    list(CUSTOM_ATTRIBUTES).filter(attribute => attribute.attribute_model === 'contact_attribute'),
  'attributes/getAttributes': () => list(CUSTOM_ATTRIBUTES),
  'attributes/getAttributesByModel': () => model =>
    list(CUSTOM_ATTRIBUTES).filter(attribute => attribute.attribute_model === model),
  'attributes/getUIFlags': () => NO_FLAGS,
  'conversationStats/getStats': () => ({}),
  'notifications/getMeta': () => ({ unreadCount: 3 }),
  'globalConfig/isOnChatwootCloud': () => false,
  'globalConfig/isACustomBrandedInstance': () => false,
  'globalConfig/get': () => ({
    installationName: 'Lynomia',
    appVersion: '4.18.0',
    gitSha: '9f2c1ab7d4e55803c2f1',
    displayManifest: true,
    brandName: 'Lynomia',
  }),
  'sla/getSLA': () => list(SLA_POLICIES),
  'sla/getUIFlags': () => NO_FLAGS,
  'agentBots/getBots': () => list(AGENT_BOTS),
  'agentBots/getUIFlags': () => NO_FLAGS,
  'webhooks/getWebhooks': () => list(WEBHOOKS),
  'webhooks/getUIFlags': () => NO_FLAGS,
  'dashboardApps/getRecords': () => list(DASHBOARD_APPS),
  'dashboardApps/getUIFlags': () => NO_FLAGS,
  'auditlogs/getAuditLogs': () => list(AUDIT_LOGS),
  'auditlogs/getUIFlags': () => NO_FLAGS,
  'auditlogs/getMeta': () => ({ currentPage: 1, totalEntries: list(AUDIT_LOGS).length, perPage: 15 }),
  'macros/getMacros': () => list(MACROS),
  'macros/getUIFlags': () => NO_FLAGS,
  // `cannedResponse` is not a namespaced Vuex module, so its getters live at the root.
  getCannedResponses: () => list(CANNED_RESPONSES),
  getSortedCannedResponses: () => () => list(CANNED_RESPONSES),
  getUIFlags: () => NO_FLAGS,
  'customRole/getCustomRoles': () => list(CUSTOM_ROLES),
  'customRole/getUIFlags': () => NO_FLAGS,
  'integrations/getAppIntegrations': () => list(INTEGRATION_APPS),
  'integrations/getUIFlags': () => NO_FLAGS,
  // Sidebar + compose
  getCurrentUserAvailability: () => 'online',
  getCurrentUserAutoOffline: () => false,
  getUserAccounts: () => USER.accounts,
  getMessageSignature: () => '',
  'notifications/getUnreadCount': () => 3,
  'sidebarSortPreferences/getSectionSort': () => section =>
    DEFAULT_SIDEBAR_SORT_PREFERENCES[section],
  'conversationUnreadCounts/getAllUnreadCount': () => 4,
  'conversationUnreadCounts/getMentionsUnreadCount': () => 1,
  'conversationUnreadCounts/getUnattendedUnreadCount': () => 2,
  'conversationUnreadCounts/getParticipatingUnreadCount': () => 0,
  'conversationUnreadCounts/getFolderUnreadCount': () => () => 0,
  'conversationUnreadCounts/getInboxUnreadCount': () => () => 0,
  'conversationUnreadCounts/getLabelUnreadCount': () => () => 0,
  'conversationUnreadCounts/getTeamUnreadCount': () => () => 0,
  'contacts/getContactById': () => () => list(CONTACTS)[0] || {},
  'contactConversations/getUIFlags': () => NO_FLAGS,
  // Conversation workspace
  'inboxes/getInbox': () => id => INBOXES.find(inbox => inbox.id === Number(id)) || {},
  'inboxes/getInboxById': () => id => INBOXES.find(inbox => inbox.id === Number(id)) || {},
  'conversationMetadata/getConversationMetadata': () => () => CONVERSATION.additional_attributes,
  'conversationWatchers/getByConversationId': () => () => ({ showAddButton: true, uiFlags: {}, watchers: [AGENTS[0]] }),
  'contactConversations/get': () => () => [],
  // Camel-cased exactly as the real getter does it, because the note item reads `note.createdAt`.
  'contactNotes/getAllNotesByContactId': () => () => camelcaseKeys(CONTACT_NOTES),
  'contactNotes/getUIFlags': () => NO_FLAGS,
  'integrations/getIntegration': () => id =>
    INTEGRATION_APPS.find(app => app.id === id) || { id, name: id, enabled: id === 'linear', hooks: [] },
  'conversationLabels/getConversationLabels': () => () => CONVERSATION.labels,
  'conversationLabels/getUIFlags': () => NO_FLAGS,
  'contactConversations/getContactConversation': () => () => [CONVERSATION],
  'contactConversations/getConversationNeighbours': () => () => ({ prevConversationId: null, nextConversationId: null }),
  'inboxAssignableAgents/getAssignableAgents': () => () => AGENTS,
  'inboxAssignableAgents/getUIFlags': () => NO_FLAGS,
  // The row context menu and the bulk bar
  'bulkActions/getUIFlags': () => ({ isUpdating: false }),
  'bulkActions/getSelectedConversationIds': () => [91, 92],
  // Not namespaced: the conversation list's own filter and sort live at the store root.
  getChatStatusFilter: () => 'open',
  getChatSortFilter: () => 'last_activity_at_desc',
  getAllConversations: () => [CONVERSATION],
};
