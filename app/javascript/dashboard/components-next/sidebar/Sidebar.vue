<script setup>
import { h, ref, computed, onMounted, watch } from 'vue';
import { provideSidebarContext, useSidebarResize } from './provider';
import { useAccount } from 'dashboard/composables/useAccount';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useSidebarKeyboardShortcuts } from './useSidebarKeyboardShortcuts';
import { navigableEntries } from './navigationContract';
import { usePlatformSupportUnread } from 'dashboard/routes/dashboard/help/platformSupportStore';
import { vOnClickOutside } from '@vueuse/components';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useBranding } from 'shared/composables/useBranding';
import { useWindowSize, useEventListener, useScroll } from '@vueuse/core';

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

// THE NAVIGATION'S FADE IS A SCROLL AFFORDANCE, SO IT ONLY APPEARS WHERE THERE IS SOMETHING TO SCROLL TO.
//
// It used to be one unconditional `mask-image` fading the first and last 12px of the scroll box, whether or
// not either end had anything beyond it. Measured in the browser at 1440x900 on an account whose navigation
// fits: scrollHeight 726, clientHeight 714, scrollTop 0 -- so the box "overflows" by 12px that are entirely
// its own `pb-5`, and a fade was drawn over the foot of a list that had nothing below it.
//
// WHAT THIS DOES NOT FIX, because it was measured and it is not this: the last item ("Settings") renders
// dimmer than its siblings in both the old and the new build -- peak glyph luminance (124,131,144) before
// and (121,131,144) after, against (176,180,186) for "Help & Support". That is the item's own colour, not
// the mask. This change is about the affordance being honest, not about that item.
//
// `offset.bottom` is the padding, so "arrived at the bottom" means "nothing but padding is left"; the two
// ends are then independent, and a nav that does not scroll carries no mask at all (verified: computed
// `mask-image` is now `none` on that account, where it was the gradient). The three values are written as
// whole literal strings because Tailwind generates a rule only for a class it can see in a scanned file,
// and a mask assembled from fragments at runtime would be purged.
const navRef = ref(null);
const { arrivedState: navArrived } = useScroll(navRef, {
  offset: { bottom: 20 },
});

const NAV_FADE_TOP =
  '[mask-image:linear-gradient(to_bottom,transparent_0,#000_12px)]';
const NAV_FADE_BOTTOM =
  '[mask-image:linear-gradient(to_bottom,#000_calc(100%-12px),transparent_100%)]';
const NAV_FADE_BOTH =
  '[mask-image:linear-gradient(to_bottom,transparent_0,#000_12px,#000_calc(100%-12px),transparent_100%)]';

const navFadeClass = computed(() => {
  if (navArrived.top && navArrived.bottom) return '';
  if (navArrived.top) return NAV_FADE_BOTTOM;
  if (navArrived.bottom) return NAV_FADE_TOP;
  return NAV_FADE_BOTH;
});

const { accountScopedRoute, isOnChatwootCloud } = useAccount();
const store = useStore();

const searchShortcut = useKbd([`$mod`, 'k']);
const { t } = useI18n();
// Lynomia owns the documentation, so the dashboard links out to it rather than letting a tenant author its own
// (docs/global-documentation/12-contextual-help.md). brandLink returns '' when an installation has configured no
// destination, and the Help & Support children filter those out rather than rendering a dead link.
const { brandLink } = useBranding();
const documentationUrl = computed(() => brandLink('documentation'));
const supportUrl = computed(() => brandLink('support'));

const isACustomBrandedInstance = useMapGetter(
  'globalConfig/isACustomBrandedInstance'
);
const isRTL = useMapGetter('accounts/isRTL');

// The Platform Support Desk's unread count, read from THAT MODULE'S OWN STORE and never from `notifications`.
// The number is derived server side from the ticket's own columns, so the badge cannot disagree with the
// thread; a feed row could (dashboard/routes/dashboard/help/platformSupportStore.js).
const { unreadCount: platformSupportUnreadCount } = usePlatformSupportUnread();

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

