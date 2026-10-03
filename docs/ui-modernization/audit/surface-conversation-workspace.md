# Surface Audit — Conversation Workspace (list + detail + composer)

Read-only audit. Baseline for the feature-preservation contract: every row in the manifest
below exists in the code today at the cited `file:line`. A later redesign is checked against
this document; a control that still exists but becomes materially harder to discover counts as
a regression.

Scope: `routes/dashboard/conversation/**`, `components/widgets/conversation/**`, plus the
files those mount that are part of the same surface (`components/ChatList.vue`,
`ChatListHeader.vue`, `ConversationList.vue`, `ConversationItem.vue`,
`components/widgets/ChatTypeTabs.vue`, `components/widgets/WootWriter/Reply*Panel.vue`,
`components/widgets/WootWriter/EditorModeToggle.vue`, `components/buttons/ResolveAction.vue`,
`components/ui/ContextMenu.vue`, `components/ui/Tabs/*`,
`components-next/Conversation/ConversationCard/ConversationCardExpanded.vue`,
`components-next/Conversation/SidepanelSwitch.vue`, `composables/chatlist/*`).

All paths are relative to `/home/user/lynomiachat/app/javascript/dashboard/` unless prefixed.

---

## 1. Routes and primary task

### Routes

All 18 routes render the same component, `ConversationView.vue`, and are declared in
`routes/dashboard/conversation/conversation.routes.js`. Every one is gated by the same
`CONVERSATION_PERMISSIONS` array (`conversation.routes.js:6-12`): `administrator`, `agent`,
`conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage`.

| Route name | Path | Props it sets | Line |
|---|---|---|---|
| `home` | `accounts/:accountId/dashboard` | `inboxId: 0` | `:48` |
| `inbox_conversation` | `accounts/:accountId/conversations/:conversation_id` | `inboxId: 0`, `conversationId` | `:59` |
| `inbox_dashboard` | `accounts/:accountId/inbox/:inbox_id` | `inboxId` | `:70` |
| `conversation_through_inbox` | `accounts/:accountId/inbox/:inbox_id/conversations/:conversation_id` | `inboxId`, `conversationId` | `:82` |
| `label_conversations` | `accounts/:accountId/label/:label` | `label` | `:97` |
| `conversations_through_label` | `accounts/:accountId/label/:label/conversations/:conversation_id` | `label`, `conversationId` | `:107` |
| `team_conversations` | `accounts/:accountId/team/:teamId` | `teamId` | `:120` |
| `conversations_through_team` | `accounts/:accountId/team/:teamId/conversations/:conversationId` | `teamId`, `conversationId` | `:130` |
| `folder_conversations` | `accounts/:accountId/custom_view/:id` | `foldersId` | `:143` |
| `conversations_through_folders` | `accounts/:accountId/custom_view/:id/conversations/:conversation_id` | `foldersId`, `conversationId` | `:154` |
| `conversation_mentions` | `accounts/:accountId/mentions/conversations` | `conversationType: 'mention'` | `:168` |
| `conversation_through_mentions` | `accounts/:accountId/mentions/conversations/:conversationId` | `conversationType`, `conversationId` | `:178` |
| `conversation_unattended` | `accounts/:accountId/unattended/conversations` | `conversationType: 'unattended'` | `:191` |
| `conversation_through_unattended` | `accounts/:accountId/unattended/conversations/:conversationId` | `conversationType`, `conversationId` | `:201` |
| `conversation_participating` | `accounts/:accountId/participating/conversations` | `conversationType: 'participating'` | `:214` |
| `conversation_through_participating` | `accounts/:accountId/participating/conversations/:conversationId` | `conversationType`, `conversationId` | `:224` |

Two route guards exist and are themselves product behaviour:

- `redirectFolderListIfUnavailable` (`conversation.routes.js:23`) — a deep link to a folder the
  user cannot see silently redirects to `home`.
- `redirectFolderConversationIfUnavailable` (`conversation.routes.js:31`) — a deep link to a
  conversation inside an unavailable folder falls back to `inbox_conversation`, i.e. the
  conversation still opens but outside the folder scope.

Deep-link extras carried on the query string: `?messageId=` is read in
`ConversationView.vue:167` and drives `BUS_EVENTS.SCROLL_TO_MESSAGE`, which scrolls the thread
to a specific message.

### Primary task

An agent triages and answers customer conversations without leaving one screen: scan a
filtered, counted list; open a thread; read history; compose a public reply or a private note
with attachments, canned responses, signature, variables, macros, templates and AI assistance;
then set the conversation's status, assignee, team, priority and labels — individually, from a
right-click menu, or in bulk across a multi-selection.

Three-panel shell, assembled in `ConversationView.vue:197-224`: `ChatList` (left),
`ConversationBox` (centre, containing `MessagesView` → `MessageList` + `ReplyBox`),
`ConversationSidebar` → `ContactPanel` (right, toggled). On screens under 768px the layout is
forced to `expanded` (`routes/dashboard/Dashboard.vue:88-102`), which turns the three panels
into a list-or-detail swap (`ConversationView.vue:78-83`).

---

## 2. Feature parity manifest

Gating legend: `none` = always visible for anyone who can reach the route; a permission name
means `getUserPermissions`/`filterItemsByPermission`; `flag:` = account/cloud feature flag;
`cond:` = runtime condition on inbox, channel or conversation state.

### 2.1 Conversation list — header (`components/ChatListHeader.vue`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 1 | Page title (inbox / team / `#label` / folder / Mentions / Participating / Unattended / "Conversations") | state | `ChatList.vue:266-294` → `ChatListHeader.vue:92` | none |
| 2 | Contact-scoped title override (shows contact name) | state | `ChatListHeader.vue:49-55` | cond: contact filter applied |
| 3 | Back / clear-filter chevron (exits a filtered scope) | navigation | `ChatListHeader.vue:81-91` | cond: `hasAppliedFilters && !hasActiveFolders` |
| 4 | Total-count chip (formatted, raw count in `title`) | status | `ChatListHeader.vue:95-103` | cond: filters/folder active, count>0, not loading |
| 5 | Active-status chip ("Open"/"Resolved"/…) | status | `ChatListHeader.vue:104-109` | cond: no filters/folder |
| 6 | Save-current-filter-as-folder button | primary | `ChatListHeader.vue:114-121` | cond: filters applied, no folder |
| 7 | Edit-folder button | secondary | `ChatListHeader.vue:131-139` | cond: folder active |
| 8 | Delete-folder button | destructive | `ChatListHeader.vue:146-154` | cond: folder active |
| 9 | Open advanced-filters button | filter | `ChatListHeader.vue:157-165` | cond: no folder, not contact-scoped |
| 10 | Sort/status dropdown trigger | filter | `ConversationBasicFilter.vue:147-154` | cond: not contact-scoped |
| 11 | Status filter select (open/resolved/pending/snoozed/all) | filter | `ConversationBasicFilter.vue:45-66`, `:171-177` | cond: no filters/folder (`showStatusFilter`) |
| 12 | Order-by select (10 options incl. `unread`, `priority_desc_created_at_asc`, `waiting_since_*`) | filter | `ConversationBasicFilter.vue:68-109`, `:186-192` | none |
| 13 | Filter + sort persisted to UI settings (`conversations_filter_by`) | state | `ConversationBasicFilter.vue:123-130` | none |
| 14 | Condensed ↔ expanded layout toggle | secondary | `search/SwitchLayout.vue:24-36`, handler `ChatListHeader.vue:57-70` | cond: `md:` and up only (hidden on mobile) |
| 15 | Layout choice persisted (`conversation_display_type` + `previously_used_…`) | state | `ChatListHeader.vue:66-69` | none |

### 2.2 Conversation list — tabs, filters, folders (`components/ChatList.vue`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 16 | Assignee tab "Mine" + count | tab | `ChatList.vue:175-185`, `constants/permissions.js:33-36` | `administrator`/`agent`/any `conversation_*_manage` |
| 17 | Assignee tab "Unassigned" + count | tab | same | + `conversation_manage` or `conversation_unassigned_manage` |
| 18 | Assignee tab "All" + count | tab | same | + `conversation_manage` or `conversation_participating_manage` |
| 19 | Tabs hidden while a filter/folder is active | state | `ChatList.vue:923-929` | cond: `!hasAppliedFiltersOrActiveFolders` |
| 20 | Advanced filter panel (teleported) with per-attribute operators | filter | `ChatList.vue:972-984`, options `widgets/conversation/advancedFilterItems/index.js` | none |
| 21 | Filter attribute set incl. languages + countries + conversation custom attributes | filter | `ChatList.vue:82-87`, `:214-217`, `:472-489` | none |
| 22 | Save filter as folder modal (teleported) | primary | `ChatList.vue:902-912` | cond: `showAddFoldersModal` |
| 23 | Delete folder confirm modal | destructive | `ChatList.vue:914-921` | cond: `showDeleteFoldersModal` |
| 24 | Update existing folder from the filter panel | secondary | `ChatList.vue:434-443` | cond: folder active |
| 25 | Folder values rehydrated into the edit panel (agents/teams/inboxes/labels/campaigns/contacts/priority) | state | `ChatList.vue:461-490`, `:515-545` | cond: folder active |
| 26 | Client-side folder re-filtering of streamed conversations | state | `ChatList.vue:336-341` (`matchesFilters`) | cond: folder active |
| 27 | Client-side "unread" sort | filter | `ChatList.vue:308-312`, `:343-348` | cond: no filters/folder and sort=`unread` |
| 28 | Infinite scroll / load-more by intersection | navigation | `ConversationList.vue:88-92`, `ChatList.vue:591-604` | cond: page not ended, not loading |
| 29 | "All conversations loaded 🎉" end-of-list message | state | `ConversationList.vue:85-87` (`CHAT_LIST.EOF`) | cond: `showEndOfListMessage` |
| 30 | List loading spinner (bottom) | loading | `ConversationList.vue:82-84` | cond: `isLoading` |
| 31 | Header skeleton suppression while first page loads (`isListLoading`) | loading | `ChatList.vue:894`, consumed `ChatListHeader.vue:97` | cond: loading and list empty |
| 32 | Empty list message `CHAT_LIST.LIST.404` | empty | `ChatList.vue:931-936` | cond: not loading and list empty |
| 33 | Fetch-error toast `CHAT_LIST.FETCH_ERROR` | error | `ChatList.vue:399`, `:416`, `:425` | cond: request rejected |
| 34 | Virtualised list rendering (`virtua`) | state | `ConversationList.vue:66-81` | none |
| 35 | Scroll lock on the list while a context menu is open | state | `ConversationList.vue:64`, `ui/ContextMenu.vue:30`, `:71` | cond: menu open |
| 36 | Live stat refresh on `fetch_conversation_stats` | state | `ChatList.vue:798-801` | cond: no filters/folder |
| 37 | Selection cleared when filters change externally | state | `ChatList.vue:874` | none |
| 38 | Search input cleared when the assignee tab changes | state | `ChatList.vue:609` (`clearSearchInput`) | none |

