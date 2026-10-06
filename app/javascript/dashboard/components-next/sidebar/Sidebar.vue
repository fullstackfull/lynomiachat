<script setup>
import { h, ref, computed, onMounted, watch } from 'vue';
import { provideSidebarContext, useSidebarResize } from './provider';
import { useAccount } from 'dashboard/composables/useAccount';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useSidebarKeyboardShortcuts } from './useSidebarKeyboardShortcuts';
import { vOnClickOutside } from '@vueuse/components';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useWindowSize, useEventListener } from '@vueuse/core';

import Button from 'dashboard/components-next/button/Button.vue';
import SidebarGroup from './SidebarGroup.vue';
import SidebarProfileMenu from './SidebarProfileMenu.vue';
import SidebarChangelogCard from './SidebarChangelogCard.vue';
import SidebarChangelogButton from './SidebarChangelogButton.vue';
import ChannelLeaf from './ChannelLeaf.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import EmojiIcon from 'next/emoji-icon-picker/EmojiIcon.vue';
import SidebarAccountSwitcher from './SidebarAccountSwitcher.vue';
import Logo from 'next/icon/Logo.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import {
  SIDEBAR_SORT_SECTIONS,
  getSidebarSortOptions,
  resolveSidebarSort,
  sortSidebarItems,
} from 'dashboard/helper/sidebarSort';

const props = defineProps({
  isMobileSidebarOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'closeKeyShortcutModal',
  'openKeyShortcutModal',
  'showCreateAccountModal',
  'closeMobileSidebar',
]);

const { accountScopedRoute, isOnChatwootCloud } = useAccount();
const store = useStore();

const searchShortcut = useKbd([`$mod`, 'k']);
const { t } = useI18n();

const isACustomBrandedInstance = useMapGetter(
  'globalConfig/isACustomBrandedInstance'
);
const isRTL = useMapGetter('accounts/isRTL');

const { width: windowWidth } = useWindowSize();
const isMobile = computed(() => windowWidth.value < 768);

const accountId = useMapGetter('getCurrentAccountId');
const currentUserId = useMapGetter('getCurrentUserID');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const hasAdvancedAssignment = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.ADVANCED_ASSIGNMENT
  );
});

const hasConversationUnreadCounts = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS
  );
});

const hasFilteredUnreadCounts = computed(() => {
  return (
    hasConversationUnreadCounts.value &&
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.UNREAD_COUNT_FOR_FILTERS
    )
  );
});

const hasDataImport = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.DATA_IMPORT
  );
});

const fetchConversationUnreadCounts = ([currentAccountId, isEnabled]) => {
  if (!currentAccountId) return;

  if (!isEnabled) {
    store.dispatch('conversationUnreadCounts/clear');
    return;
  }

  store.dispatch('conversationUnreadCounts/get');
};

const fetchSidebarSortPreferences = ([currentAccountId, userId]) => {
  if (!currentAccountId || !userId) return;
  store.dispatch('sidebarSortPreferences/initialize');
};

const toggleShortcutModalFn = show => {
  if (show) {
    emit('openKeyShortcutModal');
  } else {
    emit('closeKeyShortcutModal');
  }
};

useSidebarKeyboardShortcuts(toggleShortcutModalFn);

const expandedItem = ref(null);

const setExpandedItem = name => {
  expandedItem.value = expandedItem.value === name ? null : name;
};

const {
  sidebarWidth,
  isCollapsed,
  setSidebarWidth,
  saveWidth,
  snapToCollapsed,
  COLLAPSED_THRESHOLD,
  MAX_WIDTH,
} = useSidebarResize();

// The expanded sidebar always uses the widest allowed width
const PREFERRED_EXPANDED_WIDTH = MAX_WIDTH;

// On mobile, sidebar is always expanded (flyout mode)
const isEffectivelyCollapsed = computed(
  () => !isMobile.value && isCollapsed.value
);

// Toggle sidebar collapsed/expanded state (expands to the preferred width)
const toggleSidebar = () => {
  if (isCollapsed.value) {
    setSidebarWidth(PREFERRED_EXPANDED_WIDTH);
    saveWidth();
  } else {
    snapToCollapsed();
  }
};

// Always use the preferred width when the sidebar expands, whatever triggered it
watch(isCollapsed, isNowCollapsed => {
  if (!isNowCollapsed && !isMobile.value) {
    setSidebarWidth(PREFERRED_EXPANDED_WIDTH);
    saveWidth();
  }
});

// Resize handle logic
const isResizing = ref(false);
const startX = ref(0);
const startWidth = ref(0);

provideSidebarContext({
  expandedItem,
  setExpandedItem,
  isCollapsed: isEffectivelyCollapsed,
  sidebarWidth,
  isResizing,
});

// Get clientX from mouse or touch event
const getClientX = event =>
  event.touches ? event.touches[0].clientX : event.clientX;

const onResizeStart = event => {
  isResizing.value = true;
  startX.value = getClientX(event);
  startWidth.value = sidebarWidth.value;
  Object.assign(document.body.style, {
    cursor: 'col-resize',
    userSelect: 'none',
  });
  // Prevent default to avoid scrolling on touch
  event.preventDefault();
};

const onResizeMove = event => {
  if (!isResizing.value) return;

  const delta = isRTL.value
    ? startX.value - getClientX(event)
    : getClientX(event) - startX.value;
  setSidebarWidth(startWidth.value + delta);
};

const onResizeEnd = () => {
  if (!isResizing.value) return;

  isResizing.value = false;
  Object.assign(document.body.style, { cursor: '', userSelect: '' });

  // Snap to collapsed state if below threshold
  if (sidebarWidth.value < COLLAPSED_THRESHOLD) {
    snapToCollapsed();
  } else {
    saveWidth();
  }
};

const onResizeHandleDoubleClick = () => {
  toggleSidebar();
};

// Support both mouse and touch events
useEventListener(document, 'mousemove', onResizeMove);
useEventListener(document, 'mouseup', onResizeEnd);
useEventListener(document, 'touchmove', onResizeMove, { passive: false });
useEventListener(document, 'touchend', onResizeEnd);

