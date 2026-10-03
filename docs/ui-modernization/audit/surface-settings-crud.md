# Surface Audit — Settings CRUD pages

**Surface:** Settings CRUD (agents, teams, inboxes, labels, custom attributes, canned responses, macros, agent bots)
**Mode:** read-only inventory. No application file was modified.
**Date:** 2026-10-03
**Scope root:** `app/javascript/dashboard/routes/dashboard/settings/{agents,teams,inbox,labels,attributes,canned,macros,agentBots}/**`

Everything asserted below carries a `file:line`. Paths are relative to
`/home/user/lynomiachat/app/javascript/` unless absolute.

---

## 1. Routes and the primary task

### 1.1 Route table

All eight features mount under `frontendURL('accounts/:accountId/settings/…')` and are
assembled in `dashboard/routes/dashboard/settings/settings.routes.js:54-71`.

| Feature | Path | Route name | Shell component | Feature flag | Permissions |
|---|---|---|---|---|---|
| Agents | `settings/agents` → redirect | — | `SettingsWrapper` | — | — (`agents/agent.routes.js:9-17`) |
| Agents list | `settings/agents/list` | `agent_list` | `SettingsWrapper` | `AGENT_MANAGEMENT` | `['administrator']` (`agents/agent.routes.js:18-26`) |
| Teams | `settings/teams` → redirect | — | `SettingsWrapper` | — | — (`teams/teams.routes.js:21-26`) |
| Teams list | `settings/teams/list` | `settings_teams_list` | `SettingsWrapper` | `TEAM_MANAGEMENT` | `['administrator']` (`teams/teams.routes.js:27-35`) |
| Team create step 1 | `settings/teams/new` | `settings_teams_new` | `Wrapper` → `Create/Index.vue` | `TEAM_MANAGEMENT` | `['administrator']` (`teams/teams.routes.js:53-61`) |
| Team create step 2 | `settings/teams/new/:teamId/agents` | `settings_teams_add_agents` | `Wrapper` → `Create/Index.vue` | `TEAM_MANAGEMENT` | `['administrator']` (`teams/teams.routes.js:71-79`) |
| Team create step 3 | `settings/teams/new/:teamId/finish` | `settings_teams_finish` | `Wrapper` → `Create/Index.vue` | `TEAM_MANAGEMENT` | `['administrator']` (`teams/teams.routes.js:62-70`) |
| Team edit step 1 | `settings/teams/:teamId/edit` | `settings_teams_edit` | `Wrapper` → `Edit/Index.vue` | `TEAM_MANAGEMENT` | `['administrator']` (`teams/teams.routes.js:85-94`) |
| Team edit step 2 | `settings/teams/:teamId/edit/agents` | `settings_teams_edit_members` | `Wrapper` → `Edit/Index.vue` | `TEAM_MANAGEMENT` | `['administrator']` (`teams/teams.routes.js:95-103`) |
| Team edit step 3 | `settings/teams/:teamId/edit/finish` | `settings_teams_edit_finish` | `Wrapper` → `Edit/Index.vue` | `TEAM_MANAGEMENT` | `['administrator']` (`teams/teams.routes.js:104-112`) |
| Inboxes | `settings/inboxes` → redirect | — | `SettingsWrapper` | — | — (`inbox/inbox.routes.js:20-25`) |
| Inboxes list | `settings/inboxes/list` | `settings_inbox_list` | `SettingsWrapper` | `INBOX_MANAGEMENT` | `['administrator']` (`inbox/inbox.routes.js:26-34`) |
| Inbox create step 1 | `settings/inboxes/new` | `settings_inbox_new` | `Wrapper` → `InboxChannels.vue` | `INBOX_MANAGEMENT` | `['administrator']` (`inbox/inbox.routes.js:55-63`) |
| Inbox create step 2 | `settings/inboxes/new/:sub_page` | `settings_inboxes_page_channel` | `Wrapper` → `InboxChannels.vue` → `ChannelFactory` | `INBOX_MANAGEMENT` | `['administrator']` (`inbox/inbox.routes.js:73-84`) |
| Inbox create step 3 | `settings/inboxes/new/:inbox_id/agents` | `settings_inboxes_add_agents` | `Wrapper` → `InboxChannels.vue` | `INBOX_MANAGEMENT` | `['administrator']` (`inbox/inbox.routes.js:85-93`) |
| Inbox create step 4 | `settings/inboxes/new/:inbox_id/finish` | `settings_inbox_finish` | `Wrapper` → `InboxChannels.vue` | `INBOX_MANAGEMENT` | `['administrator']` (`inbox/inbox.routes.js:64-72`) |
| Inbox detail / edit | `settings/inboxes/:inboxId/:tab?` | `settings_inbox_show` | `Wrapper` (`fullWidth`) → `Settings.vue` | `INBOX_MANAGEMENT` | `['administrator']` (`inbox/inbox.routes.js:96-104`) |
| Labels wrapper | `settings/labels` → redirect | `labels_wrapper` | `SettingsWrapper` | — | `['administrator']` (`labels/labels.routes.js:13-22`) |
| Labels list | `settings/labels/list` | `labels_list` | `SettingsWrapper` | `LABELS` | `['administrator']` (`labels/labels.routes.js:23-31`) |
| Attributes | `settings/custom-attributes` → redirect | — | `SettingsWrapper` | — | — (`attributes/attributes.routes.js:12-17`) |
| Attributes list | `settings/custom-attributes/list` | `attributes_list` | `SettingsWrapper` | `CUSTOM_ATTRIBUTES` | `['administrator']` (`attributes/attributes.routes.js:18-26`) |
| Canned | `settings/canned-response` → redirect | — | `SettingsWrapper` | — | — (`canned/canned.routes.js:16-21`) |
| Canned list | `settings/canned-response/list` | `canned_list` | `SettingsWrapper` | `CANNED_RESPONSES` | `[...ROLES, ...CONVERSATION_PERMISSIONS]` (`canned/canned.routes.js:22-30`) |
| Macros list | `settings/macros` | `macros_wrapper` | `SettingsWrapper` | `MACROS` | `[...ROLES, ...CONVERSATION_PERMISSIONS]` (`macros/macros.routes.js:19-27`) |
| Macro create | `settings/macros/new` | `macros_new` | `Wrapper` → `MacroEditor.vue` | `MACROS` | `[...ROLES, ...CONVERSATION_PERMISSIONS]` (`macros/macros.routes.js:50-58`) |
| Macro edit | `settings/macros/:macroId/edit` | `macros_edit` | `Wrapper` → `MacroEditor.vue` | `MACROS` | `[...ROLES, ...CONVERSATION_PERMISSIONS]` (`macros/macros.routes.js:41-49`) |
| Agent bots | `settings/agent-bots` | `agent_bots` | `SettingsWrapper` | `AGENT_BOTS` | `['administrator']` (`agentBots/agentBot.routes.js:9-24`) |

`ROLES` = `['agent','administrator']` and `CONVERSATION_PERMISSIONS` = the three
`conversation_*_manage` custom-role permissions (`dashboard/constants/permissions.js:11-17`).
So canned responses and macros are the only two surfaces in this group reachable by a
non-administrator; the other six are administrator-only at the route level.

`settings_home` (`settings.routes.js:37-53`) redirects administrators without a custom role to
`general_settings_index` and **everyone else to `canned_list`** — canned responses is the de-facto
settings landing page for agents.

### 1.2 Primary task

Give an administrator one place per configuration object type to **see the existing records,
find one by name, create a new one, edit one, and delete one** — with the heavier objects
(inboxes, teams, macros) escalating from an in-place dialog to a multi-step page flow because
they need agent assignment and per-channel configuration.

### 1.3 How the eight pages solve the same problem differently (the comparison axis)

| Page | Body presentation | Row actions | Create flow | Edit flow | Delete confirm | Extra |
|---|---|---|---|---|---|---|
| Agents | Hand-rolled `divide-y` stack (`agents/Index.vue:184-279`) | icon Edit + icon Delete, each conditionally hidden | `woot-modal` + `AddAgent` | `woot-modal` + `EditAgent` | `woot-delete-modal` (plain) | hover tooltip listing custom-role permissions; Reset-password inside edit modal |
| Teams | Hand-rolled `divide-y` stack (`teams/Index.vue:119-182`) | `router-link` Settings icon + icon Delete | 3-step wizard page | 3-step wizard page | `woot-confirm-delete-modal` (type the name) | emoji/icon avatar |
| Inboxes | Hand-rolled `divide-y` stack (`inbox/Index.vue:128-212`) | `router-link` Settings icon + icon Delete | 4-step wizard page | tabbed detail page | `woot-confirm-delete-modal` (type the name) | channel icon, channel name + identifier |
| Labels | `BaseTable` 4 cols (`labels/Index.vue:131-191`) | icon Edit + icon Delete | `woot-modal` + `AddLabel` | `woot-modal` + `EditLabel` | `woot-delete-modal` (plain) | colour swatch cell |
| Attributes | Hand-rolled `divide-y` + `AttributeListItem` (`attributes/Index.vue:206-218`) | icon Edit + icon Delete (inside the list item) | **self-rendering** `woot-modal` in `AddAttribute` | `woot-modal` + `EditAttribute` | `woot-confirm-delete-modal` (type the name) | 2 tabs (`TabBar`), type label, pre-chat/resolution badges |
| Canned | `BaseTable` 2 cols (`canned/Index.vue:173-249`) | icon Edit + icon Delete | `woot-modal` wrapping `AddCanned`, **which renders its own `Modal`** | same double-modal shape | `woot-delete-modal` (plain) | custom sort toggle in header cell |
| Macros | `BaseTable` 5 cols via `MacrosTableRow` (`macros/Index.vue:102-118`) | `router-link` Edit + icon Delete (delete gated) | full page (`macros_new`) | full page (`macros_edit`) | `woot-delete-modal`, title borrowed from `LABEL_MGMT` | created-by / updated-by avatars, visibility column |
| Agent bots | `BaseTable` 3 cols (`agentBots/Index.vue:129-200`) | icon Edit + icon Delete (both hidden for system bots) | next-gen `Dialog` (`AgentBotModal`) | same `Dialog` | next-gen `Dialog type="alert"` | global-bot badge, access token + secret copy/reset |

Three different page shells, three different list presentations, three different
delete-confirmation mechanisms, and four different create-flow shapes for one task family.

### 1.4 The shells

- **`SettingsWrapper.vue`** — the list-page shell. `max-w-5xl mx-auto`, `pb-8 pt-4 px-6`,
  `overflow-auto`, `bg-n-surface-1`, `<keep-alive>` keyed on `route.fullPath` unless
  `route.meta.reuseOnQueryChange` (`settings/SettingsWrapper.vue:16-33`). It renders **no header
  of its own** — each page supplies its own `BaseSettingsHeader`.
- **`Wrapper.vue`** — the sub-page shell used by team wizard, inbox wizard, inbox detail and macro
  editor. Renders `SettingsHeader` with icon + title + optional back button, constrained to
  `max-w-7xl` (`settings/Wrapper.vue:21-37`).
- **`SettingsHeader.vue`** — `h-20 min-h-[3.5rem] px-6`, `h1` wrapping `BackButton` and a
  `text-xl font-medium` title span (`settings/SettingsHeader.vue:43-59`).
- **`SettingsSubPageHeader.vue`** — `text-heading-1` + `v-dompurify-html` body, used inside the
  wizard step panes (`settings/SettingsSubPageHeader.vue:10-19`).
- **`SettingsLayout.vue`** — the state machine every list page uses: `header` slot, `preBody` slot,
  `loading` slot (defaults to `woot-loading-state`), a "no records" `<p>`, then the `body` slot
  (`settings/SettingsLayout.vue:22-41`).
- **`BaseSettingsHeader.vue`** — the shared list header: back button, title, description,
  "learn more" link, search input, `tabs` slot, `count` slot, `actions` slot
  (`settings/components/BaseSettingsHeader.vue:43-130`).

---

## 2. FEATURE PARITY MANIFEST

This table is the baseline. Every row is a control, action, state or affordance that exists in the
code today. `gating` is the condition under which it renders or is enabled.

### 2.1 Shared shell and header (applies to every list page unless noted)