const hasSupportTickets = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.LYNOMIA_SUPPORT_TICKETS
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
    ...(hasSupportTickets.value
      ? [
          {
            // Lynomia Support cases. A leaf rather than a group: the workspace is one screen whose views are
            // query parameters, so a group here would be six entries that all open the same page.
            name: 'Support',
            label: t('SIDEBAR.SUPPORT'),
            icon: 'i-lucide-ticket',
            to: accountScopedRoute('support_tickets_index'),
            activeOn: ['support_tickets_index', 'support_tickets_show'],
          },
        ]
      : []),
    {
      name: 'Analytics',
      label: t('SIDEBAR.ANALYTICS'),
      icon: 'i-lucide-chart-no-axes-combined',
      children: [
        {
          name: 'Analytics Overview',
          label: t('SIDEBAR.ANALYTICS_OVERVIEW'),
          to: accountScopedRoute('analytics_overview'),
        },
        {
          name: 'Analytics WhatsApp',
          label: t('SIDEBAR.ANALYTICS_WHATSAPP'),
          to: accountScopedRoute('analytics_whatsapp'),
        },
        {
          name: 'Analytics Campaigns',
          label: t('SIDEBAR.ANALYTICS_CAMPAIGNS'),
          to: accountScopedRoute('analytics_campaigns'),
        },
        {
          name: 'Analytics Automations',
          label: t('SIDEBAR.ANALYTICS_AUTOMATIONS'),
          to: accountScopedRoute('analytics_automations'),
        },
        {
          name: 'Analytics Flows',
          label: t('SIDEBAR.ANALYTICS_FLOWS'),
          to: accountScopedRoute('analytics_flows'),
        },
        {
          name: 'Analytics Commerce',
          label: t('SIDEBAR.ANALYTICS_COMMERCE'),
          to: accountScopedRoute('analytics_commerce'),
        },
        ...(hasSupportTickets.value
          ? [
              {
                name: 'Analytics Tickets',
                label: t('SIDEBAR.ANALYTICS_TICKETS'),
                to: accountScopedRoute('analytics_tickets'),
              },
            ]
          : []),
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
      name: 'HelpAndSupport',
      label: t('SIDEBAR.HELP_AND_SUPPORT.TITLE'),
      icon: 'i-lucide-life-buoy',
      children: navigableEntries([
        // The in-product destination first: a customer with a question about Lynomia should reach Lynomia
        // before they reach a link that leaves the product (docs/platform-support/04-customer-ux.md §2).
        // Never feature-gated -- the route carries no featureFlag, so the entry is visible to every member.
        {
          name: 'PlatformSupportMyTickets',
          label: t('PLATFORM_SUPPORT.SIDEBAR.MY_TICKETS'),
          icon: 'i-lucide-message-square-warning',
          badgeCount: platformSupportUnreadCount.value,
          activeOn: [
            'platform_support_tickets_index',
            'platform_support_tickets_show',
          ],
          to: accountScopedRoute('platform_support_tickets_index'),
        },
        {
          name: 'PlatformSupportNewTicket',
          label: t('PLATFORM_SUPPORT.SIDEBAR.NEW_TICKET'),
          icon: 'i-lucide-message-square-plus',
          to: accountScopedRoute('platform_support_tickets_new'),
        },
        {
          name: 'Documentation',
          label: t('SIDEBAR.HELP_AND_SUPPORT.DOCUMENTATION'),
          href: documentationUrl.value,
        },
        {
          name: 'ContactSupport',
          label: t('SIDEBAR.HELP_AND_SUPPORT.CONTACT_SUPPORT'),
          href: supportUrl.value,
        },
        // The navigation contract, not a hand-written filter on one routing form: both entries here are
        // href-only and either may be absent on a branded installation, and a `to`-based entry added later
        // must survive rather than vanish (sidebar/navigationContract.js).
      ]),
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
            // One billing entry, not two. Both routes render the same page now
            // (docs/p11/06-rollout-compatibility.md); showing them side by side invited an administrator to
            // pick the one that redirected off the product.
            {
              name: 'Settings Billing',
              label: t('SIDEBAR.BILLING'),
              icon: 'i-lucide-credit-card',
              to: accountScopedRoute('billing_settings_index'),
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
            {
              // Named permission sets (custom/app/models/custom_role.rb). Lynomia's own capability, sold
              // through a plan, so it belongs beside Agents and Teams rather than behind a URL -- which is
              // where it was: `custom_roles_list` had no entry point anywhere in the dashboard.
              //
              // No explicit guard here. `isAllowed` resolves the target route's own meta -- the
              // `custom_roles` feature flag and `permissions: ['administrator']`
              // (routes/dashboard/settings/customRoles/customRole.routes.js) -- so an account without the
              // capability, and any member who is not an administrator, never sees this entry.
              name: 'Settings Custom Roles',
              label: t('SIDEBAR.CUSTOM_ROLES'),
              icon: 'i-lucide-shield-check',
              to: accountScopedRoute('custom_roles_list'),
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
        ...(hasSupportTickets.value
          ? [
              {
                name: 'Settings Support',
                label: t('SIDEBAR.SETTINGS_GROUPS.SUPPORT'),
                icon: 'i-lucide-ticket',
                collapsible: false,
                children: [
                  {
                    name: 'Settings Support SLA',
                    label: t('SIDEBAR.SUPPORT_SLA_POLICIES'),
                    icon: 'i-lucide-timer',
                    to: accountScopedRoute('support_sla_policies_index'),
                  },
                ],
              },
            ]
          : []),
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
    class="dark isolate bg-lyn-ink text-n-slate-12 border-e border-white/[0.07] flex flex-col text-sm pb-px fixed top-0 ltr:left-0 rtl:right-0 h-full z-40 w-[332px] max-w-[92vw] md:w-auto md:relative md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0"
    :class="[
      {
        'shadow-2xl md:shadow-none': isMobileSidebarOpen,
        'ltr:-translate-x-full rtl:translate-x-full': !isMobileSidebarOpen,
        'transition-transform duration-300 ease-out md:transition-[width]':
          !isResizing,
      },
    ]"
    :style="isMobile ? undefined : { width: `${sidebarWidth}px` }"
  >
    <section
      class="grid relative z-10"
      :class="isEffectivelyCollapsed ? 'mt-3 mb-6 gap-4' : 'mt-0 mb-4 gap-3'"
    >
      <div
        class="flex gap-2 items-center min-h-16 min-w-0"
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
              class="hidden md:flex items-center justify-center size-8 rounded-lg text-n-slate-11 transition-colors duration-150 hover:bg-white/10 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lyn-blue"
              :title="t('SIDEBAR.EXPAND_SIDEBAR')"
              @click="toggleSidebar"
            >
              <span class="i-lucide-chevron-right size-4 rtl:rotate-180" />
            </button>
          </div>
        </template>
        <template v-else>
          <div
            class="grid flex-shrink-0 place-content-center size-10 rounded-xl bg-white/[0.06] ring-1 ring-inset ring-white/10"
          >
            <Logo class="size-5" />
          </div>
          <SidebarAccountSwitcher
            class="flex-grow min-w-0 rounded-lg transition-colors duration-150 hover:bg-white/[0.06]"
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
          <button
            v-if="!isMobile"
            type="button"
            class="hidden md:flex flex-shrink-0 items-center justify-center size-8 rounded-lg text-n-slate-11 transition-colors duration-150 hover:bg-white/10 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lyn-blue"
            :title="t('SIDEBAR.COLLAPSE_SIDEBAR')"
            @click="toggleSidebar"
          >
            <span class="i-lucide-chevron-left size-4 rtl:rotate-180" />
          </button>
        </template>
      </div>

      <div
        class="flex gap-2"
        :class="isEffectivelyCollapsed ? 'flex-col items-center' : 'px-3'"
      >
        <RouterLink
          v-if="!isEffectivelyCollapsed"
          :to="{ name: 'search' }"
          class="group flex gap-2 items-center px-3 py-2 w-full h-9 rounded-lg bg-white/[0.06] text-n-slate-11 ring-1 ring-inset ring-white/10 transition-colors duration-150 hover:bg-white/[0.1] hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lyn-blue"
        >
          <span class="flex-shrink-0 i-lucide-search size-4" />
          <span class="flex-grow text-start truncate">
            {{ t('COMBOBOX.SEARCH_PLACEHOLDER') }}
          </span>
          <span
            class="pointer-events-none select-none rounded px-1.5 py-0.5 text-xxs leading-4 text-n-slate-11 ring-1 ring-inset ring-white/10"
          >
            {{ searchShortcut }}
          </span>
        </RouterLink>

        <RouterLink
          v-else
          :to="{ name: 'search' }"
          class="flex items-center justify-center size-9 rounded-lg bg-white/[0.06] text-n-slate-11 ring-1 ring-inset ring-white/10 transition-colors duration-150 hover:bg-white/[0.1] hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lyn-blue"
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
              class="!rounded-lg !border-0 !bg-lyn-indigo !text-white transition-colors duration-150 hover:!bg-lyn-indigo-deep"
              :class="[
                isEffectivelyCollapsed ? '!size-9' : '!h-9 !px-3',
                { '!bg-lyn-indigo-deep': isOpen },
              ]"
            />
          </template>
        </ComposeConversation>
      </div>
    </section>

    <nav
      ref="navRef"
      class="relative z-10 grid overflow-y-scroll flex-grow gap-2 pb-5 no-scrollbar min-w-0"
      :class="[isEffectivelyCollapsed ? 'px-1.5' : 'px-3', navFadeClass]"
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
      class="flex relative flex-col flex-shrink-0 gap-1 justify-between items-center z-10"
    >
      <div
        class="pointer-events-none absolute inset-x-0 -top-10 h-10 bg-gradient-to-t from-lyn-ink to-transparent"
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
        class="px-1.5 py-2 flex-shrink-0 flex w-full z-50 gap-2 items-center border-t border-white/[0.07]"
        :class="isEffectivelyCollapsed ? 'justify-center' : 'justify-between'"
      >
        <SidebarProfileMenu
          :is-collapsed="isEffectivelyCollapsed"
          @open-key-shortcut-modal="emit('openKeyShortcutModal')"
        />
      </div>
    </section>

    <div
      class="hidden md:block absolute top-0 h-full w-1.5 cursor-col-resize z-40 ltr:right-0 rtl:left-0 group"
      :title="t('SIDEBAR.RESIZE_SIDEBAR')"
      @mousedown="onResizeStart"
      @touchstart="onResizeStart"
      @dblclick="onResizeHandleDoubleClick"
    >
      <div
        class="absolute top-0 h-full w-px ltr:right-0 rtl:left-0 bg-transparent transition-colors duration-150 group-hover:w-0.5 group-hover:bg-lyn-blue"
        :class="{ '!w-0.5 !bg-lyn-blue': isResizing }"
      />
    </div>
  </aside>
</template>