### 2.3 Conversation card — condensed (`components/widgets/conversation/ConversationCard.vue`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 39 | Contact avatar with availability dot | state | `ConversationCard.vue:128-135` | cond: `!hideThumbnail` |
| 40 | Bulk-select checkbox revealed on avatar hover | bulk | `ConversationCard.vue:138-146` (`v-if="hovered || selected"`) | cond: pointer hover or already selected |
| 41 | Inbox name + channel icon | state | `ConversationCard.vue:158`, `widgets/InboxName.vue` | cond: no active inbox and >1 inbox (`ConversationItem.vue:74-76`) |
| 42 | Assignee name + human/bot icon | state | `ConversationCard.vue:165-174` | cond: `showAssignee && assignee.name`; bot icon when `assignee_type` ∈ AgentBot/Captain::Assistant (`:61-63`) |
| 43 | Priority icon | status | `ConversationCard.vue:175-178`, `CardPriorityIcon.vue` | cond: `chat.priority` set |
| 44 | Contact name, bolder when unread | state | `ConversationCard.vue:181-186` | none |
| 45 | Last-message preview (private/outgoing/activity/attachment/sticker icons) | state | `MessagePreview.vue:63-108` | cond: a last message exists |
| 46 | Voice-call status row (in progress / ended / missed / in+outbound) | status | `VoiceCallStatus.vue`, mounted `ConversationCard.vue:187-193` | cond: last message `content_type === 'voice_call'` |
| 47 | "No messages" placeholder row | empty | `ConversationCard.vue:201-215` (`CHAT_LIST.NO_MESSAGES`) | cond: no last message |
| 48 | Relative timestamp (`TimeAgo`) | state | `ConversationCard.vue:220-226` | none |
| 49 | Unread count badge (9+ overflow) | status | `UnreadBadge.vue:12-26` | cond: `unread_count > 0` |
| 50 | Label chips with overflow expand/collapse chevron | state | `conversationCardComponents/CardLabels.vue:69-96` | cond: labels present |
| 51 | SLA chip (FRT/NRT/RT, due vs missed) | status | `components/SLACardLabel.vue`, mounted `ConversationCard.vue:238-240` | cond: `applied_sla.id` and contact not blocked (`:65-67`) |
| 52 | Active-row highlight + select animation | state | `ConversationCard.vue:113-118` | cond: `isActiveChat` / `selected` |
| 53 | Compact variant (no avatar, tighter padding) used by the sidebar history list | state | `ConversationCard.vue:26`, `:116-119`; consumer `routes/dashboard/conversation/ContactConversations.vue:21-22` | cond: `compact` prop |

### 2.4 Conversation card — expanded (`components-next/Conversation/ConversationCard/ConversationCardExpanded.vue`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 54 | Always-visible bulk-select checkbox | bulk | `ConversationCardExpanded.vue:87-89` | none |
| 55 | Priority column with empty placeholder | status | `ConversationCardExpanded.vue:93-95` (`show-empty`) | none |
| 56 | Assignee avatar column with tooltip, empty-assignee icon fallback | state | `ConversationCardExpanded.vue:97-115` | cond: `showAssignee && assignee.name` |
| 57 | Status icon column with empty placeholder | status | `ConversationCardExpanded.vue:117-119`, `CardStatusIcon.vue` | none |
| 58 | Inbox column | state | `ConversationCardExpanded.vue:123-130` | cond: `!isInboxView && showInboxName` |
| 59 | Conversation-ID column with `#` icon and tooltip | state | `ConversationCardExpanded.vue:132-146` | none |
| 60 | Contact avatar + name columns | state | `ConversationCardExpanded.vue:148-159` | none |
| 61 | Single-line message/voice-call/unread content column | state | `ConversationCardExpanded.vue:161-167`, `CardContent.vue` | none |
| 62 | Right-aligned labels (V5 chips, toggle disabled) | state | `ConversationCardExpanded.vue:172-178` | cond: labels present |
| 63 | Right-aligned SLA chip (also shown on threshold, not only applied SLA) | status | `ConversationCardExpanded.vue:180-182`, `:53-57` | cond: `applied_sla.id` or `hasSlaThreshold`, contact not blocked |
| 64 | Right-aligned timestamp column | state | `ConversationCardExpanded.vue:184-191` | none |
| 65 | Expanded card used only on `lg` and up | state | `ConversationList.vue:32-38` | cond: `isOnExpandedLayout && >=1024px` |

### 2.5 Card interactions (`components/ConversationItem.vue`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 66 | Click row → router push to the scope-preserving conversation URL | navigation | `ConversationItem.vue:96-112`, `:82-94` (`conversationUrl`) | none |
| 67 | Cmd/Ctrl+click row → open conversation in a new tab | navigation | `ConversationItem.vue:100-108` | none |
| 68 | Right-click row → context menu at pointer | contextual | `ConversationItem.vue:122-128`, `ui/ContextMenu.vue` | none |
| 69 | Context-menu state reset when a virtualised row is recycled | state | `ConversationItem.vue:43-52` | none |

### 2.6 Card context menu (`components/widgets/conversation/contextMenu/Index.vue`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 70 | Mark as unread | contextual | `contextMenu/Index.vue:301-306`, `:101-104` | cond: no unread messages |
| 71 | Mark as read | contextual | `contextMenu/Index.vue:307-312` | cond: has unread messages |
| 72 | Set status → Resolved | contextual | `contextMenu/Index.vue:106-110`, `:316-324` | cond: current status ≠ resolved (`show()` `:274-278`) |
| 73 | Set status → Reopen | contextual | `contextMenu/Index.vue:111-115` | cond: current status ≠ open |
| 74 | Set status → Pending | contextual | `contextMenu/Index.vue:116-120` | cond: current status ≠ pending |
| 75 | Snooze (opens the `ninja-keys` command bar at `snooze_conversation`) | contextual | `contextMenu/Index.vue:122-126`, `:245-249`, `:325-330` | cond: status === open (`showSnooze` `:221-224`) |
| 76 | Priority submenu (None/Urgent/High/Medium/Low, current value removed) | contextual | `contextMenu/Index.vue:127-153`, `:336-346` | none |
| 77 | Label submenu with search, assigned-first ordering, check marks, toggle add/remove | contextual | `contextMenu/Index.vue:225-232`, `:347-395` | cond: `labels.length` for the submenu |
| 78 | "No labels found" empty state inside the label submenu | empty | `contextMenu/Index.vue:388-393` | cond: search yields nothing |
| 79 | Agent submenu with availability sort, presence, "None" option, AI-assignee badge | contextual | `contextMenu/Index.vue:194-220`, `:396-411`, `menuItem.vue:32-48` | cond: assignable agents exist |
| 80 | Agent submenu loading placeholder | loading | `contextMenu/Index.vue:401`, `contextMenu/agentLoadingPlaceholder.vue` | cond: `inboxAssignableAgents` fetching |
| 81 | Team submenu | contextual | `contextMenu/Index.vue:164-168`, `:412-423` | cond: `teams.length` |
| 82 | Open in new tab | contextual | `contextMenu/Index.vue:174-178`, `:256-262` | none |
| 83 | Copy conversation link (+ success toast) | contextual | `contextMenu/Index.vue:179-183`, `:263-273` | none |
| 84 | Delete conversation | destructive | `contextMenu/Index.vue:169-173`, `:440-447` | `isAdmin` only |
| 85 | Delete confirm dialog with the conversation id in the title | destructive | `ChatList.vue:959-971`, `:817-832` | none |
| 86 | `allowedOptions` whitelist to render a reduced menu | state | `contextMenu/Index.vue:69-72`, `:238-241`; used `ContactConversations.vue:41` (`open-new-tab`, `copy-link` only) | cond: prop passed |

### 2.7 Bulk-action bar (`components/widgets/conversation/conversationBulkActions/`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 87 | Floating bar appears when ≥1 conversation is selected (enter/leave transition) | bulk | `conversationBulkActions/Index.vue:139-151` | cond: `conversations.length > 0` |
| 88 | "N conversations selected" count label | status | `conversationBulkActions/Index.vue:80-84`, `:168-170` | none |
| 89 | Select-all / indeterminate checkbox | bulk | `conversationBulkActions/Index.vue:162-167`, `ChatList.vue:794-796` | none |
| 90 | "All conversations selected" amber advisory banner | status | `conversationBulkActions/Index.vue:152-157` | cond: `allConversationsSelected` |
| 91 | Clear selection link button | bulk | `conversationBulkActions/Index.vue:173-179` | none |
| 92 | Bulk assign labels (searchable, multi-select, confirm footer) | bulk | `BulkLabelActions.vue` (`action="assign"`) | none |
| 93 | Bulk remove labels, restricted to labels actually applied to the selection | bulk | `BulkLabelActions.vue:73-80`; applied set computed `Index.vue:71-78` | none |
| 94 | Bulk status → Resolve | bulk | `BulkUpdateActions.vue:35-42` | cond: not all already resolved (`Index.vue:189`) |
| 95 | Bulk status → Reopen | bulk | `BulkUpdateActions.vue:44-51` | cond: not all already open (`Index.vue:190`) |
| 96 | Bulk status → Snooze until (hands off to the command bar `bulk_action_snooze_conversation`) | bulk | `BulkUpdateActions.vue:53-60`, `:65-75` | cond: not all already snoozed (`Index.vue:191`) |
| 97 | Bulk custom snooze time modal | bulk | `Index.vue:86-115`, `:207-215` | cond: `UNTIL_CUSTOM_TIME` chosen |
| 98 | Bulk assign agent — searchable list, "None", pluralised confirmation copy, Cancel/Yes | bulk | `BulkAgentActions.vue:47-100`, `:142-198` | none |
| 99 | Agents fetched lazily, only when the dropdown opens | state | `BulkAgentActions.vue:102-110` | cond: ≥1 inbox in the selection |
| 100 | Bulk assign team — searchable list, "None", pluralised confirmation, Cancel/Yes | bulk | `BulkTeamActions.vue:29-77`, `:108-164` | none |
| 101 | In-flight disable/spinner on bulk confirm buttons | loading | `BulkAgentActions.vue:191-192`, `BulkTeamActions.vue:157-158` | cond: `bulkActions/getUIFlags.isUpdating` |
| 102 | Bulk resolve skips conversations missing required custom attributes, with partial-success toast | state | `composables/chatlist/useBulkActions.js:159-220` | cond: required attributes configured |
| 103 | Command-bar entry points for bulk snooze/reopen/resolve | shortcut | `Index.vue:125-135` (`CMD_BULK_ACTION_*`) | none |
| 104 | Bar lifted above the mobile bottom nav | mobile | `Index.vue:150` (`bottom-20 sm:bottom-4`) | cond: `<640px` |
| 105 | Bar width constrained in expanded layout | state | `ChatList.vue:944` | cond: `isOnExpandedLayout` |

