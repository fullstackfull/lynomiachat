# Surface audit — Inbox (agent notifications) + Reports

Phase: UI/interaction modernization, **discovery only**. This document is the **feature-parity baseline**
for `routes/dashboard/inbox/**` and `routes/dashboard/settings/reports/**`. Every row in the manifest must
still exist, and still be reachable in roughly as few steps, after any redesign. A feature that survives but
becomes materially harder to find counts as a regression.

All paths are relative to `app/javascript/`. Line numbers are from the files as read on 2026-10-03.

---

## 1. Routes and primary task

### 1.1 Inbox (agent notification inbox)

Declared in `dashboard/routes/dashboard/inbox/routes.js`:

| Route name | Path | Component | Gate |
| --- | --- | --- | --- |
| (parent, unnamed) | `/app/accounts/:accountId/inbox-view` | `InboxList.vue` | — (layout shell) |
| `inbox_view` | `…/inbox-view` | `InboxEmptyState.vue` | `meta.permissions = [...ROLES, ...CONVERSATION_PERMISSIONS]` (`routes.js:18-20`) |
| `inbox_view_conversation` | `…/inbox-view/:type/:id` | `InboxView.vue` | same (`routes.js:26-28`) |

`ROLES = ['agent','administrator']`, `CONVERSATION_PERMISSIONS = ['conversation_manage','conversation_unassigned_manage','conversation_participating_manage']`
(`dashboard/constants/permissions.js:11-17`). There is **no feature flag** on these routes, even though
`FEATURE_FLAGS.INBOX_VIEW = 'inbox_view'` exists (`dashboard/featureFlags.js:28`) and is referenced nowhere else.

Entry points: sidebar item with unread badge (`dashboard/components-next/sidebar/Sidebar.vue:387-397`),
command palette `goto_my_inbox` (`dashboard/composables/commands/useGoToCommandHotKeys.js:39-45`).

**Primary task:** an agent triages their personal notification feed — scan what needs attention (mentions,
assignments, new messages, SLA breaches), open the conversation inline without losing the queue, and clear
each item (read / unread / snooze / delete) or sweep the whole queue.

### 1.2 Reports

Declared in `dashboard/routes/dashboard/settings/reports/reports.routes.js`. All children share
`meta = { featureFlag: FEATURE_FLAGS.REPORTS, permissions: ['administrator','report_manage'] }`
(`reports.routes.js:27-30`). Parent layout `components/ReportsWrapper.vue`.

| Route name | Path | Component |
| --- | --- | --- |
| — | `/app/accounts/:accountId/reports` | redirect → `account_overview_reports` (`:118-123`) |
| `account_overview_reports` | `…/reports/overview` | `LiveReports.vue` |
| `conversation_reports` | `…/reports/conversation` | `Index.vue` |
| `agent_reports` *(legacy)* | `…/reports/agent` | `AgentReports.vue` |
| `inbox_reports` *(legacy)* | `…/reports/inboxes` | `InboxReports.vue` |
| `label_reports` *(legacy)* | `…/reports/label` | `LabelReports.vue` |
| `team_reports` *(legacy)* | `…/reports/teams` | `TeamReports.vue` |
| `agent_reports_index` | `…/reports/agents_overview` | `AgentReportsIndex.vue` |
| `agent_reports_show` | `…/reports/agents/:id` | `AgentReportsShow.vue` |
| `inbox_reports_index` | `…/reports/inboxes_overview` | `InboxReportsIndex.vue` |
| `inbox_reports_show` | `…/reports/inboxes/:id` | `InboxReportsShow.vue` |
| `team_reports_index` | `…/reports/teams_overview` | `TeamReportsIndex.vue` |
| `team_reports_show` | `…/reports/teams/:id` | `TeamReportsShow.vue` |
| `label_reports_index` | `…/reports/labels_overview` | `LabelReportsIndex.vue` |
| `label_reports_show` | `…/reports/labels/:id` | `LabelReportsShow.vue` |
| `sla_reports` | `…/reports/sla` | `SLAReports.vue` |
| `csat_reports` | `…/reports/csat` | `CsatResponses.vue` |
| `bot_reports` | `…/reports/bot` | `BotReports.vue` |

The four **legacy** routes (`reports.routes.js:32-57`) are registered and reachable by URL but are **not linked
from the sidebar** (`Sidebar.vue:358-382` links only the `*_index` routes) nor from the command palette.
They render `WootReports.vue` with no `selectedItem`, i.e. the pre-redesign "pick one entity from a dropdown"
flow. Parity note: these URLs are live today; removing them is a deletion, not a redesign.

Entry points: sidebar "Reports" group with 9 children (`Sidebar.vue:612-643`), `Alt+R` →
`account_overview_reports` (`dashboard/components-next/sidebar/useSidebarKeyboardShortcuts.js:30-32`),
command palette `COMMAND_BAR.SECTIONS.REPORTS` entries (`useGoToCommandHotKeys.js:85-100`).

**Primary task:** an administrator (or a custom role holding `report_manage`) answers "how are we doing" —
reads a live operational snapshot, then slices historical volume/latency/quality metrics by date range and by
agent / inbox / team / label / SLA policy / CSAT rating, drills from a chart bar down to the underlying
conversations, and exports CSV for offline reporting.

---

## 2. FEATURE PARITY MANIFEST

Legend for *Gate*: "none" = always visible to anyone who can reach the route. Route-level gates
(`reports` feature flag + `administrator|report_manage`, or `ROLES|CONVERSATION_PERMISSIONS` for inbox)
are implied for every row on that surface and are only restated where something extra applies.

### 2.1 Inbox — navigation & entry

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 1 | Sidebar "Inbox" item (`i-lucide-inbox`) | navigation | `Sidebar.vue:388-397` | route meta perms |
| 2 | Unread-count badge on sidebar item (`notifications/getUnreadCount`) | status | `Sidebar.vue:394-396`; getter `store/modules/notifications/getters.js:38-40` | none |
| 3 | Active-on highlight for `inbox_view` + `inbox_view_conversation` | state | `Sidebar.vue:393` | none |
| 4 | Command palette "Go to my inbox" | shortcut | `useGoToCommandHotKeys.js:39-45` | none |
| 5 | Inbox-scoped snooze hotkeys registered only on `inbox_view_conversation` | shortcut | `composables/commands/useInboxHotKeys.js:78-83`; `helper/routeHelpers.js:142-149` | route must be the conversation child |

### 2.2 Inbox — list header

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 6 | "My Inbox" heading (`text-heading-2`, truncating `h1`) | state | `components/InboxListHeader.vue:86-88` | none |
| 7 | "Display" dropdown trigger (xs, slate, trailing chevron; `solid`→`faded` when open) | secondary | `InboxListHeader.vue:90-98` | none |
| 8 | Options trigger (`i-lucide-sliders-vertical`, sm, `ghost`→`faded`) | secondary | `InboxListHeader.vue:108-114` | none |
| 9 | Both header menus auto-close when a card context menu opens | state | `InboxListHeader.vue:28-38`; emitted from `InboxList.vue:253-254` | none |
| 10 | Clickaway close on Display menu | state | `InboxListHeader.vue:101` (`v-on-clickaway`) | none |
| 11 | Clickaway close on Options menu | state | `InboxListHeader.vue:117` | none |

### 2.3 Inbox — Display menu (sort + filters)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 12 | "Sort" section label + `i-lucide-arrow-down-up` | state | `components/InboxDisplayMenu.vue:120-126` | none |
| 13 | Active-sort button showing current sort name | filter | `InboxDisplayMenu.vue:128-137` | none |
| 14 | Sort option "Newest" (`desc`) | filter | `InboxDisplayMenu.vue:39-43`; `constants/globals.js:61-64` | none |
| 15 | Sort option "Oldest" (`asc`) | filter | `InboxDisplayMenu.vue:44-48` | none |
| 16 | Check mark on active sort option | state | `InboxDisplayMenu.vue:160-164` | none |
| 17 | "Display :" section label | state | `InboxDisplayMenu.vue:169-172` | none |
| 18 | Checkbox filter "Snoozed" (→ `status`) | filter | `InboxDisplayMenu.vue:25-30`; `globals.js:65-68` | none |
| 19 | Checkbox filter "Read" (→ `type`) | filter | `InboxDisplayMenu.vue:31-36` | none |
| 20 | Filters + sort persisted to `uiSettings.inbox_filter_by` | state | `InboxDisplayMenu.vue:90-97` | none |
| 21 | Saved filters restored on mount (menu) | state | `InboxDisplayMenu.vue:98-111` | none |
| 22 | Saved filters restored on mount (list) | state | `InboxList.vue:159-166` | none |

### 2.4 Inbox — Options (bulk) menu

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 23 | "Mark all as read" | bulk | `components/InboxOptionMenu.vue:11-14`; handler `InboxListHeader.vue:40-45` | none |
| 24 | "Delete all" | bulk / destructive | `InboxOptionMenu.vue:15-18`; handler `InboxListHeader.vue:46-50` | none — **no confirmation** |
| 25 | "Delete all read" | bulk / destructive | `InboxOptionMenu.vue:19-22`; handler `InboxListHeader.vue:51-55` | none — **no confirmation** |
| 26 | Redirect to `inbox_view` after any bulk action | state | `InboxListHeader.vue:70`; `InboxList.vue:77-80` | none |
| 27 | Toast per bulk action (3 distinct messages) | status | `InboxListHeader.vue:43,48,53`; strings `i18n/locale/en/inbox.json` `INBOX.ALERTS.*` | none |

### 2.5 Inbox — list body

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 28 | Scrollable notification list (own scroll container, `divide-y`) | state | `InboxList.vue:235-238` | none |
| 29 | Infinite scroll / "load more" via IntersectionObserver (100px root margin) | navigation | `InboxList.vue:30-33,266-270`; `components/IntersectionObserver.vue` | hidden when all loaded or fetching |
| 30 | Page increment + append fetch | state | `InboxList.vue:82-92` | stops at `isAllNotificationsLoaded` |
| 31 | In-list loading spinner | loading | `InboxList.vue:257-259` | `uiFlags.isFetching` |
| 32 | Empty state text "No notifications" | empty | `InboxList.vue:260-265` (`INBOX.LIST.NO_NOTIFICATIONS`) | `!isFetching && !notifications.length` |
| 33 | Active card highlight (`bg-n-alpha-1` / dark `n-alpha-3`, `.active`) | state | `InboxList.vue:245-249` | current route id matches |
| 34 | Auto `scrollIntoView` of active card on mount and on route change | state | `InboxList.vue:72-75,213-215,218` | none |
| 35 | Refetch (reset to page 1 + clear store) on any filter change | state | `InboxList.vue:65-70,145-157` | none |
| 36 | Filters pushed into store for cross-component reuse | state | `InboxList.vue:203-211` (`updateNotificationFilters`) | none |
| 37 | List column hidden below `xl` once a conversation is open | mobile | `InboxList.vue:228` (`'hidden xl:flex'`) | `currentConversationId` truthy |
| 38 | List column width pinned to 340px from `lg` up | mobile | `InboxList.vue:227` | ≥ lg |
| 39 | `CmdBarConversationSnooze` mounted inside the inbox shell | contextual | `InboxList.vue:274` | none |

