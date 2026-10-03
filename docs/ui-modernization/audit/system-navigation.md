# Audit — Sidebar and Settings Navigation IA

**Scope:** `app/javascript/dashboard/components-next/sidebar/*` plus its direct consumers
(`app/javascript/dashboard/routes/dashboard/Dashboard.vue`),
the sort helper (`app/javascript/dashboard/helper/sidebarSort.js`), the gating layer
(`app/javascript/dashboard/components/policy.vue`, `app/javascript/dashboard/composables/usePolicy.js`),
and the route metadata the sidebar reads permissions / feature flags from.

**Status:** read-only baseline. This document records *what exists today*, literally, as the reference the
feature-preservation contract is checked against. No redesign is proposed.

All paths are relative to the repository root. All line numbers are from the files as read for this audit.

---

## 1. File inventory

| File | Lines | Role |
| --- | --- | --- |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | 1650 | Shell + the entire menu tree (`menuItems`, lines 386–877), resize/collapse, header, footer, and 578 lines of `<style scoped>` (1072–1650) |
| `app/javascript/dashboard/components-next/sidebar/SidebarGroup.vue` | 334 | One top-level group: active-state resolution, accordion, collapsed hover popover, `Policy` gate |
| `app/javascript/dashboard/components-next/sidebar/SidebarGroupHeader.vue` | 86 | Group row (icon, label, count badge, chevron) |
| `app/javascript/dashboard/components-next/sidebar/SidebarSubGroup.vue` | 182 | Second-level section (Folders / Teams / Channels / Labels / Segments / Tagged with): minimize state, scroll cap, tree trunk |
| `app/javascript/dashboard/components-next/sidebar/SidebarGroupSeparator.vue` | 104 | Sub-group header row: label, collapse chevron, sort menu slot, tree elbow |
| `app/javascript/dashboard/components-next/sidebar/SidebarGroupLeaf.vue` | 66 | Leaf row: tree connector, icon, label, unread badge, optional custom component |
| `app/javascript/dashboard/components-next/sidebar/SidebarGroupEmptyLeaf.vue` | 13 | Dashed "No items" placeholder |
| `app/javascript/dashboard/components-next/sidebar/SidebarCollapsedPopover.vue` | 256 | Teleported flyout shown on hover when the sidebar is collapsed |
| `app/javascript/dashboard/components-next/sidebar/SidebarUnreadBadge.vue` | 27 | Shared unread pill, caps at `99+` |
| `app/javascript/dashboard/components-next/sidebar/ChannelLeaf.vue` | 70 | Custom leaf for inboxes: channel icon, `name · identifier`, reauthorize warning |
| `app/javascript/dashboard/components-next/sidebar/SidebarSortMenu.vue` | 209 | Per-section sort dropdown (hover-opened in the tree, click-opened in the popover) |
| `app/javascript/dashboard/components-next/sidebar/SidebarAccountSwitcher.vue` | 152 | Account name trigger + switch-account dropdown |
| `app/javascript/dashboard/components-next/sidebar/SidebarProfileMenu.vue` | 175 | Footer avatar trigger + 8-item user menu |
| `app/javascript/dashboard/components-next/sidebar/SidebarProfileMenuStatus.vue` | 130 | Availability picker + auto-offline toggle inside the profile menu |
| `app/javascript/dashboard/components-next/sidebar/SidebarChangelogCard.vue` | 120 | Expanded-state changelog card (hub fetch, dismissals in `ui_settings`) |
| `app/javascript/dashboard/components-next/sidebar/SidebarChangelogButton.vue` | 46 | Collapsed-state changelog trigger wrapping the same card |
| `app/javascript/dashboard/components-next/sidebar/MobileSidebarLauncher.vue` | 62 | Floating hamburger FAB, hidden on conversation routes |
| `app/javascript/dashboard/components-next/sidebar/provider.js` | 160 | `useSidebarResize`, `usePopoverState`, `useSidebarContext` / `provideSidebarContext` |
| `app/javascript/dashboard/components-next/sidebar/useSidebarKeyboardShortcuts.js` | 39 | 6 global keyboard bindings |
| `app/javascript/dashboard/components-next/sidebar/specs/` | 3 files | `ChannelLeaf.spec.js`, `SidebarGroupLeaf.spec.js`, `SidebarSubGroup.spec.js` |

---

## 2. The complete menu tree, as built

Source of truth: the `menuItems` computed, `Sidebar.vue:386–877`. It is rendered by a single
`v-for` over `SidebarGroup`, `Sidebar.vue:1016–1020`.

Permissions / feature flags are **not** declared in `Sidebar.vue`. They are read off the *target route's*
`meta` at render time by `resolvePermissions` / `resolveFeatureFlag` / `resolveInstallationType`
(`provider.js:105–147`). The tables below resolve them for you.

### 2.0 Top-level groups, in order

| # | `name` | `label` key (en value) | Icon | Children | Lines |
| --- | --- | --- | --- | --- | --- |
| 1 | `Inbox` | `SIDEBAR.INBOX` — "My Inbox" | `i-lucide-inbox` | none (direct link) | 388–397 |
| 2 | `Conversation` | `SIDEBAR.CONVERSATIONS` — "Conversations" | `i-lucide-message-circle` | 8 (4 leaves + 4 sub-groups) | 399–525 |
| 3 | `Contacts` | `SIDEBAR.CONTACTS` — "Contacts" | `i-lucide-contact` | 4 (2 leaves + 2 sub-groups) | 526–594 |
| 4 | `Companies` | `SIDEBAR.COMPANIES` — "Companies" | `i-lucide-building-2` | 1 leaf | 595–611 |
| 5 | `Reports` | `SIDEBAR.REPORTS` — "Reports" | `i-lucide-chart-spline` | 9 leaves | 612–644 |
| 6 | `Campaigns` | `SIDEBAR.CAMPAIGNS` — "Campaigns" | `i-lucide-megaphone` | 3 leaves | 645–666 |
| 7 | `Portals` | `SIDEBAR.HELP_CENTER.TITLE` — "Help Center" | `i-lucide-library-big` | 4 leaves | 667–713 |
| 8 | `Settings` | `SIDEBAR.SETTINGS` — "Settings" | `i-lucide-bolt` | 18 fixed + 2 gated = **20 max** | 714–875 |

**Static leaf count: 41 with both Settings flags off, 43 with both on**, plus N dynamic leaves
(one per folder, team, inbox, sidebar-visible label, and contact segment).

### 2.1 Group 1 — Inbox (0 children)

| `name` | Label key | Icon | Route (`to`) | `activeOn` | Permissions | Feature flag | Lines |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `Inbox` | `SIDEBAR.INBOX` | `i-lucide-inbox` | `inbox_view` | `inbox_view`, `inbox_view_conversation` | `agent`, `administrator`, `conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage` (`inbox/routes.js:20`) | none | 388–397 |

The only group with `getterKeys` (`Sidebar.vue:394–396`): `count: 'notifications/getUnreadCount'`.
Rendered as the numeric pill in `SidebarGroupHeader.vue:72–77`, capped to `99+` at line 23–25.

### 2.2 Group 2 — Conversation (8 children: 4 leaves, 4 sub-groups)

Every route below carries `CONVERSATION_PERMISSIONS` = `conversation_manage`,
`conversation_unassigned_manage`, `conversation_participating_manage`
(`conversation.routes.js:51, 100, 123, 146, 171, 194, 217`; constants at
`app/javascript/dashboard/constants/permissions.js:13–17`). No feature flag on any of them.