const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabelsOnSidebar');
const allUnreadCount = useMapGetter(
  'conversationUnreadCounts/getAllUnreadCount'
);
const getInboxUnreadCount = useMapGetter(
  'conversationUnreadCounts/getInboxUnreadCount'
);
const getLabelUnreadCount = useMapGetter(
  'conversationUnreadCounts/getLabelUnreadCount'
);
const getTeamUnreadCount = useMapGetter(
  'conversationUnreadCounts/getTeamUnreadCount'
);
const mentionsUnreadCount = useMapGetter(
  'conversationUnreadCounts/getMentionsUnreadCount'
);
const participatingUnreadCount = useMapGetter(
  'conversationUnreadCounts/getParticipatingUnreadCount'
);
const unattendedUnreadCount = useMapGetter(
  'conversationUnreadCounts/getUnattendedUnreadCount'
);
const getFolderUnreadCount = useMapGetter(
  'conversationUnreadCounts/getFolderUnreadCount'
);
const teams = useMapGetter('teams/getMyTeams');
const contactCustomViews = useMapGetter('customViews/getContactCustomViews');
const conversationCustomViews = useMapGetter(
  'customViews/getConversationCustomViews'
);
const getSidebarSectionSort = useMapGetter(
  'sidebarSortPreferences/getSectionSort'
);

onMounted(() => {
  store.dispatch('labels/get');
  store.dispatch('inboxes/get');
  store.dispatch('notifications/unReadCount');
  store.dispatch('teams/get');
  store.dispatch('attributes/get');
  store.dispatch('customViews/get', 'conversation');
  store.dispatch('customViews/get', 'contact');

  // Keep the expanded sidebar comfortable and readable on desktop.
  if (
    !isMobile.value &&
    !isCollapsed.value &&
    sidebarWidth.value !== PREFERRED_EXPANDED_WIDTH
  ) {
    setSidebarWidth(PREFERRED_EXPANDED_WIDTH);
    saveWidth();
  }
});

watch([accountId, hasConversationUnreadCounts], fetchConversationUnreadCounts, {
  immediate: true,
});

watch([accountId, currentUserId], fetchSidebarSortPreferences, {
  immediate: true,
});

const hasUnreadCountsForSection = section => {
  if (section === SIDEBAR_SORT_SECTIONS.FOLDERS) {
    return hasFilteredUnreadCounts.value;
  }

  return hasConversationUnreadCounts.value;
};

const getSortOptionsForSection = section =>
  getSidebarSortOptions(section, {
    hasUnreadCounts: hasUnreadCountsForSection(section),
  });

const getSortForSection = section =>
  resolveSidebarSort(section, getSidebarSectionSort.value(section), {
    hasUnreadCounts: hasUnreadCountsForSection(section),
  });

const updateSortPreference = (section, sortBy) => {
  store.dispatch('sidebarSortPreferences/setSectionSort', {
    section,
    sortBy,
  });
};

const buildSortConfig = section => ({
  sortOptions: getSortOptionsForSection(section),
  activeSort: getSortForSection(section),
  onSortChange: sortBy => updateSortPreference(section, sortBy),
});

const sortedFolders = computed(() =>
  sortSidebarItems(conversationCustomViews.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.FOLDERS),
    labelKey: view => view.name,
    unreadCountKey: view => getFolderUnreadCount.value(view.id),
  })
);

const sortedTeams = computed(() =>
  sortSidebarItems(teams.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.TEAMS),
    labelKey: team => team.name,
    unreadCountKey: team => getTeamUnreadCount.value(team.id),
  })
);

const sortedInboxes = computed(() =>
  sortSidebarItems(inboxes.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.CHANNELS),
    labelKey: inbox => inbox.name,
    unreadCountKey: inbox => getInboxUnreadCount.value(inbox.id),
  })
);

const sortedLabels = computed(() =>
  sortSidebarItems(labels.value, {
    sortBy: getSortForSection(SIDEBAR_SORT_SECTIONS.LABELS),
    labelKey: label => label.title,
    unreadCountKey: label => getLabelUnreadCount.value(label.id),
  })
);

const closeMobileSidebar = () => {
  if (!props.isMobileSidebarOpen) return;
  emit('closeMobileSidebar');
};

const newReportRoutes = () => [
  {
    name: 'Reports Agent',
    label: t('SIDEBAR.REPORTS_AGENT'),
    to: accountScopedRoute('agent_reports_index'),
    activeOn: ['agent_reports_show'],
  },
  {
    name: 'Reports Label',
    label: t('SIDEBAR.REPORTS_LABEL'),
    to: accountScopedRoute('label_reports_index'),
  },
  {
    name: 'Reports Inbox',
    label: t('SIDEBAR.REPORTS_INBOX'),
    to: accountScopedRoute('inbox_reports_index'),
    activeOn: ['inbox_reports_show'],
  },
  {
    name: 'Reports Team',
    label: t('SIDEBAR.REPORTS_TEAM'),
    to: accountScopedRoute('team_reports_index'),
    activeOn: ['team_reports_show'],
  },
];

const reportRoutes = computed(() => newReportRoutes());