### 2.6 Inbox — notification card (`components-next/Inbox/InboxCard.vue`)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 40 | Sender avatar (20px, rounded) | state | `InboxCard.vue:165-171` | none |
| 41 | Push-message body, 2-line clamp, sanitized HTML | state | `InboxCard.vue:96-102,172` | none |
| 42 | Bold "Name:" prefix inside the message | state | `InboxCard.vue:86-94` | message contains `name:` |
| 43 | Unread blue dot + stronger text colour/weight | status | `InboxCard.vue:41-46,99-101` | `!readAt` |
| 44 | Notification-type chip (icon + colour + label) | status | `InboxCard.vue:104-109,196-211`; map `routes/dashboard/inbox/helpers/InboxViewHelpers.js:1-16` | type present and not snoozed |
| 45 | 8 notification types: mention, assignment, creation, participating-new-message, assigned-new-message, SLA missed FRT / NRT / resolution | status | `InboxViewHelpers.js:2-15`; labels `inbox.json` `INBOX.TYPES_NEXT.*` | none |
| 46 | SLA breach types rendered in ruby (`text-n-ruby-11`) | status | `InboxViewHelpers.js:13-15` | none |
| 47 | Snoozed chip "Snoozed for {time}" (`i-lucide-alarm-clock-plus`) | status | `InboxCard.vue:111-127,176-195` | `snoozedUntil` set, no `lastSnoozedAt` |
| 48 | Snooze-ended chip (`i-lucide-alarm-clock-off`) | status | `InboxCard.vue:119-127,180-188` | `meta.lastSnoozedAt` set |
| 49 | SLA countdown label (`SLACardLabel`) | status | `InboxCard.vue:214-222` | `hasSlaThreshold && primaryActor.slaPolicyId` |
| 50 | Divider pip between SLA label and priority | state | `InboxCard.vue:223` | `hasSlaThreshold` |
| 51 | Priority icon (`CardPriorityIcon`) | status | `InboxCard.vue:224-228` | `primaryActor.priority` |
| 52 | Channel/inbox icon chip with tooltip = inbox name | contextual | `InboxCard.vue:229-238`; `helper/inbox.js` `getInboxIconByType` | `inboxIcon` resolvable |
| 53 | Relative last-activity timestamp | state | `InboxCard.vue:63-66,239-247` | `lastActivityAt` |
| 54 | Exact-timestamp tooltip on the relative time (500ms show delay) | state | `InboxCard.vue:240-243`; `shared/composables/useExactTimestamp` | none |
| 55 | Right-click context menu at cursor | contextual | `InboxCard.vue:129-143,161,250-256`; `components/ui/ContextMenu.vue` | none |
| 56 | Context item "Mark as read" (`mail`) | contextual | `InboxCard.vue:68-75` | shown when unread |
| 57 | Context item "Mark as unread" (`mail-unread`) | contextual | `InboxCard.vue:68-75` | shown when read |
| 58 | Context item "Delete" (`delete`) | destructive | `InboxCard.vue:74` | none — **no confirmation** |
| 59 | Context menu viewport clamping (16px padding) | state | `ContextMenu.vue:35-50` | none |
| 60 | Context menu locks the list's scroll while open | state | `ContextMenu.vue:21-31,70-73` | injected `contextMenuElementTarget` |
| 61 | Card click → mark read, refresh unread count, route to conversation | primary | `InboxList.vue:168-201` | no-op when already on that conversation |
| 62 | Mark-as-read toast + unread-count refresh | status | `InboxList.vue:94-111` | none |
| 63 | Mark-as-unread toast + redirect to list | status | `InboxList.vue:113-126` | none |
| 64 | Delete toast + redirect to list | status | `InboxList.vue:128-143` | none |
| 65 | Analytics events: open-via-inbox, mark read, mark unread, delete | state | `InboxList.vue:95,114,129,179`; `helper/AnalyticsHelper/events.js` `INBOX_EVENTS` | none |

### 2.7 Inbox — detail header (`components/InboxItemHeader.vue`)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 66 | Back button labelled "Back" | mobile / navigation | `InboxItemHeader.vue:117-121`; `components/widgets/BackButton.vue` | `xl:hidden` (only below xl) |
| 67 | Prev notification button (`i-lucide-chevron-up`) | navigation | `components/PaginationButton.vue:45-52` | disabled at index 1 |
| 68 | Next notification button (`i-lucide-chevron-down`) | navigation | `PaginationButton.vue:53-60` | disabled at last / when total ≤ 1 |
| 69 | "current / total" counter (tabular-nums) | state | `PaginationButton.vue:62-75` | separator + total only when total > 1 |
| 70 | Whole pagination block hidden when only one notification | state | `InboxItemHeader.vue:122-128` (`v-if="totalLength > 1"`) | none |
| 71 | "Snooze notification" button → opens command palette at `snooze_notification` | secondary | `InboxItemHeader.vue:131-139,50-53` | none |
| 72 | Snooze option "An hour from now" | contextual | `useInboxHotKeys.js:24-31`; `globals.js:51-58` | inbox conversation route |
| 73 | Snooze option "Until tomorrow" | contextual | `useInboxHotKeys.js:32-39` | same |
| 74 | Snooze option "Until next week" | contextual | `useInboxHotKeys.js:40-47` | same |
| 75 | Snooze option "Until next month" | contextual | `useInboxHotKeys.js:48-55` | same |
| 76 | Snooze option "Until custom time" → modal | contextual | `useInboxHotKeys.js:56-63`; `InboxItemHeader.vue:69-78,150-158` | same |
| 77 | Custom snooze modal (`CustomSnoozeModal` in `woot-modal`) | contextual | `InboxItemHeader.vue:150-158` | `showCustomSnoozeModal` |
| 78 | Snooze success toast | status | `InboxItemHeader.vue:64` | none |
| 79 | "Delete notification" button + toast + redirect to list | destructive | `InboxItemHeader.vue:86-98,140-148` | none — **no confirmation** |
| 80 | Button labels collapse to icon-only below `md` | mobile | `InboxItemHeader.vue:137,146` (`[&>.truncate]:hidden md:[&>.truncate]:block`) | < md |

### 2.8 Inbox — detail body (`InboxView.vue`)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 81 | Conversation fetch-by-id on route change (with store clear) | state | `InboxView.vue:126-147,172-180` | none |
| 82 | Full-pane loading spinner while the conversation loads | loading | `InboxView.vue:202-207` | `isConversationLoading` |
| 83 | Embedded `ConversationBox` in inbox mode (border suppressed) | contextual | `InboxView.vue:209-216` | none |
| 84 | `SidepanelSwitch` inside the conversation box | contextual | `InboxView.vue:215` | `currentChat.id` |
| 85 | `ConversationSidebar` (contact panel) | contextual | `InboxView.vue:217-220` | `uiSettings.is_contact_sidebar_open` **and** a selected chat |
| 86 | Scroll-to-message bus event after activating a chat | state | `InboxView.vue:114-124` (`BUS_EVENTS.SCROLL_TO_MESSAGE`) | none |
| 87 | Prev/next handlers wired to the header | navigation | `InboxView.vue:149-170` | bounded by `meta.count` |
| 88 | Agents prefetched on mount | state | `InboxView.vue:182-184` | none |
| 89 | Detail empty state "Oops! Not able to fetch messages" | empty / error | `InboxView.vue:189-193`; `INBOX.LIST.NO_MESSAGES_AVAILABLE` | no `conversationId`, or empty list while fetching |

### 2.9 Inbox — empty state (`InboxEmptyState.vue`)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 90 | `mail-inbox` icon at 40px | empty | `InboxEmptyState.vue:37` | none |
| 91 | Default copy "Notifications from all subscribed inboxes" | empty | `InboxEmptyState.vue:19-24`; `INBOX.LIST.NOTE` | no `emptyStateMessage` prop |
| 92 | Overridable message via prop | empty | `InboxEmptyState.vue:9-14` | none |
| 93 | Spinner instead of the empty state while fetching | loading | `InboxEmptyState.vue:33-35` | `uiFlags.isFetching` |
| 94 | Entire empty state hidden below `lg` | mobile | `InboxEmptyState.vue:30-32` (`hidden … lg:flex`) | ≥ lg only |

### 2.10 Reports — shared chrome

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 95 | Centred max-1024px scroll container for every report | state | `components/ReportsWrapper.vue:2-4` | none |
| 96 | Page title (`text-heading-1`, `min-h-10`) | state | `components/ReportHeader.vue:28-32` | none |
| 97 | Optional page description, clamped to 5 lines below `sm` | state | `ReportHeader.vue:33-38` | only the 4 `*_index` pages pass one |
| 98 | Optional back button in the header | navigation | `ReportHeader.vue:22-24`; `BackButton.vue` | `hasBackButton` — the 4 `*_show` pages |
| 99 | Header action slot (right-aligned, shrink-0) | state | `ReportHeader.vue:41-43` | none |
| 100 | Sidebar Reports group → 9 links | navigation | `Sidebar.vue:612-643,358-382` | `reports` flag + `administrator|report_manage` |
| 101 | `Alt+R` → reports overview | shortcut | `useSidebarKeyboardShortcuts.js:30-32` | none |
| 102 | Command-palette report entries | shortcut | `useGoToCommandHotKeys.js:85-100` | none |

### 2.11 Reports — date picker (`components/ui/DatePicker/`)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 103 | Trigger button showing the active range | filter | `DatePicker.vue:376-385`; `components/DatePickerButton.vue` | none |
| 104 | Preset "Last 7 days" (default) | filter | `helpers/DatePickerHelper.js:34` | none |
| 105 | Preset "Last 30 days" | filter | `DatePickerHelper.js:35` | none |
| 106 | Preset "Last 3 months" | filter | `DatePickerHelper.js:36-40` | none |
| 107 | Preset "Last 6 months" | filter | `DatePickerHelper.js:41-44` | none |
| 108 | Preset "Last year" | filter | `DatePickerHelper.js:45` | none |
| 109 | Preset "This week" | filter | `DatePickerHelper.js:46-50` | none |
| 110 | Preset "Month to date" | filter | `DatePickerHelper.js:51-54` | none |
| 111 | Preset "Custom range" | filter | `DatePickerHelper.js:55-59` | none |
| 112 | Period step-back/forward arrows on the trigger | filter | `DatePicker.vue:88-99,382-384` | only for navigable ranges (`thisWeek`, `monthToDate`) |
| 113 | Week-number / month name navigation label | state | `DatePicker.vue:101-117` | navigable ranges |
| 114 | Dual month calendars (start + end) | filter | `DatePicker.vue:398-460` | none |
| 115 | Typed start/end date inputs with validation + error alert | filter | `DatePicker.vue:404-421`; `components/CalendarDateInput.vue` | enabled only in `custom` range |
| 116 | Week / month / year calendar view switching | filter | `DatePicker.vue:429-459` | none |
| 117 | Hover-preview of the end of the range | state | `DatePicker.vue:449-452` | while selecting |
| 118 | Footer Apply + Clear | primary / secondary | `DatePicker.vue:462`; `components/CalendarFooter.vue` | none |
| 119 | Apply-on-clickaway when a valid range is set | state | `DatePicker.vue:361-371` | `hasAppliedRange` |
| 120 | Calendar months re-centre on the selected range when reopened | state | `DatePicker.vue:338-350` | none |