| Order | `name` | Label key (en) | Icon | Route | `activeOn` | Badge source | Lines |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `All` | `SIDEBAR.ALL_CONVERSATIONS` — "All Conversations" | `i-lucide-inbox` | `home` | `inbox_conversation` | `allUnreadCount` — unconditional | 403–410 |
| 2 | `Mentions` | `SIDEBAR.MENTIONED_CONVERSATIONS` — "Mentions" | `i-lucide-at-sign` | `conversation_mentions` | `conversation_through_mentions` | `mentionsUnreadCount` if `hasFilteredUnreadCounts` else `0` | 411–420 |
| 3 | `Participating` | `SIDEBAR.PARTICIPATING_CONVERSATIONS` — "Participating" | `i-lucide-user-round-check` | `conversation_participating` | `conversation_through_participating` | `participatingUnreadCount` if `hasFilteredUnreadCounts` else `0` | 421–430 |
| 4 | `Unattended` | `SIDEBAR.UNATTENDED_CONVERSATIONS` — "Unattended" | `i-lucide-clock-alert` | `conversation_unattended` | `conversation_through_unattended` | `unattendedUnreadCount` if `hasFilteredUnreadCounts` else `0` | 431–440 |
| 5 | `Folders` | `SIDEBAR.CUSTOM_VIEWS_FOLDER` — "Folders" | `i-lucide-folder` | — (sub-group) | `conversations_through_folders` (**never read**, see §7.1) | per-leaf, gated on `hasFilteredUnreadCounts` | 441–457 |
| 6 | `Teams` | `SIDEBAR.TEAMS` — "Teams" | `i-lucide-users` | — (sub-group) | `conversations_through_team` (never read) | per-leaf, unconditional | 458–479 |
| 7 | `Channels` | `SIDEBAR.CHANNELS` — "Channels" | `i-lucide-mailbox` | — (sub-group) | `conversation_through_inbox` (never read) | per-leaf, unconditional | 480–502 |
| 8 | `Labels` | `SIDEBAR.LABELS` — "Labels" | `i-lucide-tag` | — (sub-group) | `conversations_through_label` (never read) | per-leaf, unconditional | 503–523 |

Dynamic sub-group contents:

| Sub-group | Data source | Sorted by | Leaf `to` | Leaf icon | Custom leaf |
| --- | --- | --- | --- | --- | --- |
| Folders | `customViews/getConversationCustomViews` (`Sidebar.vue:255`) | `sortedFolders` (`321–327`) | `folder_conversations` `{ id }` | none | none |
| Teams | `teams/getMyTeams` (`253`) — members only | `sortedTeams` (`329–335`) | `team_conversations` `{ teamId }` | `EmojiIcon` with `team.icon` / `team.icon_color`, `size-3.5`, else `undefined` (`470–476`) | none |
| Channels | `inboxes/getInboxes` (`227`) | `sortedInboxes` (`337–343`) | `inbox_dashboard` `{ inbox_id }` | `ChannelIcon` `size-[16px]` (`492`) | **`ChannelLeaf`** (`494–500`) |
| Labels | `labels/getLabelsOnSidebar` (`228`) — `show_on_sidebar` only, pre-sorted A→Z by the getter | `sortedLabels` (`345–351`) | `label_conversations` `{ label: title }` | inline `h('span')`, `size-[8px] rounded-sm`, `backgroundColor: label.color` (`515–518`) | none |

All four sub-groups set `collapsible: true` and `showTreeLine: true`, and all four carry a
sort config via `buildSortConfig` (`Sidebar.vue:315–319`).

### 2.3 Group 3 — Contacts (4 children: 2 leaves, 2 sub-groups)

All four resolve to `commonMeta` in `contacts/routes.js:6–9`:
feature flag **`crm`**, permissions `administrator`, `agent`, `contact_manage`.

| Order | `name` | Label key (en) | Icon | Route | `activeOn` | Lines |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `All Contacts` | `SIDEBAR.ALL_CONTACTS` — "All Contacts" | none | `contacts_dashboard_index`, query `{ page: 1, search: undefined }` | `contacts_dashboard_index`, `contacts_edit` | 531–540 |
| 2 | `Active` | `SIDEBAR.ACTIVE` — "Active" | none | `contacts_dashboard_active` | `contacts_dashboard_active` | 541–546 |
| 3 | `Segments` | `SIDEBAR.CUSTOM_VIEWS_SEGMENTS` — **"Audiences"** | `i-lucide-group` | — (sub-group) | — | 547–568 |
| 4 | `Tagged With` | `SIDEBAR.TAGGED_WITH` — "Tagged with" | `i-lucide-tag` | — (sub-group) | — | 569–592 |

| Sub-group | Data source | Sorted | Leaf label | Leaf `to` | Leaf `activeOn` |
| --- | --- | --- | --- | --- | --- |
| Segments | `customViews/getContactCustomViews` (`254`) | **no sort menu, raw store order** | `view.name`, or `SIDEBAR.SHARED_AUDIENCE` = `"{name} · Shared"` when `view.shared` (`555–557`) | `contacts_dashboard_segments_index` `{ segmentId }`, query `{ page: 1 }` | `contacts_dashboard_segments_index`, `contacts_edit_segment` |
| Tagged With | `labels/getLabelsOnSidebar` (same ref as Conversation ▸ Labels) | **no sort menu**, getter's A→Z order | `label.title` | `contacts_dashboard_labels_index` `{ label: title }`, query `{ page: 1, search: undefined }` | `contacts_dashboard_labels_index`, `contacts_edit_label` |

Neither contacts sub-group renders unread badges.

### 2.4 Group 4 — Companies (1 leaf)

| `name` | Label key (en) | Icon | Route | `activeOn` | Gating | Lines |
| --- | --- | --- | --- | --- | --- | --- |
| `All Companies` | `SIDEBAR.ALL_COMPANIES` — "All Companies" | none | `companies_dashboard_index`, query `{ page: 1, search: undefined }` | `companies_dashboard_index`, `companies_dashboard_show` | flag **`companies`**; permissions `administrator`, `agent`; `installationTypes: [CLOUD, ENTERPRISE]` (`companies/routes.js:7–11`) | 600–609 |

This is the only sidebar entry whose route declares `installationTypes` — see §7.2 for the gap that creates.

### 2.5 Group 5 — Reports (9 leaves)

All nine share `meta` from `reports.routes.js:27–30`: flag **`reports`**, permissions
`administrator`, `report_manage`. None has an icon.

| Order | `name` | Label key (en) | Route | `activeOn` | Lines |
| --- | --- | --- | --- | --- | --- |
| 1 | `Report Overview` | `SIDEBAR.REPORTS_OVERVIEW` — "Overview" | `account_overview_reports` | — | 617–621 |
| 2 | `Report Conversation` | `SIDEBAR.REPORTS_CONVERSATION` — "Conversations" | `conversation_reports` | — | 622–626 |
| 3 | `Reports Agent` | `SIDEBAR.REPORTS_AGENT` — "Agents" | `agent_reports_index` | `agent_reports_show` | 359–364 (spread at 627) |
| 4 | `Reports Label` | `SIDEBAR.REPORTS_LABEL` — "Labels" | `label_reports_index` | — | 365–369 |
| 5 | `Reports Inbox` | `SIDEBAR.REPORTS_INBOX` — "Inbox" | `inbox_reports_index` | `inbox_reports_show` | 370–375 |
| 6 | `Reports Team` | `SIDEBAR.REPORTS_TEAM` — "Team" | `team_reports_index` | `team_reports_show` | 376–381 |
| 7 | `Reports CSAT` | `SIDEBAR.CSAT` — "CSAT" | `csat_reports` | — | 628–632 |
| 8 | `Reports SLA` | `SIDEBAR.REPORTS_SLA` — "SLA" | `sla_reports` | — | 633–637 |
| 9 | `Reports Bot` | `SIDEBAR.REPORTS_BOT` — "Bot" | `bot_reports` | — | 638–642 |

Entries 3–6 come from the `newReportRoutes()` factory (`Sidebar.vue:358–382`) wrapped in a
`reportRoutes` computed (`384`) that adds nothing — a one-call indirection.
`label_reports_index` is the only `*_index` report without a matching `*_show` in `activeOn`,
even though `label_reports_show` exists (`reports.routes.js:105`).

### 2.6 Group 6 — Campaigns (3 leaves)