const menuItems = computed(() => {
  return [
    {
      name: 'Inbox',
      label: t('SIDEBAR.INBOX'),
      icon: 'i-lucide-inbox',
      to: accountScopedRoute('inbox_view'),
      activeOn: ['inbox_view', 'inbox_view_conversation'],
      getterKeys: {
        count: 'notifications/getUnreadCount',
      },
    },
    {
      name: 'Conversation',
      label: t('SIDEBAR.CONVERSATIONS'),
      icon: 'i-lucide-message-circle',
      children: [
        {
          name: 'All',
          label: t('SIDEBAR.ALL_CONVERSATIONS'),
          icon: 'i-lucide-inbox',
          badgeCount: allUnreadCount.value,
          activeOn: ['inbox_conversation'],
          to: accountScopedRoute('home'),
        },
        {
          name: 'Mentions',
          label: t('SIDEBAR.MENTIONED_CONVERSATIONS'),
          icon: 'i-lucide-at-sign',
          badgeCount: hasFilteredUnreadCounts.value
            ? mentionsUnreadCount.value
            : 0,
          activeOn: ['conversation_through_mentions'],
          to: accountScopedRoute('conversation_mentions'),
        },
        {
          name: 'Participating',
          label: t('SIDEBAR.PARTICIPATING_CONVERSATIONS'),
          icon: 'i-lucide-user-round-check',
          badgeCount: hasFilteredUnreadCounts.value
            ? participatingUnreadCount.value
            : 0,
          activeOn: ['conversation_through_participating'],
          to: accountScopedRoute('conversation_participating'),
        },
        {
          name: 'Unattended',
          activeOn: ['conversation_through_unattended'],
          label: t('SIDEBAR.UNATTENDED_CONVERSATIONS'),
          icon: 'i-lucide-clock-alert',
          badgeCount: hasFilteredUnreadCounts.value
            ? unattendedUnreadCount.value
            : 0,
          to: accountScopedRoute('conversation_unattended'),
        },
        {
          name: 'Folders',
          label: t('SIDEBAR.CUSTOM_VIEWS_FOLDER'),
          icon: 'i-lucide-folder',
          activeOn: ['conversations_through_folders'],
          ...buildSortConfig(SIDEBAR_SORT_SECTIONS.FOLDERS),
          collapsible: true,
          showTreeLine: true,
          children: sortedFolders.value.map(view => ({
            name: `${view.name}-${view.id}`,
            label: view.name,
            badgeCount: hasFilteredUnreadCounts.value
              ? getFolderUnreadCount.value(view.id)
              : 0,
            to: accountScopedRoute('folder_conversations', { id: view.id }),
          })),
        },
        {
          name: 'Teams',
          label: t('SIDEBAR.TEAMS'),
          icon: 'i-lucide-users',
          activeOn: ['conversations_through_team'],
          ...buildSortConfig(SIDEBAR_SORT_SECTIONS.TEAMS),
          collapsible: true,
          showTreeLine: true,
          children: sortedTeams.value.map(team => ({
            name: `${team.name}-${team.id}`,
            label: team.name,
            badgeCount: getTeamUnreadCount.value(team.id),
            icon: team.icon
              ? h(EmojiIcon, {
                  value: team.icon,
                  color: team.icon_color,
                  class: 'size-3.5',
                })
              : undefined,
            to: accountScopedRoute('team_conversations', { teamId: team.id }),
          })),
        },
        {
          name: 'Channels',
          label: t('SIDEBAR.CHANNELS'),
          icon: 'i-lucide-mailbox',
          activeOn: ['conversation_through_inbox'],
          ...buildSortConfig(SIDEBAR_SORT_SECTIONS.CHANNELS),
          collapsible: true,
          showTreeLine: true,
          children: sortedInboxes.value.map(inbox => ({
            name: `${inbox.name}-${inbox.id}`,
            label: inbox.name,
            badgeCount: getInboxUnreadCount.value(inbox.id),
            icon: h(ChannelIcon, { inbox, class: 'size-[16px]' }),
            to: accountScopedRoute('inbox_dashboard', { inbox_id: inbox.id }),
            component: leafProps =>
              h(ChannelLeaf, {
                label: leafProps.label,
                active: leafProps.active,
                inbox,
                badgeCount: leafProps.badgeCount,
              }),
          })),
        },
        {
          name: 'Labels',
          label: t('SIDEBAR.LABELS'),
          icon: 'i-lucide-tag',
          activeOn: ['conversations_through_label'],
          ...buildSortConfig(SIDEBAR_SORT_SECTIONS.LABELS),
          collapsible: true,
          showTreeLine: true,
          children: sortedLabels.value.map(label => ({
            name: `${label.title}-${label.id}`,
            label: label.title,
            badgeCount: getLabelUnreadCount.value(label.id),
            icon: h('span', {
              class: `size-[8px] rounded-sm`,
              style: { backgroundColor: label.color },
            }),
            to: accountScopedRoute('label_conversations', {
              label: label.title,
            }),
          })),
        },
      ],
    },
    {
      name: 'Contacts',
      label: t('SIDEBAR.CONTACTS'),
      icon: 'i-lucide-contact',
      children: [
        {
          name: 'All Contacts',
          label: t('SIDEBAR.ALL_CONTACTS'),
          to: accountScopedRoute(
            'contacts_dashboard_index',
            {},
            { page: 1, search: undefined }
          ),
          activeOn: ['contacts_dashboard_index', 'contacts_edit'],
        },
        {
          name: 'Active',
          label: t('SIDEBAR.ACTIVE'),
          to: accountScopedRoute('contacts_dashboard_active'),
          activeOn: ['contacts_dashboard_active'],
        },
        {
          name: 'Segments',
          icon: 'i-lucide-group',
          label: t('SIDEBAR.CUSTOM_VIEWS_SEGMENTS'),
          collapsible: true,
          showTreeLine: true,
          children: [
            // First, and always present. Without it this section disappeared entirely for an account with no
            // audiences, so the word never appeared in the sidebar until somebody had already made one — and
            // there was nowhere to make one from.
            {
              name: 'All Audiences',
              label: t('SIDEBAR.ALL_AUDIENCES'),
              to: accountScopedRoute('contacts_dashboard_audiences_index'),
              activeOn: ['contacts_dashboard_audiences_index'],
            },
            ...contactCustomViews.value.map(view => ({
              name: `${view.name}-${view.id}`,
              label: view.shared
                ? t('SIDEBAR.SHARED_AUDIENCE', { name: view.name })
                : view.name,
              to: accountScopedRoute(
                'contacts_dashboard_segments_index',
                { segmentId: view.id },
                { page: 1 }
              ),
              activeOn: [
                'contacts_dashboard_segments_index',
                'contacts_edit_segment',
              ],
            })),
          ],
        },
        {
          name: 'Tagged With',
          icon: 'i-lucide-tag',
          label: t('SIDEBAR.TAGGED_WITH'),
          collapsible: true,
          showTreeLine: true,
          children: labels.value.map(label => ({
            name: `${label.title}-${label.id}`,
            label: label.title,
            icon: h('span', {
              class: `size-[8px] rounded-sm`,
              style: { backgroundColor: label.color },
            }),
            to: accountScopedRoute(
              'contacts_dashboard_labels_index',
              { label: label.title },
              { page: 1, search: undefined }
            ),
            activeOn: [
              'contacts_dashboard_labels_index',
              'contacts_edit_label',
            ],
          })),
        },
      ],
    },
    {
      name: 'Companies',
      label: t('SIDEBAR.COMPANIES'),
      icon: 'i-lucide-building-2',
      children: [
        {
          name: 'All Companies',
          label: t('SIDEBAR.ALL_COMPANIES'),
          to: accountScopedRoute(
            'companies_dashboard_index',
            {},
            { page: 1, search: undefined }
          ),
          activeOn: ['companies_dashboard_index', 'companies_dashboard_show'],
        },
      ],
    },
    {
      name: 'Reports',
      label: t('SIDEBAR.REPORTS'),
      icon: 'i-lucide-chart-spline',
      children: [
        {
          name: 'Report Overview',
          label: t('SIDEBAR.REPORTS_OVERVIEW'),
          to: accountScopedRoute('account_overview_reports'),
        },
        {
          name: 'Report Conversation',
          label: t('SIDEBAR.REPORTS_CONVERSATION'),
          to: accountScopedRoute('conversation_reports'),
        },
        ...reportRoutes.value,
        {
          name: 'Reports CSAT',
          label: t('SIDEBAR.CSAT'),
          to: accountScopedRoute('csat_reports'),
        },
        {
          name: 'Reports SLA',
          label: t('SIDEBAR.REPORTS_SLA'),
          to: accountScopedRoute('sla_reports'),
        },
        {
          name: 'Reports Bot',
          label: t('SIDEBAR.REPORTS_BOT'),
          to: accountScopedRoute('bot_reports'),
        },
      ],
    },
    {
      name: 'Campaigns',
      label: t('SIDEBAR.CAMPAIGNS'),
      icon: 'i-lucide-megaphone',
      children: [
        {
          name: 'Live chat',
          label: t('SIDEBAR.LIVE_CHAT'),
          to: accountScopedRoute('campaigns_livechat_index'),
        },
        {
          name: 'SMS',
          label: t('SIDEBAR.SMS'),
          to: accountScopedRoute('campaigns_sms_index'),
        },
        {
          name: 'WhatsApp',
          label: t('SIDEBAR.WHATSAPP'),
          to: accountScopedRoute('campaigns_whatsapp_index'),
        },
      ],
    },
    {
      name: 'Portals',
      label: t('SIDEBAR.HELP_CENTER.TITLE'),
      icon: 'i-lucide-library-big',
      children: [
        {
          name: 'Articles',
          label: t('SIDEBAR.HELP_CENTER.ARTICLES'),
          activeOn: [
            'portals_articles_index',
            'portals_articles_new',
            'portals_articles_edit',
          ],
          to: accountScopedRoute('portals_index', {
            navigationPath: 'portals_articles_index',
          }),
        },
        {
          name: 'Categories',
          label: t('SIDEBAR.HELP_CENTER.CATEGORIES'),
          activeOn: [
            'portals_categories_index',
            'portals_categories_articles_index',
            'portals_categories_articles_edit',
          ],
          to: accountScopedRoute('portals_index', {
            navigationPath: 'portals_categories_index',
          }),
        },
        {
          name: 'Locales',
          label: t('SIDEBAR.HELP_CENTER.LOCALES'),
          activeOn: ['portals_locales_index'],
          to: accountScopedRoute('portals_index', {
            navigationPath: 'portals_locales_index',
          }),
        },
        {
          name: 'Settings',
          label: t('SIDEBAR.HELP_CENTER.SETTINGS'),
          activeOn: ['portals_settings_index'],
          to: accountScopedRoute('portals_index', {
            navigationPath: 'portals_settings_index',
          }),
        },
      ],
    },
    {
      name: 'Settings',
      label: t('SIDEBAR.SETTINGS'),
      icon: 'i-lucide-bolt',
      // Twenty entries in one flat list, grouped into six labelled sections. The sections are
      // deliberately NOT collapsible: a heading groups the list without putting anything one click
      // further away, so every route stays exactly as reachable as it was — in the expanded sidebar,
      // in the collapsed popover, and on a phone.
      children: [
        {
          name: 'Settings Account',
          label: t('SIDEBAR.SETTINGS_GROUPS.ACCOUNT'),
          icon: 'i-lucide-building',
          collapsible: false,
          children: [
            {
              name: 'Settings Account Settings',
              label: t('SIDEBAR.ACCOUNT_SETTINGS'),
              icon: 'i-lucide-briefcase',
              to: accountScopedRoute('general_settings_index'),
            },
            {
              name: 'Settings Billing',
              label: t('SIDEBAR.BILLING'),
              icon: 'i-lucide-credit-card',
              to: accountScopedRoute('billing_settings_index'),
            },
            {
              name: 'Settings Subscription',
              label: t('SIDEBAR.SUBSCRIPTION'),
              icon: 'i-lucide-wallet',
              to: accountScopedRoute('subscription_settings_index'),
            },
          ],
        },
        {
          name: 'Settings People',
          label: t('SIDEBAR.SETTINGS_GROUPS.PEOPLE'),
          icon: 'i-lucide-users-round',
          collapsible: false,
          children: [
            {
              name: 'Settings Agents',
              label: t('SIDEBAR.AGENTS'),
              icon: 'i-lucide-square-user',
              to: accountScopedRoute('agent_list'),
            },
            {
              name: 'Settings Teams',
              label: t('SIDEBAR.TEAMS'),
              icon: 'i-lucide-users',
              activeOn: [
                'settings_teams_list',
                'settings_teams_new',
                'settings_teams_finish',
                'settings_teams_add_agents',
                'settings_teams_show',
                'settings_teams_edit',
                'settings_teams_edit_members',
                'settings_teams_edit_finish',
              ],
              to: accountScopedRoute('settings_teams_list'),
            },
            ...(hasAdvancedAssignment.value
              ? [
                  {
                    name: 'Settings Agent Assignment',
                    label: t('SIDEBAR.AGENT_ASSIGNMENT'),
                    icon: 'i-lucide-user-cog',
                    activeOn: [
                      'assignment_policy_index',
                      'agent_assignment_policy_index',
                      'agent_assignment_policy_create',
                      'agent_assignment_policy_edit',
                      'agent_capacity_policy_index',
                      'agent_capacity_policy_create',
                      'agent_capacity_policy_edit',
                    ],
                    to: accountScopedRoute('assignment_policy_index'),
                  },
                ]
              : []),
          ],
        },
        {
          name: 'Settings Channels',
          label: t('SIDEBAR.SETTINGS_GROUPS.CHANNELS'),
          icon: 'i-lucide-radio-tower',
          collapsible: false,
          children: [
            {
              name: 'Settings Inboxes',
              label: t('SIDEBAR.INBOXES'),
              icon: 'i-lucide-inbox',
              activeOn: [
                'settings_inbox_list',
                'settings_inbox_show',
                'settings_inbox_new',
                'settings_inbox_finish',
                'settings_inboxes_page_channel',
                'settings_inboxes_add_agents',
              ],
              to: accountScopedRoute('settings_inbox_list'),
            },
            {
              name: 'Settings Templates',
              label: t('SIDEBAR.WHATSAPP_TEMPLATES'),
              icon: 'i-lucide-layout-template',
              to: accountScopedRoute('settings_templates'),
            },
            {
              name: 'Settings Commerce',
              label: t('SIDEBAR.COMMERCE'),
              icon: 'i-lucide-store',
              to: accountScopedRoute('settings_commerce_index'),
            },
            {
              name: 'Settings Integrations',
              label: t('SIDEBAR.INTEGRATIONS'),
              icon: 'i-lucide-blocks',
              to: accountScopedRoute('settings_applications'),
            },
          ],
        },
        {
          name: 'Settings Automation',
          label: t('SIDEBAR.SETTINGS_GROUPS.AUTOMATION'),
          icon: 'i-lucide-zap',
          collapsible: false,
          children: [
            {
              name: 'Settings Automation Rules',
              label: t('SIDEBAR.AUTOMATION'),
              icon: 'i-lucide-repeat',
              to: accountScopedRoute('automation_list'),
            },
            {
              name: 'Settings Flow Builder',
              label: t('SIDEBAR.FLOW_BUILDER'),
              icon: 'i-lucide-workflow',
              to: accountScopedRoute('settings_flows_index'),
            },
            {
              name: 'Settings Agent Bots',
              label: t('SIDEBAR.AGENT_BOTS'),
              icon: 'i-lucide-bot',
              to: accountScopedRoute('agent_bots'),
            },
            {
              name: 'Settings Macros',
              label: t('SIDEBAR.MACROS'),
              icon: 'i-lucide-toy-brick',
              to: accountScopedRoute('macros_wrapper'),
            },
            {
              name: 'Conversation Workflow',
              label: t('SIDEBAR.CONVERSATION_WORKFLOW'),
              icon: 'i-lucide-list-checks',
              to: accountScopedRoute('conversation_workflow_index'),
            },
          ],
        },
        {
          name: 'Settings Conversation Data',
          label: t('SIDEBAR.SETTINGS_GROUPS.CONVERSATION_DATA'),
          icon: 'i-lucide-library',
          collapsible: false,
          children: [
            {
              name: 'Settings Labels',
              label: t('SIDEBAR.LABELS'),
              icon: 'i-lucide-tags',
              to: accountScopedRoute('labels_list'),
            },
            {
              name: 'Settings Custom Attributes',
              label: t('SIDEBAR.CUSTOM_ATTRIBUTES'),
              icon: 'i-lucide-code',
              to: accountScopedRoute('attributes_list'),
            },
            {
              name: 'Settings Canned Responses',
              label: t('SIDEBAR.CANNED_RESPONSES'),
              icon: 'i-lucide-message-square-quote',
              to: accountScopedRoute('canned_list'),
            },
          ],
        },
        {
          name: 'Settings Records',
          label: t('SIDEBAR.SETTINGS_GROUPS.RECORDS'),
          icon: 'i-lucide-archive',
          collapsible: false,
          children: [
            ...(hasDataImport.value
              ? [
                  {
                    name: 'Settings Data',
                    label: t('SIDEBAR.DATA'),
                    icon: 'i-lucide-database',
                    to: accountScopedRoute('settings_data_imports'),
                  },
                ]
              : []),
            {
              name: 'Settings Audit Logs',
              label: t('SIDEBAR.AUDIT_LOGS'),
              icon: 'i-lucide-scroll-text',
              to: accountScopedRoute('auditlogs_list'),
            },
          ],
        },
      ],
    },
  ];
});
</script>