| # | Feature | Kind | Where it lives today | Gating |
|---|---|---|---|---|
| 1 | Page scroll container, `max-w-5xl` centred, `bg-n-surface-1` | state | `settings/SettingsWrapper.vue:22-25` | list pages only |
| 2 | `<keep-alive>` page caching keyed on `route.fullPath` | state | `settings/SettingsWrapper.vue:27-29` | `keepAlive` prop, default `true` |
| 3 | Sub-page shell with `SettingsHeader` (icon + title) | navigation | `settings/Wrapper.vue:21-29` | `headerTitle \|\| icon \|\| showBackButton` |
| 4 | Back button in sub-page header | navigation | `settings/SettingsHeader.vue:47-52`, `components/widgets/BackButton.vue:29-37` | `showBackButton` prop |
| 5 | Back button falls back to `router.go(-1)` when no `backUrl` | navigation | `components/widgets/BackButton.vue:18-24` | `backUrl === ''` |
| 6 | Compact back button in list header | navigation | `settings/components/BaseSettingsHeader.vue:45-50` | `backButtonLabel` prop (unused by these 8 pages) |
| 7 | Page title `h1 text-heading-1` | state | `settings/components/BaseSettingsHeader.vue:56-58` | `title` prop (required) |
| 8 | Page description, `line-clamp-5 sm:line-clamp-none max-w-3xl` | state | `settings/components/BaseSettingsHeader.vue:67-72` | `description` or `description` slot |
| 9 | "Learn more" external help link + chevron | contextual link | `settings/components/BaseSettingsHeader.vue:74-86` | `helpURL && linkText`; **`hidden sm:inline-flex`**; suppressed on custom-branded instances via `CustomBrandPolicyWrapper` |
| 10 | Help URL resolution per feature key | contextual link | `dashboard/helper/featureHelper.js:1-31` | `featureName` must be a known key |
| 11 | Search input with magnifier prefix, `type="search"`, size `sm` | filter | `settings/components/BaseSettingsHeader.vue:103-117` | `searchPlaceholder` prop; **`hidden sm:flex`** |
| 12 | Record count chip in header | status | `settings/components/BaseSettingsHeader.vue:123` (`count` slot) | per page, only when list non-empty |
| 13 | Vertical divider between count and actions | state | `settings/components/BaseSettingsHeader.vue:124-127` | both `count` and `actions` slots filled |
| 14 | Primary action slot (the "new X" button) | primary | `settings/components/BaseSettingsHeader.vue:128` | per page |
| 15 | Tabs slot in header row | tab | `settings/components/BaseSettingsHeader.vue:102` | only attributes uses it |
| 16 | Header row collapses: `flex-wrap sm:flex-nowrap`, action group reverses on mobile when no tabs | mobile | `settings/components/BaseSettingsHeader.vue:91-121` | `sm` breakpoint |
| 17 | Loading state: `woot-loading-state` (message + spinner) | loading | `settings/SettingsLayout.vue:28-30`, `components/widgets/LoadingState.vue:9-19` | `isLoading` prop |
| 18 | Empty state: centred `<p>` with `py-20` | empty | `settings/SettingsLayout.vue:31-36` | `noRecordsFound` prop |
| 19 | `preBody` slot rendered before the state machine | state | `settings/SettingsLayout.vue:27` | unused by these 8 pages |
| 20 | Default (unnamed) slot used to host modals inside the layout | state | `settings/SettingsLayout.vue:39` | all list pages put their modals here |
| 21 | Table: `thead` kept visible in empty state | empty | `components-next/table/BaseTable.vue:65-66,89-131` | `headers.length > 0` |
| 22 | Table: per-column sort button with `aria-sort` + `TABLE.SORT_BY` aria-label | filter | `components-next/table/BaseTable.vue:99-126` | `sortableColumns[index]` — **never passed by any page** |
| 23 | Table: skeleton loading rows | loading | `components-next/table/BaseTable.vue:134-148` | `loading` prop — **never passed by any page** |
| 24 | Table: sticky header | state | `components-next/table/BaseTable.vue:92` | `stickyHeader` prop — **never passed by any page** |
| 25 | Table: horizontal scroll container | mobile | `components-next/table/BaseTable.vue:87` | `scrollable` prop, default `false` — **never passed by any page** |
| 26 | Table: `no-data-message` row spanning all columns | empty | `components-next/table/BaseTable.vue:152-159` | `items.length === 0 && noDataMessage` |
| 27 | Table row hover highlight + `aria-selected` | state | `components-next/table/BaseTableRow.vue:22-29` | `hoverable` default `true` |
| 28 | Table cell alignment start/center/end, RTL-aware padding | state | `components-next/table/BaseTableCell.vue:12-19` | `align` prop |
| 29 | Modal: Escape key closes | shortcut | `components/Modal.vue:50-58` | `show === true` |
| 30 | Modal: backdrop mousedown+mouseup closes | secondary | `components/Modal.vue:31-48` | `closeOnBackdropClick` default `true` |
| 31 | Modal: floating `X` close button top-end | secondary | `components/Modal.vue:89-96` | `showCloseButton` default `true` |
| 32 | Modal header: title, content, content-value, optional image | state | `components/ModalHeader.vue:26-49` | per modal |
| 33 | Plain delete modal: reject (faded slate) + confirm (ruby) | destructive | `components/widgets/modal/DeleteModal.vue:18-29` | used by agents, labels, canned, macros |
| 34 | Type-the-name delete modal: text input must equal `confirmValue` (whitespace-trimmed) before confirm enables | destructive | `components/widgets/modal/ConfirmDeleteModal.vue:31-41,83-88` | used by attributes, teams, inboxes |
| 35 | Next-gen `Dialog`: native `<dialog>`, `::backdrop` blur, click-outside only when topmost, `type="alert"` → ruby confirm | destructive | `components-next/dialog/Dialog.vue:101-108,117-176` | used by agent bots |
| 36 | Next-gen `Dialog` width/position variants (`3xl`…`sm`, `center`/`top`) | state | `components-next/dialog/Dialog.vue:47-60,71-86` | props |
| 37 | Toast alerts for every create/update/delete success and failure | status | `useAlert` calls, e.g. `agents/Index.vue:106`, `labels/Index.vue:70,74`, `inbox/Index.vue:74,76` | always |
| 38 | Sidebar entries for all 8 features under "Settings" | navigation | `components-next/sidebar/Sidebar.vue:725-822` | sidebar visibility |
| 39 | Sidebar `activeOn` arrays keep Teams/Inboxes highlighted across their wizard routes | navigation | `components-next/sidebar/Sidebar.vue:735-744,770-778` | always |
| 40 | `Alt+S` keyboard shortcut → agents list | shortcut | `components-next/sidebar/useSidebarKeyboardShortcuts.js:33-35` | global |
| 41 | `Cmd/Ctrl+/` opens the shortcut modal | shortcut | `components-next/sidebar/useSidebarKeyboardShortcuts.js:18-20` | global |
| 42 | Command bar "go to" entries for agents, teams, inboxes, labels, attributes, macros, canned | shortcut | `dashboard/composables/commands/useGoToCommandHotKeys.js:147-224` | route permissions/flags. **No entry for agent bots** |
| 43 | `settings_inbox_list` and `agent_list` bypass the upgrade paywall page | state | `dashboard/helper/routeHelpers.js:151-158` | always |

### 2.2 Agents — `agents/Index.vue`

| # | Feature | Kind | Where it lives today | Gating |
|---|---|---|---|---|
| 44 | Header: title `AGENT_MGMT.HEADER`, description, learn-more (`feature-name="agents"`) | state | `agents/Index.vue:155-161` | — |
| 45 | Search over `name` + `email` via `picoSearch` | filter | `agents/Index.vue:43-47,160` | — |
| 46 | Count chip `AGENT_MGMT.COUNT` | status | `agents/Index.vue:163-167` | `agentList.length` |
| 47 | "Add agent" primary button (`HEADER_BTN_TXT`), size `sm` | primary | `agents/Index.vue:168-174` | — |
| 48 | Row avatar with availability status ring, `hide-offline-status`, size 40 | state | `agents/Index.vue:191-197` | — |
| 49 | Row: agent name, `capitalize`, `text-heading-3` | state | `agents/Index.vue:199-201` | — |
| 50 | Row: email | state | `agents/Index.vue:203-205` | — |
| 51 | Row: role name — built-in role i18n label, or the custom role's name | state | `agents/Index.vue:61-67,214` | — |
| 52 | Row: hover card listing the custom role's permissions (`w-[300px]`, `backdrop-blur`) | contextual link | `agents/Index.vue:208-239` | `agent.custom_role_id` only; **hover-only, `group-hover:block`** |
| 53 | Row: "Verified" status text | status | `agents/Index.vue:241-246` | `agent.confirmed` |
| 54 | Row: "Verification Pending" status text | status | `agents/Index.vue:247-252` | `!agent.confirmed` |
| 55 | Row: pipe dividers between email / role / verification | state | `agents/Index.vue:206,240` | — |
| 56 | Row action: Edit (icon `i-woot-edit-pen`, tooltip + aria-label) | contextual | `agents/Index.vue:257-265` | `showEditAction` = `currentUserId !== agent.id` (`:83-85`) |
| 57 | Row action: Delete (icon `i-woot-bin`, ruby hover) | destructive | `agents/Index.vue:266-276` | `showDeleteAction`: never self; always for unconfirmed; for admins only when more than one verified admin exists (`:87-100`) |
| 58 | Per-row delete spinner | loading | `agents/Index.vue:274` (`loading[agent.id]`) | set in `confirmDeletion` (`:140-144`) |
| 59 | Empty state `AGENT_MGMT.LIST.404` | empty | `agents/Index.vue:151-152` | `!agentList.length` |
| 60 | Search-empty state `AGENT_MGMT.NO_RESULTS` | empty | `agents/Index.vue:178-183` | `!filteredAgentList.length && searchQuery` |
| 61 | Loading state `AGENT_MGMT.LOADING` | loading | `agents/Index.vue:149-150` | `uiFlags.isFetching` |
| 62 | Add-agent modal: Name (raw `<input>`), Role (`<select>` built-ins + custom roles), Email (`<input type=email>`) | primary | `agents/AddAgent.vue:111-148` | — |
| 63 | Add-agent validation: name required, email required+format, role required | state | `agents/AddAgent.vue:19-29` | — |
| 64 | Add-agent submit disabled + spinner while `agents/getUIFlags.isCreating` | loading | `agents/AddAgent.vue:158-163` | — |
| 65 | Add-agent duplicate-email error path (422 without `base` attribute → `EXIST_MESSAGE`) | error | `agents/AddAgent.vue:83-101` | HTTP 422 |
| 66 | Edit-agent modal title `EDIT.TITLE - <name>` | state | `agents/EditAgent.vue:67-69,158` | — |
| 67 | Edit-agent fields: Name, Role, Availability (`<select>` online/busy/offline, current value disabled) | contextual | `agents/EditAgent.vue:160-205`, options at `:112-118` | — |
| 68 | Edit-agent: "Reset password" ghost button with lock icon | contextual | `agents/EditAgent.vue:209-217`, handler `:146-153` | `provider !== 'saml'` |
| 69 | Edit-agent: setting a built-in role clears `custom_role_id` | state | `agents/EditAgent.vue:131-136` | — |
| 70 | Delete confirm: title, message, `"Yes, Delete <name>"` / `"No, Keep <name>"` | destructive | `agents/Index.vue:300-309`, texts `:31-39` | — |
| 71 | Custom roles fetched on mount for role labels | state | `agents/Index.vue:53-56` | — |

### 2.3 Teams — `teams/Index.vue` + wizard