Base `meta` (`campaigns.routes.js:10–13`): flag **`campaigns`**, permissions `administrator`. No icons.

| Order | `name` | Label key (en) | Route | Feature flag | Lines |
| --- | --- | --- | --- | --- | --- |
| 1 | `Live chat` | `SIDEBAR.LIVE_CHAT` — "Live Chat" | `campaigns_livechat_index` | `campaigns` | 650–654 |
| 2 | `SMS` | `SIDEBAR.SMS` — "SMS" | `campaigns_sms_index` | `campaigns` | 655–659 |
| 3 | `WhatsApp` | `SIDEBAR.WHATSAPP` — "WhatsApp" | `campaigns_whatsapp_index` | **`whatsapp_campaign`** (`campaigns.routes.js:58–61`) | 660–664 |

No `activeOn` on any of the three; `campaigns_whatsapp_analytics` therefore relies on the
path-prefix fallback in `SidebarGroup.vue:189–193`.

### 2.7 Group 7 — Portals / Help Center (4 leaves)

Every leaf points at the **same** route, `portals_index`, and distinguishes itself only by the
`navigationPath` param. `provider.js:109–112, 121–124, 132–135` special-cases that param so that
permissions and flags come from the *target* route, not from `portals_index`.

| Order | `name` | Label key (en) | `navigationPath` | `activeOn` | Resolved gating | Lines |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `Articles` | `SIDEBAR.HELP_CENTER.ARTICLES` — "Articles" | `portals_articles_index` | `portals_articles_index`, `portals_articles_new`, `portals_articles_edit` | flag `help_center`; `administrator`, `agent`, `knowledge_base_manage` (`helpcenter.routes.js:25–27`) | 672–683 |
| 2 | `Categories` | `SIDEBAR.HELP_CENTER.CATEGORIES` — "Categories" | `portals_categories_index` | `portals_categories_index`, `portals_categories_articles_index`, `portals_categories_articles_edit` | same | 684–695 |
| 3 | `Locales` | `SIDEBAR.HELP_CENTER.LOCALES` — "Locales" | `portals_locales_index` | `portals_locales_index` | same | 696–703 |
| 4 | `Settings` | `SIDEBAR.HELP_CENTER.SETTINGS` — "Settings" | `portals_settings_index` | `portals_settings_index` | same | 704–711 |

Note `portals_categories_articles_new` (`helpcenter.routes.js:69`) is absent from the Categories
`activeOn` list while its `_edit` sibling is present.

### 2.8 Group 8 — Settings (18 fixed + 2 gated; the full list, in order)

This is the group the brief singles out. Order is literal source order.

| # | `name` | Label key (en) | Icon | Route | `activeOn` | Route permissions | Route flag / install | Lines |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `Settings Account Settings` | `SIDEBAR.ACCOUNT_SETTINGS` — "Account Settings" | `i-lucide-briefcase` | `general_settings_index` | — | `administrator` | — | 719–724 |
| 2 | `Settings Agents` | `SIDEBAR.AGENTS` — "Agents" | `i-lucide-square-user` | `agent_list` | — | `administrator` | `agent_management` | 725–730 |
| 3 | `Settings Teams` | `SIDEBAR.TEAMS` — "Teams" | `i-lucide-users` | `settings_teams_list` | 8 names: `settings_teams_list`, `_new`, `_finish`, `_add_agents`, `_show`, `_edit`, `_edit_members`, `_edit_finish` | `administrator` | `team_management` | 731–746 |
| 4 | `Settings Agent Assignment` **(gated)** | `SIDEBAR.AGENT_ASSIGNMENT` — "Agent Assignment" | `i-lucide-user-cog` | `assignment_policy_index` | 7 names: `assignment_policy_index`, `agent_assignment_policy_index` / `_create` / `_edit`, `agent_capacity_policy_index` / `_create` / `_edit` | `administrator` | `assignment_v2` | 747–765 |
| 5 | `Settings Inboxes` | `SIDEBAR.INBOXES` — "Inboxes" | `i-lucide-inbox` | `settings_inbox_list` | 6 names: `settings_inbox_list`, `_show`, `_new`, `_finish`, `settings_inboxes_page_channel`, `settings_inboxes_add_agents` | `administrator` | `inbox_management` | 766–779 |
| 6 | `Settings Templates` | `SIDEBAR.WHATSAPP_TEMPLATES` — "Templates" | `i-lucide-layout-template` | `settings_templates` | — | `administrator` | — | 780–785 |
| 7 | `Settings Labels` | `SIDEBAR.LABELS` — "Labels" | `i-lucide-tags` | `labels_list` | — | `administrator` | `labels` | 786–791 |
| 8 | `Settings Custom Attributes` | `SIDEBAR.CUSTOM_ATTRIBUTES` — "Custom Attributes" | `i-lucide-code` | `attributes_list` | — | `administrator` | `custom_attributes` | 792–797 |
| 9 | `Settings Automation` | `SIDEBAR.AUTOMATION` — "Automation" | `i-lucide-repeat` | `automation_list` | — | `administrator` | `automations` | 798–803 |
| 10 | `Settings Agent Bots` | `SIDEBAR.AGENT_BOTS` — "Bots" | `i-lucide-bot` | `agent_bots` | — | `administrator` | `agent_bots` | 804–809 |
| 11 | `Settings Macros` | `SIDEBAR.MACROS` — "Macros" | `i-lucide-toy-brick` | `macros_wrapper` | — | `agent`, `administrator` + all 3 conversation perms | `macros` | 810–815 |
| 12 | `Settings Canned Responses` | `SIDEBAR.CANNED_RESPONSES` — "Canned Responses" | `i-lucide-message-square-quote` | `canned_list` | — | `agent`, `administrator` + all 3 conversation perms | `canned_responses` | 816–821 |
| 13 | `Settings Integrations` | `SIDEBAR.INTEGRATIONS` — "Integrations" | `i-lucide-blocks` | `settings_applications` | — | `administrator` | `integrations` | 822–827 |
| 14 | `Settings Commerce` | `SIDEBAR.COMMERCE` — "Commerce" | `i-lucide-store` | `settings_commerce_index` | — | `administrator` | **`lynomia_commerce`** | 828–833 |
| 15 | `Settings Flow Builder` | `SIDEBAR.FLOW_BUILDER` — "Flow Builder" | `i-lucide-workflow` | `settings_flows_index` | — | `administrator` | **`lynomia_flow_builder`** | 834–839 |
| 16 | `Settings Data` **(gated)** | `SIDEBAR.DATA` — "Data" | `i-lucide-database` | `settings_data_imports` | — | `administrator` | `data_import` | 840–849 |
| 17 | `Settings Audit Logs` | `SIDEBAR.AUDIT_LOGS` — "Audit Logs" | `i-lucide-briefcase` | `auditlogs_list` | — | `administrator` | `audit_logs` + `installationTypes: [CLOUD, ENTERPRISE]` | 850–855 |
| 18 | `Conversation Workflow` | `SIDEBAR.CONVERSATION_WORKFLOW` — "Conversation Workflow" | `i-lucide-workflow` | `conversation_workflow_index` | — | `administrator` | — | 856–861 |
| 19 | `Settings Billing` | `SIDEBAR.BILLING` — "Billing" | `i-lucide-credit-card` | `billing_settings_index` | — | `administrator` | — | 862–867 |
| 20 | `Settings Subscription` | `SIDEBAR.SUBSCRIPTION` — "Subscription" | `i-lucide-wallet` | `subscription_settings_index` | — | `administrator`, **`agent`** | — | 868–873 |

**The two conditional entries are gated in `Sidebar.vue`, not by route meta:**

- #4 Agent Assignment — `hasAdvancedAssignment` (`Sidebar.vue:66–71`), i.e. the
  **`advanced_assignment`** flag — but the route it points at is flagged **`assignment_v2`**
  (`assignmentPolicy.routes.js:29`). Two different flags gate the same entry at two different layers.