<template>
  <aside
    v-on-click-outside="[
      closeMobileSidebar,
      {
        ignore: [
          '#mobile-sidebar-launcher',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="sidebar-shell flex flex-col text-sm pb-px fixed top-0 ltr:left-0 rtl:right-0 h-full z-40 w-[332px] max-w-[92vw] md:w-auto md:relative md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0"
    :class="[
      {
        'shadow-2xl md:shadow-none': isMobileSidebarOpen,
        'ltr:-translate-x-full rtl:translate-x-full': !isMobileSidebarOpen,
        'transition-transform duration-300 ease-out md:transition-[width]':
          !isResizing,
        'sidebar-expanded': !isCollapsed,
      },
    ]"
    :style="isMobile ? undefined : { width: `${sidebarWidth}px` }"
  >
    <div
      class="sidebar-aurora"
      aria-hidden="true"
      :style="isEffectivelyCollapsed ? { display: 'none' } : undefined"
    />

    <section
      class="sidebar-header grid relative z-10"
      :class="isEffectivelyCollapsed ? 'mt-3 mb-6 gap-4' : 'mt-0 mb-4 gap-3'"
    >
      <div
        class="sidebar-account flex gap-2 items-center min-w-0"
        :class="{
          'justify-center px-1 pt-2': isEffectivelyCollapsed,
          'px-3 pt-3': !isEffectivelyCollapsed,
        }"
      >
        <template v-if="isEffectivelyCollapsed">
          <div class="flex flex-col items-center gap-2.5">
            <SidebarAccountSwitcher
              is-collapsed
              @show-create-account-modal="emit('showCreateAccountModal')"
            />
            <button
              v-if="!isMobile"
              type="button"
              class="sidebar-toggle-btn hidden md:flex items-center justify-center size-8 rounded-xl"
              :title="t('SIDEBAR.EXPAND_SIDEBAR')"
              @click="toggleSidebar"
            >
              <span class="i-lucide-chevron-right size-4 rtl:rotate-180" />
            </button>
          </div>
        </template>
        <template v-else>
          <div
            class="sidebar-logo grid flex-shrink-0 place-content-center size-10"
          >
            <Logo class="size-5" />
          </div>
          <SidebarAccountSwitcher
            class="sidebar-account-switcher flex-grow min-w-0"
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
          <button
            v-if="!isMobile"
            type="button"
            class="sidebar-toggle-btn hidden md:flex flex-shrink-0 items-center justify-center size-8 rounded-xl"
            :title="t('SIDEBAR.COLLAPSE_SIDEBAR')"
            @click="toggleSidebar"
          >
            <span class="i-lucide-chevron-left size-4 rtl:rotate-180" />
          </button>
        </template>
      </div>

      <div
        class="sidebar-actions flex gap-2"
        :class="isEffectivelyCollapsed ? 'flex-col items-center' : 'px-3'"
      >
        <RouterLink
          v-if="!isEffectivelyCollapsed"
          :to="{ name: 'search' }"
          class="sidebar-search group flex gap-2 items-center px-3 py-2 w-full h-9 rounded-xl transition-all duration-300 ease-out"
        >
          <span
            class="sidebar-search-icon flex-shrink-0 i-lucide-search size-4"
          />
          <span class="flex-grow text-start truncate">
            {{ t('COMBOBOX.SEARCH_PLACEHOLDER') }}
          </span>
          <span
            class="sidebar-shortcut tracking-wide pointer-events-none select-none"
          >
            {{ searchShortcut }}
          </span>
        </RouterLink>

        <RouterLink
          v-else
          :to="{ name: 'search' }"
          class="sidebar-search sidebar-icon-button flex items-center justify-center size-9 rounded-xl transition-all duration-300 ease-out"
          :title="t('COMBOBOX.SEARCH_PLACEHOLDER')"
        >
          <span class="i-lucide-search size-4" />
        </RouterLink>

        <ComposeConversation align="start">
          <template #trigger="{ isOpen }">
            <Button
              icon="i-lucide-pen-line"
              :aria-label="t('SIDEBAR.COMPOSE_CONVERSATION')"
              color="slate"
              size="sm"
              class="sidebar-compose"
              :class="[
                isEffectivelyCollapsed ? '!size-9' : '!h-9 !px-3',
                { 'sidebar-compose-active': isOpen },
              ]"
            />
          </template>
        </ComposeConversation>
      </div>
    </section>

    <nav
      class="sidebar-nav relative z-10 grid overflow-y-scroll flex-grow gap-2 pb-5 no-scrollbar min-w-0"
      :class="isEffectivelyCollapsed ? 'px-1.5' : 'px-3'"
    >
      <ul
        class="flex flex-col gap-1.5 m-0 list-none min-w-0"
        :class="{ 'items-center': isEffectivelyCollapsed }"
      >
        <SidebarGroup
          v-for="item in menuItems"
          :key="item.name"
          v-bind="item"
        />
      </ul>
    </nav>

    <section
      class="sidebar-footer flex relative flex-col flex-shrink-0 gap-1 justify-between items-center z-10"
    >
      <div
        class="sidebar-bottom-fade pointer-events-none absolute inset-x-0 -top-10 h-10"
      />

      <SidebarChangelogCard
        v-if="
          isOnChatwootCloud &&
          !isACustomBrandedInstance &&
          !isEffectivelyCollapsed
        "
      />
      <SidebarChangelogButton
        v-if="
          isOnChatwootCloud &&
          !isACustomBrandedInstance &&
          isEffectivelyCollapsed
        "
      />

      <div
        class="sidebar-profile px-1.5 py-2 flex-shrink-0 flex w-full z-50 gap-2 items-center"
        :class="isEffectivelyCollapsed ? 'justify-center' : 'justify-between'"
      >
        <SidebarProfileMenu
          :is-collapsed="isEffectivelyCollapsed"
          @open-key-shortcut-modal="emit('openKeyShortcutModal')"
        />
      </div>
    </section>

    <div
      class="sidebar-resize hidden md:block absolute top-0 h-full w-1.5 cursor-col-resize z-40 ltr:right-0 rtl:left-0 group"
      :title="t('SIDEBAR.RESIZE_SIDEBAR')"
      @mousedown="onResizeStart"
      @touchstart="onResizeStart"
      @dblclick="onResizeHandleDoubleClick"
    >
      <div
        class="sidebar-resize-line absolute top-0 h-full w-px ltr:right-0 rtl:left-0 transition-all duration-300"
        :class="{ 'is-resizing': isResizing }"
      />
    </div>
  </aside>