### 2.8 Conversation header (`components/widgets/conversation/ConversationHeader.vue`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 106 | Back button to the scope-preserving list URL | navigation | `ConversationHeader.vue:118-122`, `:43-62` | cond: expanded layout and not inbox view (`ConversationBox.vue:105`) |
| 107 | Contact avatar + availability status | state | `ConversationHeader.vue:123-129` | none |
| 108 | Contact name | state | `ConversationHeader.vue:132-136` | none |
| 109 | Unverified-session warning icon + tooltip | status | `ConversationHeader.vue:137-143`, `:64-69` | cond: web-widget inbox and `hmac_verified` false |
| 110 | `#id` button that copies the conversation id (+ toast) | secondary | `ConversationHeader.vue:149-155`, `:100-107` | none |
| 111 | Inbox name + channel icon | state | `ConversationHeader.vue:156-157` | cond: >1 inbox |
| 112 | "Snoozed until …" / "…until next reply" amber text | status | `ConversationHeader.vue:158-161`, `:79-85` | cond: status === snoozed |
| 113 | Extended SLA chip with hoverable event popover | status | `ConversationHeader.vue:168-174`, `components/SLAPopoverCard.vue` | cond: `applied_sla.id`, contact not blocked, `md:` and up |
| 114 | Voice-call button (Twilio or WhatsApp provider, loading + disabled states, permission-pending toasts) | primary | `ConversationCallButton.vue:131-143`, `:39-128` | `flag:CHANNEL_VOICE` + inbox has a voice provider |
| 115 | Resolve / Reopen / Open primary button (status-dependent label) | primary | `components/buttons/ResolveAction.vue:184-212` | none |
| 116 | Resolve-button loading state | loading | `ResolveAction.vue:86`, `:209` | cond: request in flight |
| 117 | Resolve dropdown chevron | secondary | `ResolveAction.vue:213-224` | cond: status not pending and not snoozed |
| 118 | Dropdown → "Snooze until" (command bar) | contextual | `ResolveAction.vue:232-243`, `:79-82` | cond: status ≠ pending |
| 119 | Dropdown → "Mark pending" | contextual | `ResolveAction.vue:244-255` | cond: status ≠ pending |
| 120 | Resolve blocked by missing required custom attributes → attributes modal | state | `ResolveAction.vue:120-139`, `ConversationResolveAttributesModal` | cond: required attributes missing |
| 121 | More-actions "⋮" menu | secondary | `MoreActions.vue:103-117` | none |
| 122 | Mute conversation (+ toast) | contextual | `MoreActions.vue:31-37`, `:60-62` | cond: not muted |
| 123 | Unmute conversation (+ toast) | contextual | `MoreActions.vue:38-45`, `:63-65` | cond: muted |
| 124 | Send transcript → email transcript modal | contextual | `MoreActions.vue:47-52`, `EmailTranscriptModal.vue` | none |
| 125 | Transcript target: contact / assignee / other email + validation error | contextual | `EmailTranscriptModal.vue` template `:10-67` | cond: sender email exists / assignee is a User |
| 126 | Command-bar entries for mute, unmute, send transcript | shortcut | `MoreActions.vue:82-84` | none |
| 127 | Header reflows to two rows below `xl` | mobile | `ConversationHeader.vue:113` (`h-24 xl:h-12`, `xl:flex-row`) | cond: `<1280px` |

### 2.9 Thread view (`components/widgets/conversation/MessagesView.vue`, `ConversationBox.vue`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 128 | Dashboard-app tab strip ("Messages" + one tab per app) | tab | `ConversationBox.vue:42-55`, `:110-124` | cond: `dashboardApps.length` |
| 129 | Dashboard-app iframe panes | state | `ConversationBox.vue:137-145` | cond: tab selected |
| 130 | Tab reset to Messages when the conversation changes | state | `ConversationBox.vue:72-75` | none |
| 131 | Instagram messaging-restriction banner + status link | error | `MessagesView.vue:479-486` | cond: Meta sending disabled and Instagram channel |
| 132 | Reply-window banner with channel-specific copy and policy link (WhatsApp / API hours / 24h / 48h / Twilio) | error | `MessagesView.vue:487-494`, `:196-248` | cond: `!currentChat.can_reply` |
| 133 | Duplicate-Instagram-inbox banner | error | `MessagesView.vue:495-500`, `:176-189` | cond: FB inbox with an IG DM twin |
| 134 | Message list with read/unread split and retry | state | `MessagesView.vue:502-511`, `:157-168`, `:458-462` | none |
| 135 | Previous-messages lazy load on scroll-to-top, preserving scroll offset | navigation | `MessagesView.vue:414-441` | cond: more messages exist |
| 136 | Top loading spinner while fetching history | loading | `MessagesView.vue:512-520`, `:169-174` | cond: `shouldShowSpinner` |
| 137 | "N unread messages" divider pill | status | `MessagesView.vue:529-540`, `:249-260` | cond: `unread_count > 0` |
| 138 | Older-conversation jump link (contact history) | navigation | `MessagesView.vue:521-526`, `ContactConversationLink.vue` | cond: an older conversation exists and list fully loaded |
| 139 | Newer-conversation jump link | navigation | `MessagesView.vue:548-553` | cond: a newer conversation exists |
| 140 | Referral bubble (ad/entry-point provenance) | state | `MessagesView.vue:527` | cond: `additional_attributes.referral` |
| 141 | Captain label suggestions with per-label select, add-all, dismiss (persisted in localStorage) | contextual | `conversation/LabelSuggestion.vue`, mounted `MessagesView.vue:542-547` | `flag:CAPTAIN` + label-suggestion feature + status open + no labels yet + nothing sent since open (`MessagesView.vue:114-121`, `:304-320`) |
| 142 | Typing indicator pill with animated gif and multi-user text | status | `MessagesView.vue:556-571`, `:128-146` | cond: someone typing |
| 143 | WhatsApp duplicate-source message de-duplication | state | `MessagesView.vue:147-153` | cond: WhatsApp channel |
| 144 | Drag-to-resize composer handle, double-click to reset, auto-reset after send | secondary | `ResizableEditorWrapper.vue:167-177`, `:111-129` | none |
| 145 | Resize bounds derived from container and surrounding panels | state | `ResizableEditorWrapper.vue:37-59` | none |
| 146 | Touch resize support | mobile | `ResizableEditorWrapper.vue:146-148`, `:170` | none |

### 2.10 Composer — top panel (`components/widgets/WootWriter/ReplyTopPanel.vue`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 147 | Reply ↔ Private note sliding toggle | primary | `EditorModeToggle.vue:70-96`, `ReplyTopPanel.vue:157-162` | disabled when replies restricted or editor busy |
| 148 | Toggle forced to Private note when replies are restricted | state | `EditorModeToggle.vue:35-42` | cond: `isReplyRestricted` |
| 149 | Characters-remaining counter, red past the limit | status | `ReplyTopPanel.vue:163-169`, `:141-148` | cond: within 50 chars of the channel max (`ReplyBox.vue:305-307`) |
| 150 | Copilot "sparkle" AI menu | primary | `ReplyTopPanel.vue:172-195`, `CopilotMenuBar.vue` | `flag:CAPTAIN` (`captainTasksEnabled`) |
| 151 | Expand/collapse editor size button | secondary | `ReplyTopPanel.vue:197-203` | **also** `flag:CAPTAIN` — it sits inside the same `v-if` (`:170`) |
| 152 | Alt+P / Alt+L mode shortcuts | shortcut | `ReplyTopPanel.vue:105-114` | cond: focus not in a typeable element |

### 2.11 Composer — body (`components/widgets/conversation/ReplyBox.vue`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 153 | Self-assign banner while typing on an unassigned/other-agent conversation | primary | `ReplyBoxBanner.vue:122-132`, `:53-57` | cond: typing a public reply and not assigned to you |
| 154 | Bot-handoff banner (reopen + take over) | primary | `ReplyBoxBanner.vue:133-146`, `:67-69` | cond: status pending and assignee is an AgentBot |
| 155 | Reply-to quoted message chip with dismiss | contextual | `ReplyToMessage.vue`, mounted `ReplyBox.vue:1373-1377`, `:208-216` | cond: inbox has `REPLY_TO`, not private, not 360Dialog, Copilot off |
| 156 | Reply-to selection persisted per conversation in localStorage | state | `ReplyBox.vue:1271-1298` | none |
| 157 | Emoji picker (async-loaded, click-away to close, expanded-layout variant) | secondary | `ReplyBox.vue:1378-1387`, `:64-67`, `:1587-1602` | none |
| 158 | To / Cc / Bcc email head, auto-populated from the last email | contextual | `ReplyEmailHead.vue`, mounted `ReplyBox.vue:1388-1393`; recipients `:1255-1270` | cond: email channel and not a private note (`:426-428`) |
| 159 | Audio recorder with per-channel format (ogg/mp3/wav) | secondary | `AudioRecorder`, mounted `ReplyBox.vue:1394-1403`; format `:456-467` | cond: recorder toggled on |
| 160 | Copilot editor section (generate, follow-up, close) | primary | `CopilotEditorSection.vue`, mounted `ReplyBox.vue:1404-1416` | cond: Copilot active |
| 161 | Rich editor: mentions, canned responses, variables, macros, signature, per-channel medium | primary | `ReplyBox.vue:1417-1448` | `enable-macros` → `flag:MACROS` (`:197-202`) |
| 162 | Editor disabled with channel-specific placeholder when the reply window closed | state | `ReplyBox.vue:1428`, `:291-304`, `:525-531` | cond: WhatsApp/API, public reply, `can_reply` false |
| 163 | Quoted-email preview with toggle | contextual | `QuotedEmailPreview.vue`, mounted `ReplyBox.vue:1450-1456`, `:512-521` | cond: email channel, public, quoted text present |
| 164 | Attachment preview strip with per-file remove | secondary | `AttachmentPreview`, mounted `ReplyBox.vue:1458-1468` | cond: files attached |
| 165 | Missing-signature alert | error | `MessageSignatureMissingAlert.vue`, mounted `ReplyBox.vue:1469-1476` | cond: signature enabled but none saved |
| 166 | Paste-to-attach, with per-channel file-type rejection toast | secondary | `ReplyBox.vue:792-826`, listener `:609` | cond: uploads allowed or private note |
| 167 | Per-channel max length (Facebook/Instagram/Telegram/TikTok/Twilio-WA/WA-Cloud/SMS/Email/general) | state | `ReplyBox.vue:333-368` | none |
| 168 | Per-conversation + per-mode draft autosave (debounced 500ms) and restore | state | `ReplyBox.vue:611-617`, `:714-754`, `:645-650` | none |
| 169 | Signature appended/stripped in drafts as the toggle changes | state | `ReplyBox.vue:755-774` | cond: public reply |
| 170 | Undefined-variable confirm dialog before sending | error | `ReplyBox.vue:956-979`, `:1558-1562` | cond: message has unresolved `{{var}}` |
| 171 | Send failure toast surfacing the server error | error | `ReplyBox.vue:997-1001` | cond: request rejected |
| 172 | WhatsApp/Instagram/TikTok split into separate text + attachment messages | state | `ReplyBox.vue:862-909`, `:1163-1212` | cond: those channels, public reply |
| 173 | Macro execution from the editor, with required-attributes modal | contextual | `ReplyBox.vue:839-847`, `:1552-1556` | `flag:MACROS` |
| 174 | Help-centre article search popover → insert link | contextual | `ArticleSearchPopover`, mounted `ReplyBox.vue:1357-1362`, `:666-678` | cond: inbox has a connected portal (`:482-486`) |
| 175 | WhatsApp template modal (picker → parameter form → send) | primary | `WhatsappTemplates/Modal.vue`, mounted `ReplyBox.vue:1534-1542` | cond: inbox has templates, not private (`:217-224`) |
| 176 | Contact-info request template entry point | contextual | `ReplyBox.vue:641-644`, `RequestContactInfoButton.vue` | cond: not a private note |
| 177 | Twilio Content-template modal | primary | `ContentTemplates/ContentTemplatesModal.vue`, mounted `ReplyBox.vue:1544-1550` | cond: Twilio WhatsApp channel, not private (`:225-227`) |
| 178 | Typing-status broadcast on/off, private-aware | state | `ReplyBox.vue:1086-1090`, `:1117-1130` | none |
| 179 | Instagram reply restriction forces private-note mode | state | `ReplyBox.vue:242-258`, `:544-547`, `:596-598` | cond: Meta sending disabled + Instagram |
| 180 | Bot-owned pending conversation forces private-note mode | state | `ReplyBox.vue:279-284`, `:250-258` | cond: pending + AgentBot assignee |
| 181 | Attachments cleared when switching reply ↔ note | state | `ReplyBox.vue:1017-1027` | none |