- #16 Data — `hasDataImport` (`Sidebar.vue:90–95`), **`data_import`**, which *does* match the route's
  own flag (`data.routes.js:18`). The in-component check is therefore redundant with the `Policy` gate.

**Settings is the only group whose every leaf has an icon.** Reports (9), Campaigns (3), Portals (4),
Companies (1) and the two static Contacts leaves have none.

---

## 3. Gating: how an entry disappears

Three mechanisms, applied at three different places.

| Layer | Where | What it checks | Effect |
| --- | --- | --- | --- |
| `isAllowed(to)` filter | `provider.js:141–147`, applied in `SidebarGroup.vue:117–133`, `SidebarSubGroup.vue:55–59`, `SidebarCollapsedPopover.vue:42, 67–74` | `shouldShow(featureFlag, permissions, installationTypes)` resolved from the target route's `meta` | Leaf is dropped from `visibleChildren` / `accessibleItems`. A group whose every child is filtered out is not rendered at all (`SidebarGroup.vue:246`) |
| `<Policy>` wrapper | `SidebarGroup.vue:245–251`, `SidebarGroupLeaf.vue:32–41`, component at `app/javascript/dashboard/components/policy.vue` | `permissions` + `featureFlag` only — **`installationTypes` is never passed** | Second, narrower gate on the rendered element |
| In-component `computed` | `Sidebar.vue:66–95` | `accounts/isFeatureEnabledonAccount` for `advanced_assignment`, `conversation_unread_counts`, `unread_count_for_filters`, `data_import` | Removes Settings #4 / #16 from the array; switches badge counts on and off |

`shouldShow` itself (`usePolicy.js:64–105`) is permission-first: permissions and installation type are
hard gates; after that, cloud and enterprise deliberately *keep* premium-flagged features visible so the
page can render its own paywall. Premium list: `featureFlags.js:62–72` — `sla`, `captain_integration`,
`custom_tools`, `custom_roles`, `audit_logs`, `help_center`, `saml`,
`conversation_required_attributes`, `advanced_assignment`.

---

## 4. Active state

### 4.1 Resolution order

`SidebarGroup.vue:157–194`, `activeChild`, tries three strategies in order:

1. exact `route.path === resolvePath(child.to)` (159–161);
2. `child.activeOn.includes(route.name)`, then among those, rank by matching **every** `to.params` key
   against `route.params` (168–187) — this is what keeps the right contact segment / label highlighted;
3. fallback prefix match `route.path === childPath || route.path.startsWith(childPath + '/')` (189–193).

`navigableChildren` (42–44) flattens one level: `children.flatMap(c => c.children || c)`.
The group itself is active via `isActive` (144–152): exact path match on its own `to`, else
`activeOn.includes(route.name)`.

An explanatory comment at `SidebarGroup.vue:154–156` states the reason this exists at all:
*"our routes are not always nested correctly"*, with a `TODO: Audit the routes and fix the nesting and remove this`.

### 4.2 Styling, per surface

| Surface | Idle | Active | Source |
| --- | --- | --- | --- |
| Group header (expanded) | `text-n-slate-11 hover:bg-n-alpha-2` | self active: `text-n-slate-12 bg-n-alpha-2 font-medium`; has-active-child: `text-n-slate-12 font-medium` (no background) | `SidebarGroupHeader.vue:46–50` |
| Group header label | `text-body-main` | `font-medium text-sm` | `SidebarGroupHeader.vue:64–68` |
| Group trigger (collapsed) | `text-n-slate-11 hover:bg-n-alpha-2` | `text-n-slate-12 bg-n-alpha-2` for `isActive \|\| hasActiveChild` | `SidebarGroup.vue:265–268` |
| Leaf | `text-n-slate-11`; hover is a directional gradient `ltr:hover:bg-gradient-to-r rtl:hover:bg-gradient-to-l from-transparent via-n-slate-3/70 to-n-slate-3/70` | `text-n-slate-12 bg-n-alpha-2 active` | `SidebarGroupLeaf.vue:47–50` |
| Popover row | `text-n-slate-11 hover:bg-n-alpha-2` | `text-n-slate-12 bg-n-alpha-2` | `SidebarCollapsedPopover.vue:184–188, 223–226` |
| **Sidebar-wide override** | every `a`/`button` under `.sidebar-nav` gets a bespoke dark pill, a hover `translateX(3px)` (`-3px` under `[dir='rtl']`), and a 3px gradient rail via `::after` | `.router-link-active`, `.router-link-exact-active`, `a[aria-current='page']` get a blue→pink gradient fill and the rail at full opacity | `Sidebar.vue:1342–1432`, RTL at `1521–1524` |

The last row matters: the token-based classes above are **overridden** by hardcoded hex in the scoped
block, including `.text-n-slate-12 → rgb(255 119 224)` (`Sidebar.vue:1592–1594, 1605–1607`) and
`.text-n-slate-9/10/11 → rgba(255,255,255,.88)` (`1586–1590`). Anything reading the active style from
the Tailwind classes alone will read it wrong.

### 4.3 Expansion model

- **Accordion, one group at a time.** `expandedItem` is a single `ref` (`Sidebar.vue:123`), and
  `setExpandedItem` toggles (`125–127`), so opening one group closes the previous one.
- A group also stays open while it holds the active child: `v-show="isExpanded || hasActiveChild"`
  (`SidebarGroup.vue:302`), with `onMounted` + a `{ once: true }` watcher auto-expanding it
  (`218–240`).
- **A collapsed group with an active child still shows that one child**:
  `v-show="isExpanded || activeChild?.name === child.name"` (`SidebarGroup.vue:323`), mirrored for
  sub-group items in `shouldShowItem` (`SidebarSubGroup.vue:103–108`).
- Clicking a group header navigates to its first accessible child when the group is closed and holds
  no active child, then toggles (`SidebarGroup.vue:203–216`). Groups without a `to` of their own link to
  `accessibleItems[0].to` (`linkTo`, line 201).
- The header is a real `<a href>` so ⌘/Ctrl/Alt/Shift-click opens a new tab; a plain click is
  `preventDefault`-ed into the in-app toggle (`SidebarGroupHeader.vue:27–35`).

---

## 5. Badges and unread handling

| Concern | Detail | Source |
| --- | --- | --- |
| Shared pill | `inline-grid h-5 min-w-5 place-items-center rounded-full bg-n-slate-4 px-1 text-xxs font-medium leading-3 text-n-slate-12 dark:bg-n-slate-5 flex-shrink-0`, `data-test-id="sidebar-unread-badge"` | `SidebarUnreadBadge.vue:19–25` |
| Zero / non-finite | Coerced to 0 and rendered as `<span class="hidden" />` | `SidebarUnreadBadge.vue:8–11, 26` |
| Cap | `> 99` → `"99+"` | `SidebarUnreadBadge.vue:13–15`; same rule re-implemented for the group count at `SidebarGroupHeader.vue:23–25` |
| Group numeric count | Rendered only when `dynamicCount && !expandable` — so only the Inbox group can ever show one | `SidebarGroupHeader.vue:72–77` |
| Group dot badge | `size-2 bg-n-brand absolute rounded-full border border-n-solid-2`, driven by `getterKeys.badge` | `SidebarGroupHeader.vue:55–58` |
| Flags | `conversation_unread_counts` turns the whole feature on (`Sidebar.vue:73–78`); `unread_count_for_filters` additionally gates Mentions / Participating / Unattended / Folders (`80–88`, `290–296`) | |
| Store wiring | 8 getters off `conversationUnreadCounts/*` (`Sidebar.vue:229–252`); fetched or cleared by a watcher on `[accountId, hasConversationUnreadCounts]` (`97–106, 282–284`) | |
| Where badges appear | expanded leaves (`SidebarGroupLeaf.vue:62`), `ChannelLeaf` (`ChannelLeaf.vue:62`), popover rows (`SidebarCollapsedPopover.vue:211, 247`) | |
| Where they do **not** | the collapsed 40×40 group trigger has no badge or dot of any kind (`SidebarGroup.vue:260–272`) | |
| Decorative override | anything matching `[class*='badge']` or `[data-badge]` inside `.sidebar-nav` is restyled pink | `Sidebar.vue:1453–1459` |

