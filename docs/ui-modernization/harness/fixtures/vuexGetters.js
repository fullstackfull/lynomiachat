// The fixture account as Vuex getters, so every component reads it through the store it really uses.
import {
  ACCOUNT_ID,
  AGENTS,
  AUTOMATIONS,
  CAMPAIGNS,
  CANNED_RESPONSES,
  CONTACTS,
  CONTACT_VIEWS,
  CUSTOM_ATTRIBUTES,
  CUSTOM_ROLES,
  INBOXES,
  INTEGRATION_APPS,
  LABELS,
  MACROS,
  SLA_POLICIES,
  TEAMS,
} from './data';
import { DEFAULT_SIDEBAR_SORT_PREFERENCES } from 'dashboard/helper/sidebarSort';

const params = new URLSearchParams(window.location.search);
const EMPTY = params.get('state') === 'empty';
// `?state=loading` renders every list as if its first fetch were still in flight, so loading states
// are capturable. While loading, the lists are empty — a skeleton drawn over stale rows would lie.
const LOADING = params.get('state') === 'loading';
const RTL = params.get('locale') === 'ar';
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

export const GETTERS = {
  getCurrentAccountId: () => ACCOUNT_ID,
  getCurrentUser: () => USER,
  getCurrentUserID: () => USER.id,
  getCurrentRole: () => 'administrator',
  getCurrentAccount: () => ACCOUNT,
  isLoggedIn: () => true,
  getUISettings: () => ({}),
  getSelectedChat: () => ({}),
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
  'campaigns/getUIFlags': () => NO_FLAGS,
  'contacts/getContactsList': () => list(CONTACTS),
  'contacts/getContact': () => () => list(CONTACTS)[0] || {},
  'contacts/getUIFlags': () => NO_FLAGS,
  'contacts/getMeta': () => ({ count: list(CONTACTS).length, currentPage: 1, hasMore: false }),
  'contacts/getAppliedContactFilters': () => [],
  'contacts/getAppliedContactFiltersV4': () => [],
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
  'globalConfig/get': () => ({ installationName: 'Lynomia' }),
  'sla/getSLA': () => list(SLA_POLICIES),
  'sla/getUIFlags': () => NO_FLAGS,
  'agentBots/getBots': () => [],
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
};