### 2.12 Composer — bottom panel (`components/widgets/WootWriter/ReplyBottomPanel.vue`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 182 | Emoji picker button | secondary | `ReplyBottomPanel.vue:288-296` | cond: editor not disabled |
| 183 | Attach-file button (drag-drop target, direct upload, per-channel accept list) | secondary | `ReplyBottomPanel.vue:297-321`, `:215-229` | cond: channel supports uploads or private note (`:186-189`) |
| 184 | Multi-file upload | secondary | `ReplyBottomPanel.vue:304`; allowed channels `ReplyBox.vue:429-437` | cond: email/web/API/WhatsApp/Telegram |
| 185 | Full-screen drag-and-drop overlay | secondary | `ReplyBottomPanel.vue:389-399` | cond: dragging and no new-conversation modal (`:230-232`) |
| 186 | Audio-record toggle (mic / mic-slash) | secondary | `ReplyBottomPanel.vue:322-330` | `flag:VOICE_RECORDER`, not Line/TikTok (`:190-207`) |
| 187 | Audio play/pause/stop button with duration label | secondary | `ReplyBottomPanel.vue:331-339`, `:233-245` | cond: recording in progress |
| 188 | Signature toggle (per-channel, tooltip states both ways) | secondary | `ReplyBottomPanel.vue:340-348`, `:246-258`, `:275-277` | cond: not a private note, editor enabled |
| 189 | Quoted-reply toggle (`aria-pressed`, solid when on) | secondary | `ReplyBottomPanel.vue:349-358`, `:265-269` | cond: email channel, not private |
| 190 | WhatsApp templates button | secondary | `ReplyBottomPanel.vue:359-367` | cond: `enableWhatsAppTemplates` |
| 191 | Request-contact-info button | secondary | `ReplyBottomPanel.vue:368-371` | cond: not a private note |
| 192 | Content-templates button | secondary | `ReplyBottomPanel.vue:372-380` | cond: `enableContentTemplates` |
| 193 | Video-call button | secondary | `ReplyBottomPanel.vue:381-388`, `VideoCallButton.vue` | cond: web-widget or API inbox, not private, editor enabled |
| 194 | Insert-article button | secondary | `ReplyBottomPanel.vue:400-408`, `:259-261` | cond: inbox has a portal slug |
| 195 | Send button with mode-dependent label and shortcut hint, amber in note mode | primary | `ReplyBottomPanel.vue:411-419`; label `ReplyBox.vue:387-396` | disabled per `isReplyButtonDisabled` (`ReplyBox.vue:311-321`) |
| 196 | Copilot bottom panel (submit / cancel) replaces the normal bar | primary | `CopilotReplyBottomPanel.vue`, mounted `ReplyBox.vue:1489-1495` | cond: Copilot active |

### 2.13 Sidebar panel host (`routes/dashboard/conversation/ContactPanel.vue`, `ConversationSidebar.vue`, `SidepanelSwitch.vue`)

| # | Feature | Kind | Lives today | Gate |
|---|---|---|---|---|
| 197 | Floating contact-panel toggle | navigation | `components-next/Conversation/SidepanelSwitch.vue:55-66` | cond: a conversation is selected (`ConversationView.vue:215`) |
| 198 | Floating Copilot-panel toggle | navigation | `SidepanelSwitch.vue:67-80` | `flag:CAPTAIN` (`:17-19`) |
| 199 | Panel enter/leave slide transition | state | `ConversationView.vue:218-224`, `:604-615` | none |
| 200 | Panel is a dismissible overlay on small screens (click-outside closes) | mobile | `ConversationSidebar.vue:44-60`, `:28-39` | cond: `<768px` |
| 201 | Click-outside ignores ProseMirror prompts and popovers | state | `ConversationSidebar.vue:47-51` | none |
| 202 | Sidebar header with close button | navigation | `components-next/SidebarActionsHeader.vue:21-46`, `ContactPanel.vue:150-153` | none |
| 203 | Contact info block (avatar, channel, social links, edit) | state | `ContactPanel.vue:154`, `contact/ContactInfo.vue` | none |
| 204 | Drag-to-reorder accordion sections, order persisted | secondary | `ContactPanel.vue:156-165`, `:125-130` | none |
| 205 | Per-section open/closed state persisted in UI settings | state | `ContactPanel.vue:42-45`, `:173-176` etc. | none |
| 206 | Section: Conversation actions (assignee / team / priority / labels) | state | `ContactPanel.vue:168-183`, `ConversationAction.vue` | none |
| 207 | Self-assign link in the assignee row | primary | `ConversationAction.vue:240-248`, `:176-198` | cond: not already assigned to you (`:162-173`) |
| 208 | Assignee multiselect incl. AI assignees, toggle-off by reselect | contextual | `ConversationAction.vue:251-263`, `:199-209` | none |
| 209 | Team multiselect with "None" and emoji icons | contextual | `ConversationAction.vue:270-283`, `:75-83` | none |
| 210 | Priority multiselect with per-level icons | contextual | `ConversationAction.vue:287-301`, `:37-63` | none |
| 211 | Label box: add-label chip, searchable dropdown, per-chip remove, create-new | contextual | `labels/LabelBox.vue:87-121` | create-new only when `isAdmin` (`:116`) |
| 212 | Label box loading spinner | loading | `labels/LabelBox.vue:123` | cond: `conversationLabels` fetching |
| 213 | `L` key toggles the label dropdown; Escape closes | shortcut | `labels/LabelBox.vue:38-53` | cond: focus not in a typeable element |
| 214 | Section: Conversation participants — count, avatars, add/remove, watch/unwatch | state | `ContactPanel.vue:184-201`, `ConversationParticipant.vue` template `:1-72` | none |
| 215 | "No participants" empty state | empty | `ConversationParticipant.vue:162-172` (template `:10-12`) | cond: no watchers |
| 216 | Section: Conversation info (browser/referer/custom attributes) with external referer link | state | `ContactPanel.vue:202-216`, `ConversationInfo.vue` | none |
| 217 | Section: Contact attributes, with "no records found" empty state | state/empty | `ContactPanel.vue:217-236` | none |
| 218 | Section: Previous conversations (reduced context menu, click to open) | navigation | `ContactPanel.vue:237-258`, `ContactConversations.vue` | hidden when the list is already scoped to this contact (`ContactPanel.vue:107-111`) |
| 219 | Previous-conversations empty + loading states | empty/loading | `ContactConversations.vue` template `:3-7`, `:46-48` | none |
| 220 | Section: Macros — run, preview popover, drag-reorder | contextual | `ContactPanel.vue:259-271`, `Macros/List.vue`, `Macros/MacroItem.vue` | `woot-feature-toggle feature-key="macros"` |
| 221 | Macros empty state with "add macro" link to settings | empty | `Macros/List.vue:58-71` | cond: no macros |
| 222 | Macros loading state | loading | `Macros/List.vue:72-78` | cond: fetching |
| 223 | Macro per-item executing spinner/disable | loading | `Macros/MacroItem.vue:56-57` | cond: that macro running |
| 224 | Section: Linear issues — list, create, link, setup CTA | contextual | `ContactPanel.vue:272-290`, `linear/*` | `flag:LINEAR` + Linear client configured; CTA when not connected |
| 225 | Section: Shopify orders | contextual | `ContactPanel.vue:291-306`, `ShopifyOrdersList.vue` | cond: Shopify integration enabled |
| 226 | Section: Commerce (overview, carts, orders, search, order actions) | contextual | `ContactPanel.vue:307-319`, `commerce/CommercePanel.vue` | `flag:LYNOMIA_COMMERCE` |
| 227 | Section: Contact notes | contextual | `ContactPanel.vue:320-331`, `contact/ContactNotes.vue` | none |
| 228 | Section: Shared files — media grid + file list, gallery viewer, open-in-new-tab | contextual | `ContactPanel.vue:332-343`, `SharedFiles.vue` | none |
| 229 | Shared files empty + loading states | empty/loading | `SharedFiles.vue:51-56` | none |
| 230 | Assignable agents prefetched when the conversation's inbox changes | state | `ConversationBox.vue:60-71` | none |

### 2.14 Keyboard shortcuts (whole surface)

| # | Shortcut | Action | Lives today | Gate |
|---|---|---|---|---|
| 231 | `Alt+N` | cycle assignee tabs | `widgets/ChatTypeTabs.vue:32-43` | cond: tabs visible |
| 232 | `Alt+J` | previous conversation in list | `composables/chatlist/useChatListKeyboardEvents.js:49-52` | works while typing |
| 233 | `Alt+K` | next conversation in list | `useChatListKeyboardEvents.js:53-56` | works while typing |
| 234 | `Alt+E` | resolve current conversation | `buttons/ResolveAction.vue:146-155` | not while typing |
| 235 | `Cmd/Ctrl+Alt+E` | resolve and advance to the next row | `ResolveAction.vue:156-169` | not while typing |
| 236 | `Alt+M` | open the resolve dropdown | `ResolveAction.vue:142-145` | works while typing |
| 237 | `Alt+O` | toggle the contact sidebar | `SidepanelSwitch.vue:43-48` | not while typing |
| 238 | `Alt+P` | switch composer to Private note | `ReplyTopPanel.vue:106-109` | not while typing |
| 239 | `Alt+L` | switch composer to Reply | `ReplyTopPanel.vue:110-113` | not while typing |
| 240 | `L` | toggle the sidebar label dropdown | `labels/LabelBox.vue:39-44` | not while typing; sidebar mounted |
| 241 | `Escape` | close label dropdown / hide emoji picker / blur field | `labels/LabelBox.vue:45-52`, `ReplyBox.vue:108-111`, `composables/useKeyboardEvents.js:22-27` | works while typing |
| 242 | `Enter` | send reply | `ReplyBox.vue:120-128` | cond: editor focused, hotkey preference = enter |
| 243 | `Cmd/Ctrl+Enter` | send reply / submit Copilot reply | `ReplyBox.vue:129-138` | cond: editor focused |
| 244 | `Cmd/Ctrl+K` | open the command bar | `ReplyBox.vue:112-119` | works while typing |
| 245 | `Cmd/Ctrl+Alt+A` | open the attachment picker | `ReplyBottomPanel.vue:148-164` | cond: editor not disabled |

### 2.15 Surface-level states summary

| # | State | Lives today |
|---|---|---|
| 246 | Loading inboxes / loading conversations (full-pane) | `EmptyState/EmptyState.vue:69-72`, `:37-42` |
| 247 | No inboxes + admin → onboarding view | `EmptyState.vue:74-80`, `OnboardingView.vue` |
| 248 | No inboxes + agent → `CONVERSATION.NO_INBOX_AGENT` | `EmptyState.vue:79` |
| 249 | No conversations at all → `CONVERSATION.NO_MESSAGE_1` + illustration | `EmptyState.vue:88-91`, `EmptyStateMessage.vue:16-29` |
| 250 | Conversations exist, none selected → "Select a conversation" (condensed) / `CONVERSATION.404` (expanded) | `EmptyState.vue:92-95`, `:43-48` |
| 251 | Shortcut/command-bar placeholder inside the empty state | `EmptyStateMessage.vue:31`, `FeaturePlaceholder.vue` |
| 252 | Snooze command-bar host mounted alongside the workspace | `ConversationView.vue:226` (`CmdBarConversationSnooze`) |
| 253 | Selected state cleared on route leave / on entering without an id | `ConversationView.vue:22-29`, `:99-107` |
| 254 | Conversation fetched on demand when deep-linked and absent from the list | `ConversationView.vue:142-150`, `ChatList.vue:400-402` |

**Total inventoried: 254.**

### 2.16 Load-bearing selectors and element ids (not styling — behavioural contracts)

These are queried from JavaScript. A redesign that renames them silently breaks features
without any test or type error.