---

## 6. Sub-groups, separators, sorting, collapsed mode, mobile

### 6.1 Sub-group behaviour (`SidebarSubGroup.vue`)

| Behaviour | Detail |
| --- | --- |
| Minimize persistence | `LocalStorage` JSON store under key `sidebarMinimizedSections` (`constants/localStorage.js:10`), per entry `"<accountId>:<Group:Child>"` (`SidebarSubGroup.vue:45–47`); default is **expanded** (`48–50`) |
| Cross-tab sync | `window` `storage` listener re-reads the store (`116–120`) |
| Auto-reveal | A minimized section re-opens when one of its children becomes active (`94–101`, watcher at `122–124`) |
| Scroll cap | `max-h-60 overflow-y-scroll no-scrollbar` once more than **7** accessible items (`65–71`, `155–157`) |
| Scroll affordance | Bottom gradient + `i-woot-chevrons-down`, hidden at scroll end (`169–178`); `scrollEnd` computed by exact equality `scrollHeight - scrollTop === clientHeight` (`111–114`) |
| Empty section | `v-if="hasAccessibleItems"` wraps everything — a section with no items renders an **empty `<li>`**: no header, no placeholder, no "create" affordance (`129`) |
| Tree lines | Trunk `CHILDREN_TRUNK` on the `<ul>` (`75–76`, `149`); per-leaf connector `TREE_CONNECTOR` in `SidebarGroupLeaf.vue:27–28`; separator vertical line + elbow in `SidebarGroupSeparator.vue:42–45`. Leaves inside sub-groups always pass `thin-tree-line` (`166`), which downgrades the 2px borders to 1px (`SidebarGroupLeaf.vue:39–40`) |

### 6.2 Separator row (`SidebarGroupSeparator.vue`)

- Renders as `<button aria-expanded>` when `collapsible`, else a `pointer-events-none` `<div>` (`50–68`).
  **All six sub-groups in the current tree set `collapsible: true`, so the non-collapsible branch is unreachable.**
- Right-hand controls (`79–102`): the sort menu, then a 24px chevron button
  (`i-lucide-chevron-up` / `i-lucide-chevron-down`) with `aria-expanded` and `aria-label="<label>"`.
- Padding compensates for those controls: `pe-14` / `pe-8` / `pe-10` (`63–65`).
- `aria-expanded` is set twice for the same state — once on the row, once on the chevron (`53`, `93`).

### 6.3 Sorting (`SidebarSortMenu.vue`, `helper/sidebarSort.js`)

| Item | Value |
| --- | --- |
| Sections | `folders`, `teams`, `channels`, `labels` (`sidebarSort.js:10–15`) |
| Options | `created_at_desc`, `created_at_asc`, `alphabetical_asc`, `alphabetical_desc`, `unread_count_desc`, `unread_count_asc` (`1–8`) — all six offered to all four sections (`17–50`) |
| Defaults | folders → `created_at_desc`; teams / channels / labels → `unread_count_desc` (`57–62`) |
| Unread-count options | Filtered out when the section has no unread counts; a stored unread sort then degrades to `alphabetical_asc` (`70–94`) |
| Persistence | Vuex `sidebarSortPreferences` module, initialised per `[accountId, currentUserId]` (`Sidebar.vue:108–111, 286–288`), written via `setSectionSort` (`308–313`) |
| Trigger visibility | `invisible opacity-0 pointer-events-none`, revealed by `group-hover/sidebar-section:*` — **hover-only, and forced visible while open** (`SidebarSortMenu.vue:171–173`). The group name is declared on the sub-group `<li>` (`SidebarSubGroup.vue:128`) |
| Opening | hover in the tree (`openOnHover` default `true`), click-only in the collapsed popover (`SidebarCollapsedPopover.vue:153`) |
| Rendering | Teleported `DropdownMenu`, 3 titled sections, `i-lucide-check` on the active option (`186–207`) |

### 6.4 Collapsed mode

| Aspect | Detail |
| --- | --- |
| Widths | `MIN_WIDTH 56`, `COLLAPSED_THRESHOLD 160`, `DEFAULT_WIDTH 200`, `MAX_WIDTH 320` (`provider.js:8–11`); `isCollapsed = sidebarWidth < 160` (`21`) |
| Persistence | `ui_settings.sidebar_width` via `useUISettings` (`provider.js:20, 28, 33`) |
| Effective state | `isEffectivelyCollapsed = !isMobile && isCollapsed` — **mobile is always expanded (flyout)** (`Sidebar.vue:143–145`) |
| Toggle | Chevron button in the header, `i-lucide-chevron-right` collapsed / `i-lucide-chevron-left` expanded, both `rtl:rotate-180`, titled `SIDEBAR.EXPAND_SIDEBAR` / `SIDEBAR.COLLAPSE_SIDEBAR`, `hidden md:flex` (`Sidebar.vue:927–935, 948–956`) |
| Resize handle | 6px strip on the inline-end edge, mouse **and** touch, double-click toggles; title `SIDEBAR.RESIZE_SIDEBAR` = "Drag to resize, double-click to collapse or expand"; RTL-aware delta (`Sidebar.vue:182–225, 1057–1068`); snaps to collapsed below the threshold (`210–214`) |
| Expanded width | Pinned to `MAX_WIDTH` (320) by `PREFERRED_EXPANDED_WIDTH` (`140`), applied on toggle (`148–155`), on any un-collapse (`158–163`), **and on mount** (`271–279`) |
| Collapsed layout | Header stacks vertically, `mt-3 mb-6 gap-4`; nav padding `px-1.5` vs `px-3`; items centered; group trigger is a 40×40 rounded square with icon only + `:title` (`Sidebar.vue:912, 1010, 1014, 260–272`) |
| Search | Full pill with `⌘K` hint when expanded; 36×36 icon button with `:title` when collapsed (`964–989`) |
| Compose | `ComposeConversation` trigger sized `!size-9` collapsed / `!h-9 !px-3` expanded (`991–1004`) |
| Changelog | Card when expanded, popover button when collapsed; both additionally require `isOnChatwootCloud && !isACustomBrandedInstance` (`1031–1044`) |
| Overflow | `.sidebar-shell` is `overflow: visible` so the popover can escape, switched to `hidden` by `.sidebar-expanded` (`Sidebar.vue:1626, 1646–1649`, class bound at `899`) |

**Collapsed popover** (`SidebarCollapsedPopover.vue`): teleported via `TeleportWithDirection`,
`fixed z-[100]`, positioned at `sidebarWidth + 8` on the inline-start side and flipped for RTL
(`112–116`); clamped into the viewport with a 20px margin and a 300px height assumption (`91–101`);
uppercase group label header (`123–127`); `max-h-[400px]` scroll body (`128–130`); auto-expands the
sub-group containing the active child (`79–89`); first paint skips the transition (`26, 54–65, 103–104`).
Open/close is a single shared `activePopover` ref so only one can be open (`provider.js:14, 55–83`),
with hover-intent delays of 200ms leaving the trigger and 100ms leaving the popover
(`SidebarGroup.vue:87–99`), cancelled while the sort dropdown is open (`101–104`), and force-closed on
`window` blur / `document` mouseleave (`107–109, 223–229`).

### 6.5 Mobile