</template>

<style scoped>
.sidebar-shell {
  --sb-bg: #071225;
  --sb-blue: #2f6fe4;
  --sb-blue-glow: rgba(64, 122, 240, 0.5);
  --sb-pink: #db2777;
  --sb-pink-soft: rgba(219, 39, 119, 0.16);
  --sb-pink-border: rgba(219, 39, 119, 0.3);
  --sb-pink-text: #f8b8d4;
  --sb-text: #ffffff;
  --sb-muted: #d6e3fb;

  isolation: isolate;
  overflow: hidden;
  color: var(--sb-text);
  border-inline-end: 1px solid rgba(47, 111, 228, 0.28);
  background: radial-gradient(
      circle at 14% 5%,
      rgba(47, 111, 228, 0.34),
      transparent 34%
    ),
    radial-gradient(
      circle at 88% 24%,
      rgba(219, 39, 119, 0.16),
      transparent 30%
    ),
    linear-gradient(165deg, #0d2148 0%, #09172f 36%, #071225 68%, #07101f 100%);
  box-shadow:
    inset -1px 0 0 rgba(255, 255, 255, 0.035),
    0 10px 22px -8px rgba(64, 122, 240, 0.5),
    18px 0 48px rgba(2, 9, 22, 0.28);
}

.sidebar-shell::after {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 0;
  pointer-events: none;
  opacity: 0.2;
  background-image: linear-gradient(
    112deg,
    transparent 0%,
    rgba(255, 255, 255, 0.045) 46%,
    transparent 55%
  );
  background-size: 230% 100%;
  animation: sidebar-shimmer 11s linear infinite;
}

.sidebar-aurora {
  position: absolute;
  z-index: 0;
  top: -7rem;
  left: -5rem;
  width: 19rem;
  height: 19rem;
  pointer-events: none;
  border-radius: 9999px;
  opacity: 0.38;
  filter: blur(70px);
  background: conic-gradient(
    from 115deg,
    rgba(47, 111, 228, 0.95),
    rgba(219, 39, 119, 0.68),
    rgba(47, 111, 228, 0.9)
  );
  animation: sidebar-aurora 15s ease-in-out infinite alternate;
}

.sidebar-header {
  padding-top: 0;
}

.sidebar-account {
  min-height: 4rem;
  gap: 0.75rem;
}

.sidebar-toggle-btn {
  color: var(--sb-muted);
  border: 1px solid rgba(93, 142, 239, 0.24);
  background: rgba(47, 111, 228, 0.1);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.06),
    0 4px 12px rgba(0, 0, 0, 0.12);
  backdrop-filter: blur(14px);
  cursor: pointer;
  transition: all 200ms cubic-bezier(0.22, 1, 0.36, 1);
}