| Selector / id | Read by | Feature it powers |
|---|---|---|
| `div.conversations-list div.conversation` | `useChatListKeyboardEvents.js:5`, `ResolveAction.vue:60` | Alt+J / Alt+K navigation; Cmd+Alt+E "resolve and next" |
| `div.conversations-list div.conversation.active` | `useChatListKeyboardEvents.js:8`, `ResolveAction.vue:64` | knowing which row is current |
| `.conversations-list` (scrollTop) | `ResolveAction.vue:165` | scroll-to-top after wrapping round the list |
| `#conversationAttachment` | `ReplyBottomPanel.vue:158` | Cmd+Alt+A attachment shortcut |
| `ninja-keys` element | `contextMenu/Index.vue:247`, `BulkUpdateActions.vue:69`, `ResolveAction.vue:80`, `ReplyBox.vue:115` | snooze pickers, bulk snooze, command bar |
| `#saveFilterTeleportTarget` | `ChatList.vue:903`, target `ChatListHeader.vue:123` | save-filter panel anchoring |
| `#conversationFilterTeleportTarget` | `ChatList.vue:974`, targets `ChatListHeader.vue:141`, `:167` | advanced-filter panel anchoring |
| `dialog.ProseMirror-prompt-backdrop`, `[data-popover-content]`, `[data-popover-backdrop]` | `ConversationSidebar.vue:48-50` | sidebar not closing under its own popovers |
| `.resizable-editor-body` | `ResizableEditorWrapper.vue:184` | composer height clamp |
| `.drag-handle` | `ContactPanel.vue:160`, `Macros/List.vue:85`, applied `MacroItem.vue:34` | sidebar and macro reordering |

---

## 3. Visual audit

### 3.1 Hierarchy

**H1 — `ConversationView.vue` carries a 490-line scoped stylesheet with its own parallel
accent palette, overriding the design system at the top of the highest-traffic surface.**
Severity: high. `ConversationView.vue:230-719` defines `--cw-accent: #6366f1`,
`--cw-accent-strong: #4f46e5`, `--cw-border-hover: rgba(129,140,248,0.38)` plus six bespoke
shadows (`:243-246`, `:274-276`), two blurred decorative glow divs (`:194-195`, `:289-323`),
panel radii of `16px`/`13px`/`0` (`:337`, `:669`, `:682`), four keyframe animations
(`:621-650`) and a `:deep(*)` scrollbar override that reaches every descendant
(`:577-598`). None of these values exist in `tailwind.config.js`; the indigo accent is
hard-coded, so the shell does not follow the product's brand token (`n-brand`). This is also a
direct violation of the project's Tailwind-only rule.

**H2 — Three visually different conversation-card implementations are in use, two of them
inside this one surface.** Severity: high. Condensed rows render
`components/widgets/conversation/ConversationCard.vue` (a two-line stacked card, avatar-led);
expanded rows render `components-next/Conversation/ConversationCard/ConversationCardExpanded.vue`
(a single-line 10-column grid with divider pips at `:91`, `:121`, `:129`); and a third,
`components-next/Conversation/ConversationCard/ConversationCard.vue`, is used by the Contacts
and Companies modules. The sidebar's own "Previous conversations" list inside this surface
imports the legacy one (`ContactConversations.vue:6`) while the Contacts module's equivalent
imports the next-gen one (`components-next/Contacts/ContactsSidebar/ContactHistory.vue:8`), so
the same information renders two different ways depending on which module the user came from.

**H3 — Conversation status is the primary action in the header but has no visual weight.**
Severity: medium. `ResolveAction.vue:184-212` renders Resolve/Reopen/Open as
`color="slate"`, the same neutral colour as the adjacent "⋮" and phone ghost buttons
(`MoreActions.vue:103-111`, `ConversationCallButton.vue:132-142`). The single most consequential
action on the surface is indistinguishable from its neighbours, while the composer's Send
button one panel below is `color="blue"` (`ReplyBottomPanel.vue:415`).

**H4 — Priority icons are rendered at the lowest usable contrast step.** Severity: medium.
`CardPriorityIcon.vue:61` applies `text-n-slate-5` unconditionally — including to urgent. In
the condensed card the priority indicator sits at `!size-3.5`
(`ConversationCard.vue:177`), i.e. a 14px glyph at slate-5, next to a 12px timestamp.

**H5 — Two different colours mean "unread".** Severity: low. The card badge is
`bg-n-teal-9` (`UnreadBadge.vue:20`); the in-thread divider for the same count is
`bg-n-brand` (`MessagesView.vue:535`).

### 3.2 Density and overcrowding

**D1 — The composer's bottom toolbar can hold eleven controls in a single non-wrapping flex
row inside a 340px panel.** Severity: high. `ReplyBottomPanel.vue:287` is
`<div class="left-wrap">` and `left-wrap` is `@apply items-center flex gap-2`
(`:425-427`) — no `flex-wrap`, no overflow handling. On an email inbox with a connected
portal, voice recording and quoted replies the row contains emoji, attach, mic, signature,
quote, WhatsApp template, request-contact-info, content template, video call and article
search, and the parent is `flex justify-between p-3` (`:286`) with the Send button competing
for the same line.

**D2 — The expanded card packs ten fixed-width columns plus three 1px divider pips into one
48px row.** Severity: medium. `ConversationCardExpanded.vue:73-168`: checkbox, pip, priority
(`w-4`), assignee (`w-4`), status (`w-4`), pip, inbox (`w-20`), pip, id (`max-w-20`), avatar,
name (`w-32`), content, then labels + SLA + time on the right. The name column is a hard
`w-32` (128px) regardless of available width (`:156`), so names truncate even on a 2560px
display while the content column absorbs the slack.

**D3 — The conversation header stacks to 96px on anything below 1280px.** Severity: medium.
`ConversationHeader.vue:113` is `h-24 xl:h-12` with `flex-col … xl:flex-row`. Between 768px
and 1280px — the common laptop range — the header is double height and the action cluster
drops to its own full-width row left-aligned (`:166`, `xl:justify-end`), so Resolve moves away
from the thread it acts on.

**D4 — Context-menu rows are a fixed 200px wide.** Severity: medium.
`contextMenu/menuItem.vue:62` sets `width: calc(6.25rem * 2)` and
`menuItemWithSubmenu.vue:63` sets the same as `min-width`. Agent names, team names and label
titles all truncate at 200px minus icon and padding, and there is no tooltip on the truncated
label (`menuItem.vue:49-51`).

### 3.3 Spacing and alignment

**S1 — The surface re-implements spacing, radius, blur, z-index and shadow values that the
design system already tokenises.** Severity: medium. `tailwind.config.js:58-96` defines
`spacing.13 = 3.25rem`, `borderRadius.{control,surface,overlay}`,
`boxShadow.{raised,overlay,modal}`, `blur.panel = 100px`,
`height.control-{xs,sm,md,lg}` and `zIndex.{sticky,dropdown,drawer,modal,toast}` — the config
comment at `:51-54` says these exist precisely to replace one-off values. The workspace uses
none of them: `h-[3.25rem]` (`ChatListHeader.vue:75`, `ReplyTopPanel.vue:155`),
`backdrop-blur-[100px]` in ten surface files (`contextMenu/Index.vue:298`,
`menuItemWithSubmenu.vue:43`, `:53`, `ConversationBasicFilter.vue:158`,
`labels/LabelBox.vue:110`, `ConversationParticipant.vue:211`, `ResolveAction.vue:229`,
`SLAPopoverCard.vue:44`, `Macros/MacroPreview.vue:19`, `SlashCommandMenu.vue:201`),
`rounded-[10px]` and `shadow-[0_0_12px_0_rgba(27,40,59,0.08)]`
(`conversationBulkActions/Index.vue:159`).

**S2 — Panel widths are expressed in `px`, against the project's own `rem` rule.** Severity:
low. `ChatList.vue:882` uses `w-[340px] 2xl:w-[412px]`; `ConversationSidebar.vue:54` uses
`md:w-[320px] md:min-w-[320px] 2xl:min-w-[360px] 2xl:w-[360px]`; `ConversationHeader.vue:141`
uses `min-w-[14px]`. Elsewhere in the same surface arbitrary sizes are `rem`
(`max-h-[12.5rem]`, `max-w-[12.5rem]`, `min-h-[4rem]`).

**S3 — Ad-hoc z-index ladder reaching 9999, with the bulk bar below two dropdowns.**
Severity: medium. `z-[9999]` at `ui/ContextMenu.vue:98`, `labels/LabelBox.vue:110` and
`ConversationParticipant.vue:211`; `z-[100]` at `ReplyBox.vue:1597`; `z-50` at
`ChatListHeader.vue:124`, `:142`, `:168` and `SLAPopoverCard.vue:44`; `z-40` at
`ConversationBasicFilter.vue:158` and `ConversationSidebar.vue:54`; `z-30` for the bulk bar
(`conversationBulkActions/Index.vue:150`); `z-20` at `ReplyBottomPanel.vue:392`; `hover:z-[1]`
on every card (`ConversationCard.vue:112`). The sort dropdown (z-40) and the sidebar (z-40)
both out-rank the bulk-action bar (z-30).

**S4 — Timestamp and unread badge are absolutely positioned against a magic offset tied to
whether the meta row rendered.** Severity: low. `ConversationCard.vue:216-218` switches
between `top-8` and `top-4`, and the avatar independently switches `mt-4`/`mt-8`
(`:134`). The contact name reserves space for them with a hard-coded
`ltr:pr-16 rtl:pl-16` (`:182`), so a four-digit unread count plus a long relative time
overlaps the name.

**S5 — Asymmetric physical padding on the typing pill.** Severity: low.
`MessagesView.vue:562` is `py-2 pr-4 pl-5` with no logical equivalent, and the gif margin
is correctly flipped (`ltr:ml-2 rtl:mr-2`, `:566`) while the padding is not.

### 3.4 Inconsistent controls

**C1 — The email-transcript modal uses raw unstyled native inputs while the rest of the
surface uses the design system.** Severity: medium. `EmailTranscriptModal.vue` template
`:14-20`, `:32-38`, `:44-50` are bare `<input type="radio">` with no component wrapper, and
`:57-62` is a bare `<input type="text">` — whereas the label search in the same surface uses
`components-next/input/Input.vue` (`contextMenu/Index.vue:353`) and every checkbox uses
`components-next/checkbox/Checkbox.vue`.

**C2 — The composer's bottom bar and the bulk bar use `i-ph-*` (Phosphor) icons while
everything around them uses `i-lucide-*`.** Severity: medium. Phosphor:
`ReplyBottomPanel.vue:291`, `:316`, `:325`, `:333`, `:343`, `:352`, `:362`, `:377`, `:403`,
`ReplyTopPanel.vue:181`, `SidepanelSwitch.vue:64`. Lucide: `ChatListHeader.vue:85`, `:116`,
`:134`, `:148`, `:160`, `ConversationBasicFilter.vue:149`, all four
`conversationBulkActions/Bulk*Actions.vue` triggers, `MoreActions.vue:33`, `:40`, `:48`. The
card context menu uses a third family entirely — `fluent-icon` with bare names like
`'mail'`, `'checkmark'`, `'snooze'`, `'person-add'` (`contextMenu/Index.vue:99`, `:109`,
`:125`, `:161`).

**C3 — Two WhatsApp-template entry points share the identical icon.** Severity: medium.
`ReplyBottomPanel.vue:362` ("WhatsApp templates") and `:377` ("Content Templates") are both
`icon="i-ph-whatsapp-logo"`, sitting two buttons apart in the same toolbar with no visual
distinction.

**C4 — The "Content Templates" tooltip is a bare English string.** Severity: medium.
`ReplyBottomPanel.vue:374`: `v-tooltip.top-end="'Content Templates'"`. Every sibling in the
row uses `$t(...)`. Direct violation of the project's no-bare-strings rule.