### 2.12 Reports — shared filter row

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 121 | Date range picker (conversation / entity reports) | filter | `components/ReportFilters.vue:323-327` | none |
| 122 | Date range picker (summary overviews) | filter | `components/OverviewReportFilters.vue:94-98` | none |
| 123 | Entity filter chip with inline search (agents/inboxes/teams/labels) | filter | `ReportFilters.vue:330-344`; `components/Filters/v3/ActiveFilterChip.vue` | `showEntityFilter` — off for conversation + bot |
| 124 | Selecting an entity navigates to that entity's `*_reports_show` route | navigation | `ReportFilters.vue:224-246` | route exists for the type |
| 125 | "Group By" chip (Day / Week / Month / Year) | filter | `ReportFilters.vue:346-364`; options `ReportFilters.vue:110-133` | **only when range ≥ 29 days** (`:106-108`) |
| 126 | Group-by option set narrows by range length (week/month/year tiers) | filter | `ReportFilters.vue:127-133` | none |
| 127 | "Business Hours" toggle | filter | `ReportFilters.vue:366-379`; `OverviewReportFilters.vue:100-110` | `showBusinessHours` — off for bot reports |
| 128 | Filter row disabled/dimmed while summary data loads | loading | `OverviewReportFilters.vue:89-92` | `disabled` prop |
| 129 | URL sync of `from`, `to`, `business_hours`, `group_by`, `range` | state | `helpers/reportFilterHelper.js:1-33`; `ReportFilters.vue:171-181` | none |
| 130 | Filter state restored from the URL on mount (deep-linkable reports) | state | `ReportFilters.vue:280-318`; `OverviewReportFilters.vue:61-85` | none |
| 131 | URL sync of entity filters (`agent_id`,`inbox_id`,`team_id`,`sla_policy_id`,`label`,`rating`) | state | `reportFilterHelper.js:35-68` | CSAT + SLA |
| 132 | Dropdown search with 300ms debounce + fuzzy match | filter | `components/ui/Dropdown/DropdownList.vue:43-57`; `DropdownSearch.vue` | `enableSearch` |
| 133 | Dropdown "No results found" empty state | empty | `DropdownList.vue:99-102`; `DropdownEmptyState.vue` | none |
| 134 | Dropdown "Clear filter" button inside the search bar | filter | `DropdownSearch.vue:41-48` | `showClearFilter` — **off** for entity + group-by chips (`ReportFilters.vue:339,359`) |
| 135 | Check mark on the selected dropdown option | state | `DropdownListItemButton.vue:100-105` | `activeFilterId` match |
| 136 | Dropdown loading state | loading | `DropdownList.vue:95-98`; `DropdownLoadingState.vue` | `isLoading` + `loadingPlaceholder` (unused in reports) |

### 2.13 Reports — metric + chart primitives

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 137 | Metric headline value, duration-formatted for average metrics | state | `components/ChartElements/ChartStats.vue:54-59`; `composables/useReportMetrics.js:49-54` | `STATUS.FINISHED` |
| 138 | Metric summary spinner | loading | `ChartStats.vue:45-47` | `STATUS.FETCHING` |
| 139 | Metric summary failure message | error | `ChartStats.vue:48-53` (`REPORT.SUMMARY_FETCHING_FAILED`) | `STATUS.FAILED` |
| 140 | Period-over-period trend % with up/down triangle | status | `ChartStats.vue:60-77`; `useReportMetrics.js:23-27` | trend ≠ 0 and summary finished |
| 141 | Trend colour inverted for latency metrics (up = bad) | status | `ChartStats.vue:27-36` | `isAverageMetricType` |
| 142 | Bar chart per metric with themed tooltip | state | `ReportContainer.vue:318-331`; `shared/components/charts/BarChart.vue` | data non-empty |
| 143 | Chart `aria-label` = "metric, grouping" | a11y | `ReportContainer.vue:165-173` | none |
| 144 | X-axis labels formatted per grouping (day / week-span / month / year) | state | `ReportContainer.vue:129-148` | none |
| 145 | Y-axis duration step sizing (seconds→years ladder) | state | `ReportContainer.vue:13-29,207-215` | average metrics only |
| 146 | Tooltip sample-size description ("Based on N conversations/replies") | state | `ReportContainer.vue:185-206` | FRT / resolution time / reply time |
| 147 | Per-chart loading state | loading | `ReportContainer.vue:312-316` (`REPORT.LOADING_CHART`) | `accountReport.isFetching[key]` |
| 148 | Per-chart "not enough data" message | empty | `ReportContainer.vue:332-334` (`REPORT.NO_ENOUGH_DATA`) | empty series |
| 149 | 2-up responsive chart grid | state | `ReportContainer.vue:297-299` | ≥ md |

### 2.14 Reports — drilldown

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 150 | Chart bar click opens the drilldown side panel | primary | `ReportContainer.vue:219-253,329-330` | `from && to` present |
| 151 | Drilldown blocked for non-admins with a toast | status | `ReportContainer.vue:224-227` (`REPORT.DRILLDOWN.ADMIN_ONLY`) | `currentRole !== 'administrator'` — **excludes `report_manage` holders** |
| 152 | Zero-value bars silently not drillable | state | `ReportContainer.vue:278-286` | `value > 0` / `count > 0` |
| 153 | Side panel header: metric name, bucket value, bucket label | state | `components/ReportDrilldownDrawer.vue:160-181` | none |
| 154 | Subtitle conversation count (suppressed when redundant) | state | `ReportDrilldownDrawer.vue:59-73` | not a conversation-count metric |
| 155 | Subtitle message count for timing metrics | state | `ReportDrilldownDrawer.vue:78-91` | average metric + message records |
| 156 | Previous / next bucket buttons with `aria-label` | navigation | `ReportDrilldownDrawer.vue:182-203` | `canPrev` / `canNext` from `findDrillableIndex` |
| 157 | ←/→ keyboard bucket navigation (document-level) | shortcut | `ReportDrilldownDrawer.vue:124-134` | panel open |
| 158 | Record list with "Load more" paging | navigation | `ReportDrilldownDrawer.vue:222-238`; `composables/useReportDrilldown.js:111-122` | `hasMore` |
| 159 | Drilldown loading spinner | loading | `ReportDrilldownDrawer.vue:204-206` | `isFetching` |
| 160 | Drilldown error state | error | `ReportDrilldownDrawer.vue:208-213` (`REPORT.DRILLDOWN.ERROR`) | `hasError` |
| 161 | Drilldown empty state | empty | `ReportDrilldownDrawer.vue:215-220` (`REPORT.DRILLDOWN.EMPTY`) | no records |
| 162 | In-flight request abort + de-dupe by fingerprint | state | `useReportDrilldown.js:31-36,81-97` | none |
| 163 | Record card: conversation number | state | `components/ReportDrilldownCard.vue:204` | none |
| 164 | Record card: conversation status pill | status | `ReportDrilldownCard.vue:205-210` | status present |
| 165 | Record card: incoming/outgoing direction icon + tooltip | status | `ReportDrilldownCard.vue:77-88,211-218` | message records |
| 166 | Record card: metric value pill | state | `ReportDrilldownCard.vue:45-50,219-224` | value non-null |
| 167 | Record card: message timestamp with tooltip | state | `ReportDrilldownCard.vue:65-69,230-237` | message record |
| 168 | Record card: `TimeAgo` for conversation records | state | `ReportDrilldownCard.vue:238-245` | non-message record |
| 169 | Record card: event-occurred pill + tooltip | state | `ReportDrilldownCard.vue:71-75,246-253` | event-backed record |
| 170 | Record card: 1-line message preview / "No message content" | state | `ReportDrilldownCard.vue:52-63,257-262` | none |
| 171 | Record card → contact page link (new tab) | contextual | `ReportDrilldownCard.vue:105-111,129-136` | `contact_id` present |
| 172 | Record card → inbox page link (new tab) | contextual | `ReportDrilldownCard.vue:113-119,137-142` | `inbox_id` present |
| 173 | Record card → agent report link (new tab) | contextual | `ReportDrilldownCard.vue:121-127,143-150` | `assignee_id` present |
| 174 | Record card body → conversation (new tab, deep-linked to message) | contextual | `ReportDrilldownCard.vue:90-103,179-187` | `display_id` present |
| 175 | Record card keyboard activation (Enter / Space) | a11y | `ReportDrilldownCard.vue:196-197` | none |