.sidebar-toggle-btn:hover {
  color: var(--sb-pink-text);
  border-color: var(--sb-pink-border);
  background: var(--sb-pink-soft);
  transform: translateY(-1px) scale(1.05);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    0 8px 18px -4px rgba(219, 39, 119, 0.4);
}

.sidebar-toggle-btn:active {
  transform: translateY(0) scale(0.96);
}

.sidebar-logo {
  position: relative;
  border: 1px solid rgba(111, 157, 248, 0.36);
  border-radius: 0.95rem;
  color: #fff;
  background: linear-gradient(
      145deg,
      rgba(47, 111, 228, 0.42),
      rgba(47, 111, 228, 0.18)
    ),
    rgba(255, 255, 255, 0.05);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.16),
    0 10px 22px -8px rgba(64, 122, 240, 0.5);
}

.sidebar-logo::after {
  content: '';
  position: absolute;
  inset: -3px;
  z-index: -1;
  border-radius: 1.05rem;
  opacity: 0.32;
  background: linear-gradient(
    135deg,
    rgba(47, 111, 228, 0.78),
    rgba(219, 39, 119, 0.32)
  );
  filter: blur(10px);
  transition:
    opacity 220ms ease,
    transform 220ms ease;
}

.sidebar-account:hover .sidebar-logo::after {
  opacity: 0.58;
  transform: scale(1.04);
}

.sidebar-account-switcher {
  padding: 0.3rem 0.4rem;
  border: 1px solid transparent;
  border-radius: 0.9rem;
  color: #fff;
  transition:
    background-color 180ms ease,
    border-color 180ms ease,
    box-shadow 180ms ease;
}