**C5 — The typing-indicator image alt text is a bare English string.** Severity: low.
`MessagesView.vue:568`: `alt="Someone is typing"`.

**C6 — The status-icon tooltip in the expanded card shows an untranslated raw enum.**
Severity: medium. `CardStatusIcon.vue:36` passes `content: status`, so the tooltip reads
`open` / `resolved` / `snoozed` / `pending` in lowercase English in every locale. The sibling
`CardPriorityIcon.vue:41-51` does translate its tooltip, so the two columns behave
differently.

**C7 — Bulk resolve carries a hard-coded English fallback next to a key that exists.**
Severity: low. `composables/chatlist/useBulkActions.js:190-193`:
`t('BULK_ACTION.RESOLVE.ALL_MISSING_ATTRIBUTES') || 'Cannot resolve conversations due to missing required attributes'`.
The key is present at `i18n/locale/en/bulkActions.json:25`, so the fallback is unreachable
dead English copy.

**C8 — Hard-coded hex outside the token system.** Severity: low.
`conversation/LabelSuggestion.vue:185` passes `'#2781F6'` as the selected-label background;
`linear/IssueHeader.vue:35` uses `text-[#5E6AD2]`.

**C9 — Dropdown anchoring is hand-tuned with negative offsets per component.** Severity:
low. `BulkUpdateActions.vue:104` `ltr:-right-[4.5rem]`, `BulkLabelActions.vue:162`
`ltr:-right-[6.5rem]`, `BulkAgentActions.vue:139` `ltr:-right-10`, `BulkTeamActions.vue:105`
`ltr:-right-2` — four magic numbers for four adjacent triggers in one bar, each with its own
`2xl:` reset.

### 3.5 Duplicated patterns

**P1 — Three `SLACardLabel` components.** Severity: medium.
`components/widgets/conversation/components/SLACardLabel.vue` (116 lines, used by the
condensed card and the header), `components-next/Conversation/Sla/SLACardLabel.vue` (61
lines, used by the expanded card at `ConversationCardExpanded.vue:11`), and
`components-next/Conversation/ConversationCard/SLACardLabel.vue` (67 lines). The two in use in
this surface differ in behaviour, not just styling: the legacy one gates on
`applied_sla.id` only (`ConversationCard.vue:65-67`), the next-gen one also shows on a
threshold (`ConversationCardExpanded.vue:53-57`), so the same conversation can show an SLA
chip in expanded view and none in condensed view.

**P2 — Duplicate `InboxName`, `MessagePreview`, `VoiceCallStatus` and `CardLabels`.**
Severity: medium. `components/widgets/InboxName.vue` vs
`components-next/Conversation/InboxName.vue` (both 19 lines);
`components/widgets/conversation/MessagePreview.vue` vs
`components-next/Conversation/ConversationCard/MessagePreview.vue`;
`components/widgets/conversation/VoiceCallStatus.vue` vs
`components-next/Conversation/ConversationCard/VoiceCallStatus.vue`;
`components/widgets/conversation/conversationCardComponents/CardLabels.vue` vs
`components-next/Conversation/ConversationCard/CardLabels.vue` vs `CardLabelsV5.vue`.

**P3 — The layout toggle handler is implemented twice; one copy is dead.** Severity: low.
`ChatListHeader.vue:57-70` and `ConversationView.vue:127-141` are the same
`toggleConversationLayout` body. Only the `ChatListHeader` copy is wired
(`ChatListHeader.vue:180`); `ConversationView`'s is unreferenced.

**P4 — Resolve-with-required-attributes is implemented three times.** Severity: low. Once in
`ChatList.vue:742-785`, once in `ResolveAction.vue:104-139`, once in
`useBulkActions.js:159-220`, each mounting its own `ConversationResolveAttributesModal`
(`ChatList.vue:985`, `ResolveAction.vue:258`, `Macros/List.vue:99`, `ReplyBox.vue:1552`).

**P5 — Dead state and props left behind.** Severity: low.
`ConversationView.vue:70`, `:180-185` — `showSearchModal`, `onSearch`, `closeSearch` with no
template consumer. `ConversationBox.vue:25-28`, `:56-58` — `isContactPanelOpen` prop and
`showContactPanel` computed, never used in the template and never passed by either consumer.
`ReplyTopPanel.vue:131-140` — `replyButtonClass` / `noteButtonClass` computeds, superseded by
`EditorModeToggle`. `labels/LabelBox.vue:69` — `selectedLabels: []`. `ChatList.vue:885` — a
default `<slot />` that `ConversationView` never fills.

**P6 — Dead CSS hook classes still in the markup.** Severity: low. None of these has a rule
anywhere in the codebase: `border-line` and `conversation--user`
(`ConversationCard.vue:149`, `:182`), `header-actions-wrap` and
`conversation--header--actions` (`ConversationHeader.vue:166`, `:147`), `actions--container`
(`MoreActions.vue:94`), `resolve-actions` (`ResolveAction.vue:179`),
`conversations-list-wrap` (`ChatList.vue:879`), `conversation-details-wrap`
(`ConversationBox.vue:97`), `is-note-mode` (`ReplyBottomPanel.vue:183`), `min-width-calc`
(`menuItemWithSubmenu.vue:43`), `agent-thumbnail` (`menuItem.vue:74-76`), `total-watchers`
(`ConversationParticipant.vue:162`), `sidebar-labels-wrap` (`labels/LabelBox.vue:82` — the
rule exists but is `margin-bottom: 0`). `.send-button` is declared twice identically in
`ReplyBox.vue:1567-1569` and `:1579-1581` and matches no element.

**P7 — Commented-out Safari detection left in a computed.** Severity: low.
`ReplyBottomPanel.vue:195-198` and `:205`.

**P8 — A CSS-class typo in the header.** Severity: low. `ConversationHeader.vue:151`:
`!p-0 cucursor-pointer` — the copy-id button is missing its pointer cursor.

### 3.6 CTA clarity

**T1 — The editor-expand control disappears when Captain is off.** Severity: high.
`ReplyTopPanel.vue:170` opens `<div v-if="captainTasksEnabled" class="flex items-center gap-2">`
and the maximise button at `:197-203` is inside it. On an account without the Captain flag the
expand-editor affordance is gone entirely, even though the underlying
`ResizableEditorWrapper.toggleEditorExpand` (`MessagesView.vue:463-465`) is unrelated to AI.
The drag handle (`ResizableEditorWrapper.vue:167-177`) remains as the only route, and it is a
32×2px unlabelled bar.

**T2 — The bulk-selection checkbox in the condensed card only exists on pointer hover, so
bulk selection is unreachable by touch.** Severity: high.
`ConversationCard.vue:138-146` renders the checkbox under `v-if="hovered || selected"`, where
`hovered` is set by `@mouseenter` (`:125-126`). Touch devices never fire hover, and the
expanded card — which has an always-visible checkbox (`ConversationCardExpanded.vue:87-89`) —
is gated on `isOnExpandedLayout && >=1024px` (`ConversationList.vue:32-38`). Phones are forced
to `expanded` display type but are under 1024px (`Dashboard.vue:91-94`), so they render
condensed cards. Result: on every phone and on tablets between 768px and 1023px there is no
way to select a conversation for a bulk action.

**T3 — Context-menu submenus open on CSS `:hover` only.** Severity: high.
`menuItemWithSubmenu.vue:61-70`: `.menu-with-submenu:hover .submenu { @apply block; }` is the
only thing that reveals the submenu, and the submenu body is `hidden` by default (`:53`).
Priority, Label, Agent and Team assignment from the card context menu therefore have no
keyboard or touch path at all.

**T4 — The SLA detail popover is hover-only.** Severity: medium.
`components/SLACardLabel.vue` template `:36-40`: the `SLAPopoverCard` is
`hidden group-hover:flex`. The chip is `cursor-pointer` (`:4`) but is a `<div>` with no
click handler, no `tabindex` and no `role`, so it looks clickable, is not, and its content is
unreachable without a mouse.

**T5 — Two separate controls change the same status filter, and one of them is a read-only
chip that looks like a control.** Severity: low. `ChatListHeader.vue:104-109` renders the
active status as a rounded `bg-n-slate-3` chip identical in shape to the interactive count
chip at `:95-103`; the actual control is behind the unlabelled sort icon
(`ConversationBasicFilter.vue:147-154`).

**T6 — Icon-only triggers across the surface carry no visible label and no accessible name.**
Severity: medium (see A1). The chat-list header exposes save-filter, edit-folder,
delete-folder, filter, sort and layout as six adjacent 24px icon buttons
(`ChatListHeader.vue:112-181`) with tooltips as the only affordance.

### 3.7 Empty-state quality

**E1 — The conversation-list empty state is a bare top-aligned paragraph with no
illustration, no CTA, and no distinction between "nothing matches your filter" and "this
inbox is empty".** Severity: high. `ChatList.vue:931-936`:

```
<p v-if="!chatListLoading && !conversationList.length"
   class="flex overflow-auto justify-center items-center p-4">
  {{ $t('CHAT_LIST.LIST.404') }}
</p>
```

The copy is fixed — "There are no active conversations in this group."
(`i18n/locale/en/chatlist.json:7`) — regardless of whether the user is on the Mine tab, in a
saved folder, under five advanced filters, or on a brand-new inbox. There is no "clear
filters" action even though `resetAndFetchData` is already wired to the header back button
(`ChatListHeader.vue:90`). The element has no `flex-1`, so it renders flush under the tab
strip with the rest of the panel empty below it, while the centre pane shows the much
richer illustrated `EmptyStateMessage` (`EmptyStateMessage.vue:16-31`).

**E2 — The list has no error state at all.** Severity: high. Every fetch failure path ends in
a transient toast — `ChatList.vue:399`, `:416`, `:425` all call
`useAlert(t('CHAT_LIST.FETCH_ERROR'))` — after which the list falls through to E1's "there
are no active conversations" paragraph. A failed load is therefore indistinguishable from an
empty inbox, and there is no retry affordance anywhere in the panel.

**E3 — The empty-state illustrations have untranslated decorative alt text.** Severity: low.
`EmptyStateMessage.vue:19` `alt="No Chat dark"`, `:24` `alt="No Chat"`. These are decorative
and should be `alt=""`; as written a screen reader announces "No Chat dark" twice (once per
theme variant, both are in the DOM, hidden only by `dark:block`/`dark:hidden`).

**E4 — Sidebar section empty states are inconsistent in colour, placement and whether they
offer an action.** Severity: medium. Macros centres a paragraph and offers a "create macro"
button (`Macros/List.vue:58-71`); Shared files is a centred `text-n-slate-11` paragraph with
no action (`SharedFiles.vue:54-56`); Previous conversations is a left-aligned
`text-n-slate-11` span with extra bottom margin (`ContactConversations.vue` template `:3-7`,
`:51-54`); Participants is a left-aligned `text-n-slate-10` paragraph
(`ConversationParticipant.vue:165-172`) — a different slate step from its siblings and
different from the populated state in the same component, which has no colour class at all
(`:162`).

**E5 — The label submenu's empty state is the only empty state in the context menu.**
Severity: low. `contextMenu/Index.vue:388-393` handles "no labels found", but the Agent
submenu (`:396-411`) and Team submenu (`:412-423`) just render an empty box when the list is
empty — their `sub-menu-available` prop dims the parent row to `opacity-50 cursor-not-allowed`
(`menuItemWithSubmenu.vue:44`) with no explanation of why.

### 3.8 Table / list usability