| # | Feature | Kind | Where it lives today | Gating |
|---|---|---|---|---|
| 72 | Header: title, description, learn-more (`feature-name="team_management"`) | state | `teams/Index.vue:92-97` | — |
| 73 | Search over `name` + `description` | filter | `teams/Index.vue:26-30,96` | — |
| 74 | Count chip `TEAMS_SETTINGS.COUNT` | status | `teams/Index.vue:99-103` | `teamsList.length` |
| 75 | "New team" button inside a `router-link` to `settings_teams_new` | primary | `teams/Index.vue:104-108` | `v-if="isAdmin"` on the `router-link` |
| 76 | Row icon tile: emoji/icon via `EmojiIcon`, else `i-lucide-users-round` fallback | state | `teams/Index.vue:126-140` | `team.icon` |
| 77 | Row: team name `capitalize`, description | state | `teams/Index.vue:141-148` | — |
| 78 | Row action: Settings/Edit — `router-link` to `settings_teams_edit`, icon `i-woot-settings` | contextual | `teams/Index.vue:151-167` | `v-if="isAdmin"` on the inner `Button` only |
| 79 | Row action: Delete icon with ruby hover + per-row spinner | destructive | `teams/Index.vue:169-179` | `v-if="isAdmin"` |
| 80 | Delete: type-the-team-name confirmation | destructive | `teams/Index.vue:184-195`, texts `:64-80` | — |
| 81 | Empty state `TEAMS_SETTINGS.LIST.404` | empty | `teams/Index.vue:87-88` | `!teamsList.length` |
| 82 | Search-empty state `TEAMS_SETTINGS.NO_RESULTS` | empty | `teams/Index.vue:112-117` | `searchQuery` |
| 83 | Loading state `TEAMS_SETTINGS.LOADING` | loading | `teams/Index.vue:85-86` | `uiFlags.isFetching` |
| 84 | Create wizard: 3-step rail (`woot-wizard`) inside a bordered `lg:grid-cols-8` card | navigation | `teams/Create/Index.vue:26-36`, steps `:4-19` | — |
| 85 | Wizard rail hidden below `lg` (`hidden lg:block`) | mobile | `teams/Create/Index.vue:31` | `lg` breakpoint |
| 86 | Wizard step indicator: number → check mark once passed, active step tinted blue | status | `components/ui/Wizard.vue:42-63` | derived from `route.name` |
| 87 | Create step 1: `TeamForm` — name, description, emoji/icon picker, "allow auto assign" checkbox | primary | `teams/TeamForm.vue:97-178` | — |
| 88 | Emoji/icon picker in a `Popover`, lazily loaded, with colour change + remove | contextual | `teams/TeamForm.vue:110-148`, async import `:12-15` | — |
| 89 | Team form validation: title + description rules, inline error messages | error | `teams/TeamForm.vue:62-63,106-108,156-159` | — |
| 90 | Create step 1 → auto-advance to `settings_teams_add_agents` via `router.replace` | navigation | `teams/Create/CreateTeam.vue:24-30` | on success |
| 91 | Create-step error toast `TEAM_FORM.ERROR_MESSAGE` | error | `teams/Create/CreateTeam.vue:31-33` | — |
| 92 | Create step 2: `AgentSelector` table with select-all tri-state checkbox | bulk | `teams/AgentSelector.vue:84-94`, state `:38-46` | — |
| 93 | Per-agent checkbox rows with avatar + availability + email (`---` fallback) | contextual | `teams/AgentSelector.vue:97-131` | — |
| 94 | Sticky footer showing `SELECTED_COUNT` and the submit button | status | `teams/AgentSelector.vue:135-152` | — |
| 95 | Submit disabled until at least one agent selected | state | `teams/AgentSelector.vue:48,149` | — |
| 96 | "Select all agents" helper method on the create step | bulk | `teams/Create/AddAgents.vue:61-63` | **declared but never bound in the template** |
| 97 | Agent-selection validation message `ADD.AGENT_VALIDATION_ERROR` | error | `teams/Create/AddAgents.vue:99-103` | `v$.selectedAgents.$error` |
| 98 | Create step 3: `EmptyState` success screen + "go to teams list" button | state | `teams/FinishSetup.vue:13-29` | — |
| 99 | Edit wizard: same 3-step rail with `EDIT_FLOW` copy | navigation | `teams/Edit/Index.vue:4-23,29-40` | — |
| 100 | Edit step 1 prefills from `teams/getTeam`, spinner until loaded | loading | `teams/Edit/EditTeam.vue:22-32,66-73` | `id && !uiFlags.isFetching` |
| 101 | Edit step 2 preselects current members from `teamMembers/get` | state | `teams/Edit/EditAgents.vue:60-72` | — |
| 102 | Edit step 2 spinner while team members load | loading | `teams/Edit/EditAgents.vue:129-131` | `!showAgentsList` |
| 103 | Wizard sub-pages use `Wrapper` with `headerTitle: TEAMS_SETTINGS.HEADER`, icon `people-team`, back button | navigation | `teams/teams.routes.js:41-47` | — |

### 2.4 Inboxes — `inbox/Index.vue` + wizard + detail

| # | Feature | Kind | Where it lives today | Gating |
|---|---|---|---|---|
| 104 | Header: title, description, learn-more (`feature-name="inboxes"`) | state | `inbox/Index.vue:103-107` | — |
| 105 | Search over inbox name, channel and identifier via `searchInboxes` | filter | `inbox/Index.vue:45-49,106` | — |
| 106 | List sorted alphabetically by name (`localeCompare`) | state | `inbox/Index.vue:36-43` | — |
| 107 | Channel identifier derived per inbox (`getInboxIdentifier`) | state | `inbox/Index.vue:40` | — |
| 108 | Count chip `INBOX_MGMT.COUNT` | status | `inbox/Index.vue:109-113` | `inboxesList.length` |
| 109 | "New inbox" button in a `router-link` to `settings_inbox_new` | primary | `inbox/Index.vue:114-118` | `v-if="isAdmin"` on the `router-link` |
| 110 | Row tile: avatar when `avatar_url`, else `ChannelIcon` for the channel type | state | `inbox/Index.vue:135-151` | `inbox.avatar_url` |
| 111 | Row: inbox name truncated with `title` tooltip, `capitalize` | state | `inbox/Index.vue:153-158` | — |
| 112 | Row: `ChannelName` (channel type + medium + voice flag) | status | `inbox/Index.vue:162-167` | — |
| 113 | Row: identifier in a `<bdi dir="auto">` with `·` separator, `data-test-id="channel-identifier"` | state | `inbox/Index.vue:168-178` | `inbox.channel_identifier` |
| 114 | Row action: Settings — `router-link` to `settings_inbox_show`, icon `i-woot-settings` | contextual | `inbox/Index.vue:183-199` | `v-if="isAdmin"` on the inner `Button` only |
| 115 | Row action: Delete icon, ruby hover | destructive | `inbox/Index.vue:200-209` | `v-if="isAdmin"` |
| 116 | Delete: type-the-inbox-name confirmation | destructive | `inbox/Index.vue:215-226`, texts `:53-69` | — |
| 117 | Empty state `INBOX_MGMT.LIST.404` | empty | `inbox/Index.vue:96-97` | `!inboxesList.length` |
| 118 | Search-empty state `INBOX_MGMT.NO_RESULTS` | empty | `inbox/Index.vue:122-127` | `searchQuery` |
| 119 | Loading state — spinner with **no message** | loading | `inbox/Index.vue:98` (no `loading-message`) | `uiFlags.isFetching` |
| 120 | List refetched on `onActivated` (keep-alive re-entry), not `onMounted` | state | `inbox/Index.vue:32-34` | — |
| 121 | Create wizard: 4-step rail (Channel → Inbox → Agent → Finish) | navigation | `inbox/InboxChannels.vue:16-33,67-71` | — |
| 122 | Wizard title changes by step (`AUTH.TITLE` / `TITLE_NEXT` / `TITLE_FINISH`) | state | `inbox/InboxChannels.vue:43-51` | route name |
| 123 | Mobile-only page header above the wizard (`block lg:hidden`) | mobile | `inbox/InboxChannels.vue:63` | `< lg` |
| 124 | Wizard step bodies get `replaceInstallationName` applied for white-labelling | state | `inbox/InboxChannels.vue:53-58` | — |
| 125 | Channel picker grid: `xs:grid-cols-2 sm:grid-cols-3`, `max-w-3xl` | primary | `inbox/ChannelList.vue:122-133` | — |
| 126 | 12 base channels + conditional TikTok + Voice + WhatsApp Call | primary | `inbox/ChannelList.vue:23-110` | TikTok needs `window.chatwootConfig.tiktokAppId` (`:19-21`) |
| 127 | API channel title overridden by `globalConfig.apiChannelName` | state | `inbox/ChannelList.vue:58` | white-label config |
| 128 | TikTok tile shows an "access request" description on cloud without the feature | status | `inbox/ChannelList.vue:86-92` | cloud + feature off |
| 129 | Channel tile disabled when its feature flag is off | state | `components/widgets/ChannelItem.vue:32-73,123` | per-channel feature flags |
| 130 | "Coming soon" badge | status | `components/widgets/ChannelItem.vue:75-80` | `voice` and not active |
| 131 | "Beta" badge | status | `components/widgets/ChannelItem.vue:82-84` | tiktok, voice, whatsapp_call |
| 132 | Voice badge | status | `components/widgets/ChannelItem.vue:96-101` | voice/whatsapp_call + `channel_voice` |
| 133 | TikTok tile click opens the support widget instead of navigating | contextual | `components/widgets/ChannelItem.vue:103-112` | `canRequestTiktokAccess` |
| 134 | Channel form chosen at runtime by `:sub_page` via `ChannelFactory` | navigation | `inbox/ChannelFactory.vue:17-45` | `channelName` must be in the map |
| 135 | Wizard step 3: agent picker as a `TagInput` with dropdown + avatars | primary | `inbox/AddAgents.vue:109-117`, items `:44-53` | — |
| 136 | Step 3 validation message `AGENTS.VALIDATION_ERROR` | error | `inbox/AddAgents.vue:119-121` | `v$.selectedAgentIds.$error` |
| 137 | Step 4 Finish: `EmptyState` with channel-specific message | state | `inbox/FinishSetup.vue:91-109,192-196` | — |
| 138 | Finish: widget script in a `woot-code` copy block | contextual | `inbox/FinishSetup.vue:199-203` | `web_widget_script` |
| 139 | Finish: WhatsApp webhook URL + verification token code blocks | contextual | `inbox/FinishSetup.vue:204-222` | WhatsApp Cloud, non-embedded-signup (`:55-58`) |
| 140 | Finish: "Retry webhook" button for WhatsApp manual setup v2 | contextual | `inbox/FinishSetup.vue:223-234`, handler `:159-172` | `isWhatsAppManualSetup` |
| 141 | Finish: LINE callback URL code block | contextual | `inbox/FinishSetup.vue:236-242` | `isALineChannel` |
| 142 | Finish: Bandwidth SMS callback block | contextual | `inbox/FinishSetup.vue:243-254` | SMS and not Twilio (`:87-89`) |
| 143 | Finish: Twilio callback fallback block | contextual | `inbox/FinishSetup.vue:255-266` | Twilio and not voice-enabled (`:83-85`) |
| 144 | Finish: SMS QR code image | contextual | `inbox/FinishSetup.vue:267-281` | Twilio SMS, not voice, has phone number (`:75-81`) |
| 145 | Finish: WhatsApp QR code | contextual | `inbox/FinishSetup.vue:287-301` | WhatsApp + phone number (`:71-73`) |
| 146 | Finish: Messenger QR code | contextual | `inbox/FinishSetup.vue:302-316` | Facebook inbox + `page_id` |
| 147 | Finish: Telegram QR code | contextual | `inbox/FinishSetup.vue:317-332` | Telegram + `bot_name` |
| 148 | Finish: `EmailInboxFinish` block | contextual | `inbox/FinishSetup.vue:282-286` | email channel without provider |
| 149 | Finish: duplicate-Instagram-inbox banner | error | `inbox/FinishSetup.vue:188-191`, computed `:45-53` | matching Facebook inbox exists |
| 150 | Finish: "More settings" + "Take me there" buttons | navigation | `inbox/FinishSetup.vue:333-358` | — |
| 151 | Detail page uses `Wrapper` with `fullWidth`, no back button on the list route | navigation | `inbox/inbox.routes.js:40-48` | `name === 'settings_inbox_show'` |
| 152 | Detail header: `SettingIntroBanner` with inbox avatar, name (truncated + `title`), identifier in `<bdi>` | state | `inbox/Settings.vue:785-789`, `components/widgets/SettingIntroBanner.vue:18-37` | — |
| 153 | Detail tab strip: legacy `woot-tabs` / `woot-tabs-item`, `is-compact`, `show-badge="false"` | tab | `inbox/Settings.vue:790-804` | — |
| 154 | Tab strip auto-shows left/right scroll chevrons when it overflows | mobile | `components/ui/Tabs/Tabs.vue:38-54,72-94` | measured overflow |
| 155 | Tab: Settings (always) | tab | `inbox/Settings.vue:170-173` | — |
| 156 | Tab: Collaborators (always) | tab | `inbox/Settings.vue:174-177` | — |
| 157 | Tab: Business hours (always) | tab | `inbox/Settings.vue:200-204` | — |
| 158 | Tab: CSAT (always) | tab | `inbox/Settings.vue:205-208` | — |
| 159 | Tab: Pre-chat form | tab | `inbox/Settings.vue:211-219` | `isAWebWidgetInbox` |
| 160 | Tab: Configuration | tab | `inbox/Settings.vue:221-235` | Twilio, LINE, API, email w/o provider, WhatsApp Cloud, or web widget |
| 161 | Tab: Bot configuration | tab | `inbox/Settings.vue:237-247` | `AGENT_BOTS` feature flag on the account |
| 162 | Tab: Account health (WhatsApp) | tab | `inbox/Settings.vue:248-257` | `shouldShowWhatsAppConfiguration` |
| 163 | Tab: Account health (Twilio) | tab | `inbox/Settings.vue:259-267` | Twilio + `medium === 'sms'` (`:146-148`) |
| 164 | Tab: Voice | tab | `inbox/Settings.vue:269-284` | Twilio + phone number + sms + `CHANNEL_VOICE` flag |
| 165 | Tab: Calls | tab | `inbox/Settings.vue:286-299` | WhatsApp Cloud + `CHANNEL_VOICE` flag |
| 166 | Active tab reflected in the URL via `history.replaceState` (no re-render) | navigation | `inbox/Settings.vue:656-671` | — |
| 167 | Tab restored from the `:tab?` route param on load | navigation | `inbox/Settings.vue:673-681` | — |
| 168 | Per-tab content max-width switching (`max-w-4xl` / `max-w-7xl`) | state | `inbox/Settings.vue:714-722` | tab key + web-widget |
| 169 | Reauthorize banners: Microsoft, Facebook, Google, Instagram, TikTok, WhatsApp | error | `inbox/Settings.vue:807-840` | per-channel `*Unauthorized` computed |
| 170 | Duplicate-Instagram-inbox banner | error | `inbox/Settings.vue:841-846` | `hasDuplicateInstagramInbox` |
| 171 | Instagram restriction amber banner + "status" external link | error | `inbox/Settings.vue:847-867` | `showInstagramRestrictionSettingsBanner` |
| 172 | WhatsApp manual-migration banner + dialog | contextual | `inbox/Settings.vue:868-874,1459-1465` | `showWhatsAppManualMigration` |
| 173 | Settings tab: inbox avatar upload + delete | primary | `inbox/Settings.vue:896-905`, handler `:732-747` | — |
| 174 | Settings tab: sender-name section with "set business name" inline input + Save | contextual | `inbox/Settings.vue:1018-1060` | web widget or email channel |
| 175 | Settings tab: `SenderNameExamplePreview` | state | `inbox/Settings.vue:1062-1068` | same |
| 176 | Settings tab: webhook/HMAC token with copy action | contextual | `inbox/Settings.vue:955-958`, handler `:520-522` | per channel |
| 177 | Settings tab: `Update` submit button (two variants — API inbox validates only `webhookUrl`) | primary | `inbox/Settings.vue:1363-1380` | `v$.$invalid` / `v$.webhookUrl.$invalid` |
| 178 | Settings tab: widget live preview panel, sticky, `min-h-[45rem]` | state | `inbox/Settings.vue:1383-1402` | `isAWebWidgetInbox` |
| 179 | Widget bubble settings persisted to `LocalStorage` on update | state | `inbox/Settings.vue:682-689` | — |
| 180 | Email continuity toggle with disabled explanation copy | state | `inbox/Settings.vue:1350-1360`, copy `:134-144` | `showContinuityToggle` (`:122-125`) |
| 181 | Collaborators tab: agent `TagInput` + Update | primary | `inbox/settingsPage/CollaboratorsPage.vue:365-397` | — |
| 182 | Collaborators tab: auto-assignment toggle, max-assignment limit, assignment-policy link/create/delete, enterprise upgrade CTA | contextual | `inbox/settingsPage/CollaboratorsPage.vue:402-692` | `isEnterprise`, policy availability |
| 183 | Account health tab: register-webhook action + structured provider error | error | `inbox/Settings.vue:1441-1449`, handler `:624-641` | — |
| 184 | Account health: "go to configuration" jumps to the Configuration tab | contextual link | `inbox/Settings.vue:616-622` | configuration tab exists |
| 185 | Detail page full-page spinner while the inbox loads | loading | `inbox/Settings.vue:775-781` | `uiFlags.isFetching` |
| 186 | **No delete action on the inbox detail page** — delete lives only on the list row | destructive | only `inbox/Index.vue:200-209` | — |