.sidebar-account-switcher:hover {
  border-color: rgba(47, 111, 228, 0.2);
  background: rgba(47, 111, 228, 0.09);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.04);
}

.sidebar-search {
  position: relative;
  overflow: hidden;
  color: #f1f5ff;
  border: 1px solid rgba(93, 142, 239, 0.24);
  outline: none;
  background: rgba(47, 111, 228, 0.1);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.06),
    0 8px 20px rgba(0, 0, 0, 0.14);
  backdrop-filter: blur(14px);
}

.sidebar-search::before {
  content: '';
  position: absolute;
  top: 0;
  bottom: 0;
  left: -45%;
  width: 34%;
  pointer-events: none;
  transform: skewX(-20deg);
  background: linear-gradient(
    90deg,
    transparent,
    rgba(255, 255, 255, 0.15),
    transparent
  );
  transition: left 520ms cubic-bezier(0.22, 1, 0.36, 1);
}

.sidebar-search:hover {
  color: var(--sb-pink-text);
  border-color: var(--sb-pink-border);
  background: var(--sb-pink-soft);
  transform: translateY(-1px);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    0 10px 22px -8px rgba(64, 122, 240, 0.5);
}

.sidebar-search:hover::before {
  left: 125%;
}

.sidebar-search-icon {
  color: #9fc0ff;
  filter: drop-shadow(0 0 7px rgba(47, 111, 228, 0.32));
  transition:
    color 180ms ease,
    transform 260ms cubic-bezier(0.22, 1, 0.36, 1);
}

.sidebar-search:hover .sidebar-search-icon {
  color: var(--sb-pink-text);
  transform: rotate(-8deg) scale(1.08);
}

.sidebar-shortcut {
  padding: 0.12rem 0.42rem;
  border: 1px solid rgba(135, 166, 225, 0.2);
  border-radius: 0.45rem;
  color: #d4e1fb;
  background: rgba(4, 12, 27, 0.32);
  font-size: 0.65rem;
  line-height: 1rem;
}

.sidebar-compose {
  color: #fff !important;
  border: 1px solid rgba(47, 111, 228, 0.34) !important;
  border-radius: 0.8rem !important;
  outline: none !important;
  background: linear-gradient(
    135deg,
    rgba(47, 111, 228, 0.78),
    rgba(47, 111, 228, 0.48)
  ) !important;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.13),
    0 10px 22px -8px rgba(64, 122, 240, 0.5) !important;
  transition:
    transform 220ms cubic-bezier(0.22, 1, 0.36, 1),
    box-shadow 220ms ease,
    border-color 220ms ease,
    background 220ms ease !important;
}

.sidebar-compose:hover,
.sidebar-compose-active {
  color: var(--sb-pink-text) !important;
  transform: translateY(-1px) scale(1.015);
  border-color: var(--sb-pink-border) !important;
  background: var(--sb-pink-soft) !important;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.1),
    0 10px 22px -8px rgba(64, 122, 240, 0.5) !important;
}

.sidebar-nav {
  mask-image: linear-gradient(
    to bottom,
    transparent 0,
    #000 12px,
    #000 calc(100% - 12px),
    transparent 100%
  );
}

.sidebar-nav :deep(a),
.sidebar-nav :deep(button) {
  position: relative;
  isolation: isolate;
  overflow: hidden;
  border: 1px solid transparent;
  border-radius: 0.82rem;
  color: #eef4ff;
  background: rgba(47, 111, 228, 0.035);
  text-shadow: 0 1px 1px rgba(0, 0, 0, 0.18);
  transition:
    color 180ms ease,
    transform 240ms cubic-bezier(0.22, 1, 0.36, 1),
    background-color 180ms ease,
    border-color 180ms ease,
    box-shadow 240ms ease;
}

.sidebar-nav :deep(a::before),
.sidebar-nav :deep(button::before) {
  content: '';
  position: absolute;
  z-index: -1;
  inset: 0;
  opacity: 0;
  background: linear-gradient(
    100deg,
    rgba(219, 39, 119, 0.16),
    rgba(47, 111, 228, 0.12)
  );
  transition: opacity 180ms ease;
}

.sidebar-nav :deep(a::after),
.sidebar-nav :deep(button::after) {
  content: '';
  position: absolute;
  z-index: -1;
  top: 18%;
  bottom: 18%;
  inset-inline-start: 0;
  width: 3px;
  border-radius: 99px;
  opacity: 0;
  transform: scaleY(0.35);
  background: linear-gradient(to bottom, #79a6ff, #db2777);
  box-shadow: 0 0 14px rgba(64, 122, 240, 0.58);
  transition:
    opacity 180ms ease,
    transform 220ms cubic-bezier(0.22, 1, 0.36, 1);
}

.sidebar-nav :deep(a:hover),
.sidebar-nav :deep(button:hover) {
  color: var(--sb-pink-text);
  border-color: var(--sb-pink-border);
  background: var(--sb-pink-soft);
  transform: translateX(3px);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.07),
    0 10px 22px -8px rgba(64, 122, 240, 0.5);
}

.sidebar-nav :deep(a:hover::before),
.sidebar-nav :deep(button:hover::before) {
  opacity: 1;
}

.sidebar-nav :deep(a:hover::after),
.sidebar-nav :deep(button:hover::after),
.sidebar-nav :deep(a.router-link-active::after),
.sidebar-nav :deep(a.router-link-exact-active::after),
.sidebar-nav :deep(a[aria-current='page']::after) {
  opacity: 1;
  transform: scaleY(1);
}

.sidebar-nav :deep(a.router-link-active),
.sidebar-nav :deep(a.router-link-exact-active),
.sidebar-nav :deep(a[aria-current='page']) {
  color: #fff;
  border-color: rgba(89, 140, 240, 0.42);
  background: linear-gradient(
    100deg,
    rgba(47, 111, 228, 0.25),
    rgba(219, 39, 119, 0.12)
  );
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.08),
    0 10px 22px -8px rgba(64, 122, 240, 0.5);
}

.sidebar-nav :deep([class*='i-lucide-']),
.sidebar-nav :deep([class*='i-woot-']) {
  color: #b9d0ff;
  filter: drop-shadow(0 0 5px rgba(47, 111, 228, 0.18));
  transition:
    color 180ms ease,
    transform 240ms cubic-bezier(0.22, 1, 0.36, 1),
    filter 180ms ease;
}

.sidebar-nav :deep(a:hover [class*='i-lucide-']),
.sidebar-nav :deep(button:hover [class*='i-lucide-']),
.sidebar-nav :deep(a:hover [class*='i-woot-']),
.sidebar-nav :deep(button:hover [class*='i-woot-']) {
  color: var(--sb-pink-text);
  transform: scale(1.08) rotate(-3deg);
  filter: drop-shadow(0 0 7px rgba(219, 39, 119, 0.34));
}