**L1 — The expanded "table" view has no column headers.** Severity: high.
`ConversationCardExpanded.vue:73-192` lays out ten semantic columns — priority, assignee,
status, inbox, id, contact, message, labels, SLA, time — as a bare grid of rows with no header
row anywhere in `ConversationList.vue` or `ChatList.vue`. The priority, assignee and status
columns are 16px icon slots (`:93-119`); a user has to hover each one to learn what the column
means, and three of them use the same `w-4` footprint side by side.

**L2 — Columns are not sortable from the header, because there is no header.** Severity:
medium. Ten sort orders exist (`ConversationBasicFilter.vue:68-109`) but are reachable only
through an unlabelled `i-lucide-arrow-up-down` icon button
(`ConversationBasicFilter.vue:147-154`) that opens a 288px floating panel. The sort currently
in effect is not shown anywhere in the list chrome — the header chip shows status, not sort
(`ChatListHeader.vue:104-109`).

**L3 — List rows are not focusable and have no keyboard activation.** Severity: high.
`ConversationCard.vue:111-122` and `ConversationCardExpanded.vue:72-84` are `<div>`s with
`@click`/`@contextmenu` and no `tabindex`, `role` or `@keydown`. The only keyboard route is
Alt+J / Alt+K, which work by finding DOM nodes and calling `.click()`
(`useChatListKeyboardEvents.js:40`, `:45`) — so a keyboard user cannot Tab into the list,
cannot open the context menu, and cannot toggle a row's checkbox.

**L4 — Virtualisation makes "select all" mean "select all loaded", with only a prose
disclosure.** Severity: medium. `selectAllConversations` maps over `conversationList`
(`useBulkActions.js:42-53`), which is the client-side array of fetched pages
(`ChatList.vue:314-351`), not the server-side total. The header shows the true total
(`ChatListHeader.vue:95-103`) while the bar shows the selected count
(`conversationBulkActions/Index.vue:80-84`); the only reconciliation is the amber
"All conversations selected" sentence at `:152-157`.

**L5 — The row divider is faked with a `::before` pseudo-element toggled on hover.**
Severity: low. `ConversationCard.vue:112` carries
`before:content-[none] … hover:before:content-['']` plus a sibling-aware selector on the
virtualiser (`ConversationList.vue:70`:
`[&>div:has(+_div_.active)>*]:!border-n-surface-1`). This couples row chrome to DOM sibling
order inside a virtualised list.

### 3.9 Mobile behaviour

Below 768px the display type is forced to `expanded` (`Dashboard.vue:88-102`), which makes
`showConversationList` and `showMessageView` mutually exclusive
(`ConversationView.vue:78-83`): the list fills the viewport (`ChatList.vue:882`
`basis-full`), and opening a conversation replaces it. The shell drops its padding, borders,
radii, shadows and decorative glows (`ConversationView.vue:673-698`), and the layout toggle
button hides itself (`SwitchLayout.vue:34` `md:inline-flex hidden`). The bulk bar lifts to
`bottom-20` to clear the bottom nav (`conversationBulkActions/Index.vue:150`); the sidebar
becomes a `fixed … w-full max-w-sm` overlay dismissed by click-outside
(`ConversationSidebar.vue:54`, `:28-39`); the SLA chip hides under `md:`
(`ConversationHeader.vue:173`).

**M1 — Bulk selection is unreachable on touch.** Severity: high. See T2 — hover-only
checkbox in the condensed card, and the expanded card never renders under 1024px.

**M2 — Context-menu submenus are unreachable on touch.** Severity: high. See T3 — CSS
`:hover` is the only trigger. On a phone a long-press/right-click equivalent opens the menu,
but Priority, Label, Agent and Team cannot be opened from it.

**M3 — The SLA popover is unreachable on touch.** Severity: medium. See T4.

**M4 — The floating sidepanel switch overlaps thread content at mobile widths.** Severity:
medium. `SidepanelSwitch.vue:53` pins the pill at `absolute top-36 xl:top-24 ltr:right-2` with
`!z-20`. Below `xl` the conversation header is already 96px tall
(`ConversationHeader.vue:113`), so the pill lands on top of the first messages rather than
beside the header, and it has no mobile-specific placement.

**M5 — Icon-only toolbar buttons are below the mobile tap-target floor.** Severity: medium.
The design system defines `height.control-lg = 2.5rem` and notes "40px is also the mobile
tap-target floor" (`tailwind.config.js:79-84`). The chat-list header uses `xs` buttons plus
explicit `!h-6 !w-6` (`ChatListHeader.vue:86`), the bulk bar uses `xs` throughout
(`BulkAgentActions.vue:119`, `BulkLabelActions.vue:127`, `BulkTeamActions.vue:86`,
`BulkUpdateActions.vue:84`), and the macro row uses `xs` (`MacroItem.vue:47`, `:55`).

**M6 — The composer toolbar overflows rather than adapting on narrow widths.** Severity:
high. See D1 — `left-wrap` has no `flex-wrap`, and the only responsive accommodation anywhere
in the bar is the label-button text hiding inside the *contact* variant
(`BulkLabelActions.vue:131`).

**M7 — The dashboard-app tab strip has horizontal scroll buttons but they are unlabelled
icon buttons with no accessible name.** Severity: low. `ui/Tabs.vue:72-78`, `:88-94`.

**M8 — Returning from a narrow viewport can write `undefined` as the layout.** Severity: low.
`Dashboard.vue:96-98` writes `conversation_display_type: this.previouslyUsedDisplayType`,
which is `undefined` for a user who has never toggled the layout
(`Dashboard.vue:80-85`), relying on the `= CONDENSED` default downstream
(`useUISettings.js:159-161`).

### 3.10 RTL behaviour

The surface is largely RTL-aware: `ltr:`/`rtl:` pairs and logical `ms`/`me`/`start`/`end`
utilities are used widely (e.g. `ChatListHeader.vue:86`, `:125`; `ConversationCard.vue:182`,
`:217`, `:230`; `ConversationBasicFilter.vue:159-162`; `ResolveAction.vue:190`, `:229`;
`SwitchLayout.vue:34` even counter-rotates its icon). The following break it.

**R1 — Context-menu submenus flip to the wrong side in RTL.** Severity: high.
`menuItemWithSubmenu.vue:28-32` picks `right-full` or `left-full` from
`windowWidth - right`, i.e. physical viewport geometry with no `dir` awareness, and the
disclosure chevron is a fixed `icon="chevron-right"` with no flip (`:50`). In RTL the submenu
opens away from the reading direction and the chevron points out of the menu.

**R2 — The conversation-header back button's chevron does not flip.** Severity: medium.
`widgets/BackButton.vue:35`: `<i class="i-lucide-chevron-left -ml-1 text-lg" />` — physical
`-ml-1` and a hard left chevron. Used at `ConversationHeader.vue:118`, so in RTL the "go back
to the list" arrow points forward.

**R3 — The chat-list header's clear-filter chevron does not flip.** Severity: medium.
`ChatListHeader.vue:86` is `icon="i-lucide-chevron-left"` — the margin is correctly logical
(`-ms-2 … me-1`) but the glyph is not mirrored.

**R4 — The card-label overflow chevron mirrors the icon but applies the margin twice.**
Severity: low. `conversationCardComponents/CardLabels.vue:89` is
`mr-6 ml-0 rtl:ml-6 rtl:mr-0 rtl:rotate-180` — the `rtl:rotate-180` handles the glyph, but
the base `mr-6 ml-0` is physical and only partly overridden.

**R5 — The bulk bar centres itself with physical `left-1/2 -translate-x-1/2`.** Severity:
low. `conversationBulkActions/Index.vue:150`. Harmless at exact centre, but it is the one
positioned element in the bar with no logical equivalent, next to four dropdowns that do use
`ltr:`/`rtl:` pairs.

**R6 — The typing pill's padding is physical.** Severity: low. `MessagesView.vue:562`
`pr-4 pl-5` — see S5.

**R7 — The tab active-underline uses physical insets.** Severity: low.
`ui/Tabs/TabsItem.vue:50` `after:left-0 after:right-0`; the horizontal scroll buttons
(`ui/Tabs.vue:46-47`) always add to `scrollLeft` regardless of direction, so in RTL the
"left" chevron scrolls the wrong way.

**R8 — The emoji picker's RTL offset is a hard-coded mirrored magic number.** Severity: low.
`ReplyBox.vue:1588` `ltr:-left-80 … rtl:-right-80` with the arrow rotated 270°/90°
(`:1592`); the expanded variant drops the RTL pair entirely and uses
`left-[unset]` (`:1597`) plus `ltr:left-1 rtl:right-1` (`:1601`).

### 3.11 Loading and error behaviour

**LE1 — Two loading indicators can be on screen at once for the same fetch.** Severity: low.
`ChatList.vue:894` passes `chatListLoading && !conversationList.length` to the header while
`ConversationList.vue:82-84` renders a bottom spinner for the same `isLoading`, and
`EmptyState.vue:69-72` renders a third full-pane `woot-loading-state` for
`loadingChatList` in the centre column.

**LE2 — There is no skeleton anywhere in the list.** Severity: medium. The first page shows
nothing but a bottom-anchored spinner (`ConversationList.vue:82-84`), so a cold load is an
empty panel, then a full jump to 25 rows.

**LE3 — Several failure paths are swallowed silently.** Severity: medium.
`ConversationItem` mark-as-read/unread swallow errors with an empty `catch`
(`ChatList.vue:684-702`, `// Ignore error`); `copyConversationId` swallows clipboard failures
(`ConversationHeader.vue:104-106`, `// error`); `copyConversationLink` the same
(`contextMenu/Index.vue:270-272`); `fetchPreviousMessages` the same
(`MessagesView.vue:435-437`, `// Ignore Error`). Each of these is a user-initiated action that
can fail with no feedback.

**LE4 — The one in-list error signal is a toast on a surface the user may have left.**
Severity: medium. See E2. `ChatList.vue:399-402` deliberately emits
`conversationLoad` even on failure so deep links still resolve, which means a failed list
fetch produces a toast and then a normal-looking empty list.

**LE5 — Bulk in-flight state is per-dropdown, not per-bar.** Severity: low.
`bulkActions/getUIFlags.isUpdating` disables only the confirm button inside the open dropdown
(`BulkAgentActions.vue:191`, `BulkTeamActions.vue:157`); the label, status and the other
assignment triggers stay live, so two bulk mutations can be fired against the same selection.

### 3.12 Accessibility

**A1 — The entire surface contains two `aria-*` attributes, one `role` and one `tabindex`.**
Severity: high. A grep across `ChatList.vue`, `ChatListHeader.vue`, `ConversationList.vue`,
`ConversationItem.vue`, `ChatTypeTabs.vue`, `ConversationCard.vue`,
`ConversationCardExpanded.vue`, `ConversationHeader.vue`, `ConversationBox.vue`,
`MessagesView.vue`, `ReplyBox.vue`, `ReplyTopPanel.vue`, `ReplyBottomPanel.vue`,
`EditorModeToggle.vue`, all four `Bulk*Actions.vue`, `conversationBulkActions/Index.vue`, all
four `contextMenu/*`, `ui/ContextMenu.vue`, `ResolveAction.vue`, `ContactPanel.vue` and
`ConversationBasicFilter.vue` returns exactly: `aria-label` at `ChatListHeader.vue:84`,
`aria-pressed` at `ReplyBottomPanel.vue:356`, `role="button"` at
`contextMenu/menuItem.vue:18`, `tabindex="0"` at `ui/ContextMenu.vue:100`.