| Aspect | Detail |
| --- | --- |
| Breakpoint | `isMobile = windowWidth < 768`, hardcoded in `Sidebar.vue:57–58`; `Dashboard.vue:68–70` uses `wootConstants.SMALL_SCREEN_BREAKPOINT` (also 768) |
| Panel | `fixed top-0 ltr:left-0 rtl:right-0 h-full z-40 w-[332px] max-w-[92vw]`, becomes `md:relative md:w-auto md:flex-shrink-0` (`Sidebar.vue:892`) |
| Open / closed | `ltr:-translate-x-full rtl:translate-x-full` when closed; `shadow-2xl md:shadow-none` when open; `transition-transform duration-300 ease-out md:transition-[width]` suppressed while resizing (`893–901`) |
| Inline width | `:style` width is applied only when **not** mobile (`902`) |
| Launcher | `MobileSidebarLauncher` — `i-lucide-menu` in a `ButtonGroup` pill, `fixed bottom-4 ltr:left-4 rtl:right-4 z-40 block md:hidden`, shifted `ltr:translate-x-48 rtl:-translate-x-48` while open (`MobileSidebarLauncher.vue:38–59`) |
| Launcher suppression | Hidden entirely on 9 conversation routes: `inbox_conversation`, `conversation_through_inbox`, `conversations_through_label`, `team_conversations_through_label`, `conversations_through_folders`, `conversation_through_mentions`, `conversation_through_unattended`, `conversation_through_participating`, `inbox_view_conversation` (`MobileSidebarLauncher.vue:18–31`) |
| Rendered twice | Once inside `UpgradePage`, once in the normal branch (`Dashboard.vue:150–153, 158–161`) |
| Dismissal | `v-on-click-outside` on the `<aside>`, ignoring `#mobile-sidebar-launcher`, `[data-popover-content]`, `[data-popover-backdrop]` (`Sidebar.vue:882–891`), guarded by `if (!props.isMobileSidebarOpen) return` (`353–356`) |
| Collapse controls | Both the collapse chevron (`v-if="!isMobile"`) and the resize handle (`hidden md:block`) are unavailable on mobile (`928, 949, 1058`) |

---

## 7. Keyboard, a11y and i18n surface

**Global shortcuts** (`useSidebarKeyboardShortcuts.js:17–36`), registered from `Sidebar.vue:121`:

| Chord | Action |
| --- | --- |
| `⌘/Ctrl + /` | open the keyboard-shortcut modal (emits `openKeyShortcutModal`) |
| `⌘/Ctrl + Esc` | close it |
| `Alt + C` | `home` |
| `Alt + V` | `contacts_dashboard` |
| `Alt + R` | `account_overview_reports` |
| `Alt + S` | `agent_list` |

Plus `⌘/Ctrl + K` surfaced as the search hint via `useKbd` (`Sidebar.vue:49, 976–979`); the search pill
itself routes to `{ name: 'search' }` (`966`).
`Alt+V` targets **`contacts_dashboard`**, a name that does not appear anywhere in the sidebar tree
(the sidebar uses `contacts_dashboard_index`).

**Accessibility inventory, as-is:**

- `<aside>` has no `role`, `aria-label` or `aria-hidden`; `<nav>` has no `aria-label`
  (`Sidebar.vue:881–892, 1008–1011`).
- When closed on mobile the panel is only translated off-screen — its links stay in the tab order.
- Group headers carry `role="button"` on an `<a href>` and **no `aria-expanded`**
  (`SidebarGroupHeader.vue:39–51`); the expand chevron is a `<span>` with a click handler (`79–84`).
  Sub-group separators do expose `aria-expanded` (`SidebarGroupSeparator.vue:53, 93`).
- The collapsed popover opens on **hover only** (`SidebarGroup.vue:81–85`); there is no keyboard path
  to it, and the trigger has no `aria-haspopup` / `aria-expanded`.
- The sort trigger is hover-revealed with `pointer-events-none` until hover
  (`SidebarSortMenu.vue:171–173`), so it is not reachable by keyboard either.
- Icon-only controls rely on `:title`, not `aria-label`: collapse toggle (`Sidebar.vue:931, 952`),
  collapsed search (`986`), collapsed group trigger (`SidebarGroup.vue:269`), resize handle (`1059`).
- Account switcher is the a11y high-water mark: `aria-haspopup="listbox"`, `aria-controls`, `aria-live`
  (`SidebarAccountSwitcher.vue:71–85`) — though `aria-controls="account-options"` points at an id that
  is not rendered.
- `prefers-reduced-motion` is honoured: the shimmer and aurora animations stop and transitions drop to
  0.01ms (`Sidebar.vue:1544–1559`).

**i18n:** every sidebar string goes through `t(...)` / `$t(...)`; no bare label literals in the tree.
Backing file `app/javascript/dashboard/i18n/locale/en/settings.json`, namespaces `SIDEBAR` and
`SIDEBAR_ITEMS`.

### 7.1 Orphaned i18n keys = features once in this nav

These `SIDEBAR.*` keys exist in `en/settings.json` and are referenced by **no** component
(verified by grepping all of `app/javascript` excluding `i18n/`):

`INBOX_VIEW`, `CAPTAIN`, `CAPTAIN_AI`, `CAPTAIN_ASSISTANTS`, `CAPTAIN_OVERVIEW`, `CAPTAIN_DOCUMENTS`,
`CAPTAIN_RESPONSES`, `CAPTAIN_TOOLS`, `CAPTAIN_SCENARIOS`, `CAPTAIN_PLAYGROUND`, `CAPTAIN_INBOXES`,
`CAPTAIN_SETTINGS`, `CALLS`, `SLA`, `CUSTOM_ROLES`, `SECURITY`, `HOME`, `NOTIFICATIONS`,
`APPLICATIONS`, `BETA`, `SORT_BY`, `NEW_LABEL`, `NEW_TEAM`, `NEW_INBOX`, `CURRENTLY_VIEWING_ACCOUNT`,
`SWITCH`, `SET_AVAILABILITY_TITLE`, `PROFILE_SETTINGS`, `ONGOING`, `ONE_OFF`.

### 7.2 Existing features with no sidebar entry

| Feature | Route | Reachable from |
| --- | --- | --- |
| Captain | `captain_assistants_index` (`captain/captain.routes.js:172`) | command bar only (`useGoToCommandHotKeys.js:65`) |
| SLA settings | `sla_list` (`settings/sla/sla.routes.js:31`) | command bar only (`useGoToCommandHotKeys.js:229`) |
| Custom Roles | `custom_roles_list` (`settings/customRoles/customRole.routes.js:20`) | **nothing** — URL only |
| Security settings | `security_settings_index` (`settings/security/security.routes.js:27`) | **nothing** — URL only |
| Calls dashboard | `calls_dashboard_index` (`calls/routes.js:12`) | **nothing** — URL only |
| Profile settings | `profile_settings_index` | profile menu (`SidebarProfileMenu.vue:76`) + command bar |

The command bar (`app/javascript/dashboard/composables/commands/useGoToCommandHotKeys.js`) carries
**33** `routeName` destinations against the sidebar's 41–43 static leaves; the two lists overlap but
neither contains the other.

---

## 8. Header, footer and surrounding chrome

| Region | Contents | Source |
| --- | --- | --- |
| Header | `Logo` (`size-5` in a `size-10` tile), `SidebarAccountSwitcher`, collapse toggle; collapsed variant stacks logo-trigger + toggle | `Sidebar.vue:910–958` |
| Actions row | Search pill / icon button, then `ComposeConversation` with `align="start"` | `Sidebar.vue:960–1005` |
| Nav | `overflow-y-scroll no-scrollbar`, `gap-2 pb-5`, top/bottom fade via CSS `mask-image` | `Sidebar.vue:1008–1022, 1332–1340` |
| Footer | Top fade overlay, changelog card or button, `SidebarProfileMenu` | `Sidebar.vue:1024–1055` |
| Account switcher | Dropdown only when `userAccounts.length > 1 && currentAccount.name`; accounts sorted by name; shows role or custom-role name; `i-lucide-check` on current; "New account" button behind `globalConfig.createNewAccountFromDashboard` | `SidebarAccountSwitcher.vue:33–41, 96–150` |
| Profile menu | 8 items — Contact support (flag `contact_chatwoot_support_team` + `chatwootInboxToken`), Keyboard shortcuts, Profile settings, Change appearance (opens `ninja-keys` at `appearance_settings`), Read docs, Changelog, SuperAdmin console (`type === 'SuperAdmin'`), Log out. Each declares `showOnCustomBrandedInstance`, enforced by `CustomBrandPolicyWrapper` | `SidebarProfileMenu.vue:53–127, 166–172` |
| Availability | 3 statuses (Online / Busy / Offline) with colour swatches + auto-offline `ToggleSwitch`; blocked while impersonating | `SidebarProfileMenuStatus.vue:28–75, 78–129` |
| Emits | `closeKeyShortcutModal`, `openKeyShortcutModal`, `showCreateAccountModal`, `closeMobileSidebar` | `Sidebar.vue:39–44` |
| Data bootstrapped on mount | `labels/get`, `inboxes/get`, `notifications/unReadCount`, `teams/get`, `attributes/get`, `customViews/get('conversation')`, `customViews/get('contact')` | `Sidebar.vue:262–269` |