.sidebar-nav :deep([class*='badge']),
.sidebar-nav :deep([data-badge]) {
  border: 1px solid var(--sb-pink-border);
  background: var(--sb-pink-soft);
  color: var(--sb-pink-text);
  box-shadow: 0 5px 14px -8px rgba(219, 39, 119, 0.8);
}

.sidebar-bottom-fade {
  background: linear-gradient(to top, var(--sb-bg) 8%, transparent);
}

.sidebar-profile {
  border-top: 1px solid rgba(87, 132, 220, 0.18);
  background: linear-gradient(
    180deg,
    rgba(7, 18, 37, 0.74),
    rgba(5, 12, 25, 0.96)
  );
  box-shadow: 0 -10px 28px rgba(3, 10, 24, 0.2);
  backdrop-filter: blur(16px);
}

/* Only style the profile TRIGGER */
.sidebar-profile :deep(.relative.min-w-0 > button) {
  color: #f5f8ff;
  border-radius: 0.78rem;
  transition:
    color 180ms ease,
    background-color 180ms ease,
    transform 200ms cubic-bezier(0.22, 1, 0.36, 1),
    box-shadow 180ms ease;
}

.sidebar-profile :deep(.relative.min-w-0 > button:hover) {
  color: var(--sb-pink-text);
  background: var(--sb-pink-soft);
  transform: translateY(-1px);
  box-shadow: 0 10px 22px -8px rgba(64, 122, 240, 0.5);
}

/* Profile trigger text only */
.sidebar-profile :deep(.relative.min-w-0 > button .text-n-slate-12) {
  color: rgb(255 119 224) !important;
}

.sidebar-profile :deep(.relative.min-w-0 > button .text-n-slate-11) {
  color: #ffffff !important;
}

.sidebar-resize-line {
  background: transparent;
}

.sidebar-resize:hover .sidebar-resize-line,
.sidebar-resize-line.is-resizing {
  width: 2px;
  background: linear-gradient(
    to bottom,
    transparent,
    #2f6fe4,
    #db2777,
    transparent
  );
  box-shadow: 0 0 14px rgba(64, 122, 240, 0.7);
}

/* Vue compiles `:global(X) …` to `X` alone: the ancestor selector must stay plain, or every [dir=rtl] element moves. */
[dir='rtl'] .sidebar-nav :deep(a:hover),
[dir='rtl'] .sidebar-nav :deep(button:hover) {
  transform: translateX(-3px);
}

@keyframes sidebar-aurora {
  0% {
    transform: translate3d(-6%, -8%, 0) rotate(0deg) scale(0.94);
  }
  55% {
    transform: translate3d(42%, 18%, 0) rotate(100deg) scale(1.04);
  }
  100% {
    transform: translate3d(18%, 58%, 0) rotate(205deg) scale(0.96);
  }
}

@keyframes sidebar-shimmer {
  to {
    background-position: -230% 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .sidebar-shell::after,
  .sidebar-aurora {
    animation: none;
  }

  .sidebar-search,
  .sidebar-compose,
  .sidebar-toggle-btn,
  .sidebar-nav :deep(a),
  .sidebar-nav :deep(button),
  .sidebar-nav :deep([class*='i-lucide-']),
  .sidebar-nav :deep([class*='i-woot-']) {
    transition-duration: 0.01ms !important;
  }
}

/* Custom font overrides */
.sidebar-shell.text-sm {
  font-size: 1.1rem !important;
}

.sidebar-shell :deep(.text-sm) {
  font-size: 1.1rem !important;
}

.sidebar-shell .sidebar-logo {
  background: #ffffff9c !important;
  width: 3.5rem !important;
  height: 3.5rem !important;
  padding: 2px !important;
}

.sidebar-shell .sidebar-logo :deep(svg),
.sidebar-shell .sidebar-logo :deep(img),
.sidebar-shell .sidebar-logo img {
  width: 99% !important;
  height: 99% !important;
  max-width: none !important;
  max-height: none !important;
}

.sidebar-nav :deep(.text-n-slate-9),
.sidebar-nav :deep(.text-n-slate-10),
.sidebar-nav :deep(.text-n-slate-11) {
  color: rgba(255, 255, 255, 0.88) !important;
}

.sidebar-nav :deep(.text-n-slate-12) {
  color: rgb(255 119 224) !important;
}

.sidebar-nav :deep(a:hover .text-n-slate-9),
.sidebar-nav :deep(a:hover .text-n-slate-10),
.sidebar-nav :deep(a:hover .text-n-slate-11),
.sidebar-nav :deep(button:hover .text-n-slate-9),
.sidebar-nav :deep(button:hover .text-n-slate-10),
.sidebar-nav :deep(button:hover .text-n-slate-11) {
  color: #ffffff !important;
}

.sidebar-nav :deep(li .text-n-slate-12) {
  color: rgb(255 119 224) !important;
}

.sidebar-shell :deep(#sidebar-account-switcher span) {
  color: #f2478d !important;
  font-size: 1.5rem !important;
  font-weight: 700 !important;
}
.sidebar-shell {
  --sb-bg: #071225;
  --sb-blue: #2f6fe4;
  --sb-blue-glow: rgba(64, 122, 240, 0.5);
  --sb-pink: #db2777;
  --sb-pink-soft: rgba(219, 39, 119, 0.16);
  --sb-pink-border: rgba(219, 39, 119, 0.3);
  --sb-pink-text: #f8b8d4;
  --sb-text: #ffffff;
  --sb-muted: #d6e3fb;

  isolation: isolate;
  overflow: visible; /* collapsed: let tooltips and popovers overflow the sidebar */
  color: var(--sb-text);
  border-inline-end: 1px solid rgba(47, 111, 228, 0.28);
  background: radial-gradient(
      circle at 14% 5%,
      rgba(47, 111, 228, 0.34),
      transparent 34%
    ),
    radial-gradient(
      circle at 88% 24%,
      rgba(219, 39, 119, 0.16),
      transparent 30%
    ),
    linear-gradient(165deg, #0d2148 0%, #09172f 36%, #071225 68%, #07101f 100%);
  box-shadow:
    inset -1px 0 0 rgba(255, 255, 255, 0.035),
    0 10px 22px -8px rgba(64, 122, 240, 0.5),
    18px 0 48px rgba(2, 9, 22, 0.28);
}

/* expanded: clip the decorative background inside the sidebar */
.sidebar-shell.sidebar-expanded {
  overflow: hidden;
}
</style>