### 2.5 Labels — `labels/Index.vue`

| # | Feature | Kind | Where it lives today | Gating |
|---|---|---|---|---|
| 187 | Header: title, description, learn-more (`feature-name="labels"`) | state | `labels/Index.vue:110-114` | — |
| 188 | Search over `title` (weight 4) + `description` | filter | `labels/Index.vue:32-39,113` | — |
| 189 | Count chip `LABEL_MGMT.COUNT` | status | `labels/Index.vue:116-120` | `records.length` |
| 190 | "Add label" primary button | primary | `labels/Index.vue:121-127` | — |
| 191 | Table columns: Name, Description, Color, Action | state | `labels/Index.vue:86-93` | — |
| 192 | Colour cell: swatch square with inline `backgroundColor` + hex text | state | `labels/Index.vue:153-163` | — |
| 193 | Row action: Edit (tooltip `FORM.EDIT`) | contextual | `labels/Index.vue:167-175` | — |
| 194 | Row action: Delete (tooltip `FORM.DELETE`, ruby hover) | destructive | `labels/Index.vue:176-185` | — |
| 195 | Per-row spinner bound to `loading[label.id]` on **both** buttons | loading | `labels/Index.vue:173,184` | set in `confirmDeletion` (`:80-84`) |
| 196 | Empty state `LABEL_MGMT.LIST.404` (via `SettingsLayout`) | empty | `labels/Index.vue:104-105` | `!records.length` |
| 197 | Table-level `no-data-message` switching 404 / NO_RESULTS | empty | `labels/Index.vue:134-136` | `items.length === 0` |
| 198 | Loading state `LABEL_MGMT.LOADING` | loading | `labels/Index.vue:102-103` | `uiFlags.isFetching` |
| 199 | Records fetched in `onBeforeMount` (only page that does) | state | `labels/Index.vue:95-97` | — |
| 200 | Add-label modal: Name (forced lowercase via scoped CSS), Description, colour picker, "show on sidebar" checkbox | primary | `labels/AddLabel.vue:77-111`, CSS `:132-139` | — |
| 201 | Add-label: random initial colour | state | `labels/AddLabel.vue:42-45`, `dashboard/helper/labelColor` | on mount |
| 202 | Add-label: `prefillTitle` prop lowercased into the field | state | `labels/AddLabel.vue:14-19,44` | caller-supplied |
| 203 | Add-label: title validation with a dedicated error-message resolver | error | `labels/AddLabel.vue:37-41`, `labels/validations.js` | — |
| 204 | Add-label: `data-testid` hooks (`label-title`, `label-description`, `label-submit`) | state | `labels/AddLabel.vue:84,95,122` | — |
| 205 | Add-label submit disabled + spinner on `uiFlags.isCreating` | loading | `labels/AddLabel.vue:124-125` | — |
| 206 | Add-label server error message surfaced verbatim when present | error | `labels/AddLabel.vue:60-64` | `error.message` |
| 207 | Edit-label modal title `EDIT.TITLE - <title>` | state | `labels/EditLabel.vue:36-40,82` | — |
| 208 | Edit-label closes after a 10 ms `setTimeout` | state | `labels/EditLabel.vue:70` | on success |
| 209 | Delete: plain confirm, `"Yes, Delete "` / `"No, Keep "` | destructive | `labels/Index.vue:202-211` | — |
| 210 | Delete error message surfaced verbatim when present | error | `labels/Index.vue:71-74` | `error.message` |

### 2.6 Custom attributes — `attributes/Index.vue`

| # | Feature | Kind | Where it lives today | Gating |
|---|---|---|---|---|
| 211 | Header: title, description, learn-more (`feature-name="custom_attributes"`) | state | `attributes/Index.vue:171-175` | — |
| 212 | `TabBar` with Conversation / Contact tabs (segmented pill control) | tab | `attributes/Index.vue:182-188`, tabs `:52-67` | — |
| 213 | Switching tabs clears the search query | filter | `attributes/Index.vue:81-84` | — |
| 214 | Attribute model derived from the tab index | state | `attributes/Index.vue:73-79` | — |
| 215 | Search over display name, key and description | filter | `attributes/Index.vue:152-160,174` | — |
| 216 | Count chip `ATTRIBUTES_MGMT.COUNT` (truncating) | status | `attributes/Index.vue:177-181` | `attributes.length` |
| 217 | "Add attribute" primary button | primary | `attributes/Index.vue:189-195` | — |
| 218 | Row: type icon tile mapped from the attribute type | state | `components-next/ConversationWorkflow/AttributeListItem.vue:22-34,41-45` | — |
| 219 | Row: display name + type `Label` chip | state | `.../AttributeListItem.vue:48-52` | — |
| 220 | Row: key with key icon, plus description after a divider | state | `.../AttributeListItem.vue:60-74` | description present |
| 221 | Badge: "pre-chat" when the key appears in any inbox pre-chat form | status | `attributes/Index.vue:112-127` | computed over `inboxes/getInboxes` |
| 222 | Badge: "resolution" when the key is in `conversation_required_attributes` | status | `attributes/Index.vue:129-137` | conversation attributes only |
| 223 | Row action: Edit | contextual | `.../AttributeListItem.vue:79-85` | — |
| 224 | Row action: Delete (ruby hover) | destructive | `.../AttributeListItem.vue:86-93` | — |
| 225 | Empty state `LIST.EMPTY_RESULT.404` rendered **inside the body**, not via `SettingsLayout` | empty | `attributes/Index.vue:219-224` | no attributes and no query |
| 226 | Search-empty state `ATTRIBUTES_MGMT.NO_RESULTS` | empty | `attributes/Index.vue:200-205` | `searchQuery` |
| 227 | Loading state `ATTRIBUTES_MGMT.LOADING` | loading | `attributes/Index.vue:165-166` | `uiFlags.isFetching` |
| 228 | Add modal renders its **own** `woot-modal` | primary | `attributes/AddAttribute.vue:164` | `v-if="showAddPopup"` at `attributes/Index.vue:227-232` |
| 229 | Add form: model `<select>` prefilled from the active tab | primary | `attributes/AddAttribute.vue:170-180`, default `:40` | — |
| 230 | Add form: display name auto-slugs into the key field | state | `attributes/AddAttribute.vue:123-125,192` | on name change |
| 231 | Add form: key field with "invalid key" vs "required" error branches | error | `attributes/AddAttribute.vue:85-90,195-203` | — |
| 232 | Add form: description `<textarea rows=3>` (required) | primary | `attributes/AddAttribute.vue:204-216` | — |
| 233 | Add form: type `<select>` — Text, Number, Link, Date, List, Checkbox | primary | `attributes/AddAttribute.vue:217-227`, `attributes/constants.js:6-13` | — |
| 234 | Add form: `TagInput` list values with its own invalid border + error label | primary | `attributes/AddAttribute.vue:228-251` | `attributeType === 6` |
| 235 | Changing type resets the list values and the touched flag | state | `attributes/AddAttribute.vue:115-120` | — |
| 236 | Add form: "enable regex" checkbox, then regex pattern + regex cue inputs | contextual | `attributes/AddAttribute.vue:252-275` | `attributeType === 0` |
| 237 | Regex pattern normalised before submit, cleared when regex disabled | state | `attributes/AddAttribute.vue:134-137,146` | — |
| 238 | Edit modal title `EDIT.TITLE - <display name>` | state | `attributes/EditAttribute.vue:77-81,162` | — |
| 239 | Edit: key field `readonly`, type `<select disabled>` | state | `attributes/EditAttribute.vue:185,203` | always |
| 240 | Edit: existing regex decoded back into pattern + enabled flag | state | `attributes/EditAttribute.vue:112-124` | `regex_pattern` present |
| 241 | Edit submit spinner driven by the page's `uiFlags.isUpdating` prop | loading | `attributes/Index.vue:236`, `attributes/EditAttribute.vue:272` | — |
| 242 | Delete: type-the-attribute-name confirmation, title/placeholder interpolate the name | destructive | `attributes/Index.vue:240-261` | — |
| 243 | Inboxes getter consumed purely to compute the pre-chat badge | contextual link | `attributes/Index.vue:26,112-120` | — |

### 2.7 Canned responses — `canned/Index.vue`