---

## 9. Concrete inconsistencies found

Ordered roughly by consequence. Every item is a literal observation with a citation.

1. **1650-line component with 578 lines of hand-written scoped CSS.** `Sidebar.vue:1072–1650` is a
   bespoke dark theme in raw hex (`--sb-bg: #071225`, `--sb-blue: #2f6fe4`, `--sb-pink: #db2777`, …),
   contradicting the project rule "no custom CSS, no scoped CSS, no inline styles, Tailwind only".
   It also **overrides design tokens from outside**: `.sidebar-nav :deep(.text-n-slate-12) → rgb(255 119 224)`
   (`1592–1594`, repeated at `1605–1607`), `.text-n-slate-9/10/11 → rgba(255,255,255,.88)` (`1586–1590`),
   `.sidebar-profile :deep(... .text-n-slate-12) → rgb(255 119 224)` (`1495–1497`).
2. **`.sidebar-shell` is declared twice**, at `1073–1103` and again at `1614–1644`, with the same eight
   custom properties and the same background, differing only in `overflow: hidden` vs
   `overflow: visible`. The second block wins for every shared property.
3. **Global font-size override.** `.sidebar-shell.text-sm { font-size: 1.1rem !important }` and
   `.sidebar-shell :deep(.text-sm) { font-size: 1.1rem !important }` (`1562–1568`) re-point every
   `text-sm` inside the sidebar, so the typography scale does not apply here.
   `.sidebar-logo` is likewise forced to `3.5rem` with `background: #ffffff9c !important` (`1570–1575`),
   overriding the `size-10` / `size-5` classes in the template (`940–942`).
4. **A user's chosen sidebar width is discarded on every mount.** `provider.js` persists any width
   between 160 and 320, but `Sidebar.vue:271–279` resets it to `MAX_WIDTH` on mount whenever it differs,
   and `158–163` does the same on every un-collapse. The resize handle, its tooltip and the stored
   `ui_settings.sidebar_width` therefore only ever express two states in practice.
5. **`snapToExpanded` and `DEFAULT_WIDTH` are dead exports.** Declared at `provider.js:36–39, 51` and
   consumed nowhere (`Sidebar.vue:129–137` destructures neither).
6. **Settings #4 is gated by two different feature flags at two layers.** `Sidebar.vue:66–71` requires
   `advanced_assignment`; the route it links to requires `assignment_v2`
   (`assignmentPolicy.routes.js:29`). Enabling one without the other yields either a hidden-but-reachable
   page or a visible-but-blocked entry.
7. **Settings #16's in-component flag check is redundant.** `hasDataImport` (`Sidebar.vue:90–95`) tests
   `data_import`, which is exactly the flag the `Policy` gate would already read from
   `data.routes.js:18`.
8. **`installationTypes` is resolved but never enforced by `<Policy>`.** `provider.js:129–139` computes
   it and `isAllowed` uses it, but neither `SidebarGroup.vue:245–251` nor `SidebarGroupLeaf.vue:32–41`
   passes it to `Policy`, whose own prop exists and defaults to `null`
   (`components/policy.vue:18–21, 27`). Companies and Audit Logs are the two entries this affects.
9. **Sub-group `activeOn` arrays are never read.** `navigableChildren` flattens a sub-group into its
   children (`SidebarGroup.vue:42–44`), so the sub-group object itself never reaches the `activeOn`
   comparison at line 168. That makes `activeOn` on Folders (`447`), Teams (`462`), Channels (`484`)
   and Labels (`507`) inert config.
10. **`getterKeys.badge` is dead everywhere.** `SidebarGroupHeader.vue:21` calls
    `useMapGetter(props.getterKeys.badge)`; no item in `menuItems` sets `badge` (only Inbox sets
    `count`, `Sidebar.vue:394–396`), so `store.getters[undefined]` is always `undefined` and the dot at
    lines 55–58 can never render.
11. **The `99+` cap is implemented twice**, independently: `SidebarUnreadBadge.vue:13–15` and
    `SidebarGroupHeader.vue:23–25`, with different pill markup duplicated verbatim
    (`SidebarUnreadBadge.vue:22` vs `SidebarGroupHeader.vue:74`).
12. **A collapsed group shows no unread signal.** `SidebarGroup.vue:260–272` renders icon + `:title`
    only, so with the sidebar collapsed the user cannot see that Conversations has unread items without
    hovering to open the popover.
13. **A collapsed group gives no hint it is expandable.** The chevron is
    `v-if="expandable" v-show="isExpanded"` (`SidebarGroupHeader.vue:79–84`) — present only once already
    open. There is no collapsed-state `chevron-down`, unlike sub-group separators, which show both
    directions (`SidebarGroupSeparator.vue:97–100`).
14. **Icon coverage is split by group.** Only Conversation's children and all of Settings carry icons.
    Reports (9 leaves, `617–642`), Campaigns (3, `650–664`), Portals (4, `672–711`), Companies (1, `600`)
    and the two static Contacts leaves (`531–546`) have none, so those lists read as plain text while
    the rest of the tree is iconographic.
15. **Duplicate and near-duplicate icons.** `i-lucide-briefcase` is used for both Account Settings
    (`722`) and Audit Logs (`853`); `i-lucide-workflow` for both Flow Builder (`837`) and Conversation
    Workflow (`859`). Labels are `i-lucide-tag` in Conversation (`506`) and Contacts (`571`) but
    `i-lucide-tags` in Settings (`789`).
16. **Settings naming breaks its own convention once.** Nineteen of twenty entries are named
    `Settings <Thing>`; `Conversation Workflow` (`857`) has no prefix. Since `name` is the accordion and
    popover identity key, the convention is load-bearing, not cosmetic.
17. **Parallel sub-groups are not equipped alike.** Folders / Teams / Channels / Labels get
    `buildSortConfig` and unread badges; Segments (`547–568`) and Tagged With (`569–592`) get neither —
    no sort menu, no badge — even though all six are `collapsible: true, showTreeLine: true` sub-groups
    rendered by the same component.
18. **Empty sub-groups vanish silently.** `SidebarSubGroup.vue:129` wraps the whole body in
    `v-if="hasAccessibleItems"`, so an account with no teams simply has no Teams section: no header, no
    placeholder, no "create" link. Meanwhile `SidebarGroupEmptyLeaf` ("No items") only renders for a
    group whose `children` is an empty array (`SidebarGroup.vue:329–331`), a shape no entry in
    `menuItems` has — so the one empty state that exists is unreachable, and the
    `SIDEBAR.NEW_TEAM` / `NEW_INBOX` / `NEW_LABEL` strings sit unused (§7.1).
19. **Mobile: navigating does not close the panel.** The only dismissal path is `v-on-click-outside`
    (`Sidebar.vue:882–891`); there is no route watcher and leaf links are *inside* the `<aside>`, so
    tapping a destination leaves the flyout covering it. `Sidebar.vue` imports no `useRoute` and
    `Dashboard.vue:108–110` only exposes `closeMobileSidebar` to that one handler.