**A2 — Icon-only buttons have no accessible name.** Severity: high.
`components-next/button/Button.vue:240-260` renders `<button v-bind="filteredAttrs">` with an
`Icon` and no fallback label, so an icon-only instance is announced as an unlabelled button
unless the caller passes `aria-label`. Only one call site in this surface does
(`ChatListHeader.vue:84`). The unlabelled set includes: save-filter, edit-folder,
delete-folder, filter, sort and layout in the chat-list header
(`ChatListHeader.vue:112-181`); all ten composer toolbar buttons
(`ReplyBottomPanel.vue:288-408`); the Copilot and maximise buttons
(`ReplyTopPanel.vue:172-203`); all four bulk triggers
(`BulkAgentActions.vue:115-123`, `BulkLabelActions.vue:122-137`,
`BulkTeamActions.vue:82-90`, `BulkUpdateActions.vue:80-88`); the "⋮" and phone buttons
(`MoreActions.vue:103-111`, `ConversationCallButton.vue:132-142`); both sidepanel toggles
(`SidepanelSwitch.vue:55-80`); and both macro buttons (`MacroItem.vue:42-59`). `v-tooltip`
supplies only `aria-describedby`, and only while the tooltip is rendered, so it never provides
a name.

**A3 — The context menu is not a menu.** Severity: high.
`ui/ContextMenu.vue:96-105` is a `tabindex="0"` div with no `role="menu"`; items are divs with
`role="button"` and no `tabindex` (`menuItem.vue:18`), so nothing inside is focusable. There
is no arrow-key navigation, no Escape handler (dismissal relies on `@focusout`,
`ui/ContextMenu.vue:80-87`), no `aria-expanded`/`aria-haspopup` on the submenu rows, and the
submenus open on CSS hover only (`menuItemWithSubmenu.vue:65-69`).

**A4 — Tabs are not tabs.** Severity: high. `ui/Tabs/TabsItem.vue:49-73` renders each tab as
an `<a>` with no `href`, so it is outside the tab order, and there is no `role="tablist"`,
`role="tab"`, `aria-selected` or `aria-controls` anywhere in `ui/Tabs.vue` /
`TabsItem.vue`. This covers the Mine / Unassigned / All assignee tabs
(`ChatTypeTabs.vue:49-63`) and the dashboard-app tab strip
(`ConversationBox.vue:110-124`). The only keyboard path is the undiscoverable `Alt+N`
(`ChatTypeTabs.vue:33`).

**A5 — List rows are non-semantic, non-focusable click targets.** Severity: high. See L3.

**A6 — The reply/note mode toggle is a single button with no pressed state or group
semantics.** Severity: medium. `EditorModeToggle.vue:71-96` is one `<button>` containing both
labels and a sliding chip; there is no `aria-pressed`, no `role="radiogroup"`/`radio`, and no
`aria-live` on the change, so a screen-reader user cannot tell whether they are about to send
a public reply or a private note — the one distinction on this surface with real external
consequences.

**A7 — Status and priority are conveyed by colour and icon only.** Severity: medium.
`CardStatusIcon.vue:33-41` and `CardPriorityIcon.vue:54-62` render a bare `Icon` with a
tooltip and no text alternative; in the expanded card these are whole columns
(`ConversationCardExpanded.vue:93-119`). The status tooltip is additionally an untranslated
raw enum (see C6).

**A8 — The SLA chip looks interactive, is not, and hides its content behind hover.**
Severity: medium. `components/SLACardLabel.vue` template `:2-6` — `cursor-pointer group` on a
`<div>` with no handler, `tabindex` or `role`; popover at `:39` is
`hidden group-hover:flex`.

**A9 — The composer resize handle is a mouse-only control.** Severity: medium.
`ResizableEditorWrapper.vue:167-177` is a div with `@mousedown`, `@touchstart` and
`@dblclick`, no `role="separator"`, no `aria-orientation`, no `tabindex` and no keyboard
resize. With T1 (expand button hidden without Captain) this is the only way to grow the
composer on most accounts.

**A10 — Decorative images are announced.** Severity: low. `EmptyStateMessage.vue:19`, `:24`
and `MessagesView.vue:568` all carry descriptive `alt` on purely decorative assets; both
empty-state variants are in the DOM simultaneously.

**A11 — Single-letter global shortcut with no visible hint, and a near-collision.**
Severity: low. `L` alone opens the sidebar label dropdown (`labels/LabelBox.vue:39-44`)
whenever the sidebar is mounted and focus is not in a field, while `Alt+L` switches the
composer to Reply (`ReplyTopPanel.vue:110`) and `Alt+K` moves to the next conversation
(`useChatListKeyboardEvents.js:53`) next to `Cmd+K` for the command bar
(`ReplyBox.vue:112`). None of the 15 shortcuts in §2.14 is surfaced anywhere in this surface's
chrome.

**A12 — `ConversationAction` receives an undeclared prop.** Severity: low.
`ContactPanel.vue:180` passes `:inbox-id="inboxId"` but `ConversationAction.vue:21-26`
declares only `conversationId`, so `inbox-id` falls through onto the root `<div>` as a stray
DOM attribute. Similarly `ChatList.vue:926` passes `is-compact` to `ChatTypeTabs`, which does
not declare it (`ChatTypeTabs.vue:6-15`), and `ChatTypeTabs.vue:51` passes it on to
`woot-tabs`, which does not declare it either (`ui/Tabs.vue:5-14`).

**A13 — `reduced-motion` is respected by the shell but not by the components.** Severity:
low. `ConversationView.vue:704-718` disables its own animations under
`prefers-reduced-motion`, but the card select animation (`ConversationCard.vue:114`
`animate-card-select`), the bulk-bar scale/translate transitions
(`conversationBulkActions/Index.vue:140-145`), the four dropdown transitions
(`BulkAgentActions.vue:124-131` and siblings), the two composer `Transition`s
(`ReplyBox.vue:1363-1371`, `:1480-1487`) and the mode-toggle chip slide
(`EditorModeToggle.vue:88`) are unguarded. The resize handle does guard its bounce
(`ResizableEditorWrapper.vue:174` `motion-safe:`), which shows the pattern is known here.

---

## 4. What this surface already does well and must not be lost

1. **Scope is preserved through every navigation.** `conversationUrl`
   (`ConversationItem.vue:82-94`) and `conversationListPageURL`
   (`ConversationHeader.vue:43-62`) round-trip inbox, label, team, folder and
   conversation-type, so opening a conversation from a folder and pressing back returns to that
   folder, and the 18 route pairs in §1 all keep their context. Cmd/Ctrl+click opens the same
   scoped URL in a new tab (`ConversationItem.vue:100-108`).

2. **Draft messages survive both conversation switches and reply-mode switches, keyed
   independently.** `editorStateId` / `getDraftKey` are
   `draft-<conversationId>-<replyMode>` (`ReplyBox.vue:453-455`, `:645-650`), the switch is
   explicit and idempotent (`switchDraftContext`, `:729-744`), autosave is debounced at 500ms
   with a leading call (`:611-617`) and also fires on blur (`:1092-1095`). A stale signature is
   normalised out of a restored draft rather than left in it (`:755-774`). This is subtle and
   easy to lose.

3. **Channel competence is deep and already encoded.** Per-channel max length
   (`ReplyBox.vue:333-368`), audio format (`:456-467`), allowed file types
   (`ReplyBottomPanel.vue:215-229`), multi-file support (`ReplyBox.vue:429-437`), the
   Instagram/TikTok text-and-attachment split with its two distinct reasons documented inline
   (`:872-878`, `:1191-1198`), WhatsApp caption-on-first-attachment only (`:1184-1186`), and
   channel-specific reply-window copy and policy links (`MessagesView.vue:196-248`).

4. **Required-attribute enforcement before resolve, including a sane bulk partial-success
   path.** `useBulkActions.js:166-196` splits the selection into valid and skipped, refuses
   only when nothing is resolvable, and reports partial success distinctly
   (`:212-216`). The single-conversation paths open a modal instead of failing
   (`ResolveAction.vue:120-139`, `ChatList.vue:742-769`).

5. **The bulk bar asks for confirmation with the real numbers in it.** Agent and team
   assignment render pluralised `I18nT` copy naming the count and the target, with separate
   assign and unassign strings (`BulkAgentActions.vue:147-177`,
   `BulkTeamActions.vue:113-143`), and the confirm button carries its own loading state.
   Remove-labels is correctly restricted to labels actually present on the selection
   (`BulkLabelActions.vue:73-80`), and context-menu label removal deliberately does not clear
   an in-progress bulk selection (`useBulkActions.js:122-133`).

6. **Deliberate attention to live-data correctness that reads as polish.** CC/BCC are only
   re-derived when the conversation id actually changes, not on every mutation, with the reason
   written down (`ReplyBox.vue:534-542`, `:559-570`); context-menu state is reset when a
   virtualised row is recycled (`ConversationItem.vue:43-52`); `conversationLoad` is emitted
   even on fetch failure so a deep link still resolves (`ChatList.vue:400-402`); the signature
   is only stripped when it is actually being auto-appended (`ReplyBox.vue:264-278`); the
   outbound WhatsApp call stays non-active until Meta's connect webhook so the timer does not
   start before pickup (`ConversationCallButton.vue:90-99`).

7. **Contact-history navigation inside the thread.** `ContactConversationLink.vue` puts
   "older"/"newer conversation" pills at the ends of the message list
   (`MessagesView.vue:521-526`, `:548-553`) with the start date, a last-message preview and a
   full timestamp tooltip — a cross-module link that is genuinely discoverable where it is
   needed.

8. **The sidebar is user-composable and remembers it.** Section order is drag-reorderable and
   persisted (`ContactPanel.vue:156-165`, `:125-130`) and each section's open/closed state is
   persisted independently (`:42-45`), across eleven heterogeneous panels including
   flag-gated Linear, Shopify and Commerce.

9. **The composer resizer is thoughtfully bounded.** Bounds are derived from the live
   container minus a 200px message-list floor and the measured surrounding panels
   (`ResizableEditorWrapper.vue:37-48`, `:62-69`); a content-driven request can only grow the
   editor, never shrink a dragged height (`:53-59`); the toggle jumps to max when "expanded"
   would be too close to default to be noticeable (`:121-123`); it auto-resets after send
   (`:126-129`) and cleans up drag styles on unmount and window blur (`:135-149`).

10. **Status transitions are reachable four ways, all consistent.** Header button + dropdown
    (`ResolveAction.vue:184-255`), card context menu (`contextMenu/Index.vue:316-330`), bulk
    bar (`BulkUpdateActions.vue:32-63`) and the command bar
    (`ResolveAction.vue:174-175`, `conversationBulkActions/Index.vue:125-135`), and each
    correctly hides the option matching the current status
    (`contextMenu/Index.vue:274-278`, `ChatList.vue:787-792`).

11. **Keyboard layout awareness.** `useKeyboardEvents` detects QWERTZ and remaps affected
    bindings (`composables/useKeyboardEvents.js:52-62`), blurs the field on Escape
    (`:22-27`), and distinguishes per-binding whether it may fire inside a typeable element —
    which is why Alt+J/Alt+K work while composing but Alt+P/Alt+L do not.

12. **RTL is the default assumption in most of the markup.** Logical utilities and
    `ltr:`/`rtl:` pairs are pervasive (see §3.10), including counter-rotating the layout-switch
    icon (`SwitchLayout.vue:34`) and mirroring the label-overflow chevron
    (`CardLabels.vue:89`). The breakages listed are exceptions in an otherwise RTL-literate
    surface and should be fixed, not used as licence to drop the pattern.

13. **The load-bearing selectors in §2.16 are, today, correct and working.** They are fragile,
    but Alt+J/Alt+K navigation, Cmd+Alt+E resolve-and-advance, the Cmd+Alt+A attachment
    shortcut, the two teleport anchors and the sidebar's popover-aware click-outside all
    function. Any redesign must either keep these hooks or move the behaviour onto refs first.