### 2.15 Reports — Overview (`LiveReports.vue`)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 176 | Page header "Overview" (no description, no actions) | state | `LiveReports.vue:11` | none |
| 177 | Open-conversations card: Open / Unattended / Unassigned / Pending | state | `components/StatsLiveReportsContainer.vue:39-46,111-123`; `constants.js:79-87` | none |
| 178 | Team scope dropdown on the open-conversations card ("All Teams" + each team) | filter | `StatsLiveReportsContainer.vue:22-27,89-110` | **only when `teams.length`** (`:89`) |
| 179 | Open-conversations loading message | loading | `StatsLiveReportsContainer.vue:86-87`; `overview/MetricCard.vue:55-62` | `isFetchingAccountConversationMetric` |
| 180 | Agent-status card: Online / Busy / Offline counts | state | `StatsLiveReportsContainer.vue:29-38,126-139` | none |
| 181 | "Live" badge on every overview card | status | `overview/MetricCard.vue:32-41` | default header slot (i.e. all cards without a custom `#header`) |
| 182 | 60-second auto refresh of all overview data | state | `composables/useLiveRefresh.js:3-11`; called at `StatsLiveReportsContainer.vue:64,75`, `AgentLiveReportContainer.vue:17,22`, `TeamLiveReportContainer.vue:17,22`, `heatmaps/BaseHeatmapContainer.vue:257,287` | none |
| 183 | Conversation-traffic heatmap (24h × N days, blue scale) | state | `heatmaps/ConversationHeatmapContainer.vue`; `heatmaps/BaseHeatmap.vue:142-155` | none |
| 184 | Resolutions heatmap (teal scale) | state | `heatmaps/ResolutionHeatmapContainer.vue` | none |
| 185 | Heatmap quantile colour ramp (7 steps) + zero colour | state | `BaseHeatmap.vue:59-80,148-152` | none |
| 186 | Heatmap localized day-of-week row labels + full-date descriptions | state | `BaseHeatmap.vue:40-52,84-94` | none |
| 187 | Heatmap value tooltips ("N conversations" / "No conversations") | state | `BaseHeatmapContainer.vue:123-143` | none |
| 188 | Heatmap `aria-label` ("{metric} by day and hour") | a11y | `BaseHeatmapContainer.vue:119-121` | none |
| 189 | Heatmap skeleton loader (rows × 24 cells + hour axis) | loading | `BaseHeatmap.vue:108-141` | `isLoading` |
| 190 | Heatmap range: Last 7 days | filter | `heatmaps/HeatmapDateRangeSelector.vue:32-38` | none |
| 191 | Heatmap range: Last 14 days | filter | `HeatmapDateRangeSelector.vue:39-45` | none |
| 192 | Heatmap range: Last 30 days | filter | `HeatmapDateRangeSelector.vue:46-52` | none |
| 193 | Heatmap range: This month + previous 2 months (localized month names) | filter | `HeatmapDateRangeSelector.vue:62-84` | none |
| 194 | Heatmap range menu sectioned (days / months) | state | `HeatmapDateRangeSelector.vue:103-114` | none |
| 195 | Relative presets re-anchored to "now" on each live refresh | state | `BaseHeatmapContainer.vue:145-165` | none |
| 196 | Heatmap inbox filter with searchable dropdown ("All Inboxes" + each inbox) | filter | `BaseHeatmapContainer.vue:91-113,302-322` | none |
| 197 | Heatmap CSV download (icon button, tooltip + `aria-label`) | secondary | `BaseHeatmapContainer.vue:323-334` | none |
| 198 | Heatmap download uses the backend endpoint when unfiltered | state | `BaseHeatmapContainer.vue:174-184` | day range, no inbox, `downloadAction` present (conversation heatmap only) |
| 199 | Heatmap download falls back to client-side CSV | state | `BaseHeatmapContainer.vue:186-216` | otherwise |
| 200 | Agents table: avatar + name + email, availability dot | state | `overview/AgentTable.vue:88-105`; `overview/AgentCell.vue:16-41` | offline status hidden (`AgentCell.vue:27`) |
| 201 | Agents table: Open and Unattended counts, `---` for zero | state | `AgentTable.vue:75-104` | none |
| 202 | Agents table sorted by open desc then name asc | state | `AgentTable.vue:64-72` | none |
| 203 | Agents table pagination + page-size selector (10/20/50/100) | navigation | `AgentTable.vue:126-132`; `components/table/Pagination.vue:26-43,108-177` | `showPageSizeSelector` |
| 204 | Agents table page size persisted per user | state | `AgentTable.vue:37-46` (`report_overview_agent_table_page_size`) | none |
| 205 | Agents table loading message | loading | `AgentTable.vue:133-141` | `isFetchingAgentConversationMetric` |
| 206 | Agents table empty state "There are no conversations by agents" | empty | `AgentTable.vue:142-145`; `components/widgets/EmptyState.vue` | no agents |
| 207 | Teams table: Team / Open / Unattended | state | `overview/TeamTable.vue:83-99` | none |
| 208 | Teams table pagination + persisted page size | navigation | `TeamTable.vue:36-45,120-126` (`report_overview_team_table_page_size`) | none |
| 209 | Teams table loading message | loading | `TeamTable.vue:127-135` | `isFetchingTeamConversationMetric` |
| 210 | Teams table empty state "There is no data available" | empty | `TeamTable.vue:136-139` | no teams |

### 2.16 Reports — Conversation report (`Index.vue`)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 211 | Header "Conversations" + "Download conversation reports" primary button | primary | `Index.vue:110-117` | none |
| 212 | Filters: date range, group-by, business hours (no entity filter) | filter | `Index.vue:119-123` | none |
| 213 | 7 metric charts: conversations, messages received, messages sent, first response time, resolution time, resolution count, customer waiting time | state | `Index.vue:11-19,50-58` | none |
| 214 | Summary-fetch failure toast | error | `Index.vue:42-48` | none |
| 215 | Chart-fetch failure toast (per metric) | error | `Index.vue:49-68` | none |
| 216 | CSV download with generated filename (type + date + business-hours suffix) | secondary | `Index.vue:79-92`; `helper/downloadHelper.js` `generateFileName` | none |
| 217 | Filter-change analytics event | state | `Index.vue:100-103` (`REPORTS_EVENTS.FILTER_REPORT`) | none |

### 2.17 Reports — Agent / Inbox / Team / Label overviews (`SummaryReports.vue`)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 218 | Header title + description per entity type | state | `AgentReportsIndex.vue:15-18`, `InboxReportsIndex.vue:15-18`, `TeamReportsIndex.vue:15-18`, `LabelReportsIndex.vue:15-18` | none |
| 219 | "Download X reports" primary button wired through `defineExpose` | primary | `*ReportsIndex.vue:19-24,9-11`; `SummaryReports.vue:179-202` | none |
| 220 | Date range + business hours filter row | filter | `SummaryReports.vue:206-209`; `OverviewReportFilters.vue` | none |
| 221 | Summary table column: entity name (router-link to `*_reports_show`, query preserved) | contextual | `SummaryReports.vue:75-79`; `components/SummaryReportLink.vue:10-23` | none |
| 222 | Summary table column: No. of conversations | state | `SummaryReports.vue:80-84` | none |
| 223 | Summary table column: Avg. First Response Time | state | `SummaryReports.vue:85-89` | none |
| 224 | Summary table column: Avg. Resolution Time | state | `SummaryReports.vue:90-94` | none |
| 225 | Summary table column: Avg. Customer Waiting Time | state | `SummaryReports.vue:95-99` | none |
| 226 | Summary table column: Resolution Count | state | `SummaryReports.vue:100-104` | none |
| 227 | `--` placeholder for missing metric values | state | `SummaryReports.vue:107-109` | none |
| 228 | One silent retry on summary fetch failure, then a toast | error | `SummaryReports.vue:135-150` | none |
| 229 | Fade-in loading overlay over the table | loading | `SummaryReports.vue:214-228` | `summaryReports/getUIFlags[type]` |
| 230 | Entity list refetched together with the metrics | state | `SummaryReports.vue:152-157` | none |

### 2.18 Reports — single-entity reports (`WootReports.vue`)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 231 | Header title + back button on the `*_show` routes | navigation | `WootReports.vue:168`; `AgentReportsShow.vue:26`, `InboxReportsShow.vue:22`, `TeamReportsShow.vue:22`, `LabelReportsShow.vue:26` | `hasBackButton` |
| 232 | Per-entity "Download X reports" button | primary | `WootReports.vue:169-174,125-138` | type in agent/label/inbox/team |
| 233 | Entity switcher chip (searchable) that also changes the route | filter | `WootReports.vue:177-182`; `ReportFilters.vue:330-344,224-246` | `filterItemsList` non-empty |
| 234 | 7 metric charts (6 for agents — "Messages received" omitted) | state | `WootReports.vue:75-87` | `isAgentType` |
| 235 | Charts suppressed entirely when the entity list is empty | empty | `WootReports.vue:183-184` (`v-if="filterItemsList.length"`) | none |
| 236 | Full-page spinner while the entity resolves | loading | `AgentReportsShow.vue:28-30` (and the other three) | `!entity.id` |
| 237 | Drilldown scoped to the entity (`reportType` + `selectedItemId`) | state | `WootReports.vue:188-190`; `ReportContainer.vue:246-249` | none |
| 238 | Legacy "pick an entity" variants reachable by URL | navigation | `AgentReports.vue`, `InboxReports.vue`, `TeamReports.vue`, `LabelReports.vue` | not linked from any menu |

### 2.19 Reports — CSAT (`CsatResponses.vue`)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 239 | Header "CSAT Reports" + "Download CSAT Reports" | primary | `CsatResponses.vue:118-125` | none |
| 240 | Download failure toast | error | `CsatResponses.vue:73-83` | none |
| 241 | Date range picker | filter | `components/Csat/CsatFilters.vue:257-261` | none |
| 242 | "Add filter" chip with hover submenus | filter | `CsatFilters.vue:292-302`; `components/Filters/v3/AddFilterChip.vue` | hidden when all filters applied |
| 243 | Filter: Agent | filter | `CsatFilters.vue:90-94` | none |
| 244 | Filter: Inbox | filter | `CsatFilters.vue:95-98` | none |
| 245 | Filter: Team | filter | `CsatFilters.vue:106-112`; `CsatResponses.vue:48-53` | `FEATURE_FLAGS.TEAM_MANAGEMENT` on the account |
| 246 | Filter: Rating (5 levels) | filter | `CsatFilters.vue:99-103`; `components/Csat/CsatFilterHelpers.js:10-15`; `shared/constants/messages.js:51-87` | none |
| 247 | Active-filter chips, each re-openable and removable | filter | `CsatFilters.vue:266-284,215-219` | `hasActiveFilters` |
| 248 | "Clear all" filters | filter | `CsatFilters.vue:306-310,221-230` | `hasActiveFilters` |
| 249 | Vertical dividers between filter zones | state | `CsatFilters.vue:286-289,304` | conditional |
| 250 | Metric card: Total responses (+ info tooltip) | state | `components/CsatMetrics.vue:29-34`; `components/CsatMetricCard.vue` | none |
| 251 | Metric card: Satisfaction score % (+ tooltip) | state | `CsatMetrics.vue:38-43` | none |
| 252 | Metric card: Response rate % (+ tooltip) | state | `CsatMetrics.vue:47-52` | none |
| 253 | Metric card skeletons | loading | `CsatMetricCard.vue:33-36` | `isFetchingMetrics` |
| 254 | Rating-distribution stacked percentage bar | state | `components/CsatRatingDistribution.vue:59-71` | `totalResponseCount > 0` |
| 255 | Rating-distribution legend (label, %, raw count) | state | `CsatRatingDistribution.vue:64-70` | none |
| 256 | Rating-distribution skeleton | loading | `CsatRatingDistribution.vue:47-56` | `isLoading` |
| 257 | Rating-distribution empty bar | empty | `CsatRatingDistribution.vue:72` | no responses |
| 258 | Response table column: Contact (avatar, name, conversation link, relative time + exact tooltip) | contextual | `components/CsatTable.vue:175-182`; `components/CsatContactCell.vue:24-58` | none |
| 259 | Response table column: Rating pill tinted by rating colour | status | `CsatTable.vue:183-194` | none |
| 260 | Response table column: Feedback comment with "show more" | state | `CsatTable.vue:195-205`; `components/widgets/ShowMore.vue` | none |
| 261 | "No feedback provided" placeholder | empty | `CsatTable.vue:196-201` | no feedback text |
| 262 | Response table column: Handled by (agent avatar + name) | state | `CsatTable.vue:206-215` | none |
| 263 | "No assigned agent" placeholder | empty | `CsatTable.vue:212-214` | no assignee |
| 264 | Expand/collapse chevron column | contextual | `CsatTable.vue:99-107,216-229` | `csat_review_notes` cloud feature **or** on Chatwoot Cloud |
| 265 | Whole-row click toggles expansion | contextual | `CsatTable.vue:166-174,50-57` | `showExpandableRows` |
| 266 | Expanded row: review notes rich-text editor | primary | `components/CsatExpandedRow.vue:104-135` | `csat_review_notes` enabled |
| 267 | Expanded row: Save (disabled until changed, loading state) | primary | `CsatExpandedRow.vue:125-131,58-72` | none |
| 268 | Expanded row: Cancel | secondary | `CsatExpandedRow.vue:118-124,51-56` | only when notes already exist |
| 269 | Expanded row: click saved notes to edit (pencil on hover) | contextual | `CsatExpandedRow.vue:90-102,47-49` | notes exist and not editing |
| 270 | Expanded row: "Updated by {name} · {time}" with exact tooltip | state | `CsatExpandedRow.vue:139-168` | `review_notes_updated_by` present |
| 271 | Save success / failure toasts | status | `CsatExpandedRow.vue:65,68` | none |
| 272 | Review-notes paywall with "Upgrade now" → billing settings | contextual | `components/CsatReviewNotesPaywall.vue:9-27`; `CsatExpandedRow.vue:31-33,77` | on Chatwoot Cloud **without** the feature |
| 273 | Table skeleton loader (header + 5 rows) | loading | `components/CsatTableLoader.vue` | `csat/getUIFlags.isFetching` |
| 274 | Table empty state: icon + "No responses yet" + description | empty | `CsatTable.vue:244-248`; `components/CsatEmptyState.vue` | no rows |
| 275 | Server-side pagination, 25/page | navigation | `CsatTable.vue:111-140,250-255`; `CsatResponses.vue:84-87` | `metrics.totalResponseCount` |
| 276 | Filter-change analytics event (skipped on first load) | state | `CsatResponses.vue:96-102` | none |