| # | Feature | Kind | Where it lives today | Gating |
|---|---|---|---|---|
| 244 | Header: title, description, learn-more (`feature-name="canned_responses"`) | state | `canned/Index.vue:151-155` | — |
| 245 | Search over `short_code` (weight 4) + `content` | filter | `canned/Index.vue:45-52,154` | — |
| 246 | Count chip `CANNED_MGMT.COUNT` | status | `canned/Index.vue:157-161` | `records.length` |
| 247 | "Add canned response" primary button | primary | `canned/Index.vue:162-168` | — |
| 248 | **Custom** sort toggle rendered into the first header cell (asc/desc woot icons) | filter | `canned/Index.vue:184-201`, handler `:69-71` | — |
| 249 | Sorted list from `getSortedCannedResponses(sortOrder)` | filter | `canned/Index.vue:41-43` | — |
| 250 | Table columns: Short code, Actions (only 2) | state | `canned/Index.vue:133-138` | — |
| 251 | Row: short code heading + plain-text preview of the rich content, `line-clamp-5` | state | `canned/Index.vue:213-222`, `getPlainText` at `:29` | — |
| 252 | Row action: Edit | contextual | `canned/Index.vue:226-233` | — |
| 253 | Row action: Delete (ruby hover) | destructive | `canned/Index.vue:234-243` | — |
| 254 | Empty state `CANNED_MGMT.LIST.404` | empty | `canned/Index.vue:145-146` | `!records.length` |
| 255 | Table `no-data-message` three-way expression (404 / NO_RESULTS / empty string) | empty | `canned/Index.vue:176-182` | — |
| 256 | Loading state `CANNED_MGMT.LOADING` keyed off `uiFlags.fetchingList` | loading | `canned/Index.vue:143-144` | — |
| 257 | Fetch failures swallowed silently (no toast, no error state) | error | `canned/Index.vue:73-79` | always |
| 258 | Add form: short code `<input>` (min length 2) + rich `WootMessageEditor` | primary | `canned/AddCanned.vue:92-120`, rules `:41-49` | — |
| 259 | Editor configured `channel-type="Context::Default"`, `enable-variables`, canned responses disabled inside itself | primary | `canned/AddCanned.vue:109-118` | — |
| 260 | Editor menubar hidden and min-height 12.5rem via scoped CSS | state | `canned/AddCanned.vue:145-153` | — |
| 261 | Add submit disabled + spinner on local `addCanned.showLoading` | loading | `canned/AddCanned.vue:129-138` | — |
| 262 | Form reset after a successful create | state | `canned/AddCanned.vue:51-56,70` | — |
| 263 | Edit modal title `EDIT.TITLE - <short code>` | state | `canned/EditCanned.vue:45-49,94` | — |
| 264 | Edit closes after a 10 ms `setTimeout` | state | `canned/EditCanned.vue:76-78` | on success |
| 265 | Delete: plain confirm with `"Yes, Delete <short code>"` / `"No, Keep <short code>"` | destructive | `canned/Index.vue:265-274`, texts `:55-67` | — |
| 266 | Reachable by agents and conversation-permission custom roles | state | `canned/canned.routes.js:27` | route permissions |

### 2.8 Macros — `macros/Index.vue` + `MacroEditor`

| # | Feature | Kind | Where it lives today | Gating |
|---|---|---|---|---|
| 267 | Header: title, description, learn-more (`feature-name="macros"`) | state | `macros/Index.vue:83-87` | — |
| 268 | Search over `name` only | filter | `macros/Index.vue:26-30,86` | — |
| 269 | Count chip `MACROS.COUNT` | status | `macros/Index.vue:89-93` | `records.length` |
| 270 | "New macro" button in a `router-link` to `macros_new` | primary | `macros/Index.vue:94-98` | — |
| 271 | Table columns: Name, Created by, Last updated by, Visibility, Actions | state | `macros/Index.vue:61-69` | — |
| 272 | Row: created-by avatar + name, `--` fallback | state | `macros/MacrosTableRow.vue:58-71`, name `:22-25` | `macro.created_by` |
| 273 | Row: updated-by avatar + name, `--` fallback | state | `macros/MacrosTableRow.vue:73-86` | `macro.updated_by` |
| 274 | Row: visibility label (Public/global vs Personal) | status | `macros/MacrosTableRow.vue:88-92`, label `:32-38` | — |
| 275 | Row action: Edit — `router-link` to `macros_edit`; tooltip flips to "View" when read-only | contextual | `macros/MacrosTableRow.vue:96-108`, tooltip `:44-46` | always visible |
| 276 | Row action: Delete | destructive | `macros/MacrosTableRow.vue:109-118` | `canManageMacro` = admin **or** non-global macro (`:40-42`) |
| 277 | `canManagePublicMacros` passed down from `useAdmin` | state | `macros/Index.vue:17,114` | — |
| 278 | Empty state `MACROS.LIST.404` | empty | `macros/Index.vue:74-75` | `!records.length` |
| 279 | Table `no-data-message` switching 404 / NO_RESULTS | empty | `macros/Index.vue:105-107` | — |
| 280 | Loading state `MACROS.LOADING` | loading | `macros/Index.vue:76-77` | `uiFlags.isFetching` |
| 281 | Delete confirm (plain) — title borrowed from `LABEL_MGMT.DELETE.CONFIRM.TITLE` | destructive | `macros/Index.vue:119-128` | — |
| 282 | Editor page shell: `Wrapper` with `MACROS.HEADER`, icon `flash-settings`, back button | navigation | `macros/macros.routes.js:33-39` | — |
| 283 | Editor page spinner `MACROS.EDITOR.LOADING` | loading | `macros/MacroEditor.vue:138-141` | `uiFlags.isFetchingItem` |
| 284 | Create mode seeds one `assign_team` action and visibility `global` for admins / `personal` otherwise | state | `macros/MacroEditor.vue:89-101` | `isAdmin` |
| 285 | Edit mode fetches the macro and hydrates dropdown params to objects | state | `macros/MacroEditor.vue:51-87` | `route.params.macroId` |
| 286 | Agents, teams and labels prefetched for the action dropdowns | contextual link | `macros/MacroEditor.vue:44-49` | — |
| 287 | Action types provided to descendants with icons via `provide` | state | `macros/MacroEditor.vue:28-36` | — |
| 288 | Read-only mode for global macros when the user is not an admin | state | `macros/MacroEditor.vue:40-42,117`, applied `MacroForm.vue:123` (`:inert`, `opacity-75`) | — |
| 289 | Save navigates back to `macros_wrapper` and toasts | navigation | `macros/MacroEditor.vue:128-129` | on success |
| 290 | Save error toast `MACROS.ERROR` | error | `macros/MacroEditor.vue:130-132` | — |
| 291 | Canvas: dotted radial-gradient background (light + dark variants) | state | `macros/MacroForm.vue:121,148-163` | — |
| 292 | Canvas: "Start flow" and "End flow" chips | state | `macros/MacroNodes.vue:48-56,102-110` | — |
| 293 | Canvas: drag-reorder actions (`vuedraggable`, handle `.macros__node-drag-handle`) | contextual | `macros/MacroNodes.vue:57-87` | — |
| 294 | Canvas: dashed connector lines between nodes | state | `macros/MacroNodes.vue:119-132` | — |
| 295 | Canvas: "Add action" teal button with plus icon | primary | `macros/MacroNodes.vue:88-101` | — |
| 296 | Per-node delete and reset-params actions | destructive | `macros/MacroForm.vue:89-94,104-109`, wired `MacroNodes.vue:82-83` | — |
| 297 | `single-node` flag passed to the node (last action cannot be removed) | state | `macros/MacroNodes.vue:81` | `actionData.length === 1` |
| 298 | Action-level validation via `validateActions`, errors keyed `action_<i>` | error | `macros/MacroForm.vue:96-97`, consumed `MacroNodes.vue:73` | on submit |
| 299 | Validation reset on route change | state | `macros/MacroForm.vue:47-53,110-113` | — |
| 300 | Properties panel: macro name input with required error | primary | `macros/MacroProperties.vue:76-84` | — |
| 301 | Properties panel: visibility as two selectable cards with check icons | primary | `macros/MacroProperties.vue:91-138` | — |
| 302 | Public-visibility card disabled for non-admins with explanatory copy and `aria-describedby` | state | `macros/MacroProperties.vue:31-48,95-98` | `!canManagePublicMacros` |
| 303 | Properties panel: "Actions run in order" info box | state | `macros/MacroProperties.vue:140-150` | — |
| 304 | Properties panel: full-width Save button, disabled when read-only | primary | `macros/MacroProperties.vue:152-161` | `readOnly` |
| 305 | Editor layout stacks below `lg` (`flex-col lg:flex-row`, properties `lg:w-1/3`) | mobile | `macros/MacroForm.vue:119,134` | `lg` breakpoint |
| 306 | Reachable by agents and conversation-permission custom roles | state | `macros/macros.routes.js:25,47,56` | route permissions |

### 2.9 Agent bots — `agentBots/Index.vue`

| # | Feature | Kind | Where it lives today | Gating |
|---|---|---|---|---|
| 307 | Header: title, description, learn-more (`feature-name="agent_bots"`) | state | `agentBots/Index.vue:108-112` | — |
| 308 | Flow-type bots filtered out of the list (managed in the Flow Builder) | state | `agentBots/Index.vue:28-32` | `bot.bot_type !== 'flow'` |
| 309 | Search over `name` + `description` | filter | `agentBots/Index.vue:52-56,111` | — |
| 310 | Count chip `AGENT_BOTS.COUNT` | status | `agentBots/Index.vue:114-118` | `agentBots.length` |
| 311 | "Add bot" primary button | primary | `agentBots/Index.vue:119-125` | — |
| 312 | Table columns: Details, URL, Actions | state | `agentBots/Index.vue:42-48` | — |
| 313 | Row: bot avatar (40) + name + description, truncating | state | `agentBots/Index.vue:139-164` | — |
| 314 | Row: "global bot" badge | status | `agentBots/Index.vue:152-157` | `bot.system_bot` |
| 315 | Row: webhook URL, falling back to `bot_config.webhook_url` | state | `agentBots/Index.vue:166-170` | — |
| 316 | Row action: Edit | contextual | `agentBots/Index.vue:174-183` | `!bot.system_bot` |
| 317 | Row action: Delete (ruby hover) | destructive | `agentBots/Index.vue:184-194` | `!bot.system_bot` |
| 318 | Per-row spinner bound to `loading[bot.id]` on **both** buttons | loading | `agentBots/Index.vue:181,192` | — |
| 319 | Empty state `AGENT_BOTS.LIST.404` | empty | `agentBots/Index.vue:102-103` | `!agentBots.length` |
| 320 | Table `no-data-message` switching 404 / NO_RESULTS | empty | `agentBots/Index.vue:132-134` | — |
| 321 | Loading state `AGENT_BOTS.LIST.LOADING` | loading | `agentBots/Index.vue:100-101` | `uiFlags.isFetching` |
| 322 | Create/edit in a next-gen `Dialog`, opened imperatively through `dialogRef` | primary | `agentBots/Index.vue:58-68,203-207`, exposed `components/AgentBotModal.vue:288` | — |
| 323 | Dialog title/confirm label switch on `create` vs `edit` | state | `components/AgentBotModal.vue:80-101` | `type` prop |
| 324 | Form: avatar with upload + delete, bot icon placeholder | primary | `components/AgentBotModal.vue:306-318`, handlers `:129-151` | — |
| 325 | Avatar delete calls the API for a saved bot, otherwise clears local state only | state | `components/AgentBotModal.vue:134-151` | `selectedBot.id` |
| 326 | Form: Name (next-gen `Input`, required, i18n error) | primary | `components/AgentBotModal.vue:321-329`, rule `:54-59` | — |
| 327 | Form: Description (next-gen `TextArea`) | primary | `components/AgentBotModal.vue:331-336` | — |
| 328 | Form: Webhook URL (required + URL format, i18n errors) | primary | `components/AgentBotModal.vue:338-346`, rules `:60-69` | — |
| 329 | After create, the dialog switches to an access-token/secret reveal screen | status | `components/AgentBotModal.vue:184-199,111-116` | create returns `access_token` |
| 330 | Access token field with copy action + success toast | contextual | `components/AgentBotModal.vue:363-382`, handler `:238-241` | `showAccessTokenInput` |
| 331 | Access token reset action | destructive | `components/AgentBotModal.vue:370-375`, handler `:261-272` | edit mode |
| 332 | Bot secret field with copy + reset | contextual | `components/AgentBotModal.vue:349-361`, handlers `:243-259` | edit mode and secret present |
| 333 | Secret shown once after creation with explanatory copy, no reset | status | `components/AgentBotModal.vue:384-399` | create + secret |
| 334 | Submit short-circuits while the token screen is showing | state | `components/AgentBotModal.vue:153-156` | `showAccessToken` |
| 335 | Dialog cancel + submit buttons in a custom footer (default footer suppressed) | primary | `components/AgentBotModal.vue:296-297,401-417` | — |
| 336 | Form reinitialised from `selectedBot` on every change (deep, immediate watch) | state | `components/AgentBotModal.vue:213-236,286` | — |
| 337 | Delete confirm via `Dialog type="alert"` with the bot name interpolated, loading from `uiFlags.isDeleting` | destructive | `agentBots/Index.vue:209-220` | — |
| 338 | `bot_type: 'webhook'` hard-coded on submit | state | `components/AgentBotModal.vue:158-164` | — |

**Total inventoried: 338 rows.**

---

## 3. Visual audit

### 3.1 Hierarchy

**V1 — Three page shells with three different content widths, reachable by the same sidebar group (high).**
List pages are clamped to `max-w-5xl` (`settings/SettingsWrapper.vue:25`), wizard and macro-editor
sub-pages to `max-w-7xl` (`settings/Wrapper.vue:28`, `teams/Create/Index.vue:26`,
`macros/MacroEditor.vue:137`), and the inbox detail page recomputes its own width per tab between
`max-w-4xl` and `max-w-7xl` (`inbox/Settings.vue:714-722`). Navigating Labels → Macros → "New
macro" shifts the content column twice.