20. **Mobile: no scrim and no focus containment.** Nothing renders a backdrop (`Dashboard.vue:131–177`),
    the panel is only translated off-screen when closed (`896`), and no `inert` / `aria-hidden` /
    focus trap is applied, so a closed sidebar's ~43 links remain tabbable.
21. **The 768 breakpoint is duplicated as a literal.** `Sidebar.vue:57–58` hardcodes `768` while
    `Dashboard.vue:68–70` reads `wootConstants.SMALL_SCREEN_BREAKPOINT`
    (`constants/globals.js:48`), for the same boundary.
22. **Keyboard reach is incomplete for two interactive surfaces.** The collapsed popover is hover-only
    (`SidebarGroup.vue:81–85`) and the sort trigger is `pointer-events-none` until hover
    (`SidebarSortMenu.vue:171–173`). On a collapsed sidebar, keyboard and touch users cannot reach any
    child item, and nobody can reach sorting without a pointer.
23. **`Alt+V` points at a route name absent from the tree.**
    `useSidebarKeyboardShortcuts.js:27–29` pushes `contacts_dashboard`; the sidebar uses
    `contacts_dashboard_index` (`Sidebar.vue:535`).
24. **`aria-controls` dangles.** `SidebarAccountSwitcher.vue:72` declares
    `aria-controls="account-options"`; no element with that id is rendered in the file.
25. **RTL hover offset is expressed as a plain descendant selector.** `Sidebar.vue:1520–1524` carries an
    in-code comment explaining that `:global()` compiles away, so the rule had to be written as
    `[dir='rtl'] .sidebar-nav :deep(a:hover)` — a documented workaround for the scoped-CSS approach.
26. **`activeOn` coverage is uneven in ways that match no rule.** Settings Teams lists 8 names and
    Inboxes 6, while Flow Builder, Commerce and Audit Logs list none and depend on the path-prefix
    fallback; `label_reports_index` omits `label_reports_show` though its three siblings include theirs
    (`365–381`); Portals ▸ Categories omits `portals_categories_articles_new` while including `_edit`
    (`687–691`).
27. **The non-collapsible separator branch is unreachable.** `SidebarGroupSeparator.vue:50–68` renders a
    `pointer-events-none` `<div>` when `collapsible` is false, but all six sub-groups in `menuItems` set
    `collapsible: true`.
28. **`reportRoutes` is an empty indirection.** `Sidebar.vue:384` wraps `newReportRoutes()` in a computed
    that transforms nothing; the factory is called from exactly one place (`627`).
29. **`scrollEnd` uses exact equality.** `SidebarSubGroup.vue:112–113` compares
    `scrollHeight - scrollTop === clientHeight`; fractional scroll offsets (zoom, HiDPI) can leave the
    "more below" chevron showing at the bottom of the list.

---

## 10. What a modernization should reuse rather than rebuild

- **`menuItems` as the single declarative tree.** `Sidebar.vue:386–877` already expresses every entry as
  data — `name`, `label`, `icon`, `to`, `activeOn`, `children`, `collapsible`, `showTreeLine`,
  `badgeCount`, `component`, plus the sort triple. A new presentation layer should consume this shape
  (ideally lifted out of the `.vue` file) rather than re-authoring 41–43 destinations.
- **The gating stack.** `provider.js:94–147` (`resolvePath`, `resolvePermissions`,
  `resolveFeatureFlag`, `resolveInstallationType`, `isAllowed`) + `components/policy.vue` +
  `usePolicy.js` already derive visibility from route `meta`, including the `navigationPath` indirection
  the four Help Center entries depend on. Keep this; closing gap #8 means passing `installationTypes`
  through, not replacing the mechanism.
- **The three-strategy active-state resolver.** `SidebarGroup.vue:157–194` with its param-ranking pass
  is what keeps the correct contact segment, label and report sub-page highlighted given routes that
  are, per the in-code comment, "not always nested correctly". Replacing it with plain
  `router-link-active` will silently break the Segments and Tagged-with cases.
- **`SidebarUnreadBadge`** (`SidebarUnreadBadge.vue`) as the one badge primitive, including its
  normalization, `99+` cap and `data-test-id`. Fold the duplicate in `SidebarGroupHeader.vue:23–25, 74`
  into it instead of adding a third.
- **`ChannelLeaf` and the `component` leaf escape hatch.** `SidebarGroupLeaf.vue:21–23, 52–56` and
  `SidebarCollapsedPopover.vue:50–52, 191–200` already let a leaf render arbitrary content; `ChannelLeaf`
  uses it for the `name · identifier` split and the reauthorize warning. Keep the contract
  `{ label, icon, active, badgeCount }` so `ChannelLeaf` survives unchanged.
- **The sort subsystem.** `helper/sidebarSort.js` (sections, option sets, defaults, unread-count
  degradation, tie-breaking) plus the `sidebarSortPreferences` Vuex module and `SidebarSortMenu` are
  self-contained and feature-complete. Reuse `buildSortConfig` (`Sidebar.vue:315–319`) and extend it to
  Segments and Tagged With (gap #17) rather than writing new sorting.
- **The minimize-state store.** `SidebarSubGroup.vue:33–50, 82–101, 116–124` — `sidebarMinimizedSections`
  keyed `"<accountId>:<Group:Child>"`, defaulting to expanded, auto-revealing on active child, synced
  across tabs. Three of the existing specs assert exactly this behaviour
  (`specs/SidebarSubGroup.spec.js:132–165`); preserve the key format or those preferences reset for
  every user.
- **`useSidebarResize` + `ui_settings.sidebar_width`** as the persistence channel for the collapsed /
  expanded decision (`provider.js:17–53`). The width clamp and `COLLAPSED_THRESHOLD` derivation are
  sound; what needs removing is the mount-time reset in `Sidebar.vue:271–279`, not the composable.
- **`usePopoverState`'s single-open invariant and hover-intent timings** (`provider.js:13–15, 55–83`,
  driven from `SidebarGroup.vue:81–109`), and the popover's viewport clamping and RTL flip
  (`SidebarCollapsedPopover.vue:91–101, 112–116`). These are the non-obvious parts of collapsed mode.
- **`useSidebarKeyboardShortcuts`** (6 bindings) and the `⌘K` search affordance. Any new shell must keep
  all six chords; fixing #23 is a one-token change.
- **`TeleportWithDirection`** as the RTL-aware teleport target, already used by both the popover and the
  sort menu.
- **The tree-connector class constants** — `TREE_CONNECTOR` (`SidebarGroupLeaf.vue:27–28`),
  `CHILDREN_TRUNK` (`SidebarSubGroup.vue:75–76`), `TREE_VERTICAL_LINE` / `TREE_ELBOW`
  (`SidebarGroupSeparator.vue:42–45`). They are written with logical properties (`start`, `border-s`,
  `rounded-es`) and are already RTL-correct, and four specs pin their behaviour
  (`specs/SidebarSubGroup.spec.js:99–131`).
- **The existing `prefers-reduced-motion` block** (`Sidebar.vue:1544–1559`) as the list of what must stay
  suppressible if the decorative layer is reworked.
- **The `SIDEBAR` / `SIDEBAR_ITEMS` i18n namespaces.** Every label already resolves through `t()`; reuse
  the keys. The orphan list in §7.1 is the inventory of what to retire or re-adopt deliberately — not
  silently.

### Pre-existing discoverability debt to carry into the baseline

Per the contract's "materially harder to discover counts as a regression" clause, these are **already**
below the bar today and should be recorded as the starting point, not introduced or deepened:
Custom Roles, Security settings and the Calls dashboard have **no** entry point anywhere in the UI
(§7.2); Captain and SLA settings exist only in the command bar; unread counts are invisible in
collapsed mode (#12); empty sub-groups disappear without a trace or a create affordance (#18); and the
sort control plus the entire collapsed child list are pointer-only (#22).