### 2.20 Reports — SLA (`SLAReports.vue`)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 277 | Header "SLA Reports" + "Download SLA reports" | primary | `SLAReports.vue:84-91` | none |
| 278 | Download failure toast | error | `SLAReports.vue:68-78` | none |
| 279 | Date range picker | filter | `components/SLA/SLAReportFilters.vue:91-95` | none |
| 280 | "Add filter" chip with submenus | filter | `components/SLA/SLAFilter.vue:232-242` | hidden when all 5 applied |
| 281 | Filter: SLA Policy | filter | `SLAFilter.vue:45` | none |
| 282 | Filter: Inbox | filter | `SLAFilter.vue:46` | none |
| 283 | Filter: Agent | filter | `SLAFilter.vue:47` | none |
| 284 | Filter: Team | filter | `SLAFilter.vue:48` | none |
| 285 | Filter: Label (filters by label *name*) | filter | `SLAFilter.vue:49,158-164` | none |
| 286 | Active-filter chips with per-chip removal | filter | `SLAFilter.vue:206-224,166-170` | `hasActiveFilters` |
| 287 | "Clear all" filters | filter | `SLAFilter.vue:247-251,172-182` | `hasActiveFilters` |
| 288 | Metric: Hit Rate (+ tooltip) | state | `components/SLA/SLAMetrics.vue:27-32`; `components/SLA/SLAMetricCard.vue` | none |
| 289 | Metric: Number of Misses (+ tooltip) | state | `SLAMetrics.vue:35-40` | none |
| 290 | Metric: Number of Conversations (+ tooltip) | state | `SLAMetrics.vue:42-47` | none |
| 291 | Metric card skeletons | loading | `SLAMetricCard.vue:38-41` | `isFetchingMetrics` |
| 292 | Table headers: Conversation / Policy / Agent (uppercase) | state | `components/SLA/SLATable.vue:62-78`; `components/widgets/TableHeaderCell.vue` | none |
| 293 | Row: `#id` router-link to the conversation (in-app) | contextual | `components/SLA/SLAReportItem.vue:31-34,44-46` | none |
| 294 | Row: "with {contact name}" | state | `SLAReportItem.vue:47-52` | none |
| 295 | Row: conversation labels (`CardLabels`) | state | `SLAReportItem.vue:25-29,53-58` | labels present |
| 296 | Row: SLA policy name | state | `SLAReportItem.vue:60-64` | none |
| 297 | Row: assignee avatar + name, `---` when unassigned | state | `SLAReportItem.vue:65-71` | none |
| 298 | Row: "View Details" link button | contextual | `components/SLA/SLAViewDetails.vue:40-46` | none |
| 299 | SLA-events popover grouped FRT / NRT / RT | contextual | `components/widgets/conversation/components/SLAPopoverCard.vue:42-85` | `showSlaPopoverCard` |
| 300 | SLA-events popover "show more / hide" NRT toggle | contextual | `SLAPopoverCard.vue:36-39,59-78` | `nrtMisses.length > 6` — **unreachable, see V-27** |
| 301 | Popover clickaway close | state | `SLAViewDetails.vue:36,24-26` | none |
| 302 | Table loading row ("Loading SLA data…") | loading | `SLATable.vue:80-83` | `slaReports/getUIFlags.isFetching` |
| 303 | Table empty state "SLA applied conversations are not available." | empty | `SLATable.vue:94-96` | no rows |
| 304 | Footer pagination (25/page) shown conditionally | navigation | `SLATable.vue:43-47,98-104`; `components/widgets/TableFooter.vue` | more than one page |
| 305 | Reference data prefetched on mount (agents, inboxes, teams, labels, SLA policies) | state | `SLAReports.vue:41-49` | none |

### 2.21 Reports — Bot (`BotReports.vue`)

| # | Feature | Kind | Where it lives today | Gate |
| --- | --- | --- | --- | --- |
| 306 | Header "Bot Reports" — **no download button** | state | `BotReports.vue:89` | none |
| 307 | Filters: date range + group-by, business hours explicitly off | filter | `BotReports.vue:91-96` | none |
| 308 | Metric: No. of Conversations (+ tooltip) | state | `components/BotMetrics.vue:43-48`; `components/ReportMetricCard.vue` | none |
| 309 | Metric: Total Responses (+ tooltip) | state | `BotMetrics.vue:49-54` | none |
| 310 | Metric: Resolution Rate % (+ tooltip) | state | `BotMetrics.vue:55-60,18-20` | none |
| 311 | Metric: Handoff Rate % (+ tooltip) | state | `BotMetrics.vue:61-66` | none |
| 312 | Metrics refetch on filter change (deep watch) | state | `BotMetrics.vue:34-36` | `from` and `to` set |
| 313 | Charts: bot resolution count, bot handoff count | state | `BotReports.vue:23-26,99-107` | none |
| 314 | Bot summary trend/headline driven by a dedicated getter pair | state | `BotReports.vue:100-101` (`getBotSummary`, `getBotSummaryFetchingStatus`) | none |
| 315 | Summary / chart fetch failure toasts | error | `BotReports.vue:43-61` | none |
| 316 | Filter-change analytics event | state | `BotReports.vue:79-82` | none |

**Total inventoried: 316 rows.**

---

## 3. Visual / interaction audit

Severity is about user impact, not effort. Every item carries `file:line` evidence.

### 3.1 Hierarchy

**V-1 — The only primary-coloured button on every report page is "Download" (high).**
`Index.vue:111-116`, `AgentReportsIndex.vue:19-24`, `InboxReportsIndex.vue:19-24`, `TeamReportsIndex.vue:19-24`,
`LabelReportsIndex.vue:19-24`, `CsatResponses.vue:119-124`, `SLAReports.vue:85-90`, `WootReports.vue:169-174`
all render `V4Button` with no `variant`/`color`, i.e. the default solid brand style. The page's actual primary
task is reading, and the filters that drive it are rendered as `ghost` chips (`DropdownButton.vue:21-29`). The
loudest control on the page is the one users need least often.

**V-2 — Metric values use three different type scales (medium).**
`ChartStats.vue:57` `text-xl`; `CsatMetricCard.vue:37` / `SLAMetricCard.vue:43` / `ReportMetricCard.vue:41`
`text-2xl`; `StatsLiveReportsContainer.vue:119,135` `text-3xl`. The same semantic element (a KPI) is three
sizes depending on which page you are on, so visual weight no longer tracks importance.

**V-3 — Metric qualifiers and sample-size tooltips are computed but never rendered (medium).**
`ReportContainer.vue:108-120` builds `DESC` (`"( Avg )"` / `"( Total )"`) and `INFO_TEXT`
(`"Total number of conversations used for computation:"`) for every metric, and passes the whole object into
`ChartStats`. `ChartStats.vue:39-79` renders only `metric.NAME`, the value and the trend. Result: "First
Response Time — 4m 12s" gives no indication that it is an average, and the info affordance that exists on
every *other* metric card (`CsatMetricCard.vue:28-31`, `SLAMetricCard.vue:30-36`, `ReportMetricCard.vue:31-37`)
is missing on the 7 conversation-report metrics.

**V-4 — Page headers are structurally inconsistent (low).**
`ReportHeader.vue:28-38` renders an optional description under a `min-h-10` title. Only the four `*_index`
pages pass `headerDescription`; `Index.vue:110`, `LiveReports.vue:11`, `CsatResponses.vue:118`,
`SLAReports.vue:84`, `BotReports.vue:89` and `WootReports.vue:168` do not. Navigating between report pages
makes the content jump vertically by the height of a 1–2 line paragraph.

**V-5 — Inbox list header and detail header do not align (medium).**
`InboxListHeader.vue:83` is `h-[3.25rem]` (52px); `InboxItemHeader.vue:114` is `h-12` (48px). The two
headers sit side by side across a vertical divider (`InboxList.vue:227`), so the title baseline and the
pagination/action baseline are 4px apart.

### 3.2 Density & overcrowding

**V-6 — The conversation report is one 7-chart slab with no sectioning (high).**
`ReportContainer.vue:297-338` puts all metrics in a single `rounded-xl bg-n-solid-2` card, 2 per row, each
chart `h-72` (`:311`) plus a `py-4 mb-3` wrapper. Seven metrics = four rows ≈ 1500px of chart inside one
undifferentiated container, with no group headings and a filter row that scrolls away
(`Index.vue:118-130` — no sticky).

**V-7 — Overview agent-status card is squeezed to 35% width (medium).**
`StatsLiveReportsContainer.vue:125` sets `md:w-[35%] md:max-w-[35%]`, and the 65% card
(`:81-83`) holds four metrics side by side (`:111-122`) with `text-base` labels and `text-3xl` values.
Inside a 1024px-capped wrapper (`ReportsWrapper.vue:3`) that is ~160px per metric, so "Unattended" /
"Unassigned" wrap onto two lines at the exact breakpoint where the cards go horizontal.

**V-8 — The heatmap card header carries three unlabeled controls (medium).**
`BaseHeatmapContainer.vue:294-335` stacks a range dropdown, an inbox dropdown and an icon-only download
button into `MetricCard`'s `#control` slot, which lives inside
`grid-cols-[repeat(auto-fit,minmax(max-content,50%))]` (`overview/MetricCard.vue:24-26`). Two of the three are
plain `faded` buttons whose label *is* the current value ("Last 7 days", "All Inboxes") with no field label,
so there is nothing to tell the user what either dropdown controls.

**V-9 — The inbox card packs up to 7 signals into a 24px-tall footer row (medium).**
`InboxCard.vue:174-248`: type chip, snooze chip, SLA label, divider, priority icon, channel icon, timestamp —
all inside `h-6 gap-2`, with the left slot `truncate`d. On a 340px column (`InboxList.vue:227`) with an SLA
label and a priority set, the type label is reduced to a few characters.

### 3.3 Alignment & spacing

**V-10 — SLA table header spans 11 of 12 grid columns while rows span 12 (high).**
`SLATable.vue:62-78` emits spans 6 + 2 + 2 + 1 = **11**. `SLAReportItem.vue:39-72` emits
`col-span-6` + `col-span-2` + `col-span-2` and `SLAViewDetails.vue:37` adds `col-span-2` = **12**. Every
header after the first is therefore offset from the column it labels.