**V2 — Two unrelated page-title treatments (high).**
List pages render `h1.text-heading-1` inside `BaseSettingsHeader`
(`settings/components/BaseSettingsHeader.vue:56-58`), while sub-pages render
`h1 > span.text-xl.font-medium` inside a fixed `h-20` bar
(`settings/SettingsHeader.vue:46-58`), and the inbox detail page renders a third variant,
`h2.text-2xl.font-medium` (`components/widgets/SettingIntroBanner.vue:21-25`). The same object
("Teams") is titled three different ways across its own list → wizard flow.

**V3 — Row title level is inconsistent across the eight pages (medium).**
`text-heading-3` on an `h4` for attributes (`.../AttributeListItem.vue:48`), `text-heading-3` on a
`span` for agents (`agents/Index.vue:199`), teams (`teams/Index.vue:142`), inboxes
(`inbox/Index.vue:155`) and canned (`canned/Index.vue:215`), but plain `text-body-main` for labels
(`labels/Index.vue:142`), macros (`macros/MacrosTableRow.vue:53`) and agent bots
(`agentBots/Index.vue:149`). Three list pages give the record's name no more weight than its
metadata.

**V4 — Macro properties panel competes with the canvas for the primary action (medium).**
The only Save for a macro is a full-width button at the bottom of the right-hand properties card
(`macros/MacroProperties.vue:152-161`), while the visually dominant element is the teal "Add action"
button in the middle of the dotted canvas (`macros/MacroNodes.vue:88-101`).

### 3.2 Density and spacing

**V5 — Row vertical rhythm differs between the hand-rolled lists and the tables (medium).**
Hand-rolled rows use `py-4` (`agents/Index.vue:188`, `teams/Index.vue:123`, `inbox/Index.vue:132`,
`.../AttributeListItem.vue:38`); table rows use `py-3` (`components-next/table/BaseTableCell.vue:13`)
under a `py-4` header (`components-next/table/BaseTable.vue:98`). Same information density, two
different row heights.

**V6 — Row action gap is 3 everywhere, but the header action gap is also 3 while the header/body gap is 4 (low).**
`gap-3` for row actions (`labels/Index.vue:166`, `agents/Index.vue:256`,
`agentBots/Index.vue:173`), `gap-3` for the header's action cluster
(`settings/components/BaseSettingsHeader.vue:120`), `gap-4` for the layout's header↔body gap
(`settings/SettingsLayout.vue:23`), `gap-1.5` / `gap-2` / `gap-4` inside rows
(`agents/Index.vue:190,198,202`). No single spacing step governs the surface.

**V7 — Wizard step panes each pick their own padding (low).**
`p-6` (`teams/Create/CreateTeam.vue:40`, `inbox/AddAgents.vue:93`, `inbox/FinishSetup.vue:187`,
`teams/FinishSetup.vue:14`), `p-8` (`teams/Edit/EditTeam.vue:60`), `px-8 pt-8`
(`teams/Create/AddAgents.vue:91`, `teams/Edit/EditAgents.vue:106`), `p-8`
(`inbox/ChannelList.vue:124`). Stepping through the team create wizard shifts the left edge of the
content between steps 1 and 2.

**V8 — `ml-[25%] w-[50%]` used four times to centre a block (medium).**
`inbox/FinishSetup.vue:206,236,245,257`. A percentage margin hack instead of a centred container;
it also breaks under RTL (see V22).

### 3.3 Inconsistent controls and duplicated patterns

**V9 — Three delete-confirmation mechanisms for eight sibling objects (high).**
Plain two-button confirm for agents (`agents/Index.vue:300-309`), labels
(`labels/Index.vue:202-211`), canned (`canned/Index.vue:265-274`) and macros
(`macros/Index.vue:119-128`); type-the-name confirm for attributes
(`attributes/Index.vue:240-261`), teams (`teams/Index.vue:184-195`) and inboxes
(`inbox/Index.vue:215-226`); next-gen `Dialog type="alert"` for agent bots
(`agentBots/Index.vue:209-220`). Destructiveness is not correlated with the friction applied —
deleting a label (which detaches from every conversation) is one click, deleting an attribute needs
the name typed.

**V10 — Four create-flow shapes (high).**
Legacy `woot-modal` wrapping a child (agents, labels, canned, attributes-edit); child that renders
its own modal (`attributes/AddAttribute.vue:164`, `canned/AddCanned.vue:85`,
`canned/EditCanned.vue:92`); next-gen `Dialog` (`agentBots/components/AgentBotModal.vue:292`);
full page / wizard (macros, teams, inboxes).

**V11 — Canned responses nest a modal inside a modal (high).**
`canned/Index.vue:251-253` wraps `AddCanned` in `woot-modal`, and `AddCanned`'s own root is another
`Modal` with `show: true` (`canned/AddCanned.vue:38,85`). Same for edit
(`canned/Index.vue:255-263` + `canned/EditCanned.vue:34,92`). `Modal.vue:104-105` renders
`.modal-mask` as a `fixed inset-0` backdrop, and `Modal.vue:89-96` adds an `X` button per modal, so
two stacked backdrops and two close buttons render, and Escape is handled by both listeners
(`Modal.vue:50-58`).

**V12 — `BaseTable` already provides sorting, skeleton loading, sticky headers and horizontal scroll; no page on this surface uses any of them (high).**
`sortableColumns` / `sortBy` / `sortOrder` / `@sort` (`components-next/table/BaseTable.vue:22-36,99-126`),
`loading` + `loadingRows` (`:18-21,42-46,134-148`), `stickyHeader` (`:37-41,92`), `scrollable`
(`:47-54,87`). Verified unused across `routes/dashboard/settings`. Canned responses instead
hand-rolls its own sort control in the `header-0` slot (`canned/Index.vue:184-201`) with
`i-woot-sort-ascending` / `i-woot-sort-descending` icons rather than the table's
`i-lucide-chevrons-up-down` family (`BaseTable.vue:59-63`), and without the `aria-sort` /
`TABLE.SORT_BY` affordances the table would have given it for free.

**V13 — Two different tab components on one surface (high).**
Attributes uses the next-gen segmented `TabBar` (`attributes/Index.vue:183-187`,
`components-next/tabbar/TabBar.vue:71-105`); the inbox detail page uses the legacy underlined
`woot-tabs` (`inbox/Settings.vue:790-804`, `components/ui/Tabs/Tabs.vue:66-95`). Completely
different visual language for the same interaction.

**V14 — Two form-field vocabularies, often in the same modal (high).**
Raw `<input>` / `<select>` / `<textarea>` with a `label.error` wrapper in `agents/AddAgent.vue:113-148`,
`agents/EditAgent.vue:160-205`, `canned/AddCanned.vue:93-101`, `attributes/AddAttribute.vue:170-227`;
deprecated `woot-input` (`components/widgets/forms/Input.vue:1-5,42-49` logs a deprecation warning
in dev) in `labels/AddLabel.vue:77-98`, `attributes/AddAttribute.vue:181-203`,
`macros/MacroProperties.vue:76-84`; `v3/components/Form/Input.vue` in `teams/TeamForm.vue:99-161`;
next-gen `Input`/`TextArea` in `agentBots/components/AgentBotModal.vue:321-336`. Four input
components for one surface, and `attributes/AddAttribute.vue` mixes two of them in a single form.

**V15 — Raw `<input type="checkbox">` with no design-system wrapper in three forms (medium).**
`labels/AddLabel.vue:107`, `labels/EditLabel.vue:111`, `teams/TeamForm.vue:163`,
`attributes/AddAttribute.vue:253-257`, `attributes/EditAttribute.vue:237-241` — while
`teams/AgentSelector.vue:87-92,101-104` uses the design-system `Checkbox` with indeterminate
support.

**V16 — The project forbids scoped CSS, yet nine files on this surface ship it (medium).**
`labels/AddLabel.vue:132-139`, `labels/EditLabel.vue:135-142`, `canned/AddCanned.vue:145-153`,
`canned/EditCanned.vue:149-157`, `attributes/AddAttribute.vue:296-301`,
`attributes/EditAttribute.vue:280-285`, `macros/MacroForm.vue:148-163`,
`macros/MacroProperties.vue:165-175`, `macros/MacroNodes.vue:114-143`. Two of these blocks
(`attributes/AddAttribute.vue:297-300`, `attributes/EditAttribute.vue:281-284`) define a
`.key-value` class that appears nowhere in either template — dead CSS.

**V17 — Three ways to express the same "icon-only action button" (low).**
`slate sm` attribute shorthands (`labels/Index.vue:170-172`), `variant`/`color` props
(`teams/TeamForm.vue:114-116`), and `blue solid` shorthands (`macros/MacroProperties.vue:154-155`).
`components-next/button/Button.vue:61-98` supports both forms, so both proliferate.

**V18 — Dead shared component and dead props (low).**
`settings/components/BaseSettingsListItem.vue` is not imported anywhere in `dashboard/`
(verified by grep). `macros/Index.vue:78` passes `feature-name="macros"` to `SettingsLayout`, which
declares no such prop (`settings/SettingsLayout.vue:2-19`). `teams/FinishSetup.vue:18` and
`inbox/FinishSetup.vue:195` pass `button-text` to `EmptyState`, which declares only `title` and
`message` (`components/widgets/EmptyState.vue:3-6`). `teams/Create/AddAgents.vue:61-63` defines
`selectAllAgents` which is never bound. `agents/Index.vue:275` calls
`openDeletePopup(agent, index)` against a one-parameter function (`:124-127`).

### 3.4 Unclear CTA

**V19 — The row "edit" affordance is a settings cog on three pages and a pencil on five (medium).**
`i-woot-settings` for teams (`teams/Index.vue:161`) and inboxes (`inbox/Index.vue:192`);
`i-woot-edit-pen` for agents (`agents/Index.vue:261`), labels (`labels/Index.vue:170`), canned
(`canned/Index.vue:229`), macros (`macros/MacrosTableRow.vue:102`), attributes
(`.../AttributeListItem.vue:80`) and agent bots (`agentBots/Index.vue:179`). The cog pages are the
ones that open a different kind of destination (wizard / tabbed page), but nothing in the UI says so.

**V20 — The macro edit button is a pencil even when the destination is read-only (medium).**
Only the tooltip changes to "View" (`macros/MacrosTableRow.vue:44-46`); the icon stays
`i-woot-edit-pen` (`:102`), and the read-only state is only discovered after landing on the editor
(`macros/MacroEditor.vue:40-42`, `MacroForm.vue:123`).

**V21 — Inbox delete exists only on the list row, not on the inbox detail page (medium).**
`inbox/Index.vue:200-209` is the only delete entry point; grep over the 1 470-line
`inbox/Settings.vue` finds no inbox-delete action (only `handleAvatarDelete` at `:732-747`). A user
who has drilled into an inbox to decommission it must navigate back out.

### 3.5 RTL behaviour

**V22 — `ml-[25%]` breaks the inbox finish screen under RTL (high).**
`inbox/FinishSetup.vue:206,236,245,257` use a physical left margin; under RTL the webhook, callback
and QR blocks shift to the wrong side instead of staying centred. The direction-aware form is
`ms-[25%]`.

**V23 — Physical margins in inbox sub-pages (medium).**
`inbox/settingsPage/ConfigurationPage.vue:439` and
`inbox/settingsPage/WhatsappBusinessManagementToken.vue:118` use `mr-2`;
`inbox/settingsPage/CollaboratorsPage.vue:680` uses `ml-13`.
`inbox/channels/Whatsapp.vue:234` and `inbox/channels/Tiktok.vue:83` use `text-left`;
`inbox/channels/Facebook.vue:275` uses `text-right`.

**V24 — Macro canvas connector lines are LTR-only in CSS (medium).**
`macros/MacroNodes.vue:126` draws the connector with `border-l` (physical left border) while
offsetting it with `ltr:ml-6 rtl:mr-6`; under RTL the dashed line renders on the wrong edge of the
node. `macros/MacroNodes.vue:136-139` positions `.drag-handle` with `left: -1.5rem` in raw CSS with
no RTL counterpart.

**V25 — Legacy tab scroll buttons always scroll in document direction (low).**
`components/ui/Tabs/Tabs.vue:44-54` adds or subtracts 100 from `scrollLeft` based on a
`'left'`/`'right'` label and renders `chevron-left` / `chevron-right` icons (`:77,93`) with no RTL
mirroring, so on the inbox detail page under RTL the chevrons point away from the direction they move.