**V-11 — SLA table headers are right-aligned over left-aligned data (medium).**
`TableHeaderCell.vue:32` is `text-right uppercase text-xs`; the cells are
`text-sm` left-aligned (`SLAReportItem.vue:42,61`). These are also the only uppercase table headers in
reports — every other table uses `components/table/Table.vue:43` (`text-left … text-sm`) or
`CsatTable.vue:159` (same).

**V-12 — Inbox list height calculation does not match its header (low).**
`InboxList.vue:237` reserves `h-[calc(100%-56px)]` for the scroller while the header above it is 52px
(`InboxListHeader.vue:83`), leaving a 4px dead strip at the bottom of the list.

**V-13 — "Display :" section label has no vertical rhythm and a stray space (low).**
`InboxDisplayMenu.vue:170-172` applies `px-3 py-4` to an inline `<span>`, so the vertical padding is
ignored and the label butts against the sort row. The string itself is `"Display :"` with a space before the
colon (`i18n/locale/en/inbox.json`, `INBOX.DISPLAY_MENU.DISPLAY`).

**V-14 — Sort submenu overlaps its own trigger (low).**
`InboxDisplayMenu.vue:140` positions the submenu at `top-px`, i.e. 1px below the top of the relative
wrapper — on top of the button that opened it, rather than below it.

**V-15 — Stray RTL-only border on the inbox detail header (low).**
`InboxItemHeader.vue:114` carries `border-b … rtl:border-r border-n-weak`, adding a right-hand border that
exists only in RTL and matches nothing in LTR.

### 3.4 Inconsistent controls & duplicated patterns

**V-16 — Four separate table implementations inside one surface (high).**
1. Shared `components/table/Table.vue` + `components/table/Pagination.vue` — `AgentTable.vue:125-132`,
   `TeamTable.vue:119-126`.
2. Shared `Table.vue` with **no** pagination — `SummaryReports.vue:213`.
3. Hand-rolled `<table>` markup with its own `<thead>`/`<tbody>` styling — `CsatTable.vue:150-241`.
4. CSS-grid pseudo-rows with `TableHeaderCell` + `TableFooter` — `SLATable.vue:57-105`,
   `SLAReportItem.vue:38-73`.

Two incompatible pagination components ship alongside each other: `components/table/Pagination.vue` (first/prev/
numbered/next/last + page-size selector) and `components/widgets/TableFooter.vue` (results text +
`TableFooterPagination`). Row padding, header casing, hover treatment and empty-state placement all differ.

**V-17 — Three icon systems for the same "info" affordance (medium).**
`CsatMetricCard.vue:30` uses the iconify class `i-lucide-info`; `SLAMetricCard.vue:30-35` uses
`<fluent-icon icon="information" type="outline">`; `ReportMetricCard.vue:31-37` uses
`<fluent-icon icon="info">`. Three glyphs, three sizes, three colours for one meaning.

**V-18 — Two visually different spinners used side by side (medium).**
`shared/components/Spinner.vue` is a border-based CSS ring (used in `overview/MetricCard.vue:58`,
`AgentTable.vue:137`, `TeamTable.vue:131`, `SLATable.vue:81`); `components-next/spinner/Spinner.vue` is an SVG
arc (used in `ChartStats.vue:46`, `SummaryReports.vue:226`, `InboxEmptyState.vue:34`, `InboxList.vue:258`,
`InboxView.vue:206`, `ReportDrilldownDrawer.vue:205`, and every `*ReportsShow.vue`). Both can appear on the
Overview page in the same viewport.

**V-19 — Three loading idioms for the same job (medium).**
Spinner-with-message (`AgentTable.vue:133-141`, `SLATable.vue:80-83`,
`ReportContainer.vue:312-316`), bare spinner (`ChartStats.vue:45-47`), and skeleton
(`CsatTableLoader.vue`, `CsatMetricCard.vue:33-36`, `SLAMetricCard.vue:38-41`,
`CsatRatingDistribution.vue:47-56`, `BaseHeatmap.vue:108-141`). CSAT is all-skeleton, SLA is
skeleton-metrics + spinner-table, Overview is all-spinner.

**V-20 — Business-hours toggle lives in three places and is absent from two reports (medium).**
`ReportFilters.vue:366-379` right-floats it inside the chip row (`ltr:ml-auto`);
`OverviewReportFilters.vue:100-110` puts it in a separate justified block. `CsatFilters.vue` and
`SLAReportFilters.vue` have no toggle at all, and `BotReports.vue:94` disables it while still sending
`businessHours` in the payload (`BotReports.vue:62-71`).

**V-21 — Two date-range vocabularies on one page (medium).**
The Overview heatmaps offer Last 7 / 14 / 30 days + this month + previous two months
(`HeatmapDateRangeSelector.vue:31-84`), while every other report uses the 8 `WootDatePicker` presets —
Last 7/30 days, 3/6 months, last year, this week, month to date, custom
(`DatePickerHelper.js:33-60`). "Last 14 days" exists only in the heatmap; "This week" and "Month to date"
exist only in the picker.

**V-22 — Three link idioms for "go to this conversation" (medium).**
`CsatContactCell.vue:39-46` uses a raw `<a href="/app/accounts/…">` with `target="_blank"` (full page
reload); `SLAReportItem.vue:31-34,44-46` uses an in-app `router-link`; `ReportDrilldownCard.vue:179-187`
uses `window.open`. Same destination, three behaviours.

**V-23 — Inbox context menu styling is hand-rolled and contradicts the design system (medium).**
`components/widgets/conversation/contextMenu/menuItem.vue:60-74` is scoped SCSS with
`width: calc(6.25rem * 2)` and `@apply` rules — against the project's Tailwind-only rule — and
`InboxContextMenu.vue:42` then overrides it with `!w-48`. Meanwhile the inbox's *own* menu item
(`routes/dashboard/inbox/components/MenuItem.vue`) is a third, unrelated row style for the header options
menu.

**V-24 — The display-menu checkbox is a bespoke 11-utility-deep control (low).**
`InboxDisplayMenu.vue:179-186` hand-builds a checkbox with
`appearance-none … checked:after:content-['✓'] … after:-top-[1.5px]` instead of using a design-system
checkbox, so its focus ring, size and dark-mode treatment are unique to this one menu.

**V-25 — Two generations of entity reports coexist and are both reachable (medium).**
`reports.routes.js:32-57` (legacy `agent`/`inboxes`/`label`/`teams`) and `:59-109`
(`*_overview` + `*_show`) render the same metrics through different flows. The legacy pages are
unreachable from the UI but live at stable URLs, so bookmarks and docs still hit the old design.

### 3.5 Unclear CTAs & discoverability

**V-26 — Destructive bulk actions look identical to the safe one and have no confirmation (high).**
`InboxOptionMenu.vue:34-46` renders "Mark all as read", "Delete all" and "Delete all read" through the same
`MenuItem` with the same `text-n-slate-12` styling and the same `hover:text-n-blue-11`
(`MenuItem.vue:13-17`). The handlers dispatch immediately —
`InboxListHeader.vue:46-50` and `:51-55` go straight to `notifications/deleteAll` /
`deleteAllRead`, with only a success toast afterwards. The same is true of per-item delete
(`InboxCard.vue:74` → `InboxList.vue:128-143`) and header delete (`InboxItemHeader.vue:86-98`).

**V-27 — SLA "show more misses" is unreachable (medium, functional).**
`SLAPopoverCard.vue:24-29` slices `nrtMisses` to 6 when `shouldShowAllNrts` is false, and
`:36` then gates the toggle on `nrtMisses.value.length > 6`. Because the slice runs first, the length is
never greater than 6, so the button never renders and NRT misses beyond the first six can never be seen
from SLA reports → View Details.

**V-28 — Drilldown is admin-only but looks available to everyone (medium).**
`ReportContainer.vue:329` marks bars `:clickable="isDrilldownEnabled()"` for all users; the role check
happens only after the click (`:224-227`) and surfaces as a transient toast. A `report_manage` custom-role
holder, who is explicitly allowed on the route (`reports.routes.js:29`), can click every bar on every chart
and always be refused.

**V-29 — "Group By" vanishes rather than disabling (medium).**
`ReportFilters.vue:106-108,346` only render the chip when the range is ≥ 29 days. A user who had grouped by
week and then picks "Last 7 days" loses the control with no explanation, and `emitChange` silently
rewrites their grouping back to `day` (`:190-195`).

**V-30 — Snoozing a notification opens the global command palette (medium).**
`InboxItemHeader.vue:50-53` does `document.querySelector('ninja-keys').open({ parent: 'snooze_notification' })`.
Clicking a toolbar button labelled "Snooze notification" opens an unrelated full-screen search overlay rather
than a menu attached to the button. It is also unguarded: if `ninja-keys` is not mounted this throws.

**V-31 — Agent availability is an unlabeled dot, and offline has no mark at all (medium).**
`AgentCell.vue:22-29` passes `:status` into `Avatar` with `hide-offline-status`, so offline agents render
with no indicator. `OVERVIEW_REPORTS.AGENT_CONVERSATIONS.TABLE_HEADER.STATUS` is defined in
`i18n/locale/en/report.json` but no Status column exists (`AgentTable.vue:88-105`) and there is no legend.

**V-32 — Report tables cannot be sorted (medium).**
`AgentTable.vue:112`, `TeamTable.vue:106`, `SummaryReports.vue:173` and `CsatTable.vue:126` all set
`enableSorting: false`, even though `Table.vue:45,55` and `components/table/SortButton.vue` implement
sorting. Agent/team tables are hard-sorted by open count desc then name
(`AgentTable.vue:64-72`, `TeamTable.vue:60-68`); the 6-column summary tables cannot be reordered at all, so
"who has the worst resolution time" cannot be answered by sorting.

### 3.6 Empty states

**V-33 — The inbox detail empty state is invisible below `lg` (high).**
`InboxEmptyState.vue:30-32` is `hidden … lg:flex`. On a tablet or phone, `InboxView.vue:189-193` renders
this component for the "could not fetch messages" case, so the error message disappears and the user sees a
blank panel.

**V-34 — Four different empty-state treatments across the surface (medium).**
Icon + title + description card (`CsatEmptyState.vue:19-31`); title-only centred block
(`components/widgets/EmptyState.vue:11-25`, used by `AgentTable.vue:142-145` and `TeamTable.vue:136-139`);
bare centred sentence (`SLATable.vue:94-96`, `ReportContainer.vue:332-334`,
`ReportDrilldownDrawer.vue:215-220`); and a lone paragraph (`InboxList.vue:260-265`). Only CSAT offers an
icon or any next step.

**V-35 — Summary tables have no empty state (medium).**
`SummaryReports.vue:210-229` renders `Table` unconditionally. With no agents / inboxes / teams / labels, the
page shows six column headers and nothing else — no message, no "create your first inbox" path — while the
sibling overview tables do have one.

**V-36 — No empty state is reachable for an account with reports but no data (low).**
Each chart independently prints `REPORT.NO_ENOUGH_DATA` (`ReportContainer.vue:332-334`), so a brand-new
account sees the same sentence repeated seven times inside one card rather than one page-level empty state.