**V26 — What is correct: most of the surface is direction-aware (positive).**
`BaseTableCell` (`components-next/table/BaseTableCell.vue:13`), `BaseTable`
(`components-next/table/BaseTable.vue:98,143`), row dividers and offsets
(`agents/Index.vue:217,224`, `labels/Index.vue:156`, `teams/Create/Index.vue:28`),
`SettingsHeader` (`settings/SettingsHeader.vue:51`), `BaseSettingsHeader`
(`settings/components/BaseSettingsHeader.vue:107,114,126`), `BaseSettingsListItem`
(`settings/components/BaseSettingsListItem.vue:46`) and the next-gen `Dialog`
(`components-next/TeleportWithDirection.vue` via `Dialog.vue:118`) all use logical utilities.
The inbox list even wraps its identifier in `<bdi dir="auto">` (`inbox/Index.vue:170-176`) so mixed
Arabic/Latin identifiers do not reorder.

### 3.6 Mobile behaviour

**V27 — Search is unavailable on phones on all eight pages (high).**
`settings/components/BaseSettingsHeader.vue:107` puts `hidden sm:flex` on the search `Input`, and
`:96-100` hides the whole left group below `sm` when there is no `tabs` slot. Every page here passes
`search-placeholder` and only attributes passes `tabs`, so below 640 px the sole way to find a
record is to scroll the full list. The `picoSearch` plumbing
(`agents/Index.vue:43-47`, `labels/Index.vue:32-39`, `attributes/Index.vue:152-160`,
`canned/Index.vue:45-52`, `macros/Index.vue:26-30`, `agentBots/Index.vue:52-56`,
`teams/Index.vue:26-30`, `inbox/Index.vue:45-49`) is built and then hidden.

**V28 — "Learn more" is unavailable on phones (medium).**
`settings/components/BaseSettingsHeader.vue:79` — `hidden ... sm:inline-flex`. The only in-product
path to the help article disappears on the device most likely to need it.

**V29 — Tables overflow horizontally on phones with no scroll container (high).**
`BaseTable` defaults `scrollable: false` (`components-next/table/BaseTable.vue:51-54`) and uses
`min-w-full table-auto` (`:88`). No page on this surface opts in, so the 5-column macros table
(`macros/Index.vue:61-69`), the 4-column labels table (`labels/Index.vue:86-93`) and the 3-column
agent-bots table (`agentBots/Index.vue:42-48`) push their trailing action column off-screen. The
`BaseTable` comment at `:47-50` records this as a deliberate deferral to a later responsive phase —
it is still the current behaviour.

**V30 — Hand-rolled rows never stack (medium).**
`agents/Index.vue:188`, `teams/Index.vue:123`, `inbox/Index.vue:132` and
`.../AttributeListItem.vue:39` all hard-code `flex-row` with no `sm:`/`md:` variant, so on a narrow
viewport the metadata line (email · role · verification, three items plus two dividers in
`agents/Index.vue:202-252`) is squeezed against the action buttons.

**V31 — Wizard progress rails vanish below `lg` (medium).**
`teams/Create/Index.vue:31`, `teams/Edit/Index.vue:35`, `inbox/InboxChannels.vue:68` —
`hidden lg:block`. The inbox wizard compensates with a mobile-only `PageHeader`
(`inbox/InboxChannels.vue:63`); the team wizard does not, so on a phone a user in step 2 of 3 sees
no indication of where they are.

**V32 — Agent role hover-card is unreachable without a pointer (medium).**
`agents/Index.vue:216-238` is shown only via `group-hover:block` on a `<span>` with
`cursor-pointer`. On touch there is no hover, and the card is `absolute ... top-14 md:top-12` with
`w-[300px]`, wider than a small viewport's remaining space.

**V33 — What is correct (positive).**
The header row wraps (`settings/components/BaseSettingsHeader.vue:93`), the description clamps on
small screens only (`:69`), the macro editor stacks (`macros/MacroForm.vue:119,134`), the channel
grid steps `1 → xs:2 → sm:3` (`inbox/ChannelList.vue:124`), the inbox detail tab strip grows scroll
chevrons when it overflows (`components/ui/Tabs/Tabs.vue:38-54`), the `Popover` in the team form
takes `disable-mobile-view` (`teams/TeamForm.vue:111`), and `BaseSettingsListItem` was written
`flex-col sm:flex-row` (`settings/components/BaseSettingsListItem.vue:16`) — the pattern exists, it
is just not applied to the live rows.

### 3.7 Table usability

**V34 — Column headers are passed as a positional array of strings (medium).**
`labels/Index.vue:86-93`, `canned/Index.vue:133-138`, `macros/Index.vue:61-69`,
`agentBots/Index.vue:42-48`, `teams/AgentSelector.vue:76-80`. Cells are then emitted in template
order with no key binding, so a column can only be referenced by index — which is exactly why
canned responses addresses its sort control as `#header-0` (`canned/Index.vue:184`) and the
select-all checkbox is `#header-1`'s neighbour `#header-0`
(`teams/AgentSelector.vue:85`). Adding or reordering a column silently breaks these slots.

**V35 — Headers are force-`capitalize`d, mangling an already-correct i18n string (low).**
`components-next/table/BaseTable.vue:98`. `MACROS.LIST.TABLE_HEADER['CREATED BY']` is
`"Created by"` in `dashboard/i18n/locale/en/macros.json` and renders as "Created By".

**V36 — i18n key with a space in it (low).**
`macros/Index.vue:64` reads `MACROS.LIST.TABLE_HEADER.CREATED BY`; the JSON key is literally
`"CREATED BY"` (`dashboard/i18n/locale/en/macros.json`), out of step with the
`LAST_UPDATED_BY` sibling.

**V37 — Action-column width is hard-coded `w-24` and the row-action gap is `gap-3` (low).**
`canned/Index.vue:224`, `macros/MacrosTableRow.vue:94`, `agentBots/Index.vue:172`. Two 32 px buttons
plus a 12 px gap is 76 px in a 96 px cell; a third action would overflow without a change at every
call site. The labels table does not set a width at all (`labels/Index.vue:165`), so its action
column is sized by content.

**V38 — No row-level selection or bulk action anywhere on this surface (medium).**
`BaseTableRow` supports `selected` and emits `aria-selected`
(`components-next/table/BaseTableRow.vue:15-29`) and the surface has a working multi-select pattern
in `teams/AgentSelector.vue:84-152` (tri-state select-all + sticky selected-count footer), but no
list page offers select-many-then-act. Deleting ten labels is ten dialogs.

### 3.8 Empty-state quality

**V39 — The empty state is a single centred sentence with no action (high).**
`settings/SettingsLayout.vue:31-36` renders a bare `<p class="py-20">`. The copy is a dead end on
every page: "There are no agents associated to this account"
(`dashboard/i18n/locale/en/agentMgmt.json`), "There are no labels available in this account.",
"There are no teams created on this account.", "There are no inboxes attached to this account.",
"There are no custom attributes created", "No macros found". None of them offers the create button
that sits scrolled away in the header. Only agent bots writes the next step into the sentence — "No
bots found. You can create a bot by clicking the 'Add Bot' button."
(`dashboard/i18n/locale/en/agentBots.json`) — which is a copy workaround for a missing control.

**V40 — Two empty states are layered on top of each other and one branch is unreachable (medium).**
Labels, canned, macros and agent bots pass both `no-records-found` to `SettingsLayout`
(`labels/Index.vue:104-105`, `canned/Index.vue:145-146`, `macros/Index.vue:74-75`,
`agentBots/Index.vue:102-103`) and `no-data-message` to `BaseTable`
(`labels/Index.vue:134-136`, `canned/Index.vue:176-182`, `macros/Index.vue:105-107`,
`agentBots/Index.vue:132-134`). `SettingsLayout.vue:31-37` short-circuits the `body` slot when
`noRecordsFound`, so the table's own "404" branch can never render — yet all four pages compute it,
and canned responses even computes a third empty-string branch (`canned/Index.vue:177-181`).

**V41 — The empty-state colour differs between the two renderers (low).**
`SettingsLayout.vue:33` uses `text-n-slate-12` (primary text) while the search-empty states and the
table's no-data row use `text-n-slate-11` (`BaseTable.vue:155`, `agents/Index.vue:180`,
`teams/Index.vue:114`, `inbox/Index.vue:124`, `attributes/Index.vue:202`). Attributes' own
page-level empty state uses `text-n-slate-12` (`attributes/Index.vue:221`), so one page shows both
shades depending on whether a query is active.

**V42 — Attributes renders its empty state in the body instead of through the layout (low).**
`attributes/Index.vue:164-167` deliberately omits `no-records-found`/`no-records-message` and
hand-writes the empty paragraph at `:219-224`, so that the tab bar stays visible when a tab is
empty. The right behaviour, achieved by bypassing the shared layout.

**V43 — Search-empty copy is duplicated verbatim in four places (low).**
`agents/Index.vue:178-183`, `teams/Index.vue:112-117`, `inbox/Index.vue:122-127`,
`attributes/Index.vue:200-205` all repeat
`flex-1 flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11`.

**V44 — Wizard "finish" screens are the only rich empty-ish states, and they use a different component (low).**
`teams/FinishSetup.vue:15-29` and `inbox/FinishSetup.vue:192-360` use
`components/widgets/EmptyState.vue` with a title, a message and real next-step buttons — the shape
the list empty states lack.

### 3.9 Loading and error behaviour

**V45 — Loading is a centred text+spinner line, not a shape of the content to come (medium).**
`settings/SettingsLayout.vue:28-30` → `components/widgets/LoadingState.vue:9-19` renders
`<h6>` with the message and a spinner at `p-8`. `BaseTable` can draw skeleton rows
(`components-next/table/BaseTable.vue:134-148`) and nothing uses it, so the table pages flash from a
one-line spinner to a full table.

**V46 — Inbox list shows a bare spinner with no message, unlike its seven siblings (medium).**
`inbox/Index.vue:98` passes `:is-loading` but no `loading-message`, while every other page passes
one (`agents/Index.vue:150`, `teams/Index.vue:86`, `labels/Index.vue:103`,
`attributes/Index.vue:166`, `canned/Index.vue:144`, `macros/Index.vue:77`,
`agentBots/Index.vue:101`). `LoadingState.vue:14-16` then renders an empty `<span>`.

**V47 — Inbox detail uses a third loading treatment (low).**
`inbox/Settings.vue:775-781` renders a bare `SpinnerLoader :size="28"` centred in the viewport
instead of `woot-loading-state`. The team and macro sub-pages add a fourth and fifth:
`shared/components/Spinner.vue` (`teams/Edit/EditTeam.vue:73`),
`components-next/spinner/Spinner.vue` (`teams/Edit/EditAgents.vue:129-131`) and
`woot-loading-state` (`macros/MacroEditor.vue:138-141`).

**V48 — There is no error state on this surface; failures become toasts (high).**
Every fetch/mutate failure routes to `useAlert` — `agents/Index.vue:137`,
`labels/Index.vue:72-74`, `attributes/Index.vue:102-104`, `canned/Index.vue:121-123`,
`macros/Index.vue:42-44`, `agentBots/Index.vue:79-80`, `teams/Index.vue:39-41`,
`inbox/Index.vue:75-77`. `SettingsLayout.vue` has no error slot or branch at all. If a list fetch
fails, the page settles into its *empty* state ("There are no labels available in this account")
while a transient toast carries the only hint that something broke — an empty state that actively
misinforms.

**V49 — Canned responses swallows its fetch error entirely (high).**
`canned/Index.vue:73-79` catches and does nothing ("// Ignore Error"). A failed load is
indistinguishable from an account with no canned responses, and there is not even a toast. This is
the settings landing page for every agent (`settings.routes.js:51`).

**V50 — Per-row loading spinners are wired to the wrong button on three pages (medium).**
Labels binds `loading[label.id]` to both the edit and the delete button
(`labels/Index.vue:173,184`), as does agent bots (`agentBots/Index.vue:181,192`), so confirming a
delete spins the pencil too. Agents gets this right by binding only the delete button
(`agents/Index.vue:274`).

**V51 — Canned responses' per-row spinner can never fire (medium).**
`loading` is a `ref({})` (`canned/Index.vue:32`) but is written as `loading[...] = …` without
`.value` at `:86` and `:128`, so the reactive object is never touched and
`:is-loading="loading[cannedItem.id]"` (`:241`) is always `undefined`.

**V52 — The add-attribute form reads the wrong store's UI flags (medium).**
`attributes/AddAttribute.vue:53-55` maps `uiFlags: 'getUIFlags'` — the root getter, which belongs to
the **non-namespaced** canned-response module (`dashboard/store/modules/cannedResponse.js:29-31`;
`dashboard/store/modules/attributes.js:109` is the namespaced one). That object exposes
`fetchingList/creatingItem/...`, never `isCreating`, so `isButtonDisabled`
(`attributes/AddAttribute.vue:78-84`) never reflects the in-flight create and the submit button
carries no `:is-loading` at all (`:284-288`). Every sibling form shows a spinner on submit
(`labels/AddLabel.vue:125`, `agents/AddAgent.vue:162`, `agentBots/.../AgentBotModal.vue:414`).