### 3.7 Table usability

**V-37 — Sticky headers and max-height are both inert on the overview tables (high).**
`AgentTable.vue:125` and `TeamTable.vue:119` pass `class="max-h-[calc(100vh-21.875rem)]"` to `Table`, which
applies it to the `<table>` element itself (`Table.vue:30`). There is no `overflow` ancestor
(`AgentTable.vue:124`), so `max-height` on a table is ignored and `thead.sticky top-0`
(`Table.vue:31`) has no scroll container to stick to. With 100 rows/page selected
(`Pagination.vue:40-42`) the header scrolls out of view.

**V-38 — Summary table column widths are silently ignored (medium).**
`SummaryReports.vue:74-105` declares `width: 300` / `width: 200` on each column. TanStack reads `size`, not
`width` (see the correct usage in `AgentTable.vue:93,98,104`), so `header.getSize()` in `Table.vue:40-42`
returns the 150px default for all six columns — the entity-name column is as narrow as a numeric one.

**V-39 — Pagination chrome renders above the loading and empty states (medium).**
`AgentTable.vue:126-145` and `TeamTable.vue:120-139` place `Pagination` *before* the spinner and the
`EmptyState`. With zero agents the user sees "Showing 1 to 0 of 0 results" plus five disabled pager buttons,
and *then* "There are no conversations by agents".

**V-40 — The SLA table has no responsive fallback (high).**
`SLATable.vue:62-78` and `SLAReportItem.vue:39` are fixed `grid-cols-12` with `h-16` rows, a `truncate`d
contact name and labels clamped to `w-[60%]` (`SLAReportItem.vue:56`). There is no horizontal scroll
container and no breakpoint variant, so below roughly 900px the four columns compress until the conversation
link, contact name and labels are unreadable.

**V-41 — CSAT inline styles bypass the theme (medium).**
`CsatTable.vue:186-188` sets `backgroundColor: ${getRatingData(row.rating).color}20` from the hard-coded hex
palette in `shared/constants/messages.js:51-87` (`#FDAD2A`, `#FFC532`, `#FCEC56`, `#6FD86F`, `#44CE4B`), then
puts `text-n-slate-12` on top. Those tints do not change between light and dark mode, and yellow at 12.5%
alpha behind a near-black/near-white label is the weakest contrast pairing on the surface.
`CsatRatingDistribution.vue:34` feeds the same raw hexes to the chart.

**V-42 — The CSAT rating filter list builds emoji labels that are never used (low).**
`CsatFilterHelpers.js:3-8` maps `ratings` to `item.emoji`, but `CsatFilters.vue:80-85` short-circuits
`type === 'ratings'` to `buildRatingsList`, which returns translated names
(`CsatFilterHelpers.js:10-15`). The emoji branch is dead, and the filter chip shows text while the table pill
also shows text — the emoji that users actually saw in the survey appears nowhere.

**V-43 — Expanded-row affordance has no header and no state label (low).**
`CsatTable.vue:101-104` adds an `actions` column with `header: ''`, and the chevron
(`:216-229`) is the only hint that rows expand. The row itself gets `cursor-pointer`
(`:172`) but no `role`, no `aria-expanded` and no keyboard handler.

### 3.8 Mobile behaviour

**V-44 — The date-picker panel is a fixed 880px popover (high).**
`DatePicker.vue:386-390`: `absolute … w-[880px]`, with a 680px right pane
(`:393-395`) and 340px-minimum calendars (`:422`). On any viewport under ~900px it overflows horizontally;
there is no breakpoint variant, no drawer mode and the parent filter rows do not clip it. This is the entry
control for every single report.

**V-45 — The loaded heatmap has no horizontal scroll affordance (high).**
`BaseHeatmap.vue:110-111` puts `overflow-y-scroll md:overflow-visible` on the **skeleton** only. The real
`HeatmapChart` (`:142-155`) is configured `cell-min-width=24`, `gap=5`, `row-label-width=96` → 24 × 29 + 96
≈ 790px minimum, rendered with no overflow wrapper. The skeleton scrolls; the data does not.

**V-46 — The main filter row does not wrap below `lg` (medium).**
`ReportFilters.vue:322` is `flex-col lg:flex-row`, but the inner chip row (`:329`) is
`flex gap-2 items-center w-full` with no `flex-wrap`. With an entity chip, a group-by chip and the
business-hours toggle, the row overflows on a phone. `CsatFilters.vue:256,264,266` and
`SLAFilter.vue:203,206` *do* wrap — same surface, opposite behaviour.

**V-47 — The SLA and CSAT metric dividers collapse to nothing on mobile (low).**
`CsatMetrics.vue:36,45` and `SLAMetrics.vue:34,41` render `<div class="w-full sm:w-px bg-n-strong" />`.
Below `sm` the element is full-width with no height, so it has zero height and the three metric cards run
together with only `gap-4` between them.

**V-48 — Below `lg`, the inbox shows the list *or* the conversation but the empty state never (medium).**
`InboxList.vue:228` keeps the list visible only until a conversation is selected, then hides it until `xl`.
Combined with V-33 (`InboxEmptyState.vue:30-32` is `lg:flex`), on a phone at `inbox_view` the right pane is
permanently blank — which is correct — but the same blank pane is also what a fetch failure looks like.

**V-49 — Dropdown panels are positioned with physical offsets and fixed widths (low).**
`ActiveFilterChip.vue:72` `w-[240px] … left-0 md:left-auto md:right-0`;
`AddFilterChip.vue:71,94` `left-0 md:right-0` and a `left-36` submenu;
`DropdownList.vue:81` `absolute … w-40 max-h-[400px]` with no `overflow-y-auto` on the root (only the chip
call sites add it). Nested submenus open 144px to the right regardless of remaining viewport.

### 3.9 RTL behaviour

**V-50 — `AgentCell` reverses its layout manually from a store getter (medium).**
`AgentCell.vue:13,19-21` reads `accounts/isRTL` and applies `flex-row-reverse`, instead of relying on the
document direction and logical utilities. The avatar/name/email block then also keeps `text-left`
(`:19`) and `mx-2` physical margins (`:30`), so the reversal is partial.

**V-51 — Table headers are hard-coded `text-left` (medium).**
`components/table/Table.vue:43` and `CsatTable.vue:159` both set `text-left` with no `rtl:text-right`,
so in Arabic every column header on the overview, summary and CSAT tables is left-aligned over
right-aligned content.

**V-52 — `MetricCard`'s live-dot RTL override is a no-op (low).**
`overview/MetricCard.vue:34-37`: `mr-1 rtl:mr-0 rtl:ml-0`. In RTL it removes the margin instead of moving it
to the other side (should be `rtl:ml-1`), so the "Live" dot sits flush against its label.

**V-53 — `BackButton`'s chevron is not mirrored (low).**
`components/widgets/BackButton.vue:35` renders `i-lucide-chevron-left` with `-ml-1` and no RTL variant. In
RTL the "back" arrow points away from the direction of travel, on both the inbox detail header
(`InboxItemHeader.vue:117-121`) and the four `*_reports_show` pages (`ReportHeader.vue:22-24`).

**V-54 — Context menus and the shared spinner position with physical properties (low).**
`components/ui/ContextMenu.vue:64-67,99` always sets `left`/`top`, so the inbox right-click menu opens to the
right of the cursor in RTL. `shared/components/Spinner.vue:48` uses `left-[50%] -ml-2.5`.
`ChartStats.vue:62,66,71` uses `ml-4` / `mr-1` for the trend indicator.

**V-55 — `TableHeaderCell`'s RTL flip conflicts with its content (low).**
`TableHeaderCell.vue:32` is `text-right rtl:text-left` — the inverse of the data cells, which are
`text-left rtl:text-right` (`SLAReportItem.vue:42,61`). In both directions the SLA headers end up aligned
opposite to their columns.

### 3.10 Loading & error behaviour

**V-56 — Report pages have no error state; failures are transient toasts (high).**
`Index.vue:42-67`, `BotReports.vue:43-61`, `WootReports.vue:107-124`, `CsatResponses.vue:59-66`,
`SLAReports.vue:68-78` and `SummaryReports.vue:135-150` all respond to a failed fetch with `useAlert`. Once
the toast dismisses, `ReportContainer.vue:332-334` shows "We've not received enough data points…" — i.e. a
failed request is indistinguishable from an empty one. `ChartStats.vue:48-53` is the only component anywhere
on the surface that renders a persistent failure message.

**V-57 — `BotMetrics` has no rejection handling (medium).**
`BotMetrics.vue:26-31` calls `ReportsAPI.getBotMetrics(...).then(...)` with no `.catch`. A failure leaves all
four cards showing their initial `'0'` (`:13-16`), which reads as a real zero, and produces an unhandled
promise rejection.

**V-58 — Several actions fail silently (medium).**
`BaseHeatmapContainer.vue:167-188` returns without feedback when there is no range or no data, so the
download button does nothing and is never disabled. `InboxList.vue:108-110,123-125,140-142` and
`InboxView.vue:109-111,121-123,141-143` all swallow errors in empty `catch {}` blocks, so a failed
mark-as-read or delete leaves the UI unchanged with no message. `InboxItemHeader.vue:65-67` does the same and
says so in a comment ("Silently fail without any change in the UI").

**V-59 — "Next notification" stops working past the loaded page (medium, functional).**
`InboxView.vue:149-162` bounds navigation by `totalNotificationCount` (`meta.count`, the server-side total)
but indexes into `notifications.value`, which only holds the pages fetched so far. At the end of page 1 the
next button is still enabled and simply does nothing.

**V-60 — Prev/next navigation does not refresh the unread badge (low).**
`InboxList.vue:184-192` dispatches `notifications/read` **and** `notifications/unReadCount`;
`InboxView.vue:98-108` dispatches only `read`. Moving through the queue with the header arrows therefore
leaves the sidebar unread count stale until something else refreshes it.

**V-61 — The detail header acts on a possibly-undefined notification (medium).**
`InboxView.vue:46-50` resolves `activeNotification` by matching `primary_actor.id` against the route id over
the *locally loaded* list. Deep-linking to `inbox_view_conversation` with a conversation that is not on the
loaded page leaves it `undefined`, and `InboxItemHeader.vue:57-62,86-93` then dispatches snooze/delete with
`id: undefined`.

**V-62 — Two getters for the same data in two casings (low).**
`InboxList.vue:37` uses `notifications/getFilteredNotificationsV4` (camelCased via `camelcase-keys`,
`store/modules/notifications/getters.js:12-18`) while `InboxView.vue:25` uses
`notifications/getFilteredNotifications` (snake_case, `:5-11`). The same list is read twice per page in two
shapes, which is why the two components address the same field as `primaryActor` and `primary_actor`.

**V-63 — The "Live" badge is shown on historical cards (low).**
`overview/MetricCard.vue:32-41` renders the badge in its *default* header slot, which both heatmap cards use
(`BaseHeatmapContainer.vue:293` passes only `#control`). A heatmap showing "September 2026" is therefore
labelled "Live".

### 3.11 Accessibility