**V53 — `setTimeout(…, 10)` used to close two edit modals (low).**
`labels/EditLabel.vue:70` and `canned/EditCanned.vue:76-78`. A timing workaround where the other six
pages close synchronously.

**V54 — Macro delete borrows its dialog title from the labels namespace (low).**
`macros/Index.vue:123` uses `$t('LABEL_MGMT.DELETE.CONFIRM.TITLE')` because
`MACROS.DELETE.CONFIRM` has no `TITLE` key (`dashboard/i18n/locale/en/macros.json`).

### 3.10 Accessibility

**V55 — Empty focusable links render for non-admins on the teams and inboxes rows (medium).**
`teams/Index.vue:151-167` and `inbox/Index.vue:183-199` put `v-if="isAdmin"` on the `Button`
*inside* the `router-link`, not on the link. The link keeps its `aria-label` and tooltip while its
only child disappears, producing a focusable anchor with an accessible name and no visible content.
(Both routes are `['administrator']`-gated today, so this is latent rather than live — but it is the
shape the markup commits to.)

**V56 — The agent role permission list is pointer-only (medium).**
`agents/Index.vue:208-239`: a `<span>` with `cursor-pointer` and `group-hover:block`, no `tabindex`,
no `aria-expanded`, no focus trigger. Keyboard and screen-reader users cannot read which permissions
a custom role grants.

**V57 — Icon-only buttons inside `router-link`s rely on the link carrying the name (medium, mostly handled).**
`teams/Index.vue:151-166`, `inbox/Index.vue:183-198` and `macros/MacrosTableRow.vue:96-108` put the
`aria-label` and tooltip on the anchor and mark the inner button `tabindex="-1" aria-hidden="true"` —
the right pattern. But the "new" buttons wrapped in `router-link` carry no accessible name on the
link at all and depend on the button's `label` (`teams/Index.vue:105-108`,
`inbox/Index.vue:115-118`, `macros/Index.vue:95-97`), so the three patterns differ.

**V58 — Checkbox inputs are associated to their label by nothing (medium).**
`labels/AddLabel.vue:107-111`, `labels/EditLabel.vue:111-115` and `teams/TeamForm.vue:163-167` all
render `<input type="checkbox">` followed by `<label for="conversation_creation">` — an `id` that
exists on no element in any of the three files, and is copy-pasted across two unrelated features.
Clicking the label does nothing and the accessible name is empty.
`attributes/AddAttribute.vue:252-259` and `attributes/EditAttribute.vue:236-243` go further and emit
a bare checkbox followed by loose text with no `<label>` element at all.

**V59 — The custom sort control in the canned table is a button with no sort semantics (low).**
`canned/Index.vue:185-200` renders a `<button>` with an icon and no `aria-label`, and the `<th>`
gets no `aria-sort`, whereas `BaseTable`'s own sort button supplies both
(`components-next/table/BaseTable.vue:99-112`).

**V60 — Non-semantic headings (low).**
`settings/SettingsHeader.vue:46-58` nests the title text in a `<span>` inside the `h1` alongside the
back `<button>`, so the heading's accessible name includes the back-button label.
`components/widgets/LoadingState.vue:11` uses an `<h6>` purely for text styling.
`agents/Index.vue:199`, `teams/Index.vue:142`, `inbox/Index.vue:155` and `canned/Index.vue:215`
style record names as `text-heading-3` on `<span>`s, giving the list no heading structure at all,
while `.../AttributeListItem.vue:48` uses a real `<h4>`.

**V61 — `aria-hidden="true"` on a skeleton row is right; nothing else announces load state (low).**
`components-next/table/BaseTable.vue:138` marks skeleton rows hidden, but no page uses them, and the
live `LoadingState` has no `role="status"` / `aria-live` (`components/widgets/LoadingState.vue:9-19`),
so a screen reader is told nothing when a list finishes loading.

**V62 — What is correct (positive).**
Every icon-only row action on all eight pages carries both `v-tooltip.top` and a matching
`aria-label` (`agents/Index.vue:259-260,268-269`; `labels/Index.vue:168-169,177-178`;
`canned/Index.vue:227-228,235-236`; `macros/MacrosTableRow.vue:97-99,111-112`;
`teams/Index.vue:152-157,171-172`; `inbox/Index.vue:184-189,202-203`;
`agentBots/Index.vue:176-177,186-187`; `.../AttributeListItem.vue:81,88`).
`BaseTable` emits `aria-sort` (`:99-105`), `BaseTableRow` emits `aria-selected` (`:28`),
`MacroProperties` wires `aria-describedby` to its disabled-card explanation (`:96-98,112`),
`Checkbox` supports `indeterminate` (`teams/AgentSelector.vue:88-91`), the next-gen `Dialog` uses a
native `<dialog>` with `showModal()` for a real focus trap (`components-next/dialog/Dialog.vue:88-91`),
`Modal` handles Escape (`components/Modal.vue:50-55`), and the inbox identifier is wrapped in
`<bdi dir="auto">` (`inbox/Index.vue:170-176`).

---

## 4. What this surface already does well and must not be lost

1. **One header contract, honoured by all eight pages.** Every list page drives
   `BaseSettingsHeader` with the same five inputs — title, description, learn-more link, search
   placeholder, feature name — plus the `count`/`actions`/`tabs` slots
   (`agents/Index.vue:155-175`, `teams/Index.vue:91-109`, `inbox/Index.vue:101-119`,
   `labels/Index.vue:108-128`, `attributes/Index.vue:169-196`, `canned/Index.vue:149-169`,
   `macros/Index.vue:81-99`, `agentBots/Index.vue:106-126`). This uniformity is the single
   strongest thing about the surface.

2. **A declarative loading/empty/body state machine.** `SettingsLayout`
   (`settings/SettingsLayout.vue:22-41`) means no page hand-rolls `v-if` chains for loading and
   empty, and every page passes a *feature-specific* loading message and empty sentence rather than
   a generic one.

3. **Fuzzy, weighted, multi-field search on every page.** `picoSearch` with field weights where it
   matters — `title` weight 4 for labels (`labels/Index.vue:35-38`), `short_code` weight 4 for
   canned (`canned/Index.vue:48-51`) — and a domain-specific helper for inboxes that searches name,
   channel *and* identifier (`inbox/Index.vue:48`, `dashboard/helper/inbox`).

4. **A real record count next to the primary action.** `AGENT_MGMT.COUNT` and siblings are
   pluralised i18n strings, rendered only when the list is non-empty, separated from the action
   button by a divider (`settings/components/BaseSettingsHeader.vue:123-128`;
   `agents/Index.vue:163-167` and the seven equivalents).

5. **Destructive confirmation that reads the record's name back.** The plain modals interpolate the
   name into both buttons — `"Yes, Delete sales-team"` / `"No, Keep sales-team"`
   (`agents/Index.vue:31-36`, `canned/Index.vue:55-63`), and the high-stakes ones require the user to
   type it (`components/widgets/modal/ConfirmDeleteModal.vue:31-41`;
   `teams/Index.vue:191-192`, `inbox/Index.vue:222-223`, `attributes/Index.vue:253-258`).
   Whitespace-trimmed comparison (`ConfirmDeleteModal.vue:36-38`) means a trailing space does not
   block a correct answer.

6. **Permission and eligibility gating done per row, not per page.** Agents cannot delete
   themselves, cannot delete the last verified administrator, and *can* always delete an unconfirmed
   invite (`agents/Index.vue:77-100`). Macros hide delete but keep view for public macros a
   non-admin cannot manage, and the tooltip changes to "View"
   (`macros/MacrosTableRow.vue:40-46,110`). System bots expose neither edit nor delete
   (`agentBots/Index.vue:175,185`). Public macro visibility is disabled with an explanation, not
   silently absent (`macros/MacroProperties.vue:34-48`).

7. **Read-only mode is a first-class state in the macro editor.** `:inert` plus `opacity-75` on the
   canvas, a disabled Save, and guards in both the property setters and the save handler
   (`macros/MacroForm.vue:123`, `macros/MacroProperties.vue:56-66,158`,
   `macros/MacroEditor.vue:117`).

8. **Status is surfaced inline on the row, not hidden behind a click.** Verified / Verification
   Pending for agents (`agents/Index.vue:241-252`), channel + identifier for inboxes
   (`inbox/Index.vue:162-178`), Public/Personal for macros (`macros/MacrosTableRow.vue:88-92`),
   global-bot badge for bots (`agentBots/Index.vue:152-157`), and — the best of them — the
   attributes page computing "this key is used in a pre-chat form" and "this key is required at
   resolution" badges by reading across the inboxes and account-settings stores
   (`attributes/Index.vue:108-140`).

9. **Contextual links out to the modules that consume the record.** The attribute badges above; the
   macro editor prefetching agents, teams and labels so its action dropdowns are populated
   (`macros/MacroEditor.vue:44-49`); the inbox account-health tab linking into the configuration tab
   (`inbox/Settings.vue:616-622`); the inbox finish screen offering both "more settings" and "go to
   the inbox" (`inbox/FinishSetup.vue:333-358`).

10. **Progressive disclosure in the forms.** Attribute list-values only when the type is List,
    regex pattern and cue only when the type is Text *and* regex is enabled, with the pattern cleared
    on submit if disabled (`attributes/AddAttribute.vue:228-275,134-137`). Business-name input only
    after the user asks for it (`inbox/Settings.vue:1022-1060`). Access token and secret revealed
    once after bot creation, then replaced by reset-capable fields in edit mode
    (`agentBots/components/AgentBotModal.vue:111-116,184-199,349-399`).

11. **Heavy objects escalate to a stepped flow with a visible rail.** Four steps for an inbox
    (`inbox/InboxChannels.vue:16-33`), three for a team (`teams/Create/Index.vue:4-19`), with the
    step marker turning into a check once passed (`components/ui/Wizard.vue:49-63`) and a real
    success screen at the end (`teams/FinishSetup.vue:15-29`, `inbox/FinishSetup.vue:192-360`).

12. **The inbox detail page's tab set is computed from the channel, not hard-coded.** Twelve
    possible tabs, each gated on channel type, account feature flag, or both
    (`inbox/Settings.vue:166-300`), with the active tab written into the URL without re-rendering
    (`:656-671`) and restored from the route param on load (`:673-681`) — so an inbox tab is
    linkable and survives a refresh.

13. **Channel availability is communicated, not hidden.** Disabled tiles, "Coming soon", "Beta" and
    voice badges (`components/widgets/ChannelItem.vue:75-101`), and the TikTok tile turning into a
    "request access" affordance that opens support instead of dead-ending
    (`components/widgets/ChannelItem.vue:103-112`, `inbox/ChannelList.vue:86-92`).

14. **Reconnection and provider-health problems are banners on the page, not silent failures.**
    Six per-provider reauthorize banners plus duplicate-inbox, Instagram-restriction and
    WhatsApp-migration banners, all width-matched to the active tab
    (`inbox/Settings.vue:807-874`, `:714-722`), and the account-health tabs expose the provider's own
    error message plus a "register webhook" retry (`inbox/Settings.vue:1441-1457`, `:624-641`).

15. **Multi-select is already solved once, well.** `teams/AgentSelector.vue:84-152` — tri-state
    select-all in the header cell, per-row design-system checkboxes, and a sticky footer showing
    `"{selected} of {total}"` beside the submit button, which stays disabled at zero.

16. **Rich text and structured input where the data warrants it.** The ProseMirror editor with
    variables for canned-response content (`canned/AddCanned.vue:109-118`), colour picker with a
    random seed colour for labels (`labels/AddLabel.vue:103,42-44`), tag input for attribute list
    values (`attributes/AddAttribute.vue:236-243`), emoji/icon picker with colour for team icons
    (`teams/TeamForm.vue:110-148`), avatar upload for bots and inboxes
    (`agentBots/components/AgentBotModal.vue:310-318`, `inbox/Settings.vue:896-905`).

17. **White-labelling is respected.** The help link is wrapped in `CustomBrandPolicyWrapper`
    (`settings/components/BaseSettingsHeader.vue:73-87`), the inbox wizard runs its step copy through
    `replaceInstallationName` (`inbox/InboxChannels.vue:53-58`), and the API channel's title comes
    from `globalConfig.apiChannelName` (`inbox/ChannelList.vue:58`).

18. **Logical (direction-aware) Tailwind utilities are the norm.** See V26. The shared table,
    header, dividers, modals and wizard are all RTL-correct; the exceptions are localised and
    enumerable (V22–V25).