**V-64 — Dropdown panels are rendered inside `<button>` elements (high).**
`components/ui/Dropdown/DropdownButton.vue:21-32` places `<slot name="dropdown" />` in the default slot of
`components-next/button/Button.vue`, which renders a real `<button>` (`Button.vue:240,257,260`). Every report
filter panel — including its search `<input>` (`DropdownSearch.vue:33-38`) and its option `<button>`s
(`DropdownListItemButton.vue:87`) — is therefore a descendant of a button. That is invalid HTML and breaks
keyboard and screen-reader interaction for the entity filter (`ActiveFilterChip.vue:57-77`), the group-by
chip, the CSAT filters and the SLA filters.

**V-65 — Filter triggers expose no popup semantics (high).**
None of `ActiveFilterChip.vue:57-62`, `AddFilterChip.vue:62-66`, `InboxListHeader.vue:90-98,108-114`,
`InboxDisplayMenu.vue:128-137`, `StatsLiveReportsContainer.vue:94-101`,
`HeatmapDateRangeSelector.vue:196-203`, `BaseHeatmapContainer.vue:306-313` or
`DatePickerButton` set `aria-expanded`, `aria-haspopup` or `aria-controls`. Dismissal is clickaway-only —
there is no `Escape` handler on any of them.

**V-66 — `role="button"` on divs with no `tabindex` and no key handler (high).**
`components-next/Inbox/InboxCard.vue:159`, `routes/dashboard/inbox/components/MenuItem.vue:12`,
`InboxDisplayMenu.vue:145` and `contextMenu/menuItem.vue:18` all claim the button role while being
unfocusable `<div>`s with `@click` only. The entire inbox — opening a notification, the three bulk actions,
the sort options, the two context-menu items — is mouse-only.

**V-67 — Inbox has no keyboard shortcuts at all.** A grep for `useKeyboardEvents|keydown|hotkey` across
`routes/dashboard/inbox/` and `components-next/Inbox/` returns nothing. The prev/next buttons
(`PaginationButton.vue:45-60`) have no key equivalent, so the queue cannot be worked without a mouse.
Compare `ReportDrilldownDrawer.vue:124-134`, which does bind ←/→.

**V-68 — The business-hours switch is labelled "Toggle" (medium).**
`components-next/switch/Switch.vue:28` provides the only accessible name (`SWITCH.TOGGLE`). The visible
"Business Hours" text is an unassociated `<span>` (`ReportFilters.vue:370-372`,
`OverviewReportFilters.vue:101-103`) with no `aria-labelledby` and no `<label for>`.

**V-69 — Charts offer no non-visual alternative (medium).**
`BarChart.vue:30`, `BaseHeatmap.vue:144` and `CsatRatingDistribution.vue:62` pass a single `aria-label`
("Conversations, Day"), which conveys the title but no values. There is no data table, no "view as table"
toggle and no `<figcaption>`.

**V-70 — Trend direction is colour-only (medium).**
`ChartStats.vue:63-77` renders direction as a CSS border triangle plus
`border-n-ruby-9`/`border-n-teal-10` text colour. There is no arrow glyph, no `+`/`−` sign and no
`aria-label`, so a red-green colour-blind user cannot tell improvement from regression. (`medium` at
`:66,71` is also not a real utility class.)

**V-71 — Tables have no `scope`, `caption` or column semantics (medium).**
`Table.vue:37-57`, `CsatTable.vue:153-163` and the grid-based `SLATable.vue:62-78` (which uses `<div>`s, not
table markup at all) omit `scope="col"`, `<caption>` and any `aria-rowcount`. The SLA table is not a table
to assistive tech.

**V-72 — Nested interactive content on the drilldown card (medium).**
`ReportDrilldownCard.vue:191-198` is an `<article role="link" tabindex="0">` that contains three `<a>`
elements (`:265-276`). The outer role claims a link while handling `keydown.space` (`:197`), and the inner
links are unreachable in the outer element's tab stop order in a predictable way.

**V-73 — Spinners are not announced (low).**
`shared/components/Spinner.vue:34` is a bare `<span>`; `components-next/spinner/Spinner.vue:11-24` is a bare
`<svg>`. Neither has `role="status"`, `aria-live` or `aria-hidden`, so loading transitions are silent.

**V-74 — Clickable chart bars and expandable rows aren't announced as interactive (low).**
`ReportContainer.vue:329-330` makes bars clickable only through the viz library's `on-item-click`;
`CsatTable.vue:166-174` makes rows clickable with no `role`/`aria-expanded`. Neither surface announces that
there is something behind the element.

**V-75 — Context menu positioning uses page coordinates for a fixed element (low).**
`InboxCard.vue:137-140` reads `e.pageX || e.clientX`, and `ContextMenu.vue:96-99` positions with
`position: fixed`. Page coordinates include document scroll; fixed positioning does not. Any document-level
scroll offsets the menu from the cursor.

---

## 4. What this surface already does well — and must not be lost

**Inbox**

1. **Two-pane triage that keeps the queue in view.** `InboxList.vue:225-275` keeps a 340px queue beside a
   full `ConversationBox` (`InboxView.vue:209-216`), so an agent can read and reply without leaving the
   notification list. The active card is highlighted and auto-scrolled into view
   (`InboxList.vue:72-75,213-215`). This is the whole point of the surface.
2. **Prev/next walking of the queue with a position counter.** `PaginationButton.vue:42-76` plus
   `InboxView.vue:149-170` lets an agent clear a backlog without returning to the list, and
   `tabular-nums` (`:63`) keeps the counter from jittering.
3. **Rich, honest signal density per card.** `InboxCard.vue:104-248` encodes notification type, unread,
   snooze state, SLA threshold, priority, channel and recency in one 2-row card. The type→icon+colour map
   (`InboxViewHelpers.js:1-16`) is a single source of truth and gives SLA breaches their own ruby treatment.
4. **Both relative and exact timestamps.** `InboxCard.vue:239-247` shows "2h" with the full timestamp on a
   500ms-delayed tooltip, so scanning stays compact without losing precision. `CsatContactCell.vue:48-55`
   and `CsatExpandedRow.vue:158-166` repeat the pattern.
5. **Filter + sort state survives reloads.** `InboxDisplayMenu.vue:90-97` writes to
   `uiSettings.inbox_filter_by` and both the menu and the list rehydrate from it
   (`:98-111`, `InboxList.vue:159-166`).
6. **Menus cooperate.** Opening a card's context menu closes the header menus
   (`InboxListHeader.vue:28-38` ← `InboxList.vue:253-254`), and the context menu clamps itself to the
   viewport and locks the list's scroll while open (`ContextMenu.vue:35-50,21-31`).
7. **Every mutation confirms itself.** Seven distinct toasts (`INBOX.ALERTS.*`) cover read, unread, snooze,
   delete and the three bulk actions, and destructive actions redirect back to a valid route
   (`InboxList.vue:77-80`).
8. **Snooze is genuinely expressive.** Five presets plus a custom date/time modal
   (`useInboxHotKeys.js:17-63`, `InboxItemHeader.vue:69-85,150-158`).

**Reports**

9. **Reports are deep-linkable and shareable.** `helpers/reportFilterHelper.js:1-68` round-trips date range,
   business hours, grouping and every entity filter through the query string, and both filter components
   rehydrate on mount (`ReportFilters.vue:280-318`, `OverviewReportFilters.vue:61-85`,
   `CsatFilters.vue:39-59`, `SLAFilter.vue:184-198`). `SummaryReportLink.vue:14-19` even forwards
   `$route.query`, so clicking into an entity keeps the analyst's date range.
10. **Chart→record drilldown.** `ReportContainer.vue:219-291` + `ReportDrilldownDrawer.vue` +
    `useReportDrilldown.js` turn a bar into the actual conversations behind it, with bucket-to-bucket
    prev/next, ←/→ keys, paging, request de-duplication and abort, and real loading/error/empty states. This
    is the strongest interaction on the surface and the only place where an aggregate is traceable to
    evidence.
11. **Drilldown cards are genuine cross-module hubs.** `ReportDrilldownCard.vue:129-151` links out to the
    contact, the inbox and the agent's own report alongside the conversation, so one record connects four
    modules.
12. **Metric trends with correct polarity.** `useReportMetrics.js:23-27` computes period-over-period change
    and `ChartStats.vue:27-36` inverts the colour semantics for latency metrics, so a rising first-response
    time is correctly red.
13. **Duration formatting is unit-aware end to end.** `ReportContainer.vue:13-29,174-184,207-215` picks axis
    steps from a seconds→years ladder and formats values with `formatTime`, so latency charts don't degrade
    into "14400".
14. **Live operational view with honest refresh.** `useLiveRefresh.js` drives a 60s refresh across all five
    overview containers, relative presets are re-anchored to "now" on each tick
    (`BaseHeatmapContainer.vue:145-165`), and the timer is cleaned up on unmount (`:20-22`).
15. **The heatmaps are the most informative visual here.** `BaseHeatmap.vue:54-105` renders a localized
    24h × N-day grid with a 7-step quantile ramp, a distinct zero colour, per-cell tooltips, an `aria-label`
    and a matching skeleton — and it is fully themed through CSS custom properties (`:153`) rather than
    hard-coded colours.
16. **Charts are themed through design tokens.** `BarChart.vue:32` and `BaseHeatmap.vue:153` map every
    viz colour to `rgb(var(--…))`, so light/dark mode is handled centrally rather than per chart.
17. **CSAT is the most finished page.** Skeleton loading at three levels
    (`CsatTableLoader.vue`, `CsatMetricCard.vue:33-36`, `CsatRatingDistribution.vue:47-56`), an icon-led
    empty state with a next step (`CsatEmptyState.vue`), tooltips on every metric
    (`CsatMetrics.vue:30-52`), a distribution chart with %-and-count legend
    (`CsatRatingDistribution.vue:64-70`), and inline review notes with an explicit paywall rather than a
    hidden feature (`CsatReviewNotesPaywall.vue`).
18. **Composable filter chips.** `AddFilterChip.vue` + `ActiveFilterChip.vue` + `DropdownList.vue` give CSAT
    and SLA a consistent add/edit/remove/clear-all model with debounced fuzzy search
    (`DropdownList.vue:43-57`) and already-applied types removed from the add menu
    (`CsatFilters.vue:121-128`, `SLAFilter.vue:67-74`).
19. **Table page size is remembered per user.** `AgentTable.vue:37-46` and `TeamTable.vue:36-45` persist the
    selection to `uiSettings`, and `Pagination.vue:45-50,112` formats counts with `Intl.NumberFormat`.
20. **CSV export everywhere it makes sense,** with descriptive generated filenames
    (`Index.vue:79-92`, `WootReports.vue:125-138`, `SummaryReports.vue:179-202`,
    `BaseHeatmapContainer.vue:206-216`) and a backend path when the range is unfiltered
    (`:174-184`).
21. **Average metrics degrade gracefully.** `SummaryReports.vue:107-109` renders `--` rather than `0` for
    missing averages, which keeps "no data" distinct from "zero".
22. **Entity switching is a first-class filter, not a separate page.** `ReportFilters.vue:224-246` changes
    the chip *and* the route, so the URL always reflects what is on screen.
